// Runtime I/O for the supports: replaces the server-scope / file cache of the
// CFML bridge with Workers KV (provider indexes, and upstream group files as a fallback,
// kept fresh by the hourly cron) and the Cache API (everything else, TTL based).
// Directory listings and maven-metadata.xml use the short METADATA_CACHE_TTL_MINUTES.
import type { BridgeConfig } from "./config";
import type { Env } from "./env";
import { BridgeError, UPSTREAM_NOT_FOUND } from "./errors";
import { buildIndex, deserializeIndex, serializeIndex, type RestIndex, type StoredIndex } from "./rest-index";
import { applyRestVersionOverlays } from "./rest-overlays";
import { checksumOfText, type ChecksumType } from "./checksum";
import {
	buildArtifactMetadataXml,
	buildGroupMetadataXml,
	generateDirectoryListingHtml,
	groupFingerprint,
	isExtensionArtifactId,
	listingFingerprint,
	parseArtifactMetadataXml,
	parseDirectoryListingHtml,
	parseGroupMetadataXml,
	splitMetadataChecksum,
	summarizeVersions,
	versionsFingerprint,
	type DirectoryEntry,
	type GroupArtifact
} from "./metadata-generate";
import { mavenTimestamp } from "./cfml";
import {
	artifactFromR2Key,
	eventObjectKeys,
	listArtifactIds,
	listArtifactVersions,
	listDirectoryEntries,
	listRootsFromConfig
} from "./r2-metadata";
import { contentTypeForPath, type BridgeSupport, type SupportIo, type UpstreamContent } from "./support";

/** Cache API origin for generated metadata: a fixed key, not the request host. */
const GENERATED_CACHE_ORIGIN = "https://lucee-maven-bridge.internal";

const GENERATION_KEY = "cache-generation";
/** bumped by ?flush=metadata; part of the Cache API key of every listing and metadata file */
export const METADATA_GENERATION_KEY = "metadata-generation";
/** extra time a KV entry stays "fresh" so a slightly late cron run does not cause live loads */
const GRACE_MS = 15 * 60 * 1000;
export const USER_AGENT = "lucee-maven-bridge-worker";

interface StoredUpstream {
	body: string;
	contentType: string;
	fetchedAt: string;
}

export function indexKey(support: BridgeSupport): string {
	return `index:${support.groupId}`;
}

export function upstreamKey(support: BridgeSupport, rel: string): string {
	return `upstream:${support.upstreamUrl}${rel}`;
}

/** Upstream files that are kept in KV and refreshed by the cron (like syncUpstreamRepository). */
export function groupLevelFiles(support: BridgeSupport): string[] {
	return [`${support.groupPath}/maven-metadata.xml`, `${support.groupPath}/index.html`];
}

/** true for upstream files that change with every publish: maven-metadata.xml (+ checksums) and index.html listings */
export function isMetadataFile(relativePath: string): boolean {
	const name = (relativePath.split("/").pop() ?? "").toLowerCase();
	return name.startsWith("maven-metadata") || name === "index.html";
}

function cleanRel(relativePath: string): string {
	return relativePath.replace(/\\/g, "/").replace(/^\/+/, "");
}

export class RuntimeIo implements SupportIo {
	private generation: Promise<string> | undefined;
	private metadataGeneration: Promise<string> | undefined;

	constructor(
		readonly env: Env,
		readonly config: BridgeConfig,
		/** background work (ctx.waitUntil); undefined = await inline */
		readonly waitUntil?: (p: Promise<unknown>) => void,
		/** origin used for Cache API keys; undefined disables the Cache API layer */
		readonly cacheOrigin?: string
	) {}

	get r2(): R2Bucket | undefined {
		return this.config.r2Mode === "serve" ? this.env.ARTIFACTS : undefined;
	}

	/** R2 bucket used to list artifacts for generated metadata (cron and queue have no hostname, so r2Mode may be off). */
	private get artifacts(): R2Bucket | undefined {
		return this.env.ARTIFACTS;
	}

	private signal(support: BridgeSupport): AbortSignal {
		return AbortSignal.timeout(support.timeout * 1000);
	}

	private background(work: Promise<unknown>): void {
		const guarded = work.catch((e) => console.error("maven-bridge background task failed", e));
		if (this.waitUntil) this.waitUntil(guarded);
	}

	// --- cache generation (bumped by flush, part of every Cache API key and computed checksum key) ---

