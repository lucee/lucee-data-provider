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
	/**
	 * Directory listings (index.html) and maven-metadata.xml files are cached per location for
	 * this many minutes, then read again from the upstream. Default 5, 0 = not cached.
	 */
	METADATA_CACHE_TTL_MINUTES?: string;
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
	/**
	 * Fill-on-miss files up to this size (MB) are streamed to the client while they are
	 * stored; larger files are stored first, then served from R2. Default 32, 0 = always store first.
	 */
	R2_FILL_STREAM_MAX_MB?: string;
	/**
	 * Checksums (.sha1, .md5, ...) the upstream does not have are computed from the artifact,
	 * for artifacts up to this size (MB); larger ones answer 404. Default 128, 0 = never compute.
	 */
	CHECKSUM_MAX_MB?: string;
	/**
	 * Computed checksums of artifacts up to this size (MB) are hashed inside the request; larger
	 * ones are hashed in the background and answer 404 until they are cached. Default 16, 0 = always background.
	 */
	CHECKSUM_INLINE_MAX_MB?: string;
	/**
	 * Stored SNAPSHOT files are served from R2 for this many minutes after they were stored
	 * or last revalidated, then revalidated against their source. Default 5, 0 = on every request.
	 */
	R2_REVALIDATE_MINUTES?: string;
	/**
	 * Comma separated hostnames that use R2 (R2_MODE, R2_FILL_ON_MISS); other hostnames
	 * and the cron behave as with R2_MODE = "off". Empty = every hostname.
	 */
	R2_HOSTS?: string;
	/** Optional key prefix inside the R2 bucket. */
	R2_PREFIX?: string;
	/** Secret: required for ?flush=true. When unset, flushing is disabled. */
	FLUSH_TOKEN?: string;
}
