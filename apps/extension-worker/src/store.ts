// Where the index lives: KV (EXT_CACHE) when there is one, shared by every isolate and filled by the cron,
// and a copy in the memory of the isolate. Without KV the index is built by the isolate itself.
import { buildIndex, emptyState, type BuildState } from "./builder";
import type { Config } from "./config";
import type { Env } from "./env";
import type { ExtensionIndex, Logos } from "./types";

const KEY_INDEX = "index";
const KEY_LOGOS = "logos";
const KEY_STATE = "state";
const KEY_LOCK = "build-lock";
/** how long the isolate keeps the index before it looks at KV again */
const MEMORY_MS = 60_000;

interface Memory {
	index?: ExtensionIndex;
	checkedAt: number;
	logos?: { builtAt: number; logos: Logos };
	state?: BuildState;
	building?: Promise<ExtensionIndex>;
}

// one per isolate
const memory: Memory = { checkedAt: 0 };

/** for the tests */
export function resetMemory(): void {
	memory.index = undefined;
	memory.logos = undefined;
	memory.state = undefined;
	memory.building = undefined;
	memory.checkedAt = 0;
}

async function readState(env: Env): Promise<BuildState> {
	if (!env.EXT_CACHE) return memory.state ?? emptyState();
	const state = await env.EXT_CACHE.get<BuildState>(KEY_STATE, "json");
	return { ...emptyState(), ...(state ?? {}) };
}

/** builds the index and stores it (KV and memory) */
export async function rebuild(env: Env, config: Config): Promise<ExtensionIndex> {
	if (memory.building) return memory.building;
	memory.building = (async () => {
		try {
			const previous = memory.index ?? (env.EXT_CACHE ? (await env.EXT_CACHE.get<ExtensionIndex>(KEY_INDEX, "json")) ?? undefined : undefined);
			const result = await buildIndex(config, await readState(env), previous);
			if (env.EXT_CACHE) {
				// the logos first, so an index is never served without the logos of its build
				await env.EXT_CACHE.put(KEY_LOGOS, JSON.stringify({ builtAt: result.index.builtAt, logos: result.logos }));
				if (result.stateChanged) await env.EXT_CACHE.put(KEY_STATE, JSON.stringify(result.state));
				await env.EXT_CACHE.put(KEY_INDEX, JSON.stringify(result.index));
			} else {
				memory.state = result.state;
			}
			memory.index = result.index;
			memory.logos = { builtAt: result.index.builtAt, logos: result.logos };
			memory.checkedAt = Date.now();
			console.log(`Extension index built: ${JSON.stringify(result.index.stats)}`);
			return result.index;
		} finally {
			memory.building = undefined;
		}
	})();
	return memory.building;
}

/** a rebuild in the background, at most one at a time over all isolates (a KV lock of a minute) */
async function rebuildInBackground(env: Env, config: Config): Promise<void> {
	try {
		if (env.EXT_CACHE) {
			if (await env.EXT_CACHE.get(KEY_LOCK)) return;
			await env.EXT_CACHE.put(KEY_LOCK, String(Date.now()), { expirationTtl: 60 });
		}
		await rebuild(env, config);
	} catch (e) {
		console.log(`Background build of the extension index failed: ${(e as Error).message}`);
	}
}

/**
 * The current index: from memory, else from KV, else built now. An index older than INDEX_TTL_MINUTES is
 * served and rebuilt in the background.
 */
export async function getIndex(env: Env, config: Config, waitUntil: (p: Promise<unknown>) => void): Promise<ExtensionIndex> {
	const now = Date.now();
	if (memory.index && now - memory.checkedAt < MEMORY_MS) return memory.index;

	if (env.EXT_CACHE) {
		const stored = await env.EXT_CACHE.get<ExtensionIndex>(KEY_INDEX, "json");
		if (stored) {
			if (!memory.index || memory.index.builtAt !== stored.builtAt) memory.index = stored;
			memory.checkedAt = now;
		}
	}
	if (!memory.index) return rebuild(env, config);

	memory.checkedAt = now;
	if (now - memory.index.builtAt > config.indexTtlMs) waitUntil(rebuildInBackground(env, config));
	return memory.index;
}

/** the logos of the given index (only read when an answer has them, withLogo) */
export async function getLogos(env: Env, index: ExtensionIndex): Promise<Logos> {
	if (memory.logos && memory.logos.builtAt === index.builtAt) return memory.logos.logos;
	if (env.EXT_CACHE) {
		const stored = await env.EXT_CACHE.get<{ builtAt: number; logos: Logos }>(KEY_LOGOS, "json");
		if (stored) {
			memory.logos = stored;
			return stored.logos;
		}
	}
	return memory.logos?.logos ?? {};
}