	getGeneration(): Promise<string> {
		this.generation ??= this.env.BRIDGE_CACHE.get(GENERATION_KEY).then((g) => g ?? "0");
		return this.generation;
	}

	async bumpGeneration(): Promise<void> {
		const next = String(Date.now());
		await this.env.BRIDGE_CACHE.put(GENERATION_KEY, next);
		this.generation = Promise.resolve(next);
	}

	getMetadataGeneration(): Promise<string> {
		this.metadataGeneration ??= this.env.BRIDGE_CACHE.get(METADATA_GENERATION_KEY).then((g) => g ?? "0");
		return this.metadataGeneration;
	}

	/**
	 * Drops every cached listing and metadata file in all locations: the new generation is part of
	 * their Cache API keys (KV reads are cached for about a minute per location, so that is the delay).
	 */
	async bumpMetadataGeneration(): Promise<string> {
		const next = String(Date.now());
		await this.env.BRIDGE_CACHE.put(METADATA_GENERATION_KEY, next);
		this.metadataGeneration = Promise.resolve(next);
		return next;
	}

	private async cacheKey(kind: string, id: string): Promise<Request | undefined> {
		if (!this.cacheOrigin) return undefined;
		const gen = await this.getGeneration();
		return new Request(`${this.cacheOrigin}/__maven-bridge-cache/${gen}/${kind}/${encodeURIComponent(id)}`);
	}

	private async cacheGet(key: Request | undefined): Promise<Response | undefined> {
		return key ? caches.default.match(key) : undefined;
	}

	private cachePut(key: Request | undefined, body: string, ttlSeconds: number, contentType = "text/plain"): void {
		if (!key) return;
		const res = new Response(body, {
			headers: { "content-type": contentType, "cache-control": `public, max-age=${ttlSeconds}` }
		});
		this.background(caches.default.put(key, res));
	}

	// --- negative cache: what the upstream answered 404 is not asked again for NEGATIVE_CACHE_TTL_MINUTES ---

	/** Cache API key of the "upstream has no such file" marker; metadata files follow the metadata generation (?flush=metadata) */
	private async missingKey(url: string): Promise<Request | undefined> {
		const meta = isMetadataFile(url.split("?")[0]) ? `${await this.getMetadataGeneration()}/` : "";
		return this.cacheKey("missing", meta + url);
	}

	private async isKnownMissing(url: string): Promise<boolean> {
		return this.config.negativeCacheTtlSeconds > 0 && (await this.cacheGet(await this.missingKey(url))) !== undefined;
	}

	private rememberMissing(url: string): void {
		const ttl = this.config.negativeCacheTtlSeconds;
		if (ttl <= 0) return;
		this.background(this.missingKey(url).then((k) => this.cachePut(k, "1", ttl)));
	}

	// --- upstream text files ---

	/**
	 * Live read of an upstream file: R2 first (in serve mode), then the upstream URL. Listings and
	 * maven-metadata.xml change with every release, so for those the upstream comes first and a copy
	 * in R2 is only used when the upstream does not have the file or cannot be reached.
	 */
	async fetchUpstreamLive(support: BridgeSupport, relativePath: string): Promise<UpstreamContent> {
		const rel = cleanRel(relativePath);
		const r2 = this.r2;
		if (!r2) return this.fetchUpstreamUrl(support, rel);
		const fromR2 = async () => {
			const obj = await r2.get(this.config.r2Prefix + rel);
			return obj ? { body: await obj.text(), contentType: contentTypeForPath(rel) } : undefined;
		};
		if (!isMetadataFile(rel)) return (await fromR2()) ?? this.fetchUpstreamUrl(support, rel);
		try {
			return await this.fetchUpstreamUrl(support, rel);
		} catch (e) {
			const stored = await fromR2();
			if (stored) return stored;
			throw e;
		}
	}

	private async fetchUpstreamUrl(support: BridgeSupport, rel: string): Promise<UpstreamContent> {
		const url = support.upstreamUrl + rel;
		if (await this.isKnownMissing(url)) throw new BridgeError(`Upstream not found [${rel}]`, UPSTREAM_NOT_FOUND);
		const res = await fetch(url, { headers: { "user-agent": USER_AGENT }, signal: this.signal(support) });
		if (res.status === 404) {
			await res.body?.cancel();
			this.rememberMissing(url);
			throw new BridgeError(`Upstream not found [${rel}]`, UPSTREAM_NOT_FOUND);
		}
		if (res.status !== 200) {
			await res.body?.cancel();
			throw new BridgeError(`Upstream [${url}] returned HTTP ${res.status}`, "bridge.upstream");
		}
		return { body: await res.text(), contentType: contentTypeForPath(rel) };
	}

