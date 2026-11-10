// Compatibility with the CFML provider: the answers recorded from https://extension.lucee.org (see
// scripts/record-fixtures.mjs) for a few extensions, compared with what the worker answers when it reads
// the sources recorded at the same time.
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import fixtures from "./fixtures/compat.json";
import { BASE, call, mockFetch, resetState, type Route } from "./helpers";

interface Recorded {
	path: string;
	status: number;
	location: string | null;
	contentType: string | null;
	body: string;
}

const routes = (): Record<string, Route> => {
	const r: Record<string, Route> = {
		"https://ext.lucee.org/extensions.json": JSON.stringify(fixtures.meta),
		"https://ext.lucee.org/extensions-maven.json": JSON.stringify(fixtures.state)
	};
	for (const [url, res] of Object.entries(fixtures.upstream as Record<string, { status: number; body: string }>)) {
		r[url] = res.status === 200 ? res.body : new Response("", { status: res.status });
	}
	return r;
};

// the recorded extension meta is the complete one for these extensions, nothing to discover
const settings = { EXTENSIONS_DISCOVERY_MAX: "0" };

beforeEach(async () => {
	await resetState();
	mockFetch(routes());
});
afterEach(() => {
	vi.restoreAllMocks();
});

describe(`answers like the CFML provider (recorded ${fixtures.recordedAt})`, () => {
	it.each((fixtures.responses as Recorded[]).map((r) => [r.path, r] as const))("%s", async (path, recorded) => {
		const res = await call(BASE + path, {}, settings);
		expect(res.status).toBe(recorded.status);
		expect(res.headers.get("location")).toBe(recorded.location);
		if (recorded.status === 200) expect(res.headers.get("content-type")).toBe(recorded.contentType);
		const body = await res.text();
		if (recorded.status === 200) expect(JSON.parse(body)).toEqual(JSON.parse(recorded.body));
		else expect(body).toBe(recorded.body);
		// byte for byte, as Lucee core and the admin read it
		expect(body).toBe(recorded.body);
	});
});
