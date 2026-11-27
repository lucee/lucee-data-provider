// node --test scripts/publish-lex-bundles-to-r2.test.mjs
import { test } from "node:test";
import assert from "node:assert/strict";
import { deflateRawSync } from "node:zlib";
import { bundleKey, bundleOfJar, bundlesOfLex, isLexKey, parseManifest, planPublish, pomFor, zipEntries, zipRead } from "./publish-lex-bundles-to-r2.mjs";

// minimal zip writer (stored or deflated entries, no CRC check on read)
function zip(files, { deflate = true } = {}) {
	const locals = [];
	const centrals = [];
	let offset = 0;
	for (const [name, content] of Object.entries(files)) {
		const raw = Buffer.isBuffer(content) ? content : Buffer.from(content);
		const data = deflate ? deflateRawSync(raw) : raw;
		const nameBuf = Buffer.from(name);
		const local = Buffer.alloc(30);
		local.writeUInt32LE(0x04034b50, 0);
		local.writeUInt16LE(deflate ? 8 : 0, 8);
		local.writeUInt32LE(data.length, 18);
		local.writeUInt32LE(raw.length, 22);
		local.writeUInt16LE(nameBuf.length, 26);
		const central = Buffer.alloc(46);
		central.writeUInt32LE(0x02014b50, 0);
		central.writeUInt16LE(deflate ? 8 : 0, 10);
		central.writeUInt32LE(data.length, 20);
		central.writeUInt32LE(raw.length, 24);
		central.writeUInt16LE(nameBuf.length, 28);
		central.writeUInt32LE(offset, 42);
		locals.push(local, nameBuf, data);
		centrals.push(central, nameBuf);
		offset += 30 + nameBuf.length + data.length;
	}
	const cd = Buffer.concat(centrals);
	const eocd = Buffer.alloc(22);
	eocd.writeUInt32LE(0x06054b50, 0);
	eocd.writeUInt16LE(Object.keys(files).length, 8);
	eocd.writeUInt16LE(Object.keys(files).length, 10);
	eocd.writeUInt32LE(cd.length, 12);
	eocd.writeUInt32LE(offset, 16);
	return Buffer.concat([...locals, cd, eocd]);
}

const manifest = (name, version) => `Manifest-Version: 1.0\r\nBundle-ManifestVersion: 2\r\nBundle-SymbolicName: ${name};singleton:=true\r\nBundle-Version: ${version}\r\n\r\n`;

test("zip entries can be read, stored and deflated", () => {
	for (const deflate of [true, false]) {
		const z = zip({ "a.txt": "hello", "b/c.txt": "world" }, { deflate });
		const entries = zipEntries(z);
		assert.deepEqual(entries.map((e) => e.name), ["a.txt", "b/c.txt"]);
		assert.equal(zipRead(z, entries[1]).toString(), "world");
	}
	assert.throws(() => zipEntries(Buffer.from("not a zip")), /not a zip/);
});

test("manifest continuation lines are joined, only the main section is read", () => {
	const m = parseManifest("Bundle-SymbolicName: org.lucee.very.long.na\r\n me.extension\r\nBundle-Version: 1.0\r\n\r\nName: x\r\nBundle-Version: 9\r\n");
	assert.equal(m["Bundle-SymbolicName"], "org.lucee.very.long.name.extension");
	assert.equal(m["Bundle-Version"], "1.0");
});

test("bundle name and version come from the jar manifest, directives dropped", () => {
	const jar = zip({ "META-INF/MANIFEST.MF": manifest("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT"), "x.class": "x" });
	assert.deepEqual(bundleOfJar(jar), { name: "org.lucee.axis.extension", version: "1.4.0.27-SNAPSHOT" });
	assert.equal(bundleOfJar(zip({ "META-INF/MANIFEST.MF": "Manifest-Version: 1.0\r\n" })), undefined);
});

test("bundles of a lex: only jars/*.jar with an OSGi manifest", () => {
	const lex = zip({
		"META-INF/MANIFEST.MF": "Manifest-Version: 1.0\r\nid: \"X\"\r\n",
		"jars/mssqljdbc4-4-0-2206-100.jar": zip({ "META-INF/MANIFEST.MF": manifest("mssqljdbc4", "4.0.2206.100") }),
		"jars/plain.jar": zip({ "META-INF/MANIFEST.MF": "Manifest-Version: 1.0\r\n" }),
		"jars/broken.jar": "not a jar",
		"context/jars/other.jar": zip({ "META-INF/MANIFEST.MF": manifest("other", "1.0") })
	});
	const bundles = bundlesOfLex(lex);
	assert.deepEqual(bundles.map((b) => [b.path, b.name, b.version]), [["jars/mssqljdbc4-4-0-2206-100.jar", "mssqljdbc4", "4.0.2206.100"]]);
});

test("bundle keys use the org.lucee:<Bundle-SymbolicName> layout, SNAPSHOT in the plain layout too", () => {
	assert.equal(bundleKey("mssqljdbc4", "4.0.2206.100"), "org/lucee/mssqljdbc4/4.0.2206.100/mssqljdbc4-4.0.2206.100.jar");
	assert.equal(
		bundleKey("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT", "pom", "p"),
		"p/org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.pom"
	);
	assert.equal(bundleKey("../x", "1"), "");
	assert.equal(bundleKey("x", "1/2"), "");
	assert.match(pomFor("mssqljdbc4", "4.0.2206.100"), /<artifactId>mssqljdbc4<\/artifactId>[\s\S]*<version>4.0.2206.100<\/version>/);
	assert.ok(isLexKey("org/lucee/axis-extension/1.5.0.6/axis-extension-1.5.0.6.lex"));
	assert.ok(!isLexKey("org/lucee/axis-extension/1.5.0.6/axis-extension-1.5.0.6.pom"));
});

test("plan: existing keys are skipped, duplicates written once, filter applied", async () => {
	const b = (name, version) => ({ name, version, data: Buffer.from(name) });
	const existing = new Set(["org/lucee/org.lucee.axis/1.4.0.L0002/org.lucee.axis-1.4.0.L0002.jar"]);
	const plan = await planPublish(
		[
			{ key: "a.lex", bundles: [b("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT"), b("org.lucee.axis", "1.4.0.L0002"), b("bad/name", "1")] },
			{ key: "b.lex", bundles: [b("org.lucee.axis.extension", "1.4.0.27-SNAPSHOT"), b("mssqljdbc4", "4.0.2206.100")] }
		],
		async (k) => existing.has(k)
	);
	assert.deepEqual(plan.write.map((w) => [w.lex, w.key]), [
		["a.lex", "org/lucee/org.lucee.axis.extension/1.4.0.27-SNAPSHOT/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar"],
		["b.lex", "org/lucee/mssqljdbc4/4.0.2206.100/mssqljdbc4-4.0.2206.100.jar"]
	]);
	assert.equal(plan.skip.length, 1);
	assert.equal(plan.unsafe.length, 1);
	const filtered = await planPublish([{ key: "b.lex", bundles: [b("mssqljdbc4", "4.0.2206.100"), b("org.lucee.axis", "1")] }], async () => false, { bundleFilter: /^mssql/ });
	assert.deepEqual(filtered.write.map((w) => w.name), ["mssqljdbc4"]);
});