	async getUpstreamContent(support: BridgeSupport, relativePath: string): Promise<UpstreamContent> {
		const rel = cleanRel(relativePath);
		if (isMetadataFile(rel)) return this.getMetadataContent(support, rel);

		const cacheKey = await this.cacheKey("upstream", support.upstreamUrl + rel);
		const hit = await this.cacheGet(cacheKey);
		if (hit) return { body: await hit.text(), contentType: contentTypeForPath(rel) };
		const live = await this.fetchUpstreamLive(support, rel);
		this.cachePut(cacheKey, live.body, support.cacheTtlMinutes * 60, live.contentType);
		return live;
	}

	/**
	 * Listings and maven-metadata.xml: cached per location for METADATA_CACHE_TTL_MINUTES only, so a
	 * new release shows up within minutes everywhere. Group level files keep their KV copy (written
	 * when it changed, and by the cron) as the answer when the upstream cannot be reached.
	 */
	private async getMetadataContent(support: BridgeSupport, rel: string): Promise<UpstreamContent> {
		if (this.shouldGenerateMetadata(support, rel)) {
			return this.getGeneratedMetadata(support, rel);
		}

		const ttlSeconds = this.config.metadataCacheTtlSeconds;
		const cacheKey =
			ttlSeconds > 0
				? await this.cacheKey("metadata", `${await this.getMetadataGeneration()}/${support.upstreamUrl}${rel}`)
				: undefined;
		const hit = await this.cacheGet(cacheKey);
		if (hit) return { body: await hit.text(), contentType: contentTypeForPath(rel) };

		if (!groupLevelFiles(support).includes(rel)) {
			const live = await this.fetchUpstreamLive(support, rel);
			this.cachePut(cacheKey, live.body, ttlSeconds, live.contentType);
			return live;
		}

		const stored = await this.env.BRIDGE_CACHE.get<StoredUpstream>(upstreamKey(support, rel), "json");
		let live: UpstreamContent;
		try {
			live = await this.fetchUpstreamLive(support, rel);
		} catch (e) {
			if (e instanceof BridgeError && e.type === UPSTREAM_NOT_FOUND) {
				// gone upstream (or not there yet during migration): drop the KV copy, like the cron does
				if (stored) this.background(this.env.BRIDGE_CACHE.delete(upstreamKey(support, rel)));
				throw e;
			}
			if (!stored) throw e;
			console.warn(`maven-bridge upstream [${rel}] failed, serving the stored copy`, e);
			return { body: stored.body, contentType: stored.contentType };
		}
		this.cachePut(cacheKey, live.body, ttlSeconds, live.contentType);
		// KV is only written when the file changed (the cron rewrites it every hour anyway)
		if (!stored || stored.body !== live.body) this.background(this.storeUpstreamFile(support, rel, live));
		return live;
	}

	private storeUpstreamFile(support: BridgeSupport, rel: string, content: UpstreamContent): Promise<void> {
		const stored: StoredUpstream = { ...content, fetchedAt: new Date().toISOString() };
		return this.env.BRIDGE_CACHE.put(upstreamKey(support, rel), JSON.stringify(stored));
	}

	/** Re-fetch a group level file into KV; a 404 removes it, other errors keep the stale copy. */
	async refreshUpstreamFile(support: BridgeSupport, rel: string): Promise<void> {
		try {
			await this.storeUpstreamFile(support, rel, await this.fetchUpstreamLive(support, rel));
		} catch (e) {
			if (e instanceof BridgeError && e.type === UPSTREAM_NOT_FOUND) {
				// group files may not exist yet on upstream during migration
				await this.env.BRIDGE_CACHE.delete(upstreamKey(support, rel));
				return;
			}
			throw e;
		}
	}

	// --- existence checks ---

