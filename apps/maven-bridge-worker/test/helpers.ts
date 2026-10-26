import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { vi } from "vitest";
import type { Env } from "../src/env";
import worker from "../src/index";
import forgebox from "./fixtures/forgebox-info.json";

export const ORIGIN = "https://mvn.lucee-services.com";
export const CDN = "https://cdn.lucee.org/";
export const GITHUB = "https://github.com/lucee/Lucee/releases/download/";

export type Route = (req: Request) => Response | Promise<Response> | undefined;

/** fetch calls seen by the mock, as "METHOD url" */
export let calls: string[] = [];

/**
 * Replaces the global fetch; unmatched requests answer 404 so a test never
 * reaches the network. Routes see the request and may return undefined to pass.
 */
export function mockFetch(routes: Record<string, Route | Response | string>) {
	calls = [];
	return vi.spyOn(globalThis, "fetch").mockImplementation(async (input, init) => {
		const req = new Request(input as RequestInfo, init);
		calls.push(`${req.method} ${req.url}`);
		const route = routes[req.url];
		if (route !== undefined) {
			if (typeof route === "string") {
				// like the CDN / GitHub: a known content-length on GET and HEAD
				const headers = { "content-length": String(new TextEncoder().encode(route).byteLength) };
				return new Response(req.method === "HEAD" ? null : route, { status: 200, headers });
			}
			if (route instanceof Response) return route.clone();
			const res = await route(req);
			if (res) return res;
		}
		return new Response("missing", { status: 404 });
	});
}

export function forgeboxRoute(): Route {
	return () => Response.json(forgebox);
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
	// consume the body first, as the runtime does while waitUntil work (e.g. an R2 fill) runs
	const body = res.body ? await res.arrayBuffer() : null;
	await waitOnExecutionContext(ctx);
	return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
}

/** fresh KV/R2 state and a fresh Cache API generation for every test */
export async function resetState(): Promise<void> {
	const e = env as unknown as Env;
	const keys = await e.BRIDGE_CACHE.list();
	await Promise.all(keys.keys.map((k) => e.BRIDGE_CACHE.delete(k.name)));
	await e.BRIDGE_CACHE.put("cache-generation", crypto.randomUUID());
	const objects = await e.ARTIFACTS!.list();
	await Promise.all(objects.objects.map((o) => e.ARTIFACTS!.delete(o.key)));
}

export const GROUP_METADATA = `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifacts>
    <artifact><artifactId>redis-extension</artifactId><latest>3.0.0.1-SNAPSHOT</latest><release>2.0.0.1</release></artifact>
    <artifact><artifactId>admin-extension</artifactId><latest>1.0.0.0</latest></artifact>
  </artifacts>
</metadata>`;

export const REDIS_METADATA = `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifactId>redis-extension</artifactId>
  <versioning>
    <latest>3.0.0.1-SNAPSHOT</latest>
    <release>2.0.0.1</release>
    <versions>
      <version>2.0.0.1</version>
      <version>3.0.0.1-SNAPSHOT</version>
    </versions>
  </versioning>
</metadata>`;
