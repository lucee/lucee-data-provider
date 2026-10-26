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

/**
 * Lazy migration: fetch `sourceUrl` and store a copy in R2 under `key`.
 *
 * Files up to `streamMaxBytes` are streamed to the client and stored at the same
 * time (tee). A tee buffers what the slower branch has not read yet, so for larger
 * files a slow client could hold most of the file in memory; those are stored
 * first and then served from R2.
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
	// the timeout covers the answer, not the body: a large file to a slow client may take longer
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`Timeout fetching [${sourceUrl}]`)), options.timeoutSeconds * 1000);
	let upstream: Response;
	try {
		upstream = await fetch(sourceUrl, {
			redirect: "follow",
			headers: { "user-agent": options.userAgent, "accept-encoding": "identity" },
			signal: controller.signal
		});
	} catch (e) {
		console.warn(`R2 fill of [${key}]: fetching [${sourceUrl}] failed`, e);
		return null;
	} finally {
		clearTimeout(timer);
	}
	if (upstream.status !== 200 || !upstream.body) {
		await upstream.body?.cancel();
		return null;
	}

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

	const putOptions: R2PutOptions = {
		httpMetadata: { contentType },
		customMetadata: { source: sourceUrl, filledAt: new Date().toISOString() }
	};

	if (length > options.streamMaxBytes) {
		try {
			// FixedLengthStream fails the put when the source ends early or sends more
			await bucket.put(key, upstream.body.pipeThrough(new FixedLengthStream(length)), putOptions);
		} catch (e) {
			console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
			return null;
		}
		return serveFromR2(bucket, key, options.request);
	}

	headers.set("content-length", String(length));
	headers.set("accept-ranges", "bytes");
	// both tee branches of a fetch body keep its known length, which R2 needs for a streamed put
	const [toClient, toBucket] = upstream.body.tee();
	waitUntil(
		bucket.put(key, toBucket, putOptions).catch((e) => {
			console.error(`R2 fill of [${key}] from [${sourceUrl}] failed`, e);
		})
	);
	return new Response(toClient, { status: 200, headers });
}

