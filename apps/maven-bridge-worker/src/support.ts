// Port of BridgeSupport.cfc: one configured provider / groupId.
import { compareNoCase, containsNoCase, encodeForHtml, equalsNoCase, isNumeric, mavenTimestamp, startsWithNoCase, xmlFormat } from "./cfml";
import { splitChecksum } from "./checksum";
import { DEFAULT_GITHUB_RELEASES_URL, normalizeUpstreamUrl, val } from "./config";
import { BridgeError, isUpstreamNotFound } from "./errors";
import type { RestIndex } from "./rest-index";
import { sortVersions } from "./rest-index";
import { childText, select, textOf } from "./xml";

export const SNAPSHOT_SUFFIX = "-SNAPSHOT";
const GITHUB_RELEASES_MIN_VERSION = [7, 1];
// core files published as GitHub Release assets (classifier -> allowed extensions)
const GITHUB_RELEASE_FILES: Record<string, string[]> = {
	"": ["jar", "lco", "war"],
	light: ["jar"],
	zero: ["jar"],
	express: ["zip"]
};

export type ParsedType =
	| "unknown"
	| "group-index"
	| "group-metadata"
	| "artifact-index"
	| "artifact-metadata"
	| "version-index"
	| "version-metadata"
	| "artifact-file";

export interface ParsedPath {
	type: ParsedType;
	groupId?: string;
	artifactId?: string;
	version?: string;
	classifier?: string;
	extension?: string;
}

export interface UpstreamContent {
	body: string;
	contentType: string;
}

/** I/O used by the support; implemented by the Worker runtime (store.ts) and by tests. */
export interface SupportIo {
	/** Cached upstream text file; throws BridgeError(UPSTREAM_NOT_FOUND) on 404. */
	getUpstreamContent(support: BridgeSupport, relativePath: string): Promise<UpstreamContent>;
	/** HEAD with redirects, true on 200, false on any error (remoteResourceExists). */
	remoteResourceExists(url: string): Promise<boolean>;
	/** HEAD on the upstream, true on 200 (upstreamResourceExists). */
	upstreamResourceExists(support: BridgeSupport, relativePath: string): Promise<boolean>;
	/** REST provider index (cached). */
	getIndex(support: BridgeSupport): Promise<RestIndex>;
}

export interface SupportConfig {
	provider: string;
	groupId: string;
	upstream?: string;
	cacheTtlMinutes?: number;
	timeout?: number;
	githubReleasesUrl?: string;
}

export class BridgeSupport {
	readonly providerUrl: string;
	readonly groupId: string;
	readonly upstreamUrl: string;
	readonly cacheTtlMinutes: number;
	readonly timeout: number;
	readonly githubReleasesUrl: string;
	io!: SupportIo;

	constructor(config: SupportConfig) {
		let provider = config.provider.trim();
		if (provider.endsWith("/")) provider = provider.slice(0, -1);
		this.providerUrl = provider;
		this.groupId = config.groupId.trim();
		this.upstreamUrl = normalizeUpstreamUrl(config.upstream ?? "");
		let ttl = val(config.cacheTtlMinutes ?? 60);
		if (ttl < 1) ttl = 60;
		let timeout = val(config.timeout ?? 300);
		if (timeout < 1) timeout = 300;
		this.cacheTtlMinutes = ttl;
		this.timeout = timeout;
		this.githubReleasesUrl =
			config.githubReleasesUrl !== undefined
				? normalizeUpstreamUrl(config.githubReleasesUrl)
				: DEFAULT_GITHUB_RELEASES_URL;
	}

	get groupPath(): string {
		return this.groupId.split(".").join("/");
	}

	hasUpstream(): boolean {
		return this.upstreamUrl.length > 0;
	}

	// --- path parsing ---

