#!/usr/bin/env node
// Publishes the OSGi bundle jars that only exist inside extension .lex files as
// org.lucee:<Bundle-SymbolicName>:<Bundle-Version> in the R2 bucket the Maven bridge worker serves
// (maven.lucee-services.com).
//
// The update provider answers /rest/update/provider/download/<bundle>/<version> with a 302 to a jar
// on a Maven repository, or a 404. It does not extract a jar from a .lex. A jar that ships only
// inside a .lex (for example the extension's own bundle, org.lucee.axis.extension, or old bundles
// like mssqljdbc4) is found once it is at
//   org/lucee/<Bundle-SymbolicName>/<Bundle-Version>/<Bundle-SymbolicName>-<Bundle-Version>.jar
// which is the layout of the "Upload Maven jar" workflow of lucee/Lucee.
//
// For every .lex in the source bucket the script reads jars/*.jar, takes Bundle-SymbolicName and
// Bundle-Version from each jar's manifest and writes the jar (and a minimal pom) to that key when it
// is not there yet. SNAPSHOT versions are written to the plain Maven-layout key as well (not below
// R2_SNAPSHOT_PREFIX), so the snapshot lifecycle rule does not remove them; the worker looks up that
// key for SNAPSHOT files too.
//
//   - idempotent: a jar already at its key is skipped
//   - --dry-run lists what would be written and writes nothing
//   - --lex <regex>     only read .lex files whose key matches
//   - --bundle <regex>  only publish bundles whose Bundle-SymbolicName matches
//
// Source (SOURCE, default r2):
//   r2  the .lex files below org/lucee/ and snapshots/org/lucee/ of R2_BUCKET (no egress cost)
//   s3  the .lex files below S3_PREFIX of S3_BUCKET, e.g. a bucket that is not copied to R2 yet
//       S3 credentials: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (or INPUT_S3_ACCESS_KEY / INPUT_S3_SECRET_KEY)
//       S3_BUCKET default lucee-downloads, S3_REGION default us-east-1, S3_PREFIX default org/lucee/
//
// Destination: R2_ENDPOINT, R2_BUCKET, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_PREFIX (optional)
//
// Not run by CI. Run it by hand, credentials in the environment (never on the command line):
//
//   node scripts/publish-lex-bundles-to-r2.mjs --dry-run
//   node scripts/publish-lex-bundles-to-r2.mjs

import { createHash, createHmac } from "node:crypto";
import { inflateRawSync } from "node:zlib";

// ---------------------------------------------------------------- zip / manifest

/** Entries of a zip file (central directory): [{ name, method, compressedSize, size, offset }]. */
export function zipEntries(buf) {
	const min = Math.max(0, buf.length - 0xffff - 22);
	let eocd = -1;
	for (let i = buf.length - 22; i >= min; i--) {
		if (buf.readUInt32LE(i) === 0x06054b50) {
			eocd = i;
			break;
		}
	}
	if (eocd < 0) throw new Error("not a zip file (no end of central directory)");
	const count = buf.readUInt16LE(eocd + 10);
	let p = buf.readUInt32LE(eocd + 16);
	const entries = [];
	for (let n = 0; n < count; n++) {
		if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error("broken zip central directory");
		const method = buf.readUInt16LE(p + 10);
		const compressedSize = buf.readUInt32LE(p + 20);
		const size = buf.readUInt32LE(p + 24);
		const nameLen = buf.readUInt16LE(p + 28);
		const extraLen = buf.readUInt16LE(p + 30);
		const commentLen = buf.readUInt16LE(p + 32);
		const offset = buf.readUInt32LE(p + 42);
		const name = buf.toString("utf8", p + 46, p + 46 + nameLen);
		entries.push({ name, method, compressedSize, size, offset });
		p += 46 + nameLen + extraLen + commentLen;
	}
	return entries;
}

/** The bytes of one zip entry (stored or deflated). */
export function zipRead(buf, entry) {
	const p = entry.offset;
	if (buf.readUInt32LE(p) !== 0x04034b50) throw new Error(`broken zip local header for ${entry.name}`);
	const start = p + 30 + buf.readUInt16LE(p + 26) + buf.readUInt16LE(p + 28);
	const data = buf.subarray(start, start + entry.compressedSize);
	if (entry.method === 0) return Buffer.from(data);
	if (entry.method === 8) return inflateRawSync(data);
	throw new Error(`unsupported zip method ${entry.method} for ${entry.name}`);
}

