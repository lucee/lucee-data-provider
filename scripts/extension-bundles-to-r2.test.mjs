// node --test scripts/extension-bundles-to-r2.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { deflateRawSync } from "node:zlib";
import { createHash } from "node:crypto";
import {
	lexUrl, redact, requiredBundles, collectBundles, planObjects, providerState, signedRequest, r2Config, summaryTable, run, USER_AGENT
} from "./extension-bundles-to-r2.mjs";
import { parseManifest, bundleKey } from "./publish-lex-bundles-to-r2.mjs";

// minimal zip writer (deflated entries) for the fixtures
function zip(files) {
	const locals = [];
	const centrals = [];
	let offset = 0;
	for (const [name, content] of Object.entries(files)) {
		const raw = Buffer.from(content);
		const data = deflateRawSync(raw);
		const n = Buffer.from(name);
		const l = Buffer.alloc(30);
		l.writeUInt32LE(0x04034b50, 0); l.writeUInt16LE(20, 4); l.writeUInt16LE(8, 8);
		l.writeUInt32LE(data.length, 18); l.writeUInt32LE(raw.length, 22); l.writeUInt16LE(n.length, 26);
		const c = Buffer.alloc(46);
		c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6); c.writeUInt16LE(8, 10);
		c.writeUInt32LE(data.length, 20); c.writeUInt32LE(raw.length, 24); c.writeUInt16LE(n.length, 28); c.writeUInt32LE(offset, 42);
		locals.push(l, n, data);
		centrals.push(c, n);
		offset += 30 + n.length + data.length;
	}
	const cd = Buffer.concat(centrals);
	const e = Buffer.alloc(22);
	e.writeUInt32LE(0x06054b50, 0); e.writeUInt16LE(centrals.length / 2, 8); e.writeUInt16LE(centrals.length / 2, 10);
	e.writeUInt32LE(cd.length, 12); e.writeUInt32LE(offset, 16);
	return Buffer.concat([...locals, cd, e]);
}
const jar = (bsn, version) => zip({ "META-INF/MANIFEST.MF": `Manifest-Version: 1.0\r\nBundle-SymbolicName: ${bsn}\r\nBundle-Version: ${version}\r\n\r\n`, "a/B.class": "x" });

const AXIS_MF = `Manifest-Version: 1.0
version: "1.4.0.27-SNAPSHOT"
id: "DF28D0A4-6748-44B9-A2FDC12E4E2E4D38"
name: Axis 1 Webservices
webservice: "{'class':'org.lucee.extension.axis.Axis1Handler','name':'org.lucee.axis.extension','version':'1.4.0.27-SNAPSHOT'}"
`;
const axisLex = () => zip({
	"META-INF/MANIFEST.MF": AXIS_MF,
	"jars/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar": jar("org.lucee.axis.extension;singleton:=true", "1.4.0.27-SNAPSHOT"),
	"jars/org.lucee.axis-1.4.0.L0002.jar": jar("org.lucee.axis", "1.4.0.L0002"),
	"jars/plain.jar": zip({ "META-INF/MANIFEST.MF": "Manifest-Version: 1.0\n" })
});

test("lexUrl maps Maven coordinates and keeps https URLs", () => {
	assert.equal(lexUrl("org.lucee:axis-extension:1.4.0.27-SNAPSHOT"),
		"https://maven.lucee-services.com/org/lucee/axis-extension/1.4.0.27-SNAPSHOT/axis-extension-1.4.0.27-SNAPSHOT.lex");
	assert.equal(lexUrl("https://example.org/x.lex"), "https://example.org/x.lex");
	assert.throws(() => lexUrl("http://example.org/x.lex"), /https/);
	assert.throws(() => lexUrl("org.lucee:../x:1"), /neither/);
	assert.throws(() => lexUrl(""), /required/);
});

test("redact never prints a query string (presigned URLs)", () => {
	assert.equal(redact("https://b.s3.amazonaws.com/a.lex?X-Amz-Signature=abc&X-Amz-Credential=AKIA"), "https://b.s3.amazonaws.com/a.lex?…");
	assert.equal(redact("https://h/p.jar"), "https://h/p.jar");
});

