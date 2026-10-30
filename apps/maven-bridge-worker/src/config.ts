import { DEFAULT_CHECKSUM_INLINE_MAX_MB, DEFAULT_CHECKSUM_MAX_MB } from "./checksum";
import type { Env } from "./env";
import { normalizeSnapshotPrefix } from "../scripts/lifecycle.mjs";

export interface ProviderEntry {
	provider: string;
	groupId: string;
	upstream?: string;
}

export interface BridgeConfig {
	providers: ProviderEntry[];
	cacheTtlMinutes: number;
	/** seconds directory listings and maven-metadata.xml files are cached per location; 0 = not cached */
	metadataCacheTtlSeconds: number;
	/** seconds a 404 of the upstream is remembered per location; 0 = never */
	negativeCacheTtlSeconds: number;
	/** seconds */
	timeout: number;
	githubReleasesUrl: string;
	r2Mode: "off" | "serve";
	r2FillOnMiss: boolean;
	r2Prefix: string;
	/** key prefix (after r2Prefix) of stored SNAPSHOT files, ends with a slash */
	r2SnapshotPrefix: string;
	/** lower case hostnames using R2; empty = all */
	r2Hosts: string[];
	/** bytes; larger fill-on-miss files are stored in R2 before they are served */
	r2FillStreamMaxBytes: number;
	/** bytes; checksums are only computed for artifacts up to this size */
	checksumMaxBytes: number;
	/** bytes; larger checksums are computed in the background (404 until cached) */
	checksumInlineMaxBytes: number;
	flushToken: string;
}

export const DEFAULT_GITHUB_RELEASES_URL = "https://github.com/lucee/Lucee/releases/download/";
export const DEFAULT_R2_FILL_STREAM_MAX_MB = 32;
export const DEFAULT_NEGATIVE_CACHE_TTL_MINUTES = 5;
export const DEFAULT_METADATA_CACHE_TTL_MINUTES = 5;

export function defaultProviders(): ProviderEntry[] {
	return [
		{ provider: "https://www.forgebox.io", groupId: "io.forgebox" },
		{ provider: "https://extension.lucee.org", groupId: "org.lucee", upstream: "https://cdn.lucee.org/" }
	];
}

/** CFML val(): leading number of a string, 0 when there is none. */
export function val(value: unknown): number {
	const n = parseFloat(String(value ?? "").trim());
	return Number.isFinite(n) ? n : 0;
}

export function normalizeUpstreamUrl(upstream: string): string {
	const normalized = String(upstream ?? "").trim();
	if (!normalized.length) return "";
	return normalized.endsWith("/") ? normalized : normalized + "/";
}

/** Same formats as BridgeRegistry.parseProviders(). */
export function parseProviders(env: string): ProviderEntry[] {
	const raw = String(env ?? "").trim();
	if (!raw.length) return [];
	if (raw.startsWith("[")) {
		const parsed: unknown = JSON.parse(raw);
		if (!Array.isArray(parsed)) throw new Error("EXTENSION_PROVIDERS must be a JSON array");
		return normalizeProviderEntries(parsed);
	}
	return normalizeProviderEntries(raw.split(",").filter((s) => s.length));
}

function normalizeProviderEntries(entries: unknown[]): ProviderEntry[] {
	const providers: ProviderEntry[] = [];
	for (const entry of entries) {
		if (entry !== null && typeof entry === "object") {
			const e = lowerKeys(entry as Record<string, unknown>);
			const provider = String(e.provider ?? "").trim();
			const groupId = String(e.groupid ?? "").trim();
			if (provider.length && groupId.length) {
				const item: ProviderEntry = { provider, groupId };
				const upstream = String(e.upstream ?? "").trim();
				if (upstream.length) item.upstream = upstream;
				providers.push(item);
			}
			continue;
		}
		const pair = String(entry ?? "").trim();
		if (!pair.length) continue;
		const segments = pair.split("|").filter((s) => s.length);
		if (segments.length < 2) continue;
		const item: ProviderEntry = { provider: segments[0].trim(), groupId: segments[1].trim() };
		if (segments.length >= 3 && segments[2].trim().length) item.upstream = segments[2].trim();
		providers.push(item);
	}
	return providers;
}

function lowerKeys(obj: Record<string, unknown>): Record<string, unknown> {
	const out: Record<string, unknown> = {};
	for (const [k, v] of Object.entries(obj)) {
		const lower = k.toLowerCase();
		if (!(lower in out)) out[lower] = v;
	}
	return out;
}

/**
 * `hostname` is the request's host; R2 is switched off for hosts not listed in R2_HOSTS
 * (and for the cron, which has no host) when that list is not empty.
 */