	/** HEAD of `url`: "found" (200), "missing" (404/410, may be remembered) or "unknown" (anything else, never remembered) */
	private async headStatus(url: string, support?: BridgeSupport): Promise<"found" | "missing" | "unknown"> {
		const res = await fetch(url, {
			method: "HEAD",
			redirect: "follow",
			headers: { "user-agent": USER_AGENT },
			signal: AbortSignal.timeout((support?.timeout ?? this.config.timeout) * 1000)
		});
		await res.body?.cancel();
		if (res.status === 200) return "found";
		return res.status === 404 || res.status === 410 ? "missing" : "unknown";
	}

	/**
	 * Positive results are cached (Cache API) for the cache TTL, a 404 for NEGATIVE_CACHE_TTL_MINUTES;
	 * other answers and failures are always re-checked.
	 */
	private async cachedExists(url: string, check: () => Promise<"found" | "missing" | "unknown">): Promise<boolean> {
		const key = await this.cacheKey("exists", url);
		if (await this.cacheGet(key)) return true;
		if (await this.isKnownMissing(url)) return false;
		const result = await check();
		if (result === "found") this.cachePut(key, "1", this.config.cacheTtlMinutes * 60);
		else if (result === "missing") this.rememberMissing(url);
		return result === "found";
	}

	async remoteResourceExists(url: string): Promise<boolean> {
		return this.cachedExists(url, async () => {
			try {
				return await this.headStatus(url);
			} catch (e) {
				console.warn(`HEAD ${url} failed`, e);
				return "unknown";
			}
		});
	}

	async upstreamResourceExists(support: BridgeSupport, relativePath: string): Promise<boolean> {
		const url = support.upstreamUrl + cleanRel(relativePath);
		return this.cachedExists(url, () => this.headStatus(url, support));
	}

	// --- REST provider index ---

	async loadIndex(support: BridgeSupport): Promise<RestIndex> {
		const uri = `${support.providerUrl}/rest/extension/provider/info?type=all&withLogo=false`;
		const res = await fetch(uri, {
			headers: { accept: "application/json", "user-agent": USER_AGENT },
			signal: this.signal(support)
		});
		if (res.status !== 200) {
			await res.body?.cancel();
			throw new BridgeError(`Extension provider [${uri}] returned HTTP ${res.status}`, "bridge.provider");
		}
		const payload: unknown = await res.json();
		return buildIndex(payload, support.providerUrl, support.groupId);
	}

	async refreshIndex(support: BridgeSupport): Promise<RestIndex> {
		const index = await this.loadIndex(support);
		await this.env.BRIDGE_CACHE.put(indexKey(support), JSON.stringify(serializeIndex(index)));
		return index;
	}

	async getIndex(support: BridgeSupport): Promise<RestIndex> {
		const stored = await this.env.BRIDGE_CACHE.get<StoredIndex>(indexKey(support), "json");
		if (stored) {
			const index = applyRestVersionOverlays(deserializeIndex(stored));
			if (Date.now() - index.cachedAt.getTime() >= support.cacheTtlMinutes * 60 * 1000 + GRACE_MS) {
				this.background(this.refreshIndex(support));
			}
			return index;
		}
		return this.refreshIndex(support);
	}

	// --- sync / flush ---

	/** Cron and flush: reload every provider index and upstream group file into KV. */
	async syncAll(supports: BridgeSupport[]): Promise<{ groupId: string; ok: boolean; error?: string }[]> {
		const results = [];
		for (const support of supports) {
			try {
				if (support.hasUpstream()) {
					if (this.config.metadataSource === "upstream") {
						for (const rel of groupLevelFiles(support)) await this.refreshUpstreamFile(support, rel);
					} else {
						await this.rebuildAllGenerated(support);
					}
				} else {
					await this.refreshIndex(support);
				}
				results.push({ groupId: support.groupId, ok: true });
			} catch (e) {
				console.error(`maven-bridge sync of [${support.groupId}] failed`, e);
				results.push({ groupId: support.groupId, ok: false, error: e instanceof Error ? e.message : String(e) });
			}
		}
		return results;
	}

	async flushAll(supports: BridgeSupport[]): Promise<void> {
		const deletes: Promise<void>[] = [];
		for (const support of supports) {
			deletes.push(this.env.BRIDGE_CACHE.delete(indexKey(support)));
			for (const rel of groupLevelFiles(support)) deletes.push(this.env.BRIDGE_CACHE.delete(upstreamKey(support, rel)));
		}
		await Promise.all(deletes);
		await this.bumpGeneration();
		await this.syncAll(supports);
	}