	parseMavenPath(path: string): ParsedPath {
		const prefix = "/" + this.groupPath;
		if (equalsNoCase(path, prefix) || equalsNoCase(path, prefix + "/")) {
			return { type: "group-index", groupId: this.groupId };
		}
		if (!startsWithNoCase(path, prefix + "/")) return { type: "unknown" };

		const parts = path.slice(prefix.length + 1).split("/").filter((p) => p.length);
		const groupId = this.groupId;
		const isMeta = (p: string) => equalsNoCase(p, "maven-metadata.xml");

		if (parts.length === 1) {
			if (isMeta(parts[0])) return { type: "group-metadata", groupId };
			return { type: "artifact-index", groupId, artifactId: parts[0] };
		}
		if (parts.length === 2) {
			if (isMeta(parts[1])) return { type: "artifact-metadata", groupId, artifactId: parts[0] };
			return { type: "version-index", groupId, artifactId: parts[0], version: parts[1] };
		}
		if (parts.length === 3) {
			const [artifactId, version, fileName] = parts;
			if (isMeta(fileName)) return { type: "version-metadata", groupId, artifactId, version };
			// after "<artifactId>-<version>" comes ".<extension>" or "-<classifier>.<extension>"
			const base = artifactId + "-" + version;
			if (startsWithNoCase(fileName, base) && fileName.length > base.length) {
				let rest = fileName.slice(base.length);
				let classifier = "";
				const dot = rest.indexOf(".") + 1; // CFML find(), 1-based, 0 = none
				if (rest.startsWith("-") && dot > 2) {
					classifier = rest.substring(1, dot - 1);
					rest = rest.slice(dot - 1);
				}
				if (rest.startsWith(".") && rest.length > 1) {
					return { type: "artifact-file", groupId, artifactId, version, classifier, extension: rest.slice(1) };
				}
			}
		}
		return { type: "unknown" };
	}

	toUpstreamRelativePath(parsed: ParsedPath): string {
		const g = this.groupPath;
		const a = parsed.artifactId;
		const v = parsed.version;
		switch (parsed.type) {
			case "group-index": return `${g}/index.html`;
			case "group-metadata": return `${g}/maven-metadata.xml`;
			case "artifact-index": return `${g}/${a}/index.html`;
			case "artifact-metadata": return `${g}/${a}/maven-metadata.xml`;
			case "version-index": return `${g}/${a}/${v}/index.html`;
			case "version-metadata": return `${g}/${a}/${v}/maven-metadata.xml`;
			case "artifact-file": {
				let fileName = `${a}-${v}`;
				if (parsed.classifier) fileName += "-" + parsed.classifier;
				fileName += "." + parsed.extension;
				return `${g}/${a}/${v}/${fileName}`;
			}
			default: return "";
		}
	}

	/**
	 * Core "lucee" build files live flat at the upstream root with legacy names
	 * (lucee-light-<v>.jar, forgebox-<v>.zip, <v>.lco, ...); "" = no mapping.
	 */
	toUpstreamLegacyCorePath(parsed: ParsedPath): string {
		if (parsed.type !== "artifact-file" || !equalsNoCase(parsed.artifactId ?? "", "lucee")) return "";
		// checksum files keep the legacy name of their artifact: 6.2.0.321.lco.sha1
		const checksum = splitChecksum(parsed);
		if (checksum) {
			const base = this.toUpstreamLegacyCorePath(checksum.artifact);
			return base.length ? `${base}.${parsed.extension!.slice(checksum.artifact.extension!.length + 1)}` : "";
		}
		const version = parsed.version!;
		const ext = parsed.extension!;
		const classifier = parsed.classifier ?? "";
		if (equalsNoCase(ext, "lco") && !classifier.length) return `${version}.lco`;
		if (startsWithNoCase(classifier, "forgebox")) return `${classifier}-${version}.${ext}`;
		if (classifier.length) return `lucee-${classifier}-${version}.${ext}`;
		return `lucee-${version}.${ext}`;
	}

	/** true for an org.lucee:lucee core build file */
	isCoreFile(parsed: ParsedPath): boolean {
		return parsed.type === "artifact-file" && equalsNoCase(parsed.artifactId ?? "", "lucee");
	}

