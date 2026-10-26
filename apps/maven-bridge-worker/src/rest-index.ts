// Port of the REST provider index loading of BridgeSupport.cfc (loadIndex and helpers).
import { NoCaseMap, compare, isNumeric, urlEncodedFormat } from "./cfml";
import { BridgeError } from "./errors";

export interface VersionEntry {
	id: string;
	name: string;
	description: string;
	filename: string;
	created: string;
	downloadUrl: string;
}

export interface ArtifactEntry {
	id: string;
	name: string;
	versions: NoCaseMap<VersionEntry>;
}

export interface RestIndex {
	cachedAt: Date;
	provider: string;
	groupId: string;
	artifacts: NoCaseMap<ArtifactEntry>;
}

/** JSON shape stored in KV (keeps key order and casing). */
export interface StoredIndex {
	cachedAt: string;
	provider: string;
	groupId: string;
	artifacts: [string, { id: string; name: string; versions: [string, VersionEntry][] }][];
}

type Row = Record<string, unknown>;

const str = (v: unknown): string => (v === null || v === undefined ? "" : String(v));

export function serializeIndex(index: RestIndex): StoredIndex {
	return {
		cachedAt: index.cachedAt.toISOString(),
		provider: index.provider,
		groupId: index.groupId,
		artifacts: index.artifacts.keys().map((key) => {
			const a = index.artifacts.get(key)!;
			return [key, { id: a.id, name: a.name, versions: a.versions.keys().map((v) => [v, a.versions.get(v)!]) }];
		})
	};
}

export function deserializeIndex(stored: StoredIndex): RestIndex {
	const artifacts = new NoCaseMap<ArtifactEntry>();
	for (const [key, a] of stored.artifacts) {
		const versions = new NoCaseMap<VersionEntry>();
		for (const [v, entry] of a.versions) versions.set(v, entry);
		artifacts.set(key, { id: a.id, name: a.name, versions });
	}
	return { cachedAt: new Date(stored.cachedAt), provider: stored.provider, groupId: stored.groupId, artifacts };
}

export function buildIndex(payload: unknown, providerUrl: string, groupId: string, now = new Date()): RestIndex {
	const artifacts = new NoCaseMap<ArtifactEntry>();
	for (const ext of normalizeExtensions(payload)) {
		addVersionEntry(artifacts, ext, providerUrl);
		addOlderVersions(artifacts, ext, providerUrl);
	}
	return { cachedAt: now, provider: providerUrl, groupId, artifacts };
}

function lowerKeys(obj: Record<string, unknown>): Row {
	const out: Row = {};
	for (const [k, v] of Object.entries(obj)) {
		const lower = k.toLowerCase();
		if (!(lower in out)) out[lower] = v;
	}
	return out;
}

/** Accepts {extensions: {COLUMNS, DATA}} (serialized query) or {extensions: [rows]}. */
export function normalizeExtensions(payload: unknown): Row[] {
	if (payload !== null && typeof payload === "object" && !Array.isArray(payload)) {
		const p = lowerKeys(payload as Record<string, unknown>);
		const block = p.extensions;
		if (Array.isArray(block)) {
			return block.filter((r) => r !== null && typeof r === "object").map((r) => lowerKeys(r as Row));
		}
		if (block !== null && typeof block === "object") {
			const b = lowerKeys(block as Record<string, unknown>);
			const cols = Array.isArray(b.columns) ? (b.columns as unknown[]) : [];
			const data = Array.isArray(b.data) ? (b.data as unknown[]) : [];
			return data.map((rowData) => {
				const row: Row = {};
				const values = Array.isArray(rowData) ? rowData : [];
				cols.forEach((col, i) => {
					const key = String(col).toLowerCase();
					if (!(key in row)) row[key] = values[i];
				});
				return row;
			});
		}
	}
	throw new BridgeError("Unexpected extension provider response shape", "bridge.provider");
}

function addVersionEntry(artifacts: NoCaseMap<ArtifactEntry>, ext: Row, providerUrl: string): void {
	const version = str(ext.version);
	if (!version.length) return;
	const artifactId = resolveArtifactId(ext);
	if (!artifactId.length) return;

	const name = ext.name === null || ext.name === undefined ? artifactId : str(ext.name);
	if (!artifacts.has(artifactId)) {
		artifacts.set(artifactId, { id: str(ext.id), name, versions: new NoCaseMap() });
	}
	artifacts.get(artifactId)!.versions.set(version, {
		id: str(ext.id),
		name,
		description: str(ext.description),
		filename: str(ext.filename),
		created: str(ext.created),
		downloadUrl: resolveDownloadUrl(ext, providerUrl)
	});
}

function toList(value: unknown): string[] {
	if (Array.isArray(value)) return value.map(str);
	if (value === null || value === undefined) return [];
	return String(value).split(",").filter((s) => s.length);
}

function addOlderVersions(artifacts: NoCaseMap<ArtifactEntry>, ext: Row, providerUrl: string): void {
	const olderVersions = toList(ext.older);
	const olderNames = toList(ext.oldername);
	olderVersions.forEach((raw, i) => {
		const version = raw.trim();
		if (!version.length) return;
		const filename = olderNames.length > i ? olderNames[i].trim() : "";
		const pseudo: Row = { ...ext, version, url: "" };
		if (filename.length) pseudo.filename = filename;
		addVersionEntry(artifacts, pseudo, providerUrl);
	});
}

export function resolveArtifactId(ext: Row): string {
	if (str(ext.artifactid).length) return normalizeArtifactId(str(ext.artifactid));
	if (str(ext.filename).length && str(ext.version).length) {
		return normalizeArtifactId(filenameToArtifactId(str(ext.filename), str(ext.version)));
	}
	if (str(ext.name).length) return normalizeArtifactId(str(ext.name).replace(/\s+/g, "-") + "-extension");
	return "";
}

export function filenameToArtifactId(filename: string, version: string): string {
	let base = filename.split(".lex").join("");
	const suffix = "-" + version;
	if (base.toLowerCase().endsWith(suffix.toLowerCase())) base = base.slice(0, base.length - suffix.length);
	return base;
}

export function normalizeArtifactId(artifactId: string): string {
	let id = artifactId.trim();
	id = id.split(".extension").join("-extension");
	id = id.split(".").join("-");
	if (id.toLowerCase().endsWith("-extension")) return id.toLowerCase();
	return id.toLowerCase() + "-extension";
}

function resolveDownloadUrl(ext: Row, providerUrl: string): string {
	if (str(ext.url).length) return str(ext.url);
	if (str(ext.id).length && str(ext.version).length) {
		return providerUrl + "/rest/extension/provider/full/" + str(ext.id) + "?version=" + urlEncodedFormat(str(ext.version));
	}
	return "";
}

export function versionSortKey(version: string): string {
	let key = "";
	for (const part of version.split(/[.-]/).filter((p) => p.length)) {
		if (part.toLowerCase() === "snapshot") key += ".999999";
		else if (isNumeric(part)) key += "." + String(Math.round(Number(part))).padStart(5, "0");
		else key += "." + part;
	}
	return key;
}

export function sortVersions(versions: string[]): string[] {
	return [...versions].sort((a, b) => compare(versionSortKey(a), versionSortKey(b)));
}
