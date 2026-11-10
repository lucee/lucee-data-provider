// The answers of the extension provider, port of list(), getExtensionDetail() and getDownloadUrl() of
// services/ExtensionMetadataReader.cfc on top of an ExtensionIndex.
import type { Config } from "./config";
import type { MavenExtensionSource } from "./maven";
import type { CfQuery, ExtensionIndex, Logos, Row } from "./types";
import { checkVersionGTE, compareNoCase, coreVersionParts, effectiveMinCore, fitsCoreVersion, matchesReleaseType } from "./versions";

function str(value: unknown): string {
	return value === null || value === undefined ? "" : String(value);
}

/** struct with case-insensitive keys that keeps the order and the casing of the first insert, like a CFML ordered struct */
class OrderedNoCaseMap<V> {
	private readonly map = new Map<string, { key: string; value: V }>();

	get(key: string): V | undefined {
		return this.map.get(key.toLowerCase())?.value;
	}

	set(key: string, value: V): void {
		const existing = this.map.get(key.toLowerCase());
		this.map.set(key.toLowerCase(), { key: existing ? existing.key : key, value });
	}

	entries(): [string, V][] {
		return [...this.map.values()].map((e) => [e.key, e.value]);
	}
}

interface ExtensionVersions {
	latest: string;
	versions: OrderedNoCaseMap<Row>;
}

export class NoVersionForCore extends Error {}

export class ExtensionProvider {
	readonly served: Row[];
	readonly columns: string[];
	private readonly mapped = new OrderedNoCaseMap<ExtensionVersions>();
	private readonly listCache = new Map<string, CfQuery>();

	constructor(
		readonly index: ExtensionIndex,
		private readonly config: Config,
		private readonly source: MavenExtensionSource,
		private readonly logos: () => Promise<Logos>
	) {
		this.columns = index.columns;
		this.served = this.buildServed();
		for (const row of this.served) {
			const id = str(row.id);
			let entry = this.mapped.get(id);
			if (!entry) {
				entry = { latest: str(row.version), versions: new OrderedNoCaseMap<Row>() };
				this.mapped.set(id, entry);
			}
			entry.versions.set(str(row.version), row);
		}
	}

	/** LDEV-6795: is there a Maven source to serve from? Without one everything is served from the flat bucket */
	hasMavenSource(): boolean {
		return this.config.mavenCdnUrl.length > 0 || this.source.hasRepos();
	}

	/** LDEV-6795: is the file served from a Maven source (Maven first), the others are the fallback to the flat bucket */
	isMavenServed(fileName: string): boolean {
		const location = this.index.locations[fileName];
		if (!location) return false;
		return location.source === "repo" || this.config.mavenCdnUrl.length > 0;
	}

	/** _buildServed(): without the flat fallback only what is served from a Maven source, the effective min core version applied */
	private buildServed(): Row[] {
		let dropFlat = !this.config.flatFallback;
		if (dropFlat && !this.hasMavenSource()) {
			console.log("The flat S3 fallback is switched off, but there is no Maven source configured. Ignoring that, the flat files are served.");
			dropFlat = false;
		}
		const served: Row[] = [];
		for (const data of this.index.rows) {
			const row: Row = {};
			this.columns.forEach((col, i) => (row[col] = data[i]));
			if (dropFlat && !this.isMavenServed(str(row.filename))) continue;
			row.minCoreVersion = effectiveMinCore(str(row.minCoreVersion), str(row.packaging), this.config.mavenOnlyMinCore);
			served.push(row);
		}
		return served;
	}

	/** list(): the newest version of every extension of the given type the core version can load, sorted by name */
	async list(type: string, withLogo: boolean, coreVersion: string): Promise<CfQuery> {
		const cacheKey = `list-${withLogo ? "wl" : "nl"}_${type}_${coreVersion}`;
		const cached = this.listCache.get(cacheKey);
		if (cached) return cached;

		let extensions = this.served;
		if (coreVersion.length) {
			const v = coreVersionParts(coreVersion);
			extensions = extensions.filter((row) => !str(row.minCoreVersion).length || checkVersionGTE(str(row.minCoreVersion), v[0], v[1], v[2], v[3]));
		}
		// LDEV-6789: filter by release type first, so the version an extension is listed with is the newest one of that type
		if (type.toLowerCase() !== "all") extensions = extensions.filter((row) => matchesReleaseType(str(row.version), type));

		const stripped = this.stripAllButLatestVersions(extensions);
		// sort by name (case-insensitive), versionSortable desc as the tie-breaker
		stripped.sort((a, b) => {
			const byName = compareNoCase(str(a.name), str(b.name));
			if (byName !== 0) return byName;
			const x = str(a.versionSortable);
			const y = str(b.versionSortable);
			return x > y ? -1 : x < y ? 1 : 0;
		});

		const logos = withLogo ? await this.logos() : {};
		const columns = [...this.columns, "coreVersion"];
		const result: CfQuery = {
			COLUMNS: columns,
			DATA: stripped.map((row) => columns.map((col) => (col === "image" ? (withLogo ? logos[str(row.filename)] ?? "" : "") : row[col] ?? "")))
		};
		if (this.listCache.size >= 100) this.listCache.delete(this.listCache.keys().next().value!);
		this.listCache.set(cacheKey, result);
		return result;
	}