	/**
	 * Upstream URL of a core file, in lookup order (LDEV-6726):
	 * 1. GitHub Release asset (7.1+ final/RC jar, lco, war, light, zero, express)
	 * 2. Maven layout on the upstream (org/lucee/lucee/<v>/lucee-<v>[-<classifier>].<ext>), e.g. poms and snapshots
	 * 3. legacy flat CDN name (lucee-light-<v>.jar, <v>.lco, ...) for older builds
	 * "" when none exists.
	 */
	async findCoreFileUrl(parsed: ParsedPath): Promise<string> {
		if (!this.isCoreFile(parsed) || !this.hasUpstream()) return "";
		const github = await this.findGithubReleaseUrl(parsed);
		if (github.length) return github;

		const mavenPath = this.toUpstreamRelativePath(parsed);
		let mavenExists = false;
		try {
			mavenExists = await this.io.upstreamResourceExists(this, mavenPath);
		} catch (e) {
			// a failing check must not hide the legacy fallback
			console.warn(`maven-bridge HEAD ${this.upstreamUrl + mavenPath} failed`, e);
		}
		if (mavenExists) return this.upstreamUrl + mavenPath;

		const legacyPath = this.toUpstreamLegacyCorePath(parsed);
		if (legacyPath.length && (await this.io.upstreamResourceExists(this, legacyPath))) {
			return this.upstreamUrl + legacyPath;
		}
		return "";
	}

	/** true for non-snapshot core versions from 7.1 on; 6.2/7.0 stay on the upstream CDN */
	isGithubReleaseVersion(version: string): boolean {
		if (!this.githubReleasesUrl.length) return false;
		if (containsNoCase(version, SNAPSHOT_SUFFIX)) return false;
		const numeric = version.split("-").filter((p) => p.length)[0] ?? "";
		const parts = numeric.split(".").filter((p) => p.length);
		if (parts.length < 2 || !isNumeric(parts[0]) || !isNumeric(parts[1])) return false;
		const major = val(parts[0]);
		const minor = val(parts[1]);
		const [minMajor, minMinor] = GITHUB_RELEASES_MIN_VERSION;
		return major > minMajor || (major === minMajor && minor >= minMinor);
	}

	/** Candidate GitHub Release asset URLs for a core file, in lookup order (LDEV-6706). */
	toGithubReleaseUrls(parsed: ParsedPath): string[] {
		if (parsed.type !== "artifact-file" || !equalsNoCase(parsed.artifactId ?? "", "lucee")) return [];
		const version = parsed.version!;
		if (!this.isGithubReleaseVersion(version)) return [];
		const classifier = (parsed.classifier ?? "").toLowerCase();
		const allowed = GITHUB_RELEASE_FILES[classifier];
		if (!Object.prototype.hasOwnProperty.call(GITHUB_RELEASE_FILES, classifier) || !allowed.some((e) => equalsNoCase(e, parsed.extension!))) {
			return [];
		}
		const fileName = this.toUpstreamLegacyCorePath(parsed);
		const tags = [version.split("-").filter((p) => p.length)[0] ?? version];
		if (!equalsNoCase(tags[0], version)) tags.push(version);
		return tags.map((tag) => this.githubReleasesUrl + tag + "/" + fileName);
	}

	async findGithubReleaseUrl(parsed: ParsedPath): Promise<string> {
		for (const candidate of this.toGithubReleaseUrls(parsed)) {
			if (await this.io.remoteResourceExists(candidate)) return candidate;
		}
		return "";
	}

	contentTypeForPath(relativePath: string): string {
		return contentTypeForPath(relativePath);
	}

	// --- REST provider data ---

	async getIndex(): Promise<RestIndex> {
		return this.io.getIndex(this);
	}

	async listVersions(artifactId: string): Promise<string[]> {
		const artifact = (await this.getIndex()).artifacts.get(artifactId);
		if (!artifact) return [];
		return sortVersions(artifact.versions.keys());
	}

	async getDownloadUrl(artifactId: string, version: string): Promise<string> {
		const artifact = (await this.getIndex()).artifacts.get(artifactId);
		return artifact?.versions.get(version)?.downloadUrl ?? "";
	}

	/** versions listed in the upstream artifact maven-metadata.xml */
	async listUpstreamVersions(artifactId: string): Promise<string[]> {
		const content = await this.io.getUpstreamContent(this, `${this.groupPath}/${artifactId}/maven-metadata.xml`);
		return select(content.body, ["metadata", "versioning", "versions", "version"]).map((v) => textOf(v));
	}

	// --- builders ---

