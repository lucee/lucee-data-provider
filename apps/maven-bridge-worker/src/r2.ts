// Serving artifacts from the R2 bucket, and optional lazy fill on a miss.
import { containsNoCase } from "./cfml";

const ARTIFACT_TYPES: Record<string, string> = {
	jar: "application/java-archive",
	war: "application/java-archive",
	zip: "application/zip",
	pom: "application/xml; charset=utf-8",
	xml: "application/xml; charset=utf-8",
	html: "text/html; charset=utf-8",
	md5: "text/plain; charset=utf-8",
	sha1: "text/plain; charset=utf-8",
	sha256: "text/plain; charset=utf-8",
	sha512: "text/plain; charset=utf-8",
	asc: "text/plain; charset=utf-8"
};

export function contentTypeForArtifact(key: string): string {
	const ext = key.toLowerCase().split("/").pop()!.split(".").pop() ?? "";
	return ARTIFACT_TYPES[ext] ?? "application/octet-stream";
}

function objectHeaders(obj: R2Object, key: string): Headers {
	const headers = new Headers();
	obj.writeHttpMetadata(headers);
	if (!headers.has("content-type")) headers.set("content-type", contentTypeForArtifact(key));
	headers.set("etag", obj.httpEtag);
	headers.set("last-modified", obj.uploaded.toUTCString());
	headers.set("accept-ranges", "bytes");
	return headers;
}

function hasConditional(request: Request): boolean {
	return request.headers.has("if-none-match") || request.headers.has("if-modified-since");
}

/**
 * Streams the object stored under `key` (GET with Range/conditional support, or HEAD).
 * Returns null when the bucket has no such object.
 */
