import { describe, expect, it } from "vitest";
import { CHECKSUM_TYPES, READ_CHUNK_BYTES, checksumOfStream, checksumOfText, checksumsOfStream, splitChecksum } from "../src/checksum";
import { encodeForHtml, urlEncodedFormat, xmlFormat } from "../src/cfml";
import { parseProviders, readConfig } from "../src/config";
import type { Env } from "../src/env";
import { isImmutableArtifact } from "../src/r2";
import { buildIndex, sortVersions } from "../src/rest-index";
import { normalizeRequestPath, r2KeyFor, r2KeysFor } from "../src/proxy";
import { BridgeSupport, type SupportIo } from "../src/support";
import forgebox from "./fixtures/forgebox-info.json";
import mongoPom from "./fixtures/ortus-mongodb-cache-extension-1.2.0.5291.pom?raw";

const lucee = () => new BridgeSupport({ provider: "https://extension.lucee.org", groupId: "org.lucee", upstream: "https://cdn.lucee.org" });

function restSupport(): BridgeSupport {
	const support = new BridgeSupport({ provider: "https://www.forgebox.io/", groupId: "io.forgebox" });
	const index = buildIndex(forgebox, support.providerUrl, support.groupId, new Date(Date.UTC(2026, 9, 26, 13, 41, 6)));
	const io: SupportIo = {
		getIndex: async () => index,
		getUpstreamContent: async () => {
			throw new Error("not used");
		},
		remoteResourceExists: async () => false,
		upstreamResourceExists: async () => false
	};
	support.io = io;
	return support;
}

describe("parseMavenPath", () => {
	const s = lucee();
	it.each([
		["/org/lucee", { type: "group-index" }],
		["/org/lucee/", { type: "group-index" }],
		["/org/lucee/maven-metadata.xml", { type: "group-metadata" }],
		["/org/lucee/redis-extension", { type: "artifact-index", artifactId: "redis-extension" }],
		["/org/lucee/redis-extension/maven-metadata.xml", { type: "artifact-metadata", artifactId: "redis-extension" }],
		["/org/lucee/redis-extension/3.0.0.1", { type: "version-index", version: "3.0.0.1" }],
		["/org/lucee/redis-extension/3.0.0.1-SNAPSHOT/maven-metadata.xml", { type: "version-metadata", version: "3.0.0.1-SNAPSHOT" }],
		[
			"/org/lucee/redis-extension/3.0.0.1/redis-extension-3.0.0.1.lex",
			{ type: "artifact-file", artifactId: "redis-extension", version: "3.0.0.1", classifier: "", extension: "lex" }
		],
		[
			"/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10-light.jar",
			{ type: "artifact-file", artifactId: "lucee", version: "7.1.0.10", classifier: "light", extension: "jar" }
		],
		[
			"/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar.sha1",
			{ type: "artifact-file", classifier: "", extension: "jar.sha1" }
		],
		["/org/lucee/a/b/c/d", { type: "unknown" }],
		["/org/lucee/lucee/7.1.0.10/other-7.1.0.10.jar", { type: "unknown" }],
		["/io/forgebox", { type: "unknown" }],
		["/org/luceex", { type: "unknown" }]
	])("%s", (path, expected) => {
		expect(s.parseMavenPath(path)).toMatchObject(expected);
	});

	it("is case-insensitive like CFML", () => {
		expect(s.parseMavenPath("/ORG/Lucee/redis-extension/MAVEN-METADATA.XML").type).toBe("artifact-metadata");
	});
});

