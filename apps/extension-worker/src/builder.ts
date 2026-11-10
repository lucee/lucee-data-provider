// Builds the extension index, the part of ExtensionMetadataReader.cfc's loadMeta() a Worker can do:
// - the extension meta is the extensions.json the CFML provider keeps in the extension bucket (read over http)
// - the Maven sources (the Maven layout of the core bucket and the Maven repositories) are listed, and every
//   file of the meta gets its Maven location (LDEV-6789/6795)
// - files of the Maven sources that the meta does not have yet are read (manifest, logo, packaging) and
//   added, a few per build (EXTENSIONS_DISCOVERY_MAX), like _addMavenCandidates()
import type { Config } from "./config";
import { httpGet } from "./http";
import { manifestValue, readLex } from "./lex";
import { listBucketMavenFiles, MavenExtensionSource, type MavenFile, type MavenListing } from "./maven";
import type { CfQuery, ExtensionIndex, Location, Logos, MavenState, Row } from "./types";
import { compare, sortableVersionString } from "./versions";

export const EMPTY_COLUMNS = [
	"id", "version", "versionSortable", "name", "description", "filename", "image", "category", "author", "created",
	"releaseType", "minLoaderVersion", "minCoreVersion", "price", "currency", "disableFull", "trial", "older", "olderName",
	"olderDate", "promotionLevel", "promotionText", "projectUrl", "sourceUrl", "documentionUrl", "packaging"
];

/** what a build reads from and writes to besides the network (KV, or memory without KV) */
export interface BuildState {
	mavenState: MavenState;
	/** rows added by the discovery, with their logos */
	discovered: Row[];
	/** file name > packaging, read for rows of the meta without one */
	packaging: Record<string, string>;
}

export interface BuildResult {
	index: ExtensionIndex;
	logos: Logos;
	state: BuildState;
	stateChanged: boolean;
}

interface Candidate extends MavenFile {
	source: "bucket" | "repo";
}

function str(value: unknown): string {
	return value === null || value === undefined ? "" : String(value);
}

export function emptyState(): BuildState {
	return { mavenState: { skipped: {}, artifactIds: {} }, discovered: [], packaging: {} };
}

/** _mavenCandidates(): the files of the Maven sources by file name, the ones of the core bucket first */
export function mavenCandidates(bucketFiles: MavenFile[], remoteFiles: MavenFile[]): Map<string, Candidate> {
	const candidates = new Map<string, Candidate>();
	for (const file of bucketFiles) candidates.set(file.name, { ...file, source: "bucket" });
	for (const file of remoteFiles) if (!candidates.has(file.name)) candidates.set(file.name, { ...file, source: "repo" });
	return candidates;
}

/**
 * _setMavenLocations(): a file of the meta with the name of a Maven file, and a file with another name (the
 * flat bucket has the older ones under their old names) of an id and version the Maven sources have. When
 * part of a source could not be listed, what is known of that source already is kept.
 */
export function mavenLocations(
	candidates: Map<string, Candidate>,
	bucketComplete: boolean,
	remoteComplete: boolean,
	rows: Row[],
	artifactIds: Record<string, string>,
	previous: Record<string, Location> = {}
): Record<string, Location> {
	const locations: Record<string, Location> = {};
	for (const [name, location] of Object.entries(previous)) {
		if ((location.source === "bucket" && !bucketComplete) || (location.source === "repo" && !remoteComplete)) locations[name] = location;
	}

	const byKey = new Map<string, Candidate>();
	for (const candidate of candidates.values()) {
		const id = artifactIds[candidate.artifact] ?? "";
		const key = `${id}|${candidate.version}`;
		if (id.length && !byKey.has(key)) byKey.set(key, candidate);
	}

	for (const row of rows) {
		const fileName = str(row.filename);
		const found = candidates.get(fileName) ?? byKey.get(`${str(row.id)}|${str(row.version)}`);
		if (!found) continue;
		locations[fileName] =
			found.source === "bucket"
				? { source: "bucket", path: found.path ?? "" }
				: { source: "repo", artifact: found.artifact, version: found.version, repos: found.repos ?? [] };
	}
	return locations;
}

/** the url to read a candidate from */
async function candidateUrl(config: Config, source: MavenExtensionSource, candidate: { source: string; path?: string; artifact: string; version: string; repos?: string[] }): Promise<string> {
	if (candidate.source === "bucket") return config.mavenCdnUrl + (candidate.path ?? "");
	return source.getFileUrl(candidate.artifact, candidate.version, candidate.repos ?? []);
}

