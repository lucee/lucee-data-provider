// Maven checksum files (.md5, .sha1, .sha256, .sha512): served from the upstream when it has
// them, otherwise computed from the artifact itself (streamed, size bounded, cached in KV).
// Large artifacts are hashed in the background (ctx.waitUntil) so the request answers right away;
// that work still counts toward the invocation's CPU and memory limits.
import type { ParsedPath } from "./support";

const ALGORITHMS = { md5: "MD5", sha1: "SHA-1", sha256: "SHA-256", sha512: "SHA-512" } as const;
export type ChecksumType = keyof typeof ALGORITHMS;

export const DEFAULT_CHECKSUM_MAX_MB = 128;
/** artifacts up to this size are hashed inside the request, larger ones in the background */
export const DEFAULT_CHECKSUM_INLINE_MAX_MB = 16;
/** bytes per read: few large reads into one reused buffer keep CPU and memory flat */
export const READ_CHUNK_BYTES = 1024 * 1024;
/** seconds a background computation blocks further attempts for the same artifact */
export const PENDING_TTL_SECONDS = 300;
/** background attempts per artifact before giving up until ATTEMPTS_TTL_SECONDS have passed */
export const MAX_BACKGROUND_ATTEMPTS = 3;
/** seconds the attempt count of an artifact is kept */
export const ATTEMPTS_TTL_SECONDS = 24 * 60 * 60;

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

export class TooLargeError extends Error {}

/** every checksum type, in the order Maven clients usually ask for them */
export const CHECKSUM_TYPES = Object.keys(ALGORITHMS) as ChecksumType[];

/**
 * BYOB reader of a byte stream (fetch, R2 and Blob bodies), null for streams that only
 * support the default reader (e.g. a plain JS ReadableStream).
 */
function byobReader(body: ReadableStream<Uint8Array>): ReadableStreamBYOBReader | null {
	try {
		return body.getReader({ mode: "byob" });
	} catch (e) {
		// per spec a TypeError means "not a byte stream"; anything else is a real failure
		if (e instanceof TypeError) return null;
		throw e;
	}
}

/**
 * Hashes a stream without buffering it, with one pass for all requested types (native
 * crypto.DigestStream); fails once more than maxBytes have been read, and when
 * expectedBytes is given and the stream ends with a different length (truncated download).
 * Byte streams are read in READ_CHUNK_BYTES blocks into a single reused buffer.
 */