/** Main attributes of a MANIFEST.MF (continuation lines joined). */
export function parseManifest(text) {
	const attrs = {};
	const lines = String(text).replace(/\r\n?/g, "\n").split("\n");
	let last = "";
	for (const line of lines) {
		if (line === "") {
			if (Object.keys(attrs).length) break; // end of the main section
			continue;
		}
		if (line.startsWith(" ") && last) {
			attrs[last] += line.slice(1);
			continue;
		}
		const i = line.indexOf(":");
		if (i <= 0) continue;
		last = line.slice(0, i).trim();
		attrs[last] = line.slice(i + 1).trim();
	}
	return attrs;
}

/** Bundle-SymbolicName (without directives) and Bundle-Version of a jar, or undefined for a plain jar. */
export function bundleOfJar(jarBuf) {
	const entry = zipEntries(jarBuf).find((e) => e.name.toUpperCase() === "META-INF/MANIFEST.MF");
	if (!entry) return undefined;
	const attrs = parseManifest(zipRead(jarBuf, entry).toString("utf8"));
	const name = (attrs["Bundle-SymbolicName"] ?? "").split(";")[0].trim();
	const version = (attrs["Bundle-Version"] ?? "").trim();
	if (!name || !version) return undefined;
	return { name, version };
}

/** The bundle jars of a .lex: [{ path, name, version, data }]. */
export function bundlesOfLex(lexBuf) {
	const out = [];
	for (const e of zipEntries(lexBuf)) {
		if (!/^jars\/[^/]+\.jar$/i.test(e.name)) continue;
		const data = zipRead(lexBuf, e);
		let b;
		try {
			b = bundleOfJar(data);
		} catch {
			b = undefined;
		}
		if (b) out.push({ path: e.name, ...b, data });
	}
	return out;
}

const SAFE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/** R2 key of org.lucee:<name>:<version> (plain Maven layout, also for SNAPSHOT versions); "" for unsafe names. */
export function bundleKey(name, version, ext = "jar", prefix = "") {
	if (!SAFE.test(name) || !SAFE.test(version)) return "";
	return `${dirPrefix(prefix)}org/lucee/${name}/${version}/${name}-${version}.${ext}`;
}

export function pomFor(name, version) {
	return `<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.lucee</groupId>
  <artifactId>${name}</artifactId>
  <version>${version}</version>
  <packaging>jar</packaging>
  <description>OSGi bundle ${name} ${version}, published from the jars of a Lucee extension</description>
</project>
`;
}

export function isLexKey(key) {
	return /\.lex$/i.test(key);
}

/**
 * The jars to write: bundles of the given lex files that are not at their key yet, the first lex wins
 * when two carry the same bundle version. lexes: [{ key, bundles }], exists(key) -> Promise<boolean>.
 */
export async function planPublish(lexes, exists, { prefix = "", bundleFilter } = {}) {
	const plan = { write: [], skip: [], unsafe: [] };
	const seen = new Set();
	for (const lex of lexes) {
		for (const b of lex.bundles) {
			if (bundleFilter && !bundleFilter.test(b.name)) continue;
			const key = bundleKey(b.name, b.version, "jar", prefix);
			if (!key) {
				plan.unsafe.push({ lex: lex.key, ...b });
				continue;
			}
			if (seen.has(key)) continue;
			seen.add(key);
			if (await exists(key)) plan.skip.push({ lex: lex.key, key, name: b.name, version: b.version });
			else plan.write.push({ lex: lex.key, key, pomKey: bundleKey(b.name, b.version, "pom", prefix), name: b.name, version: b.version, data: b.data });
		}
	}
	return plan;
}

// ---------------------------------------------------------------- S3 / R2 (SigV4)

export function dirPrefix(value, fallback = "") {
	const s = (value ?? fallback).trim().replace(/^\/+/, "");
	if (!s) return "";
	return s.endsWith("/") ? s : s + "/";
}

function env(name, fallback = "") {
	return (process.env[name] ?? fallback).trim();
}

function required(name, value) {
	if (!value) throw new Error(`missing environment variable ${name}`);
	return value;
}

