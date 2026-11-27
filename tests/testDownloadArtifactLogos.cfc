component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/download8util": expandPath(dir & "../apps/download8/components/org/lucee/download/")
		};
		variables.util = new download8util.Util();
		variables.util.ARTIFACTS_URL = "https://artifacts.lucee.org/extension-logos/";
		variables.base = variables.util.ARTIFACTS_URL;
		variables.hosted = variables.base & "org-lucee-ajax-extension.png";
		variables.raw = "https://raw.githubusercontent.com/lucee/extension-ajax/main/source/images/logo.png";
		variables.legacy = "https://cdn.lucee.org/artifacts/org-lucee-ajax-extension.png";
	}

	function run(testResults, testBox) {
		describe("download page: extension logos on artifacts.lucee.org", function() {

			it(title="builds {group}-{artifact}.png under ARTIFACTS_URL, dots become dashes, no version", body=function() {
				expect(util.artifactLogoUrl("org.lucee", "ajax-extension")).toBe(hosted);
				expect(util.artifactLogoUrl("com.example.foo", "bar.baz-extension")).toBe(
					base & "com-example-foo-bar-baz-extension.png"
				);
			});

			it(title="leaves a non-GitHub, non-legacy image URL unchanged", body=function() {
				var custom = "https://example.invalid/logo.png";
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", custom)).toBe(custom);
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", "")).toBe("");
			});

			it(title="rewrites a GitHub raw logo to the artifacts host when that file is there", body=function() {
				util.artifactLogoProbe = { "#hosted#": true };
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", raw)).toBe(hosted);
			});

			it(title="keeps a GitHub raw logo when the artifacts host does not have the file", body=function() {
				util.artifactLogoProbe = { "#hosted#": false };
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", raw)).toBe(raw);
			});

			it(title="rewrites a leftover cdn.lucee.org/artifacts/ URL when the new host has the file", body=function() {
				util.artifactLogoProbe = { "#hosted#": true };
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", legacy)).toBe(hosted);
			});

			it(title="keeps a leftover cdn.lucee.org/artifacts/ URL when the new host does not have the file", body=function() {
				util.artifactLogoProbe = { "#hosted#": false };
				expect(util.githubRawToCdn("org.lucee", "ajax-extension", legacy)).toBe(legacy);
			});

			it(title="resolveRelativeImage falls back to the artifacts host when there is no http base", body=function() {
				expect(util.resolveRelativeImage("org.lucee", "ajax-extension", "./ajax-extension-1.0.0-logo.png", "")).toBe(hosted);
			});

			it(title="resolveRelativeImage keeps a relative logo next to an http .lex URL", body=function() {
				var lex = "https://repo.example/org/lucee/ajax-extension/1.0.0/ajax-extension-1.0.0.lex";
				expect(util.resolveRelativeImage("org.lucee", "ajax-extension", "./ajax-extension-1.0.0-logo.png", lex)).toBe(
					"https://repo.example/org/lucee/ajax-extension/1.0.0/ajax-extension-1.0.0-logo.png"
				);
			});

			it(title="core jar and lco fallbacks still use cdn.lucee.org, not the artifacts host", body=function() {
				expect(util.cdnLinks("6.2.4.24").jar).toBe("https://cdn.lucee.org/lucee-6.2.4.24.jar");
				expect(util.cdnLinks("6.2.4.24").lco).toBe("https://cdn.lucee.org/6.2.4.24.lco");
				expect(util.CDN).toBe("https://cdn.lucee.org/");
			});
		});
	}
}
