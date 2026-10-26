#!/usr/bin/env node
// Idempotently creates the KV namespace used by wrangler.toml
// and writes its id into wrangler.toml (CI only, not committed).
//
// env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
// optional: KV_TITLE (default "lucee-skill-cache")
import { readFile, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const token = process.env.CLOUDFLARE_API_TOKEN;
const account = process.env.CLOUDFLARE_ACCOUNT_ID;
if (!token || !account) {
	console.error("CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID are required");
	process.exit(1);
}

const tomlPath = fileURLToPath(new URL("../wrangler.toml", import.meta.url));
let toml = await readFile(tomlPath, "utf8");

const kvTitle = process.env.KV_TITLE || "lucee-skill-cache";
const base = `https://api.cloudflare.com/client/v4/accounts/${account}`;

async function api(method, path, body) {
	const res = await fetch(base + path, {
		method,
		headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
		body: body === undefined ? undefined : JSON.stringify(body),
		signal: AbortSignal.timeout(30_000)
	});
	const json = await res.json().catch(() => ({}));
	return { status: res.status, ok: res.ok && json.success !== false, json };
}

function fail(what, r) {
	const errors = (r.json.errors ?? []).map((e) => `${e.code}: ${e.message}`).join("; ");
	throw new Error(`${what} failed with HTTP ${r.status} ${errors}`);
}

// --- KV namespace ---
let kvId = "";
for (let page = 1; !kvId; page++) {
	const r = await api("GET", `/storage/kv/namespaces?per_page=100&page=${page}`);
	if (!r.ok) fail("Listing KV namespaces", r);
	const hit = r.json.result.find((ns) => ns.title === kvTitle);
	if (hit) kvId = hit.id;
	if (r.json.result.length < 100) break;
}
if (kvId) {
	console.log(`KV namespace "${kvTitle}" exists (${kvId})`);
} else {
	const r = await api("POST", "/storage/kv/namespaces", { title: kvTitle });
	if (!r.ok) fail(`Creating KV namespace "${kvTitle}"`, r);
	kvId = r.json.result.id;
	console.log(`KV namespace "${kvTitle}" created (${kvId})`);
}

// --- wrangler.toml ---
const block = /(\[\[kv_namespaces\]\]\s*\nbinding\s*=\s*"SKILL_CACHE"\s*\n)(id\s*=\s*"[^"]*"\s*\n)?/;
if (!block.test(toml)) throw new Error('No [[kv_namespaces]] block for "SKILL_CACHE" in wrangler.toml');
toml = toml.replace(block, (_, head) => `${head}id = "${kvId}"\n`);
await writeFile(tomlPath, toml);
console.log("wrangler.toml: SKILL_CACHE id set");