describe("legacy core mapping", () => {
	const s = lucee();
	const file = (version: string, classifier: string, extension: string) =>
		s.toUpstreamLegacyCorePath({ type: "artifact-file", artifactId: "lucee", version, classifier, extension });
	it.each([
		["6.2.0.321", "", "jar", "lucee-6.2.0.321.jar"],
		["6.2.0.321", "light", "jar", "lucee-light-6.2.0.321.jar"],
		["6.2.0.321", "zero", "jar", "lucee-zero-6.2.0.321.jar"],
		["6.2.0.321", "", "lco", "6.2.0.321.lco"],
		["6.2.0.321", "forgebox-light", "zip", "forgebox-light-6.2.0.321.zip"],
		["7.0.0.1-SNAPSHOT", "", "war", "lucee-7.0.0.1-SNAPSHOT.war"]
	])("%s %s %s", (version, classifier, ext, expected) => {
		expect(file(version, classifier, ext)).toBe(expected);
	});

	it("only maps the lucee artifact", () => {
		expect(s.toUpstreamLegacyCorePath({ type: "artifact-file", artifactId: "redis", version: "1", classifier: "", extension: "jar" })).toBe("");
	});
});

describe("R2 keys", () => {
	const s = lucee();
	const config = { r2Prefix: "" } as Parameters<typeof r2KeyFor>[0];
	const core = (version: string, classifier: string, extension: string) =>
		({ type: "artifact-file", groupId: "org.lucee", artifactId: "lucee", version, classifier, extension }) as const;
	it("uses the Maven layout first, then the legacy core name", () => {
		expect(r2KeyFor(config, s, core("8.0.1.12-SNAPSHOT", "", "pom"))).toBe("org/lucee/lucee/8.0.1.12-SNAPSHOT/lucee-8.0.1.12-SNAPSHOT.pom");
		expect(r2KeysFor(config, s, core("6.2.0.321", "light", "jar"))).toEqual([
			"org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar",
			"lucee-light-6.2.0.321.jar"
		]);
	});
	it("has a single key for non-core files and applies the prefix", () => {
		const prefixed = { r2Prefix: "maven/" } as Parameters<typeof r2KeyFor>[0];
		const lex = { type: "artifact-file", groupId: "org.lucee", artifactId: "redis-extension", version: "2.0.0.1", classifier: "", extension: "lex" } as const;
		expect(r2KeysFor(prefixed, s, lex)).toEqual(["maven/org/lucee/redis-extension/2.0.0.1/redis-extension-2.0.0.1.lex"]);
		expect(r2KeysFor(prefixed, s, core("7.1.0.10", "", "lco"))).toEqual(["maven/org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.lco", "maven/7.1.0.10.lco"]);
	});
});

describe("GitHub release urls", () => {
	const s = lucee();
	const urls = (version: string, classifier = "", extension = "jar") =>
		s.toGithubReleaseUrls({ type: "artifact-file", artifactId: "lucee", version, classifier, extension });
	it("uses the numeric tag first, then the full version", () => {
		expect(urls("7.1.2.184-RC")).toEqual([
			"https://github.com/lucee/Lucee/releases/download/7.1.2.184/lucee-7.1.2.184-RC.jar",
			"https://github.com/lucee/Lucee/releases/download/7.1.2.184-RC/lucee-7.1.2.184-RC.jar"
		]);
		expect(urls("7.1.0.10", "light")).toEqual(["https://github.com/lucee/Lucee/releases/download/7.1.0.10/lucee-light-7.1.0.10.jar"]);
		expect(urls("7.1.0.10", "express", "zip")).toHaveLength(1);
		expect(urls("8.0.0.1", "", "lco")).toEqual(["https://github.com/lucee/Lucee/releases/download/8.0.0.1/8.0.0.1.lco"]);
	});
	it("skips snapshots, old versions and unpublished files", () => {
		expect(urls("7.1.0.10-SNAPSHOT")).toEqual([]);
		expect(urls("7.0.1.100")).toEqual([]);
		expect(urls("6.2.0.321")).toEqual([]);
		expect(urls("7.1.0.10", "", "pom")).toEqual([]);
		expect(urls("7.1.0.10", "", "jar.sha1")).toEqual([]);
		expect(urls("7.1.0.10", "light", "zip")).toEqual([]);
	});
	it("is disabled with an empty GITHUB_RELEASES_URL", () => {
		const off = new BridgeSupport({ provider: "p", groupId: "org.lucee", upstream: "https://cdn.lucee.org/", githubReleasesUrl: "" });
		expect(off.toGithubReleaseUrls({ type: "artifact-file", artifactId: "lucee", version: "7.1.0.10", classifier: "", extension: "jar" })).toEqual([]);
	});
});

