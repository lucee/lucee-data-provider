// skills.json (LDEV-6552): the topic files are mirrored from the manifest and served under /skill/.
import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import { cacheKey, type CachedSkill } from "../src/store";
import { SKILL, SOURCE, call, calls, kv, mockFetch, resetState, sourceRoute, testEnv, type Route } from "./helpers";

const MANIFEST = "https://docs.lucee.org/skill/skills.json";
const AI = "# Lucee skill: AI\n\n| ID | Title |\n|----|-------|\n| `ai` | AI |\n";
const ORM = "# Lucee skill: ORM\n\n| ID | Title |\n|----|-------|\n| `orm` | ORM |\n";
const ROUTER = SKILL.replace("name: lucee-docs", "name: lucee");

async function sha256(text: string): Promise<string> {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

interface TopicSpec {
	id: string;
	body: string;
	entries?: number;
	sha?: string;
	url?: string;
}

async function manifest(topics: TopicSpec[], router = ROUTER): Promise<string> {
	return JSON.stringify(
		{
			name: "lucee",
			router: { url: SOURCE, sha256: await sha256(router), approxTokens: 924 },
			topics: await Promise.all(
				topics.map(async (t) => ({
					id: t.id,
					title: t.id.toUpperCase(),
					description: `${t.id} things`,
					url: t.url ?? `https://docs.lucee.org/skill/${t.id}.md`,
					path: `skill/${t.id}.md`,
					entries: t.entries ?? 3,
					sha256: t.sha ?? (await sha256(t.body)),
					approxTokens: 600
				}))
			)
		},
		null,
		2
	);
}

const topicUrl = (id: string) => `https://docs.lucee.org/skill/${id}.md`;

async function routes(topics: TopicSpec[], router = ROUTER): Promise<Record<string, Route>> {
	// ETags change with the content, like on docs.lucee.org
	const etag = async (body: string) => `"${(await sha256(body)).slice(0, 16)}"`;
	const json = await manifest(topics, router);
	const r: Record<string, Route> = {
		[SOURCE]: sourceRoute(router, await etag(router)),
		[MANIFEST]: sourceRoute(json, await etag(json))
	};
	for (const t of topics) r[topicUrl(t.id)] = sourceRoute(t.body, await etag(t.body));
	return r;
}

async function runCron() {
	const ctx = createExecutionContext();
	const p = worker.scheduled(createScheduledController({ cron: "0 * * * *" }) as never, testEnv(), ctx);
	await waitOnExecutionContext(ctx);
	return p;
}

const stored = (file: string) => kv().get<CachedSkill>(cacheKey(file), "json");

beforeEach(resetState);
afterEach(() => vi.restoreAllMocks());

describe("cron refresh with skills.json", () => {
	it("mirrors the manifest, the router and every topic file it lists", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }, { id: "orm", body: ORM }]));
		await runCron();
		expect(calls.map((r) => r.url).sort()).toEqual([MANIFEST, SOURCE, topicUrl("ai"), topicUrl("orm")].sort());
		expect((await stored("skill/ai.md"))?.body).toBe(AI);
		expect((await stored("skill/orm.md"))?.body).toBe(ORM);
		expect((await stored("main.skill"))?.body).toBe(ROUTER);

		// second run revalidates everything with conditional GETs
		await runCron();
		expect(calls.slice(4).every((r) => r.headers.get("if-none-match") !== null)).toBe(true);
	});

	it("picks up a new topic without any configuration change", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		await runCron();
		expect(await stored("skill/orm.md")).toBeNull();
		expect((await call("/skill/orm.md")).status).toBe(404);

		mockFetch(await routes([{ id: "ai", body: AI }, { id: "orm", body: ORM }]));
		await runCron();
		expect((await stored("skill/orm.md"))?.body).toBe(ORM);
		const res = await call("/skill/orm.md");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(ORM);
	});

	it("does not store a topic file that does not match its sha256 and keeps the last good copy", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		await runCron();

		// the manifest announces a new version, but the file still has the old content
		const r = await routes([{ id: "ai", body: AI + "new\n" }]);
		r[topicUrl("ai")] = (await routes([{ id: "ai", body: AI }]))[topicUrl("ai")];
		mockFetch(r);
		await expect(runCron()).rejects.toThrow(/skill\/ai\.md: .*does not match the sha256/);
		// asked for the full body, not a conditional GET, since the copy no longer matches
		const aiCall = calls.find((c) => c.url === topicUrl("ai"))!;
		expect(aiCall.headers.get("if-none-match")).toBeNull();
		expect((await stored("skill/ai.md"))?.body).toBe(AI);
		expect(await (await call("/skill/ai.md")).text()).toBe(AI);
	});

	it("checks the router against the manifest too", async () => {
		const r = await routes([{ id: "ai", body: AI }]);
		r[SOURCE] = sourceRoute(ROUTER + "tampered\n", '"router-x"');
		mockFetch(r);
		await expect(runCron()).rejects.toThrow(/main\.skill: .*does not match the sha256/);
		expect(await stored("main.skill")).toBeNull();
	});

	it("keeps the last good manifest when the new one is invalid", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		await runCron();
		const good = (await stored("skills.json"))!.body;

		const r = await routes([{ id: "ai", body: AI }, { id: "evil", body: "x", url: "https://example.org/evil.md" }]);
		mockFetch(r);
		await expect(runCron()).rejects.toThrow(/skills\.json: .*topic "evil" is not on https:\/\/docs\.lucee\.org/);
		expect((await stored("skills.json"))?.body).toBe(good);
		expect(calls.some((c) => c.url.startsWith("https://example.org"))).toBe(false);
		// the topics of the last good manifest are still refreshed
		expect(calls.some((c) => c.url === topicUrl("ai"))).toBe(true);
	});
});

