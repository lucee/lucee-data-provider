#!/usr/bin/env node
// Compares two skill hosts path by path: status, content type and body hash.
//
//   node scripts/compare.mjs [--prod https://skill.lucee-services.com] [--target https://skl.lucee-services.com]
//                            [--paths paths.txt] [--strict] [--verbose] [--timeout 60]
//
// paths.txt: one path per line, "#" comments. Without --paths a default set is used.
// Unless --strict is given, HTML is normalized before hashing: whitespace, character
// references (index.cfm encodes more characters), the host in the skill links and the
// "Updated" date. Error pages and the content type of /health.cfm (text/html on Cloud Run)
// differ by design, so only their status is compared. Exit code 1 when any path differs.
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
	const i = args.indexOf(name);
	return i >= 0 && args[i + 1] ? args[i + 1] : fallback;
};
const flag = (name) => args.includes(name);

const prod = opt("--prod", "https://skill.lucee-services.com").replace(/\/+$/, "");
const target = opt("--target", "https://skl.lucee-services.com").replace(/\/+$/, "");
const strict = flag("--strict");
const verbose = flag("--verbose");
const timeoutMs = Number(opt("--timeout", "60")) * 1000;

const DEFAULT_PATHS = [
	"/",
	"/index.cfm",
	"/main.skill",
	"/health.cfm",
	"/res/skill.css",
	"/res/lucee-logo.svg",
	"/res/favicon.png",
	"/res/byme.png",
	"/res/byme2.png",
	"/nope.skill",
	"/res/missing.png"
];

async function loadPaths() {
	const file = opt("--paths", "");
	if (!file) return DEFAULT_PATHS;
	return (await readFile(file, "utf8"))
		.split(/\r?\n/)
		.map((l) => l.replace(/#.*/, "").trim())
		.filter(Boolean);
}

const NAMED = { amp: "&", lt: "<", gt: ">", quot: '"', mdash: "\u2014", middot: "\u00b7", copy: "\u00a9" };

// Cloud Run answers health.cfm as text/html, the worker as text/plain
const TYPE_MAY_DIFFER = new Set(["/health.cfm"]);

function normalize(body, type) {
	if (strict || !type.startsWith("text/html")) return body;
	return body
		.replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
		.replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
		.replace(/&(amp|lt|gt|quot|mdash|middot|copy);/g, (_, n) => NAMED[n])
		.replace(/(class="skill-url"[^>]*>)https:\/\/[^/<]+\//g, "$1https://<host>/")
		.replace(/Updated [A-Z][a-z]{2} \d{1,2}, \d{4}/g, "Updated <date>")
		.replace(/\s+/g, " ")
		.replace(/> </g, "><")
		.trim();
}

async function probe(base, path) {
	try {
		const res = await fetch(base + path, {
			redirect: "manual",
			headers: { "user-agent": "lucee-skill-compare" },
			signal: AbortSignal.timeout(timeoutMs)
		});
		const type = (res.headers.get("content-type") ?? "").replace(/\s+/g, "").toLowerCase();
		const buf = Buffer.from(await res.arrayBuffer());
		const body = type.startsWith("text/html") ? normalize(buf.toString("utf8"), type) : buf;
		return {
			status: res.status,
			type: type.split(";")[0],
			hash: createHash("sha256").update(body).digest("hex").slice(0, 16)
		};
	} catch (e) {
		return { status: 0, type: "", hash: "", error: e instanceof Error ? e.message : String(e) };
	}
}

const paths = await loadPaths();
let differ = 0;
for (const path of paths) {
	const [a, b] = await Promise.all([probe(prod, path), probe(target, path)]);
	// error pages differ by design (Tomcat HTML vs plain text), only their status counts
	const error = a.status >= 400;
	const sameType = error || TYPE_MAY_DIFFER.has(path) || a.type === b.type;
	const same = a.status === b.status && sameType && (error || a.hash === b.hash);
	if (!same) differ++;
	if (!same || verbose) {
		const show = (r) => (r.error ? `error ${r.error}` : `${r.status} ${r.type} ${r.hash}`);
		console.log(`${same ? "same  " : "DIFFER"} ${path}\n  prod   ${show(a)}\n  target ${show(b)}`);
	}
}
console.log(`${paths.length - differ}/${paths.length} paths match (${prod} vs ${target})`);
process.exit(differ ? 1 : 0);
