// Lucee skill site (port of apps/skill): mirrors the skill files from docs.lucee.org into KV
// and serves them with a landing page and a health check.
import { readConfig, type Config, type SkillDef } from "./config";
import type { Env } from "./env";
import { renderLanding, skillInfo, type SkillInfo } from "./landing";
import { SkillStore, type CachedSkill } from "./store";

const TEXT = "text/plain; charset=utf-8";
export const SKILL_CACHE_CONTROL = "public, max-age=600";
export const LANDING_CACHE_CONTROL = "public, max-age=300";

function text(status: number, body: string, headers: Record<string, string> = {}): Response {
	return new Response(body, { status, headers: { "content-type": TEXT, "cache-control": "no-store", ...headers } });
}

function lastModifiedOf(skill: CachedSkill): string {
	return skill.lastModified || new Date(skill.fetchedAt).toUTCString();
}

/** If-None-Match (weak comparison, list or "*"), else If-Modified-Since */
function notModified(request: Request, skill: CachedSkill): boolean {
	const inm = request.headers.get("if-none-match");
	if (inm !== null) {
		const strip = (t: string) => t.trim().replace(/^W\//, "");
		return inm.split(",").some((t) => t.trim() === "*" || strip(t) === skill.etag);
	}
	const ims = request.headers.get("if-modified-since");
	if (ims !== null) {
		const since = Date.parse(ims);
		const modified = Date.parse(lastModifiedOf(skill));
		return !Number.isNaN(since) && !Number.isNaN(modified) && modified <= since;
	}
	return false;
}

function refreshIfStale(store: SkillStore, def: SkillDef, skill: CachedSkill, config: Config, ctx: ExecutionContext) {
	if (Date.now() - skill.fetchedAt < config.refreshMinutes * 60_000) return;
	ctx.waitUntil(
		store.refresh(def).then(
			() => undefined,
			(e) => console.error(`background refresh of ${def.file} failed, keeping the cached copy`, e)
		)
	);
}

async function serveSkill(request: Request, def: SkillDef, store: SkillStore, config: Config, ctx: ExecutionContext) {
	let skill: CachedSkill;
	try {
		skill = await store.getOrFetch(def);
	} catch (e) {
		console.error(`${def.file} is not cached and the source failed`, e);
		return text(503, `${def.file} not available`, { "retry-after": "60" });
	}
	refreshIfStale(store, def, skill, config, ctx);

	const headers: Record<string, string> = {
		"content-type": TEXT,
		etag: skill.etag,
		"last-modified": lastModifiedOf(skill),
		"cache-control": SKILL_CACHE_CONTROL
	};
	if (notModified(request, skill)) return new Response(null, { status: 304, headers });
	return new Response(skill.body, { status: 200, headers });
}

async function landing(request: Request, store: SkillStore, config: Config, ctx: ExecutionContext) {
	const skills: SkillInfo[] = [];
	for (const def of config.skills) {
		try {
			const skill = await store.getOrFetch(def);
			refreshIfStale(store, def, skill, config, ctx);
			skills.push(skillInfo(def.file, skill));
		} catch (e) {
			// like index.cfm: a skill that is not available is not listed
			console.error(`${def.file} is not available for the landing page`, e);
		}
	}
	return new Response(renderLanding(skills, new URL(request.url).host), {
		headers: { "content-type": "text/html; charset=utf-8", "cache-control": LANDING_CACHE_CONTROL }
	});
}

async function health(store: SkillStore, config: Config) {
	for (const def of config.skills) {
		try {
			await store.getOrFetch(def);
		} catch (e) {
			console.error(`health: ${def.file} not available`, e);
			return text(503, `${def.file} not available`);
		}
	}
	return text(200, "ok");
}

async function handle(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
	if (request.method !== "GET" && request.method !== "HEAD") {
		return text(405, "Method Not Allowed", { allow: "GET, HEAD" });
	}
	const config = readConfig(env);
	const store = new SkillStore(env.SKILL_CACHE, config.timeoutSeconds);
	const path = new URL(request.url).pathname;

	if (path === "/" || path === "/index.cfm") return landing(request, store, config, ctx);
	if (path === "/health" || path === "/health.cfm") return health(store, config);

	const def = config.skills.find((s) => "/" + s.file === path);
	if (def) return serveSkill(request, def, store, config, ctx);

	return text(404, "Not Found");
}

export default {
	async fetch(request, env, ctx): Promise<Response> {
		let response: Response;
		try {
			response = await handle(request, env, ctx);
		} catch (e) {
			console.error("skill request failed", e);
			response = text(500, e instanceof Error ? e.message : "Internal error");
		}
		if (request.method === "HEAD" && response.body) {
			// keep the length of the GET body
			const length = (await response.arrayBuffer()).byteLength;
			const headers = new Headers(response.headers);
			headers.set("content-length", String(length));
			return new Response(null, { status: response.status, headers });
		}
		return response;
	},

	async scheduled(_controller, env, _ctx): Promise<void> {
		const config = readConfig(env);
		const store = new SkillStore(env.SKILL_CACHE, config.timeoutSeconds);
		const results = await store.refreshAll(config.skills);
		for (const r of results) {
			if (r.ok) console.log(`skill ${r.file}: ${r.status}`);
		}
		const failed = results.filter((r) => !r.ok);
		if (failed.length) {
			throw new Error(
				`skill refresh failed for ${failed.map((f) => `[${f.file}: ${"error" in f ? f.error : ""}]`).join(", ")} (cached copies kept)`
			);
		}
	}
} satisfies ExportedHandler<Env>;