describe("serving topic files", () => {
	it("serves /skills.json and /skill/<id>.md, fetching them on first request", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		const json = await call("/skills.json");
		expect(json.status).toBe(200);
		expect(json.headers.get("content-type")).toBe("application/json; charset=utf-8");
		expect(JSON.parse(await json.text()).topics[0].id).toBe("ai");

		const md = await call("/skill/ai.md");
		expect(md.status).toBe(200);
		expect(md.headers.get("content-type")).toBe("text/markdown; charset=utf-8");
		expect(md.headers.get("etag")).toBe(`"${(await sha256(AI)).slice(0, 32)}"`);
		expect(await md.text()).toBe(AI);

		const head = await call("/skill/ai.md", { method: "HEAD" });
		expect(head.headers.get("content-length")).toBe(String(new TextEncoder().encode(AI).byteLength));

		// /main.skill stays the router for existing installs
		expect(await (await call("/main.skill")).text()).toBe(ROUTER);
	});

	it("404s topics that are not in the manifest and paths outside /skill/<id>.md", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		for (const path of ["/skill/nope.md", "/skill/.md", "/skill/ai.txt", "/skill/", "/skill/a/b.md"]) {
			expect((await call(path)).status, path).toBe(404);
		}
		expect(calls.some((c) => c.url.includes("nope"))).toBe(false);
	});

	it("answers 503 when the manifest is not available", async () => {
		mockFetch({ [SOURCE]: sourceRoute(ROUTER) });
		vi.spyOn(console, "error").mockImplementation(() => undefined);
		const res = await call("/skill/ai.md");
		expect(res.status).toBe(503);
		expect(await res.text()).toBe("skills.json not available");
	});

	it("serves no topic files when SKILL_MANIFEST_URL is empty", async () => {
		mockFetch(await routes([{ id: "ai", body: AI }]));
		expect((await call("/skills.json", {}, { SKILL_MANIFEST_URL: "" })).status).toBe(404);
		expect((await call("/skill/ai.md", {}, { SKILL_MANIFEST_URL: "" })).status).toBe(404);
		expect(calls).toHaveLength(0);
	});
});

describe("landing page with topics", () => {
	it("lists the router and every topic with entries, size and tokens", async () => {
		mockFetch(await routes([{ id: "ai", body: AI, entries: 9 }, { id: "orm", body: ORM }]));
		await runCron();
		const html = await (await call("/")).text();
		expect(html).toContain('<div class="skill-card-name">lucee</div>');
		expect(html).toContain(`<span class="skill-meta-chip">${new TextEncoder().encode(ROUTER).byteLength} B</span>`);
		expect(html).toContain("<h2 class=\"section-title\">Topic Indexes</h2>");
		expect(html).toContain('<a href="/skill/ai.md">AI</a><div class="topic-id">ai</div>');
		expect(html).toContain("<td>ai things</td>");
		expect(html).toContain('<td class="num">9</td>');
		expect(html).toContain(`<td class="num">${new TextEncoder().encode(AI).byteLength} B<br>~600 tokens</td>`);
		expect(html).toContain('<a href="/skill/orm.md">ORM</a>');
		expect(html).toContain('<a href="/skills.json">skills.json</a>');
	});

	it("refreshes a router copy the manifest says is outdated right away (no stale size until the next cron)", async () => {
		// the old, big router is still mirrored
		const OLD = SKILL + "x".repeat(5000);
		mockFetch({ [SOURCE]: sourceRoute(OLD, '"old"') });
		await call("/main.skill");
		expect((await stored("main.skill"))?.body).toBe(OLD);

		// docs.lucee.org now publishes the router and skills.json
		mockFetch(await routes([{ id: "ai", body: AI }]));
		const first = await (await call("/")).text();
		// topics not mirrored yet show their token estimate only
		expect(first).toContain('<td class="num">~600 tokens</td>');
		// the background refresh replaced the router and fetched the topic
		expect((await stored("main.skill"))?.body).toBe(ROUTER);
		expect((await stored("skill/ai.md"))?.body).toBe(AI);
		const second = await (await call("/")).text();
		expect(second).toContain(`<span class="skill-meta-chip">${new TextEncoder().encode(ROUTER).byteLength} B</span>`);
		expect(second).toContain(`${new TextEncoder().encode(AI).byteLength} B<br>~600 tokens`);
	});
});
