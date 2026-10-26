#!/usr/bin/env node
// Idempotently creates the KV namespace and the R2 bucket used by wrangler.toml
// and writes the KV namespace id into wrangler.toml (CI only, not committed).
//
// env: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID
// optional: KV_TITLE (default "lucee-maven-bridge-cache"), R2_BUCKET (default: bucket_name in wrangler.toml)
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

const kvTitle = process.env.KV_TITLE || "lucee-maven-bridge-cache";
const bucket = process.env.R2_BUCKET || /bucket_name\s*=\s*"([^"]+)"/.exec(toml)?.[1];
if (!bucket) throw new Error("No R2 bucket name found in wrangler.toml");

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

// --- R2 bucket ---
const info = await api("GET", `/r2/buckets/${encodeURIComponent(bucket)}`);
if (info.ok) {
	console.log(`R2 bucket "${bucket}" exists`);
} else if (info.status === 404) {
	const r = await api("POST", "/r2/buckets", { name: bucket });
	if (!r.ok) fail(`Creating R2 bucket "${bucket}"`, r);
	console.log(`R2 bucket "${bucket}" created`);
} else {
	fail(`Reading R2 bucket "${bucket}"`, info);
}

// --- wrangler.toml ---
const block = /(\[\[kv_namespaces\]\]\s*\nbinding\s*=\s*"BRIDGE_CACHE"\s*\n)(id\s*=\s*"[^"]*"\s*\n)?/;
if (!block.test(toml)) throw new Error('No [[kv_namespaces]] block for "BRIDGE_CACHE" in wrangler.toml');
toml = toml.replace(block, (_, head) => `${head}id = "${kvId}"\n`);
await writeFile(tomlPath, toml);
console.log("wrangler.toml: BRIDGE_CACHE id set");