export function readConfig(env: Env, hostname?: string): BridgeConfig {
	let providers: ProviderEntry[];
	const raw = String(env.EXTENSION_PROVIDERS ?? "").trim();
	if (raw.length) {
		providers = parseProviders(raw);
	} else {
		const provider = String(env.EXTENSION_PROVIDER ?? "").trim();
		const groupId = String(env.GROUP_ID ?? "").trim();
		providers =
			provider.length || groupId.length
				? [{ provider: provider || "https://extension.lucee.org", groupId: groupId || "org.lucee" }]
				: defaultProviders();
	}

	let cacheTtlMinutes = val(env.CACHE_TTL_MINUTES ?? 60);
	if (cacheTtlMinutes < 1) cacheTtlMinutes = 60;
	let timeout = val(env.TIMEOUT ?? 300);
	if (timeout < 1) timeout = 300;

	// an explicitly empty value disables the GitHub Releases lookup
	const githubReleasesUrl =
		env.GITHUB_RELEASES_URL !== undefined
			? normalizeUpstreamUrl(env.GITHUB_RELEASES_URL)
			: DEFAULT_GITHUB_RELEASES_URL;

	const mode = String(env.R2_MODE ?? "off").trim().toLowerCase();
	if (mode !== "off" && mode !== "serve" && mode !== "") {
		throw new Error(`Invalid R2_MODE [${env.R2_MODE}], expected "off" or "serve"`);
	}

	const streamMaxMb = env.R2_FILL_STREAM_MAX_MB === undefined || String(env.R2_FILL_STREAM_MAX_MB).trim() === ""
		? DEFAULT_R2_FILL_STREAM_MAX_MB
		: val(env.R2_FILL_STREAM_MAX_MB);
	if (streamMaxMb < 0) throw new Error(`Invalid R2_FILL_STREAM_MAX_MB [${env.R2_FILL_STREAM_MAX_MB}]`);

	const checksumMaxMb = env.CHECKSUM_MAX_MB === undefined || String(env.CHECKSUM_MAX_MB).trim() === ""
		? DEFAULT_CHECKSUM_MAX_MB
		: val(env.CHECKSUM_MAX_MB);
	if (checksumMaxMb < 0) throw new Error(`Invalid CHECKSUM_MAX_MB [${env.CHECKSUM_MAX_MB}]`);

	const checksumInlineMaxMb = env.CHECKSUM_INLINE_MAX_MB === undefined || String(env.CHECKSUM_INLINE_MAX_MB).trim() === ""
		? DEFAULT_CHECKSUM_INLINE_MAX_MB
		: val(env.CHECKSUM_INLINE_MAX_MB);
	if (checksumInlineMaxMb < 0) throw new Error(`Invalid CHECKSUM_INLINE_MAX_MB [${env.CHECKSUM_INLINE_MAX_MB}]`);

	const negativeTtlMinutes = env.NEGATIVE_CACHE_TTL_MINUTES === undefined || String(env.NEGATIVE_CACHE_TTL_MINUTES).trim() === ""
		? DEFAULT_NEGATIVE_CACHE_TTL_MINUTES
		: val(env.NEGATIVE_CACHE_TTL_MINUTES);
	if (negativeTtlMinutes < 0) throw new Error(`Invalid NEGATIVE_CACHE_TTL_MINUTES [${env.NEGATIVE_CACHE_TTL_MINUTES}]`);

	const metadataTtlMinutes = env.METADATA_CACHE_TTL_MINUTES === undefined || String(env.METADATA_CACHE_TTL_MINUTES).trim() === ""
		? DEFAULT_METADATA_CACHE_TTL_MINUTES
		: val(env.METADATA_CACHE_TTL_MINUTES);
	if (metadataTtlMinutes < 0) throw new Error(`Invalid METADATA_CACHE_TTL_MINUTES [${env.METADATA_CACHE_TTL_MINUTES}]`);

	const r2Hosts = String(env.R2_HOSTS ?? "")
		.split(",")
		.map((h) => h.trim().toLowerCase())
		.filter((h) => h.length);
	const r2ForHost = !r2Hosts.length || (hostname !== undefined && r2Hosts.includes(hostname.toLowerCase()));

	return {
		providers,
		cacheTtlMinutes,
		metadataCacheTtlSeconds: Math.floor(metadataTtlMinutes * 60),
		negativeCacheTtlSeconds: Math.floor(negativeTtlMinutes * 60),
		timeout,
		githubReleasesUrl,
		r2Mode: mode === "serve" && r2ForHost ? "serve" : "off",
		r2FillOnMiss: ["1", "true", "yes", "on"].includes(String(env.R2_FILL_ON_MISS ?? "").trim().toLowerCase()),
		r2Prefix: String(env.R2_PREFIX ?? ""),
		r2SnapshotPrefix: normalizeSnapshotPrefix(env.R2_SNAPSHOT_PREFIX),
		r2Hosts,
		r2FillStreamMaxBytes: Math.floor(streamMaxMb * 1024 * 1024),
		checksumMaxBytes: Math.floor(checksumMaxMb * 1024 * 1024),
		checksumInlineMaxBytes: Math.floor(checksumInlineMaxMb * 1024 * 1024),
		flushToken: String(env.FLUSH_TOKEN ?? "")
	};
}
