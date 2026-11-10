// A small, made-up extension provider world: the extension meta, the Maven layout of the core bucket and
// three Maven repositories, as the worker sees them over http.
import { EMPTY_COLUMNS } from "../src/builder";
import { buildZip, type Route } from "./helpers";

export const EXT_CDN = "https://ext.lucee.org/";
export const CDN = "https://cdn.lucee.org/org/lucee/";
export const REPO1 = "https://repo1.maven.org/maven2/";
export const SNAPSHOTS = "https://central.sonatype.com/repository/maven-snapshots/";
export const MIXED = "https://maven.lucee-services.com/";

export const ALPHA = "AAAAAAAA-0000-0000-0000000000000001";
export const BRAVO = "BBBBBBBB-0000-0000-0000000000000002";
export const CHARLIE = "CCCCCCCC-0000-0000-0000000000000003";
export const DELTA = "DDDDDDDD-0000-0000-0000000000000004";

type R = Partial<Record<(typeof EMPTY_COLUMNS)[number], unknown>>;

function row(values: R): unknown[] {
	const defaults: R = { trial: false, image: "", packaging: "", releaseType: "server", created: "2026-01-01 10:00:00" };
	return EMPTY_COLUMNS.map((col) => (values[col] ?? defaults[col] ?? ""));
}

export const LOGO_BRAVO = "R0lGODlhAQABAAAAACw=";

export function metaJson(): string {
	return JSON.stringify({
		COLUMNS: EMPTY_COLUMNS,
		DATA: [
			// versionSortable deliberately wrong for one row: it is recomputed (LDEV-5699)
			row({ id: ALPHA, version: "2.0.0.1-SNAPSHOT", versionSortable: "", name: "Alpha", filename: "alpha-extension-2.0.0.1-SNAPSHOT.lex", minCoreVersion: "7.0.0.0" }),
			row({ id: ALPHA, version: "1.0.0.2", versionSortable: "01.000.000.0002.100", name: "Alpha", filename: "alpha-extension-1.0.0.2.lex", minCoreVersion: "6.0.0.0", created: "2026-03-01 10:00:00" }),
			row({ id: ALPHA, version: "1.0.0.1-RC", versionSortable: "01.000.000.0001.075", name: "Alpha", filename: "alpha-extension-1.0.0.1-RC.lex", minCoreVersion: "6.0.0.0" }),
			row({ id: ALPHA, version: "1.0.0.0", versionSortable: "01.000.000.0000.100", name: "Alpha", filename: "alpha.ext-1.0.0.0.lex", minCoreVersion: "5.0.0.0", created: "2025-01-01 10:00:00" }),
			row({ id: BRAVO, version: "3.0.0.0", versionSortable: "03.000.000.0000.100", name: "beta thing", filename: "bravo-3.0.0.0.lex", image: LOGO_BRAVO, category: "Misc" }),
			row({ id: CHARLIE, version: "1.0.0.0", versionSortable: "01.000.000.0000.100", name: "Charlie", filename: "charlie-extension-1.0.0.0.lex", minCoreVersion: "6.0.0.0", packaging: "maven" }),
			// a broken file without an id (it is not listed, like in the CFML version)
			row({ id: "", version: "", name: "", filename: "broken.lex" })
		]
	});
}

export const MAVEN_STATE = JSON.stringify({ SKIPPED: {}, ARTIFACTIDS: { "alpha-extension": ALPHA } });

export function metadata(artifact: string, versions: string[]): string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifactId>${artifact}</artifactId>
  <versioning>
    <versions>
${versions.map((v) => `      <version>${v}</version>`).join("\n")}
    </versions>
  </versioning>
</metadata>`;
}

export const GROUP_METADATA = `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifacts>
    <artifact><artifactId>alpha-extension</artifactId></artifact>
    <artifact><artifactId>charlie-extension</artifactId></artifact>
    <artifact><artifactId>lucee</artifactId></artifact>
  </artifacts>
