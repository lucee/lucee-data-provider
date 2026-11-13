import type { Env } from "./env";

export interface SkillDef {
	/** file name served as /<file>, e.g. "main.skill" */
	file: string;
	/** where the file is mirrored from */
	source: string;
	/** expected SHA-256 (hex) of the body, from skills.json; a copy that does not match is not stored */
	sha256?: string;
}

export interface Config {
	skills: SkillDef[];
	/** skills.json listing the topic files mirrored under /skill/, null when disabled */
	manifestUrl: string | null;
	refreshMinutes: number;
	timeoutSeconds: number;
}

const FILE_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]*\.skill$/;

function positiveNumber(name: string, value: string | undefined, fallback: number): number {
	if (value === undefined || value.trim() === "") return fallback;
	const n = Number(value);
	if (!Number.isFinite(n) || n <= 0) throw new Error(`${name} must be a positive number, got "${value}"`);
	return n;
}

export function readConfig(env: Env): Config {
	const sourceUrl = (env.SKILL_SOURCE_URL ?? "").trim();
	if (!sourceUrl) throw new Error("SKILL_SOURCE_URL is not set");
	// validates the url
	new URL(sourceUrl);

	const entries = (env.SKILLS ?? "main.skill")
		.split(",")
		.map((s) => s.trim())
		.filter(Boolean);
	if (!entries.length) throw new Error("SKILLS is empty");

	let defaultUsed = false;
	const skills: SkillDef[] = [];
	for (const entry of entries) {
		const sep = entry.indexOf("|");
		const file = (sep >= 0 ? entry.slice(0, sep) : entry).trim();
		let source = sep >= 0 ? entry.slice(sep + 1).trim() : "";
		if (!FILE_NAME.test(file)) throw new Error(`Invalid skill file name "${file}" in SKILLS`);
		if (skills.some((s) => s.file === file)) throw new Error(`Skill file "${file}" is listed twice in SKILLS`);
		if (!source) {
			source = defaultUsed ? new URL(file, sourceUrl).toString() : sourceUrl;
			defaultUsed = true;
		}
		skills.push({ file, source: new URL(source).toString() });
	}

	// unset: the manifest next to the default source; empty: no topic files
	const manifestSetting = env.SKILL_MANIFEST_URL === undefined ? new URL("skill/skills.json", sourceUrl).toString() : env.SKILL_MANIFEST_URL.trim();
	const manifestUrl = manifestSetting ? new URL(manifestSetting).toString() : null;

	return {
		skills,
		manifestUrl,
		refreshMinutes: positiveNumber("REFRESH_MINUTES", env.REFRESH_MINUTES, 60),
		timeoutSeconds: positiveNumber("TIMEOUT", env.TIMEOUT, 60)
	};
}
