import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../src/env";
import worker from "../src/index";
import { CDN, GITHUB, GROUP_METADATA, REDIS_METADATA, call, calls, forgeboxRoute, mockFetch, resetState, testEnv, type Route } from "./helpers";

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
		// the Maven layout is checked first
		const maven = calls.indexOf(`HEAD ${CDN}org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar`);
		const legacy = calls.indexOf(`HEAD ${CDN}lucee-light-6.2.0.321.jar`);
		expect(maven).toBeGreaterThanOrEqual(0);
		expect(legacy).toBeGreaterThan(maven);
	});

	it.each([
		["snapshot", "8.0.1.12-SNAPSHOT"],
		["RC", "8.0.0.294-RC"],
		["7.1+ final", "7.1.0.10"]
	])("redirects a %s core pom to the Maven layout on the CDN", async (_label, version) => {
		const path = `org/lucee/lucee/${version}/lucee-${version}.pom`;
		mockFetch({ ...baseRoutes(), [CDN + path]: "<project/>" });
		const res = await call("/" + path);
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(CDN + path);
		// poms are never GitHub Release assets, and the legacy flat name is not needed
		expect(calls.some((c) => c.includes("github.com"))).toBe(false);
		expect(calls).not.toContain(`HEAD ${CDN}lucee-${version}.pom`);
	});

	it("redirects snapshot core jars and lco files to the Maven layout", async () => {
		const jar = "org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.jar";
		const lco = "org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.lco";
		mockFetch({ ...baseRoutes(), [CDN + jar]: "jar", [CDN + lco]: "lco", [`${CDN}lucee-8.0.1.12-SNAPSHOT.jar`]: "jar" });
		const res = await call("/" + jar);
		expect(res.headers.get("location")).toBe(CDN + jar);
		const resLco = await call("/" + lco);
		expect(resLco.headers.get("location")).toBe(CDN + lco);
	});

	it("prefers GitHub Releases over the Maven layout for 7.1+ jars", async () => {
		const gh = `${GITHUB}8.0.0.294/lucee-8.0.0.294-RC.jar`;
		const maven = "org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.jar";
		mockFetch({ ...baseRoutes(), [gh]: "jar", [CDN + maven]: "jar" });
		const res = await call("/" + maven);
		expect(res.headers.get("location")).toBe(gh);
		expect(calls).not.toContain(`HEAD ${CDN}${maven}`);
	});

	it("uses the Maven layout when a 7.1+ jar has no GitHub Release asset", async () => {
		const maven = "org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.jar";
		mockFetch({ ...baseRoutes(), [CDN + maven]: "jar", [`${CDN}lucee-8.0.0.294-RC.jar`]: "jar" });
		const res = await call("/" + maven);
		expect(res.headers.get("location")).toBe(CDN + maven);
	});

	it("still falls back to the legacy name when the Maven-layout check fails", async () => {
		const maven = `${CDN}org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar`;
		mockFetch({
			...baseRoutes(),
			[maven]: () => {
				throw new TypeError("network down");
			},
			[`${CDN}lucee-6.2.0.321.jar`]: "jar"
		});
		vi.spyOn(console, "warn").mockImplementation(() => {});
		const res = await call("/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar");
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(`${CDN}lucee-6.2.0.321.jar`);
	});

	it("answers 404 for a core file missing in every layout", async () => {
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/lucee/8.0.1.99-SNAPSHOT/lucee-8.0.1.99-SNAPSHOT.pom");
		expect(res.status).toBe(404);
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

	it("uses the Maven-layout key for core files", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put("org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.pom", "<project/>");
		await bindings.ARTIFACTS!.put("org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", "maven");
		await bindings.ARTIFACTS!.put("lucee-7.1.0.10.jar", "legacy");
		const pom = await call("/org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.pom", {}, R2);
		expect(pom.status).toBe(200);
		expect(await pom.text()).toBe("<project/>");
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", {}, R2);
		expect(await res.text()).toBe("maven");
	});

	it("falls back to the legacy key for core files copied from the CDN root", async () => {
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

	it("serves maven-metadata.xml from R2 only when the upstream does not have it", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}org/lucee/redis-extension/maven-metadata.xml`]: new Response("missing", { status: 404 }) });
		await bindings.ARTIFACTS!.put("org/lucee/redis-extension/maven-metadata.xml", "<metadata/>");
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, R2);
		expect(await res.text()).toBe("<metadata/>");
	});

	it("prefers the upstream maven-metadata.xml over an old copy in R2", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put("org/lucee/redis-extension/maven-metadata.xml", "<old/>");
		await bindings.ARTIFACTS!.put("org/lucee/maven-metadata.xml", "<old/>");
		expect(await (await call("/org/lucee/redis-extension/maven-metadata.xml", {}, R2)).text()).toBe(REDIS_METADATA);
		expect(await (await call("/org/lucee/maven-metadata.xml", {}, R2)).text()).toBe(GROUP_METADATA);
	});

	it("falls back to the R2 copy of maven-metadata.xml when the upstream fails", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}org/lucee/redis-extension/maven-metadata.xml`]: new Response("down", { status: 503 }) });
		await bindings.ARTIFACTS!.put("org/lucee/redis-extension/maven-metadata.xml", "<metadata/>");
		expect(await (await call("/org/lucee/redis-extension/maven-metadata.xml", {}, R2)).text()).toBe("<metadata/>");
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

	it("fills core jars from GitHub Releases under the Maven-layout key", async () => {
		const gh = `${GITHUB}7.1.0.10/lucee-7.1.0.10.jar`;
		mockFetch({ ...baseRoutes(), [gh]: "jar-bytes" });
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", {}, FILL);
		expect(res.status).toBe(200);
		const stored = await bindings.ARTIFACTS!.get("org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar");
		expect(await stored!.text()).toBe("jar-bytes");
		expect(stored!.httpMetadata?.contentType).toBe("application/java-archive");
		expect(await bindings.ARTIFACTS!.head("lucee-7.1.0.10.jar")).toBeNull();
	});

	it("fills an RC core pom from the Maven layout on the CDN", async () => {
		const path = "org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.pom";
		mockFetch({ ...baseRoutes(), [CDN + path]: "<project/>" });
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("<project/>");
		const stored = await bindings.ARTIFACTS!.get(path);
		expect(await stored!.text()).toBe("<project/>");
		expect(stored!.customMetadata?.source).toBe(CDN + path);
	});

	it("fills older core builds from the legacy CDN name under the Maven-layout key", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}lucee-light-6.2.0.321.jar`]: "light-bytes" });
		const res = await call("/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar", {}, FILL);
		expect(res.status).toBe(200);
		const stored = await bindings.ARTIFACTS!.get("org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar");
		expect(await stored!.text()).toBe("light-bytes");
		expect(stored!.customMetadata?.source).toBe(`${CDN}lucee-light-6.2.0.321.jar`);
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

	it("asks the source for an unencoded body", async () => {
		let acceptEncoding: string | null = null;
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) => {
				if (req.method === "GET") acceptEncoding = req.headers.get("accept-encoding");
				return new Response(req.method === "HEAD" ? null : body, { status: 200, headers: { "content-length": String(body.length) } });
			}
		});
		expect((await call("/" + path, {}, FILL)).status).toBe(200);
		expect(acceptEncoding).toBe("identity");
	});

	it("stores larger files first and serves them from R2", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		const res = await call("/" + path, {}, { ...FILL, R2_FILL_STREAM_MAX_MB: "0" });
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(body);
		const stored = await bindings.ARTIFACTS!.head(path);
		expect(stored).not.toBeNull();
		expect(res.headers.get("etag")).toBe(stored!.httpEtag);
		expect(res.headers.get("content-length")).toBe(String(body.length));
	});

	it("does not store a file that ends before its content-length", async () => {
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) =>
				req.method === "HEAD"
					? new Response(null, { status: 200 })
					: new Response(new Blob([body]).stream(), { status: 200, headers: { "content-length": "100" } })
		});
		const res = await call("/" + path, {}, { ...FILL, R2_FILL_STREAM_MAX_MB: "0" });
		expect(res.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("streams without storing when the source sends an encoded body", async () => {
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) =>
				new Response(req.method === "HEAD" ? null : body, {
					status: 200,
					headers: { "content-length": "7", "content-encoding": "gzip" }
				})
		});
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-length")).not.toBe("7");
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("falls back to the redirect when the source cannot be reached", async () => {
		mockFetch({
			...baseRoutes(),
			[CDN + path]: (req) => (req.method === "HEAD" ? new Response(null, { status: 200 }) : Promise.reject(new TypeError("Network connection lost")))
		});
		const res = await call("/" + path, {}, FILL);
		expect(res.status).toBe(302);
		expect(res.headers.get("location")).toBe(CDN + path);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});

	it("does not fill when the flag is off", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: body });
		const res = await call("/" + path, {}, R2);
		expect(res.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();
	});
});

describe("R2 read-through of SNAPSHOT files", () => {
	const snap = "org/lucee/redis-extension/3.0.0.1-SNAPSHOT/redis-extension-3.0.0.1-SNAPSHOT.lex";
	const STALE = { ...FILL, R2_REVALIDATE_MINUTES: "0" } as const;

	/** CDN-like source: ETag validator, 304 on a matching If-None-Match */
	function source(state: { body: string; etag: string; seen: (string | null)[] }): Route {
		return (req) => {
			if (req.method === "GET") state.seen.push(req.headers.get("if-none-match"));
			if (req.headers.get("if-none-match") === state.etag) return new Response(null, { status: 304, headers: { etag: state.etag } });
			const headers = { etag: state.etag, "content-length": String(state.body.length), "last-modified": "Tue, 27 Oct 2026 16:21:27 GMT" };
			return new Response(req.method === "HEAD" ? null : state.body, { status: 200, headers });
		};
	}

	it("stores SNAPSHOT files with the source's validators and serves them from R2 while fresh", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		const res = await call("/" + snap, {}, FILL);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("snapshot-1");
		const stored = await bindings.ARTIFACTS!.head(snap);
		expect(stored!.customMetadata?.source).toBe(CDN + snap);
		expect(stored!.customMetadata?.sourceEtag).toBe('"v1"');
		expect(stored!.customMetadata?.sourceLastModified).toBe("Tue, 27 Oct 2026 16:21:27 GMT");

		mockFetch(baseRoutes());
		const again = await call("/" + snap, {}, FILL);
		expect(again.status).toBe(200);
		expect(await again.text()).toBe("snapshot-1");
		expect(calls.some((c) => c.includes(snap))).toBe(false);
		// HEAD of a fresh copy is answered from R2 too
		const head = await call("/" + snap, { method: "HEAD" }, FILL);
		expect(head.status).toBe(200);
		expect(head.headers.get("content-length")).toBe("10");
	});

	it("revalidates a stale copy with If-None-Match and keeps it on 304", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		await call("/" + snap, {}, STALE);
		const before = await bindings.ARTIFACTS!.head(snap);

		const res = await call("/" + snap, {}, STALE);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("snapshot-1");
		expect(state.seen).toEqual([null, '"v1"']);
		// not rewritten
		expect((await bindings.ARTIFACTS!.head(snap))!.uploaded.getTime()).toBe(before!.uploaded.getTime());
	});

	it("replaces a stale copy when the source has a new version", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		await call("/" + snap, {}, STALE);
		state.body = "snapshot-two";
		state.etag = '"v2"';

		const res = await call("/" + snap, {}, STALE);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("snapshot-two");
		const stored = await bindings.ARTIFACTS!.get(snap);
		expect(await stored!.text()).toBe("snapshot-two");
		expect(stored!.customMetadata?.sourceEtag).toBe('"v2"');
	});

	it("remembers a successful revalidation for R2_REVALIDATE_MINUTES", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		// stored long ago
		await bindings.ARTIFACTS!.put(snap, "snapshot-1", {
			customMetadata: { source: CDN + snap, filledAt: "2026-01-01T00:00:00.000Z", sourceEtag: '"v1"' }
		});
		expect(await (await call("/" + snap, {}, FILL)).text()).toBe("snapshot-1");
		expect(state.seen).toEqual(['"v1"']);
		expect(await (await call("/" + snap, {}, FILL)).text()).toBe("snapshot-1");
		expect(state.seen).toEqual(['"v1"']);
	});

	it("falls back to If-Modified-Since when the source sent no ETag", async () => {
		let ims: string | null = null;
		mockFetch({
			...baseRoutes(),
			[CDN + snap]: (req) => {
				ims = req.headers.get("if-modified-since");
				return new Response(null, { status: 304 });
			}
		});
		await bindings.ARTIFACTS!.put(snap, "old", {
			customMetadata: { source: CDN + snap, filledAt: "2026-01-01T00:00:00.000Z", sourceLastModified: "Tue, 27 Oct 2026 16:21:27 GMT" }
		});
		expect(await (await call("/" + snap, {}, FILL)).text()).toBe("old");
		expect(ims).toBe("Tue, 27 Oct 2026 16:21:27 GMT");
	});

	it("drops the stored copy when the source no longer has the file", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		const routes = { ...baseRoutes(), [CDN + snap]: source(state) };
		mockFetch(routes);
		await call("/" + snap, {}, STALE);
		mockFetch(baseRoutes());
		const res = await call("/" + snap, {}, STALE);
		expect(res.status).toBe(404);
		expect(res.headers.get("cache-control")).toBe("no-store");
		expect(await bindings.ARTIFACTS!.head(snap)).toBeNull();
	});

	it("serves the stored copy when the source cannot be reached", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		await call("/" + snap, {}, STALE);
		for (const failing of [() => Promise.reject(new TypeError("Network connection lost")), () => new Response("busy", { status: 503 })]) {
			mockFetch({ ...baseRoutes(), [CDN + snap]: failing as Route });
			const res = await call("/" + snap, {}, STALE);
			expect(res.status).toBe(200);
			expect(await res.text()).toBe("snapshot-1");
		}
		expect(await bindings.ARTIFACTS!.head(snap)).not.toBeNull();
	});

	it("redirects HEAD and Range requests for a stale copy instead of revalidating", async () => {
		const state = { body: "snapshot-1", etag: '"v1"', seen: [] as (string | null)[] };
		mockFetch({ ...baseRoutes(), [CDN + snap]: source(state) });
		await call("/" + snap, {}, STALE);
		state.seen = [];
		const head = await call("/" + snap, { method: "HEAD" }, STALE);
		expect(head.status).toBe(302);
		const range = await call("/" + snap, { headers: { range: "bytes=0-1" } }, STALE);
		expect(range.status).toBe(302);
		expect(state.seen).toEqual([]);
	});

	it("stores SNAPSHOT checksum files from the source instead of computing them", async () => {
		const pom = "org/lucee/redis-extension/3.0.0.1-SNAPSHOT/redis-extension-3.0.0.1-SNAPSHOT.pom";
		mockFetch({ ...baseRoutes(), [`${CDN}${pom}.sha1`]: "0123456789abcdef0123456789abcdef01234567" });
		const res = await call(`/${pom}.sha1`, {}, FILL);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("0123456789abcdef0123456789abcdef01234567");
		expect(calls.some((c) => c === `GET ${CDN}${pom}`)).toBe(false);
		const stored = await bindings.ARTIFACTS!.head(`${pom}.sha1`);
		expect(stored!.customMetadata?.source).toBe(`${CDN}${pom}.sha1`);
	});

	it("keeps SNAPSHOT files in R2 as they are when fill-on-miss is off", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put(snap, "copied", { customMetadata: { filledAt: "2026-01-01T00:00:00.000Z" } });
		const res = await call("/" + snap, {}, R2);
		expect(await res.text()).toBe("copied");
		expect(calls.some((c) => c.includes(snap))).toBe(false);
	});
});

describe("R2_HOSTS", () => {
	const path = "org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex";

	async function callHost(origin: string): Promise<Response> {
		const ctx = createExecutionContext();
		const res = await worker.fetch(
			new Request(origin + "/" + path) as never,
			testEnv({ ...FILL, R2_HOSTS: "mvn.lucee-services.com" }),
			ctx
		);
		const body = res.body ? await res.arrayBuffer() : null;
		await waitOnExecutionContext(ctx);
		return new Response(body, { status: res.status, headers: res.headers });
	}

	it("uses R2 only on the listed hostnames", async () => {
		mockFetch({ ...baseRoutes(), [CDN + path]: "extension-bytes" });
		const other = await callHost("https://maven.lucee-services.com");
		expect(other.status).toBe(302);
		expect(await bindings.ARTIFACTS!.head(path)).toBeNull();

		const listed = await callHost("https://mvn.lucee-services.com");
		expect(listed.status).toBe(200);
		expect(await bindings.ARTIFACTS!.head(path)).not.toBeNull();
		// the other hostname still redirects, even with the object in R2
		expect((await callHost("https://maven.lucee-services.com")).status).toBe(302);
	});
});

const sha1 = async (text: string, algo = "SHA-1") =>
	[...new Uint8Array(await crypto.subtle.digest(algo, new TextEncoder().encode(text)))].map((b) => b.toString(16).padStart(2, "0")).join("");

describe("checksums (org.lucee)", () => {
	const rc = "org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC";
	const pom = "<project><version>8.0.0.294-RC</version></project>";

	it("computes a core pom checksum the CDN does not have, and caches it in KV", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.pom`]: pom });
		const res = await call(`/${rc}.pom.sha1`);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-type")).toContain("text/plain");
		expect(await res.text()).toBe(await sha1(pom));
		// the upstream checksum file is tried first, Maven layout before the legacy name
		const maven = calls.indexOf(`HEAD ${CDN}${rc}.pom.sha1`);
		expect(maven).toBeGreaterThanOrEqual(0);
		expect(calls.indexOf(`HEAD ${CDN}lucee-8.0.0.294-RC.pom.sha1`)).toBeGreaterThan(maven);
		const gen = await bindings.BRIDGE_CACHE.get("cache-generation");
		expect(await bindings.BRIDGE_CACHE.get(`checksum:${gen}:sha1:${CDN}${rc}.pom`)).toBe(await sha1(pom));

		mockFetch(baseRoutes());
		const again = await call(`/${rc}.pom.sha1`);
		expect(await again.text()).toBe(await sha1(pom));
		expect(calls).not.toContain(`GET ${CDN}${rc}.pom`);
	});

	it("computes md5, sha256 and sha512 too, from a single download", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.pom`]: pom });
		expect(await (await call(`/${rc}.pom.md5`)).text()).toBe(await sha1(pom, "MD5"));
		expect(await (await call(`/${rc}.pom.sha256`)).text()).toBe(await sha1(pom, "SHA-256"));
		expect(await (await call(`/${rc}.pom.sha512`)).text()).toBe(await sha1(pom, "SHA-512"));
		expect(await (await call(`/${rc}.pom.sha1`)).text()).toBe(await sha1(pom));
		expect(calls.filter((c) => c === `GET ${CDN}${rc}.pom`)).toHaveLength(1);
	});

	it("caches checksums of immutable artifacts for 30 days", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.pom`]: pom });
		expect((await call(`/${rc}.pom.sha1`)).status).toBe(200);
		const keys = (await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys;
		expect(keys).toHaveLength(4);
		const now = Date.now() / 1000;
		for (const key of keys) {
			expect(key.expiration).toBeGreaterThan(now + 29 * 24 * 3600);
			expect(key.expiration).toBeLessThanOrEqual(now + 30 * 24 * 3600 + 60);
		}
	});

	it("hashes a 7.1+ core jar from GitHub Releases", async () => {
		const gh = `${GITHUB}7.1.0.10/lucee-7.1.0.10.jar`;
		mockFetch({ ...baseRoutes(), [gh]: "jar-bytes" });
		const res = await call("/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar.sha1");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await sha1("jar-bytes"));
		expect(calls).not.toContain(`HEAD ${GITHUB}7.1.0.10/lucee-7.1.0.10.jar.sha1`);
	});

	it("redirects to an upstream checksum file when there is one", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.jar.sha1`]: "abc", [`${CDN}lucee-6.2.0.321.jar.sha1`]: "def", [`${CDN}6.2.0.321.lco.sha1`]: "ghi" });
		const maven = await call(`/${rc}.jar.sha1`);
		expect(maven.status).toBe(302);
		expect(maven.headers.get("location")).toBe(`${CDN}${rc}.jar.sha1`);
		const legacy = await call("/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar.sha1");
		expect(legacy.headers.get("location")).toBe(`${CDN}lucee-6.2.0.321.jar.sha1`);
		const lco = await call("/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco.sha1");
		expect(lco.headers.get("location")).toBe(`${CDN}6.2.0.321.lco.sha1`);
	});

	it("computes an extension md5 when the CDN only has the sha1", async () => {
		const lex = "org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex";
		mockFetch({ ...baseRoutes(), [CDN + lex]: "lex-bytes", [`${CDN}${lex}.sha1`]: "x" });
		expect((await call(`/${lex}.sha1`)).status).toBe(302);
		const md5 = await call(`/${lex}.md5`);
		expect(md5.status).toBe(200);
		expect(await md5.text()).toBe(await sha1("lex-bytes", "MD5"));
	});

	it("caches snapshot checksums only for the cache TTL", async () => {
		const snap = "org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.pom";
		mockFetch({ ...baseRoutes(), [CDN + snap]: pom });
		expect(await (await call(`/${snap}.sha1`)).text()).toBe(await sha1(pom));
		const keys = (await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys;
		expect(keys).toHaveLength(4);
		const now = Date.now() / 1000;
		for (const key of keys) {
			expect(key.expiration).toBeGreaterThan(now);
			// CACHE_TTL_MINUTES = 60
			expect(key.expiration).toBeLessThanOrEqual(now + 3600 + 60);
		}
	});

	it("answers 404 when the artifact does not exist", async () => {
		mockFetch(baseRoutes());
		expect((await call(`/${rc}.jar.sha1`)).status).toBe(404);
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys).toHaveLength(0);
	});

	it("answers 404 for artifacts over CHECKSUM_MAX_MB", async () => {
		const big = "x".repeat(2048);
		mockFetch({
			...baseRoutes(),
			[`${CDN}${rc}.jar`]: big,
			[`${CDN}${rc}.war`]: (req) =>
				new Response(req.method === "HEAD" ? null : new Blob([big]).stream(), { status: 200 })
		});
		const limit = { CHECKSUM_MAX_MB: String(1024 / (1024 * 1024)) };
		const declared = await call(`/${rc}.jar.sha1`, {}, limit);
		expect(declared.status).toBe(404);
		expect(calls).toContain(`GET ${CDN}${rc}.jar`);
		// no content-length: the stream is cut off at the limit
		expect((await call(`/${rc}.war.sha1`, {}, limit)).status).toBe(404);
		expect((await call(`/${rc}.jar.sha1`, {}, { CHECKSUM_MAX_MB: "0" })).status).toBe(404);
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys).toHaveLength(0);
	});

	it("hashes the artifact from R2 without asking the upstream", async () => {
		mockFetch(baseRoutes());
		await bindings.ARTIFACTS!.put(`${rc}.jar`, "r2-bytes");
		const res = await call(`/${rc}.jar.sha1`, {}, R2);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await sha1("r2-bytes"));
		expect(calls.some((c) => c.includes(`${rc}.jar`) && !c.includes(".sha1"))).toBe(false);
		expect(await (await call(`/${rc}.jar.md5`, {}, R2)).text()).toBe(await sha1("r2-bytes", "MD5"));
	});

	it("stores computed checksums of immutable artifacts in R2 on fill-on-miss", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.pom`]: pom });
		expect((await call(`/${rc}.pom.sha1`, {}, FILL)).status).toBe(200);
		const stored = await bindings.ARTIFACTS!.get(`${rc}.pom.sha1`);
		expect(await stored!.text()).toBe(await sha1(pom));
		expect(stored!.customMetadata?.source).toBe("computed");
		// served from R2 from now on
		mockFetch(baseRoutes());
		expect(await (await call(`/${rc}.pom.sha1`, {}, FILL)).text()).toBe(await sha1(pom));
		expect(calls.some((c) => c.includes(rc))).toBe(false);
	});
});