/** _initExtensionMetaFromManifest() and _storeLexFile(): a row of the meta for an extension file */
export function rowFromLex(columns: string[], fileName: string, manifest: Record<string, string>, logo: string, packaging: string): Row {
	const meta: Row = {};
	for (const col of columns) meta[col] = manifestValue(manifest, col);
	const commonMappings: Record<string, string> = {
		created: "Built-Date",
		minCoreVersion: "lucee-core-version",
		minLoaderVersion: "lucee-loader-version",
		releaseType: "release-type"
	};
	for (const [col, key] of Object.entries(commonMappings)) {
		if (!str(meta[col]).length && manifestValue(manifest, key).length) meta[col] = manifestValue(manifest, key);
	}
	if (columns.includes("packaging")) meta.packaging = packaging;
	meta.image = logo;
	meta.filename = fileName;
	meta.versionSortable = str(meta.version).length ? sortableVersionString(str(meta.version)) : "";
	meta.trial = false;
	meta.releaseType = str(meta.releaseType).length ? meta.releaseType : "all";
	return meta;
}

function rowsFromQuery(query: CfQuery): { columns: string[]; rows: Row[] } {
	if (!query || !Array.isArray(query.COLUMNS) || !Array.isArray(query.DATA)) throw new Error("the extension meta is not a serialized query");
	const columns = [...query.COLUMNS];
	const rows = query.DATA.map((data) => {
		const row: Row = {};
		columns.forEach((col, i) => (row[col] = data[i] ?? ""));
		return row;
	});
	// the extension meta of a state file written before the packaging was recorded has no such column
	if (!columns.some((c) => c.toLowerCase() === "packaging")) {
		columns.push("packaging");
		for (const row of rows) row.packaging = "";
	}
	return { columns, rows };
}

/** LDEV-5699, LDEV-6089: versionSortable recomputed, sorted by id asc, versionSortable desc (QuerySort is stable) */
export function sortMeta(rows: Row[]): Row[] {
	for (const row of rows) if (str(row.version).length) row.versionSortable = sortableVersionString(str(row.version));
	return rows
		.map((row, i) => ({ row, i }))
		.sort((a, b) => compare(str(a.row.id), str(b.row.id)) || compare(str(b.row.versionSortable), str(a.row.versionSortable)) || a.i - b.i)
		.map((x) => x.row);
}

async function readMavenStateFile(config: Config): Promise<MavenState> {
	const res = await httpGet(config.mavenStateUrl, { timeoutMs: config.timeoutMs, cacheSeconds: config.metadataCacheSeconds });
	if (res.status !== 200) return { skipped: {}, artifactIds: {} };
	try {
		const json = JSON.parse(res.content) as Record<string, unknown>;
		const pick = (name: string) => {
			const key = Object.keys(json).find((k) => k.toLowerCase() === name.toLowerCase());
			return (key ? json[key] : {}) as Record<string, never>;
		};
		return { skipped: { ...pick("skipped") }, artifactIds: { ...pick("artifactIds") } };
	} catch {
		return { skipped: {}, artifactIds: {} };
	}
}

