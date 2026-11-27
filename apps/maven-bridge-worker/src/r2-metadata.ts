// List Maven artifacts and versions from the R2 bucket the worker serves.
// Release/RC/BETA/ALPHA objects live under <R2_PREFIX>org/lucee/<artifact>/<version>/.
// SNAPSHOT objects live under <R2_PREFIX><R2_SNAPSHOT_PREFIX>org/lucee/<artifact>/<version>/.
// Both locations are listed and the results are unioned.
import type { BridgeConfig } from "./config";
import type { DirectoryEntry } from "./metadata-generate";

export interface R2ListRoots {
	r2Prefix: string;
	r2SnapshotPrefix: string;
}

export function listRootsFromConfig(config: Pick<BridgeConfig, "r2Prefix" | "r2SnapshotPrefix">): R2ListRoots {
	return { r2Prefix: config.r2Prefix, r2SnapshotPrefix: config.r2SnapshotPrefix };
}

function dir(prefix: string): string {
	if (!prefix) return "";
	return prefix.endsWith("/") ? prefix : prefix + "/";
}

/** Maven-layout prefixes to list: the release tree and the SNAPSHOT tree. */
export function mavenLayoutPrefixes(groupPath: string, roots: R2ListRoots): string[] {
	const group = groupPath.replace(/^\/+|\/+$/g, "") + "/";
	const base = dir(roots.r2Prefix);
	const snap = dir(roots.r2SnapshotPrefix);
	const prefixes = [`${base}${group}`];
	if (snap) prefixes.push(`${base}${snap}${group}`);
	return [...new Set(prefixes)];
}

async function listAllPrefixes(bucket: R2Bucket, prefix: string): Promise<string[]> {
	const out: string[] = [];
	let cursor: string | undefined;
	do {
		const page = await bucket.list({ prefix, delimiter: "/", cursor, limit: 1000 });
		for (const entry of page.delimitedPrefixes ?? []) out.push(entry);
		cursor = page.truncated ? page.cursor : undefined;
	} while (cursor);
	return out;
}

function childName(prefix: string, full: string): string {
	const rest = full.slice(prefix.length).replace(/\/+$/, "");
	return rest.includes("/") ? "" : rest;
}

export async function listArtifactIds(bucket: R2Bucket, groupPath: string, roots: R2ListRoots): Promise<string[]> {
	const names = new Set<string>();
	for (const prefix of mavenLayoutPrefixes(groupPath, roots)) {
		for (const entry of await listAllPrefixes(bucket, prefix)) {
			const name = childName(prefix, entry);
			if (name) names.add(name);
		}
	}
	return [...names].sort((a, b) => a.localeCompare(b));
}

export async function listArtifactVersions(
	bucket: R2Bucket,
	groupPath: string,
	artifactId: string,
	roots: R2ListRoots
): Promise<string[]> {
	const versions = new Set<string>();
	for (const root of mavenLayoutPrefixes(groupPath, roots)) {
		const artifactPrefix = `${root}${artifactId}/`;
		for (const entry of await listAllPrefixes(bucket, artifactPrefix)) {
			const version = childName(artifactPrefix, entry);
			if (version) versions.add(version);
		}
	}
	return [...versions];
}

export async function listDirectoryEntries(
	bucket: R2Bucket,
	groupPath: string,
	roots: R2ListRoots
): Promise<DirectoryEntry[]> {
	return (await listArtifactIds(bucket, groupPath, roots)).map((name) => ({ name }));
}

/**
 * Parse an R2 object key into a Maven artifact the metadata generator cares about.
 * Metadata files and objects outside the group layout are ignored (so a notification
 * about a generated file, if one were ever stored, cannot retrigger itself).
 */
export function artifactFromR2Key(
	key: string,
	groupPath: string,
	roots: R2ListRoots
): { artifactId: string } | undefined {
	let rest = key.replace(/^\/+/, "");
	const base = dir(roots.r2Prefix);
	if (base) {
		if (!rest.startsWith(base)) return undefined;
		rest = rest.slice(base.length);
	}
	const snap = dir(roots.r2SnapshotPrefix);
	if (snap && rest.startsWith(snap)) rest = rest.slice(snap.length);
	const group = groupPath.replace(/^\/+|\/+$/g, "") + "/";
	if (!rest.startsWith(group)) return undefined;
	rest = rest.slice(group.length);
	const parts = rest.split("/").filter((p) => p.length);
	if (parts.length < 2) return undefined;
	const fileName = parts[parts.length - 1].toLowerCase();
	if (fileName.startsWith("maven-metadata") || fileName === "index.html") return undefined;
	return { artifactId: parts[0] };
}

export function eventObjectKeys(body: unknown): string[] {
	const keys: string[] = [];
	const take = (value: unknown) => {
		if (!value || typeof value !== "object") return;
		const record = value as Record<string, unknown>;
		const object = record.object && typeof record.object === "object" ? (record.object as Record<string, unknown>) : record;
		const key = object.key ?? record.key ?? record.objectKey;
		if (typeof key === "string" && key.length) keys.push(key);
	};
	if (Array.isArray(body)) {
		for (const item of body) take(item);
	} else {
		take(body);
		if (body && typeof body === "object" && Array.isArray((body as { events?: unknown[] }).events)) {
			for (const item of (body as { events: unknown[] }).events) take(item);
		}
	}
	return keys;
}
