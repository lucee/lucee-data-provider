#!/usr/bin/env node
// One-off copy of the Maven layout in the S3 bucket lucee-downloads (prefix org/lucee/)
// into the Cloudflare R2 bucket the Maven bridge worker serves from.
//
//   - idempotent: an object already in R2 with the same size (and ETag, when both are
//     a plain MD5) is skipped
//   - maven-metadata.xml* and index.html are not copied (the worker generates those)
//   - SNAPSHOT version folders are written under R2_SNAPSHOT_PREFIX (default snapshots/)
//   - --dry-run lists what would be copied or skipped, and writes nothing
//
// This script is not run by CI. Run it by hand after a dry run, with credentials in the
// environment (never on the command line):
//
//   S3 credentials (either pair works):
//     AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
//     or INPUT_S3_ACCESS_KEY / INPUT_S3_SECRET_KEY
//   S3_BUCKET          default lucee-downloads
//   S3_REGION          default us-east-1
//   S3_PREFIX          default org/lucee/
//   R2_ENDPOINT        required (Cloudflare R2 S3 API endpoint)
//   R2_BUCKET          required
//   R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
//   R2_PREFIX          optional
//   R2_SNAPSHOT_PREFIX default snapshots/
//   COPY_CONCURRENCY   default 32 (planning HEADs and copies)
//   COPY_TIMEOUT_MS    default 30000 (per-request timeout for HEAD, GET and PUT)
//
//   node scripts/copy-s3-maven-to-r2.mjs --dry-run
//   node scripts/copy-s3-maven-to-r2.mjs
//   node scripts/copy-s3-maven-to-r2.mjs --self-test
//
// The script talks only to S3 and R2. It does not change Cloudflare Worker settings.

import { createHash } from "node:crypto";
import { createHmac } from "node:crypto";

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has("--dry-run") || args.has("-n");
const HELP = args.has("--help") || args.has("-h");

