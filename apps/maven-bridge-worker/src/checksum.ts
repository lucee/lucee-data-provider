// Maven checksum files (.md5, .sha1, .sha256, .sha512): served from the upstream when it has
// them, otherwise computed from the artifact itself (streamed, size bounded, cached in KV).
import type { ParsedPath } from "./support";

const ALGORITHMS = { md5: "MD5", sha1: "SHA-1", sha256: "SHA-256", sha512: "SHA-512" } as const;
export type ChecksumType = keyof typeof ALGORITHMS;

export const DEFAULT_CHECKSUM_MAX_MB = 128;
/** KV minimum expiration */
const MIN_KV_TTL_SECONDS = 60;

export function isChecksumType(value: string): value is ChecksumType {
	return Object.prototype.hasOwnProperty.call(ALGORITHMS, value.toLowerCase());
}

/**
 * Splits "lucee-1.jar.sha1" into the artifact it belongs to and the checksum type;
 * null when the parsed file is not a checksum file.
 */
export function splitChecksum(parsed: ParsedPath): { artifact: ParsedPath; type: ChecksumType } | null {
	if (parsed.type !== "artifact-file") return null;
	const ext = parsed.extension ?? "";
	const dot = ext.lastIndexOf(".");
	if (dot < 1) return null;
	const type = ext.slice(dot + 1).toLowerCase();
	if (!isChecksumType(type)) return null;
	return { artifact: { ...parsed, extension: ext.slice(0, dot) }, type };
}

function toHex(buffer: ArrayBuffer): string {
	return [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export async function checksumOfText(text: string, type: ChecksumType): Promise<string> {
	return toHex(await crypto.subtle.digest(ALGORITHMS[type], new TextEncoder().encode(text)));
}

class TooLargeError extends Error {}

/** Hashes a stream without buffering it; fails once more than maxBytes have been read. */
export async function checksumOfStream(body: ReadableStream<Uint8Array>, type: ChecksumType, maxBytes: number): Promise<string> {
	let read = 0;
	const limit = new TransformStream<Uint8Array, Uint8Array>({
		transform(chunk, controller) {
			read += chunk.byteLength;
			if (read > maxBytes) throw new TooLargeError(`more than ${maxBytes} bytes`);
			controller.enqueue(chunk);
		}
	});
	const digest = new crypto.DigestStream(ALGORITHMS[type]);
	const result = digest.digest;
	// an aborted pipe also rejects the digest; the pipe error is the one reported
	result.catch(() => undefined);
	await body.pipeThrough(limit).pipeTo(digest);
	return toHex(await result);
}

export interface ChecksumOptions {
	/** artifacts larger than this are not hashed (the checksum answers 404) */
	maxBytes: number;
	/** seconds for the whole download of the artifact */
	timeoutSeconds: number;
	/** seconds a checksum of a mutable artifact (SNAPSHOT) stays cached */
	mutableTtlSeconds: number;
	userAgent: string;
}

/** Computed checksums, cached in KV: forever for immutable artifacts, for the cache TTL otherwise. */
export class ChecksumStore {
	constructor(
		readonly kv: KVNamespace,
		readonly options: ChecksumOptions
	) {}

	private async cached(id: string, type: ChecksumType, immutable: boolean, compute: () => Promise<string>): Promise<string> {
		const key = `checksum:${type}:${id}`;
		const hit = await this.kv.get(key);
		if (hit) return hit;
		const value = await compute();
		if (value.length) {
			const ttl = Math.max(MIN_KV_TTL_SECONDS, this.options.mutableTtlSeconds);
			await this.kv.put(key, value, immutable ? undefined : { expirationTtl: ttl });
		}
		return value;
	}

	/** Checksum of the file at `url`; "" when it is missing, too large or could not be read. */
	async ofUrl(url: string, type: ChecksumType, immutable: boolean): Promise<string> {
		return this.cached(url, type, immutable, async () => {
			try {
				const res = await fetch(url, {
					redirect: "follow",
					headers: { "user-agent": this.options.userAgent, "accept-encoding": "identity" },
					signal: AbortSignal.timeout(this.options.timeoutSeconds * 1000)
				});
				if (res.status !== 200 || !res.body) {
					await res.body?.cancel();
					return "";
				}
				const length = Number(res.headers.get("content-length") ?? "");
				if (Number.isFinite(length) && length > this.options.maxBytes) {
					await res.body.cancel();
					console.warn(`checksum of [${url}] skipped: ${length} bytes is over the limit`);
					return "";
				}
				return await checksumOfStream(res.body, type, this.options.maxBytes);
			} catch (e) {
				console.warn(`checksum of [${url}] failed`, e);
				return "";
			}
		});
	}

	/** Checksum of an R2 object; null when the bucket has no such object, "" when it is too large. */
	async ofR2(bucket: R2Bucket, key: string, type: ChecksumType): Promise<string | null> {
		const head = await bucket.head(key);
		if (!head) return null;
		const stored = head.checksums[type];
		if (stored) return toHex(stored);
		if (head.size > this.options.maxBytes) return "";
		// keyed by etag: a replaced object gets a new checksum
		return this.cached(`r2:${key}:${head.etag}`, type, true, async () => {
			const obj = await bucket.get(key);
			if (!obj) return "";
			try {
				return await checksumOfStream(obj.body, type, this.options.maxBytes);
			} catch (e) {
				console.warn(`checksum of R2 object [${key}] failed`, e);
				return "";
			}
		});
	}
}
