import { createScheduledController } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { EMPTY_COLUMNS } from "../src/builder";
import type { Env } from "../src/env";
import worker from "../src/index";
import type { ExtensionIndex } from "../src/types";
import { ALPHA, BRAVO, CDN, CHARLIE, DELTA, EXT_CDN, LOGO_BRAVO, MIXED, PNG, REPO1, SNAPSHOTS, metadata, world } from "./fixtures";
import { BASE, call, calls, mockFetch, resetState, testEnv } from "./helpers";

const kv = () => (env as unknown as Env).EXT_CACHE!;
const LIST_COLUMNS = [...EMPTY_COLUMNS, "coreVersion"];
const PNG_BASE64 = btoa(String.fromCharCode(...PNG));

interface Info {
	META: Record<string, string>;
	EXTENSIONS: { COLUMNS: string[]; DATA: unknown[][] };
}

/** the rows of an info answer as objects */
function rows(info: Info): Record<string, unknown>[] {
	return info.EXTENSIONS.DATA.map((r) => Object.fromEntries(info.EXTENSIONS.COLUMNS.map((c, i) => [c, r[i]])));
}

async function info(query = "", overrides = {}, origin?: string) {
	const res = await call(`${BASE}/info${query}`, {}, overrides, origin);
	expect(res.status).toBe(200);
	return (await res.json()) as Info;
}

beforeEach(async () => {
	await resetState();
	mockFetch(await world());
});
afterEach(() => {
	vi.restoreAllMocks();
});

