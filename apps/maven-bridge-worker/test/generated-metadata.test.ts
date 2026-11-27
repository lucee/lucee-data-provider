import { createExecutionContext, env, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { checksumOfText } from "../src/checksum";
import worker from "../src/index";
import { call, CDN, mockFetch, resetState, testEnv, type Route } from "./helpers";

const REDIS_UPSTREAM = `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifactId>redis-extension</artifactId>
  <versioning>
    <latest>3.0.0.1-SNAPSHOT</latest>
    <release>2.0.0.1</release>
    <versions>
      <version>2.0.0.1</version>
      <version>3.0.0.1-SNAPSHOT</version>
    </versions>
  </versioning>
</metadata>`;

const GROUP_UPSTREAM = `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifacts>
    <artifact>
      <artifactId>admin-extension</artifactId>
      <latest>1.0.0.0</latest>
      <release>1.0.0.0</release>
    </artifact>
    <artifact>
      <artifactId>redis-extension</artifactId>
      <latest>3.0.0.1-SNAPSHOT</latest>
      <release>2.0.0.1</release>
    </artifact>
  </artifacts>
  <lastUpdated>20260101000000</lastUpdated>
</metadata>`;

const INDEX_UPSTREAM = `<!DOCTYPE html>
<html><body><pre id="contents">
<a href="../">../</a>
<a href="maven-metadata.xml" title="maven-metadata.xml">maven-metadata.xml                                </a>                     2026-01-01 00:00         -      
<a href="admin-extension/" title="admin-extension/">admin-extension/                                  </a>                     2026-01-01 00:00         -      
<a href="lucee/" title="lucee/">lucee/                                            </a>                     2026-01-01 00:00         -      
<a href="redis-extension/" title="redis-extension/">redis-extension/                                  </a>                     2026-01-01 00:00         -      
</pre></body></html>`;

async function putMaven(key: string, body = "x"): Promise<void> {
	await (env as unknown as { ARTIFACTS: R2Bucket }).ARTIFACTS.put(key, body);
}

function routes(): Record<string, Route | string> {
	return {
		[`${CDN}org/lucee/redis-extension/maven-metadata.xml`]: REDIS_UPSTREAM,
		[`${CDN}org/lucee/maven-metadata.xml`]: GROUP_UPSTREAM,
		[`${CDN}org/lucee/index.html`]: INDEX_UPSTREAM,
		[`${CDN}org/lucee/admin-extension/maven-metadata.xml`]: `<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>org.lucee</groupId>
  <artifactId>admin-extension</artifactId>
  <versioning>
    <latest>1.0.0.0</latest>
    <release>1.0.0.0</release>
    <versions>
      <version>1.0.0.0</version>
    </versions>
  </versioning>
</metadata>`
	};
}

beforeEach(async () => {
	await resetState();
});

afterEach(() => {
	mockFetch({});
});

describe("generated metadata from R2", () => {
	it("merge unions R2 versions with the upstream file and keeps a SNAPSHOT as latest only", async () => {
		mockFetch(routes());
		await putMaven("org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex");
		await putMaven("snapshots/org/lucee/redis-extension/4.3.0.1-SNAPSHOT/redis-extension-4.3.0.1-SNAPSHOT.lex");
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_SOURCE: "merge" });
		expect(res.status).toBe(200);
		const xml = await res.text();
		expect(xml).toContain("<version>2.0.0.1</version>");
		expect(xml).toContain("<version>3.0.0.1-SNAPSHOT</version>");
		expect(xml).toContain("<version>4.2.0.6</version>");
		expect(xml).toContain("<version>4.3.0.1-SNAPSHOT</version>");
		expect(xml).toContain("<latest>4.3.0.1-SNAPSHOT</latest>");
		expect(xml).toContain("<release>4.2.0.6</release>");
	});

	it("r2 uses only the versions present in the bucket", async () => {
		mockFetch(routes());
		await putMaven("org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex");
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_SOURCE: "r2" });
		expect(res.status).toBe(200);
		const xml = await res.text();
		expect(xml).toContain("<version>4.2.0.6</version>");
		expect(xml).not.toContain("2.0.0.1");
		expect(xml).toContain("<latest>4.2.0.6</latest>");
		expect(xml).toContain("<release>4.2.0.6</release>");
	});

	it("answers .sha1 and .md5 of the generated artifact metadata", async () => {
		mockFetch(routes());
		await putMaven("org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex");
		const xmlRes = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_SOURCE: "r2" });
		const xml = await xmlRes.text();
		const sha1 = await call("/org/lucee/redis-extension/maven-metadata.xml.sha1", {}, { METADATA_SOURCE: "r2" });
		const md5 = await call("/org/lucee/redis-extension/maven-metadata.xml.md5", {}, { METADATA_SOURCE: "r2" });
		expect(sha1.status).toBe(200);
		expect(md5.status).toBe(200);
		expect(await sha1.text()).toBe(await checksumOfText(xml, "sha1"));
		expect(await md5.text()).toBe(await checksumOfText(xml, "md5"));
	});

	it("builds the group metadata and index from R2, unioned with the upstream in merge mode", async () => {
		mockFetch(routes());
		await putMaven("org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex");
		await putMaven("org/lucee/lucee/7.1.0.10/lucee-7.1.0.10.jar");
		const group = await call("/org/lucee/maven-metadata.xml", {}, { METADATA_SOURCE: "merge" });
		expect(group.status).toBe(200);
		const xml = await group.text();
		expect(xml).toContain("<artifactId>admin-extension</artifactId>");
		expect(xml).toContain("<artifactId>redis-extension</artifactId>");
		expect(xml).not.toContain("<artifactId>lucee</artifactId>");
		expect(xml).toContain("<latest>4.2.0.6</latest>");
		const index = await call("/org/lucee/", {}, { METADATA_SOURCE: "merge" });
		expect(index.status).toBe(200);
		const html = await index.text();
		expect(html).toContain('href="redis-extension/"');
		expect(html).toContain('href="admin-extension/"');
		expect(html).toContain('href="lucee/"');
		expect(html).toContain("maven-metadata.xml");
	});

	it("returns 404 for an artifact that has no versions in R2 or upstream", async () => {
		mockFetch(routes());
		const res = await call("/org/lucee/unknown-extension/maven-metadata.xml", {}, { METADATA_SOURCE: "r2" });
		expect(res.status).toBe(404);
	});

	it("rebuilds the affected artifact when an R2 object-created event arrives", async () => {
		mockFetch(routes());
		await putMaven("org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex");
		const ctx = createExecutionContext();
		let acked = 0;
		const batch = {
			queue: "lucee-artifacts-object-created",
			messages: [
				{
					id: "1",
					timestamp: new Date(),
					attempts: 1,
					body: { action: "PutObject", object: { key: "org/lucee/redis-extension/4.2.0.6/redis-extension-4.2.0.6.lex" } },
					ack() {
						acked += 1;
					},
					retry() {}
				}
			]
		};
		await worker.queue(batch as never, testEnv({ METADATA_SOURCE: "r2" }), ctx);
		await waitOnExecutionContext(ctx);
		expect(acked).toBe(1);
		const res = await call("/org/lucee/redis-extension/maven-metadata.xml", {}, { METADATA_SOURCE: "r2" });
		expect(await res.text()).toContain("<version>4.2.0.6</version>");
	});
});
