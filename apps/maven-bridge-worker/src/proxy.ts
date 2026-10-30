// Port of BridgeProxy.cfc: maps a request path onto a Maven repository response.
import { cfJsonDate, compareNoCase, containsNoCase, encodeForHtml, startsWithNoCase } from "./cfml";
import { checksumOfText, splitChecksum, type ChecksumStore, type ChecksumType } from "./checksum";
import type { BridgeConfig } from "./config";
import { isUpstreamNotFound } from "./errors";
import { fetchAndFill, fillOnly, isImmutableArtifact, isStorableFile, serveFromR2, type FillOptions } from "./r2";
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

/**
 * SNAPSHOT files the worker stores in R2: kept under their own key prefix (R2_SNAPSHOT_PREFIX)
 * so the bucket's lifecycle rule can expire them. Like every stored file they are served as
 * stored and never fetched from their source again (every build has its own file name).
 */
export function isSnapshotFile(parsed: ParsedPath, fileName: string): boolean {
	return !isImmutableArtifact(parsed.version ?? "", fileName) && isStorableFile(fileName);
}

/** R2 key of an artifact file in the plain Maven layout of the upstream. */
export function r2MavenKeyFor(config: BridgeConfig, support: BridgeSupport, parsed: ParsedPath): string {
	return config.r2Prefix + support.toUpstreamRelativePath(parsed);
}

/**
 * R2 object key fill-on-miss writes for an artifact file: the Maven layout, for SNAPSHOT
 * files below R2_SNAPSHOT_PREFIX.
 */
export function r2KeyFor(config: BridgeConfig, support: BridgeSupport, parsed: ParsedPath): string {
	const rel = support.toUpstreamRelativePath(parsed);
	const prefix = isSnapshotFile(parsed, rel.split("/").pop() ?? "") ? config.r2Prefix + config.r2SnapshotPrefix : config.r2Prefix;
	return prefix + rel;
}

/**
 * R2 keys looked up for an artifact file, in order: the key fill-on-miss writes, for SNAPSHOT
 * files then the plain Maven-layout key (bulk copies), then for core files of upstream mirrors
 * the legacy flat CDN name (bucket copies of cdn.lucee.org).
 */
export function r2KeysFor(config: BridgeConfig, support: BridgeSupport, parsed: ParsedPath): string[] {
	const keys = [r2KeyFor(config, support, parsed)];
	const maven = r2MavenKeyFor(config, support, parsed);
	if (maven !== keys[0]) keys.push(maven);
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
	// a stored file is served as stored: it is never checked against its source again
	if (ctx.bucket) {
		for (const candidate of r2KeysFor(ctx.config, support, parsed)) {
			const fromR2 = await serveFromR2(ctx.bucket, candidate, ctx.request);
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

		if (shouldFill(ctx, key)) {
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
 * Checksum of an artifact computed by the bridge (hex digest, as in a Maven checksum file):
 * upstream mirrors hash the artifact from R2 or its upstream URL, REST providers hash the
 * generated pom or the extension download. 404 (not cacheable) when the artifact is missing, too large or its checksum is still being computed.
 *
 * An artifact of an upstream mirror that is not in R2 yet is downloaded once into R2 (when fill-on-miss
 * is on) and hashed from there, so the file is not downloaded a second time when it is requested.
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
			if (url.length) value = await checksumOfUpstream(ctx, support, store, artifact, url, type);
		}
	} else if (equalsExt(artifact, "pom")) {
		// same bytes as the generated pom served for this version
		value = await checksumOfText(await support.buildMinimalPom(artifact.artifactId!, artifact.version!), type);
	} else if (equalsExt(artifact, "lex")) {
		const downloadUrl = await support.getDownloadUrl(artifact.artifactId!, artifact.version!);
		if (downloadUrl.length) value = await store.ofUrl(downloadUrl, type);
	}
	if (!value.length) {
		// may be a checksum still being computed in the background: never let a cache keep this 404
		const res = textResponse(404, TEXT, "Not found");
		res.headers.set("cache-control", "no-store");
		return res;
	}

	if (support.hasUpstream() && shouldFill(ctx, checksumKey)) {
		ctx.waitUntil(
			ctx.bucket!.put(checksumKey, value, {
				httpMetadata: { contentType: "text/plain" },
				customMetadata: { source: "computed", filledAt: new Date().toISOString() }
			})
		);
	}
	return textResponse(200, TEXT, value);
}

/** checksum of an artifact of an upstream mirror that R2 does not have: stored in R2 by one download, else hashed from the source */
async function checksumOfUpstream(
	ctx: ProxyContext,
	support: BridgeSupport,
	store: ChecksumStore,
	artifact: ParsedPath,
	url: string,
	type: ChecksumType
): Promise<string> {
	const key = r2KeyFor(ctx.config, support, artifact);
	const fileName = key.split("/").pop() ?? "";
	if (!ctx.bucket || !ctx.config.r2FillOnMiss || !isStorableFile(fileName)) return store.ofUrl(url, type);
	const filled = await fillOnly(ctx.bucket, key, url, { ...fillOptions(ctx, support), maxBytes: ctx.config.checksumMaxBytes });
	switch (filled) {
		case "stored":
			return (await store.ofR2(ctx.bucket, key, type)) ?? "";
		case "unsupported":
			// the source states no length, so it cannot be stored (nothing was downloaded)
			return store.ofUrl(url, type);
		default:
			// failed or too large: the source was answered once already, not asked again for the same request
			return "";
	}
}

function equalsExt(parsed: ParsedPath, ext: string): boolean {
	return (parsed.extension ?? "").toLowerCase() === ext;
}

/** fill-on-miss only for plain GETs, and only with a bucket in serve mode */
function canFill(ctx: ProxyContext): boolean {
	if (!ctx.bucket || !ctx.config.r2FillOnMiss) return false;
	return ctx.request.method === "GET" && !ctx.request.headers.has("range");
}

/** every storable file is stored once and served from R2 from then on */
function shouldFill(ctx: ProxyContext, key: string): boolean {
	return canFill(ctx) && isStorableFile(key.split("/").pop() ?? "");
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