export async function buildIndex(config: Config, previousState: BuildState, previous?: ExtensionIndex): Promise<BuildResult> {
	const metaRes = await httpGet(config.metaUrl, { timeoutMs: Math.max(config.timeoutMs, 60_000), cacheSeconds: config.metadataCacheSeconds });
	if (metaRes.status !== 200) throw new Error(`the extension meta [${config.metaUrl}] could not be read: ${metaRes.status} ${metaRes.error}`);
	const { columns, rows: metaRows } = rowsFromQuery(JSON.parse(metaRes.content) as CfQuery);
	const fromMeta = metaRows.length;

	// what the CFML provider knows, and on top what the discovery learned
	const fileState = await readMavenStateFile(config);
	const state: BuildState = {
		mavenState: {
			skipped: { ...fileState.skipped, ...previousState.mavenState.skipped },
			artifactIds: { ...fileState.artifactIds, ...previousState.mavenState.artifactIds }
		},
		discovered: [],
		packaging: { ...previousState.packaging }
	};
	let stateChanged = false;

	const rows: Row[] = [...metaRows];
	const knownFiles = new Set(rows.map((r) => str(r.filename)));
	const knownVersions = new Set(rows.map((r) => `${str(r.id)}|${str(r.version)}`));

	// discovered rows the extension meta has meanwhile (the CFML provider added them) are dropped
	for (const row of previousState.discovered) {
		const key = `${str(row.id)}|${str(row.version)}`;
		if (knownFiles.has(str(row.filename)) || knownVersions.has(key)) {
			stateChanged = true;
			continue;
		}
		state.discovered.push(row);
		rows.push({ ...row });
		knownFiles.add(str(row.filename));
		knownVersions.add(key);
	}

	const source = new MavenExtensionSource(config);
	const [bucket, remote] = await Promise.all([
		listBucketMavenFiles(config),
		source.listExtensions().catch((e: Error): MavenListing => {
			console.log(`Error listing the maven repositories: ${e.message}`);
			return { files: [], complete: false };
		})
	]);
	const candidates = mavenCandidates(bucket.files, remote.files);

	// the discovery: files of the Maven sources the meta doesn't have yet (LDEV-6789)
	let discoveryRead = 0;
	let discoveryErrors = 0;
	const skip = (name: string) => {
		console.log(`Extension file [${name}] has the same id and version as a known extension, ignoring it.`);
		state.mavenState.skipped[name] = true;
		stateChanged = true;
	};
	const skipKnownVersions = (list: Candidate[]) =>
		list.filter((c) => {
			const id = state.mavenState.artifactIds[c.artifact] ?? "";
			if (id.length && knownVersions.has(`${id}|${c.version}`)) {
				skip(c.name);
				return false;
			}
			return true;
		});

	if (config.discoveryMax > 0) {
		let pending = [...candidates.values()].filter((c) => !knownFiles.has(c.name) && !state.mavenState.skipped[c.name]);
		pending = skipKnownVersions(pending);
		// the newest version first, the first of every artifact we don't know the id of yet goes first
		pending.sort((a, b) => compare(sortableVersionString(b.version), sortableVersionString(a.version)));
		const first: Candidate[] = [];
		const rest: Candidate[] = [];
		const seen = new Set<string>();
		for (const c of pending) {
			if (state.mavenState.artifactIds[c.artifact] !== undefined || seen.has(c.artifact)) rest.push(c);
			else {
				seen.add(c.artifact);
				first.push(c);
			}
		}

		const process = async (list: Candidate[]) => {
			for (const candidate of list) {
				if (discoveryRead >= config.discoveryMax) return;
				discoveryRead++;
				try {
					const url = await candidateUrl(config, source, candidate);
					if (!url.length) throw new Error("no download url");
					const lex = await readLex(url);
					const row = rowFromLex(columns, candidate.name, lex.manifest, lex.logo, lex.packaging);
					const id = str(row.id);
					if (id.length && state.mavenState.artifactIds[candidate.artifact] !== id) {
						state.mavenState.artifactIds[candidate.artifact] = id;
						stateChanged = true;
					}
					const key = `${id}|${str(row.version)}`;
					if (knownVersions.has(key)) {
						skip(candidate.name);
						continue;
					}
					console.log(`Discovered extension file [${candidate.name}] (${id} ${str(row.version)}).`);
					knownVersions.add(key);
					knownFiles.add(candidate.name);
					state.discovered.push(row);
					rows.push({ ...row });
					stateChanged = true;
				} catch (e) {
					// will be tried again with the next build
					discoveryErrors++;
					console.log(`Error processing lex file: [${candidate.name}]: ${(e as Error).message}`);
				}
			}
		};
		await process(first);
		await process(skipKnownVersions(rest));
	}

	const locations = mavenLocations(candidates, bucket.complete, remote.complete, rows, state.mavenState.artifactIds, previous?.locations);

	// LDEV-6795: the packaging of the files we don't know it of yet, only needed with a min core version for Maven
	let packagingRead = 0;
	if (config.mavenOnlyMinCore.length && config.discoveryMax > 0) {
		for (const row of rows) {
			const fileName = str(row.filename);
			if (str(row.packaging).length) continue;
			if (state.packaging[fileName]) {
				row.packaging = state.packaging[fileName];
				continue;
			}
			if (packagingRead >= config.discoveryMax) continue;
			packagingRead++;
			try {
				const location = locations[fileName];
				const url = location ? await candidateUrl(config, source, { ...location, artifact: location.source === "repo" ? location.artifact : "", version: location.source === "repo" ? location.version : "" }) : config.extensionsCdnUrl + fileName;
				const lex = await readLex(url);
				row.packaging = state.packaging[fileName] = lex.packaging;
				stateChanged = true;
			} catch (e) {
				console.log(`Error probing the packaging of [${fileName}]: ${(e as Error).message}`);
			}
		}
	}

	// the logos are kept apart, they are most of the size and only needed with withLogo
	const logos: Logos = {};
	const sorted = sortMeta(rows);
	const data = sorted.map((row) => {
		const image = str(row.image);
		if (image.length) logos[str(row.filename)] = image;
		return columns.map((col) => (col === "image" ? "" : row[col] ?? ""));
	});

	const index: ExtensionIndex = {
		builtAt: Date.now(),
		columns,
		rows: data,
		locations,
		stats: {
			rows: data.length,
			fromMeta,
			discovered: state.discovered.length,
			mavenFiles: candidates.size,
			bucketComplete: bucket.complete,
			reposComplete: remote.complete,
			discoveryRead,
			discoveryErrors,
			packagingRead
		}
	};
	return { index, logos, state, stateChanged };
}