test("requiredBundles reads jdbc, webservice and cache entries", () => {
	const r = requiredBundles(parseManifest(`${AXIS_MF}jdbc: "[{'id':'mssql','class':'com.microsoft.sqlserver.jdbc.SQLServerDriver','bundleName':'mssqljdbc4','bundleVersion':'4.0.2206.100'}]"
cache: "[{'class':'x.Y','bundle-name':'org.lucee.ehcache','bundle-version':'2.10.0.33'}]"
`));
	assert.deepEqual(r.map((b) => `${b.name}@${b.version}`).sort(),
		["mssqljdbc4@4.0.2206.100", "org.lucee.axis.extension@1.4.0.27-SNAPSHOT", "org.lucee.ehcache@2.10.0.33"]);
});

test("collectBundles merges shipped and required bundles", () => {
	const lex = zip({ "META-INF/MANIFEST.MF": AXIS_MF + `jdbc: "[{'class':'D','bundleName':'not.shipped','bundleVersion':'1.0'}]"\n`,
		"jars/ext.jar": jar("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT") });
	const { extension, bundles } = collectBundles(lex);
	assert.equal(extension.version, "1.4.0.27-SNAPSHOT");
	const ext = bundles.find((b) => b.name === "org.lucee.axis.extension");
	assert.ok(ext.shipped && ext.required && ext.jar);
	const ns = bundles.find((b) => b.name === "not.shipped");
	assert.ok(!ns.shipped && ns.required && ns.jar === null);
	// shipped jar with a directive in Bundle-SymbolicName (read by bundlesOfLex)
	assert.ok(collectBundles(axisLex()).bundles.some((b) => b.name === "org.lucee.axis.extension" && b.shipped));
	assert.equal(collectBundles(axisLex()).notBundles[0], "jars/plain.jar");
});

test("planObjects: org.lucee:<BSN>:<version>, SNAPSHOT on the plain key, checksums", () => {
	const body = Buffer.from("jar-bytes");
	const objs = planObjects("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT", body, "p/");
	assert.deepEqual(objs.map((o) => o.key), [
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar",
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar.sha1",
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar.md5",
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.pom",
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.pom.sha1",
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.pom.md5"
	]);
	assert.equal(objs[1].body.toString(), createHash("sha1").update(body).digest("hex"));
	assert.equal(objs[2].body.toString(), createHash("md5").update(body).digest("hex"));
	assert.match(objs[3].body.toString(), /<artifactId>org.lucee.axis.extension<\/artifactId>/);
	assert.equal(bundleKey("../evil", "1"), "");
	assert.throws(() => planObjects("a b", "1", body), /Maven path/);
});

test("providerState", () => {
	assert.equal(providerState(302, "https://repo1.maven.org/x.jar").state, "present");
	assert.equal(providerState(302, "https://s3/x.jar?X-Amz-Signature=s").detail, "https://s3/x.jar?…");
	assert.equal(providerState(404).state, "missing");
	assert.equal(providerState(500).state, "error");
});

test("signedRequest signs If-None-Match and keeps the secret out of the headers", () => {
	const cfg = { endpoint: "https://acc.r2.cloudflarestorage.com", bucket: "b", accessKeyId: "AK", secretAccessKey: "SECRET" };
	const { url, init } = signedRequest(cfg, "PUT", "org/lucee/a/1/a-1.jar", { body: Buffer.from("x"), headers: { "if-none-match": "*" } }, new Date("2026-11-27T00:00:00Z"));
	assert.equal(url, "https://acc.r2.cloudflarestorage.com/b/org/lucee/a/1/a-1.jar");
	assert.match(init.headers.authorization, /Credential=AK\/20261127\/auto\/s3\/aws4_request, SignedHeaders=host;if-none-match;x-amz-content-sha256;x-amz-date, Signature=[0-9a-f]{64}$/);
	assert.ok(!JSON.stringify(init.headers).includes("SECRET"));
	assert.throws(() => r2Config({ R2_BUCKET: "b" }), /R2_ENDPOINT/);
});

test("summaryTable", () => {
	assert.match(summaryTable([{ name: "a", version: "1", from: "jars/", status: "present", detail: "x|y" }]), /\| a \| 1 \| jars\/ \| present \| x\\\|y \|/);
});

