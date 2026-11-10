/**
 * Bindings and settings of the extension provider worker. The settings mirror the environment
 * variables of apps/updateserver/Application.cfc, so both are configured the same way.
 */
export interface Env {
	/**
	 * KV namespace for the extension index (built by the cron and on demand), the logos, and what the
	 * Maven discovery found out. Optional: without it the index is built per isolate and kept in memory.
	 */
	EXT_CACHE?: KVNamespace;

	/** base url of the flat extension files, the fallback of a download. Default https://ext.lucee.org/ */
	S3_EXTENSIONS_CDN_URL?: string;
	/** base url of the core bucket, which holds the Maven layout of the extensions. Default https://cdn.lucee.org/ */
	S3_CORE_CDN_URL?: string;
	/** path of the extensions in the Maven layout of the core bucket. Default org/lucee/, empty: no such layout */
	S3_EXTENSIONS_MAVEN_PATH?: string;
	/**
	 * The extension meta the CFML provider maintains (<S3_EXTENSIONS_ROOT>/extensions.json), read over http.
	 * Default <S3_EXTENSIONS_CDN_URL>extensions.json
	 */
	EXTENSIONS_META_URL?: string;
	/** What the CFML provider found out about the Maven files. Default <S3_EXTENSIONS_CDN_URL>extensions-maven.json */
	EXTENSIONS_MAVEN_STATE_URL?: string;

	/** "false": no Maven repositories (the Maven layout of the core bucket is still used) */
	EXTENSIONS_MAVEN_REPOS_ENABLED?: string;
	/** comma separated repository urls, "none" for none (EXTENSIONS_MAVEN_REPOS_* first, then LUCEE_MVN_REPO_*) */
	EXTENSIONS_MAVEN_REPOS_RELEASES?: string;
	EXTENSIONS_MAVEN_REPOS_SNAPSHOTS?: string;
	EXTENSIONS_MAVEN_REPOS_MIXED?: string;
	LUCEE_MVN_REPO_RELEASES?: string;
	LUCEE_MVN_REPO_SNAPSHOTS?: string;
	LUCEE_MVN_REPO_MIXED?: string;
	/** seconds, listing and metadata requests. Default 20 */
	EXTENSIONS_MAVEN_TIMEOUT?: string;

	/** "false": only serve what is served from a Maven source (LDEV-6795). Default true */
	EXTENSIONS_FLAT_S3_FALLBACK?: string;
	/** minimum core version for extensions packaged for Maven (LDEV-6795). Default empty */
	EXTENSIONS_MAVEN_ONLY_MIN_CORE?: string;

	/**
	 * How many extension files of the Maven sources that the extension meta does not have yet are read
	 * (manifest and logo, with range requests) per index build. Default 10, 0 = off.
	 */
	EXTENSIONS_DISCOVERY_MAX?: string;
	/** minutes after which the index is rebuilt in the background on a request. Default 15 */
	INDEX_TTL_MINUTES?: string;
	/** seconds upstream metadata (maven-metadata.xml, listings, extensions.json) is cached at the edge. Default 300 */
	METADATA_CACHE_SECONDS?: string;

	/** Secret: required for flush=true, /updateCache and /reset. Without it they are disabled. */
	FLUSH_TOKEN?: string;
}
