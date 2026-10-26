import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { SKILL_CACHE_CONTROL } from "../src/index";
import { cacheKey, type CachedSkill } from "../src/store";
import {
	SKILL,
	SOURCE,
	SOURCE_ETAG,
	SOURCE_LAST_MODIFIED,
	call,
	calls,
	kv,
	mockFetch,
	resetState,
	sourceRoute,
	testEnv
} from "./helpers";

async function runCron() {
	const ctx = createExecutionContext();
	const p = worker.scheduled(createScheduledController({ cron: "0 * * * *" }) as never, testEnv(), ctx);
	await waitOnExecutionContext(ctx);
	return p;
}

async function stored(file = "main.skill") {
	return kv().get<CachedSkill>(cacheKey(file), "json");
}

beforeEach(resetState);
afterEach(() => vi.restoreAllMocks());

describe("skill file", () => {
	it("fetches lazily when KV is empty and stores the copy", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		const res = await call("/main.skill");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(SKILL);
		expect(res.headers.get("content-type")).toBe("text/plain; charset=utf-8");
		expect(res.headers.get("last-modified")).toBe(SOURCE_LAST_MODIFIED);
		expect(res.headers.get("cache-control")).toBe(SKILL_CACHE_CONTROL);
		expect(res.headers.get("etag")).toMatch(/^"[0-9a-f]{32}"$/);

		const s = await stored();
		expect(s?.body).toBe(SKILL);
		expect(s?.sourceEtag).toBe(SOURCE_ETAG);
		expect(calls.map((r) => r.headers.get("user-agent"))).toEqual(["lucee-skill-worker"]);

		// served from KV from now on
		await call("/main.skill");
		expect(calls).toHaveLength(1);
	});

	it("answers 304 for a matching If-None-Match or If-Modified-Since", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		const first = await call("/main.skill");
		const etag = first.headers.get("etag")!;

		const byEtag = await call("/main.skill", { headers: { "if-none-match": `W/${etag}` } });
		expect(byEtag.status).toBe(304);
		expect(byEtag.headers.get("etag")).toBe(etag);
		expect(await byEtag.text()).toBe("");

		const byDate = await call("/main.skill", { headers: { "if-modified-since": SOURCE_LAST_MODIFIED } });
		expect(byDate.status).toBe(304);

		const older = await call("/main.skill", { headers: { "if-modified-since": "Thu, 01 Jan 2026 00:00:00 GMT" } });
		expect(older.status).toBe(200);

		// If-None-Match wins over If-Modified-Since
		const other = await call("/main.skill", {
			headers: { "if-none-match": '"other"', "if-modified-since": SOURCE_LAST_MODIFIED }
		});
		expect(other.status).toBe(200);
	});

	it("HEAD has no body but the GET length", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		const res = await call("/main.skill", { method: "HEAD" });
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("");
		expect(res.headers.get("content-length")).toBe(String(new TextEncoder().encode(SKILL).byteLength));
	});

	it("answers 503 when nothing is cached and the source fails", async () => {
		mockFetch({ [SOURCE]: new Response("down", { status: 502 }) });
		const res = await call("/main.skill");
		expect(res.status).toBe(503);
		expect(await res.text()).toBe("main.skill not available");
		expect(await stored()).toBeNull();
	});

	it("does not store an empty body", async () => {
		mockFetch({ [SOURCE]: new Response("  \n", { status: 200 }) });
		expect((await call("/main.skill")).status).toBe(503);
		expect(await stored()).toBeNull();
	});

	it("refreshes a stale copy in the background and keeps it when the source is down", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		await call("/main.skill");
		const s = (await stored())!;
		await kv().put(cacheKey("main.skill"), JSON.stringify({ ...s, fetchedAt: Date.now() - 2 * 3600_000 }));

		mockFetch({ [SOURCE]: new Response("down", { status: 500 }) });
		const logged = vi.spyOn(console, "error").mockImplementation(() => undefined);
		const res = await call("/main.skill");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(SKILL);
		expect(calls).toHaveLength(1);
		expect((await stored())?.body).toBe(SKILL);
		expect(logged).toHaveBeenCalledWith(
			expect.stringContaining("background refresh of main.skill failed"),
			expect.any(Error)
		);
	});

	it("only serves files listed in SKILLS", async () => {
		mockFetch({
			[SOURCE]: sourceRoute(),
			"https://docs.lucee.org/extensions.skill": sourceRoute("---\nname: ext\n---\n", '"e"')
		});
		expect((await call("/extensions.skill")).status).toBe(404);
		const res = await call("/extensions.skill", {}, { SKILLS: "main.skill,extensions.skill" });
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("---\nname: ext\n---\n");
		expect((await call("/lucee.skill")).status).toBe(404);
		expect(calls.map((r) => r.url)).toEqual(["https://docs.lucee.org/extensions.skill"]);
	});
});