describe("checksums of large artifacts (background)", () => {
	const version = "7.1.0.204";
	const path = `/org/lucee/lucee/${version}/lucee-${version}.jar`;
	const gh = `${GITHUB}${version}/lucee-${version}.jar`;
	// 4 KiB inline limit; the "jar" is 2.5 MiB, so it is read in several blocks
	const INLINE = { CHECKSUM_INLINE_MAX_MB: String(4096 / (1024 * 1024)) };
	const jar = new Uint8Array(2.5 * 1024 * 1024);
	for (let i = 0; i < jar.length; i++) jar[i] = (i * 7 + (i >> 10)) & 0xff;
	const digest = async (algo: string) =>
		[...new Uint8Array(await crypto.subtle.digest(algo, jar))].map((b) => b.toString(16).padStart(2, "0")).join("");
	const jarResponse = (req: Request, withLength = true) =>
		new Response(req.method === "HEAD" ? null : new Blob([jar]).stream(), {
			status: 200,
			headers: withLength ? { "content-length": String(jar.byteLength) } : {}
		});
	const gets = () => calls.filter((c) => c === `GET ${gh}`).length;
	const pendingKeys = async () => (await bindings.BRIDGE_CACHE.list({ prefix: "checksum-pending:" })).keys;

	it("answers 404 right away and caches every checksum computed in the background", async () => {
		mockFetch({ ...baseRoutes(), [gh]: (req) => jarResponse(req) });
		const first = await call(`${path}.sha1`, {}, INLINE);
		expect(first.status).toBe(404);
		// a 404 that turns into a 200 once the checksum is cached must not be kept by any cache
		expect(first.headers.get("cache-control")).toBe("no-store");
		// the request only read the headers; the same download was hashed in the background
		expect(gets()).toBe(1);
		const gen = await bindings.BRIDGE_CACHE.get("cache-generation");
		expect(await bindings.BRIDGE_CACHE.get(`checksum:${gen}:sha1:${gh}`)).toBe(await digest("SHA-1"));
		// a finished attempt leaves no attempt count behind
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum-attempts:" })).keys).toHaveLength(0);

		mockFetch({ ...baseRoutes(), [gh]: (req) => jarResponse(req) });
		const sha1 = await call(`${path}.sha1`, {}, INLINE);
		expect(sha1.status).toBe(200);
		expect(await sha1.text()).toBe(await digest("SHA-1"));
		expect(await (await call(`${path}.md5`, {}, INLINE)).text()).toBe(await digest("MD5"));
		expect(await (await call(`${path}.sha256`, {}, INLINE)).text()).toBe(await digest("SHA-256"));
		expect(await (await call(`${path}.sha512`, {}, INLINE)).text()).toBe(await digest("SHA-512"));
		expect(gets()).toBe(0);
	});

	it("hashes artifacts below CHECKSUM_INLINE_MAX_MB inside the request", async () => {
		mockFetch({ ...baseRoutes(), [gh]: (req) => jarResponse(req) });
		const res = await call(`${path}.sha1`);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await digest("SHA-1"));
		expect(gets()).toBe(1);
		expect(await pendingKeys()).toHaveLength(0);
	});

	it("moves a download without content-length to the background once it passes the inline limit", async () => {
		mockFetch({ ...baseRoutes(), [gh]: (req) => jarResponse(req, false) });
		expect((await call(`${path}.sha1`, {}, INLINE)).status).toBe(404);
		expect(gets()).toBe(2);
		const res = await call(`${path}.sha1`, {}, INLINE);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await digest("SHA-1"));
	});

	/** a response that declares the full jar length but ends early */
	const truncatedResponse = () => {
		const short = jar.slice(0, jar.length - 1000);
		return new Response(new Blob([short]).stream(), { status: 200, headers: { "content-length": String(jar.byteLength) } });
	};

	it("does not download again while a computation is pending, and retries once the marker expires", async () => {
		let n = 0;
		// the first download ends short, the next one is complete
		mockFetch({ ...baseRoutes(), [gh]: (req) => (req.method === "GET" && ++n === 1 ? truncatedResponse() : jarResponse(req)) });
		expect((await call(`${path}.sha1`, {}, INLINE)).status).toBe(404);
		expect(gets()).toBe(1);
		const gen = await bindings.BRIDGE_CACHE.get("cache-generation");
		expect(await bindings.BRIDGE_CACHE.get(`checksum:${gen}:sha1:${gh}`)).toBeNull();
		const pending = await pendingKeys();
		expect(pending.map((k) => k.name)).toEqual([`checksum-pending:${gen}:${gh}`]);
		// PENDING_TTL_SECONDS = 300
		expect(pending[0].expiration).toBeLessThanOrEqual(Date.now() / 1000 + 300 + 60);
		expect(await bindings.BRIDGE_CACHE.get(`checksum-attempts:${gen}:${gh}`)).toBe("1");

		const blocked = await call(`${path}.md5`, {}, INLINE);
		expect(blocked.status).toBe(404);
		expect(blocked.headers.get("cache-control")).toBe("no-store");
		expect(gets()).toBe(1);

		// marker expired
		await bindings.BRIDGE_CACHE.delete(pending[0].name);
		expect((await call(`${path}.sha1`, {}, INLINE)).status).toBe(404);
		expect(gets()).toBe(2);
		const res = await call(`${path}.sha1`, {}, INLINE);
		expect(await res.text()).toBe(await digest("SHA-1"));
		expect(await bindings.BRIDGE_CACHE.get(`checksum-attempts:${gen}:${gh}`)).toBeNull();
	});

	it("stops starting background runs for an artifact whose attempts never finish", async () => {
		mockFetch({ ...baseRoutes(), [gh]: (req) => jarResponse(req) });
		const gen = await bindings.BRIDGE_CACHE.get("cache-generation");
		// MAX_BACKGROUND_ATTEMPTS = 3 runs that were ended by the runtime before they could finish
		await bindings.BRIDGE_CACHE.put(`checksum-attempts:${gen}:${gh}`, "3");
		const res = await call(`${path}.sha1`, {}, INLINE);
		expect(res.status).toBe(404);
		expect(res.headers.get("cache-control")).toBe("no-store");
		// only the request's own download, which is released unread
		expect(gets()).toBe(1);
		expect(await pendingKeys()).toHaveLength(0);
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys).toHaveLength(0);
		expect(await bindings.BRIDGE_CACHE.get(`checksum-attempts:${gen}:${gh}`)).toBe("3");
	});

	it("never caches a checksum of a download that ends short of its content-length", async () => {
		mockFetch({ ...baseRoutes(), [gh]: (req) => (req.method === "HEAD" ? new Response(null, { status: 200 }) : truncatedResponse()) });
		// in the background and inside the request
		expect((await call(`${path}.sha1`, {}, INLINE)).status).toBe(404);
		expect(await call(`${path}.sha1`).then((r) => r.status)).toBe(404);
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys).toHaveLength(0);
	});

	it("never caches a checksum of a download whose connection drops", async () => {
		mockFetch({
			...baseRoutes(),
			[gh]: (req) => {
				if (req.method === "HEAD") return new Response(null, { status: 200 });
				const bytes = jar.slice(0, 64 * 1024);
				const body = new ReadableStream({
					type: "bytes",
					pull(controller) {
						if (controller.desiredSize !== null && bytes.length) {
							controller.enqueue(bytes.slice());
							controller.error(new Error("connection lost"));
						}
					}
				});
				return new Response(body, { status: 200, headers: { "content-length": String(jar.byteLength) } });
			}
		});
		expect((await call(`${path}.sha1`, {}, INLINE)).status).toBe(404);
		expect(await call(`${path}.sha1`).then((r) => r.status)).toBe(404);
		expect((await bindings.BRIDGE_CACHE.list({ prefix: "checksum:" })).keys).toHaveLength(0);
	});

	it("hashes a large R2 object in the background", async () => {
		mockFetch(baseRoutes());
		const key = path.slice(1);
		await bindings.ARTIFACTS!.put(key, jar);
		const env = { ...R2, ...INLINE };
		expect((await call(`${path}.sha1`, {}, env)).status).toBe(404);
		const res = await call(`${path}.sha1`, {}, env);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await digest("SHA-1"));
		expect(await (await call(`${path}.sha512`, {}, env)).text()).toBe(await digest("SHA-512"));
		expect(calls.some((c) => c.includes(gh))).toBe(false);
	});
});

