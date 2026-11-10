export const USER_AGENT = "lucee-data-provider extension provider worker";

export interface HttpResult {
	status: number;
	error: string;
	content: string;
}

export interface HttpOptions {
	timeoutMs: number;
	/** seconds the answer may be cached at the edge, 0 = not cached */
	cacheSeconds?: number;
	retries?: number;
	retryDelayMs?: number;
}

/** an abort signal after the given time, with a timer that is cleared when done (AbortSignal.timeout() keeps its timer) */
export function withTimeout(ms: number): { signal: AbortSignal; clear: () => void } {
	const controller = new AbortController();
	const timer = setTimeout(() => controller.abort(new Error(`timeout after ${ms} ms`)), ms);
	return { signal: controller.signal, clear: () => clearTimeout(timer) };
}

function isTemporaryFailure(status: number): boolean {
	return status === 0 || status === 429 || status >= 500;
}

function edgeCache(cacheSeconds: number | undefined): RequestInit {
	if (!cacheSeconds) return {};
	return { cf: { cacheTtl: cacheSeconds, cacheEverything: true } } as RequestInit;
}

/**
 * GET as text, redirects followed. A repository answers with a 5xx (or 429) now and then, or the
 * request fails (status 0): those are retried a few times, like _get() of MavenExtensionSource.cfc.
 */
export async function httpGet(url: string, options: HttpOptions): Promise<HttpResult> {
	const retries = options.retries ?? 2;
	const delay = options.retryDelayMs ?? 500;
	let result: HttpResult = { status: 0, error: "", content: "" };

	for (let attempt = 0; attempt <= retries; attempt++) {
		if (attempt > 0 && delay > 0) await new Promise((r) => setTimeout(r, delay * attempt));
		const timeout = withTimeout(options.timeoutMs);
		try {
			const res = await fetch(url, {
				headers: { "user-agent": USER_AGENT },
				redirect: "follow",
				signal: timeout.signal,
				...edgeCache(options.cacheSeconds)
			});
			result = { status: res.status, error: res.ok ? "" : res.statusText, content: await res.text() };
		} catch (e) {
			result = { status: 0, error: e instanceof Error ? e.message : String(e), content: "" };
		} finally {
			timeout.clear();
		}
		if (!isTemporaryFailure(result.status)) break;
	}
	return result;
}

/** maps the items with at most `limit` running at the same time (like ArrayEach( ..., parallel, maxThreads )) */
export async function mapLimit<T, R>(items: T[], limit: number, fn: (item: T, index: number) => Promise<R>): Promise<R[]> {
	const results = new Array<R>(items.length);
	let next = 0;
	const workers = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
		while (next < items.length) {
			const index = next++;
			results[index] = await fn(items[index], index);
		}
	});
	await Promise.all(workers);
	return results;
}
