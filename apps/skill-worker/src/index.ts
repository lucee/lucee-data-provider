// Lucee skill site (port of apps/skill): mirrors the skill router and the topic files listed in
// skills.json from docs.lucee.org into KV and serves them with a landing page and a health check.
import { readConfig, type Config, type SkillDef } from "./config";
import type { Env } from "./env";
import { renderLanding, skillInfo, type SkillInfo, type TopicInfo } from "./landing";
import { JSON_TYPE, LANDING_CACHE_CONTROL, MARKDOWN, SKILL_CACHE_CONTROL, TEXT } from "./http";
import {
	MANIFEST_FILE,
	manifestDef,
	parseManifest,
	topicDef,
	topicFile,
	withRouterChecksum,
	type Manifest
} from "./manifest";
import { etagOf, lastModifiedOf, SkillStore, type CachedSkill } from "./store";

// Only the default handler may be exported from this module: the Workers runtime rejects
// named exports that are not functions or classes (constants live in ./http).

function text(status: number, body: string, headers: Record<string, string> = {}): Response {
	return new Response(body, { status, headers: { "content-type": TEXT, "cache-control": "no-store", ...headers } });
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

/** background refreshes running in this isolate, by file (each request does its own I/O) */
const refreshing = new Set<string>();

/** a missing copy, one older than REFRESH_MINUTES or one that does not match skills.json */
function isStale(def: SkillDef, skill: CachedSkill | null, config: Config): boolean {
	if (!skill) return true;
	if (def.sha256 && skill.etag !== etagOf(def.sha256)) return true;
	return Date.now() - skill.fetchedAt >= config.refreshMinutes * 60_000;
}

function refreshIfStale(
	store: SkillStore,
	def: SkillDef,
	skill: CachedSkill | null,
	config: Config,
	ctx: ExecutionContext,
	check?: (body: string) => void
) {
	if (!isStale(def, skill, config)) return;
	if (refreshing.has(def.file)) return;
	refreshing.add(def.file);
	ctx.waitUntil(
		store
			.refresh(def, check)
			.then(
				() => undefined,
				(e) => console.error(`background refresh of ${def.file} failed, keeping the cached copy`, e)
			)
			.finally(() => refreshing.delete(def.file))
	);
}

function manifestCheck(config: Config) {
	return (body: string) => {
		parseManifest(body, config.manifestUrl!);
	};
}

/** the mirrored skills.json (fetched when not cached yet); throws when it is not available */
async function loadManifest(store: SkillStore, config: Config, ctx: ExecutionContext): Promise<Manifest | null> {
	if (!config.manifestUrl) return null;
	const def = manifestDef(config.manifestUrl);
	const check = manifestCheck(config);
	const cached = await store.getOrFetch(def, check);
	refreshIfStale(store, def, cached, config, ctx, check);
	return parseManifest(cached.body, config.manifestUrl);
}

async function serveSkill(
	request: Request,
	def: SkillDef,
	store: SkillStore,
	config: Config,
	ctx: ExecutionContext,
	contentType = TEXT,
	check?: (body: string) => void
) {
	let skill: CachedSkill;
	try {
		skill = await store.getOrFetch(def, check);
	} catch (e) {
		console.error(`${def.file} is not cached and the source failed`, e);
		return text(503, `${def.file} not available`, { "retry-after": "60" });
	}
	refreshIfStale(store, def, skill, config, ctx, check);

	const headers: Record<string, string> = {
		"content-type": contentType,
		etag: skill.etag,
		"last-modified": lastModifiedOf(skill),
		"cache-control": SKILL_CACHE_CONTROL
	};
	if (notModified(request, skill)) return new Response(null, { status: 304, headers });
	return new Response(skill.body, { status: 200, headers });
}

async function serveTopic(
	request: Request,
	id: string,
	store: SkillStore,
	config: Config,
	ctx: ExecutionContext
): Promise<Response> {
	let manifest: Manifest | null;
	try {
		manifest = await loadManifest(store, config, ctx);
	} catch (e) {
		console.error(`${MANIFEST_FILE} is not available`, e);
		return text(503, `${MANIFEST_FILE} not available`, { "retry-after": "60" });
	}
	const topic = manifest?.topics.find((t) => t.id === id);
	if (!topic) return text(404, "Not Found");
	return serveSkill(request, topicDef(topic), store, config, ctx, MARKDOWN);
}

async function landing(request: Request, store: SkillStore, config: Config, ctx: ExecutionContext) {
	let manifest: Manifest | null = null;
	try {
		manifest = await loadManifest(store, config, ctx);
	} catch (e) {
		// the router is still listed, just without its topics
		console.error(`${MANIFEST_FILE} is not available for the landing page`, e);
	}

	const skills: SkillInfo[] = [];
	for (const def of withRouterChecksum(config.skills, manifest)) {
		try {
			const skill = await store.getOrFetch(def);
			// a copy that skills.json says is out of date is refreshed now, not at the next cron run
			refreshIfStale(store, def, skill, config, ctx);
			skills.push(skillInfo(def.file, skill));
		} catch (e) {
			// like index.cfm: a skill that is not available is not listed
			console.error(`${def.file} is not available for the landing page`, e);
		}
	}

	// topic files are not fetched for the page; a missing or outdated copy is refreshed in the background
	const topics: TopicInfo[] = [];
	for (const topic of manifest?.topics ?? []) {
		const def = topicDef(topic);
		const cached = await store.get(def.file);
		refreshIfStale(store, def, cached, config, ctx);
		const current = cached && (!def.sha256 || cached.etag === etagOf(def.sha256));
		topics.push({
			id: topic.id,
			title: topic.title,
			description: topic.description,
			entries: topic.entries,
			approxTokens: topic.approxTokens,
			path: "/" + topicFile(topic.id),
			size: current ? new TextEncoder().encode(cached.body).byteLength : null
		});
	}

	return new Response(renderLanding(skills, new URL(request.url).host, topics), {
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

	if (config.manifestUrl) {
		if (path.toLowerCase() === "/" + MANIFEST_FILE) {
			return serveSkill(request, manifestDef(config.manifestUrl), store, config, ctx, JSON_TYPE, manifestCheck(config));
		}
		const topic = /^\/skill\/([a-z0-9][a-z0-9-]*)\.md$/.exec(path.toLowerCase());
		if (topic) return serveTopic(request, topic[1], store, config, ctx);
	}

	// like the Cloud Run site, the file name is matched case-insensitively
	const lower = path.toLowerCase();
	const def = config.skills.find((s) => "/" + s.file.toLowerCase() === lower);
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

		// skills.json first: it lists the topic files and the checksums to verify
		let manifest: Manifest | null = null;
		const results = [];
		if (config.manifestUrl) {
			const def = manifestDef(config.manifestUrl);
			const [result] = await store.refreshAll([def], manifestCheck(config));
			results.push(result);
			// on failure the last good copy still drives the topic refresh
			const cached = await store.get(def.file);
			try {
				if (cached) manifest = parseManifest(cached.body, config.manifestUrl);
			} catch (e) {
				console.error(`cached ${MANIFEST_FILE} is not usable`, e);
			}
		}
		const defs = [...withRouterChecksum(config.skills, manifest), ...(manifest?.topics ?? []).map(topicDef)];
		results.push(...(await store.refreshAll(defs)));

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
