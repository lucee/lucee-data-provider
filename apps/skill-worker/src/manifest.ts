// skills.json from docs.lucee.org (LDEV-6552): the router plus one index file per topic.
// The manifest drives which topic files are mirrored, so a new topic needs no code change.
import type { SkillDef } from "./config";

export interface ManifestTopic {
	id: string;
	title: string;
	description: string;
	/** where the topic file is mirrored from */
	url: string;
	entries: number;
	/** SHA-256 (hex) of the topic file, empty when the manifest gives none */
	sha256: string;
	approxTokens: number;
}

export interface Manifest {
	name: string;
	router: { url: string; sha256: string; approxTokens: number } | null;
	topics: ManifestTopic[];
}

/** the manifest is served as /skills.json and stored under this name */
export const MANIFEST_FILE = "skills.json";

const TOPIC_ID = /^[a-z0-9][a-z0-9-]*$/;
const SHA256 = /^[0-9a-f]{64}$/;

/** KV name and path (without the leading slash) of a topic file */
export function topicFile(id: string): string {
	return `skill/${id}.md`;
}

function str(value: unknown): string {
	return typeof value === "string" ? value.trim() : "";
}

function count(value: unknown): number {
	return typeof value === "number" && Number.isFinite(value) && value >= 0 ? Math.round(value) : 0;
}

function sha(value: unknown, what: string): string {
	const s = str(value).toLowerCase();
	if (s && !SHA256.test(s)) throw new Error(`${what}: sha256 is not a SHA-256 hex digest`);
	return s;
}

/**
 * Parses and checks skills.json. Topic files must come from the same origin as the manifest
 * (so the mirror cannot be pointed anywhere else). Throws on anything unexpected, so a broken
 * manifest never replaces the last good copy.
 */
export function parseManifest(body: string, manifestUrl: string): Manifest {
	let data: unknown;
	try {
		data = JSON.parse(body);
	} catch {
		throw new Error(`${MANIFEST_FILE} is not valid JSON`);
	}
	if (!data || typeof data !== "object" || !Array.isArray((data as { topics?: unknown }).topics)) {
		throw new Error(`${MANIFEST_FILE} has no topics array`);
	}
	const raw = data as { name?: unknown; router?: unknown; topics: unknown[] };
	const base = new URL(manifestUrl);

	const topics: ManifestTopic[] = [];
	for (const item of raw.topics) {
		const t = (item ?? {}) as Record<string, unknown>;
		const id = str(t.id);
		if (!TOPIC_ID.test(id)) throw new Error(`${MANIFEST_FILE}: invalid topic id "${id}"`);
		if (topics.some((x) => x.id === id)) throw new Error(`${MANIFEST_FILE}: topic "${id}" is listed twice`);
		const href = str(t.url) || str(t.path);
		if (!href) throw new Error(`${MANIFEST_FILE}: topic "${id}" has no url`);
		const url = new URL(href, base);
		if (url.origin !== base.origin) throw new Error(`${MANIFEST_FILE}: topic "${id}" is not on ${base.origin}`);
		topics.push({
			id,
			title: str(t.title) || id,
			description: str(t.description),
			url: url.toString(),
			entries: count(t.entries),
			sha256: sha(t.sha256, `topic "${id}"`),
			approxTokens: count(t.approxTokens)
		});
	}

	let router: Manifest["router"] = null;
	if (raw.router && typeof raw.router === "object") {
		const r = raw.router as Record<string, unknown>;
		const href = str(r.url);
		if (href) router = { url: new URL(href, base).toString(), sha256: sha(r.sha256, "router"), approxTokens: count(r.approxTokens) };
	}

	return { name: str(raw.name), router, topics };
}

export function manifestDef(manifestUrl: string): SkillDef {
	return { file: MANIFEST_FILE, source: manifestUrl };
}

export function topicDef(topic: ManifestTopic): SkillDef {
	return { file: topicFile(topic.id), source: topic.url, sha256: topic.sha256 || undefined };
}

/** the skills in SKILLS that are the manifest's router get its checksum */
export function withRouterChecksum(skills: SkillDef[], manifest: Manifest | null): SkillDef[] {
	const router = manifest?.router;
	if (!router?.sha256) return skills;
	return skills.map((s) => (s.source === router.url ? { ...s, sha256: router.sha256 } : s));
}
