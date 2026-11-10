#!/usr/bin/env node
// Records the fixtures of test/compat.test.ts from the live CFML provider and its sources. Read-only (GET).
//
//   node scripts/record-fixtures.mjs
//
// Writes test/fixtures/compat.json:
// - meta:      the rows of a few extensions from <ext.lucee.org>/extensions.json (logos only for one)
// - state:     extensions-maven.json
// - upstream:  the Maven metadata and listings the worker reads for them, by url
// - responses: the answers of https://extension.lucee.org/rest/extension/provider/... for them
//              (lists filtered to these extensions)
import { writeFileSync } from "node:fs";

const LIVE = "https://extension.lucee.org/rest/extension/provider";
const EXT_CDN = "https://ext.lucee.org/";
const CDN = "https://cdn.lucee.org/org/lucee/";
const REPOS = ["https://repo1.maven.org/maven2/", "https://central.sonatype.com/repository/maven-snapshots/", "https://maven.lucee-services.com/"];
const IDS = {
	"D46D49C3-EB85-8D97-30BEC2F38561E985": "documentation-extension",
	"60772C12-F179-D555-8E2CD2B4F7428718": "redis-extension",
	"6E2CB28F-98FB-4B51-B6BE6C64ADF35473": "ajax-extension",
	"37C61C0A-5D7E-4256-8572639BE0CF5838": "esapi-extension",
	"DFE10517-14CE-4D8B-89A68091D9A6C81E": "athena-jdbc-extension"
};
const WITH_LOGO = "D46D49C3-EB85-8D97-30BEC2F38561E985";

async function get(url, manual = false) {
	const res = await fetch(url, { redirect: manual ? "manual" : "follow", headers: { "user-agent": "lucee-data-provider fixture recorder" } });
	return { status: res.status, location: res.headers.get("location"), contentType: res.headers.get("content-type"), body: await res.text() };
}

const upstream = {};
async function record(url) {
	if (upstream[url]) return upstream[url];
	const res = await get(url);
	upstream[url] = { status: res.status, body: res.status === 200 ? res.body : "" };
	return upstream[url];
}

const meta = JSON.parse((await get(EXT_CDN + "extensions.json")).body);
const imageCol = meta.COLUMNS.indexOf("image");
meta.DATA = meta.DATA.filter((r) => IDS[r[0]]).map((r) => (r[0] === WITH_LOGO ? r : r.map((v, i) => (i === imageCol ? "" : v))));
const state = JSON.parse((await get(EXT_CDN + "extensions-maven.json")).body);

await record(CDN + "maven-metadata.xml");
for (const repo of REPOS) await record(repo + "org/lucee/");
for (const artifact of Object.values(IDS)) {
	await record(`${CDN}${artifact}/maven-metadata.xml`);
	for (const repo of REPOS) await record(`${repo}org/lucee/${artifact}/maven-metadata.xml`);
}

const filterList = (body) => {
	const json = JSON.parse(body);
	json.EXTENSIONS.DATA = json.EXTENSIONS.DATA.filter((r) => IDS[r[0]]);
	return JSON.stringify(json);
};

const paths = [
	"/info?withLogo=false",
	"/info?withLogo=false&type=all",
	"/info?withLogo=false&type=snapshot",
	"/info?withLogo=false&type=abc",
	"/info?withLogo=false&type=all&coreVersion=7.1.2.191",
	"/info?withLogo=false&coreVersion=5.3.0.1",
	`/info/${WITH_LOGO}`,
	"/info/NOPE-NOPE",
	"/info/NOPE-NOPE?version=1.0.0.0",
	"/full/NOPE-NOPE",
	`/trial/${WITH_LOGO}`
];
for (const id of Object.keys(IDS)) {
	paths.push(
		`/info/${id}?withLogo=false`,
		`/info/${id}?withLogo=false&type=all`,
		`/info/${id}?withLogo=false&coreVersion=5.3.0.1`,
		`/full/${id}`,
		`/full/${id}?type=snapshot`,
		`/full/${id}?type=abc`,
		`/full/${id}?coreVersion=7.1.2.191`
	);
}
// the oldest version of every extension, asked for explicitly
const versionsById = new Map();
for (const r of meta.DATA) versionsById.set(r[0], [...(versionsById.get(r[0]) ?? []), r[1]]);
for (const [id, versions] of versionsById) {
	const oldest = versions[versions.length - 1];
	paths.push(`/info/${id}?withLogo=false&version=${encodeURIComponent(oldest)}`, `/full/${id}?version=${encodeURIComponent(oldest)}`);
}

const responses = [];
for (const path of [...new Set(paths)]) {
	const res = await get(LIVE + path, true);
	const body = res.status === 200 && path.startsWith("/info?") ? filterList(res.body) : res.body;
	responses.push({ path, status: res.status, location: res.location, contentType: res.contentType, body });
	// the maven-metadata.xml of a snapshot version the provider redirects to
	const m = res.location && /^(.*\/org\/lucee\/([^/]+)\/([^/]+-SNAPSHOT)\/)/.exec(res.location);
	if (m) for (const repo of [...REPOS, "https://cdn.lucee.org/"]) await record(`${repo}org/lucee/${m[2]}/${m[3]}/maven-metadata.xml`);
	console.log(res.status, path, res.location ?? "");
}

writeFileSync(new URL("../test/fixtures/compat.json", import.meta.url), JSON.stringify({ recordedAt: new Date().toISOString(), meta, state, upstream, responses }, null, 1) + "\n");
console.log(`recorded ${responses.length} responses, ${Object.keys(upstream).length} upstream files`);