export async function checksumsOfStream(
	body: ReadableStream<Uint8Array>,
	types: readonly ChecksumType[],
	maxBytes: number,
	expectedBytes?: number
): Promise<Record<ChecksumType, string>> {
	const digests = types.map((type) => new crypto.DigestStream(ALGORITHMS[type]));
	// an aborted digest rejects; the read error is the one reported
	for (const d of digests) d.digest.catch(() => undefined);
	const writers = digests.map((d) => d.getWriter());
	let read = 0;
	const consume = async (chunk: Uint8Array) => {
		read += chunk.byteLength;
		if (read > maxBytes) throw new TooLargeError(`more than ${maxBytes} bytes`);
		// every write is complete before the buffer is read into again
		await Promise.all(writers.map((w) => w.write(chunk)));
	};
	const byob = byobReader(body);
	const reader = byob ?? body.getReader();
	try {
		if (byob) {
			let buffer: ArrayBuffer = new ArrayBuffer(READ_CHUNK_BYTES);
			for (;;) {
				const result: ReadableStreamReadResult<Uint8Array<ArrayBuffer>> = await byob.readAtLeast(
					READ_CHUNK_BYTES,
					new Uint8Array(buffer)
				);
				const { done, value } = result;
				if (value && value.byteLength) await consume(value);
				if (done || !value) break;
				buffer = value.buffer;
			}
		} else {
			const plain = reader as ReadableStreamDefaultReader<Uint8Array>;
			for (;;) {
				const { done, value } = await plain.read();
				if (done) break;
				await consume(value);
			}
		}
		if (expectedBytes !== undefined && read !== expectedBytes) {
			throw new Error(`read ${read} bytes, expected ${expectedBytes}`);
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
	/**
	 * artifacts larger than this are hashed in the background (waitUntil): the request
	 * answers 404 until the result is cached; 0 = always in the background
	 */
	inlineMaxBytes: number;
	/** seconds for the whole download of the artifact */
	timeoutSeconds: number;
	userAgent: string;
}

/** seconds a computed checksum stays cached in KV (every artifact file is immutable: its name never gets other content) */
export const IMMUTABLE_KV_TTL_SECONDS = 30 * 24 * 60 * 60;

type Computed = Record<ChecksumType, string> | null;

/** background computations running in this isolate, by pending key */
const running = new Set<string>();

function contentLength(res: Response): number | null {
	const header = res.headers.get("content-length");
	if (header === null || header.trim() === "") return null;
	const length = Number(header);
	return Number.isSafeInteger(length) && length >= 0 ? length : null;
}

/**
 * Computed checksums, cached in KV for 30 days (SNAPSHOT files included: each build has its own file name).
 * One download of the artifact yields every checksum type. Keys carry the cache generation,
 * so a flush invalidates them without deleting key by key.
 *
 * Artifacts over inlineMaxBytes are hashed in the background when a waitUntil is given:
 * the request answers "" (404, which Maven only warns about) right away, and a KV marker
 * keeps further requests from starting the same download for PENDING_TTL_SECONDS.
 */
export class ChecksumStore {
	constructor(
		readonly kv: KVNamespace,
		readonly options: ChecksumOptions,
		/** current cache generation (bumped by flush) */
		readonly generation: () => Promise<string>,
		/** background work (ctx.waitUntil); undefined = every artifact is hashed inline */
		readonly waitUntil?: (p: Promise<unknown>) => void
	) {}

	private async kvKey(id: string, type: ChecksumType): Promise<string> {
		return `checksum:${await this.generation()}:${type}:${id}`;
	}

	private async pendingKey(id: string): Promise<string> {
		return `checksum-pending:${await this.generation()}:${id}`;
	}

	private async attemptsKey(id: string): Promise<string> {
		return `checksum-attempts:${await this.generation()}:${id}`;
	}

	/** size up to which an artifact is hashed inside the request */
	private get inlineLimit(): number {
		if (!this.waitUntil) return this.options.maxBytes;
		return Math.min(this.options.inlineMaxBytes, this.options.maxBytes);
	}

	private async store(id: string, values: Record<ChecksumType, string>): Promise<void> {
		const ttl = IMMUTABLE_KV_TTL_SECONDS;
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
	}

	/** cached value, or "" when a background computation for this artifact is pending */
	private async lookup(id: string, type: ChecksumType): Promise<string | null> {
		const hit = await this.kv.get(await this.kvKey(id, type));
		if (hit) return hit;
		const pendingKey = await this.pendingKey(id);
		if (running.has(pendingKey) || (await this.kv.get(pendingKey)) !== null) return "";
		return null;
	}

	/**
	 * Starts hashing in the background, at most once per artifact while the marker lives.
	 * A run the runtime ends early (CPU or memory limit, waitUntil time limit) cannot report
	 * itself, so every attempt is counted: an unfinished previous attempt is logged, and after
	 * MAX_BACKGROUND_ATTEMPTS the artifact is left alone for ATTEMPTS_TTL_SECONDS.
	 * `discard` releases what `compute` would have read (e.g. an open download) when it does not run.
	 */
	private async background(
		id: string,
		compute: () => Promise<Computed>,
		discard: () => Promise<void> = async () => undefined
	): Promise<void> {
		const pendingKey = await this.pendingKey(id);
		if (running.has(pendingKey)) {
			await discard();
			return;
		}
		running.add(pendingKey);
		const task = (async () => {
			let started = false;
			try {
				const attemptsKey = await this.attemptsKey(id);
				const attempts = Number((await this.kv.get(attemptsKey)) ?? "0") || 0;
				if (attempts >= MAX_BACKGROUND_ATTEMPTS) {
					console.error(
						`background checksum of [${id}] not started: ${attempts} attempts did not finish, ` +
							`likely the Worker's CPU or memory limit; retried after the attempt count expires`
					);
					return;
				}
				if (attempts > 0) console.warn(`background checksum of [${id}]: attempt ${attempts + 1}, the previous one did not finish`);
				await this.kv.put(attemptsKey, String(attempts + 1), { expirationTtl: ATTEMPTS_TTL_SECONDS });
				await this.kv.put(pendingKey, new Date().toISOString(), { expirationTtl: PENDING_TTL_SECONDS });
				started = true;
				const values = await compute();
				if (values) {
					await this.store(id, values);
					await this.kv.delete(attemptsKey);
				}
			} catch (e) {
				// nothing is cached: the checksum keeps answering 404 and is retried after the marker expires
				console.error(`background checksum of [${id}] failed`, e);
			} finally {
				running.delete(pendingKey);
				if (!started) await discard().catch((e) => console.warn(`releasing the download of [${id}] failed`, e));
			}
		})();
		this.waitUntil!(task);
	}

	private async download(url: string): Promise<Response | null> {
		const res = await fetch(url, {
			redirect: "follow",
			headers: { "user-agent": this.options.userAgent, "accept-encoding": "identity" },
			signal: AbortSignal.timeout(this.options.timeoutSeconds * 1000)
		});
		if (res.status !== 200 || !res.body) {
			await res.body?.cancel();
			return null;
		}
		return res;
	}

	/** every checksum of the file at `url`, null when it is missing, too large or unreadable */
	private async hashUrl(url: string, res?: Response): Promise<Computed> {
		try {
			res ??= (await this.download(url)) ?? undefined;
			if (!res) return null;
			const length = contentLength(res);
			if (length !== null && length > this.options.maxBytes) {
				await res.body!.cancel();
				console.warn(`checksum of [${url}] skipped: ${length} bytes is over the limit`);
				return null;
			}
			return await checksumsOfStream(res.body!, CHECKSUM_TYPES, this.options.maxBytes, length ?? undefined);
		} catch (e) {
			console.warn(`checksum of [${url}] failed`, e);
			return null;
		}
	}

	/** Checksum of the file at `url`; "" when it is missing, too large, could not be read or is being computed. */
	async ofUrl(url: string, type: ChecksumType): Promise<string> {
		const known = await this.lookup(url, type);
		if (known !== null) return known;

		const limit = this.inlineLimit;
		let values: Computed;
		if (limit >= this.options.maxBytes) {
			values = await this.hashUrl(url);
		} else {
			let res: Response | null;
			try {
				res = await this.download(url);
			} catch (e) {
				console.warn(`checksum of [${url}] failed`, e);
				return "";
			}
			if (!res) return "";
			const length = contentLength(res);
			if (length !== null && length > this.options.maxBytes) {
				await res.body!.cancel();
				console.warn(`checksum of [${url}] skipped: ${length} bytes is over the limit`);
				return "";
			}
			if (length !== null && length > limit) {
				// the open download is hashed in the background, no second request
				const download = res;
				await this.background(url, () => this.hashUrl(url, download), async () => {
					await download.body!.cancel();
				});
				return "";
			}
			if (length !== null) {
				values = await this.hashUrl(url, res);
			} else {
				// unknown size: hash inline up to the inline limit, beyond that in the background
				try {
					values = await checksumsOfStream(res.body!, CHECKSUM_TYPES, limit);
				} catch (e) {
					if (!(e instanceof TooLargeError)) {
						console.warn(`checksum of [${url}] failed`, e);
						return "";
					}
					await this.background(url, () => this.hashUrl(url));
					return "";
				}
			}
		}
		if (!values) return "";
		await this.store(url, values);
		return values[type];
	}

	/** Checksum of an R2 object; null when the bucket has no such object, "" when it is too large or being computed. */
	async ofR2(bucket: R2Bucket, key: string, type: ChecksumType): Promise<string | null> {
		const head = await bucket.head(key);
		if (!head) return null;
		const stored = head.checksums[type];
		if (stored) return toHex(stored);
		if (head.size > this.options.maxBytes) return "";
		// keyed by etag: a replaced object gets a new checksum
		const id = `r2:${key}:${head.etag}`;
		const known = await this.lookup(id, type);
		if (known !== null) return known;
		const compute = async (): Promise<Computed> => {
			const obj = await bucket.get(key, { onlyIf: { etagMatches: head.etag } });
			if (!obj || !("body" in obj)) return null;
			try {
				return await checksumsOfStream(obj.body, CHECKSUM_TYPES, this.options.maxBytes, obj.size);
			} catch (e) {
				console.warn(`checksum of R2 object [${key}] failed`, e);
				return null;
			}
		};
		if (head.size > this.inlineLimit) {
			await this.background(id, compute);
			return "";
		}
		const values = await compute();
		if (!values) return "";
		await this.store(id, values);
		return values[type];
	}
}
