component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/download8util": expandPath(dir & "../apps/download8/components/org/lucee/download/")
		};
		variables.util = new download8util.Util();
		variables.gh = "https://github.com/lucee/Lucee/releases/download/";
	}

	function run(testResults, testBox) {
		describe("LDEV-6709 download page: 7.1+ core files from GitHub Releases", function() {

			it(title="only 7.1+ non-snapshot versions use GitHub Releases", body=function() {
				expect(util.isGithubCoreVersion("7.1.1.17")).toBeTrue();
				expect(util.isGithubCoreVersion("7.1.2.184-RC")).toBeTrue();
				expect(util.isGithubCoreVersion("8.0.0.171-BETA")).toBeTrue();
				expect(util.isGithubCoreVersion("9.0.0.279-ALPHA")).toBeTrue();
				expect(util.isGithubCoreVersion("7.0.6.10")).toBeFalse();
				expect(util.isGithubCoreVersion("6.2.4.24")).toBeFalse();
				expect(util.isGithubCoreVersion("5.4.8.2")).toBeFalse();
				expect(util.isGithubCoreVersion("7.1.2.190-SNAPSHOT")).toBeFalse();
			});

			it(title="final release uses the numeric tag", body=function() {
				expect(util.githubAssetCandidates("7.1.1.17", "jar")).toBe([gh & "7.1.1.17/lucee-7.1.1.17.jar"]);
			});

			it(title="qualified release tries the numeric tag, then the full-version tag", body=function() {
				expect(util.githubAssetCandidates("7.1.2.184-RC", "light")).toBe([
					gh & "7.1.2.184/lucee-light-7.1.2.184-RC.jar",
					gh & "7.1.2.184-RC/lucee-light-7.1.2.184-RC.jar"
				]);
			});

			it(title="asset names match the GitHub Release assets", body=function() {
				expect(util.githubAssetCandidates("7.1.1.17", "zero")[1]).toBe(gh & "7.1.1.17/lucee-zero-7.1.1.17.jar");
				expect(util.githubAssetCandidates("7.1.1.17", "lco")[1]).toBe(gh & "7.1.1.17/7.1.1.17.lco");
				expect(util.githubAssetCandidates("7.1.1.17", "express")[1]).toBe(gh & "7.1.1.17/lucee-express-7.1.1.17.zip");
			});

			it(title="6.2 / 7.0, snapshots and other types are not looked up on GitHub", body=function() {
				expect(util.githubAssetCandidates("7.0.6.10", "jar")).toBe([]);
				expect(util.githubAssetCandidates("6.2.4.24", "light")).toBe([]);
				expect(util.githubAssetCandidates("7.1.2.190-SNAPSHOT", "jar")).toBe([]);
				expect(util.githubAssetCandidates("7.1.1.17", "win64")).toBe([]);
				expect(util.githubAssetUrl("7.0.6.10", "jar")).toBe("");
				expect(util.githubCoreLinks("6.2.4.24")).toBe({});
			});

			it(title="existing GitHub links keep their URLs", body=function() {
				expect(util.expressUrl("7.0.6.10")).toBe(gh & "7.0.6.10/lucee-express-7.0.6.10.zip");
				expect(util.cdnLinks("7.0.6.10").war).toBe(gh & "7.0.6.10/lucee-7.0.6.10.war");
				expect(util.cdnLinks("7.0.6.10").jar).toBe("https://cdn.lucee.org/lucee-7.0.6.10.jar");
			});
		});
	}
}
