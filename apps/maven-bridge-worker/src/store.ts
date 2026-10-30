// Runtime I/O for the supports: replaces the server-scope / file cache of the
// CFML bridge with Workers KV (provider indexes, and upstream group files as a fallback,
// kept fresh by the hourly cron) and the Cache API (everything else, TTL based).
// Directory listings and maven-metadata.xml use the short METADATA_CACHE_TTL_MINUTES.
import type { BridgeConfig } from "./config";
import type { Env } from "./env";
import { BridgeError, UPSTREAM_NOT_FOUND } from "./errors";
import { buildIndex, deserializeIndex, serializeIndex, type RestIndex, type StoredIndex } from "./rest-index";
import { contentTypeForPath, type BridgeSupport, type SupportIo, type UpstreamContent } from "./support";

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
			const index = deserializeIndex(stored);
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
					for (const rel of groupLevelFiles(support)) await this.refreshUpstreamFile(support, rel);
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
}
