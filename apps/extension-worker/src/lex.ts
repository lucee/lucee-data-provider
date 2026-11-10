// Reads the manifest, logo and packaging of an extension (.lex, a zip file) over http, without downloading
// the whole file when the server supports range requests: the central directory at the end first, then
// only the entries that are needed. Replaces ManifestRead(), the zip:// reads and _probePackaging() of
// ExtensionMetadataReader.cfc.
import { USER_AGENT, withTimeout } from "./http";

interface ZipEntry {
	name: string;
	method: number;
	compressedSize: number;
	localOffset: number;
}

export interface LexInfo {
	/** main attributes of META-INF/MANIFEST.MF, keys as in the manifest, values without surrounding quotes */
	manifest: Record<string, string>;
	/** base64 of META-INF/logo.png, "" when there is none */
	logo: string;
	/** "osgi", "maven" or "unknown", see _probePackaging() */
	packaging: string;
}

const TAIL = 65_557; // end of central directory record (22) + the longest comment (65535)

class RangeReader {
	private whole?: Uint8Array;
	private readonly timeout: { signal: AbortSignal; clear: () => void };
	size = 0;

	constructor(private readonly url: string, timeoutMs: number, private readonly maxBytes: number) {
		this.timeout = withTimeout(timeoutMs);
	}

	/** a request of the file, the timeout covers reading the body (by the caller) too */
	private async get(range?: string): Promise<Response> {
		const headers: Record<string, string> = { "user-agent": USER_AGENT };
		if (range) headers.range = range;
		const res = await fetch(this.url, { headers, redirect: "follow", signal: this.timeout.signal });
		if (res.status !== 200 && res.status !== 206) {
			await res.body?.cancel();
			throw new Error(`${this.url}: ${res.status}`);
		}
		return res;
	}

	close(): void {
		this.timeout.clear();
	}

	private async readWhole(res: Response): Promise<Uint8Array> {
		const length = Number(res.headers.get("content-length") ?? "0");
		if (length > this.maxBytes) {
			await res.body?.cancel();
			throw new Error(`${this.url}: no range support and larger than ${this.maxBytes} bytes`);
		}
		this.whole = new Uint8Array(await res.arrayBuffer());
		this.size = this.whole.length;
		return this.whole;
	}

	/** the last bytes of the file, and where they start */
	async tail(): Promise<{ bytes: Uint8Array; start: number }> {
		const res = await this.get(`bytes=-${TAIL}`);
		if (res.status === 200) return { bytes: await this.readWhole(res), start: 0 };
		const total = /\/(\d+)\s*$/.exec(res.headers.get("content-range") ?? "");
		const bytes = new Uint8Array(await res.arrayBuffer());
		this.size = total ? Number(total[1]) : bytes.length;
		if (bytes.length >= this.size) this.whole = bytes; // the whole file is smaller than the tail
		return { bytes, start: this.size - bytes.length };
	}

	async range(start: number, end: number): Promise<Uint8Array> {
		end = Math.min(end, this.size - 1);
		if (this.whole) return this.whole.subarray(start, end + 1);
		const res = await this.get(`bytes=${start}-${end}`);
		if (res.status === 200) return (await this.readWhole(res)).subarray(start, end + 1);
		return new Uint8Array(await res.arrayBuffer());
	}
}

function u16(b: Uint8Array, o: number): number {
	return b[o] | (b[o + 1] << 8);
}

function u32(b: Uint8Array, o: number): number {
	return (b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)) >>> 0;
}

