// Lucee extension provider on Cloudflare Workers: the REST interface of
// apps/updateserver/rest/ExtensionProvider.cfc (/rest/extension/provider/...), see README.md.
import { parseCfBoolean, readConfig, type Config } from "./config";
import type { Env } from "./env";
import { MavenExtensionSource } from "./maven";
import { ExtensionProvider } from "./provider";
import { getIndex, getLogos, rebuild } from "./store";
import type { ExtensionIndex } from "./types";

const BASE = "/rest/extension/provider";
const CSP = "sandbox; object-src 'none'; script-src 'none'";
const JSON_TYPE = "application/json;charset=UTF-8";
const TEXT_TYPE = "text/plain;charset=UTF-8";
const HTML_TYPE = "text/html;charset=UTF-8";

// the provider (served view, list cache, snapshot file names) of the current index, per isolate
let current: { builtAt: number; config: Config; provider: ExtensionProvider } | undefined;

/** for the tests */
export function resetProvider(): void {
	current = undefined;
}

function providerFor(index: ExtensionIndex, config: Config, env: Env): ExtensionProvider {
	if (!current || current.builtAt !== index.builtAt || JSON.stringify(current.config) !== JSON.stringify(config)) {
		const provider = new ExtensionProvider(index, config, new MavenExtensionSource(config), () => getLogos(env, index));
		current = { builtAt: index.builtAt, config, provider };
	}
	return current.provider;
}

/** EncodeForHtml() (ESAPI): letters, digits and " ,.-_" as they are, everything else as an entity */
export function encodeForHtml(value: string): string {
	const named: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" };
	let out = "";
	for (const ch of value) {
		if (/[A-Za-z0-9 ,.\-_]/.test(ch)) out += ch;
		else if (named[ch]) out += named[ch];
		else out += `&#x${ch.codePointAt(0)!.toString(16)};`;
	}
	return out;
}

function respond(status: number, body: string | null, contentType: string | null, extra: Record<string, string> = {}, head = false): Response {
	const headers: Record<string, string> = { "content-security-policy": CSP, "x-content-type-options": "nosniff", ...extra };
	if (contentType) headers["content-type"] = contentType;
	return new Response(head ? null : body, { status, headers });
}

function json(value: unknown, head: boolean): Response {
	return respond(200, JSON.stringify(value), JSON_TYPE, { "return-format": "json" }, head);
}

/** the url scope: case-insensitive names, the first value of a name */
function urlScope(url: URL): (name: string) => string | undefined {
	const params = new Map<string, string>();
	for (const [k, v] of url.searchParams) if (!params.has(k.toLowerCase())) params.set(k.toLowerCase(), v);
	return (name) => params.get(name.toLowerCase());
}

function boolArg(value: string | undefined, fallback: boolean): boolean {
	return value === undefined ? fallback : parseCfBoolean(value) ?? fallback;
}

async function isAuthorized(request: Request, config: Config): Promise<boolean> {
	if (!config.flushToken.length) return false;
	const header = request.headers.get("x-flush-token") ?? "";
	const bearer = /^Bearer\s+(.+)$/i.exec((request.headers.get("authorization") ?? "").trim());
	const token = (header || (bearer ? bearer[1] : "")).trim();
	if (!token.length) return false;
	const digest = (v: string) => crypto.subtle.digest("SHA-256", new TextEncoder().encode(v));
	const [a, b] = await Promise.all([digest(token), digest(config.flushToken)]);
	return crypto.subtle.timingSafeEqual(a, b);
}

