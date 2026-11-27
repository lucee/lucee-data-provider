// Build Maven metadata XML and the org.lucee group directory listing from a list of
// versions / artifacts. The format matches the files written for the current upstream
// (lucee/Lucee ant/upload_to_s3.cfm and .github/scripts/maven-group-metadata.js):
//   <latest>  = highest version (SNAPSHOT, RC, BETA and ALPHA included)
//   <release> = highest non-SNAPSHOT version (RC / BETA / ALPHA count as a release)
//   <versions> in Maven ComparableVersion order, oldest first
//   <lastUpdated> is a UTC yyyyMMddHHmmss stamp
import { mavenTimestamp } from "./cfml";
import type { ChecksumType } from "./checksum";
import { findLatestRelease, sortVersions } from "./maven-version";

export const GROUP_METADATA_NAME = "maven-metadata.xml";
export const GROUP_INDEX_NAME = "index.html";
export const CHECKSUM_SUFFIXES: ChecksumType[] = ["md5", "sha1", "sha256", "sha512"];

export function xmlEscape(value: string): string {
	return String(value)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&apos;");
}

export function isExtensionArtifactId(artifactId: string): boolean {
	return artifactId.endsWith("-extension");
}

/** Split "maven-metadata.xml.sha1" into the metadata file and an optional checksum type. */
export function splitMetadataChecksum(fileName: string): { name: string; checksumType?: ChecksumType } | undefined {
	const lower = fileName.toLowerCase();
	if (lower === GROUP_METADATA_NAME) return { name: GROUP_METADATA_NAME };
	for (const type of CHECKSUM_SUFFIXES) {
		if (lower === `${GROUP_METADATA_NAME}.${type}`) return { name: GROUP_METADATA_NAME, checksumType: type };
	}
	return undefined;
}

export interface ArtifactVersions {
	versions: string[];
	latest: string;
	release: string;
}

/** Unique versions, Maven order, plus latest / release. An empty list is valid (latest and release are ""). */
export function summarizeVersions(versions: Iterable<string>): ArtifactVersions {
	const sorted = sortVersions(new Set([...versions].map((v) => v.trim()).filter((v) => v.length)));
	return {
		versions: sorted,
		latest: sorted[sorted.length - 1] ?? "",
		release: findLatestRelease(sorted)
	};
}

export function parseArtifactMetadataXml(xml: string): ArtifactVersions {
	const versions: string[] = [];
	const block = xml.match(/<versions>([\s\S]*?)<\/versions>/i)?.[1] ?? "";
	for (const match of block.matchAll(/<version>([^<]*)<\/version>/gi)) {
		const v = match[1].trim();
		if (v) versions.push(v);
	}
	const summarized = summarizeVersions(versions);
	if (summarized.versions.length) return summarized;
	const latest = xml.match(/<latest>([^<]*)<\/latest>/i)?.[1]?.trim() ?? "";
	const release = xml.match(/<release>([^<]*)<\/release>/i)?.[1]?.trim() ?? "";
	return { versions: [], latest, release };
}

export function buildArtifactMetadataXml(
	groupId: string,
	artifactId: string,
	versions: Iterable<string>,
	lastUpdated: string
): string {
	const { versions: sorted, latest, release } = summarizeVersions(versions);
	const lines = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		"<metadata>",
		`  <groupId>${xmlEscape(groupId)}</groupId>`,
		`  <artifactId>${xmlEscape(artifactId)}</artifactId>`,
		"  <versioning>",
		`    <latest>${xmlEscape(latest)}</latest>`,
		`    <release>${xmlEscape(release)}</release>`,
		"    <versions>"
	];
	for (const version of sorted) lines.push(`      <version>${xmlEscape(version)}</version>`);
	lines.push(
		"    </versions>",
		`    <lastUpdated>${xmlEscape(lastUpdated)}</lastUpdated>`,
		"  </versioning>",
		"</metadata>"
	);
	return lines.join("\n");
}

export interface GroupArtifact {
	artifactId: string;
	latest: string;
	release: string;
}

