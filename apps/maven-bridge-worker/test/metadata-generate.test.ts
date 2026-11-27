import { describe, expect, it } from "vitest";
import { findLatestRelease, isSnapshotVersion, sortVersions } from "../src/maven-version";
import {
	buildArtifactMetadataXml,
	buildGroupMetadataXml,
	generateDirectoryListingHtml,
	groupFingerprint,
	parseArtifactMetadataXml,
	parseDirectoryListingHtml,
	parseGroupMetadataXml,
	splitMetadataChecksum,
	summarizeVersions,
	versionsFingerprint,
	xmlEscape
} from "../src/metadata-generate";
import { artifactFromR2Key, eventObjectKeys, mavenLayoutPrefixes } from "../src/r2-metadata";

describe("summarizeVersions", () => {
	it("sorts Maven-style and treats SNAPSHOT as latest when it is highest, but not as release", () => {
		const s = summarizeVersions(["7.1.3.0-SNAPSHOT", "7.1.2.191", "8.0.0.1-RC", "8.0.0.1"]);
		expect(s.versions).toEqual(["7.1.2.191", "7.1.3.0-SNAPSHOT", "8.0.0.1-RC", "8.0.0.1"]);
		expect(s.latest).toBe("8.0.0.1");
		expect(s.release).toBe("8.0.0.1");
	});

	it("includes a SNAPSHOT in <latest> when it is the highest version", () => {
		const s = summarizeVersions(["4.2.0.6", "4.3.0.1-SNAPSHOT"]);
		expect(s.latest).toBe("4.3.0.1-SNAPSHOT");
		expect(s.release).toBe("4.2.0.6");
	});

	it("counts RC, BETA and ALPHA as a release, matching the current upstream files", () => {
		const s = summarizeVersions(["8.0.1.126-SNAPSHOT", "9.0.0.1510-ALPHA"]);
		expect(s.latest).toBe("9.0.0.1510-ALPHA");
		expect(s.release).toBe("9.0.0.1510-ALPHA");
		expect(findLatestRelease(sortVersions(["8.0.0.304-RC", "8.0.0.304"]))).toBe("8.0.0.304");
		expect(isSnapshotVersion("7.1.3.0-SNAPSHOT")).toBe(true);
		expect(isSnapshotVersion("7.1.3.0-RC")).toBe(false);
	});

	it("returns empty latest and release for an empty artifact", () => {
		const s = summarizeVersions([]);
		expect(s.versions).toEqual([]);
		expect(s.latest).toBe("");
		expect(s.release).toBe("");
	});
});

describe("buildArtifactMetadataXml", () => {
	it("writes latest, release and versions in the upstream format", () => {
		const xml = buildArtifactMetadataXml("org.lucee", "redis-extension", ["4.3.0.1-SNAPSHOT", "4.2.0.6"], "20261127170643");
		expect(xml).toBe(`<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifactId>redis-extension</artifactId>
  <versioning>
    <latest>4.3.0.1-SNAPSHOT</latest>
    <release>4.2.0.6</release>
    <versions>
      <version>4.2.0.6</version>
      <version>4.3.0.1-SNAPSHOT</version>
    </versions>
    <lastUpdated>20261127170643</lastUpdated>
  </versioning>
</metadata>`);
		expect(parseArtifactMetadataXml(xml)).toEqual({
			versions: ["4.2.0.6", "4.3.0.1-SNAPSHOT"],
			latest: "4.3.0.1-SNAPSHOT",
			release: "4.2.0.6"
		});
	});

	it("builds a valid empty versions list", () => {
		const xml = buildArtifactMetadataXml("org.lucee", "unknown", [], "20260101000000");
		expect(xml).toContain("<latest></latest>");
		expect(xml).toContain("<release></release>");
		expect(xml).toContain("    <versions>\n    </versions>");
		expect(parseArtifactMetadataXml(xml).versions).toEqual([]);
	});

	it("escapes special characters in artifact ids", () => {
		expect(xmlEscape('a&b<"\'>')).toBe("a&amp;b&lt;&quot;&apos;&gt;");
	});

	it("keeps a stable fingerprint when the same versions are given in another order", () => {
		expect(versionsFingerprint(["2.0", "1.0-SNAPSHOT"])).toBe(versionsFingerprint(["1.0-SNAPSHOT", "2.0"]));
	});
});

