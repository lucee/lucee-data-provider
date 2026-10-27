// Port of BridgeProxy.cfc: maps a request path onto a Maven repository response.
import { cfJsonDate, compareNoCase, containsNoCase, encodeForHtml, startsWithNoCase } from "./cfml";
import { checksumOfText, splitChecksum, type ChecksumStore, type ChecksumType } from "./checksum";
import type { BridgeConfig } from "./config";
import { isUpstreamNotFound } from "./errors";
import { fetchAndFill, isFreshlyFilled, isImmutableArtifact, isStorableFile, revalidateFromSource, serveFromR2, type FillOptions } from "./r2";
import type { BridgeRegistry } from "./registry";
import { USER_AGENT } from "./store";
import type { BridgeSupport, ParsedPath, ParsedType } from "./support";

const TEXT = "text/plain; charset=utf-8";
const HTML = "text/html; charset=utf-8";
const XML = "application/xml; charset=utf-8";

const UPSTREAM_CONTENT_TYPES: ParsedType[] = [
	"group-index",
	"group-metadata",
	"artifact-index",
	"artifact-metadata",
	"version-index",
	"version-metadata"
];

export function textResponse(status: number, contentType: string, body: string): Response {
	return new Response(body, { status, headers: { "content-type": contentType } });
}

export function redirectResponse(location: string): Response {
	return new Response("", { status: 302, headers: { "content-type": TEXT, location } });
}

