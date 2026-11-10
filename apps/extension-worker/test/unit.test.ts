import { afterEach, describe, expect, it, vi } from "vitest";
import { mavenRepos, parseCfBoolean, readConfig } from "../src/config";
import { parseManifest, probePackaging, readLex } from "../src/lex";
import { checkVersionGTE, effectiveMinCore, fitsCoreVersion, matchesReleaseType, sortableVersionString } from "../src/versions";
import { encodeForHtml } from "../src/index";
import { DELTA, DELTA_MANIFEST, PNG, deltaLex } from "./fixtures";
import { calls, mockFetch } from "./helpers";

afterEach(() => {
	vi.restoreAllMocks();
});

describe("sortableVersionString (VersionUtils.cfc)", () => {
	it.each([
		["1.0.0.8", "01.000.000.0008.100"],
		["7.1.2.191-SNAPSHOT", "07.001.002.0191.000"],
		["4.2.0.4-RC", "04.002.000.0004.075"],
		["5.4.29.10-BETA", "05.004.029.0010.050"],
		["2.1.0.16-ALPHA", "02.001.000.0016.075"],
		["3.0.0.0-snapshot", "03.000.000.0000.000"],
		["12.4.2.jre8", "12.004.002.0000.075"],
		["42.7.11", "42.007.011.0000"],
		["13.2.1", "13.002.001.0000"],
		["6.2.1-jre8", "06.002.018.0000"],
		["9.4.1.jre11-preview", "09.004.001.0000.075"]
	])("%s", (version, expected) => {
		expect(sortableVersionString(version)).toBe(expected);
	});
});

describe("checkVersionGTE (VersionUtils.cfc)", () => {
	it("compares the parts as numbers", () => {
		expect(checkVersionGTE("5.0.0.019", "5", "3", "0", "1")).toBe(true);
		expect(checkVersionGTE("6.0.0.0", "5", "3", "0", "1")).toBe(false);
		expect(checkVersionGTE("7.1.2.191", "7", "1", "2", "191")).toBe(true);
		expect(checkVersionGTE("7.1.2.192", "7", "1", "2", "191")).toBe(false);
		expect(checkVersionGTE("7.1", "7", "1", "0", "0")).toBe(true);
		expect(checkVersionGTE("", "1", "0", "0", "0")).toBe(true);
	});

	it("compares a snapshot build as a string, ignoring case", () => {
		expect(checkVersionGTE("7.0.0.0", "7", "0", "0", "1-SNAPSHOT")).toBe(true);
		expect(checkVersionGTE("7.0.0.2", "7", "0", "0", "10-SNAPSHOT")).toBe(false); // "2" > "10-snapshot" as strings
	});

	it("fitsCoreVersion: yes when in doubt", () => {
		expect(fitsCoreVersion("", "5.0.0.0")).toBe(true);
		expect(fitsCoreVersion("9.0.0.0", "8.0")).toBe(true);
		expect(fitsCoreVersion("9.0.0.0", "8.0.0.1")).toBe(false);
	});
});

describe("release types and min core versions", () => {
	it("matchesReleaseType", () => {
		expect(matchesReleaseType("1.0.0.0", "release")).toBe(true);
		expect(matchesReleaseType("1.0.0.0-rc", "release")).toBe(false);
		expect(matchesReleaseType("1.0.0.0-SNAPSHOT", "snapshot")).toBe(true);
		expect(matchesReleaseType("1.0.0.0-BETA", "abc")).toBe(true);
		expect(matchesReleaseType("1.0.0.0-SNAPSHOT", "abc")).toBe(false);
		expect(matchesReleaseType("1.0.0.0-SNAPSHOT", "all")).toBe(true);
		expect(matchesReleaseType("1.0.0.0-SNAPSHOT", "whatever")).toBe(true);
	});

	it("effectiveMinCore", () => {
		expect(effectiveMinCore("6.0.0.0", "maven", "")).toBe("6.0.0.0");
		expect(effectiveMinCore("6.0.0.0", "osgi", "7.0.0.0")).toBe("6.0.0.0");
		expect(effectiveMinCore("6.0.0.0", "maven", "7.0.0.0")).toBe("7.0.0.0");
		expect(effectiveMinCore("", "maven", "7.0.0.0")).toBe("7.0.0.0");
		expect(effectiveMinCore("8.0.0.0", "maven", "7.0.0.0")).toBe("8.0.0.0");
	});
});

