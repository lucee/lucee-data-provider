#!/usr/bin/env node
// Compares the answers of a running extension worker (e.g. `npm run dev`) with the CFML provider.
// Read-only: only GET requests to the info, full and trial endpoints.
//
//   node scripts/compare.mjs [workerBase] [liveBase]
//   defaults: http://127.0.0.1:8787  https://extension.lucee.org
//
// The host name in the META of the worker is replaced with the live one before comparing. Rows of
// extensions that only one side has are reported, not counted as a difference (the two sides read their
// sources at different times).
const worker = (process.argv[2] ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const live = (process.argv[3] ?? "https://extension.lucee.org").replace(/\/$/, "");
const liveHost = new URL(live).host;
const workerHost = new URL(worker).host;
const BASE = "/rest/extension/provider";

async function get(base, path) {
	const res = await fetch(base + path, { redirect: "manual" });
	let body = await res.text();
	// fetch can't set the Host header: the META of the worker names the host it was asked on
	if (base === worker) body = body.split(workerHost).join(liveHost);
	return { status: res.status, location: res.headers.get("location"), type: res.headers.get("content-type"), body };
}

let failures = 0;
const fail = (msg) => {
	failures++;
	console.log("  DIFF " + msg);
};

function compareQueries(path, a, b) {
	if (JSON.stringify(a.COLUMNS) !== JSON.stringify(b.COLUMNS)) return fail(`${path}: columns differ`);
	const idx = (q) => new Map(q.DATA.map((r) => [r[0], r]));
	const A = idx(a);
	const B = idx(b);
	const onlyLive = [...A.keys()].filter((k) => !B.has(k));
	const onlyWorker = [...B.keys()].filter((k) => !A.has(k));
	if (onlyLive.length || onlyWorker.length) console.log(`  note ${path}: only live ${JSON.stringify(onlyLive)}, only worker ${JSON.stringify(onlyWorker)}`);
	let diffs = 0;
	for (const [id, row] of A) {
		const other = B.get(id);
		if (!other) continue;
		a.COLUMNS.forEach((col, i) => {
			if (JSON.stringify(row[i]) !== JSON.stringify(other[i])) {
				diffs++;
				if (diffs <= 10) fail(`${path}: ${row[3]} ${col}: live ${JSON.stringify(row[i]).slice(0, 120)} worker ${JSON.stringify(other[i]).slice(0, 120)}`);
			}
		});
	}
	const order = (q, keep) => q.DATA.map((r) => r[0]).filter((id) => keep.has(id)).join(",");
	if (order(a, B) !== order(b, A)) fail(`${path}: order differs`);
	return diffs;
}

async function check(path, { json = true } = {}) {
	const [a, b] = await Promise.all([get(live, path), get(worker, path)]);
	console.log(`${path}  live ${a.status} worker ${b.status}`);
	if (a.status !== b.status) return fail(`${path}: status`);
	if (a.location !== b.location) return fail(`${path}: location live ${a.location} worker ${b.location}`);
	if (a.status !== 200 || !json) {
		if (a.body !== b.body) fail(`${path}: body live ${JSON.stringify(a.body)} worker ${JSON.stringify(b.body)}`);
		return;
	}
	const x = JSON.parse(a.body);
	const y = JSON.parse(b.body);
	if (x.EXTENSIONS) {
		if (JSON.stringify(x.META) !== JSON.stringify(y.META)) fail(`${path}: META differs`);
		compareQueries(path, x.EXTENSIONS, y.EXTENSIONS);
	} else if (a.body !== b.body) {
		for (const k of Object.keys(x)) if (JSON.stringify(x[k]) !== JSON.stringify(y[k])) fail(`${path}: ${k}: live ${JSON.stringify(x[k]).slice(0, 120)} worker ${JSON.stringify(y[k]).slice(0, 120)}`);
		if (JSON.stringify(Object.keys(x)) !== JSON.stringify(Object.keys(y))) fail(`${path}: keys or key order differ`);
	}
}

const lists = [
	"/info?withLogo=false",
	"/info",
	"/info?withLogo=false&type=all",
	"/info?withLogo=false&type=snapshot",
	"/info?withLogo=false&type=abc",
	"/info?type=all&coreVersion=7.1.2.191",
	"/info?withLogo=false&coreVersion=6.2.9.4",
	"/info?withLogo=false&coreVersion=5.3.0.1",
	"/info?withLogo=false&type=all&coreVersion=8.0.0.304"
];
for (const p of lists) await check(BASE + p);

// details and downloads of every listed extension, a few ways
const listing = JSON.parse((await get(live, BASE + "/info?withLogo=false&type=all")).body).EXTENSIONS;
const ids = listing.DATA.map((r) => r[0]).filter((id) => id.length);
const olderCol = listing.COLUMNS.indexOf("older");
for (const id of ids) {
	await check(`${BASE}/info/${id}`);
	await check(`${BASE}/info/${id}?withLogo=false&coreVersion=7.1.2.191`);
	await check(`${BASE}/full/${id}`, { json: false });
	await check(`${BASE}/full/${id}?coreVersion=6.2.9.4`, { json: false });
	await check(`${BASE}/full/${id}?type=snapshot`, { json: false });
	const row = listing.DATA.find((r) => r[0] === id);
	const older = row[olderCol];
	if (Array.isArray(older) && older.length) {
		await check(`${BASE}/info/${id}?withLogo=false&version=${encodeURIComponent(older[older.length - 1])}`);
		await check(`${BASE}/full/${id}?version=${encodeURIComponent(older[0])}`, { json: false });
	}
}
await check(`${BASE}/info/NOPE-NOPE`, { json: false });
await check(`${BASE}/info/NOPE-NOPE?version=1.0.0.0`, { json: false });
await check(`${BASE}/full/NOPE-NOPE`, { json: false });
await check(`${BASE}/trial/${ids[0]}`, { json: false });

console.log(failures ? `\n${failures} difference(s)` : "\nno differences");
process.exitCode = failures ? 1 : 0;
