export interface Env {
	/** KV namespace for provider indexes, upstream group files and the cache generation. */
	BRIDGE_CACHE: KVNamespace;
	/** Optional R2 bucket holding the artifacts (served when R2_MODE = "serve"). */
	ARTIFACTS?: R2Bucket;

	/** Pipe list "provider|groupId|upstream,..." or a JSON array (see README). */
	EXTENSION_PROVIDERS?: string;
	/** Legacy single provider mode. */
	EXTENSION_PROVIDER?: string;
	GROUP_ID?: string;
	CACHE_TTL_MINUTES?: string;
	/** Timeout in seconds for upstream/provider requests. */
	TIMEOUT?: string;
	/** Base URL of the GitHub Release assets for core files; empty disables the lookup. */
	GITHUB_RELEASES_URL?: string;
	/** "off" (default) or "serve": serve artifacts found in the R2 bucket. */
	R2_MODE?: string;
	/**
	 * "true": in serve mode, an immutable artifact that is not in R2 yet is fetched
	 * from its source, streamed to the client and stored in R2 (lazy migration).
	 */
	R2_FILL_ON_MISS?: string;
	/** Optional key prefix inside the R2 bucket. */
	R2_PREFIX?: string;
	/** Secret: required for ?flush=true. When unset, flushing is disabled. */
	FLUSH_TOKEN?: string;
}