describe("config", () => {
	it("reads the settings like Application.cfc", () => {
		const config = readConfig({ S3_EXTENSIONS_CDN_URL: "https://ext.example.org", EXTENSIONS_MAVEN_REPOS_SNAPSHOTS: "none", LUCEE_MVN_REPO_MIXED: "https://a/, https://a/ ,https://b" });
		expect(config.extensionsCdnUrl).toBe("https://ext.example.org/");
		expect(config.metaUrl).toBe("https://ext.example.org/extensions.json");
		expect(config.mavenCdnUrl).toBe("https://cdn.lucee.org/org/lucee/");
		expect(config.releaseRepos).toEqual(["https://repo1.maven.org/maven2/"]);
		expect(config.snapshotRepos).toEqual([]);
		expect(config.mixedRepos).toEqual(["https://a/", "https://b/"]);
		expect(readConfig({ EXTENSIONS_MAVEN_REPOS_ENABLED: "false" }).releaseRepos).toEqual([]);
		expect(readConfig({ S3_EXTENSIONS_MAVEN_PATH: "" }).mavenCdnUrl).toBe("");
		expect(mavenRepos("none")).toEqual([]);
	});

	it("parses booleans like CFML", () => {
		expect(parseCfBoolean("yes")).toBe(true);
		expect(parseCfBoolean("0")).toBe(false);
		expect(parseCfBoolean("2")).toBe(true);
		expect(parseCfBoolean("maybe")).toBeUndefined();
	});

	it("encodeForHtml", () => {
		expect(encodeForHtml("AB-1_2.3, x")).toBe("AB-1_2.3, x");
		expect(encodeForHtml("<a href='x'>&\"/")).toBe("&lt;a href&#x3d;&#x27;x&#x27;&gt;&amp;&quot;&#x2f;");
	});
});

describe("lex files", () => {
	it("parses the main section of a manifest", () => {
		const mf = parseManifest(DELTA_MANIFEST);
		expect(mf.id).toBe(DELTA);
		expect(mf.version).toBe("1.0.0.0");
		expect(mf["release-type"]).toBe("server");
		expect(mf.description).toBe("A description that is longer than one manifest line, so it is continued on the next line of the manifest");
		expect(mf["Built-Date"]).toBe("2026/11/01 10:00:00 UTC");
	});

	it("probes the packaging", () => {
		expect(probePackaging(["META-INF/MANIFEST.MF", "jars/a.jar"], { groupId: "x", artifactId: "y" })).toBe("osgi");
		expect(probePackaging(["META-INF/MANIFEST.MF", "maven/x.pom"], {})).toBe("maven");
		expect(probePackaging(["META-INF/MANIFEST.MF"], { groupId: "org.lucee", artifactId: "y" })).toBe("maven");
		expect(probePackaging(["META-INF/MANIFEST.MF", "jars/sub/a.jar"], {})).toBe("unknown");
	});

	it("reads manifest, logo and packaging with range requests", async () => {
		const url = "https://repo.example.org/delta.lex";
		// a file larger than the tail that is read first
		mockFetch({ [url]: await deltaLex(200_000) });
		const lex = await readLex(url);
		expect(lex.manifest.id).toBe(DELTA);
		expect(lex.logo).toBe(btoa(String.fromCharCode(...PNG)));
		expect(lex.packaging).toBe("osgi");
		expect(calls.every((c) => / bytes=\d*-\d*$/.test(c))).toBe(true);
	});

	it("reads a file from a server without range support", async () => {
		const url = "https://repo.example.org/delta.lex";
		const bytes = await deltaLex();
		mockFetch({ [url]: () => new Response(bytes, { status: 200 }) });
		const lex = await readLex(url);
		expect(lex.manifest.name).toBe("Delta");
		expect(calls).toHaveLength(1);
	});

	it("fails for a file that is not a zip", async () => {
		const url = "https://repo.example.org/broken.lex";
		mockFetch({ [url]: "not a zip" });
		await expect(readLex(url)).rejects.toThrow("not a zip file");
	});
});
