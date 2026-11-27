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
//
//   node scripts/copy-s3-maven-to-r2.mjs --dry-run
//   node scripts/copy-s3-maven-to-r2.mjs
//
// The script talks only to S3 and R2. It does not change Cloudflare Worker settings.

import { createHash } from "node:crypto";
import { createHmac } from "node:crypto";

const args = new Set(process.argv.slice(2));
const DRY_RUN = args.has("--dry-run") || args.has("-n");
const HELP = args.has("--help") || args.has("-h");
const CONCURRENCY = Math.max(1, Number(process.env.COPY_CONCURRENCY || 8));

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

async function s3Fetch(cfg, method, key, { query = "", headers = {}, body, hash } = {}) {
	const { url, host, path } = objectUrl(cfg, key, query);
	const bodyHash = hash ?? (body == null ? sha256Hex("") : sha256Hex(body));
	const signed = sign(cfg, method, url, path, host, headers, bodyHash);
	const res = await fetch(url, { method, headers: signed, body });
	return res;
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

async function mapPool(items, limit, fn) {
	const ret = [];
	let i = 0;
	const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
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

export async function planCopy(sourceObjects, destKeyFor, destHead) {
	const plan = { copy: [], skip: [], exclude: [] };
	for (const obj of sourceObjects) {
		if (isMetadataKey(obj.key)) {
			plan.exclude.push(obj);
			continue;
		}
		const destKey = destKeyFor(obj.key);
		const existing = await destHead(destKey);
		if (sameObject(obj, existing)) plan.skip.push({ ...obj, destKey });
		else plan.copy.push({ ...obj, destKey });
	}
	return plan;
}

async function main() {
	if (HELP) {
		console.log(`Usage: node scripts/copy-s3-maven-to-r2.mjs [--dry-run]

Copy org/lucee/** from S3 (lucee-downloads) to the Maven bridge R2 bucket.
Skips metadata files and objects that already exist with the same size.
See the file header for the environment variables.`);
		return;
	}
	const source = s3Config();
	const dest = r2Config();
	log(`listing s3://${source.bucket}/${source.prefix} (region ${source.region})`);
	const objects = await listObjects(source, source.prefix);
	log(`found ${objects.length} objects`);
	const destKeyFor = (key) => r2DestKey(key, dest);
	const plan = await planCopy(objects, destKeyFor, (key) => headObject(dest, key));
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

const isMain = import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith("copy-s3-maven-to-r2.mjs");
if (isMain && !args.has("--self-test")) {
	main().catch((e) => {
		console.error(e instanceof Error ? e.message : e);
		process.exit(1);
	});
}