export function parseGroupMetadataXml(xml: string): GroupArtifact[] {
	const artifacts: GroupArtifact[] = [];
	for (const block of xml.matchAll(/<artifact>([\s\S]*?)<\/artifact>/gi)) {
		const body = block[1];
		const artifactId = body.match(/<artifactId>([^<]*)<\/artifactId>/i)?.[1]?.trim() ?? "";
		if (!artifactId) continue;
		artifacts.push({
			artifactId,
			latest: body.match(/<latest>([^<]*)<\/latest>/i)?.[1]?.trim() ?? "",
			release: body.match(/<release>([^<]*)<\/release>/i)?.[1]?.trim() ?? ""
		});
	}
	return artifacts;
}

export function buildGroupMetadataXml(groupId: string, artifacts: GroupArtifact[], lastUpdated: string): string {
	const sorted = [...artifacts].sort((a, b) => a.artifactId.localeCompare(b.artifactId));
	const lines = [
		'<?xml version="1.0" encoding="UTF-8"?>',
		"<metadata>",
		`  <groupId>${xmlEscape(groupId)}</groupId>`,
		"  <artifacts>"
	];
	for (const artifact of sorted) {
		lines.push("    <artifact>");
		lines.push(`      <artifactId>${xmlEscape(artifact.artifactId)}</artifactId>`);
		lines.push(`      <latest>${xmlEscape(artifact.latest)}</latest>`);
		if (artifact.release) lines.push(`      <release>${xmlEscape(artifact.release)}</release>`);
		lines.push("    </artifact>");
	}
	lines.push("  </artifacts>", `  <lastUpdated>${xmlEscape(lastUpdated)}</lastUpdated>`, "</metadata>");
	return lines.join("\n");
}

export interface DirectoryEntry {
	name: string;
	lastModified?: Date;
}

export function parseDirectoryListingHtml(html: string): DirectoryEntry[] {
	const entries: DirectoryEntry[] = [];
	for (const match of html.matchAll(/<a href="([^"]+)\/" title="[^"]*">[\s\S]*?<\/a>\s+([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}|\s+-)/gi)) {
		const name = match[1];
		if (!name || name === ".." || name === "maven-metadata.xml") continue;
		const dateRaw = match[2].trim();
		const lastModified = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(dateRaw) ? new Date(dateRaw.replace(" ", "T") + ":00Z") : undefined;
		entries.push({ name, lastModified: lastModified && !Number.isNaN(lastModified.getTime()) ? lastModified : undefined });
	}
	return entries;
}

function formatListingDate(date: Date | undefined, now: Date): string {
	const value = date && date.getTime() !== 0 ? date : undefined;
	if (!value) return "                   -";
	const stamp = (value.getTime() ? value : now).toISOString().slice(0, 16).replace("T", " ");
	return stamp;
}

export function generateDirectoryListingHtml(artifacts: DirectoryEntry[], now = new Date()): string {
	const sorted = [...artifacts].sort((a, b) => a.name.localeCompare(b.name));
	const padName = (name: string) => name.padEnd(50);
	const metadataLine = `<a href="maven-metadata.xml" title="maven-metadata.xml">${padName("maven-metadata.xml")}</a>                     ${formatListingDate(now, now)}         -      `;
	const artifactLinks = sorted
		.map((artifact) => {
			const label = artifact.name + "/";
			return `<a href="${label}" title="${label}">${padName(label)}</a>                     ${formatListingDate(artifact.lastModified, now)}         -      `;
		})
		.join("\n");
	return `<!DOCTYPE html>
<html>

<head>
  <title>Central Repository: org/lucee</title>
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
body {
  background: #fff;
}
  </style>
</head>

<body>
  <header>
    <h1>org/lucee</h1>
  </header>
  <hr/>
  <main>
    <pre id="contents">
<a href="../">../</a>
${metadataLine}
${artifactLinks}
    </pre>
  </main>
  <hr/>
</body>

</html>`;
}

export function listingFingerprint(artifacts: DirectoryEntry[]): string {
	return artifacts
		.map((a) => a.name)
		.sort((a, b) => a.localeCompare(b))
		.join("\n");
}

export function versionsFingerprint(versions: Iterable<string>): string {
	return summarizeVersions(versions).versions.join("\n");
}

export function groupFingerprint(artifacts: GroupArtifact[]): string {
	return [...artifacts]
		.map((a) => `${a.artifactId}\t${a.latest}\t${a.release}`)
		.sort()
		.join("\n");
}

export function mavenTimestampNow(date = new Date()): string {
	return mavenTimestamp(date);
}
