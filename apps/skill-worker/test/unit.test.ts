import { describe, expect, it } from "vitest";
import { readConfig } from "../src/config";
import { parseManifest } from "../src/manifest";
import type { Env } from "../src/env";
import { encodeForUrl, formatBytes, formatDate, humanizeSlug, parseFrontmatter, skillInfo } from "../src/landing";
import { SKILL, SOURCE, SOURCE_LAST_MODIFIED } from "./helpers";

const env = (vars: Partial<Record<keyof Env, string>>) => ({ SKILL_SOURCE_URL: SOURCE, ...vars }) as unknown as Env;

describe("readConfig", () => {
	it("defaults to main.skill from SKILL_SOURCE_URL", () => {
		const c = readConfig(env({}));
		expect(c.skills).toEqual([{ file: "main.skill", source: SOURCE }]);
		expect(c.refreshMinutes).toBe(60);
		expect(c.timeoutSeconds).toBe(60);
	});

	it("resolves further files relative to the source and honours explicit urls", () => {
		const c = readConfig(env({ SKILLS: "main.skill, extensions.skill, other.skill|https://example.org/x.skill" }));
		expect(c.skills).toEqual([
			{ file: "main.skill", source: SOURCE },
			{ file: "extensions.skill", source: "https://docs.lucee.org/extensions.skill" },
			{ file: "other.skill", source: "https://example.org/x.skill" }
		]);
	});

	it("rejects bad names, duplicates and bad numbers", () => {
		expect(() => readConfig(env({ SKILLS: "../etc.skill" }))).toThrow(/Invalid skill file name/);
		expect(() => readConfig(env({ SKILLS: "main.txt" }))).toThrow(/Invalid skill file name/);
		expect(() => readConfig(env({ SKILLS: "a.skill,a.skill" }))).toThrow(/listed twice/);
		expect(() => readConfig(env({ REFRESH_MINUTES: "0" }))).toThrow(/REFRESH_MINUTES/);
		expect(() => readConfig(env({ TIMEOUT: "abc" }))).toThrow(/TIMEOUT/);
		expect(() => readConfig(env({ SKILL_SOURCE_URL: "" }))).toThrow(/SKILL_SOURCE_URL/);
	});
});

describe("landing helpers (index.cfm)", () => {
	it("parses folded descriptions", () => {
		expect(parseFrontmatter(SKILL, "main")).toEqual({
			name: "lucee-docs",
			description: "Lucee CFML documentation index. Use it for recipes, guides and technical specs."
		});
	});

	it("parses inline descriptions and falls back without frontmatter", () => {
		expect(parseFrontmatter("---\r\nname: x\r\ndescription: short one\r\n---\r\nbody", "f")).toEqual({
			name: "x",
			description: "short one"
		});
		expect(parseFrontmatter("no frontmatter", "main")).toEqual({ name: "main", description: "" });
	});

	it("stops the description at the next key", () => {
		const s = "---\nname: a\ndescription: |\n  line one\n  line two\nversion: 1\n  not part\n---\n";
		expect(parseFrontmatter(s, "f").description).toBe("line one line two");
	});

	it("formats like index.cfm", () => {
		expect(humanizeSlug("lucee-docs_main")).toBe("Lucee Docs Main");
		expect(formatBytes(512)).toBe("512 B");
		expect(formatBytes(51_700)).toBe("50 KB");
		expect(formatBytes(1024 * 1024 * 1.25)).toBe("1.3 MB");
		expect(formatDate(new Date(SOURCE_LAST_MODIFIED))).toBe("Oct 23, 2026");
		expect(encodeForUrl("a b*.skill~")).toBe("a+b*.skill%7E");
	});

	it("uses the fetch time when the source sent no Last-Modified", () => {
		const fetchedAt = Date.UTC(2026, 0, 5, 12);
		const info = skillInfo("main.skill", {
			body: SKILL,
			etag: '"x"',
			lastModified: "",
			sourceEtag: "",
			fetchedAt,
			source: SOURCE
		});
		expect(info.updated.getTime()).toBe(fetchedAt);
		expect(info.size).toBe(new TextEncoder().encode(SKILL).byteLength);
		expect(info.sourceHost).toBe("docs.lucee.org");
		expect(info.displayName).toBe("Lucee Docs");
	});
});

describe("readConfig manifest", () => {
	it("defaults to skills.json next to the source and can be disabled", () => {
		expect(readConfig(env({})).manifestUrl).toBe("https://docs.lucee.org/skill/skills.json");
		expect(readConfig(env({ SKILL_MANIFEST_URL: "" })).manifestUrl).toBeNull();
		expect(readConfig(env({ SKILL_MANIFEST_URL: "https://example.org/s.json" })).manifestUrl).toBe("https://example.org/s.json");
	});
});

describe("parseManifest", () => {
	const URL_ = "https://docs.lucee.org/skill/skills.json";
	const sha = "a".repeat(64);
	const doc = (topics: unknown[], extra: object = {}) => JSON.stringify({ name: "lucee", topics, ...extra });

	it("reads topics, resolves relative paths and the router", () => {
		const m = parseManifest(
			doc([{ id: "ai", title: "AI", description: "d", path: "skill/ai.md", entries: 9, sha256: sha.toUpperCase(), approxTokens: 626 }], {
				router: { url: "https://docs.lucee.org/lucee.skill", sha256: sha, approxTokens: 924 }
			}),
			URL_
		);
		expect(m.topics).toEqual([
			{ id: "ai", title: "AI", description: "d", url: "https://docs.lucee.org/skill/skill/ai.md", entries: 9, sha256: sha, approxTokens: 626 }
		]);
		expect(m.router).toEqual({ url: "https://docs.lucee.org/lucee.skill", sha256: sha, approxTokens: 924 });
	});

	it("rejects anything unexpected", () => {
		expect(() => parseManifest("nope", URL_)).toThrow(/not valid JSON/);
		expect(() => parseManifest("{}", URL_)).toThrow(/no topics array/);
		expect(() => parseManifest(doc([{ id: "../x", url: "/x.md" }]), URL_)).toThrow(/invalid topic id/);
		expect(() => parseManifest(doc([{ id: "a", url: "/a.md" }, { id: "a", url: "/b.md" }]), URL_)).toThrow(/listed twice/);
		expect(() => parseManifest(doc([{ id: "a" }]), URL_)).toThrow(/has no url/);
		expect(() => parseManifest(doc([{ id: "a", url: "https://example.org/a.md" }]), URL_)).toThrow(/is not on https:\/\/docs\.lucee\.org/);
		expect(() => parseManifest(doc([{ id: "a", url: "/a.md", sha256: "xyz" }]), URL_)).toThrow(/not a SHA-256/);
	});
});
