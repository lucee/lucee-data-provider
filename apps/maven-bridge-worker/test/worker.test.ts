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
		expect(await bindings.BRIDGE_CACHE.get(`checksum:sha1:${CDN}${rc}.pom`)).toBe(await sha1(pom));

		mockFetch(baseRoutes());
		const again = await call(`/${rc}.pom.sha1`);
		expect(await again.text()).toBe(await sha1(pom));
		expect(calls).not.toContain(`GET ${CDN}${rc}.pom`);
	});

	it("computes md5 and sha256 too", async () => {
		mockFetch({ ...baseRoutes(), [`${CDN}${rc}.pom`]: pom });
		expect(await (await call(`/${rc}.pom.md5`)).text()).toBe(await sha1(pom, "MD5"));
		expect(await (await call(`/${rc}.pom.sha256`)).text()).toBe(await sha1(pom, "SHA-256"));
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
		expect(keys).toHaveLength(1);
		expect(keys[0].expiration).toBeGreaterThan(Date.now() / 1000);
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
		await bindings.BRIDGE_CACHE.put("checksum:sha1:https://cdn.lucee.org/x.jar", "abc");
		const before = await bindings.BRIDGE_CACHE.get("cache-generation");
		const res = await call("/health?flush=1", { headers: { authorization: "Bearer test-flush-token" } });
		expect(res.status).toBe(200);
		const json = (await res.json()) as Record<string, unknown>;
		expect(json.status).toBe("ok");
		expect(await bindings.BRIDGE_CACHE.get("cache-generation")).not.toBe(before);
		const index = await bindings.BRIDGE_CACHE.get("index:io.forgebox", "json");
		expect(index).not.toMatchObject({ stale: true });
		expect(await bindings.BRIDGE_CACHE.get("checksum:sha1:https://cdn.lucee.org/x.jar")).toBeNull();
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
