import type { Env } from "./env";

export interface Config {
	extensionsCdnUrl: string;
	coreCdnUrl: string;
	/** <coreCdnUrl><S3_EXTENSIONS_MAVEN_PATH>, empty when there is no Maven layout in the core bucket */
	mavenCdnUrl: string;
	metaUrl: string;
	mavenStateUrl: string;
	releaseRepos: string[];
	snapshotRepos: string[];
	mixedRepos: string[];
	timeoutMs: number;
	flatFallback: boolean;
	mavenOnlyMinCore: string;
	discoveryMax: number;
	indexTtlMs: number;
	metadataCacheSeconds: number;
	flushToken: string;
}

export function withTrailingSlash(path: string): string {
	return path.endsWith("/") ? path : path + "/";
}

/** an environment variable of true or false, the fallback when it is not set or not a boolean (like _envBoolean()) */
export function envBoolean(value: string | undefined, fallback: boolean): boolean {
	const parsed = parseCfBoolean((value ?? "").trim());
	return parsed ?? fallback;
}

/** CFML boolean casting: true/false, yes/no and numbers; undefined when it is not a boolean */
export function parseCfBoolean(value: string): boolean | undefined {
	const v = value.trim().toLowerCase();
	if (v === "true" || v === "yes") return true;
	if (v === "false" || v === "no") return false;
	if (v.length && Number.isFinite(Number(v))) return Number(v) !== 0;
	return undefined;
}

function envNumber(value: string | undefined, fallback: number): number {
	if (value === undefined || value.trim() === "") return fallback;
	const n = Number(value);
	return Number.isFinite(n) && n >= 0 ? n : fallback;
}

/** comma separated urls, "none" for none, each with a trailing slash, no duplicates (like _mavenRepos() and _normaliseRepos()) */
export function mavenRepos(value: string): string[] {
	if (value.trim() === "none") return [];
	const result: string[] = [];
	for (const raw of value.split(",")) {
		const repo = raw.trim();
		if (!repo.length) continue;
		const normalised = withTrailingSlash(repo);
		if (!result.includes(normalised)) result.push(normalised);
	}
	return result;
}

export function readConfig(env: Env): Config {
	const extensionsCdnUrl = withTrailingSlash((env.S3_EXTENSIONS_CDN_URL ?? "https://ext.lucee.org/").trim());
	const coreCdnUrl = withTrailingSlash((env.S3_CORE_CDN_URL ?? "https://cdn.lucee.org/").trim());
	const mavenPath = (env.S3_EXTENSIONS_MAVEN_PATH ?? "org/lucee/").trim();
	const reposEnabled = envBoolean(env.EXTENSIONS_MAVEN_REPOS_ENABLED, true);

	return {
		extensionsCdnUrl,
		coreCdnUrl,
		mavenCdnUrl: mavenPath.length ? coreCdnUrl + withTrailingSlash(mavenPath.replace(/^\/+/, "")) : "",
		metaUrl: (env.EXTENSIONS_META_URL ?? "").trim() || extensionsCdnUrl + "extensions.json",
		mavenStateUrl: (env.EXTENSIONS_MAVEN_STATE_URL ?? "").trim() || extensionsCdnUrl + "extensions-maven.json",
		releaseRepos: reposEnabled
			? mavenRepos(env.EXTENSIONS_MAVEN_REPOS_RELEASES ?? env.LUCEE_MVN_REPO_RELEASES ?? "https://repo1.maven.org/maven2/")
			: [],
		snapshotRepos: reposEnabled
			? mavenRepos(env.EXTENSIONS_MAVEN_REPOS_SNAPSHOTS ?? env.LUCEE_MVN_REPO_SNAPSHOTS ?? "https://central.sonatype.com/repository/maven-snapshots/")
			: [],
		mixedRepos: reposEnabled
			? mavenRepos(env.EXTENSIONS_MAVEN_REPOS_MIXED ?? env.LUCEE_MVN_REPO_MIXED ?? "https://maven.lucee-services.com/")
			: [],
		timeoutMs: envNumber(env.EXTENSIONS_MAVEN_TIMEOUT, 20) * 1000,
		flatFallback: envBoolean(env.EXTENSIONS_FLAT_S3_FALLBACK, true),
		mavenOnlyMinCore: (env.EXTENSIONS_MAVEN_ONLY_MIN_CORE ?? "").trim(),
		discoveryMax: Math.floor(envNumber(env.EXTENSIONS_DISCOVERY_MAX, 10)),
		indexTtlMs: envNumber(env.INDEX_TTL_MINUTES, 15) * 60_000,
		metadataCacheSeconds: Math.floor(envNumber(env.METADATA_CACHE_SECONDS, 300)),
		flushToken: (env.FLUSH_TOKEN ?? "").trim()
	};
}
