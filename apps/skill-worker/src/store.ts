// Mirror of the skill files in KV (replaces the /downloads volume of apps/skill).
import type { SkillDef } from "./config";

export interface CachedSkill {
	body: string;
	/** our ETag for the body (strong, SHA-256 based) */
	etag: string;
	/** Last-Modified of the source (HTTP date), empty when the source sent none */
	lastModified: string;
	/** ETag of the source, used for the conditional GET */
	sourceEtag: string;
	/** when the source was last checked successfully (epoch ms) */
	fetchedAt: number;
	/** where the copy came from */
	source: string;
}

export type RefreshResult =
	| { file: string; ok: true; status: "updated" | "unchanged" }
	| { file: string; ok: false; error: string };

export const USER_AGENT = "lucee-skill-worker";

export function cacheKey(file: string): string {
	return `skill:${file}`;
}

async function sha256Hex(text: string): Promise<string> {
	const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
	return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export class SkillStore {
	/** refreshes running in this isolate, so concurrent requests share one fetch */
	private static running = new Map<string, Promise<CachedSkill>>();

	constructor(
		private readonly kv: KVNamespace,
		private readonly timeoutSeconds: number
	) {}

	get(file: string): Promise<CachedSkill | null> {
		return this.kv.get<CachedSkill>(cacheKey(file), "json");
	}

	/** cached copy, or a fresh one from the source when nothing is cached yet; throws when neither works */
	async getOrFetch(skill: SkillDef): Promise<CachedSkill> {
		const cached = await this.get(skill.file);
		if (cached) return cached;
		return this.refresh(skill);
	}

	/**
	 * Checks the source (conditional GET when a copy exists) and stores the result.
	 * Throws when the source fails; the cached copy is left untouched in that case.
	 */
	refresh(skill: SkillDef): Promise<CachedSkill> {
		const key = cacheKey(skill.file);
		let p = SkillStore.running.get(key);
		if (!p) {
			p = this.doRefresh(skill).finally(() => SkillStore.running.delete(key));
			SkillStore.running.set(key, p);
		}
		return p;
	}

	private async doRefresh(skill: SkillDef): Promise<CachedSkill> {
		const cached = await this.get(skill.file);
		const headers: Record<string, string> = { "user-agent": USER_AGENT };
		// only revalidate a copy of the same source (SKILLS may have changed)
		if (cached && cached.source === skill.source) {
			if (cached.sourceEtag) headers["if-none-match"] = cached.sourceEtag;
			if (cached.lastModified) headers["if-modified-since"] = cached.lastModified;
		}

		const res = await fetch(skill.source, {
			headers,
			signal: AbortSignal.timeout(this.timeoutSeconds * 1000)
		});

		if (res.status === 304 && cached && cached.source === skill.source) {
			await res.body?.cancel();
			const next = { ...cached, fetchedAt: Date.now() };
			await this.kv.put(cacheKey(skill.file), JSON.stringify(next));
			return next;
		}
		if (res.status !== 200) {
			await res.body?.cancel();
			throw new Error(`${skill.source} answered ${res.status}`);
		}
		const body = await res.text();
		if (!body.trim()) throw new Error(`${skill.source} answered with an empty body`);

		const next: CachedSkill = {
			body,
			etag: `"${(await sha256Hex(body)).slice(0, 32)}"`,
			lastModified: res.headers.get("last-modified") ?? "",
			sourceEtag: res.headers.get("etag") ?? "",
			fetchedAt: Date.now(),
			source: skill.source
		};
		await this.kv.put(cacheKey(skill.file), JSON.stringify(next));
		return next;
	}

	/** refreshes every skill; one failing source does not stop the others */
	async refreshAll(skills: SkillDef[]): Promise<RefreshResult[]> {
		return Promise.all(
			skills.map(async (skill): Promise<RefreshResult> => {
				const before = await this.get(skill.file);
				try {
					const after = await this.refresh(skill);
					const unchanged = before !== null && before.etag === after.etag;
					return { file: skill.file, ok: true, status: unchanged ? "unchanged" : "updated" };
				} catch (e) {
					return { file: skill.file, ok: false, error: e instanceof Error ? e.message : String(e) };
				}
			})
		);
	}
}