function envInt(name, fallback) {
	const n = Number(process.env[name]);
	return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

export const CONCURRENCY = Math.max(1, envInt("COPY_CONCURRENCY", 32));
export const REQUEST_TIMEOUT_MS = envInt("COPY_TIMEOUT_MS", 30_000);
export const MAX_RETRIES = 3;
export const MAX_ATTEMPTS = MAX_RETRIES + 1;

export function dirPrefix(value, fallback = "") {
	const s = (value ?? fallback).trim().replace(/^\/+/, "");
	if (!s) return "";
	return s.endsWith("/") ? s : s + "/";
}

export function isMetadataKey(key) {
	const name = (key.split("/").pop() ?? "").toLowerCase();
	return name.startsWith("maven-metadata") || name === "index.html";
}

/** org/lucee/<artifactId>/<version>/... — SNAPSHOT versions go under the snapshot prefix in R2. */
export function isSnapshotMavenKey(key) {
	const prefix = "org/lucee/";
	if (!key.startsWith(prefix)) return false;
	const parts = key.slice(prefix.length).split("/").filter((p) => p.length);
	if (parts.length < 3) return false;
	return /-SNAPSHOT$/i.test(parts[1]);
}

export function r2DestKey(mavenKey, { prefix = "", snapshotPrefix = "snapshots/" } = {}) {
	return dirPrefix(prefix) + (isSnapshotMavenKey(mavenKey) ? dirPrefix(snapshotPrefix, "snapshots/") : "") + mavenKey;
}

export function parseArgs(argv) {
	return { dryRun: argv.includes("--dry-run") || argv.includes("-n"), help: argv.includes("--help") || argv.includes("-h") };
}

export function sameObject(source, dest) {
	if (!dest) return false;
	if (Number(source.size) !== Number(dest.size)) return false;
	const a = normalizeEtag(source.etag);
	const b = normalizeEtag(dest.etag);
	if (!a || !b || a.includes("-") || b.includes("-")) return true; // size already matches; multipart ETags are not comparable
	return a === b;
}

function normalizeEtag(value) {
	return String(value ?? "")
		.trim()
		.replaceAll('"', "")
		.toLowerCase();
}

function env(name, fallback = "") {
	return (process.env[name] ?? fallback).trim();
}

function required(name, value) {
	if (!value) throw new Error(`missing environment variable ${name}`);
	return value;
}

function s3Config() {
	const accessKeyId = env("AWS_ACCESS_KEY_ID") || env("INPUT_S3_ACCESS_KEY");
	const secretAccessKey = env("AWS_SECRET_ACCESS_KEY") || env("INPUT_S3_SECRET_KEY");
	return {
		endpoint: "",
		region: env("S3_REGION", "us-east-1"),
		bucket: env("S3_BUCKET", "lucee-downloads"),
		prefix: dirPrefix(env("S3_PREFIX", "org/lucee/"), "org/lucee/"),
		accessKeyId: required("AWS_ACCESS_KEY_ID or INPUT_S3_ACCESS_KEY", accessKeyId),
		secretAccessKey: required("AWS_SECRET_ACCESS_KEY or INPUT_S3_SECRET_KEY", secretAccessKey),
		pathStyle: false
	};
}

function r2Config() {
	return {
		endpoint: required("R2_ENDPOINT", env("R2_ENDPOINT")).replace(/\/+$/, ""),
		region: "auto",
		bucket: required("R2_BUCKET", env("R2_BUCKET")),
		prefix: dirPrefix(env("R2_PREFIX")),
		snapshotPrefix: dirPrefix(env("R2_SNAPSHOT_PREFIX"), "snapshots/"),
		accessKeyId: required("R2_ACCESS_KEY_ID", env("R2_ACCESS_KEY_ID")),
		secretAccessKey: required("R2_SECRET_ACCESS_KEY", env("R2_SECRET_ACCESS_KEY")),
		pathStyle: true
	};
}

function hmac(key, value) {
	return createHmac("sha256", key).update(value).digest();
}

function sha256Hex(data) {
	return createHash("sha256").update(data).digest("hex");
}

function amzDate(date) {
	const iso = date.toISOString().replace(/[:-]|\.\d{3}/g, "");
	return { amz: iso, day: iso.slice(0, 8) };
}

function uriEncode(value, isPath = false) {
	let out = encodeURIComponent(value).replaceAll(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
	if (isPath) out = out.replaceAll("%2F", "/");
	return out;
}

function hostOf(cfg) {
	if (cfg.endpoint) return new URL(cfg.endpoint).host;
	return cfg.region === "us-east-1" ? "s3.amazonaws.com" : `s3.${cfg.region}.amazonaws.com`;
}

function objectUrl(cfg, key, query = "") {
	const host = hostOf(cfg);
	const path = cfg.pathStyle || cfg.endpoint ? `/${cfg.bucket}/${key.split("/").map((p) => uriEncode(p)).join("/")}` : `/${key.split("/").map((p) => uriEncode(p)).join("/")}`;
	const virtualHost = cfg.pathStyle || cfg.endpoint ? host : `${cfg.bucket}.${host}`;
	const base = cfg.endpoint ? cfg.endpoint : `https://${virtualHost}`;
	const origin = cfg.endpoint ? `${base}${path}` : `https://${virtualHost}${cfg.pathStyle ? path : `/${key.split("/").map((p) => uriEncode(p)).join("/")}`}`;
	return { url: origin + (query ? `?${query}` : ""), host: virtualHost, path };
}

function sign(cfg, method, url, path, host, headers, bodyHash, date = new Date()) {
	const { amz, day } = amzDate(date);
	const service = "s3";
	const region = cfg.region;
	const signed = { host, "x-amz-date": amz, "x-amz-content-sha256": bodyHash, ...headers };
	const names = Object.keys(signed)
		.map((n) => n.toLowerCase())
		.sort();
	const canonicalHeaders = names.map((n) => `${n}:${String(signed[Object.keys(signed).find((k) => k.toLowerCase() === n)]).trim()}\n`).join("");
	const u = new URL(url);
	const qs = [...u.searchParams.entries()].sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
	const canonicalQs = qs.map(([k, v]) => `${uriEncode(k)}=${uriEncode(v)}`).join("&");
	const canonical = [method, path, canonicalQs, canonicalHeaders, names.join(";"), bodyHash].join("\n");
	const scope = `${day}/${region}/${service}/aws4_request`;
	const stringToSign = ["AWS4-HMAC-SHA256", amz, scope, sha256Hex(canonical)].join("\n");
	const kDate = hmac(`AWS4${cfg.secretAccessKey}`, day);
	const kRegion = hmac(kDate, region);
	const kService = hmac(kRegion, service);
	const kSigning = hmac(kService, "aws4_request");
	const signature = createHmac("sha256", kSigning).update(stringToSign).digest("hex");
	signed.authorization = `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, SignedHeaders=${names.join(";")}, Signature=${signature}`;
	return signed;
}

export function isRetryableStatus(status) {
	return Number(status) >= 500 && Number(status) <= 599;
}

export function isRetryableError(error) {
	if (!error) return false;
	const name = error.name || "";
	if (name === "TimeoutError" || name === "AbortError" || name === "ConnectTimeoutError") return true;
	const code = error.code || "";
	if (
		code === "ABORT_ERR" ||
		code === "ETIMEDOUT" ||
		code === "ECONNRESET" ||
		code === "ECONNREFUSED" ||
		code === "ENOTFOUND" ||
		code === "EAI_AGAIN" ||
		code === "EPIPE" ||
		code === "ENETUNREACH" ||
		code === "UND_ERR_CONNECT_TIMEOUT" ||
		code === "UND_ERR_SOCKET" ||
		code === "UND_ERR_HEADERS_TIMEOUT" ||
		code === "UND_ERR_BODY_TIMEOUT"
	) {
		return true;
	}
	if (name === "TypeError" && /fetch failed|network|ECONNRESET|socket/i.test(String(error.message || ""))) return true;
	if (error.cause && isRetryableError(error.cause)) return true;
	return false;
}

export function backoffMs(attempt) {
	// attempt is the failed try (1-based): 250ms, 500ms, 1000ms, ...
	return 250 * 2 ** (attempt - 1);
}

export function delay(ms) {
	return new Promise((resolve) => setTimeout(resolve, ms));
}

/** AbortSignal.timeout plus a ref'd timer: Node unrefs the timeout timer, so a hung fetch would otherwise never abort. */
export function requestSignal(timeoutMs = REQUEST_TIMEOUT_MS) {
	const ms = Math.max(1, Number(timeoutMs) || REQUEST_TIMEOUT_MS);
	const signal = AbortSignal.timeout(ms);
	const keepAlive = setTimeout(() => {}, ms);
	const clear = () => clearTimeout(keepAlive);
	if (signal.aborted) clear();
	else signal.addEventListener("abort", clear, { once: true });
	return signal;
}

/** Up to MAX_RETRIES retries (MAX_ATTEMPTS total tries) with timeout and backoff on network errors, 5xx and timeouts. */
export async function fetchWithRetry({ timeoutMs = REQUEST_TIMEOUT_MS, attempts = MAX_ATTEMPTS, run, sleep = delay } = {}) {
	if (typeof run !== "function") throw new Error("fetchWithRetry requires a run(signal) function");
	const maxAttempts = Math.max(1, attempts);
	let lastError;
	for (let attempt = 1; attempt <= maxAttempts; attempt++) {
		const signal = requestSignal(timeoutMs);
		try {
			const res = await run(signal);
			if (!isRetryableStatus(res.status) || attempt === maxAttempts) return res;
			try {
				res.body?.cancel?.();
			} catch {
				// ignore cancel failures on already-closed bodies
			}
			await sleep(backoffMs(attempt));
		} catch (e) {
			lastError = e;
			if (!isRetryableError(e) || attempt === maxAttempts) throw e;
			await sleep(backoffMs(attempt));
		}
	}
	throw lastError ?? new Error("fetchWithRetry exhausted attempts");
}

async function s3Fetch(cfg, method, key, { query = "", headers = {}, body, hash } = {}) {
	const { url, host, path } = objectUrl(cfg, key, query);
	const bodyHash = hash ?? (body == null ? sha256Hex("") : sha256Hex(body));
	return fetchWithRetry({
		timeoutMs: REQUEST_TIMEOUT_MS,
		attempts: MAX_ATTEMPTS,
		run: (signal) => {
			const signed = sign(cfg, method, url, path, host, headers, bodyHash);
			return fetch(url, { method, headers: signed, body, signal });
		}
	});
}

function decodeXml(value) {
	return value
		.replaceAll("&quot;", '"')
		.replaceAll("&apos;", "'")
		.replaceAll("&lt;", "<")
		.replaceAll("&gt;", ">")
		.replaceAll("&amp;", "&");
}

async function listObjects(cfg, prefix) {
	const objects = [];
	let token = "";
	do {
		const params = new URLSearchParams({ "list-type": "2", prefix, "max-keys": "1000" });
		if (token) params.set("continuation-token", token);
		const res = await s3Fetch(cfg, "GET", "", { query: params.toString() });
		const text = await res.text();
		if (!res.ok) throw new Error(`ListObjectsV2 ${cfg.bucket}/${prefix} HTTP ${res.status}: ${text.slice(0, 400)}`);
		for (const block of text.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
			const body = block[1];
			const key = decodeXml(body.match(/<Key>([^<]+)<\/Key>/)?.[1] ?? "");
			if (!key) continue;
			objects.push({
				key,
				size: Number(body.match(/<Size>([^<]+)<\/Size>/)?.[1] ?? 0),
				etag: decodeXml(body.match(/<ETag>([^<]+)<\/ETag>/)?.[1] ?? "")
			});
		}
		const truncated = /<IsTruncated>true<\/IsTruncated>/.test(text);
		const next = text.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/);
		token = truncated && next ? decodeXml(next[1]) : "";
	} while (token);
	return objects;
}

async function headObject(cfg, key) {
	const res = await s3Fetch(cfg, "HEAD", key);
	if (res.status === 404) return undefined;
	if (!res.ok) throw new Error(`HEAD ${cfg.bucket}/${key} HTTP ${res.status}`);
	return { size: Number(res.headers.get("content-length") ?? 0), etag: res.headers.get("etag") ?? "" };
}

async function copyObject(source, dest, key, destKey) {
	const get = await s3Fetch(source, "GET", key);
	if (!get.ok) throw new Error(`GET ${source.bucket}/${key} HTTP ${get.status}`);
	const buf = Buffer.from(await get.arrayBuffer());
	const contentType = get.headers.get("content-type") || "application/octet-stream";
	const put = await s3Fetch(dest, "PUT", destKey, {
		headers: { "content-type": contentType, "content-length": String(buf.length) },
		body: buf,
		hash: sha256Hex(buf)
	});
	if (!put.ok) throw new Error(`PUT ${dest.bucket}/${destKey} HTTP ${put.status}: ${(await put.text()).slice(0, 400)}`);
}

export async function mapPool(items, limit, fn) {
	const ret = [];
	let i = 0;
	const workers = Array.from({ length: Math.min(Math.max(1, limit), items.length) }, async () => {
		while (i < items.length) {
			const idx = i++;
			ret[idx] = await fn(items[idx], idx);
		}
	});
	await Promise.all(workers);
	return ret;
}

function log(message) {
	console.log(message);
}

export async function planCopy(sourceObjects, destKeyFor, destHead, { concurrency = CONCURRENCY, onProgress } = {}) {
	const total = sourceObjects.length;
	const limit = Math.max(1, Number(concurrency) || 1);
	let checked = 0;
	let copyCount = 0;
	let skipCount = 0;
	const outcomes = await mapPool(sourceObjects, limit, async (obj) => {
		let outcome;
		if (isMetadataKey(obj.key)) {
			outcome = { kind: "exclude", obj };
		} else {
			const destKey = destKeyFor(obj.key);
			const existing = await destHead(destKey);
			if (sameObject(obj, existing)) outcome = { kind: "skip", item: { ...obj, destKey } };
			else outcome = { kind: "copy", item: { ...obj, destKey } };
		}
		checked += 1;
		if (outcome.kind === "copy") copyCount += 1;
		else if (outcome.kind === "skip") skipCount += 1;
		if (onProgress && (checked % 500 === 0 || checked === total)) {
			onProgress({ checked, total, copy: copyCount, skip: skipCount });
		}
		return outcome;
	});
	const plan = { copy: [], skip: [], exclude: [] };
	for (const outcome of outcomes) {
		if (outcome.kind === "exclude") plan.exclude.push(outcome.obj);
		else plan[outcome.kind].push(outcome.item);
	}
	return plan;
}

async function main() {
	if (HELP) {
		console.log(`Usage: node scripts/copy-s3-maven-to-r2.mjs [--dry-run]

Copy org/lucee/** from S3 (lucee-downloads) to the Maven bridge R2 bucket.
Skips metadata files and objects that already exist with the same size.
Planning HEADs and copies run with COPY_CONCURRENCY (default 32).
Each HEAD, GET and PUT uses COPY_TIMEOUT_MS (default 30000) and up to 3 retries.
See the file header for the environment variables.`);
		return;
	}
	const source = s3Config();
	const dest = r2Config();
	log(`listing s3://${source.bucket}/${source.prefix} (region ${source.region})`);
	const objects = await listObjects(source, source.prefix);
	log(`found ${objects.length} objects`);
	const destKeyFor = (key) => r2DestKey(key, dest);
	const plan = await planCopy(objects, destKeyFor, (key) => headObject(dest, key), {
		concurrency: CONCURRENCY,
		onProgress: ({ checked, total, copy, skip }) => log(`checked ${checked}/${total}, copy ${copy}, skip ${skip}`)
	});
	log(`copy ${plan.copy.length}, skip ${plan.skip.length}, exclude ${plan.exclude.length} metadata files${DRY_RUN ? " (dry run)" : ""}`);
	if (DRY_RUN) {
		for (const item of plan.copy.slice(0, 20)) log(`DRY RUN would copy s3://${source.bucket}/${item.key} -> r2://${dest.bucket}/${item.destKey} (${item.size} bytes)`);
		if (plan.copy.length > 20) log(`... and ${plan.copy.length - 20} more`);
		return;
	}
	let done = 0;
	await mapPool(plan.copy, CONCURRENCY, async (item) => {
		await copyObject(source, dest, item.key, item.destKey);
		done += 1;
		if (done % 50 === 0 || done === plan.copy.length) log(`copied ${done}/${plan.copy.length}`);
	});
	log(`done: copied ${plan.copy.length}, skipped ${plan.skip.length}, excluded ${plan.exclude.length}`);
}

export async function runSelfTests() {
	const failures = [];
	const assert = (cond, msg) => {
		if (!cond) failures.push(msg);
	};
	const eq = (a, b, msg) => {
		const as = JSON.stringify(a);
		const bs = JSON.stringify(b);
		assert(as === bs, `${msg}: expected ${bs}, got ${as}`);
	};

	eq(dirPrefix("org/lucee"), "org/lucee/", "dirPrefix adds slash");
	eq(dirPrefix("org/lucee/"), "org/lucee/", "dirPrefix keeps slash");
	eq(dirPrefix(""), "", "dirPrefix empty");
	eq(dirPrefix(undefined, "snapshots/"), "snapshots/", "dirPrefix fallback");

	assert(isMetadataKey("org/lucee/foo/maven-metadata.xml"), "metadata xml");
	assert(isMetadataKey("org/lucee/foo/maven-metadata.xml.sha1"), "metadata checksum");
	assert(isMetadataKey("org/lucee/foo/index.html"), "index.html");
	assert(!isMetadataKey("org/lucee/foo/1.0.0/foo-1.0.0.jar"), "jar is not metadata");

	assert(isSnapshotMavenKey("org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar"), "snapshot key");
	assert(!isSnapshotMavenKey("org/lucee/foo/1.0.0/foo-1.0.0.jar"), "release key");
	assert(!isSnapshotMavenKey("org/lucee/foo/maven-metadata.xml"), "artifact-level key is not a snapshot version folder");

	eq(r2DestKey("org/lucee/foo/1.0.0/foo-1.0.0.jar"), "org/lucee/foo/1.0.0/foo-1.0.0.jar", "release dest key");
	eq(
		r2DestKey("org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar"),
		"snapshots/org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar",
		"snapshot dest key"
	);
	eq(
		r2DestKey("org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar", { prefix: "pre/", snapshotPrefix: "snaps/" }),
		"pre/snaps/org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar",
		"dest key with prefixes"
	);

	assert(parseArgs(["--dry-run"]).dryRun && !parseArgs(["--dry-run"]).help, "parseArgs dry-run");
	assert(parseArgs(["-n"]).dryRun, "parseArgs -n");
	assert(parseArgs(["--help"]).help, "parseArgs help");

	assert(!sameObject({ size: 1, etag: "abc" }, undefined), "sameObject missing dest");
	assert(!sameObject({ size: 2, etag: "abc" }, { size: 1, etag: "abc" }), "sameObject size mismatch");
	assert(sameObject({ size: 1, etag: "ABC" }, { size: 1, etag: '"abc"' }), "sameObject normalizes etag");
	assert(!sameObject({ size: 1, etag: "aaa" }, { size: 1, etag: "bbb" }), "sameObject etag mismatch");
	assert(sameObject({ size: 1, etag: "aaa" }, { size: 1, etag: "" }), "sameObject missing etag compares size only");
	assert(sameObject({ size: 10, etag: "abc-1" }, { size: 10, etag: "zzz-2" }), "sameObject multipart etag compares size only");

	assert(isRetryableStatus(500) && isRetryableStatus(503) && isRetryableStatus(599), "5xx retryable");
	assert(!isRetryableStatus(200) && !isRetryableStatus(404) && !isRetryableStatus(403) && !isRetryableStatus(429), "non-5xx not retryable");
	assert(isRetryableError({ name: "TimeoutError" }), "TimeoutError retryable");
	assert(isRetryableError({ name: "AbortError" }), "AbortError retryable");
	assert(isRetryableError({ code: "ECONNRESET" }), "ECONNRESET retryable");
	assert(isRetryableError({ name: "TypeError", message: "fetch failed" }), "fetch failed retryable");
	assert(isRetryableError({ name: "TypeError", message: "fetch failed", cause: { code: "ECONNRESET" } }), "wrapped cause retryable");
	assert(!isRetryableError({ name: "TypeError", message: "Cannot read properties of undefined" }), "programming TypeError not retryable");
	eq(backoffMs(1), 250, "backoff 1");
	eq(backoffMs(2), 500, "backoff 2");
	eq(backoffMs(3), 1000, "backoff 3");

	const pool = await mapPool([1, 2, 3, 4, 5], 2, async (n) => n * 10);
	eq(pool, [10, 20, 30, 40, 50], "mapPool keeps result order");
	eq(await mapPool([], 32, async (n) => n), [], "mapPool empty");

	let inFlight = 0;
	let maxInFlight = 0;
	await mapPool([1, 2, 3, 4, 5, 6], 3, async () => {
		inFlight += 1;
		maxInFlight = Math.max(maxInFlight, inFlight);
		await delay(20);
		inFlight -= 1;
	});
	assert(maxInFlight === 3, `mapPool concurrency was ${maxInFlight}, expected 3`);

	const sourceObjects = [
		{ key: "org/lucee/foo/maven-metadata.xml", size: 10, etag: "m1" },
		{ key: "org/lucee/foo/1.0.0/foo-1.0.0.jar", size: 100, etag: "a" },
		{ key: "org/lucee/foo/1.0.0/foo-1.0.0.jar.md5", size: 32, etag: "b" },
		{ key: "org/lucee/foo/index.html", size: 20, etag: "i" },
		{ key: "org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar", size: 50, etag: "c" },
		{ key: "org/lucee/bar/2.0.0/bar-2.0.0.lex", size: 7, etag: "d" }
	];
	const dest = {
		"org/lucee/foo/1.0.0/foo-1.0.0.jar": { size: 100, etag: "a" },
		"org/lucee/foo/1.0.0/foo-1.0.0.jar.md5": { size: 1, etag: "old" }
	};
	const headCalls = [];
	const plan = await planCopy(
		sourceObjects,
		(key) => r2DestKey(key),
		async (destKey) => {
			headCalls.push(destKey);
			await delay(5);
			return dest[destKey];
		},
		{ concurrency: 4 }
	);
	eq(
		plan.exclude.map((o) => o.key),
		["org/lucee/foo/maven-metadata.xml", "org/lucee/foo/index.html"],
		"plan exclude order"
	);
	eq(
		plan.skip.map((o) => o.key),
		["org/lucee/foo/1.0.0/foo-1.0.0.jar"],
		"plan skip order"
	);
	eq(
		plan.copy.map((o) => o.key),
		["org/lucee/foo/1.0.0/foo-1.0.0.jar.md5", "org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar", "org/lucee/bar/2.0.0/bar-2.0.0.lex"],
		"plan copy order is source order"
	);
	eq(plan.copy.find((o) => o.key.includes("SNAPSHOT")).destKey, "snapshots/org/lucee/foo/1.0.0-SNAPSHOT/foo-1.0.0-SNAPSHOT.jar", "plan snapshot destKey");
	eq(headCalls.length, 4, "planCopy HEADs only non-metadata keys");
	assert(!headCalls.some((k) => k.includes("maven-metadata") || k.endsWith("index.html")), "no HEAD for metadata");

	// HEAD completion order is reversed, result order stays deterministic
	const many = Array.from({ length: 12 }, (_, i) => ({ key: `org/lucee/a/1.0.0/f${String(i).padStart(2, "0")}.jar`, size: 1, etag: "x" }));
	const revPlan = await planCopy(
		many,
		(key) => key,
		async (destKey) => {
			const n = Number(destKey.match(/f(\d+)/)[1]);
			await delay((12 - n) * 4);
			return n % 2 === 0 ? { size: 1, etag: "x" } : undefined;
		},
		{ concurrency: 6 }
	);
	eq(
		revPlan.skip.map((o) => o.key),
		many.filter((_, i) => i % 2 === 0).map((o) => o.key),
		"concurrent plan skip order follows source"
	);
	eq(
		revPlan.copy.map((o) => o.key),
		many.filter((_, i) => i % 2 === 1).map((o) => o.key),
		"concurrent plan copy order follows source"
	);

	const progress = [];
	const thousand = Array.from({ length: 1000 }, (_, i) => ({ key: `org/lucee/a/1.0.0/p${i}.jar`, size: 1, etag: "e" }));
	await planCopy(
		thousand,
		(key) => key,
		async () => undefined,
		{
			concurrency: 16,
			onProgress: (p) => progress.push({ ...p })
		}
	);
	eq(
		progress.map((p) => `${p.checked}/${p.total}:${p.copy}/${p.skip}`),
		["500/1000:500/0", "1000/1000:1000/0"],
		"progress every 500 and at end"
	);

	const halfSkip = Array.from({ length: 500 }, (_, i) => ({ key: `org/lucee/a/1.0.0/s${i}.jar`, size: 2, etag: "e" }));
	const mid = [];
	await planCopy(
		halfSkip,
		(key) => key,
		async (destKey) => (destKey.endsWith("s0.jar") ? { size: 2, etag: "e" } : undefined),
		{ concurrency: 8, onProgress: (p) => mid.push(p) }
	);
	eq(mid.length, 1, "progress once at 500");
	eq({ copy: mid[0].copy, skip: mid[0].skip, checked: mid[0].checked }, { copy: 499, skip: 1, checked: 500 }, "progress copy/skip so far");

	const sleeps = [];
	let calls = 0;
	const ok = await fetchWithRetry({
		timeoutMs: 1000,
		attempts: MAX_ATTEMPTS,
		sleep: async (ms) => {
			sleeps.push(ms);
		},
		run: async () => {
			calls += 1;
			if (calls < 3) return { status: 503, body: { cancel() {} } };
			return { status: 200, body: { cancel() {} } };
		}
	});
	assert(ok.status === 200, "fetchWithRetry succeeds after 5xx");
	eq(calls, 3, "fetchWithRetry 5xx retried twice then succeeded");
	eq(sleeps, [250, 500], "fetchWithRetry backoff after 5xx");

	calls = 0;
	const notFound = await fetchWithRetry({
		timeoutMs: 1000,
		attempts: MAX_ATTEMPTS,
		sleep: async () => {
			throw new Error("should not sleep on 404");
		},
		run: async () => {
			calls += 1;
			return { status: 404 };
		}
	});
	assert(notFound.status === 404 && calls === 1, "404 is not retried");

	calls = 0;
	let forbiddenSleep = 0;
	const forbidden = await fetchWithRetry({
		timeoutMs: 1000,
		attempts: MAX_ATTEMPTS,
		sleep: async () => {
			forbiddenSleep += 1;
		},
		run: async () => {
			calls += 1;
			return { status: 403 };
		}
	});
	assert(forbidden.status === 403 && calls === 1 && forbiddenSleep === 0, "403 is not retried");

	const last500 = await fetchWithRetry({
		timeoutMs: 1000,
		attempts: MAX_ATTEMPTS,
		sleep: async () => {},
		run: async () => ({ status: 500, body: { cancel() {} } })
	});
	assert(last500.status === 500, "exhausted 5xx returns last response");

	calls = 0;
	const recovered = await fetchWithRetry({
		timeoutMs: 1000,
		attempts: MAX_ATTEMPTS,
		sleep: async () => {},
		run: async () => {
			calls += 1;
			if (calls <= 3) {
				const err = new Error("aborted");
				err.name = "TimeoutError";
				throw err;
			}
			return { status: 200 };
		}
	});
	assert(recovered.status === 200 && calls === 4, "retries TimeoutError up to 3 times then succeeds");

	const t0 = Date.now();
	const sig = requestSignal(50);
	try {
		await new Promise((_, reject) => {
			sig.addEventListener("abort", () => reject(sig.reason ?? new Error("aborted")), { once: true });
		});
		assert(false, "requestSignal should abort");
	} catch (e) {
		assert(sig.aborted, "requestSignal aborted");
		assert(e && (e.name === "TimeoutError" || e.name === "AbortError" || e.code === "ABORT_ERR"), `requestSignal reason ${e && e.name}`);
		assert(Date.now() - t0 >= 40, "requestSignal waited for the timeout");
	}

	calls = 0;
	try {
		await fetchWithRetry({
			timeoutMs: 15,
			attempts: 2,
			sleep: async () => {},
			run: (signal) =>
				new Promise((_, reject) => {
					calls += 1;
					const onAbort = () => reject(signal.reason ?? Object.assign(new Error("aborted"), { name: "AbortError" }));
					if (signal.aborted) onAbort();
					else signal.addEventListener("abort", onAbort, { once: true });
				})
		});
		assert(false, "timeout should throw");
	} catch (e) {
		assert(e && (e.name === "TimeoutError" || e.name === "AbortError" || e.code === "ABORT_ERR"), `AbortSignal.timeout rejected with ${e && e.name}`);
		assert(calls === 2, `timeout retried, calls=${calls}`);
	}

	calls = 0;
	try {
		await fetchWithRetry({
			timeoutMs: 1000,
			attempts: MAX_ATTEMPTS,
			sleep: async () => {},
			run: async () => {
				calls += 1;
				throw Object.assign(new Error("bad request"), { name: "Error" });
			}
		});
		assert(false, "non-retryable error should throw");
	} catch (e) {
		assert(e.message === "bad request" && calls === 1, "non-retryable error is not retried");
	}

	if (failures.length) {
		for (const msg of failures) console.error(`FAIL ${msg}`);
		throw new Error(`${failures.length} self-test(s) failed`);
	}
	console.log(`self-test: ${"ok"}`);
}

const isMain = import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("copy-s3-maven-to-r2.mjs");
if (isMain && args.has("--self-test")) {
	runSelfTests().catch((e) => {
		console.error(e instanceof Error ? e.message : e);
		process.exit(1);
	});
} else if (isMain) {
	main().catch((e) => {
		console.error(e instanceof Error ? e.message : e);
		process.exit(1);
	});
}