describe("GET /rest/extension/provider/info", () => {
	it("answers the provider meta and the extensions as a serialized query", async () => {
		const res = await call(`${BASE}/info`);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-type")).toBe("application/json;charset=UTF-8");
		const body = await res.text();
		// the key order of the CFML answer
		expect(body.startsWith('{"META":{"MODE":"production","URL":"https://extension.lucee.org","IMAGE":"https://extension.lucee.org/extension/extension-provider.png","TITLE":"Lucee Association Switzerland Extension Store (extension.lucee.org)","DESCRIPTION":""},"EXTENSIONS":{"COLUMNS":')).toBe(true);
		const json = JSON.parse(body) as Info;
		expect(Object.keys(json)).toEqual(["META", "EXTENSIONS"]);
		expect(json.EXTENSIONS.COLUMNS).toEqual(LIST_COLUMNS);
		for (const r of json.EXTENSIONS.DATA) expect(r).toHaveLength(LIST_COLUMNS.length);
	});

	it("lists the newest final of every extension, sorted by name, with the older versions", async () => {
		const list = rows(await info());
		expect(list.map((r) => [r.name, r.version])).toEqual([
			["Alpha", "1.0.0.2"],
			["beta thing", "3.0.0.0"],
			["Charlie", "1.0.0.0"],
			["Delta", "1.0.0.0"]
		]);
		const alpha = list[0];
		expect(alpha.older).toEqual(["1.0.0.0"]);
		expect(alpha.olderName).toEqual(["alpha.ext-1.0.0.0.lex"]);
		expect(alpha.olderDate).toEqual(["2025-01-01 10:00:00"]);
		expect(alpha.coreVersion).toEqual(["5.0.0.0"]);
		expect(alpha.versionSortable).toBe("01.000.000.0002.100");
		expect(alpha.trial).toBe(false);
		expect(list[1].older).toEqual([]);
		expect(list[1].coreVersion).toEqual([]);
	});

	it("has the logos by default and none with withLogo=false", async () => {
		const withLogo = rows(await info());
		expect(withLogo.find((r) => r.id === BRAVO)!.image).toBe(LOGO_BRAVO);
		// the logo of a discovered extension is the png of the .lex
		expect(withLogo.find((r) => r.id === DELTA)!.image).toBe(PNG_BASE64);
		for (const flag of ["false", "no", "0"]) {
			const without = rows(await info(`?withLogo=${flag}`));
			expect(without.every((r) => r.image === "")).toBe(true);
		}
	});

	it("filters by release type before choosing the latest version", async () => {
		expect(rows(await info("?type=snapshot")).map((r) => [r.id, r.version, r.older])).toEqual([[ALPHA, "2.0.0.1-SNAPSHOT", []]]);
		expect(rows(await info("?type=abc")).map((r) => [r.id, r.version])).toEqual([[ALPHA, "1.0.0.1-RC"]]);
		const all = rows(await info("?type=all"));
		expect(all[0].version).toBe("2.0.0.1-SNAPSHOT");
		expect(all[0].older).toEqual(["1.0.0.2", "1.0.0.1-RC", "1.0.0.0"]);
		// url parameter names are case-insensitive, like the url scope
		expect(rows(await info("?TYPE=snapshot")).map((r) => r.version)).toEqual(["2.0.0.1-SNAPSHOT"]);
	});

	it("only lists the versions the core version can load", async () => {
		const list = rows(await info("?coreVersion=5.5.0.0"));
		expect(list.map((r) => [r.id, r.version])).toEqual([
			[ALPHA, "1.0.0.0"],
			[BRAVO, "3.0.0.0"]
		]);
		const v6 = rows(await info("?coreVersion=6.2.0.0&type=all"));
		expect(v6.map((r) => [r.id, r.version])).toEqual([
			[ALPHA, "1.0.0.2"],
			[BRAVO, "3.0.0.0"],
			[CHARLIE, "1.0.0.0"],
			[DELTA, "1.0.0.0"]
		]);
		// a snapshot core version: the build is compared as a string, like CFML does
		expect(rows(await info("?coreVersion=7.0.0.1-SNAPSHOT&type=snapshot")).map((r) => r.version)).toEqual(["2.0.0.1-SNAPSHOT"]);
	});

	it("answers alphas, betas and RCs on a beta. host name", async () => {
		const json = await info("", {}, "https://beta.extension.lucee.org");
		expect(json.META.URL).toBe("https://beta.extension.lucee.org");
		expect(rows(json).map((r) => r.version)).toEqual(["1.0.0.1-RC"]);
	});

	it("drops what is not served from a Maven source when the flat fallback is off (LDEV-6795)", async () => {
		const list = rows(await info("?type=all", { EXTENSIONS_FLAT_S3_FALLBACK: "false" }));
		expect(list.map((r) => [r.id, r.version, r.older])).toEqual([
			[ALPHA, "2.0.0.1-SNAPSHOT", ["1.0.0.2", "1.0.0.0"]],
			[CHARLIE, "1.0.0.0", []],
			[DELTA, "1.0.0.0", []]
		]);
	});

	it("applies the min core version of Maven packaged extensions (LDEV-6795)", async () => {
		const overrides = { EXTENSIONS_MAVEN_ONLY_MIN_CORE: "7.0.0.0" };
		const list = rows(await info("", overrides));
		expect(list.find((r) => r.id === CHARLIE)!.minCoreVersion).toBe("7.0.0.0");
		// osgi packaged (Delta) and unknown packaging keep the min core version of their manifest
		expect(list.find((r) => r.id === DELTA)!.minCoreVersion).toBe("6.2.0.0");
		expect(rows(await info("?coreVersion=6.5.0.0", overrides)).map((r) => r.id)).not.toContain(CHARLIE);
	});
});