	/** _stripAllButLatestVersions(): the first row of every id, with the older versions in older, olderName, olderDate, coreVersion */
	private stripAllButLatestVersions(extensions: Row[]): Row[] {
		const stripped: Row[] = [];
		// starts as "" like the CFML version, so rows without an id at the start are not listed
		let last = "";
		let current: Row | undefined;
		for (const ext of extensions) {
			const id = str(ext.id);
			if (last.toLowerCase() !== id.toLowerCase()) {
				current = { ...ext, older: [], olderName: [], olderDate: [], coreVersion: [] };
				stripped.push(current);
			} else if (str(ext.version).length && current) {
				(current.older as unknown[]).push(ext.version);
				(current.olderName as unknown[]).push(ext.filename);
				(current.olderDate as unknown[]).push(ext.created);
				(current.coreVersion as unknown[]).push(ext.minCoreVersion);
			}
			last = id;
		}
		return stripped;
	}

	/**
	 * getExtensionDetail(): without a version (or "latest") the newest version of the given type that fits the
	 * core version, a version that is given explicitly is returned as it is, whatever its type. undefined when
	 * there is no such extension or version (the REST endpoints answer 404).
	 */
	async detail(id: string, version: string, withLogo: boolean, coreVersion: string, type: string): Promise<Row | undefined> {
		const entry = this.mapped.get(id);
		if (!entry) return undefined;

		if (version.toLowerCase() === "latest" || !version.length) {
			try {
				version = this.latestVersion(entry, coreVersion, type);
			} catch (e) {
				if (e instanceof NoVersionForCore) return undefined;
				throw e;
			}
		}
		const found = entry.versions.get(version);
		if (!found) return undefined;

		// LDEV-6795: a version that is asked for explicitly is not served to a core that can't load it
		if (coreVersion.length && !fitsCoreVersion(str(found.minCoreVersion), coreVersion)) return undefined;

		const ext: Row = {};
		for (const col of this.columns) ext[col] = found[col] ?? "";
		ext.image = withLogo ? (await this.logos())[str(found.filename)] ?? "" : "";
		return ext;
	}

	/** _getLatestVersion(): the newest version of the type that fits the core version, the versions are newest first */
	private latestVersion(entry: ExtensionVersions, coreVersion: string, type: string): string {
		if (!coreVersion.length && type.toLowerCase() === "all") return entry.latest;
		const cv = coreVersionParts(coreVersion);
		let typeMatched = false;
		for (const [k, v] of entry.versions.entries()) {
			if (!matchesReleaseType(k, type)) continue;
			typeMatched = true;
			if (!coreVersion.length) return k;
			if (checkVersionGTE(str(v.minCoreVersion), cv[0], cv[1], cv[2], cv[3])) return k;
		}
		if (typeMatched) throw new NoVersionForCore(`No extension version available for [${coreVersion}]`);
		return "";
	}

	/**
	 * getDownloadUrl(): Maven first (LDEV-6795). A file in the Maven layout of the core bucket is served from the
	 * Maven cdn url, a file available from a Maven repository from there; everything else is the fallback to
	 * the flat bucket.
	 */
	async downloadUrl(fileName: string): Promise<string> {
		const location = this.index.locations[fileName];
		if (location?.source === "bucket" && this.config.mavenCdnUrl.length) return this.config.mavenCdnUrl + location.path;
		if (location?.source === "repo") {
			const resolved = await this.source.getFileUrl(location.artifact, location.version, location.repos);
			if (resolved.length) return resolved;
			console.log(`Could not resolve the download url of [${fileName}] in the maven repositories.`);
		}
		if (this.hasMavenSource() && !this.isMavenServed(fileName)) {
			console.log(`Flat S3 fallback: the download of [${fileName}] is served from the flat bucket, it is not in the Maven layout.`);
		}
		return this.config.extensionsCdnUrl + fileName;
	}
}
