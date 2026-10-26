// Lucee Maven bridge as a Cloudflare Worker (port of apps/maven-bridge).
import { readConfig, type BridgeConfig } from "./config";
import type { Env } from "./env";
import { landingPage } from "./landing";
import { healthResponse, invokePath, normalizeRequestPath, textResponse } from "./proxy";
import { BridgeRegistry } from "./registry";
import { ChecksumStore } from "./checksum";
import { RuntimeIo, USER_AGENT } from "./store";

const TEXT = "text/plain; charset=utf-8";
const HEALTH_PATHS = ["/health", "/healthcheck", "/health.cfm"];

/** same truthy values as isFlushRequest() in Application.cfc */
export function isFlushRequested(url: URL): boolean {
	if (!url.searchParams.has("flush")) return false;
	const value = (url.searchParams.get("flush") ?? "").trim().toLowerCase();
	if (["1", "true", "yes", "force"].includes(value)) return true;
	const n = Number(value);
	return value.length > 0 && Number.isFinite(n) && n !== 0;
}

function presentedToken(request: Request): string {
	const header = request.headers.get("x-flush-token");
	if (header) return header.trim();
	const auth = request.headers.get("authorization") ?? "";
	const match = /^Bearer\s+(.+)$/i.exec(auth.trim());
	return match ? match[1].trim() : "";
}

async function digest(value: string): Promise<ArrayBuffer> {
	return crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
}

/** Flushing needs the FLUSH_TOKEN secret; without the secret flushing is disabled. */
export async function isFlushAuthorized(request: Request, config: BridgeConfig): Promise<boolean> {
	if (!config.flushToken.length) return false;
	const token = presentedToken(request);
	if (!token.length) return false;
	const [a, b] = await Promise.all([digest(token), digest(config.flushToken)]);
	return crypto.subtle.timingSafeEqual(a, b);
}

function createBridge(env: Env, waitUntil: (p: Promise<unknown>) => void, origin?: string) {
	const config = readConfig(env);
	const io = new RuntimeIo(env, config, waitUntil, origin);
	const registry = new BridgeRegistry(config, io);
	return { config, io, registry };
}

async function handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
	const url = new URL(request.url);
	const { config, io, registry } = createBridge(env, (p) => ctx.waitUntil(p), url.origin);

	let flushed = false;
	if (isFlushRequested(url)) {
		if (!(await isFlushAuthorized(request, config))) {
			return textResponse(403, TEXT, config.flushToken.length ? "Forbidden" : "Flush is disabled");
		}
		await io.flushAll(registry.getSupports());
		flushed = true;
	}

	const path = normalizeRequestPath(url.pathname);
	if (path === "/" || path.toLowerCase() === "/index.cfm") {
		return textResponse(200, "text/html; charset=utf-8", await landingPage(registry));
	}
	if (HEALTH_PATHS.includes(path.toLowerCase())) {
		return healthResponse(registry, flushed);
	}
	return invokePath(
		{
			registry,
			config,
			request,
			waitUntil: (p) => ctx.waitUntil(p),
			bucket: io.r2,
			checksums: new ChecksumStore(
				env.BRIDGE_CACHE,
				{
					maxBytes: config.checksumMaxBytes,
					inlineMaxBytes: config.checksumInlineMaxBytes,
					timeoutSeconds: config.timeout,
					mutableTtlSeconds: config.cacheTtlMinutes * 60,
					userAgent: USER_AGENT
				},
				() => io.getGeneration(),
				(p) => ctx.waitUntil(p)
			)
		},
		path
	);
}

export default {
	async fetch(request, env, ctx): Promise<Response> {
		let response: Response;
		try {
			response = await handle(request, env, ctx);
		} catch (e) {
			console.error("maven-bridge request failed", e);
			response = textResponse(500, TEXT, e instanceof Error ? e.message : "Internal error");
		}
		if (request.method === "HEAD" && response.body) {
			await response.body.cancel();
			return new Response(null, { status: response.status, headers: response.headers });
		}
		return response;
	},

	async scheduled(_controller, env, ctx): Promise<void> {
		const { io, registry } = createBridge(env, (p) => ctx.waitUntil(p));
		const results = await io.syncAll(registry.getSupports());
		const failed = results.filter((r) => !r.ok);
		if (failed.length) {
			throw new Error(`maven-bridge sync failed for ${failed.map((f) => `[${f.groupId}: ${f.error}]`).join(", ")}`);
		}
	}
} satisfies ExportedHandler<Env>;
