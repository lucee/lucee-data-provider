import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/env";
import worker from "../src/index";
import { CDN, GITHUB, GROUP_METADATA, REDIS_METADATA, call, calls, forgeboxRoute, mockFetch, resetState, testEnv } from "./helpers";

const bindings = env as unknown as Env;
const R2 = { R2_MODE: "serve" } as const;
const FILL = { R2_MODE: "serve", R2_FILL_ON_MISS: "true" } as const;

const baseRoutes = () => ({
	"https://www.forgebox.io/rest/extension/provider/info?type=all&withLogo=false": forgeboxRoute(),
	"https://extension.lucee.org/rest/extension/provider/info?type=all&withLogo=false": Response.json({ extensions: [] }),
	[`${CDN}org/lucee/maven-metadata.xml`]: GROUP_METADATA,
	[`${CDN}org/lucee/redis-extension/maven-metadata.xml`]: REDIS_METADATA
});

beforeEach(async () => {
	await resetState();
});
afterEach(() => {
	vi.restoreAllMocks();
});

describe("upstream mirror (org.lucee)", () => {
	it("passes maven-metadata.xml through from the CDN", async () => {
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml");
		expect(res.status).toBe(200);
		expect(res.headers.get("content-type")).toContain("xml");
		expect(await res.text()).toBe(REDIS_METADATA);
	});

	it("caches group-level upstream files in KV", async () => {
		mockFetch(baseRoutes());
		await call("/org/lucee/maven-metadata.xml");
		const stored = await bindings.BRIDGE_CACHE.get(`upstream:${CDN}org/lucee/maven-metadata.xml`, "json");
		expect(stored).toMatchObject({ body: GROUP_METADATA });
	});

	it("redirects an extension file to the CDN when it exists", async () => {
		const path = "org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex";
		mockFetch({ ...baseRoutes(), [CDN + path]: "lex" });
		const res = await call("/" + path);
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(CDN + path);
		expect(calls).toContain(`HEAD ${CDN}${path}`);
	});

	it("answers 404 when the CDN has no such file", async () => {
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/redis-extension/9.9.9.9/redis-extension-9.9.9.9.lex");
		expect(res.status).toBe(404);
	});

	it("redirects 7.1+ core jars to GitHub Releases", async () => {
		const gh = `${GITHUB}7.1.0.10/lucee-7.1.0.10.jar`;
		mockFetch({ ...baseRoutes(), [gh]: "jar" });
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar");
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(gh);
	});

	it("falls back to the legacy CDN layout for older core builds", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}lucee-light-6.2.0.321.jar`]: "jar" });
		const res = await call("/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar");
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(`${CDN}lucee-light-6.2.0.321.jar`);
		expect(calls.some((c) => c.includes("github.com"))).toBe(false);
	});

	it("serves HEAD without a body", async () => {
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", { method: "HEAD" });
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("");
	});
});

describe("REST provider (io.forgebox)", () => {
	it("redirects a lex to the ForgeBox download", async () => {
		mockFetch(baseRoutes());
		const res = await call("/io/forgebox/ortus-mongodb-cache-extension/1.2.0.5291/ortus-mongodb-cache-extension-1.2.0.5291.lex");
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(
			"https://www.forgebox.io/rest/extension/provider/full/6A03159F-C6DC-4FCC-95A068B1E1A903FA?version=1%2E2%2E0%2E5291"
		);
	});

	it("answers like production for an unknown artifact", async () => {
		mockFetch(baseRoutes());
		const res = await call("/io/forgebox/nope-extension/1/nope-extension-1.lex");
		expect(res.status).toBe(404);
		expect(await res.text()).toBe("No [lex] artifact for [io.forgebox:nope-extension:1]");
	});

	it("builds artifact metadata", async () => {
		mockFetch(baseRoutes());
		const res = await call("/io/forgebox/ortus-redis-cache-extension/maven-metadata.xml");
		expect(res.status).toBe(200);
		expect(await res.text()).toContain("<artifactId>ortus-redis-cache-extension</artifactId>");
	});

	it("caches the provider index in KV", async () => {
		mockFetch(baseRoutes());
		await call("/io/forgebox/maven-metadata.xml");
		expect(await bindings.BRIDGE_CACHE.get("index:io.forgebox")).not.toBeNull();
	});
});

describe("R2", () => {
	const path = "org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex";
	const body = "0123456789abcdef";

	it("serves an object from R2 with metadata", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put(path, body);
		const res = await call("/" + path, {}, R2);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-length")).toBe(String(body.length));
		expect(res.headers.get("etag")).toMatch(/^".+"$/);
		expect(res.headers.get("accept-ranges")).toBe("bytes");
		expect(await res.text()).toBe(body);
		expect(calls.some((c) => c.includes(path))).toBe(false);
	});

	it("supports Range requests", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put(path, body);
		const res = await call("/" + path, { headers: { range: "bytes=2-5" } }, R2);
		expect(res.status).toBe(206);
		expect(res.headers.get("content-range")).toBe(`bytes 2-5/${body.length}`);
		expect(await res.text()).toBe("2345");
	});

	it("answers HEAD from R2 without a body", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put(path, body);
		const res = await call("/" + path, { method: "HEAD" }, R2);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-length")).toBe(String(body.length));
		expect(await res.text()).toBe("");
	});

	it("answers 304 for a matching If-None-Match", async () => {
		mockFetch(baseRoutes());
		const obj = await bindings.ARTIFACTS!.put(path, body);
		const res = await call("/" + path, { headers: { "if-none-match": obj!.httpEtag } }, R2);
		expect(res.status).toBe(304);
	});

	it("uses the legacy key layout for core files", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put("lucee-7.1.0.10.jar", "core");
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", {}, R2);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("core");
	});

	it("falls back to the upstream redirect on a miss", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		const res = await call("/" + path, {}, R2);
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(CDN + path);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("ignores the bucket when R2_MODE is off", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		await bindings.ARTIFACTS!.put(path, body);
		const res = await call("/" + path);
		expect(res.status).toBe(302);
	});

	it("serves maven-metadata.xml from R2 when present", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put("org/lucee/redis-extension/maven-metadata.xml", "<metadata/>");
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, R2);
		expect(await res.text()).toBe("<metadata/>");
	});
});

describe("R2 fill-on-miss", () => {
	const path = "org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex";
	const body = "extension-bytes";

	it("streams the upstream file and stores it in R2", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(body);
		const stored = await bindings.ARTIFACTS!.get(path);
		expect(stored).not.toBeNull();
		expect(await stored!.text()).toBe(body);
		expect(stored!.httpMetadata?.contentType).toBe("application/octet-stream");
		expect(stored!.customMetadata?.source).toBe(CDN + path);

		// the next request is served from R2 without touching the upstream
		mockFetch(baseRoutes());
		const again = await call("/" + path, {}, FILL);
		expect(await again.text()).toBe(body);
		expect(calls.some((c) => c.includes(path))).toBe(false);
	});

	it("fills core jars from GitHub Releases under the legacy key", async () => {
		const gh = `${GITHUB}7.1.0.10/lucee-7.1.0.10.jar`;
		mockFetch({ ...baseRoutes(), [gh]: "jar-bytes" });
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", {}, FILL);
		expect(res.status).toBe(200);
		const stored = await bindings.ARTIFACTS!.get("lucee-7.1.0.10.jar");
		expect(await stored!.text()).toBe("jar-bytes");
		expect(stored!.httpMetadata?.contentType).toBe("application/java-archive");
	});

	it("never stores SNAPSHOT files", async () => {
		const snap = "org/lucee/redis-extension/3.0.0.1-SNAPSHOT/redis-extension-3.0.0.1-SNAPSHOT.lex";
		mockFetch({ ...baseRoutes(), [CDN + snap]: body });
		const res = await call("/" + snap, {}, FILL);
		expect(res.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(snap)).toBeNull();
	});

	it("never stores maven-metadata.xml", async () => {
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, FILL);
		expect(res.status).toBe(200);
		expect((await bindings.ARTIFACTS!.list()).objects).toHaveLength(0);
	});

	it("does not fill on HEAD or Range requests", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		expect((await call("/" + path, { method: "HEAD" }, FILL)).status).toBe(302);
		expect((await call("/" + path, { headers: { range: "bytes=0-1" } }, FILL)).status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("does not store non-200 upstream answers", async () => {
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) => (req.method === "HEAD" ? new Response(null, { status: 200 }) : new Response("busy", { status: 503 }))
		});
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("streams without storing when the upstream sends no content-length", async () => {
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) =>
				req.method === "HEAD"
					? new Response(null, { status: 200 })
					: new Response(new Blob([body]).stream(), { status: 200 })
		});
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(body);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("does not fill when the flag is off", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		const res = await call("/" + path, {}, R2);
		expect(res.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});
});

describe("flush", () => {
	it("is forbidden without a token", async () => {
		mockFetch(baseRoutes());
		const res = await call("/health?flush=true");
		expect(res.status).toBe(403);
		expect(await res.text()).toBe("Forbidden");
	});

	it("is forbidden with a wrong token", async () => {
		mockFetch(baseRoutes());
		const res = await call("/health?flush=true", { headers: { "x-flush-token": "wrong" } });
		expect(res.status).toBe(403);
	});

	it("is disabled when FLUSH_TOKEN is not set", async () => {
		mockFetch(baseRoutes());
		const res = await call("/health?flush=true", { headers: { "x-flush-token": "test-flush-token" } }, { FLUSH_TOKEN: "" });
		expect(res.status).toBe(403);
		expect(await res.text()).toBe("Flush is disabled");
	});

	it("flushes and resyncs with the right token", async () => {
		mockFetch(baseRoutes());
		await bindings.BRIDGE_CACHE.put("index:io.forgebox", JSON.stringify({ stale: true }));
		const before = await bindings.BRIDGE_CACHE.get("cache-generation");
		const res = await call("/health?flush=1", { headers: { authorization: "Bearer test-flush-token" } });
		expect(res.status).toBe(200);
		const json = (await res.json()) as Record<string, unknown>;
		expect(json.status).toBe("ok");
		expect(await bindings.BRIDGE_CACHE.get("cache-generation")).not.toBe(before);
		const index = await bindings.BRIDGE_CACHE.get("index:io.forgebox", "json");
		expect(index).not.toMatchObject({ stale: true });
	});

	it("is not triggered by flush=false", async () => {
		mockFetch(baseRoutes());
		const res = await call("/health?flush=false");
		expect(res.status).toBe(200);
	});
});

describe("health, landing and scheduled", () => {
	it("reports providers", async () => {
		mockFetch(baseRoutes());
		const res = await call("/health");
		expect(res.status).toBe(200);
		const json = (await res.json()) as { status: string; providers: { groupId: string }[] };
		expect(json.status).toBe("ok");
		expect(Object.keys(json)).toEqual(["status", "artifactCount", "providers"]);
		expect(json.providers.map((p) => p.groupId)).toEqual(["org.lucee", "io.forgebox"]);
	});

	it("renders the landing page", async () => {
		mockFetch(baseRoutes());
		const res = await call("/");
		expect(res.status).toBe(200);
		const html = await res.text();
		expect(html).toContain("org.lucee");
		expect(html).toContain("io.forgebox");
	});

	it("answers 404 for unknown paths", async () => {
		mockFetch(baseRoutes());
		expect((await call("/com/example/thing")).status).toBe(404);
	});

	it("fills KV from the cron trigger", async () => {
		mockFetch(baseRoutes());
		const ctx = createExecutionContext();
		await worker.scheduled(createScheduledController({ cron: "0 * * * *" }) as never, testEnv(), ctx);
		await waitOnExecutionContext(ctx);
		expect(await bindings.BRIDGE_CACHE.get("index:io.forgebox")).not.toBeNull();
		expect(await bindings.BRIDGE_CACHE.get(`upstream:${CDN}org/lucee/maven-metadata.xml`)).not.toBeNull();
	});

	it("fails the cron run when a provider cannot be synced", async () => {
		mockFetch({ ...baseRoutes(), "https://www.forgebox.io/rest/extension/provider/info?type=all&withLogo=false": new Response("down", { status: 500 }) });
		const ctx = createExecutionContext();
		await expect(worker.scheduled(createScheduledController() as never, testEnv(), ctx)).rejects.toThrow();
		await waitOnExecutionContext(ctx);
	});
});
