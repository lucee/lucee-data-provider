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

/** every checksum type, in the order Maven clients usually ask for them */
export const CHECKSUM_TYPES = Object.keys(ALGORITHMS) as ChecksumType[];

/**
 * Hashes a stream without buffering it, with one pass for all requested types;
 * fails once more than maxBytes have been read.
 */
export async function checksumsOfStream(
	body: ReadableStream<Uint8Array>,
	types: readonly ChecksumType[],
	maxBytes: number
): Promise<Record<ChecksumType, string>> {
	const digests = types.map((type) => new crypto.DigestStream(ALGORITHMS[type]));
	// an aborted digest rejects; the read error is the one reported
	for (const d of digests) d.digest.catch(() => undefined);
	const writers = digests.map((d) => d.getWriter());
	const reader = body.getReader();
	let read = 0;
	try {
		for (;;) {
			const { done, value } = await reader.read();
			if (done) break;
			read += value.byteLength;
			if (read > maxBytes) throw new TooLargeError(`more than ${maxBytes} bytes`);
			await Promise.all(writers.map((w) => w.write(value)));
		}
		await Promise.all(writers.map((w) => w.close()));
	} catch (e) {
		await reader.cancel(e).catch(() => undefined);
		await Promise.all(writers.map((w) => w.abort(e).catch(() => undefined)));
		throw e;
	}
	const result = {} as Record<ChecksumType, string>;
	for (let i = 0; i < types.length; i++) result[types[i]] = toHex(await digests[i].digest);
	return result;
}

/** Hashes a stream without buffering it; fails once more than maxBytes have been read. */
export async function checksumOfStream(body: ReadableStream<Uint8Array>, type: ChecksumType, maxBytes: number): Promise<string> {
	return (await checksumsOfStream(body, [type], maxBytes))[type];
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

/** seconds a checksum of an immutable artifact stays cached in KV */
export const IMMUTABLE_KV_TTL_SECONDS = 30 * 24 * 60 * 60;

type Computed = Record<ChecksumType, string> | null;

/**
 * Computed checksums, cached in KV: 30 days for immutable artifacts, the cache TTL otherwise.
 * One download of the artifact yields every checksum type. Keys carry the cache generation,
 * so a flush invalidates them without deleting key by key.
 */
export class ChecksumStore {
	constructor(
		readonly kv: KVNamespace,
		readonly options: ChecksumOptions,
		/** current cache generation (bumped by flush) */
		readonly generation: () => Promise<string>
	) {}

	private async kvKey(id: string, type: ChecksumType): Promise<string> {
		return `checksum:${await this.generation()}:${type}:${id}`;
	}

	private async cached(id: string, type: ChecksumType, immutable: boolean, compute: () => Promise<Computed>): Promise<string> {
		const hit = await this.kv.get(await this.kvKey(id, type));
		if (hit) return hit;
		const values = await compute();
		if (!values) return "";
		const ttl = immutable ? IMMUTABLE_KV_TTL_SECONDS : Math.max(MIN_KV_TTL_SECONDS, this.options.mutableTtlSeconds);
		await Promise.all(
			CHECKSUM_TYPES.map(async (t) => {
				try {
					await this.kv.put(await this.kvKey(id, t), values[t], { expirationTtl: ttl });
				} catch (e) {
					// the computed value is still correct; it is just not cached
					console.warn(`caching checksum ${t} of [${id}] failed`, e);
				}
			})
		);
		return values[type];
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
					return null;
				}
				const length = Number(res.headers.get("content-length") ?? "");
				if (Number.isFinite(length) && length > this.options.maxBytes) {
					await res.body.cancel();
					console.warn(`checksum of [${url}] skipped: ${length} bytes is over the limit`);
					return null;
				}
				return await checksumsOfStream(res.body, CHECKSUM_TYPES, this.options.maxBytes);
			} catch (e) {
				console.warn(`checksum of [${url}] failed`, e);
				return null;
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
			if (!obj) return null;
			try {
				return await checksumsOfStream(obj.body, CHECKSUM_TYPES, this.options.maxBytes);
			} catch (e) {
				console.warn(`checksum of R2 object [${key}] failed`, e);
				return null;
			}
		});
	}
}
