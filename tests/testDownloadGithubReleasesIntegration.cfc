component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/download8util": expandPath(dir & "../apps/download8/components/org/lucee/download/")
		};
		variables.util = new download8util.Util();
		variables.gh = "https://github.com/lucee/Lucee/releases/download/";
	}

	function run(testResults, testBox) {
		describe("LDEV-6709 download page: resolve 7.1+ core files on GitHub Releases", function() {

			it(title="final release jar / light / zero / lco", body=function() {
				var links = util.githubCoreLinks("7.1.1.17");
				expect(links.jar).toBe(gh & "7.1.1.17/lucee-7.1.1.17.jar");
				expect(links.light).toBe(gh & "7.1.1.17/lucee-light-7.1.1.17.jar");
				expect(links.zero).toBe(gh & "7.1.1.17/lucee-zero-7.1.1.17.jar");
				expect(links.lco).toBe(gh & "7.1.1.17/7.1.1.17.lco");
			});

			it(title="RC published under the numeric tag", body=function() {
				expect(util.githubAssetUrl("7.1.2.184-RC", "express")).toBe(gh & "7.1.2.184/lucee-express-7.1.2.184-RC.zip");
			});

			it(title="backfilled RC published under the full-version tag", body=function() {
				expect(util.githubAssetUrl("7.1.1.17-RC", "light")).toBe(gh & "7.1.1.17-RC/lucee-light-7.1.1.17-RC.jar");
			});

			it(title="missing asset resolves to nothing, so the current source is kept", body=function() {
				expect(util.githubAssetUrl("7.1.0.0", "jar")).toBe("");
			});
		});
	}
}