describe("GET /rest/extension/provider/info/{id}", () => {
	it("answers the newest final as a struct with the columns of the meta", async () => {
		const res = await call(`${BASE}/info/${ALPHA}`);
		expect(res.status).toBe(200);
		expect(res.headers.get("content-type")).toBe("application/json;charset=UTF-8");
		const body = await res.text();
		expect(Object.keys(JSON.parse(body))).toEqual(EMPTY_COLUMNS);
		expect(JSON.parse(body)).toMatchObject({ id: ALPHA, version: "1.0.0.2", filename: "alpha-extension-1.0.0.2.lex", trial: false, older: "" });
	});

	it("answers the logo by default, none with withLogo=false", async () => {
		expect(((await (await call(`${BASE}/info/${BRAVO}`)).json()) as Record<string, string>).image).toBe(LOGO_BRAVO);
		expect(((await (await call(`${BASE}/info/${BRAVO}?withLogo=false`)).json()) as Record<string, string>).image).toBe("");
	});

	it("answers a version that is asked for, whatever its type, the id ignoring case", async () => {
		const res = await call(`${BASE}/info/${ALPHA.toLowerCase()}?version=1.0.0.1-rc`);
		expect(res.status).toBe(200);
		expect(((await res.json()) as Record<string, string>).version).toBe("1.0.0.1-RC");
		const latest = await call(`${BASE}/info/${ALPHA}?version=latest&type=all`);
		expect(((await latest.json()) as Record<string, string>).version).toBe("2.0.0.1-SNAPSHOT");
	});

	it("answers the newest version the core version can load", async () => {
		const res = await call(`${BASE}/info/${ALPHA}?coreVersion=5.3.0.1`);
		expect(((await res.json()) as Record<string, string>).version).toBe("1.0.0.0");
	});

	it("answers 404 when no version of the type fits the core version, or the version doesn't fit", async () => {
		const none = await call(`${BASE}/info/${CHARLIE}?coreVersion=5.3.0.1`);
		expect(none.status).toBe(404);
		const explicit = await call(`${BASE}/info/${ALPHA}?version=1.0.0.2&coreVersion=5.3.0.1`);
		expect(explicit.status).toBe(404);
		const noSnapshot = await call(`${BASE}/info/${BRAVO}?type=snapshot`);
		expect(noSnapshot.status).toBe(404);
	});

	it("answers 404 with a text message for an unknown id or version", async () => {
		const res = await call(`${BASE}/info/NOPE<x>`);
		expect(res.status).toBe(404);
		expect(res.headers.get("content-type")).toBe("text/plain;charset=UTF-8");
		expect(await res.text()).toBe("There is no extension at this provider with id [NOPE&lt;x&gt;].");
		const version = await call(`${BASE}/info/${ALPHA}?version=9.9.9.9`);
		expect(await version.text()).toBe(`There is no extension at this provider with id [${ALPHA}] in version [9.9.9.9].`);
	});
});