	// --- generated org.lucee metadata (R2 listings, optional union with the upstream file) ---

	private shouldGenerateMetadata(support: BridgeSupport, rel: string): boolean {
		if (this.config.metadataSource === "upstream") return false;
		if (!support.hasUpstream()) return false;
		return this.generatedMetadataKind(support, rel) !== undefined;
	}

	/**
	 * group-index, group-metadata (+ checksums) and artifact-metadata (+ checksums) are generated.
	 * Artifact directory listings and version-level maven-metadata.xml still come from the upstream / R2 object.
	 */
	private generatedMetadataKind(
		support: BridgeSupport,
		rel: string
	): "group-index" | "group-metadata" | "artifact-metadata" | undefined {
		const path = cleanRel(rel);
		const group = support.groupPath;
		if (path === `${group}/index.html`) return "group-index";
		const prefix = group + "/";
		if (!path.startsWith(prefix)) return undefined;
		const rest = path.slice(prefix.length);
		const segs = rest.split("/");
		const meta = splitMetadataChecksum(segs[segs.length - 1] ?? "");
		if (segs.length === 1 && meta) return "group-metadata";
		if (segs.length === 2 && meta) return "artifact-metadata";
		return undefined;
	}

	private async generatedKvKey(rel: string): Promise<string> {
		const [cacheGen, metaGen] = await Promise.all([this.getGeneration(), this.getMetadataGeneration()]);
		return `generated-metadata:${cacheGen}:${metaGen}:${cleanRel(rel)}`;
	}

	/** Cache API key that does not include the request origin, so every hostname shares the same entry. */
	private async generatedCacheRequest(rel: string): Promise<Request> {
		const [cacheGen, metaGen] = await Promise.all([this.getGeneration(), this.getMetadataGeneration()]);
		return new Request(`${GENERATED_CACHE_ORIGIN}/__generated/${cacheGen}/${metaGen}/${encodeURIComponent(cleanRel(rel))}`);
	}

	private async getGeneratedMetadata(support: BridgeSupport, rel: string): Promise<UpstreamContent> {
		const path = cleanRel(rel);
		const fileName = path.split("/").pop() ?? "";
		const meta = splitMetadataChecksum(fileName);
		const xmlRel = meta?.checksumType ? path.slice(0, -(meta.checksumType.length + 1)) : path;

		const ttlSeconds = this.config.metadataGenerateTtlSeconds;
		const cacheReq = ttlSeconds > 0 ? await this.generatedCacheRequest(path) : undefined;
		const hit = await this.cacheGet(cacheReq);
		if (hit) return { body: await hit.text(), contentType: contentTypeForPath(path) };

		const content = meta?.checksumType
			? await this.checksumOfGenerated(support, xmlRel, meta.checksumType)
			: await this.loadOrRebuildGenerated(support, xmlRel);
		this.cachePut(cacheReq, content.body, ttlSeconds || this.config.metadataCacheTtlSeconds, content.contentType);
		return { body: content.body, contentType: contentTypeForPath(path) };
	}

	private async checksumOfGenerated(support: BridgeSupport, xmlRel: string, type: ChecksumType): Promise<UpstreamContent> {
		const xml = await this.loadOrRebuildGenerated(support, xmlRel);
		return { body: await checksumOfText(xml.body, type), contentType: "text/plain; charset=utf-8" };
	}

	private async loadOrRebuildGenerated(support: BridgeSupport, rel: string): Promise<UpstreamContent> {
		const key = await this.generatedKvKey(rel);
		const ttl = this.config.metadataGenerateTtlSeconds;
		const stored = await this.env.BRIDGE_CACHE.get<{ body: string; contentType: string; generatedAt: string; fingerprint: string }>(
			key,
			"json"
		);
		if (stored && (ttl <= 0 || Date.now() - Date.parse(stored.generatedAt) < ttl * 1000)) {
			return { body: stored.body, contentType: stored.contentType };
		}
		return this.rebuildGenerated(support, rel, stored ?? undefined);
	}