describe("ForgeBox ids and metadata", () => {
	it("derives artifact ids like the CFML bridge", async () => {
		const s = restSupport();
		const ids = (await s.getIndex()).artifacts.keys().sort();
		expect(ids).toContain("ortus-mongodb-cache-extension");
		expect(ids).toContain("lucee-mariadb-extension-extension");
		expect(ids).toContain("cfspreadsheet-extension");
		expect(ids).toContain("ortus-orm-extension-extension");
	});

	it("includes older versions with REST download urls", async () => {
		const s = restSupport();
		const versions = await s.listVersions("ortus-mongodb-cache-extension");
		expect(versions).toContain("1.1.2.3893");
		// same key-based order as the CFML bridge: "-snapshot" sorts after the build number
		expect(versions.slice(-2)).toEqual(["1.2.0.5291", "1.2.0-snapshot"]);
		expect(await s.getDownloadUrl("ortus-mongodb-cache-extension", "1.1.2.3893")).toBe(
			"https://www.forgebox.io/rest/extension/provider/full/6A03159F-C6DC-4FCC-95A068B1E1A903FA?version=1%2E1%2E2%2E3893"
		);
		expect(await s.getDownloadUrl("nope-extension", "1")).toBe("");
	});

	it("builds artifact metadata with latest and release", async () => {
		const s = restSupport();
		const xml = await s.buildArtifactMetadata("ortus-couchbase-cache-extension", new Date(Date.UTC(2026, 0, 2, 3, 4, 5)));
		expect(xml).toContain("<groupId>io.forgebox</groupId>");
		expect(xml).toContain("<latest>4.1.0-snapshot</latest>");
		expect(xml).toContain("<release>4.0.0.6</release>");
		expect(xml).toContain("<lastUpdated>20260102030405</lastUpdated>");
		await expect(s.buildArtifactMetadata("nope-extension")).rejects.toThrow("No versions found for [nope-extension]");
	});

	it("builds the minimal pom identical to production", async () => {
		const s = restSupport();
		expect(await s.buildMinimalPom("ortus-mongodb-cache-extension", "1.2.0.5291")).toBe(mongoPom.trimEnd());
	});

	it("builds snapshot version metadata", async () => {
		const s = restSupport();
		const xml = await s.buildVersionMetadata("ortus-redis-cache-extension", "3.5.0-SNAPSHOT", new Date(Date.UTC(2026, 0, 2, 3, 4, 5)));
		expect(xml).toContain("<version>3.5.0-SNAPSHOT</version>");
		expect(xml).toContain("<timestamp>20260102030405</timestamp>");
	});

	it("builds the group metadata sorted by artifact id", async () => {
		const xml = await restSupport().buildGroupMetadata();
		expect(xml.indexOf("cfspreadsheet-extension")).toBeLessThan(xml.indexOf("ortus-redis-cache-extension"));
	});
});