describe("cron refresh", () => {
	it("stores the file, then revalidates with a conditional GET", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		await runCron();
		const first = (await stored())!;
		expect(first.body).toBe(SKILL);

		await runCron();
		expect(calls).toHaveLength(2);
		expect(calls[1].headers.get("if-none-match")).toBe(SOURCE_ETAG);
		expect(calls[1].headers.get("if-modified-since")).toBe(SOURCE_LAST_MODIFIED);
		const second = (await stored())!;
		expect(second.etag).toBe(first.etag);
		expect(second.fetchedAt).toBeGreaterThanOrEqual(first.fetchedAt);
	});

	it("picks up a changed file", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		await runCron();
		const before = (await stored())!;
		mockFetch({ [SOURCE]: sourceRoute(SKILL + "more\n", '"src-2"', "Sat, 24 Oct 2026 10:00:00 GMT") });
		await runCron();
		const after = (await stored())!;
		expect(after.body).toBe(SKILL + "more\n");
		expect(after.etag).not.toBe(before.etag);
		expect(after.lastModified).toBe("Sat, 24 Oct 2026 10:00:00 GMT");
	});

	it("throws when the source fails but keeps the last good copy", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		await runCron();
		mockFetch({ [SOURCE]: new Response("down", { status: 503 }) });
		await expect(runCron()).rejects.toThrow(/main\.skill: .*answered 503/);
		expect((await stored())?.body).toBe(SKILL);
		const res = await call("/main.skill");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(SKILL);
	});
});

describe("landing page", () => {
	it("renders the skill card like index.cfm", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		for (const path of ["/", "/index.cfm"]) {
			const res = await call(path);
			expect(res.status).toBe(200);
			expect(res.headers.get("content-type")).toBe("text/html; charset=utf-8");
			const html = await res.text();
			expect(html).toContain("<h3>Lucee Docs</h3>");
			expect(html).toContain('<div class="skill-card-name">lucee-docs</div>');
			expect(html).toContain("<p>Lucee CFML documentation index. Use it for recipes, guides and technical specs.</p>");
			expect(html).toContain("Updated Oct 23, 2026");
			expect(html).toContain("Refreshed hourly from docs.lucee.org");
			expect(html).toContain('<a class="skill-url" href="/main.skill">https://skl.lucee-services.com/main.skill</a>');
			expect(html).toContain('href="/res/skill.css?v=1"');
		}
	});

	it("escapes the frontmatter and lists no card when the skill is unavailable", async () => {
		mockFetch({ [SOURCE]: sourceRoute('---\nname: x<script>\ndescription: "a" & b\n---\n') });
		const html = await (await call("/")).text();
		expect(html).toContain('<div class="skill-card-name">x&lt;script&gt;</div>');
		expect(html).toContain("<p>&quot;a&quot; &amp; b</p>");

		await resetState();
		mockFetch({ [SOURCE]: new Response("down", { status: 500 }) });
		vi.spyOn(console, "error").mockImplementation(() => undefined);
		const res = await call("/");
		expect(res.status).toBe(200);
		expect(await res.text()).not.toContain('class="skill-card"');
	});
});

describe("health and routing", () => {
	it("reports ok when the skill is available", async () => {
		mockFetch({ [SOURCE]: sourceRoute() });
		for (const path of ["/health", "/health.cfm"]) {
			const res = await call(path);
			expect(res.status).toBe(200);
			expect(await res.text()).toBe("ok");
			expect(res.headers.get("cache-control")).toBe("no-store");
		}
	});

	it("reports 503 when the skill is not available", async () => {
		mockFetch({ [SOURCE]: new Response("down", { status: 500 }) });
		vi.spyOn(console, "error").mockImplementation(() => undefined);
		const res = await call("/health");
		expect(res.status).toBe(503);
		expect(await res.text()).toBe("main.skill not available");
	});

	it("404s unknown paths and 405s other methods", async () => {
		mockFetch({});
		const res = await call("/nope");
		expect(res.status).toBe(404);
		expect(await res.text()).toBe("Not Found");
		const post = await call("/main.skill", { method: "POST", body: "x" });
		expect(post.status).toBe(405);
		expect(post.headers.get("allow")).toBe("GET, HEAD");
		expect(calls).toHaveLength(0);
	});

	it("answers 500 on a configuration error", async () => {
		mockFetch({});
		vi.spyOn(console, "error").mockImplementation(() => undefined);
		const res = await call("/main.skill", {}, { SKILLS: "bad name" });
		expect(res.status).toBe(500);
		expect(await res.text()).toMatch(/Invalid skill file name/);
	});
});