describe("checksums (io.forgebox)", () => {
	const mongo = "io/forgebox/ortus-mongodb-cache-extension/1.2.0.5291/ortus-mongodb-cache-extension-1.2.0.5291";
	const download = "https://www.forgebox.io/rest/extension/provider/full/6A03159F-C6DC-4FCC-95A068B1E1A903FA?version=1%2E2%2E0%2E5291";

	it("hashes the lex download instead of redirecting to it", async () => {
		mockFetch({ ...baseRoutes(), [download]: "lex-bytes" });
		const res = await call(`/${mongo}.lex.sha1`);
		expect(res.status).toBe(200);
		expect(res.headers.get("location")).toBeNull();
		expect(await res.text()).toBe(await sha1("lex-bytes"));
		expect(await (await call(`/${mongo}.lex.md5`)).text()).toBe(await sha1("lex-bytes", "MD5"));
	});

	it("hashes the generated pom", async () => {
		mockFetch(baseRoutes());
		const pom = await (await call(`/${mongo}.pom`)).text();
		const res = await call(`/${mongo}.pom.sha1`);
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(await sha1(pom));
	});

	it("answers 404, never the artifact, when there is nothing to hash", async () => {
		mockFetch(baseRoutes());
		const missing = await call(`/${mongo}.lex.sha1`);
		expect(missing.status).toBe(404);
		expect(missing.headers.get("location")).toBeNull();
		expect((await call("/io/forgebox/nope-extension/1/nope-extension-1.lex.sha1")).status).toBe(404);
		expect((await call(`/${mongo}.jar.sha1`)).status).toBe(404);
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
		const rc = "org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.pom";
		mockFetch({ ...baseRoutes(), [CDN + rc]: "old" });
		expect(await (await call(`/${rc}.sha1`)).text()).toBe(await sha1("old"));
		mockFetch({ ...baseRoutes(), [CDN + rc]: "new" });
		// still cached
		expect(await (await call(`/${rc}.sha1`)).text()).toBe(await sha1("old"));
		const before = await bindings.BRIDGE_CACHE.get("cache-generation");
		const res = await call("/health?flush=1", { headers: { authorization: "Bearer test-flush-token" } });
		expect(res.status).toBe(200);
		const json = (await res.json()) as Record<string, unknown>;
		expect(json.status).toBe("ok");
		expect(await bindings.BRIDGE_CACHE.get("cache-generation")).not.toBe(before);
		const index = await bindings.BRIDGE_CACHE.get("index:io.forgebox", "json");
		expect(index).not.toMatchObject({ stale: true });
		// computed checksums belong to the old generation and are computed again
		expect(await (await call(`/${rc}.sha1`)).text()).toBe(await sha1("new"));
		expect(calls).toContain(`GET ${CDN}${rc}`);
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

describe("listings and maven-metadata.xml cache time", () => {
	const metadataWith = (version: string) => REDIS_METADATA.replace("<version>2.0.0.1</version>", `<version>2.0.0.1</version>\n      <version>${version}</version>`);
	const cachedEntry = async (kind: string, id: string) => {
		const gen = await bindings.BRIDGE_CACHE.get("cache-generation");
		return caches.default.match(`https://mvn.lucee-services.com/__maven-bridge-cache/${gen}/${kind}/${encodeURIComponent(id)}`);
	};

	it("caches maven-metadata.xml for METADATA_CACHE_TTL_MINUTES, not CACHE_TTL_MINUTES", async () => {
		mockFetch(baseRoutes());
		await call("/org/lucee/redis-extension/maven-metadata.xml");
		const entry = await cachedEntry("metadata", `0/${CDN}org/lucee/redis-extension/maven-metadata.xml`);
		expect(entry?.headers.get("cache-control")).toBe("public, max-age=300");
		await entry?.arrayBuffer();
		mockFetch(baseRoutes());
		expect(await (await call("/org/lucee/redis-extension/maven-metadata.xml")).text()).toBe(REDIS_METADATA);
		expect(calls).not.toContain(`GET ${CDN}org/lucee/redis-extension/maven-metadata.xml`);
	});

	it("uses the configured cache time for listings", async () => {
		mockFetch(baseRoutes());
		await call("/org/lucee/redis-extension/", {}, { METADATA_CACHE_TTL_MINUTES: "2" });
		const entry = await cachedEntry("metadata", `0/${CDN}org/lucee/redis-extension/maven-metadata.xml`);
		expect(entry?.headers.get("cache-control")).toBe("public, max-age=120");
		await entry?.arrayBuffer();
	});

	it("does not cache listings and metadata with METADATA_CACHE_TTL_MINUTES = 0", async () => {
		mockFetch(baseRoutes());
		await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_CACHE_TTL_MINUTES: "0" });
		mockFetch(baseRoutes());
		await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_CACHE_TTL_MINUTES: "0" });
		expect(calls).toContain(`GET ${CDN}org/lucee/redis-extension/maven-metadata.xml`);
	});

	it("reads the group maven-metadata.xml again once the short cache is gone, even with a fresh KV copy", async () => {
		await bindings.BRIDGE_CACHE.put(
			`upstream:${CDN}org/lucee/maven-metadata.xml`,
			JSON.stringify({ body: "<old/>", contentType: "application/xml", fetchedAt: Date.now() })
		);
		mockFetch(baseRoutes());
		const res = await call("/org/lucee/maven-metadata.xml", {}, { METADATA_CACHE_TTL_MINUTES: "0" });
		expect(await res.text()).toBe(GROUP_METADATA);
		// the changed file replaces the KV copy
		expect(await bindings.BRIDGE_CACHE.get(`upstream:${CDN}org/lucee/maven-metadata.xml`, "json")).toMatchObject({ body: GROUP_METADATA });
	});

	it("serves the KV copy of a group file when the CDN fails", async () => {
		await bindings.BRIDGE_CACHE.put(
			`upstream:${CDN}org/lucee/maven-metadata.xml`,
			JSON.stringify({ body: GROUP_METADATA, contentType: "application/xml", fetchedAt: 0 })
		);
		mockFetch({ ...baseRoutes(), [`${CDN}org/lucee/maven-metadata.xml`]: new Response("down", { status: 503 }) });
		const res = await call("/org/lucee/maven-metadata.xml");
		expect(res.status).toBe(200);
		expect(await res.text()).toBe(GROUP_METADATA);
	});

	it("shows a new release in the artifact listing after ?flush=metadata", async () => {
		mockFetch(baseRoutes());
		expect(await (await call("/org/lucee/redis-extension/")).text()).not.toContain("2.0.0.2-RC");
		mockFetch({ ...baseRoutes(), [`${CDN}org/lucee/redis-extension/maven-metadata.xml`]: metadataWith("2.0.0.2-RC") });
		// still the cached listing
		expect(await (await call("/org/lucee/redis-extension/")).text()).not.toContain("2.0.0.2-RC");
		const res = await call("/org/lucee/redis-extension/?flush=metadata", { headers: { "x-flush-token": "test-flush-token" } });
		expect(res.status).toBe(200);
		// the request itself already answers with the fresh listing
		expect(await res.text()).toContain("2.0.0.2-RC");
		expect(await bindings.BRIDGE_CACHE.get("metadata-generation")).not.toBeNull();
		expect(await (await call("/org/lucee/redis-extension/")).text()).toContain("2.0.0.2-RC");
		expect(await (await call("/org/lucee/redis-extension/maven-metadata.xml")).text()).toContain("2.0.0.2-RC");
	});

	it("keeps artifacts, checksums and indexes on ?flush=metadata", async () => {
		mockFetch(baseRoutes());
		await call("/health");
		const before = await bindings.BRIDGE_CACHE.get("cache-generation");
		const index = await bindings.BRIDGE_CACHE.get("index:io.forgebox");
		const res = await call("/health?flush=metadata", { headers: { authorization: "Bearer test-flush-token" } });
		expect(res.status).toBe(200);
		expect(((await res.json()) as Record<string, unknown>).flushed).toBe(true);
		expect(await bindings.BRIDGE_CACHE.get("cache-generation")).toBe(before);
		expect(await bindings.BRIDGE_CACHE.get("index:io.forgebox")).toBe(index);
	});

	it("needs the flush token for ?flush=metadata", async () => {
		mockFetch(baseRoutes());
		const none = await call("/health?flush=metadata");
		expect(none.status).toBe(403);
		expect(await none.text()).toBe("Forbidden");
		const wrong = await call("/health?flush=metadata", { headers: { "x-flush-token": "wrong" } });
		expect(wrong.status).toBe(403);
		const disabled = await call("/health?flush=metadata", { headers: { "x-flush-token": "test-flush-token" } }, { FLUSH_TOKEN: "" });
		expect(disabled.status).toBe(403);
		expect(await disabled.text()).toBe("Flush is disabled");
		expect(await bindings.BRIDGE_CACHE.get("metadata-generation")).toBeNull();
	});
});