/** normalizeTargetPage() (Application.cfc) followed by normalizePath() (BridgeProxy.cfc) */
export function normalizeRequestPath(rawPath: string): string {
	let p = rawPath.replace(/\\/g, "/");
	while (p.includes("//")) p = p.replace(/\/\//g, "/");
	if (!p.startsWith("/")) p = "/" + p;
	if (p.startsWith("/index.cfm/")) p = p.slice(10);
	if (p.toLowerCase().endsWith("/index.cfm")) p = p.slice(0, -9);
	if (p.length > 1 && p.endsWith("/")) p = p.slice(0, -1);
	return p.length ? p : "/";
}

export interface ProxyContext {
	registry: BridgeRegistry;
	config: BridgeConfig;
	request: Request;
	waitUntil: (p: Promise<unknown>) => void;
	bucket?: R2Bucket;
	/** computes checksums the upstream does not have; undefined = never compute */
	checksums?: ChecksumStore;
	/** remembers revalidated SNAPSHOT objects in R2; undefined = revalidate once their fill time is older than the TTL */
	freshness?: R2Freshness;
}

export interface R2Freshness {
	isR2Fresh(key: string): Promise<boolean>;
	markR2Fresh(key: string, ttlSeconds: number): void;
}

export async function invokePath(ctx: ProxyContext, cleanPath: string): Promise<Response> {
	const resolved = ctx.registry.resolve(cleanPath);
	if (resolved.parsed.type === "unknown" || !resolved.support) {
		const prefixHtml = buildGroupPrefixIndexHtml(ctx.registry, cleanPath);
		if (prefixHtml.length) return textResponse(200, HTML, prefixHtml);
		return textResponse(404, TEXT, "Not found");
	}

	const support = resolved.support;
	const parsed = resolved.parsed;
	try {
		if (support.hasUpstream() && UPSTREAM_CONTENT_TYPES.includes(parsed.type)) {
			return await upstreamContentResponse(support, parsed);
		}
		switch (parsed.type) {
			case "group-index":
				return textResponse(200, HTML, await support.buildGroupIndexHtml());
			case "group-metadata":
				return textResponse(200, XML, await support.buildGroupMetadata());
			case "artifact-index":
				return textResponse(200, HTML, await support.buildArtifactIndexHtml(parsed.artifactId!));
			case "artifact-metadata":
				return textResponse(200, XML, await support.buildArtifactMetadata(parsed.artifactId!));
			case "version-index":
				return textResponse(200, HTML, support.buildVersionIndexHtml(parsed.artifactId!, parsed.version!));
			case "version-metadata":
				return textResponse(200, XML, await support.buildVersionMetadata(parsed.artifactId!, parsed.version!));
			case "artifact-file":
				return await artifactFileResponse(ctx, support, parsed);
			default:
				return textResponse(404, TEXT, "Not found");
		}
	} catch (e) {
		console.warn(`maven-bridge [${cleanPath}] failed`, e);
		return textResponse(404, TEXT, (e instanceof Error && e.message) || "Not found");
	}
}

/** R2 object key of an artifact file: the Maven layout, as used by the upstream and for fill-on-miss. */
export function r2KeyFor(config: BridgeConfig, support: BridgeSupport, parsed: ParsedPath): string {
	return config.r2Prefix + support.toUpstreamRelativePath(parsed);
}

/**
 * R2 keys looked up for an artifact file, in order: the Maven-layout key, then for
 * core files of upstream mirrors the legacy flat CDN name (bucket copies of cdn.lucee.org).
 */
export function r2KeysFor(config: BridgeConfig, support: BridgeSupport, parsed: ParsedPath): string[] {
	const keys = [r2KeyFor(config, support, parsed)];
	const legacy = support.hasUpstream() ? support.toUpstreamLegacyCorePath(parsed) : "";
	if (legacy.length) keys.push(config.r2Prefix + legacy);
	return keys;
}

/** URL of an upstream-mirror file at its source, "" when the source does not have it. */
async function upstreamTarget(support: BridgeSupport, parsed: ParsedPath): Promise<string> {
	// GitHub Releases (7.1+), then the Maven layout on the CDN, then the legacy flat CDN name
	if (support.isCoreFile(parsed)) return support.findCoreFileUrl(parsed);
	const upstreamPath = support.toUpstreamRelativePath(parsed);
	return (await support.io.upstreamResourceExists(support, upstreamPath)) ? support.upstreamUrl + upstreamPath : "";
}

function fillOptions(ctx: ProxyContext, support: BridgeSupport): FillOptions {
	return {
		timeoutSeconds: support.timeout,
		userAgent: USER_AGENT,
		streamMaxBytes: ctx.config.r2FillStreamMaxBytes,
		request: ctx.request
	};
}

async function artifactFileResponse(ctx: ProxyContext, support: BridgeSupport, parsed: ParsedPath): Promise<Response> {
	const key = r2KeyFor(ctx.config, support, parsed);
	const fileName = key.split("/").pop() ?? "";
	// with fill-on-miss, stored SNAPSHOT files of upstream mirrors are revalidated against their source
	const revalidate =
		support.hasUpstream() && ctx.config.r2FillOnMiss && !isImmutableArtifact(parsed.version ?? "", fileName) && isStorableFile(fileName);
	if (ctx.bucket) {
		for (const candidate of r2KeysFor(ctx.config, support, parsed)) {
			const fromR2 =
				revalidate && candidate === key
					? await mutableFromR2(ctx, support, parsed, key)
					: await serveFromR2(ctx.bucket, candidate, ctx.request);
			if (fromR2) return fromR2;
		}
	}

	// upstream mirrors serve files from the upstream repo only, never from the REST provider
	if (support.hasUpstream()) {
		const target = await upstreamTarget(support, parsed);
		if (!target.length) {
			// no checksum file upstream (e.g. core poms, RCs, snapshots): compute it from the artifact
			const checksum = splitChecksum(parsed);
			if (checksum) return computedChecksumResponse(ctx, support, checksum.artifact, checksum.type, key);
			return textResponse(404, TEXT, "Not found");
		}

		if (canFill(ctx) && (revalidate || shouldFill(ctx, parsed, key))) {
			const filled = await fetchAndFill(ctx.bucket!, key, target, ctx.waitUntil, fillOptions(ctx, support));
			if (filled) return filled;
		}
		return redirectResponse(target);
	}

	// the REST provider has no checksum files: compute them, never redirect them to the artifact
	const checksum = splitChecksum(parsed);
	if (checksum) return computedChecksumResponse(ctx, support, checksum.artifact, checksum.type, key);

	if (equalsExt(parsed, "pom")) {
		return textResponse(200, XML, await support.buildMinimalPom(parsed.artifactId!, parsed.version!));
	}
	const downloadUrl = await support.getDownloadUrl(parsed.artifactId!, parsed.version!);
	if (!downloadUrl.length) {
		return textResponse(
			404,
			TEXT,
			`No [${parsed.extension}] artifact for [${support.groupId}:${parsed.artifactId}:${parsed.version}]`
		);
	}
	return redirectResponse(downloadUrl);
}

/**
 * A stored SNAPSHOT file (mutable: the same name is published again): served from R2 while it
 * is fresh (stored or revalidated less than R2_REVALIDATE_MINUTES ago), otherwise revalidated
 * with a conditional GET of its source first. When the source cannot be reached the stored
 * copy is served. Null (redirect logic) when R2 has no copy, or the copy is stale and the request
 * is a HEAD or Range request, which never fetch the whole file.
 */
async function mutableFromR2(ctx: ProxyContext, support: BridgeSupport, parsed: ParsedPath, key: string): Promise<Response | null> {
	const bucket = ctx.bucket!;
	const stored = await bucket.head(key);
	if (!stored) return null;
	const ttlSeconds = ctx.config.r2RevalidateSeconds;
	if (isFreshlyFilled(stored, ttlSeconds * 1000) || (ttlSeconds > 0 && ctx.freshness && (await ctx.freshness.isR2Fresh(key)))) {
		return serveFromR2(bucket, key, ctx.request);
	}
	if (!canFill(ctx)) return null;

	const recorded = stored.customMetadata?.source ?? "";
	const source = /^https?:\/\//i.test(recorded) ? recorded : await upstreamTarget(support, parsed);
	if (!source.length) return null;

	const result = await revalidateFromSource(bucket, key, stored, source, ctx.waitUntil, fillOptions(ctx, support));
	switch (result.status) {
		case "not-modified":
			ctx.freshness?.markR2Fresh(key, ttlSeconds);
			return serveFromR2(bucket, key, ctx.request);
		case "replaced":
			return result.response;
		case "gone": {
			await bucket.delete(key);
			const res = textResponse(404, TEXT, "Not found");
			res.headers.set("cache-control", "no-store");
			return res;
		}
		default:
			// stale-if-error: the source is down, the stored copy is the best answer
			return serveFromR2(bucket, key, ctx.request);
	}
}

/**
 * Checksum of an artifact computed by the bridge (hex digest, as in a Maven checksum file):
 * upstream mirrors hash the artifact from R2 or its upstream URL, REST providers hash the
 * generated pom or the extension download. 404 (not cacheable) when the artifact is missing, too large or its checksum is still being computed.
 */
async function computedChecksumResponse(
	ctx: ProxyContext,
	support: BridgeSupport,
	artifact: ParsedPath,
	type: ChecksumType,
	checksumKey: string
): Promise<Response> {
	const store = ctx.checksums;
	if (!store || ctx.config.checksumMaxBytes <= 0) return textResponse(404, TEXT, "Not found");
	const fileName = support.toUpstreamRelativePath(artifact).split("/").pop() ?? "";
	const immutable = isImmutableArtifact(artifact.version ?? "", fileName);

	let value = "";
	if (support.hasUpstream()) {
		let inR2 = false;
		if (ctx.bucket) {
			for (const candidate of r2KeysFor(ctx.config, support, artifact)) {
				const fromR2 = await store.ofR2(ctx.bucket, candidate, type);
				if (fromR2 !== null) {
					value = fromR2;
					inR2 = true;
					break;
				}
			}
		}
		if (!inR2) {
			const url = await upstreamTarget(support, artifact);
			if (url.length) value = await store.ofUrl(url, type, immutable);
		}
	} else if (equalsExt(artifact, "pom")) {
		// same bytes as the generated pom served for this version
		value = await checksumOfText(await support.buildMinimalPom(artifact.artifactId!, artifact.version!), type);
	} else if (equalsExt(artifact, "lex")) {
		const downloadUrl = await support.getDownloadUrl(artifact.artifactId!, artifact.version!);
		if (downloadUrl.length) value = await store.ofUrl(downloadUrl, type, immutable);
	}
	if (!value.length) {
		// may be a checksum still being computed in the background: never let a cache keep this 404
		const res = textResponse(404, TEXT, "Not found");
		res.headers.set("cache-control", "no-store");
		return res;
	}

	if (support.hasUpstream() && shouldFill(ctx, artifact, checksumKey)) {
		ctx.waitUntil(
			ctx.bucket!.put(checksumKey, value, {
				httpMetadata: { contentType: "text/plain" },
				customMetadata: { source: "computed", filledAt: new Date().toISOString() }
			})
		);
	}
	return textResponse(200, TEXT, value);
}

function equalsExt(parsed: ParsedPath, ext: string): boolean {
	return (parsed.extension ?? "").toLowerCase() === ext;
}

/** fill-on-miss only for plain GETs, and only with a bucket in serve mode */
function canFill(ctx: ProxyContext): boolean {
	if (!ctx.bucket || !ctx.config.r2FillOnMiss) return false;
	return ctx.request.method === "GET" && !ctx.request.headers.has("range");
}

/** permanent fill (no revalidation): immutable files only */
function shouldFill(ctx: ProxyContext, parsed: ParsedPath, key: string): boolean {
	const fileName = key.split("/").pop() ?? "";
	return canFill(ctx) && isImmutableArtifact(parsed.version ?? "", fileName);
}

async function upstreamContentResponse(support: BridgeSupport, parsed: ParsedPath): Promise<Response> {
	// pass-through: what the upstream has is what we serve
	const relativePath = support.toUpstreamRelativePath(parsed);
	try {
		const content = await support.io.getUpstreamContent(support, relativePath);
		return textResponse(200, content.contentType, content.body);
	} catch (e) {
		if (!isUpstreamNotFound(e)) throw e;
	}
	return upstreamSynthesizedResponse(support, parsed);
}

async function upstreamSynthesizedResponse(support: BridgeSupport, parsed: ParsedPath): Promise<Response> {
	const has = (list: string[], v: string) => list.some((x) => x.toLowerCase() === v.toLowerCase());
	switch (parsed.type) {
		case "artifact-index":
			return textResponse(
				200,
				HTML,
				await support.buildArtifactIndexHtml(parsed.artifactId!, await support.listUpstreamVersions(parsed.artifactId!))
			);
		case "version-index":
			if (!has(await support.listUpstreamVersions(parsed.artifactId!), parsed.version!)) {
				return textResponse(404, TEXT, "Not found");
			}
			return textResponse(200, HTML, await support.buildUpstreamVersionIndexHtml(parsed.artifactId!, parsed.version!));
		case "version-metadata":
			if (
				containsNoCase(parsed.version!, "-SNAPSHOT") &&
				has(await support.listUpstreamVersions(parsed.artifactId!), parsed.version!)
			) {
				return textResponse(200, XML, await support.buildVersionMetadata(parsed.artifactId!, parsed.version!));
			}
			return textResponse(404, TEXT, "Not found");
		default:
			return textResponse(404, TEXT, "Not found");
	}
}

/** index for path segments above the group level (/org, /io) */
export function buildGroupPrefixIndexHtml(registry: BridgeRegistry, path: string): string {
	const children = new Map<string, string>();
	for (const support of registry.getSupports()) {
		const groupPath = "/" + support.groupPath;
		if (startsWithNoCase(groupPath, path + "/")) {
			const remainder = groupPath.slice(path.length + 1);
			const name = remainder.split("/").filter((s) => s.length)[0];
			if (name && !children.has(name.toLowerCase())) children.set(name.toLowerCase(), name);
		}
	}
	if (!children.size) return "";
	const names = [...children.values()].sort(compareNoCase);
	const title = path.slice(1);
	const html = [
		"<!DOCTYPE html>",
		`<html><head><title>${encodeForHtml(title)}</title></head><body>`,
		`<h1>${encodeForHtml(title)}</h1>`,
		"<pre>"
	];
	for (const name of names) {
		html.push(`<a href="${encodeForHtml(path)}/${encodeForHtml(name)}/">${encodeForHtml(name)}/</a>\n`);
	}
	html.push("</pre></body></html>");
	return html.join("\n");
}

export async function healthResponse(registry: BridgeRegistry, flushed: boolean): Promise<Response> {
	const providers: Record<string, unknown>[] = [];
	let artifactCount = 0;
	for (const support of registry.getSupports()) {
		if (support.hasUpstream()) {
			providers.push({
				upstream: support.upstreamUrl,
				mode: "upstream-mirror",
				groupId: support.groupId,
				provider: support.providerUrl
			});
		} else {
			const index = await support.getIndex();
			artifactCount += index.artifacts.size;
			providers.push({
				mode: "rest-provider",
				cachedAt: cfJsonDate(index.cachedAt),
				artifactCount: index.artifacts.size,
				groupId: support.groupId,
				provider: support.providerUrl
			});
		}
	}
	const body: Record<string, unknown> = { status: "ok", artifactCount, providers };
	if (flushed) body.flushed = true;
	return textResponse(200, "application/json; charset=utf-8", JSON.stringify(body));
}