// fetch stub: provider, repository and R2
function stubFetch({ provider = {}, repo = new Set(), r2 = new Map(), lex }) {
	const calls = [];
	globalThis.fetch = async (url, init = {}) => {
		const method = init.method ?? "GET";
		calls.push({ url, method, headers: init.headers ?? {} });
		const res = (status, headers = {}, body = null) => ({ status, ok: status >= 200 && status < 300, url, headers: new Headers(headers), arrayBuffer: async () => body, text: async () => "" });
		if (url.endsWith(".lex")) return res(200, { "content-length": String(lex.length) }, lex);
		if (url.includes("/rest/update/provider/download/")) {
			const k = decodeURIComponent(url.split("/download/")[1]);
			return provider[k] ? res(302, { location: provider[k] }) : res(404);
		}
		if (url.startsWith("https://r2.test/")) {
			const key = url.slice("https://r2.test/bucket/".length);
			if (method === "HEAD") return res(r2.has(key) ? 200 : 404);
			if (r2.has(key)) return res(412);
			r2.set(key, init.body);
			return res(200);
		}
		if (url.startsWith("https://maven.test/")) return res(repo.has(url.slice("https://maven.test/".length)) ? 200 : 404);
		throw new Error(`unexpected ${method} ${url}`);
	};
	return calls;
}

const baseEnv = { EXTENSION: "org.lucee:axis-extension:1.4.0.27-SNAPSHOT", MAVEN_REPO: "https://maven.test", PROVIDER_URL: "https://upd.test/rest/update/provider/download/" };

test("dry run: reports, writes nothing, sends the user agent", async () => {
	const calls = stubFetch({ lex: axisLex(), provider: { "org.lucee.axis/1.4.0.L0002": "https://maven.test/org/lucee/axis/1.4.0.L0002/axis-1.4.0.L0002.jar" } });
	const out = await run({ ...baseEnv }, () => {});
	const by = Object.fromEntries(out.rows.map((r) => [r.name, r.status]));
	assert.deepEqual(by, { "org.lucee.axis": "present", "org.lucee.axis.extension": "would-upload" });
	assert.ok(out.dryRun);
	assert.ok(!calls.some((c) => c.method === "PUT" || c.url.startsWith("https://r2.test/")));
	assert.ok(calls.every((c) => c.headers["user-agent"] === USER_AGENT));
});

test("write mode uploads missing jars once and never overwrites", async () => {
	const r2 = new Map();
	const env = { ...baseEnv, DRY_RUN: "false", R2_ENDPOINT: "https://r2.test", R2_BUCKET: "bucket", R2_ACCESS_KEY_ID: "a", R2_SECRET_ACCESS_KEY: "s" };
	const key = "org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar";
	// a checksum is already there: it is kept (412), the rest is written
	r2.set(key + ".md5", "keep");
	stubFetch({ lex: axisLex(), r2 });
	let out = await run(env, () => {});
	const row = out.rows.find((r) => r.name === "org.lucee.axis.extension");
	assert.equal(row.status, "uploaded");
	assert.match(row.detail, /5\/6 objects written/);
	assert.equal(r2.get(key + ".md5"), "keep");
	assert.ok(r2.has(key) && r2.has(key.replace(/\.jar$/, ".pom")));
	// second run: the jar is in R2, nothing is written
	const calls = stubFetch({ lex: axisLex(), r2 });
	out = await run(env, () => {});
	assert.equal(out.rows.find((r) => r.name === "org.lucee.axis.extension").status, "present");
	assert.ok(!calls.some((c) => c.method === "PUT"));
});

test("a required bundle that is not in the lex and not on the provider is unresolvable", async () => {
	const lex = zip({ "META-INF/MANIFEST.MF": `Manifest-Version: 1.0\nversion: "1"\njdbc: "[{'class':'D','bundleName':'gone','bundleVersion':'1.0'}]"\n` });
	stubFetch({ lex });
	const out = await run({ ...baseEnv }, () => {});
	assert.equal(out.rows[0].status, "unresolvable");
	assert.equal(out.failed, 0);
});