describe("helpers", () => {
	it("formats like CFML", () => {
		expect(xmlFormat(`a&b<c>"d'`)).toBe("a&amp;b&lt;c&gt;&quot;d&apos;");
		expect(encodeForHtml(`<a href='x'>`)).toBe("&lt;a href=&#39;x&#39;&gt;");
		expect(urlEncodedFormat("1.0.0-SNAPSHOT")).toBe("1%2E0%2E0%2DSNAPSHOT");
	});
	it("sorts versions numerically", () => {
		expect(sortVersions(["1.10.0", "1.2.0", "1.2.0-SNAPSHOT", "1.9.1"])).toEqual(["1.2.0", "1.2.0-SNAPSHOT", "1.9.1", "1.10.0"]);
	});
	it("normalizes request paths", () => {
		expect(normalizeRequestPath("//org//lucee/")).toBe("/org/lucee");
		expect(normalizeRequestPath("/index.cfm/org/lucee")).toBe("/org/lucee");
		expect(normalizeRequestPath("/org/lucee/index.cfm")).toBe("/org/lucee");
		expect(normalizeRequestPath("/")).toBe("/");
	});
	it("parses provider configs", () => {
		expect(parseProviders("https://a|g.a,https://b|g.b|https://cdn/")).toEqual([
			{ provider: "https://a", groupId: "g.a" },
			{ provider: "https://b", groupId: "g.b", upstream: "https://cdn/" }
		]);
		expect(parseProviders('[{"provider":"https://a","groupId":"g.a"}]')).toEqual([{ provider: "https://a", groupId: "g.a" }]);
		expect(() => readConfig({ R2_MODE: "bogus" } as unknown as Env)).toThrow("Invalid R2_MODE");
		expect(readConfig({ R2_FILL_ON_MISS: "true" } as unknown as Env).r2FillOnMiss).toBe(true);
		expect(readConfig({} as unknown as Env).r2FillOnMiss).toBe(false);
		expect(readConfig({} as unknown as Env).r2FillStreamMaxBytes).toBe(32 * 1024 * 1024);
		expect(readConfig({ R2_FILL_STREAM_MAX_MB: "8" } as unknown as Env).r2FillStreamMaxBytes).toBe(8 * 1024 * 1024);
		expect(readConfig({ R2_FILL_STREAM_MAX_MB: "0" } as unknown as Env).r2FillStreamMaxBytes).toBe(0);
		expect(() => readConfig({ R2_FILL_STREAM_MAX_MB: "-1" } as unknown as Env)).toThrow("Invalid R2_FILL_STREAM_MAX_MB");
		expect(readConfig({} as unknown as Env).r2RevalidateSeconds).toBe(300);
		expect(readConfig({ R2_REVALIDATE_MINUTES: "0" } as unknown as Env).r2RevalidateSeconds).toBe(0);
		expect(readConfig({} as unknown as Env).metadataCacheTtlSeconds).toBe(300);
		expect(readConfig({ METADATA_CACHE_TTL_MINUTES: "" } as unknown as Env).metadataCacheTtlSeconds).toBe(300);
		expect(readConfig({ METADATA_CACHE_TTL_MINUTES: "2" } as unknown as Env).metadataCacheTtlSeconds).toBe(120);
		expect(readConfig({ METADATA_CACHE_TTL_MINUTES: "0.5" } as unknown as Env).metadataCacheTtlSeconds).toBe(30);
		expect(readConfig({ METADATA_CACHE_TTL_MINUTES: "0" } as unknown as Env).metadataCacheTtlSeconds).toBe(0);
		expect(() => readConfig({ METADATA_CACHE_TTL_MINUTES: "-1" } as unknown as Env)).toThrow("Invalid METADATA_CACHE_TTL_MINUTES");
		expect(readConfig({ CACHE_TTL_MINUTES: "60", METADATA_CACHE_TTL_MINUTES: "5" } as unknown as Env).cacheTtlMinutes).toBe(60);
		expect(readConfig({} as unknown as Env).invalidateToken).toBe("");
		expect(readConfig({ R2_REVALIDATE_MINUTES: "1.5" } as unknown as Env).r2RevalidateSeconds).toBe(90);
		expect(() => readConfig({ R2_REVALIDATE_MINUTES: "-1" } as unknown as Env)).toThrow("Invalid R2_REVALIDATE_MINUTES");
		const hosts = { R2_MODE: "serve", R2_HOSTS: " mvn.example.org , other.example.org" } as unknown as Env;
		expect(readConfig(hosts, "mvn.example.org").r2Mode).toBe("serve");
		expect(readConfig(hosts, "MVN.example.org").r2Mode).toBe("serve");
		expect(readConfig(hosts, "maven.example.org").r2Mode).toBe("off");
		expect(readConfig(hosts).r2Mode).toBe("off");
		expect(readConfig({ R2_MODE: "serve", R2_HOSTS: "" } as unknown as Env, "any.example.org").r2Mode).toBe("serve");
		expect(readConfig({ R2_MODE: "serve" } as unknown as Env).r2Mode).toBe("serve");
	});
	it("only treats final/RC files as immutable", () => {
		expect(isImmutableArtifact("7.1.0.10", "lucee-7.1.0.10.jar")).toBe(true);
		expect(isImmutableArtifact("7.1.2.184-RC", "lucee-7.1.2.184-RC.jar")).toBe(true);
		expect(isImmutableArtifact("7.1.0.10-SNAPSHOT", "lucee-7.1.0.10-SNAPSHOT.jar")).toBe(false);
		expect(isImmutableArtifact("7.1.0.10", "maven-metadata.xml")).toBe(false);
		expect(isImmutableArtifact("7.1.0.10", "maven-metadata.xml.sha1")).toBe(false);
	});
});