async function handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
	const url = new URL(request.url);
	const config = readConfig(env);
	const head = request.method === "HEAD";
	const path = url.pathname.replace(/\/+$/, "");
	const lower = path.toLowerCase();

	if (lower === "/healthcheck" || lower === "/healthcheck/index.cfm") return respond(200, "OK", HTML_TYPE, {}, head);
	if (lower === "" || lower === "/index.cfm") {
		return respond(200, `Lucee extension provider, see ${url.origin}${BASE}/info`, TEXT_TYPE, {}, head);
	}
	if (!lower.startsWith(BASE + "/")) return respond(404, "not found", HTML_TYPE, {}, head);
	if (request.method !== "GET" && !head) return respond(405, "Method Not Allowed", TEXT_TYPE, { allow: "GET, HEAD" });

	const segments = path.substring(BASE.length + 1).split("/");
	const action = segments[0].toLowerCase();
	const arg = urlScope(url);
	const waitUntil = (p: Promise<unknown>) => ctx.waitUntil(p);

	// admin-ish endpoints of the CFML version: need the FLUSH_TOKEN secret, disabled without it
	if (segments.length === 1 && (action === "updatecache" || action === "reset" || action === "status")) {
		if (!(await isAuthorized(request, config))) {
			return respond(403, config.flushToken.length ? "Forbidden" : "Disabled", TEXT_TYPE, {}, head);
		}
		if (action === "status") {
			const index = await getIndex(env, config, waitUntil);
			return json({ builtAt: new Date(index.builtAt).toISOString(), stats: index.stats }, head);
		}
		const index = await rebuild(env, config);
		if (action === "reset") return respond(200, "", JSON_TYPE, {}, head);
		return json({ META: {}, EXTENSIONS: { COLUMNS: index.columns, DATA: index.rows } }, head);
	}

	// ?flush=true reloads the extension meta, only with the FLUSH_TOKEN (Lucee core never flushes), ignored otherwise
	let index: ExtensionIndex;
	try {
		index = boolArg(arg("flush"), false) && (await isAuthorized(request, config)) ? await rebuild(env, config) : await getIndex(env, config, waitUntil);
	} catch (e) {
		console.log(`The extension index is not available: ${(e as Error).message}`);
		return respond(503, "The extension index is not available, try again later.", TEXT_TYPE, { "retry-after": "60" }, head);
	}
	const provider = providerFor(index, config, env);

	// GET info
	if (segments.length === 1 && action === "info") {
		const hostName = request.headers.get("host") ?? url.host;
		const type = /^beta\./i.test(hostName) ? "abc" : arg("type") ?? "release";
		try {
			const extensions = await provider.list(type, boolArg(arg("withLogo"), true), arg("coreVersion") ?? "");
			return json(
				{
					META: {
						MODE: "production",
						URL: `https://${hostName}`,
						IMAGE: `https://${hostName}/extension/extension-provider.png`,
						TITLE: `Lucee Association Switzerland Extension Store (${hostName})`,
						DESCRIPTION: ""
					},
					EXTENSIONS: extensions
				},
				head
			);
		} catch (e) {
			return respond(500, JSON.stringify({ message: (e as Error).message }), JSON_TYPE, {}, head);
		}
	}

	// GET info/{id}, full/{id}, trial/{id}
	if (segments.length === 2 && (action === "info" || action === "full" || action === "trial")) {
		let id: string;
		try {
			id = decodeURIComponent(segments[1]);
		} catch {
			id = segments[1];
		}
		const version = arg("version") ?? "";
		const coreVersion = arg("coreVersion") ?? "";
		const type = arg("type") ?? "release";

		if (action === "info") {
			const ext = await provider.detail(id, version, boolArg(arg("withLogo"), true), coreVersion, type);
			if (ext) return json(ext, head);
			let msg = `There is no extension at this provider with id [${encodeForHtml(id)}]`;
			msg += version.length ? ` in version [${encodeForHtml(version)}].` : ".";
			return respond(404, msg, TEXT_TYPE, {}, head);
		}

		const ext = await provider.detail(id, version, false, coreVersion, type);
		if (ext) {
			return respond(302, "", HTML_TYPE, { location: await provider.downloadUrl(String(ext.filename)) }, head);
		}
		return respond(404, "", HTML_TYPE, {}, head);
	}

	return respond(404, "not found", HTML_TYPE, {}, head);
}

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		return handle(request, env, ctx);
	},

	/** the cron rebuilds the index, so requests don't have to */
	async scheduled(_controller: ScheduledController, env: Env): Promise<void> {
		await rebuild(env, readConfig(env));
	}
} satisfies ExportedHandler<Env>;