export async function serveFromR2(bucket: R2Bucket, key: string, request: Request): Promise<Response | null> {
	if (request.method === "HEAD") {
		const head = await bucket.head(key);
		if (!head) return null;
		const headers = objectHeaders(head, key);
		headers.set("content-length", String(head.size));
		return new Response(null, { status: 200, headers });
	}

	let obj: R2Object | R2ObjectBody | null;
	try {
		obj = await bucket.get(key, { onlyIf: request.headers, range: request.headers });
	} catch (e) {
		// unsatisfiable range
		const head = await bucket.head(key);
		if (!head) return null;
		if (!request.headers.has("range")) throw e;
		const headers = objectHeaders(head, key);
		headers.set("content-range", `bytes */${head.size}`);
		return new Response(null, { status: 416, headers });
	}
	if (!obj) return null;

	const headers = objectHeaders(obj, key);
	if (!("body" in obj)) {
		// a precondition (If-None-Match, If-Match, ...) did not pass
		return new Response(null, { status: hasConditional(request) ? 304 : 412, headers });
	}

	const range = obj.range as { offset?: number; length?: number; suffix?: number } | undefined;
	if (range && request.headers.has("range")) {
		let offset: number;
		let length: number;
		if (range.suffix !== undefined) {
			length = Math.min(range.suffix, obj.size);
			offset = obj.size - length;
		} else {
			offset = range.offset ?? 0;
			length = range.length ?? obj.size - offset;
		}
		headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${obj.size}`);
		headers.set("content-length", String(length));
		return new Response(obj.body, { status: 206, headers });
	}
	headers.set("content-length", String(obj.size));
	return new Response(obj.body, { status: 200, headers });
}

/**
 * Only immutable files may be stored permanently: no snapshots, no metadata,
 * no indexes.
 */
export function isImmutableArtifact(version: string, fileName: string): boolean {
	if (containsNoCase(version, "-SNAPSHOT") || containsNoCase(fileName, "SNAPSHOT")) return false;
	return isStorableFile(fileName);
}

/**
 * Files that may be kept in R2 at all: everything but metadata and indexes, which the
 * worker passes through (and caches) separately. SNAPSHOT files are storable, but are
 * revalidated against their source (see revalidateFromSource).
 */
export function isStorableFile(fileName: string): boolean {
	const lower = fileName.toLowerCase();
	return !(lower.startsWith("maven-metadata") || lower.endsWith(".html"));
}

/**
 * A stored mutable (SNAPSHOT) object is fresh for `ttlMs` after it was stored; a
 * successful revalidation extends that elsewhere (Cache API marker).
 */
export function isFreshlyFilled(obj: R2Object, ttlMs: number, now = Date.now()): boolean {
	if (ttlMs <= 0) return false;
	const filledAt = Date.parse(obj.customMetadata?.filledAt ?? "");
	return Number.isFinite(filledAt) && now - filledAt < ttlMs;
}

export interface FillOptions {
	/** seconds until the source has to answer with headers */
	timeoutSeconds: number;
	userAgent: string;
	/** files up to this size are streamed to the client while they are stored; larger ones are stored first */
	streamMaxBytes: number;
	request: Request;
}

/** GET of the source, answer headers within the timeout (the body may take longer). Null when unreachable. */
async function fetchSource(sourceUrl: string, options: FillOptions, extraHeaders: Record<string, string> = {}): Promise<Response | null> {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`Timeout fetching [${sourceUrl}]`)), options.timeoutSeconds * 1000);
	try {
		return await fetch(sourceUrl, {
			redirect: "follow",
			headers: { "user-agent": options.userAgent, "accept-encoding": "identity", ...extraHeaders },
			signal: controller.signal
		});
	} catch (e) {
		console.warn(`fetching [${sourceUrl}] failed`, e);
		return null;
	} finally {
		clearTimeout(timer);
	}
}

/**
 * Lazy migration: fetch `sourceUrl` and store a copy in R2 under `key`.
 *
 * Returns null when the source did not answer 200 or could not be reached (the
 * caller falls back to the redirect logic).
 */
export async function fetchAndFill(
	bucket: R2Bucket,
	key: string,
	sourceUrl: string,
	waitUntil: (p: Promise<unknown>) => void,
	options: FillOptions
): Promise<Response | null> {
	const upstream = await fetchSource(sourceUrl, options);
	if (!upstream) return null;
	if (upstream.status !== 200 || !upstream.body) {
		await upstream.body?.cancel();
		return null;
	}
	return storeAndServe(bucket, key, sourceUrl, upstream, waitUntil, options);
}

/**
 * Stores a 200 answer of the source in R2 and answers the client.
 *
 * Files up to `streamMaxBytes` are streamed to the client and stored at the same
 * time (tee). A tee buffers what the slower branch has not read yet, so for larger
 * files a slow client could hold most of the file in memory; those are stored
 * first and then served from R2. Answers without a usable length are streamed
 * without being stored. Null when storing a large file failed.
 */
async function storeAndServe(
	bucket: R2Bucket,
	key: string,
	sourceUrl: string,
	upstream: Response,
	waitUntil: (p: Promise<unknown>) => void,
	options: FillOptions
): Promise<Response | null> {
	const contentType = contentTypeForArtifact(key);
	const headers = new Headers({ "content-type": contentType });
	const etag = upstream.headers.get("etag");
	const lastModified = upstream.headers.get("last-modified");
	if (etag) headers.set("etag", etag);
	if (lastModified) headers.set("last-modified", lastModified);

	// a decoded body no longer matches content-length, and R2 needs the exact length
	const encoding = (upstream.headers.get("content-encoding") ?? "").trim().toLowerCase();
	const length = encoding === "" || encoding === "identity" ? Number(upstream.headers.get("content-length") ?? "") : NaN;
	if (!Number.isSafeInteger(length) || length <= 0) {
		return new Response(upstream.body, { status: 200, headers });
	}

	// the source's validators are kept for conditional revalidation of mutable files
	const customMetadata: Record<string, string> = { source: sourceUrl, filledAt: new Date().toISOString() };
	if (etag) customMetadata.sourceEtag = etag;
	if (lastModified) customMetadata.sourceLastModified = lastModified;
	const putOptions: R2PutOptions = { httpMetadata: { contentType }, customMetadata };

	if (length > options.streamMaxBytes) {
		try {
			// FixedLengthStream fails the put when the source ends early or sends more
			await bucket.put(key, upstream.body!.pipeThrough(new FixedLengthStream(length)), putOptions);
		} catch (e) {
			console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
			return null;
		}
		return serveFromR2(bucket, key, options.request);
	}

	headers.set("content-length", String(length));
	headers.set("accept-ranges", "bytes");
	// both tee branches of a fetch body keep its known length, which R2 needs for a streamed put
	const [toClient, toBucket] = upstream.body!.tee();
	waitUntil(
		bucket.put(key, toBucket, putOptions).catch((e) => {
			console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
		})
	);
	return new Response(toClient, { status: 200, headers });
}

export type RevalidateResult =
	/** the stored copy is current (304) */
	| { status: "not-modified" }
	/** the source has a new version: it was stored and is in `response` */
	| { status: "replaced"; response: Response }
	/** the source no longer has the file (404/410) */
	| { status: "gone" }
	/** the source failed or could not be reached: the stored copy may be served */
	| { status: "error" };

/**
 * Conditional GET of the source of a stored mutable object, using the validators
 * stored with it (ETag, then Last-Modified). A 200 replaces the stored object.
 */
export async function revalidateFromSource(
	bucket: R2Bucket,
	key: string,
	stored: R2Object,
	sourceUrl: string,
	waitUntil: (p: Promise<unknown>) => void,
	options: FillOptions
): Promise<RevalidateResult> {
	const conditional: Record<string, string> = {};
	const etag = stored.customMetadata?.sourceEtag;
	const lastModified = stored.customMetadata?.sourceLastModified;
	if (etag) conditional["if-none-match"] = etag;
	else if (lastModified) conditional["if-modified-since"] = lastModified;

	const upstream = await fetchSource(sourceUrl, options, conditional);
	if (!upstream) return { status: "error" };
	if (upstream.status === 304) {
		await upstream.body?.cancel();
		return { status: "not-modified" };
	}
	if (upstream.status === 404 || upstream.status === 410) {
		await upstream.body?.cancel();
		return { status: "gone" };
	}
	if (upstream.status !== 200 || !upstream.body) {
		await upstream.body?.cancel();
		console.warn(`revalidating [${key}] against [${sourceUrl}]: HTTP ${upstream.status}`);
		return { status: "error" };
	}
	const response = await storeAndServe(bucket, key, sourceUrl, upstream, waitUntil, options);
	return response ? { status: "replaced", response } : { status: "error" };
}
