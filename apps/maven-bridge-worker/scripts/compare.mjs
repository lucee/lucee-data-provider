#!/usr/bin/env node
// Compares two Maven bridge hosts path by path: status, Location and body hash.
//
//   node scripts/compare.mjs [--prod https://maven.lucee-services.com] [--target https://mvn.lucee-services.com]
//                            [--paths paths.txt] [--method GET|HEAD] [--strict] [--verbose]
//
// paths.txt: one path per line, "#" comments. Without --paths a default set is used.
// Generated timestamps (<lastUpdated>, <timestamp>, landing/health dates) are normalized
// before hashing unless --strict is given. Exit code 1 when any path differs.
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
	const i = args.indexOf(name);
	return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const flag = (name) => args.includes(name);

const prod = opt("--prod", "https://maven.lucee-services.com").replace(/\/+$/, "");
const target = opt("--target", "https://mvn.lucee-services.com").replace(/\/+$/, "");
const method = opt("--method", "GET").toUpperCase();
const strict = flag("--strict");
const verbose = flag("--verbose");
const timeoutMs = Number(opt("--timeout", "60")) * 1000;

const DEFAULT_PATHS = [
	"/org/lucee",
	"/org/lucee/maven-metadata.xml",
	"/org/lucee/lucee/maven-metadata.xml",
	"/org/lucee/lucee/6.2.0.321",
	"/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.pom",
	"/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar",
	"/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar",
	"/org/lucee/lucee/7.0.0.395/lucee-7.0.0.395.jar",
	"/org/lucee/redis-extension/maven-metadata.xml",
	"/io/forgebox",
	"/io/forgebox/maven-metadata.xml",
	"/io/forgebox/ortus-mongodb-cache-extension",
	"/io/forgebox/ortus-mongodb-cache-extension/maven-metadata.xml",
	"/io/forgebox/ortus-mongodb-cache-extension/1.2.0.5291",
	"/io/forgebox/ortus-mongodb-cache-extension/1.2.0.5291/ortus-mongodb-cache-extension-1.2.0.5291.pom",
	"/io/forgebox/ortus-mongodb-cache-extension/1.2.0.5291/ortus-mongodb-cache-extension-1.2.0.5291.lex",
	"/io/forgebox/nope-extension/1/nope-extension-1.lex",
	"/com/example/unknown"
];

async function loadPaths() {
	const file = opt("--paths", "");
	if (!file) return DEFAULT_PATHS;
	return (await readFile(file, "utf8"))
		.split(/\r?\n/)
		.map((l) => l.replace(/#.*/, "").trim())
		.filter(Boolean);
}

function normalize(body) {
	if (strict) return body;
	return body
		.replace(/<lastUpdated>\d+<\/lastUpdated>/g, "<lastUpdated/>")
		.replace(/<timestamp>[\d.]+<\/timestamp>/g, "<timestamp/>")
		.replace(/"(lastUpdated|lastupdated|generated)"\s*:\s*"[^"]*"/g, '"$1":""');
}

async function probe(host, path) {
	try {
		const res = await fetch(host + path, {
			method,
			redirect: "manual",
			headers: { "user-agent": "lucee-maven-bridge-compare" },
			signal: AbortSignal.timeout(timeoutMs)
		});
		const body = method === "HEAD" ? "" : await res.text();
		return {
			status: res.status,
			location: res.headers.get("location") ?? "",
			hash: createHash("sha256").update(normalize(body)).digest("hex").slice(0, 16),
			type: res.headers.get("content-type") ?? ""
		};
	} catch (e) {
		return { status: 0, location: "", hash: "", type: "", error: String(e?.message ?? e) };
	}
}

const paths = await loadPaths();
let differences = 0;
console.log(`compare ${method} ${prod} vs ${target} (${paths.length} paths${strict ? ", strict" : ""})`);
for (const path of paths) {
	const [a, b] = await Promise.all([probe(prod, path), probe(target, path)]);
	const diffs = [];
	if (a.status !== b.status) diffs.push(`status ${a.status} != ${b.status}`);
	if (a.location !== b.location) diffs.push(`location [${a.location}] != [${b.location}]`);
	if (a.hash !== b.hash) diffs.push(`body ${a.hash} != ${b.hash}`);
	if (a.error) diffs.push(`prod error: ${a.error}`);
	if (b.error) diffs.push(`target error: ${b.error}`);
	if (diffs.length) {
		differences++;
		console.log(`DIFF ${path}\n     ${diffs.join("\n     ")}`);
	} else {
		console.log(`OK   ${path}  ${a.status}${a.location ? " -> " + a.location : ""}${verbose ? "  " + a.hash + " " + a.type : ""}`);
	}
}
console.log(`\n${paths.length - differences}/${paths.length} identical`);
process.exit(differences ? 1 : 0);