	async buildGroupMetadata(now = new Date()): Promise<string> {
		const index = await this.getIndex();
		const artifactIds = index.artifacts.keys().sort(compareNoCase);
		const xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			`  <groupId>${xmlFormat(this.groupId)}</groupId>`,
			"  <artifacts>"
		];
		for (const artifactId of artifactIds) {
			const versions = await this.listVersions(artifactId);
			if (!versions.length) continue;
			const latest = versions[versions.length - 1];
			const release = lastRelease(versions);
			xml.push("    <artifact>");
			xml.push(`      <artifactId>${xmlFormat(artifactId)}</artifactId>`);
			xml.push(`      <latest>${xmlFormat(latest)}</latest>`);
			if (release.length) xml.push(`      <release>${xmlFormat(release)}</release>`);
			xml.push("    </artifact>");
		}
		xml.push("  </artifacts>");
		xml.push(`  <lastUpdated>${xmlFormat(mavenTimestamp(now))}</lastUpdated>`);
		xml.push("</metadata>");
		return xml.join("\n");
	}

	async buildGroupIndexHtml(): Promise<string> {
		const index = await this.getIndex();
		const artifactIds = index.artifacts.keys().sort(compareNoCase);
		const html = [
			"<!DOCTYPE html>",
			`<html><head><title>${encodeForHtml(this.groupId)}</title></head><body>`,
			`<h1>${encodeForHtml(this.groupId)}</h1>`,
			"<pre>",
			'<a href="maven-metadata.xml">maven-metadata.xml</a>\n'
		];
		for (const id of artifactIds) html.push(`<a href="${encodeForHtml(id)}/">${encodeForHtml(id)}/</a>\n`);
		html.push("</pre></body></html>");
		return html.join("\n");
	}

	async buildArtifactIndexHtml(artifactId: string, versions?: string[]): Promise<string> {
		const versionList = versions ?? (await this.listVersions(artifactId));
		const title = `${encodeForHtml(this.groupId)}:${encodeForHtml(artifactId)}`;
		const html = [
			"<!DOCTYPE html>",
			`<html><head><title>${title}</title></head><body>`,
			`<h1>${title}</h1>`,
			"<pre>",
			'<a href="maven-metadata.xml">maven-metadata.xml</a>\n'
		];
		for (const v of versionList) html.push(`<a href="${encodeForHtml(v)}/">${encodeForHtml(v)}/</a>\n`);
		html.push("</pre></body></html>");
		return html.join("\n");
	}

	/**
	 * Version index for upstream mirrors: the file list comes from the upstream
	 * version-level maven-metadata.xml (snapshotVersions), otherwise a single .lex.
	 */
	async buildUpstreamVersionIndexHtml(artifactId: string, version: string): Promise<string> {
		const baseName = `${artifactId}-${version}`;
		let files: string[] = [];
		let hasVersionMetadata = false;
		try {
			const content = await this.io.getUpstreamContent(this, `${this.groupPath}/${artifactId}/${version}/maven-metadata.xml`);
			hasVersionMetadata = true;
			for (const node of select(content.body, ["metadata", "versioning", "snapshotVersions", "snapshotVersion"])) {
				const value = childText(node, "value") ?? version;
				const classifier = childText(node, "classifier") ?? "";
				const extension = childText(node, "extension");
				if (extension === undefined) throw new BridgeError("Element EXTENSION is undefined in snapshotVersion");
				files.push(`${artifactId}-${value}${classifier.length ? "-" + classifier : ""}.${extension}`);
			}
		} catch (e) {
			if (!isUpstreamNotFound(e)) throw e;
		}
		if (!files.length) files = [baseName + ".lex"];

		const html = [
			"<!DOCTYPE html>",
			`<html><head><title>${encodeForHtml(baseName)}</title></head><body>`,
			`<h1>${encodeForHtml(baseName)}</h1>`,
			"<pre>"
		];
		if (hasVersionMetadata || containsNoCase(version, SNAPSHOT_SUFFIX)) {
			html.push('<a href="maven-metadata.xml">maven-metadata.xml</a>\n');
		}
		for (const f of files) html.push(`<a href="${encodeForHtml(f)}">${encodeForHtml(f)}</a>\n`);
		html.push("</pre></body></html>");
		return html.join("\n");
	}

	buildVersionIndexHtml(artifactId: string, version: string): string {
		const baseName = `${artifactId}-${version}`;
		const b = encodeForHtml(baseName);
		const html = ["<!DOCTYPE html>", `<html><head><title>${b}</title></head><body>`, `<h1>${b}</h1>`, "<pre>"];
		if (containsNoCase(version, SNAPSHOT_SUFFIX)) html.push('<a href="maven-metadata.xml">maven-metadata.xml</a>\n');
		html.push(`<a href="${b}.lex">${b}.lex</a>\n`);
		html.push(`<a href="${b}.pom">${b}.pom</a>\n`);
		html.push("</pre></body></html>");
		return html.join("\n");
	}

	async buildArtifactMetadata(artifactId: string, now = new Date()): Promise<string> {
		const versions = await this.listVersions(artifactId);
		if (!versions.length) throw new BridgeError(`No versions found for [${artifactId}]`, "bridge.notfound");
		const latest = versions[versions.length - 1];
		const release = lastRelease(versions);
		const xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			`  <groupId>${xmlFormat(this.groupId)}</groupId>`,
			`  <artifactId>${xmlFormat(artifactId)}</artifactId>`,
			"  <versioning>",
			`    <latest>${xmlFormat(latest)}</latest>`
		];
		if (release.length) xml.push(`    <release>${xmlFormat(release)}</release>`);
		xml.push("    <versions>");
		for (const v of versions) xml.push(`      <version>${xmlFormat(v)}</version>`);
		xml.push("    </versions>");
		xml.push(`    <lastUpdated>${xmlFormat(mavenTimestamp(now))}</lastUpdated>`);
		xml.push("  </versioning>");
		xml.push("</metadata>");
		return xml.join("\n");
	}

	async buildVersionMetadata(artifactId: string, version: string, now = new Date()): Promise<string> {
		if (!containsNoCase(version, SNAPSHOT_SUFFIX)) return this.buildArtifactMetadata(artifactId, now);
		const ts = xmlFormat(mavenTimestamp(now));
		return [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			`  <groupId>${xmlFormat(this.groupId)}</groupId>`,
			`  <artifactId>${xmlFormat(artifactId)}</artifactId>`,
			`  <version>${xmlFormat(version)}</version>`,
			"  <versioning>",
			"    <snapshot>",
			`      <timestamp>${ts}</timestamp>`,
			"      <buildNumber>1</buildNumber>",
			"    </snapshot>",
			`    <lastUpdated>${ts}</lastUpdated>`,
			"    <snapshotVersions>",
			"      <snapshotVersion>",
			"        <extension>lex</extension>",
			`        <value>${xmlFormat(version)}</value>`,
			`        <updated>${ts}</updated>`,
			"      </snapshotVersion>",
			"    </snapshotVersions>",
			"  </versioning>",
			"</metadata>"
		].join("\n");
	}

	async buildMinimalPom(artifactId: string, version: string): Promise<string> {
		const ext = (await this.getIndex()).artifacts.get(artifactId)?.versions.get(version);
		const xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			'<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">',
			"  <modelVersion>4.0.0</modelVersion>",
			`  <groupId>${xmlFormat(this.groupId)}</groupId>`,
			`  <artifactId>${xmlFormat(artifactId)}</artifactId>`,
			`  <version>${xmlFormat(version)}</version>`,
			"  <packaging>lex</packaging>",
			`  <name>${xmlFormat(ext?.name ?? artifactId)}</name>`
		];
		if (ext?.description) xml.push(`  <description>${xmlFormat(ext.description)}</description>`);
		xml.push("</project>");
		return xml.join("\n");
	}
}

function lastRelease(versions: string[]): string {
	for (let i = versions.length - 1; i >= 0; i--) {
		if (!containsNoCase(versions[i], SNAPSHOT_SUFFIX)) return versions[i];
	}
	return "";
}

export function contentTypeForPath(relativePath: string): string {
	const path = relativePath.toLowerCase();
	if (path.endsWith(".xml")) return "application/xml; charset=utf-8";
	if (path.endsWith(".html")) return "text/html; charset=utf-8";
	return "application/octet-stream";
}
