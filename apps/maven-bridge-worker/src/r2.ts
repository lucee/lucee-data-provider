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
 * Release and RC files: the name of such a file never gets other content, they are stored
 * under their plain Maven key. SNAPSHOT files are immutable by name too (every build has a
 * unique build number in its file name), but they are stored under the SNAPSHOT prefix, where
 * a lifecycle rule expires them; nothing here ever asks the source for them again.
 */
export function isImmutableArtifact(version: string, fileName: string): boolean {
	if (containsNoCase(version, "-SNAPSHOT") || containsNoCase(fileName, "SNAPSHOT")) return false;
	return isStorableFile(fileName);
}

/**
 * Files that may be kept in R2 at all: everything but metadata and indexes, which the
 * worker passes through (and caches) separately. A stored file is never revalidated.
 */
export function isStorableFile(fileName: string): boolean {
	const lower = fileName.toLowerCase();
	return !(lower.startsWith("maven-metadata") || lower.endsWith(".html"));
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
async function fetchSource(sourceUrl: string, options: FillOptions): Promise<Response | null> {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`Timeout fetching [${sourceUrl}]`)), options.timeoutSeconds * 1000);
	try {
		return await fetch(sourceUrl, {
			redirect: "follow",
			headers: { "user-agent": options.userAgent, "accept-encoding": "identity" },
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
 * Downloads of the same key that are running in this isolate. A second request for a file
 * that is being stored waits for that download instead of starting its own; the promise
 * resolves true once the object is in R2, false when it was not stored.
 */
const inflight = new Map<string, Promise<boolean>>();

/** a download this isolate started for `key`; `settle` must be called exactly once, when the object is stored or the attempt failed */
function startFill(key: string): { settle: (stored: boolean) => void } {
	let resolve!: (stored: boolean) => void;
	const promise = new Promise<boolean>((r) => (resolve = r));
	inflight.set(key, promise);
	let settled = false;
	return {
		settle(stored) {
			if (settled) return;
			settled = true;
			if (inflight.get(key) === promise) inflight.delete(key);
			resolve(stored);
		}
	};
}

/**
 * The download another request of this isolate runs for `key` (resolves to whether the object got stored,
 * false after `timeoutSeconds`); undefined when there is none. Not async on purpose: the caller starts its
 * own fill in the same tick, so two requests cannot both start one.
 */
function pendingFill(key: string, timeoutSeconds: number): Promise<boolean> | undefined {
	const pending = inflight.get(key);
	if (!pending) return undefined;
	let timer: ReturnType<typeof setTimeout> | null = null;
	const timeout = new Promise<boolean>(
		(r) =>
			(timer = setTimeout(() => {
				// a download that never reports back must not block later requests for the file
				if (inflight.get(key) === pending) inflight.delete(key);
				r(false);
			}, timeoutSeconds * 1000))
	);
	return Promise.race([pending, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Lazy migration: fetch `sourceUrl` and store a copy in R2 under `key`.
 *
 * A request for a file that another request of this isolate is storing right now waits for
 * that download and is then served from R2. Returns null when the source did not answer 200
 * or could not be reached (the caller falls back to the redirect logic).
 */
export async function fetchAndFill(
	bucket: R2Bucket,
	key: string,
	sourceUrl: string,
	waitUntil: (p: Promise<unknown>) => void,
	options: FillOptions
): Promise<Response | null> {
	const joining = pendingFill(key, options.timeoutSeconds);
	if (joining) return (await joining) ? serveFromR2(bucket, key, options.request) : null;

	const fill = startFill(key);
	try {
		const upstream = await fetchSource(sourceUrl, options);
		if (!upstream) {
			fill.settle(false);
			return null;
		}
		if (upstream.status !== 200 || !upstream.body) {
			await upstream.body?.cancel();
			fill.settle(false);
			return null;
		}
		return await storeAndServe(bucket, key, sourceUrl, upstream, waitUntil, options, fill.settle);
	} catch (e) {
		fill.settle(false);
		throw e;
	}
}

export type FillOnlyResult =
	/** the object is in R2 (stored now, or by a download that was already running) */
	| "stored"
	/** the source answered, but the object could not be stored (not found, error, R2 failure) */
	| "failed"
	/** the source did not state a usable length, nothing was downloaded */
	| "unsupported"
	/** the source is larger than `maxBytes`, nothing was downloaded */
	| "too-large";

/**
 * Stores `sourceUrl` in R2 without serving it, for requests that only need the content to
 * be there (a checksum computed from the stored object). Shares the downloads of
 * fetchAndFill.
 */
export async function fillOnly(
	bucket: R2Bucket,
	key: string,
	sourceUrl: string,
	options: FillOptions & { /** larger sources are not downloaded */ maxBytes?: number }
): Promise<FillOnlyResult> {
	const joining = pendingFill(key, options.timeoutSeconds);
	if (joining) return (await joining) ? "stored" : "failed";

	const fill = startFill(key);
	try {
		const upstream = await fetchSource(sourceUrl, options);
		if (!upstream || upstream.status !== 200 || !upstream.body) {
			await upstream?.body?.cancel();
			fill.settle(false);
			return "failed";
		}
		const length = usableLength(upstream);
		if (length === undefined) {
			// not read: the download ends here, R2 needs the exact length up front
			await upstream.body.cancel();
			fill.settle(false);
			return "unsupported";
		}
		if (options.maxBytes !== undefined && length > options.maxBytes) {
			await upstream.body.cancel();
			fill.settle(false);
			return "too-large";
		}
		const stored = await putStreaming(bucket, key, sourceUrl, upstream, length);
		fill.settle(stored);
		return stored ? "stored" : "failed";
	} catch (e) {
		fill.settle(false);
		throw e;
	}
}

/** content-length of a plain (not content-encoded) 200 answer, undefined when R2 could not use it */
function usableLength(upstream: Response): number | undefined {
	// a decoded body no longer matches content-length, and R2 needs the exact length
	const encoding = (upstream.headers.get("content-encoding") ?? "").trim().toLowerCase();
	const length = encoding === "" || encoding === "identity" ? Number(upstream.headers.get("content-length") ?? "") : NaN;
	return Number.isSafeInteger(length) && length > 0 ? length : undefined;
}

function putOptionsFor(key: string, sourceUrl: string, upstream: Response): R2PutOptions {
	const contentType = contentTypeForArtifact(key);
	const customMetadata: Record<string, string> = { source: sourceUrl, filledAt: new Date().toISOString() };
	const etag = upstream.headers.get("etag");
	const lastModified = upstream.headers.get("last-modified");
	if (etag) customMetadata.sourceEtag = etag;
	if (lastModified) customMetadata.sourceLastModified = lastModified;
	return { httpMetadata: { contentType }, customMetadata };
}

/** stores the whole body (store first); false when that failed */
async function putStreaming(bucket: R2Bucket, key: string, sourceUrl: string, upstream: Response, length: number): Promise<boolean> {
	try {
		// FixedLengthStream fails the put when the source ends early or sends more
		await bucket.put(key, upstream.body!.pipeThrough(new FixedLengthStream(length)), putOptionsFor(key, sourceUrl, upstream));
		return true;
	} catch (e) {
		console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
		return false;
	}
}

/**
 * Stores a 200 answer of the source in R2 and answers the client.
 *
 * Files up to `streamMaxBytes` are streamed to the client and stored at the same
 * time (tee). A tee buffers what the slower branch has not read yet, so for larger
 * files a slow client could hold most of the file in memory; those are stored
 * first and then served from R2. Answers without a usable length are streamed
 * without being stored. Null when storing a large file failed. `settle` reports
 * when the object is stored (or that it was not).
 */
async function storeAndServe(
	bucket: R2Bucket,
	key: string,
	sourceUrl: string,
	upstream: Response,
	waitUntil: (p: Promise<unknown>) => void,
	options: FillOptions,
	settle: (stored: boolean) => void
): Promise<Response | null> {
	const headers = new Headers({ "content-type": contentTypeForArtifact(key) });
	const etag = upstream.headers.get("etag");
	const lastModified = upstream.headers.get("last-modified");
	if (etag) headers.set("etag", etag);
	if (lastModified) headers.set("last-modified", lastModified);

	const length = usableLength(upstream);
	if (length === undefined) {
		settle(false);
		return new Response(upstream.body, { status: 200, headers });
	}

	if (length > options.streamMaxBytes) {
		const stored = await putStreaming(bucket, key, sourceUrl, upstream, length);
		settle(stored);
		return stored ? serveFromR2(bucket, key, options.request) : null;
	}

	headers.set("content-length", String(length));
	headers.set("accept-ranges", "bytes");
	// both tee branches of a fetch body keep its known length, which R2 needs for a streamed put
	const [toClient, toBucket] = upstream.body!.tee();
	waitUntil(
		bucket
			.put(key, toBucket, putOptionsFor(key, sourceUrl, upstream))
			.then(
				() => settle(true),
				(e) => {
					console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
					settle(false);
				}
			)
	);
	return new Response(toClient, { status: 200, headers });
}