describe("checksums", () => {
	const s = lucee();
	const core = (version: string, classifier: string, extension: string) =>
		({ type: "artifact-file", groupId: "org.lucee", artifactId: "lucee", version, classifier, extension }) as const;

	it("splits a checksum path into its artifact and type", () => {
		expect(splitChecksum(core("8.0.0.294-RC", "", "jar.sha1"))).toEqual({ artifact: core("8.0.0.294-RC", "", "jar"), type: "sha1" });
		expect(splitChecksum(core("1", "", "lex.MD5"))?.type).toBe("md5");
		expect(splitChecksum(core("1", "", "pom.sha512"))?.type).toBe("sha512");
		expect(splitChecksum(core("1", "", "jar"))).toBeNull();
		expect(splitChecksum(core("1", "", "sha1"))).toBeNull();
		expect(splitChecksum(core("1", "", "jar.asc"))).toBeNull();
		expect(splitChecksum({ type: "version-index", artifactId: "lucee", version: "1" })).toBeNull();
	});

	it("keeps the legacy core name for checksum files", () => {
		expect(s.toUpstreamLegacyCorePath(core("6.2.0.321", "", "jar.sha1"))).toBe("lucee-6.2.0.321.jar.sha1");
		expect(s.toUpstreamLegacyCorePath(core("6.2.0.321", "light", "jar.md5"))).toBe("lucee-light-6.2.0.321.jar.md5");
		expect(s.toUpstreamLegacyCorePath(core("6.2.0.321", "", "lco.sha1"))).toBe("6.2.0.321.lco.sha1");
		expect(s.toUpstreamRelativePath(core("8.0.0.294-RC", "", "pom.sha1"))).toBe("org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.pom.sha1");
	});

	it("never looks for checksum files on GitHub Releases", () => {
		expect(s.toGithubReleaseUrls(core("7.1.0.10", "", "jar.sha1"))).toEqual([]);
	});

	it("computes hex digests of text and streams", async () => {
		expect(await checksumOfText("abc", "sha1")).toBe("a9993e364706816aba3e25717850c26c9cd0d89d");
		expect(await checksumOfText("abc", "md5")).toBe("900150983cd24fb0d6963f7d28e17f72");
		expect(await checksumOfText("abc", "sha256")).toBe("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
		expect(await checksumOfStream(new Blob(["a", "bc"]).stream(), "sha1", 3)).toBe("a9993e364706816aba3e25717850c26c9cd0d89d");
		await expect(checksumOfStream(new Blob(["abcd"]).stream(), "sha1", 3)).rejects.toThrow();
	});

	it("computes every checksum type in one pass over a chunked stream", async () => {
		const chunks = () =>
			new ReadableStream<Uint8Array>({
				start(controller) {
					for (const part of ["a", "b", "c"]) controller.enqueue(new TextEncoder().encode(part));
					controller.close();
				}
			});
		const all = await checksumsOfStream(chunks(), CHECKSUM_TYPES, 3);
		expect(Object.keys(all).sort()).toEqual(["md5", "sha1", "sha256", "sha512"]);
		for (const type of CHECKSUM_TYPES) expect(all[type]).toBe(await checksumOfText("abc", type));
		await expect(checksumsOfStream(chunks(), CHECKSUM_TYPES, 2)).rejects.toThrow("more than 2 bytes");
	});

	const hex = (buffer: ArrayBuffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
	const ALGOS = { md5: "MD5", sha1: "SHA-1", sha256: "SHA-256", sha512: "SHA-512" } as const;
	/** deterministic bytes, a few blocks plus a partial one */
	const largeBytes = () => {
		const bytes = new Uint8Array(3 * READ_CHUNK_BYTES + 12345);
		for (let i = 0; i < bytes.length; i++) bytes[i] = (i * 31 + (i >> 8)) & 0xff;
		return bytes;
	};

	it("hashes a large byte stream in blocks, with the same digests as hashing it whole", async () => {
		const bytes = largeBytes();
		const all = await checksumsOfStream(new Blob([bytes]).stream(), CHECKSUM_TYPES, bytes.length, bytes.length);
		for (const type of CHECKSUM_TYPES) expect(all[type]).toBe(hex(await crypto.subtle.digest(ALGOS[type], bytes)));
	});

	it("hashes a JS byte stream with odd chunk sizes", async () => {
		const bytes = largeBytes();
		const stream = new ReadableStream({
			type: "bytes",
			start(controller) {
				for (let i = 0; i < bytes.length; i += 70001) controller.enqueue(bytes.slice(i, i + 70001));
				controller.close();
			}
		});
		const all = await checksumsOfStream(stream, ["sha1", "md5"], bytes.length);
		expect(all.sha1).toBe(hex(await crypto.subtle.digest("SHA-1", bytes)));
		expect(all.md5).toBe(hex(await crypto.subtle.digest("MD5", bytes)));
	});

	it("rejects a stream over the limit or shorter than its expected length", async () => {
		const bytes = largeBytes();
		await expect(checksumsOfStream(new Blob([bytes]).stream(), CHECKSUM_TYPES, bytes.length - 1)).rejects.toThrow(
			`more than ${bytes.length - 1} bytes`
		);
		// a truncated download never yields a checksum
		await expect(checksumsOfStream(new Blob([bytes]).stream(), CHECKSUM_TYPES, bytes.length + 10, bytes.length + 1)).rejects.toThrow(
			`read ${bytes.length} bytes, expected ${bytes.length + 1}`
		);
	});

	it("reads CHECKSUM_INLINE_MAX_MB", () => {
		expect(readConfig({} as unknown as Env).checksumInlineMaxBytes).toBe(16 * 1024 * 1024);
		expect(readConfig({ CHECKSUM_INLINE_MAX_MB: "0" } as unknown as Env).checksumInlineMaxBytes).toBe(0);
		expect(readConfig({ CHECKSUM_INLINE_MAX_MB: "64" } as unknown as Env).checksumInlineMaxBytes).toBe(64 * 1024 * 1024);
		expect(() => readConfig({ CHECKSUM_INLINE_MAX_MB: "-1" } as unknown as Env)).toThrow("Invalid CHECKSUM_INLINE_MAX_MB");
	});

	it("reads CHECKSUM_MAX_MB", () => {
		expect(readConfig({} as unknown as Env).checksumMaxBytes).toBe(128 * 1024 * 1024);
		expect(readConfig({ CHECKSUM_MAX_MB: "0" } as unknown as Env).checksumMaxBytes).toBe(0);
		expect(() => readConfig({ CHECKSUM_MAX_MB: "-1" } as unknown as Env)).toThrow("Invalid CHECKSUM_MAX_MB");
	});
});