describe("GET /rest/extension/provider/full/{id} and trial/{id}", () => {
	async function location(path: string, overrides = {}) {
		const res = await call(`${BASE}${path}`, {}, overrides);
		expect(res.status).toBe(302);
		expect(await res.text()).toBe("");
		return res.headers.get("location");
	}

	it("redirects to a Maven repository first (LDEV-6795)", async () => {
		expect(await location(`/full/${ALPHA}`)).toBe(`${REPO1}org/lucee/alpha-extension/1.0.0.2/alpha-extension-1.0.0.2.lex`);
		expect(await location(`/trial/${ALPHA}`)).toBe(`${REPO1}org/lucee/alpha-extension/1.0.0.2/alpha-extension-1.0.0.2.lex`);
		expect(await location(`/full/${DELTA}`)).toBe(`${REPO1}org/lucee/delta-extension/1.0.0.0/delta-extension-1.0.0.0.lex`);
	});

	it("redirects an old flat file name to the Maven file of the same id and version", async () => {
		expect(await location(`/full/${ALPHA}?version=1.0.0.0`)).toBe(`${REPO1}org/lucee/alpha-extension/1.0.0.0/alpha-extension-1.0.0.0.lex`);
	});

	it("redirects a snapshot to its timestamped file in the snapshot repository", async () => {
		expect(await location(`/full/${ALPHA}?type=snapshot`)).toBe(`${SNAPSHOTS}org/lucee/alpha-extension/2.0.0.1-SNAPSHOT/alpha-extension-2.0.0.1-20261101.101010-3.lex`);
	});

	it("redirects to the Maven layout of the core bucket", async () => {
		expect(await location(`/full/${CHARLIE}`)).toBe(`${CDN}charlie-extension/1.0.0.0/charlie-extension-1.0.0.0.lex`);
	});

	it("falls back to the flat files", async () => {
		expect(await location(`/full/${BRAVO}`)).toBe(`${EXT_CDN}bravo-3.0.0.0.lex`);
		expect(await location(`/full/${ALPHA}?version=1.0.0.1-RC`)).toBe(`${EXT_CDN}alpha-extension-1.0.0.1-RC.lex`);
	});

	it("uses the configured urls", async () => {
		const overrides = { S3_EXTENSIONS_CDN_URL: "https://ext.example.org/", S3_CORE_CDN_URL: "https://cdn.example.org" };
		mockFetch(
			await world({
				"https://ext.example.org/extensions.json": (await (await world())[EXT_CDN + "extensions.json"]) as string,
				"https://cdn.example.org/org/lucee/maven-metadata.xml": (await world())[CDN + "maven-metadata.xml"],
				"https://cdn.example.org/org/lucee/charlie-extension/maven-metadata.xml": metadata("charlie-extension", ["1.0.0.0"])
			})
		);
		expect(await location(`/full/${BRAVO}`, overrides)).toBe("https://ext.example.org/bravo-3.0.0.0.lex");
		expect(await location(`/full/${CHARLIE}`, overrides)).toBe("https://cdn.example.org/org/lucee/charlie-extension/1.0.0.0/charlie-extension-1.0.0.0.lex");
	});

	it("answers 404 without a body when there is nothing to download", async () => {
		for (const path of [`/full/NOPE`, `/trial/NOPE`, `/full/${CHARLIE}?coreVersion=5.0.0.0`, `/full/${ALPHA}?version=9.9.9.9`]) {
			const res = await call(`${BASE}${path}`);
			expect(res.status).toBe(404);
			expect(await res.text()).toBe("");
		}
	});

	it("ignores what Lucee core sends besides (ioid)", async () => {
		expect(await location(`/full/${ALPHA}?ioid=abc&coreVersion=7.1.2.191`)).toBe(`${REPO1}org/lucee/alpha-extension/1.0.0.2/alpha-extension-1.0.0.2.lex`);
	});
});

describe("index", () => {
	it("is stored in KV with the logos apart, and read from there", async () => {
		await info();
		const stored = await kv().get<ExtensionIndex>("index", "json");
		expect(stored!.stats).toMatchObject({ fromMeta: 7, discovered: 1, bucketComplete: true, reposComplete: false });
		expect(stored!.rows.every((r) => r[EMPTY_COLUMNS.indexOf("image")] === "")).toBe(true);
		const logos = await kv().get<{ logos: Record<string, string> }>("logos", "json");
		expect(logos!.logos["bravo-3.0.0.0.lex"]).toBe(LOGO_BRAVO);
		const state = await kv().get<{ mavenState: { artifactIds: Record<string, string> } }>("state", "json");
		expect(state!.mavenState.artifactIds["delta-extension"]).toBe(DELTA);
	});

	it("is not built again by the next requests", async () => {
		await info();
		const before = calls.length;
		await info("?withLogo=false");
		await call(`${BASE}/info/${BRAVO}`);
		expect(calls.slice(before).filter((c) => c.includes("extensions.json"))).toEqual([]);
	});

	it("reads a discovered file with range requests, not the whole file", async () => {
		await info();
		const lexCalls = calls.filter((c) => c.includes("delta-extension-1.0.0.0.lex"));
		expect(lexCalls.length).toBeGreaterThan(0);
		expect(lexCalls.every((c) => / bytes=/.test(c))).toBe(true);
	});

	it("reads the discovered file only once", async () => {
		await info();
		await resetMemoryOnly();
		mockFetch(await world());
		await call(`${BASE}/info?flush=true`, { headers: { "x-flush-token": "test-flush-token" } });
		expect(calls.filter((c) => c.includes("delta-extension-1.0.0.0.lex"))).toEqual([]);
		expect(rows(await info()).map((r) => r.id)).toContain(DELTA);
	});

	it("does no discovery with EXTENSIONS_DISCOVERY_MAX=0", async () => {
		const list = rows(await info("", { EXTENSIONS_DISCOVERY_MAX: "0" }));
		expect(list.map((r) => r.id)).not.toContain(DELTA);
	});

	it("answers 503 when the extension meta can't be read", async () => {
		mockFetch({});
		const res = await call(`${BASE}/info`);
		expect(res.status).toBe(503);
	});

	it("is built by the cron", async () => {
		await worker.scheduled(createScheduledController({ cron: "*/10 * * * *" }), testEnv());
		expect(await kv().get("index")).not.toBeNull();
	});
});