async function inflate(method: number, data: Uint8Array): Promise<Uint8Array> {
	if (method === 0) return data;
	if (method !== 8) throw new Error(`unsupported compression method ${method}`);
	const stream = new Blob([data]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
	return new Uint8Array(await new Response(stream).arrayBuffer());
}

function readCentralDirectory(cd: Uint8Array): ZipEntry[] {
	const entries: ZipEntry[] = [];
	const decoder = new TextDecoder();
	let o = 0;
	while (o + 46 <= cd.length && u32(cd, o) === 0x02014b50) {
		const method = u16(cd, o + 10);
		const compressedSize = u32(cd, o + 20);
		const nameLength = u16(cd, o + 28);
		const extraLength = u16(cd, o + 30);
		const commentLength = u16(cd, o + 32);
		const localOffset = u32(cd, o + 42);
		const name = decoder.decode(cd.subarray(o + 46, o + 46 + nameLength));
		entries.push({ name, method, compressedSize, localOffset });
		o += 46 + nameLength + extraLength + commentLength;
	}
	return entries;
}

async function readEntry(reader: RangeReader, entry: ZipEntry): Promise<Uint8Array> {
	// the local header has its own name and extra field, read generously, then exactly when that was not enough
	let chunk = await reader.range(entry.localOffset, entry.localOffset + 30 + 1024 + entry.compressedSize);
	if (u32(chunk, 0) !== 0x04034b50) throw new Error(`invalid local header of ${entry.name}`);
	const dataStart = 30 + u16(chunk, 26) + u16(chunk, 28);
	if (chunk.length < dataStart + entry.compressedSize) {
		chunk = await reader.range(entry.localOffset, entry.localOffset + dataStart + entry.compressedSize - 1);
	}
	return inflate(entry.method, chunk.subarray(dataStart, dataStart + entry.compressedSize));
}

/** the main section of a manifest, continuation lines joined, values without surrounding quotes */
export function parseManifest(text: string): Record<string, string> {
	const lines = text.replace(/\r\n?/g, "\n").split("\n");
	const joined: string[] = [];
	for (const line of lines) {
		if (line.startsWith(" ") && joined.length) joined[joined.length - 1] += line.substring(1);
		else if (line.trim() === "") {
			if (joined.length) break; // end of the main section
		} else joined.push(line);
	}
	const result: Record<string, string> = {};
	for (const line of joined) {
		const i = line.indexOf(":");
		if (i <= 0) continue;
		let value = line.substring(i + 1).trim();
		if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) value = value.substring(1, value.length - 1);
		result[line.substring(0, i).trim()] = value;
	}
	return result;
}

function toBase64(bytes: Uint8Array): string {
	let binary = "";
	for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
	return btoa(binary);
}

export function manifestValue(manifest: Record<string, string>, key: string): string {
	const lower = key.toLowerCase();
	for (const k of Object.keys(manifest)) if (k.toLowerCase() === lower) return manifest[k];
	return "";
}

/**
 * _probePackaging(): "osgi" when the extension has jars in a jars folder (any Lucee can load it), "maven"
 * when it has a maven folder or Maven coordinates in its manifest (only newer Lucee versions can load it).
 */
export function probePackaging(names: string[], manifest: Record<string, string>): string {
	const hasJars = names.some((n) => /^jars\/[^/]+\.jar$/i.test(n));
	const hasMaven = names.some((n) => n.startsWith("maven/") || n.startsWith("mvn/"));
	const hasCoords = manifestValue(manifest, "groupId").length > 0 && manifestValue(manifest, "artifactId").length > 0;
	if (hasJars) return "osgi";
	if (hasMaven || hasCoords) return "maven";
	return "unknown";
}

export async function readLex(url: string, timeoutMs = 60_000, maxBytes = 64 * 1024 * 1024): Promise<LexInfo> {
	const reader = new RangeReader(url, timeoutMs, maxBytes);
	try {
		return await readEntries(reader, url);
	} finally {
		reader.close();
	}
}

async function readEntries(reader: RangeReader, url: string): Promise<LexInfo> {
	const { bytes: tail, start } = await reader.tail();

	let eocd = -1;
	for (let i = tail.length - 22; i >= 0; i--) {
		if (u32(tail, i) === 0x06054b50) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) throw new Error(`${url}: not a zip file`);
	const cdSize = u32(tail, eocd + 12);
	const cdOffset = u32(tail, eocd + 16);
	if (cdOffset === 0xffffffff) throw new Error(`${url}: zip64 is not supported`);

	const cd = cdOffset >= start ? tail.subarray(cdOffset - start, cdOffset - start + cdSize) : await reader.range(cdOffset, cdOffset + cdSize - 1);
	const entries = readCentralDirectory(cd);
	const names = entries.map((e) => e.name);

	const manifestEntry = entries.find((e) => e.name === "META-INF/MANIFEST.MF");
	const manifest = manifestEntry ? parseManifest(new TextDecoder().decode(await readEntry(reader, manifestEntry))) : {};
	const logoEntry = entries.find((e) => e.name === "META-INF/logo.png");
	const logo = logoEntry ? toBase64(await readEntry(reader, logoEntry)) : "";

	return { manifest, logo, packaging: probePackaging(names, manifest) };
}