function r2Config() {
	return {
		endpoint: required("R2_ENDPOINT", env("R2_ENDPOINT")).replace(/\/+$/, ""),
		region: "auto",
		bucket: required("R2_BUCKET", env("R2_BUCKET")),
		prefix: dirPrefix(env("R2_PREFIX")),
		accessKeyId: required("R2_ACCESS_KEY_ID", env("R2_ACCESS_KEY_ID")),
		secretAccessKey: required("R2_SECRET_ACCESS_KEY", env("R2_SECRET_ACCESS_KEY"))
	};
}

function s3Config() {
	return {
		endpoint: "",
		region: env("S3_REGION", "us-east-1"),
		bucket: env("S3_BUCKET", "lucee-downloads"),
		prefix: env("S3_PREFIX", "org/lucee/").replace(/^\/+/, ""),
		accessKeyId: required("AWS_ACCESS_KEY_ID", env("AWS_ACCESS_KEY_ID") || env("INPUT_S3_ACCESS_KEY")),
		secretAccessKey: required("AWS_SECRET_ACCESS_KEY", env("AWS_SECRET_ACCESS_KEY") || env("INPUT_S3_SECRET_KEY"))
	};
}

const sha256Hex = (data) => createHash("sha256").update(data).digest("hex");
const hmac = (key, value) => createHmac("sha256", key).update(value).digest();

function uriEncode(value) {
	return encodeURIComponent(value).replaceAll(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
}

function target(cfg, key, query) {
	const encKey = key
		.split("/")
		.map((p) => uriEncode(p))
		.join("/");
	if (cfg.endpoint) {
		const host = new URL(cfg.endpoint).host;
		const path = `/${cfg.bucket}${key ? "/" + encKey : "/"}`;
		return { url: `${cfg.endpoint}${path}${query ? "?" + query : ""}`, host, path };
	}
	const host = `${cfg.bucket}.${cfg.region === "us-east-1" ? "s3.amazonaws.com" : `s3.${cfg.region}.amazonaws.com`}`;
	const path = `/${encKey}`;
	return { url: `https://${host}${path}${query ? "?" + query : ""}`, host, path };
}

async function s3Fetch(cfg, method, key, { query = "", headers = {}, body } = {}) {
	const { url, host, path } = target(cfg, key, query);
	const iso = new Date().toISOString().replace(/[:-]|\.\d{3}/g, "");
	const day = iso.slice(0, 8);
	const bodyHash = sha256Hex(body ?? "");
	const signed = { host, "x-amz-date": iso, "x-amz-content-sha256": bodyHash, ...headers };
	const names = Object.keys(signed).map((n) => n.toLowerCase()).sort();
	const lookup = Object.fromEntries(Object.entries(signed).map(([k, v]) => [k.toLowerCase(), String(v).trim()]));
	const qs = [...new URLSearchParams(query).entries()]
		.sort((a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0))
		.map(([k, v]) => `${uriEncode(k)}=${uriEncode(v)}`)
		.join("&");
	const canonical = [method, path, qs, names.map((n) => `${n}:${lookup[n]}\n`).join(""), names.join(";"), bodyHash].join("\n");
	const scope = `${day}/${cfg.region}/s3/aws4_request`;
	const toSign = ["AWS4-HMAC-SHA256", iso, scope, sha256Hex(canonical)].join("\n");
	const kSigning = hmac(hmac(hmac(hmac(`AWS4${cfg.secretAccessKey}`, day), cfg.region), "s3"), "aws4_request");
	signed.authorization = `AWS4-HMAC-SHA256 Credential=${cfg.accessKeyId}/${scope}, SignedHeaders=${names.join(";")}, Signature=${createHmac("sha256", kSigning).update(toSign).digest("hex")}`;
	for (let attempt = 1; ; attempt++) {
		try {
			const res = await fetch(url, { method, headers: signed, body, signal: AbortSignal.timeout(120000) });
			if (res.status >= 500 && attempt < 4) throw new Error(`HTTP ${res.status}`);
			return res;
		} catch (e) {
			if (attempt >= 4) throw e;
			await new Promise((r) => setTimeout(r, 1000 * attempt));
		}
	}
}

async function listKeys(cfg, prefix) {
	const keys = [];
	let token = "";
	do {
		const params = new URLSearchParams({ "list-type": "2", prefix, "max-keys": "1000" });
		if (token) params.set("continuation-token", token);
		const res = await s3Fetch(cfg, "GET", "", { query: params.toString() });
		const text = await res.text();
		if (!res.ok) throw new Error(`ListObjectsV2 ${cfg.bucket}/${prefix} HTTP ${res.status}`);
		for (const m of text.matchAll(/<Key>([^<]+)<\/Key>/g)) keys.push(m[1].replaceAll("&amp;", "&"));
		const next = /<IsTruncated>true<\/IsTruncated>/.test(text) ? text.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/) : null;
		token = next ? next[1].replaceAll("&amp;", "&") : "";
	} while (token);
	return keys;
}