	private async storeGenerated(
		rel: string,
		body: string,
		contentType: string,
		fingerprint: string,
		previous?: { body: string; fingerprint: string; generatedAt: string; contentType: string }
	): Promise<UpstreamContent> {
		const stable = previous && previous.fingerprint === fingerprint ? previous : undefined;
		const stored = {
			body: stable?.body ?? body,
			contentType: stable?.contentType ?? contentType,
			generatedAt: new Date().toISOString(),
			fingerprint
		};
		const ttl = Math.max(this.config.metadataGenerateTtlSeconds * 2, 24 * 60 * 60);
		await this.env.BRIDGE_CACHE.put(await this.generatedKvKey(rel), JSON.stringify(stored), {
			expirationTtl: Math.max(60, ttl)
		});
		return { body: stored.body, contentType: stored.contentType };
	}

	private async rebuildGenerated(
		support: BridgeSupport,
		rel: string,
		previous?: { body: string; contentType: string; generatedAt: string; fingerprint: string }
	): Promise<UpstreamContent> {
		const path = cleanRel(rel);
		const kind = this.generatedMetadataKind(support, path);
		if (kind === "group-index") return this.rebuildGroupIndex(support, previous);
		if (kind === "group-metadata") return this.rebuildGroupMetadata(support, previous);
		if (kind === "artifact-metadata") {
			const artifactId = path.slice(support.groupPath.length + 1).split("/")[0];
			return this.rebuildArtifactMetadata(support, artifactId, previous);
		}
		throw new BridgeError(`Cannot generate metadata for [${path}]`, UPSTREAM_NOT_FOUND);
	}

	private async r2Versions(support: BridgeSupport, artifactId: string): Promise<string[]> {
		const bucket = this.artifacts;
		if (!bucket) return [];
		return listArtifactVersions(bucket, support.groupPath, artifactId, listRootsFromConfig(this.config));
	}

	private async r2ArtifactIds(support: BridgeSupport): Promise<string[]> {
		const bucket = this.artifacts;
		if (!bucket) return [];
		return listArtifactIds(bucket, support.groupPath, listRootsFromConfig(this.config));
	}

	private async r2DirectoryEntries(support: BridgeSupport): Promise<DirectoryEntry[]> {
		const bucket = this.artifacts;
		if (!bucket) return [];
		return listDirectoryEntries(bucket, support.groupPath, listRootsFromConfig(this.config));
	}

	private async upstreamText(support: BridgeSupport, rel: string): Promise<string | undefined> {
		if (this.config.metadataSource !== "merge") return undefined;
		try {
			return (await this.fetchUpstreamUrl(support, rel)).body;
		} catch (e) {
			if (e instanceof BridgeError && e.type === UPSTREAM_NOT_FOUND) return undefined;
			console.warn(`maven-bridge merge: upstream [${rel}] failed, continuing with R2 only`, e);
			return undefined;
		}
	}

	private async unionArtifactVersions(support: BridgeSupport, artifactId: string): Promise<string[]> {
		const fromR2 = await this.r2Versions(support, artifactId);
		const xml = await this.upstreamText(support, `${support.groupPath}/${artifactId}/maven-metadata.xml`);
		const fromUpstream = xml ? parseArtifactMetadataXml(xml).versions : [];
		return [...new Set([...fromR2, ...fromUpstream])];
	}

	private async rebuildArtifactMetadata(
		support: BridgeSupport,
		artifactId: string,
		previous?: { body: string; contentType: string; generatedAt: string; fingerprint: string }
	): Promise<UpstreamContent> {
		const versions = await this.unionArtifactVersions(support, artifactId);
		if (!versions.length) throw new BridgeError(`Upstream not found [${artifactId}]`, UPSTREAM_NOT_FOUND);
		const fingerprint = versionsFingerprint(versions);
		const lastUpdated = mavenTimestamp(new Date());
		const body = buildArtifactMetadataXml(support.groupId, artifactId, versions, lastUpdated);
		return this.storeGenerated(
			`${support.groupPath}/${artifactId}/maven-metadata.xml`,
			body,
			"application/xml; charset=utf-8",
			fingerprint,
			previous
		);
	}

	private async unionGroupArtifacts(support: BridgeSupport): Promise<GroupArtifact[]> {
		const ids = new Set<string>();
		for (const id of await this.r2ArtifactIds(support)) {
			if (isExtensionArtifactId(id)) ids.add(id);
		}
		const xml = await this.upstreamText(support, `${support.groupPath}/maven-metadata.xml`);
		const fromUpstream = xml ? parseGroupMetadataXml(xml) : [];
		for (const a of fromUpstream) ids.add(a.artifactId);
		const artifacts: GroupArtifact[] = [];
		for (const artifactId of ids) {
			const versions = await this.unionArtifactVersions(support, artifactId);
			if (!versions.length) {
				const fallback = fromUpstream.find((a) => a.artifactId === artifactId);
				if (fallback) artifacts.push(fallback);
				continue;
			}
			const summarized = summarizeVersions(versions);
			artifacts.push({ artifactId, latest: summarized.latest, release: summarized.release });
		}
		return artifacts.sort((a, b) => a.artifactId.localeCompare(b.artifactId));
	}

