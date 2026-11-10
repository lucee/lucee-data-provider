// Port of services/MavenExtensionSource.cfc (LDEV-6789): the extensions published to Maven repositories,
// the same repositories Lucee core uses (releases, snapshots and the "mixed" Lucee repository), and
// (LDEV-6789) the Maven layout of the core bucket (cdn.lucee.org/org/lucee/), read over http.
import type { Config } from "./config";
import { httpGet, mapLimit, type HttpResult } from "./http";
import { groupArtifacts, metadataVersions, snapshotVersions } from "./xml";

export interface MavenFile {
	name: string;
	artifact: string;
	version: string;
	/** Maven layout of the core bucket: the path relative to the Maven cdn url */
	path?: string;
	/** Maven repositories: the repos the version is in, in order of preference */
	repos?: string[];
}

export interface MavenListing {
	files: MavenFile[];
	/** false when a repository or an artifact could not be read */
	complete: boolean;
}

const GROUP = "org.lucee";
const SUFFIX = "-extension";
// requests at the same time (EXTENSIONS_MAVEN_THREADS of the CFML version, a Worker has 6 connections at a time)
const MAX_THREADS = 6;

export function isSnapshot(version: string): boolean {
	return version.endsWith("-SNAPSHOT");
}

export class MavenExtensionSource {
	private readonly snapshotFiles = new Map<string, { file: string; time: number }>();
	private readonly snapshotTtlMs = 300_000;

	constructor(private readonly config: Config) {}

	hasRepos(): boolean {
		return this.config.releaseRepos.length + this.config.snapshotRepos.length + this.config.mixedRepos.length > 0;
	}

	private get(url: string) {
		return httpGet(url, { timeoutMs: this.config.timeoutMs, cacheSeconds: this.config.metadataCacheSeconds });
	}

	/** the extension versions of all the repositories, see listExtensions() of the CFML version */
	async listExtensions(): Promise<MavenListing> {
		const result: MavenListing = { files: [], complete: true };
		if (!this.hasRepos()) return result;

		const listing = await this.listArtifacts();
		result.complete = listing.complete;

		const found = await mapLimit(listing.artifacts, MAX_THREADS, (artifact) => this.listVersions(artifact));

		listing.artifacts.forEach((artifact, i) => {
			const artifactResult = found[i];
			if (!artifactResult.complete) result.complete = false;
			for (const [version, repos] of artifactResult.versions) {
				result.files.push({ name: `${artifact}-${version}.lex`, artifact, version, repos });
			}
		});
		return result;
	}

	/** the url of the extension file of a version, in the first of the repos that has it, "" when none can say */
	async getFileUrl(artifact: string, version: string, repos: string[]): Promise<string> {
		for (const repo of repos) {
			const fileName = await this.fileName(artifact, version, repo);
			if (fileName.length) return this.versionUrl(repo, artifact, version) + fileName;
		}
		return "";
	}

	/** the artifacts are the "<name>-extension" folders of the group folder of the repositories (html listings) */
	private async listArtifacts(): Promise<{ artifacts: string[]; complete: boolean }> {
		const repos = this.allRepos();
		const pages = await mapLimit(repos, MAX_THREADS, (repo) => this.get(this.groupUrl(repo)));
		const names = new Set<string>();
		let complete = true;

		pages.forEach((page, i) => {
			if (page.status !== 200) {
				console.log(`Maven repository [${repos[i]}] could not be listed: ${page.status} ${page.error}`);
				complete = false;
				return;
			}
			for (const m of page.content.matchAll(new RegExp(`href="[^"]*${SUFFIX}/?"`, "gi"))) {
				const href = m[0].replace(/^href="|\/?"$/gi, "");
				const name = href.split("/").filter((p) => p.length).pop() ?? "";
				if (name.length > SUFFIX.length) names.add(name);
			}
		});

		const artifacts = [...names].sort((a, b) => {
			const x = a.toLowerCase();
			const y = b.toLowerCase();
			return x < y ? -1 : x > y ? 1 : 0;
		});
		return { artifacts, complete };
	}

	/** the versions of an artifact from the maven-metadata.xml of every repository */
	private async listVersions(artifact: string): Promise<{ versions: Map<string, string[]>; complete: boolean }> {
		const versions = new Map<string, string[]>();
		let complete = true;
		const repos = this.allRepos();
		const pages: HttpResult[] = [];
		for (const repo of repos) pages.push(await this.get(this.artifactUrl(repo, artifact) + "maven-metadata.xml"));

		repos.forEach((repo, i) => {
			const page = pages[i];
			const kind = this.repoKind(repo);
			if (page.status === 404) return; // the repo doesn't have the artifact
			if (page.status !== 200) {
				console.log(`Maven metadata of [${artifact}] in [${repo}] could not be read: ${page.status} ${page.error}`);
				complete = false;
				return;
			}
			let list: string[];
			try {
				list = metadataVersions(page.content.trim());
			} catch (e) {
				console.log(`Maven metadata of [${artifact}] in [${repo}] is not valid: ${(e as Error).message}`);
				complete = false;
				return;
			}
			for (const version of list) {
				if (!version.length || (kind === "releases" && isSnapshot(version)) || (kind === "snapshots" && !isSnapshot(version))) continue;
				const inRepos = versions.get(version) ?? [];
				if (!inRepos.includes(repo)) inRepos.push(repo);
				versions.set(version, inRepos);
			}
		});

		// the repos of a version in order of preference: the repos of its kind first, then the mixed ones
		for (const [version, inRepos] of versions) {
			versions.set(version, this.allRepos(isSnapshot(version)).filter((r) => inRepos.includes(r)));
		}
		return { versions, complete };
	}

