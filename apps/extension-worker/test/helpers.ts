import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { vi } from "vitest";
import type { Env } from "../src/env";
import worker, { resetProvider } from "../src/index";
import { resetMemory } from "../src/store";

export const ORIGIN = "https://extension.lucee.org";
export const BASE = "/rest/extension/provider";

export type Route = Response | string | Uint8Array | ((req: Request) => Response | Promise<Response>);

/** fetch calls seen by the mock, as "METHOD url [range]" */
export let calls: string[] = [];

/** a body served like S3 or a Maven repository: Range requests answer 206 */
function serveBytes(req: Request, bytes: Uint8Array): Response {
	const range = req.headers.get("range");
	const size = bytes.length;
	if (range) {
		const suffix = /^bytes=-(\d+)$/.exec(range);
		const span = /^bytes=(\d+)-(\d+)$/.exec(range);
		let start = 0;
		let end = size - 1;
		if (suffix) start = Math.max(0, size - Number(suffix[1]));
		else if (span) {
			start = Number(span[1]);
			end = Math.min(Number(span[2]), size - 1);
		}
		return new Response(bytes.slice(start, end + 1), {
			status: 206,
			headers: { "content-range": `bytes ${start}-${end}/${size}`, "content-length": String(end - start + 1) }
		});
	}
	return new Response(bytes, { status: 200, headers: { "content-length": String(size) } });
}

/** Replaces the global fetch; unmatched requests answer 404 so a test never reaches the network. */
export function mockFetch(routes: Record<string, Route>) {
	calls = [];
	return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
		const req = new Request(input as RequestInfo, init);
		calls.push(`${req.method} ${req.url}${req.headers.get("range") ? " " + req.headers.get("range") : ""}`);
		const route = routes[req.url];
		if (route === undefined) return new Response("missing", { status: 404 });
		if (typeof route === "string") return serveBytes(req, new TextEncoder().encode(route));
		if (route instanceof Uint8Array) return serveBytes(req, route);
		if (route instanceof Response) return route.clone();
		return route(req);
	});
}

export function testEnv(overrides: Partial<Record<keyof Env, string>> = {}): Env {
	return { ...(env as unknown as Env), ...overrides } as Env;
}

export async function call(path: string, init: RequestInit = {}, overrides: Partial<Record<keyof Env, string>> = {}, origin = ORIGIN): Promise<Response> {
	const ctx = createExecutionContext();
	const res = await worker.fetch(new Request(origin + path, { redirect: "manual", ...init }) as never, testEnv(overrides), ctx);
	const body = res.body ? await res.arrayBuffer() : null;
	await waitOnExecutionContext(ctx);
	return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}

/** fresh KV and memory for every test */
export async function resetState(): Promise<void> {
	const e = env as unknown as Env;
	const keys = await e.EXT_CACHE!.list();
	await Promise.all(keys.keys.map((k) => e.EXT_CACHE!.delete(k.name)));
	resetMemory();
	resetProvider();
}

// ---- a minimal zip writer for .lex files ----

function crc32(bytes: Uint8Array): number {
	let crc = 0xffffffff;
	for (const b of bytes) {
		crc ^= b;
		for (let k = 0; k < 8; k++) crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
	}
	return (crc ^ 0xffffffff) >>> 0;
}

async function deflateRaw(data: Uint8Array): Promise<Uint8Array> {
	const stream = new Blob([data]).stream().pipeThrough(new CompressionStream("deflate-raw"));
	return new Uint8Array(await new Response(stream).arrayBuffer());
}

export async function buildZip(entries: { name: string; data: Uint8Array | string; deflate?: boolean }[], padding = 0): Promise<Uint8Array> {
	const enc = new TextEncoder();
	const parts: Uint8Array[] = [];
	const central: Uint8Array[] = [];
	let offset = 0;
	if (padding) {
		parts.push(new Uint8Array(padding)); // pretend there is more before the entries (large files)
		offset = padding;
	}
	for (const entry of entries) {
		const raw = typeof entry.data === "string" ? enc.encode(entry.data) : entry.data;
		const data = entry.deflate ? await deflateRaw(raw) : raw;
		const name = enc.encode(entry.name);
		const local = new DataView(new ArrayBuffer(30));
		local.setUint32(0, 0x04034b50, true);
		local.setUint16(4, 20, true);
		local.setUint16(8, entry.deflate ? 8 : 0, true);
		local.setUint32(14, crc32(raw), true);
		local.setUint32(18, data.length, true);
		local.setUint32(22, raw.length, true);
		local.setUint16(26, name.length, true);
		parts.push(new Uint8Array(local.buffer), name, data);

		const cd = new DataView(new ArrayBuffer(46));
		cd.setUint32(0, 0x02014b50, true);
		cd.setUint16(4, 20, true);
		cd.setUint16(6, 20, true);
		cd.setUint16(10, entry.deflate ? 8 : 0, true);
		cd.setUint32(16, crc32(raw), true);
		cd.setUint32(20, data.length, true);
		cd.setUint32(24, raw.length, true);
		cd.setUint16(28, name.length, true);
		cd.setUint32(42, offset, true);
		central.push(new Uint8Array(cd.buffer), name);
		offset += 30 + name.length + data.length;
	}
	const cdSize = central.reduce((n, p) => n + p.length, 0);
	const eocd = new DataView(new ArrayBuffer(22));
	eocd.setUint32(0, 0x06054b50, true);
	eocd.setUint16(8, entries.length, true);
	eocd.setUint16(10, entries.length, true);
	eocd.setUint32(12, cdSize, true);
	eocd.setUint32(16, offset, true);
	const all = [...parts, ...central, new Uint8Array(eocd.buffer)];
	const out = new Uint8Array(all.reduce((n, p) => n + p.length, 0));
	let o = 0;
	for (const p of all) {
		out.set(p, o);
		o += p.length;
	}
	return out;
}