async function exists(cfg, key) {
	const res = await s3Fetch(cfg, "HEAD", key);
	if (res.status === 404) return false;
	if (!res.ok) throw new Error(`HEAD ${cfg.bucket}/${key} HTTP ${res.status}`);
	return true;
}

async function getObject(cfg, key) {
	const res = await s3Fetch(cfg, "GET", key);
	if (!res.ok) throw new Error(`GET ${cfg.bucket}/${key} HTTP ${res.status}`);
	return Buffer.from(await res.arrayBuffer());
}

async function putObject(cfg, key, body, contentType) {
	const res = await s3Fetch(cfg, "PUT", key, { headers: { "content-type": contentType, "content-length": String(body.length) }, body });
	if (!res.ok) throw new Error(`PUT ${cfg.bucket}/${key} HTTP ${res.status}`);
}

// ---------------------------------------------------------------- main

function argValue(argv, name) {
	const i = argv.indexOf(name);
	return i >= 0 && i + 1 < argv.length ? argv[i + 1] : "";
}

async function main(argv) {
	if (argv.includes("--help") || argv.includes("-h")) {
		console.log("Usage: node scripts/publish-lex-bundles-to-r2.mjs [--dry-run] [--lex <regex>] [--bundle <regex>]\nSee the file header for the environment variables.");
		return;
	}
	const dryRun = argv.includes("--dry-run") || argv.includes("-n");
	const lexFilter = argValue(argv, "--lex") ? new RegExp(argValue(argv, "--lex"), "i") : undefined;
	const bundleFilter = argValue(argv, "--bundle") ? new RegExp(argValue(argv, "--bundle")) : undefined;
	const dest = r2Config();
	const sourceKind = env("SOURCE", "r2").toLowerCase();
	const source = sourceKind === "s3" ? s3Config() : dest;
	const prefixes = sourceKind === "s3" ? [source.prefix] : [dest.prefix + "org/lucee/", dest.prefix + "snapshots/org/lucee/"];

	let lexKeys = [];
	for (const p of prefixes) {
		console.log(`listing ${sourceKind}://${source.bucket}/${p}`);
		lexKeys.push(...(await listKeys(source, p)).filter(isLexKey));
	}
	if (lexFilter) lexKeys = lexKeys.filter((k) => lexFilter.test(k));
	console.log(`found ${lexKeys.length} .lex files`);

	let written = 0;
	let skipped = 0;
	let failed = 0;
	const seen = new Set();
	let n = 0;
	for (const key of lexKeys) {
		n++;
		let bundles;
		try {
			bundles = bundlesOfLex(await getObject(source, key));
		} catch (e) {
			failed++;
			console.log(`skip ${key}: ${e instanceof Error ? e.message : e}`);
			continue;
		}
		const plan = await planPublish([{ key, bundles: bundles.filter((b) => !seen.has(bundleKey(b.name, b.version))) }], (k) => exists(dest, k), { prefix: dest.prefix, bundleFilter });
		for (const b of bundles) seen.add(bundleKey(b.name, b.version));
		skipped += plan.skip.length;
		for (const item of plan.write) {
			if (dryRun) {
				console.log(`DRY RUN would write ${item.key} (${item.data.length} bytes, from ${item.lex})`);
			} else {
				await putObject(dest, item.key, item.data, "application/java-archive");
				await putObject(dest, item.pomKey, Buffer.from(pomFor(item.name, item.version)), "application/xml");
				console.log(`wrote ${item.key}`);
			}
			written++;
		}
		if (n % 100 === 0) console.log(`progress ${n}/${lexKeys.length} lex files`);
	}
	console.log(`${dryRun ? "dry run: would write" : "done: wrote"} ${written} bundle jars, ${skipped} already there, ${failed} lex files unreadable`);
}

const isMain = process.argv[1]?.endsWith("publish-lex-bundles-to-r2.mjs");
if (isMain) {
	main(process.argv.slice(2)).catch((e) => {
		console.error(e instanceof Error ? e.message : e);
		process.exit(1);
	});
}
