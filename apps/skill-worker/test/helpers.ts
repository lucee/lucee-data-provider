import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { vi } from "vitest";
import type { Env } from "../src/env";
import worker from "../src/index";

export const ORIGIN = "https://skl.lucee-services.com";
export const SOURCE = "https://docs.lucee.org/lucee.skill";
export const SOURCE_LAST_MODIFIED = "Fri, 23 Oct 2026 22:53:01 GMT";
export const SOURCE_ETAG = '"src-1"';

export const SKILL = `---
name: lucee-docs
description: >
  Lucee CFML documentation index. Use it for
  recipes, guides   and technical specs.
---

# Lucee docs

Some content.
`;

export type Route = (req: Request) => Response | Promise<Response> | undefined;

/** fetch calls seen by the mock, as "METHOD url" */
export let calls: Request[] = [];

/**
 * Replaces the global fetch; unmatched requests answer 404 so a test never
 * reaches the network.
 */
export function mockFetch(routes: Record<string, Route | Response>) {
	calls = [];
	return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
		const req = new Request(input as RequestInfo, init);
		calls.push(req);
		const route = routes[req.url];
		if (route !== undefined) {
			if (route instanceof Response) return route.clone();
			const res = await route(req);
			if (res) return res;
		}
		return new Response("missing", { status: 404 });
	});
}

/** the source as docs.lucee.org answers it, honouring If-None-Match */
export function sourceRoute(body = SKILL, etag = SOURCE_ETAG, lastModified = SOURCE_LAST_MODIFIED): Route {
	return (req) => {
		const headers = { etag, "last-modified": lastModified, "content-type": "text/plain" };
		if (req.headers.get("if-none-match") === etag) return new Response(null, { status: 304, headers });
		return new Response(body, { status: 200, headers });
	};
}

export function testEnv(overrides: Partial<Record<keyof Env, string>> = {}): Env {
	return { ...(env as unknown as Env), ...overrides } as Env;
}

export async function call(
	path: string,
	init: RequestInit = {},
	overrides: Partial<Record<keyof Env, string>> = {}
): Promise<Response> {
	const ctx = createExecutionContext();
	const res = await worker.fetch(new Request(ORIGIN + path, init) as never, testEnv(overrides), ctx);
	const body = res.body ? await res.arrayBuffer() : null;
	await waitOnExecutionContext(ctx);
	return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}

export async function resetState(): Promise<void> {
	const e = env as unknown as Env;
	const keys = await e.SKILL_CACHE.list();
	await Promise.all(keys.keys.map((k) => e.SKILL_CACHE.delete(k.name)));
}

export function kv(): KVNamespace {
	return (env as unknown as Env).SKILL_CACHE;
}