	private async rebuildGroupMetadata(
		support: BridgeSupport,
		previous?: { body: string; contentType: string; generatedAt: string; fingerprint: string }
	): Promise<UpstreamContent> {
		const artifacts = await this.unionGroupArtifacts(support);
		const body = buildGroupMetadataXml(support.groupId, artifacts, mavenTimestamp(new Date()));
		return this.storeGenerated(
			`${support.groupPath}/maven-metadata.xml`,
			body,
			"application/xml; charset=utf-8",
			groupFingerprint(artifacts),
			previous
		);
	}

	private async unionDirectoryEntries(support: BridgeSupport): Promise<DirectoryEntry[]> {
		const byName = new Map<string, DirectoryEntry>();
		for (const entry of await this.r2DirectoryEntries(support)) byName.set(entry.name, entry);
		const html = await this.upstreamText(support, `${support.groupPath}/index.html`);
		if (html) {
			for (const entry of parseDirectoryListingHtml(html)) {
				if (!byName.has(entry.name)) byName.set(entry.name, entry);
			}
		}
		return [...byName.values()].sort((a, b) => a.name.localeCompare(b.name));
	}

	private async rebuildGroupIndex(
		support: BridgeSupport,
		previous?: { body: string; contentType: string; generatedAt: string; fingerprint: string }
	): Promise<UpstreamContent> {
		const entries = await this.unionDirectoryEntries(support);
		const body = generateDirectoryListingHtml(entries);
		return this.storeGenerated(
			`${support.groupPath}/index.html`,
			body,
			"text/html; charset=utf-8",
			listingFingerprint(entries),
			previous
		);
	}

	/** Rebuild one artifact's metadata and the group files (used by the R2 queue consumer). */
	async rebuildAffectedMetadata(support: BridgeSupport, artifactIds: Iterable<string>): Promise<void> {
		const unique = [...new Set([...artifactIds].filter((id) => id.length))];
		for (const artifactId of unique) {
			try {
				await this.rebuildArtifactMetadata(support, artifactId);
			} catch (e) {
				if (e instanceof BridgeError && e.type === UPSTREAM_NOT_FOUND) continue;
				throw e;
			}
		}
		await this.rebuildGroupMetadata(support);
		await this.rebuildGroupIndex(support);
	}

	/** Hourly safety net: rebuild every generated file from the current R2 listing (and upstream, in merge mode). */
	async rebuildAllGenerated(support: BridgeSupport): Promise<void> {
		const ids = new Set(await this.r2ArtifactIds(support));
		if (this.config.metadataSource === "merge") {
			const xml = await this.upstreamText(support, `${support.groupPath}/maven-metadata.xml`);
			if (xml) for (const a of parseGroupMetadataXml(xml)) ids.add(a.artifactId);
			const html = await this.upstreamText(support, `${support.groupPath}/index.html`);
			if (html) for (const e of parseDirectoryListingHtml(html)) ids.add(e.name);
		}
		await this.rebuildAffectedMetadata(support, ids);
	}

	/**
	 * Queue consumer: object-created notifications from the R2 bucket. Rebuilds the
	 * affected artifact metadata and the group files. Metadata object keys are ignored.
	 */
	async handleObjectCreated(supports: BridgeSupport[], batch: { messages: readonly { body: unknown; ack: () => void }[] }): Promise<void> {
		const keys = batch.messages.flatMap((m) => eventObjectKeys(m.body));
		for (const support of supports) {
			if (!support.hasUpstream()) continue;
			if (this.config.metadataSource === "upstream") continue;
			const roots = listRootsFromConfig(this.config);
			const ids = new Set<string>();
			for (const key of keys) {
				const hit = artifactFromR2Key(key, support.groupPath, roots);
				if (hit) ids.add(hit.artifactId);
			}
			if (ids.size) await this.rebuildAffectedMetadata(support, ids);
		}
		for (const message of batch.messages) message.ack();
	}
}