async function resetMemoryOnly() {
	const { resetMemory } = await import("../src/store");
	const { resetProvider } = await import("../src/index");
	resetMemory();
	resetProvider();
}

describe("admin endpoints and flush", () => {
	it("are disabled without the FLUSH_TOKEN secret", async () => {
		for (const path of ["/updateCache", "/reset", "/status"]) {
			const res = await call(`${BASE}${path}`, {}, { FLUSH_TOKEN: "" });
			expect(res.status).toBe(403);
			expect(await res.text()).toBe("Disabled");
		}
	});

	it("need the token", async () => {
		const res = await call(`${BASE}/updateCache`, { headers: { "x-flush-token": "wrong" } });
		expect(res.status).toBe(403);
	});

	it("rebuild the index with the token", async () => {
		const update = await call(`${BASE}/updateCache`, { headers: { authorization: "Bearer test-flush-token" } });
		expect(update.status).toBe(200);
		const json = (await update.json()) as Info;
		expect(json.META).toEqual({});
		expect(json.EXTENSIONS.COLUMNS).toEqual(EMPTY_COLUMNS);
		const reset = await call(`${BASE}/reset`, { headers: { "x-flush-token": "test-flush-token" } });
		expect(reset.status).toBe(200);
		const status = await call(`${BASE}/status`, { headers: { "x-flush-token": "test-flush-token" } });
		expect(((await status.json()) as { stats: { rows: number } }).stats.rows).toBe(8);
	});

	it("flush=true without the token is ignored, not an error", async () => {
		await info();
		const before = calls.length;
		await info("?flush=true");
		expect(calls.slice(before).filter((c) => c.includes("extensions.json"))).toEqual([]);
	});
});

describe("other requests", () => {
	it("answers HEAD like GET without a body", async () => {
		const res = await call(`${BASE}/info/${ALPHA}`, { method: "HEAD" });
		expect(res.status).toBe(200);
		expect(await res.text()).toBe("");
	});

	it("answers 405 for other methods", async () => {
		const res = await call(`${BASE}/info`, { method: "POST" });
		expect(res.status).toBe(405);
	});

	it("answers 404 for unknown paths, OK for the health check", async () => {
		expect((await call("/rest/other")).status).toBe(404);
		expect((await call(`${BASE}/info/a/b`)).status).toBe(404);
		const health = await call("/healthcheck/");
		expect(await health.text()).toBe("OK");
	});

	it("matches the paths ignoring case and a trailing slash", async () => {
		expect((await call(`/REST/Extension/Provider/Info/`)).status).toBe(200);
		expect((await call(`${BASE}/FULL/${ALPHA}`)).status).toBe(302);
	});

	it("sends the security headers of the CFML provider", async () => {
		const res = await call(`${BASE}/info`);
		expect(res.headers.get("content-security-policy")).toBe("sandbox; object-src 'none'; script-src 'none'");
		expect(res.headers.get("x-content-type-options")).toBe("nosniff");
	});
});

// the requests of the index build go to the configured sources only
it("reads the configured repositories", async () => {
	await info();
	const hosts = new Set(calls.map((c) => new URL(c.split(" ")[1]).origin + "/"));
	expect([...hosts].sort()).toEqual(["https://central.sonatype.com/", "https://cdn.lucee.org/", "https://ext.lucee.org/", MIXED, "https://repo1.maven.org/"].sort());
});