describe("group metadata and directory listing", () => {
	it("omits an empty <release> and sorts artifacts by id", () => {
		const xml = buildGroupMetadataXml(
			"org.lucee",
			[
				{ artifactId: "crypto-extension", latest: "1.0.0.1-SNAPSHOT", release: "" },
				{ artifactId: "ajax-extension", latest: "1.0.0.8", release: "1.0.0.8" }
			],
			"20261127170643"
		);
		expect(xml).toBe(`<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifacts>
    <artifact>
      <artifactId>ajax-extension</artifactId>
      <latest>1.0.0.8</latest>
      <release>1.0.0.8</release>
    </artifact>
    <artifact>
      <artifactId>crypto-extension</artifactId>
      <latest>1.0.0.1-SNAPSHOT</latest>
    </artifact>
  </artifacts>
  <lastUpdated>20261127170643</lastUpdated>
</metadata>`);
		expect(parseGroupMetadataXml(xml).map((a) => a.artifactId)).toEqual(["ajax-extension", "crypto-extension"]);
		expect(groupFingerprint(parseGroupMetadataXml(xml)).length).toBeGreaterThan(0);
	});

	it("renders the group index with a metadata row and artifact folders", () => {
		const html = generateDirectoryListingHtml(
			[
				{ name: "lucee", lastModified: new Date("2026-11-27T17:05:00Z") },
				{ name: "redis-extension" }
			],
			new Date("2026-11-27T17:06:00Z")
		);
		expect(html).toContain("<title>Central Repository: org/lucee</title>");
		expect(html).toContain('<a href="maven-metadata.xml" title="maven-metadata.xml">');
		expect(html).toContain("2026-11-27 17:06");
		expect(html).toContain('<a href="lucee/" title="lucee/">');
		expect(html).toContain("2026-11-27 17:05");
		expect(html).toContain('<a href="redis-extension/" title="redis-extension/">');
		expect(html.indexOf("lucee/")).toBeLessThan(html.indexOf("redis-extension/"));
		const parsed = parseDirectoryListingHtml(html);
		expect(parsed.map((e) => e.name)).toEqual(["lucee", "redis-extension"]);
	});
});

describe("splitMetadataChecksum", () => {
	it("recognises metadata files and their checksums", () => {
		expect(splitMetadataChecksum("maven-metadata.xml")).toEqual({ name: "maven-metadata.xml" });
		expect(splitMetadataChecksum("MAVEN-METADATA.XML.SHA1")).toEqual({ name: "maven-metadata.xml", checksumType: "sha1" });
		expect(splitMetadataChecksum("maven-metadata.xml.md5")?.checksumType).toBe("md5");
		expect(splitMetadataChecksum("index.html")).toBeUndefined();
		expect(splitMetadataChecksum("lucee-1.jar.sha1")).toBeUndefined();
	});
});

describe("R2 key and event helpers", () => {
	const roots = { r2Prefix: "", r2SnapshotPrefix: "snapshots/" };

	it("lists both the release tree and the SNAPSHOT tree", () => {
		expect(mavenLayoutPrefixes("org/lucee", roots)).toEqual(["org/lucee/", "snapshots/org/lucee/"]);
		expect(mavenLayoutPrefixes("org/lucee", { r2Prefix: "pre/", r2SnapshotPrefix: "snapshots/" })).toEqual([
			"pre/org/lucee/",
			"pre/snapshots/org/lucee/"
		]);
	});

	it("maps an object-created key to its artifact and ignores metadata files", () => {
		expect(artifactFromR2Key("org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar", "org/lucee", roots)).toEqual({
			artifactId: "lucee"
		});
		expect(
			artifactFromR2Key("snapshots/org/lucee/redis-extension/4.3.0.1-SNAPSHOT/redis-extension-4.3.0.1-SNAPSHOT.lex", "org/lucee", roots)
		).toEqual({ artifactId: "redis-extension" });
		expect(artifactFromR2Key("org/lucee/lucee/maven-metadata.xml", "org/lucee", roots)).toBeUndefined();
		expect(artifactFromR2Key("org/lucee/index.html", "org/lucee", roots)).toBeUndefined();
		expect(artifactFromR2Key("other/file.jar", "org/lucee", roots)).toBeUndefined();
	});

	it("reads object keys from R2 event notification payloads", () => {
		expect(eventObjectKeys({ action: "PutObject", object: { key: "org/lucee/lucee/1/a.jar" } })).toEqual([
			"org/lucee/lucee/1/a.jar"
		]);
		expect(
			eventObjectKeys([
				{ action: "PutObject", object: { key: "a" } },
				{ action: "CompleteMultipartUpload", object: { key: "b" } }
			])
		).toEqual(["a", "b"]);
	});
});