	/**
	 * Name of the extension file of a version in a repository. Snapshot files are timestamped on most
	 * repositories, the name is in the maven-metadata.xml of the version. "" when that can't be read.
	 */
	private async fileName(artifact: string, version: string, repo: string): Promise<string> {
		const plain = `${artifact}-${version}.lex`;
		if (!isSnapshot(version)) return plain;

		const metaUrl = this.versionUrl(repo, artifact, version) + "maven-metadata.xml";
		const cached = this.snapshotFiles.get(metaUrl);
		if (cached && Date.now() - cached.time < this.snapshotTtlMs) return cached.file;

		const page = await this.get(metaUrl);
		if (page.status === 404) return plain; // a repository that has no metadata for the version
		if (page.status !== 200) {
			console.log(`Maven snapshot metadata [${metaUrl}] could not be read: ${page.status} ${page.error}`);
			return "";
		}

		let fileName = "";
		try {
			// the extension itself, not a classifier like the -lite file
			const node = snapshotVersions(page.content.trim()).find((n) => n.extension === "lex" && n.classifier === undefined);
			if (node) fileName = `${artifact}-${node.value}.lex`;
		} catch (e) {
			console.log(`Maven snapshot metadata [${metaUrl}] is not valid: ${(e as Error).message}`);
			return "";
		}
		if (!fileName.length) fileName = plain; // metadata without snapshotVersions (older repositories)

		this.snapshotFiles.set(metaUrl, { file: fileName, time: Date.now() });
		return fileName;
	}

	/** all repos, the ones of the kind of version (releases or snapshots) first, the mixed ones last */
	private allRepos(snapshot = false): string[] {
		const first = snapshot ? this.config.snapshotRepos : this.config.releaseRepos;
		const other = snapshot ? this.config.releaseRepos : this.config.snapshotRepos;
		const repos: string[] = [];
		for (const list of [first, other, this.config.mixedRepos]) {
			for (const repo of list) if (!repos.includes(repo)) repos.push(repo);
		}
		return repos;
	}

	private repoKind(repo: string): "releases" | "snapshots" | "mixed" {
		const isRelease = this.config.releaseRepos.includes(repo);
		const isSnap = this.config.snapshotRepos.includes(repo);
		const isMixed = this.config.mixedRepos.includes(repo);
		if (isRelease && !isSnap && !isMixed) return "releases";
		if (isSnap && !isRelease && !isMixed) return "snapshots";
		return "mixed";
	}

	private groupUrl(repo: string): string {
		return repo + GROUP.replace(/\./g, "/") + "/";
	}

	private artifactUrl(repo: string, artifact: string): string {
		return this.groupUrl(repo) + artifact + "/";
	}

	private versionUrl(repo: string, artifact: string, version: string): string {
		return this.artifactUrl(repo, artifact) + version + "/";
	}
}

/**
 * LDEV-6789: the extension files in the Maven layout of the core bucket,
 * <mavenCdnUrl><artifactId>-extension/<version>/<artifactId>-extension-<version>.lex.
 *
 * The CFML version lists the bucket (S3 credentials); over http the bucket can't be listed by prefix, so
 * the artifacts come from the group maven-metadata.xml and the versions from the maven-metadata.xml of
 * each artifact, which the publishing workflows keep up to date (see README).
 */
export async function listBucketMavenFiles(config: Config): Promise<MavenListing> {
	const result: MavenListing = { files: [], complete: true };
	const root = config.mavenCdnUrl;
	if (!root.length) return result;

	const options = { timeoutMs: config.timeoutMs, cacheSeconds: config.metadataCacheSeconds };
	const group = await httpGet(root + "maven-metadata.xml", options);
	let artifacts: string[];
	try {
		if (group.status !== 200) throw new Error(`${group.status} ${group.error}`);
		artifacts = groupArtifacts(group.content.trim()).filter((a) => a.endsWith(SUFFIX));
	} catch (e) {
		console.log(`Error listing the maven layout [${root}]: ${(e as Error).message}`);
		return { files: [], complete: false };
	}
	artifacts = [...new Set(artifacts)].sort();

	const pages = await mapLimit(artifacts, MAX_THREADS, (artifact) => httpGet(`${root}${artifact}/maven-metadata.xml`, options));
	artifacts.forEach((artifact, i) => {
		const page = pages[i];
		if (page.status === 404) return;
		try {
			if (page.status !== 200) throw new Error(`${page.status} ${page.error}`);
			for (const version of metadataVersions(page.content.trim())) {
				if (!version.length) continue;
				const name = `${artifact}-${version}.lex`;
				result.files.push({ name, artifact, version, path: `${artifact}/${version}/${name}` });
			}
		} catch (e) {
			console.log(`Error listing the maven layout for [${artifact}]: ${(e as Error).message}`);
			result.complete = false;
		}
	});
	return result;
}