</metadata>`;

export const SNAPSHOT_METADATA = `<?xml version="1.0" encoding="UTF-8"?>
<metadata modelVersion="1.1.0">
  <groupId>org.lucee</groupId>
  <artifactId>alpha-extension</artifactId>
  <version>2.0.0.1-SNAPSHOT</version>
  <versioning>
    <snapshotVersions>
      <snapshotVersion><classifier>lite</classifier><extension>lex</extension><value>2.0.0.1-20261101.101010-3</value></snapshotVersion>
      <snapshotVersion><extension>lex</extension><value>2.0.0.1-20261101.101010-3</value></snapshotVersion>
      <snapshotVersion><extension>pom</extension><value>2.0.0.1-20261101.101010-3</value></snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>`;

export function listing(names: string[]): string {
	return `<html><body><pre><a href="../">../</a>\n${names.map((n) => `<a href="${n}/" title="${n}/">${n}/</a>`).join("\n")}</pre></body></html>`;
}

export const DELTA_MANIFEST = [
	"Manifest-Version: 1.0",
	"Built-Date: 2026/11/01 10:00:00 UTC",
	'version: "1.0.0.0"',
	`id: "${DELTA}"`,
	'name: "Delta"',
	'description: "A description that is longer than one manifest line, so it is continued on the next line of the',
	'  manifest"',
	'lucee-core-version: "6.2.0.0"',
	"release-type: server",
	"",
	"Name: some/other/section",
	"id: not-this-one",
	""
].join("\r\n");

export const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4]);

export async function deltaLex(padding = 0): Promise<Uint8Array> {
	return buildZip(
		[
			{ name: "META-INF/", data: "" },
			{ name: "META-INF/MANIFEST.MF", data: DELTA_MANIFEST, deflate: true },
			{ name: "META-INF/logo.png", data: PNG },
			{ name: "jars/", data: "" },
			{ name: "jars/delta.jar", data: "jar", deflate: true }
		],
		padding
	);
}

/** the routes of this world, by url */
export async function world(extra: Record<string, Route> = {}): Promise<Record<string, Route>> {
	return {
		[EXT_CDN + "extensions.json"]: metaJson(),
		[EXT_CDN + "extensions-maven.json"]: MAVEN_STATE,
		// the Maven layout of the core bucket
		[CDN + "maven-metadata.xml"]: GROUP_METADATA,
		[CDN + "charlie-extension/maven-metadata.xml"]: metadata("charlie-extension", ["1.0.0.0"]),
		// the Maven repositories
		[REPO1 + "org/lucee/"]: listing(["alpha-extension", "delta-extension", "lucee"]),
		[SNAPSHOTS + "org/lucee/"]: new Response("no listing", { status: 404 }),
		[MIXED + "org/lucee/"]: listing(["alpha-extension"]),
		[REPO1 + "org/lucee/alpha-extension/maven-metadata.xml"]: metadata("alpha-extension", ["1.0.0.0", "1.0.0.2", "2.0.0.1-SNAPSHOT"]),
		[SNAPSHOTS + "org/lucee/alpha-extension/maven-metadata.xml"]: metadata("alpha-extension", ["2.0.0.1-SNAPSHOT"]),
		[MIXED + "org/lucee/alpha-extension/maven-metadata.xml"]: metadata("alpha-extension", ["1.0.0.2", "2.0.0.1-SNAPSHOT"]),
		[SNAPSHOTS + "org/lucee/alpha-extension/2.0.0.1-SNAPSHOT/maven-metadata.xml"]: SNAPSHOT_METADATA,
		[REPO1 + "org/lucee/delta-extension/maven-metadata.xml"]: metadata("delta-extension", ["1.0.0.0"]),
		[REPO1 + "org/lucee/delta-extension/1.0.0.0/delta-extension-1.0.0.0.lex"]: await deltaLex(),
		...extra
	};
}
