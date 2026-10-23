component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/mavenbridge": expandPath(dir & "../apps/maven-bridge/www/components/org/lucee/mavenbridge/")
		};
		variables.gh = "https://github.com/lucee/Lucee/releases/download/";
	}

	private function newSupport(struct extra={}) {
		var config = {
			provider: "https://extension.lucee.org",
			groupId: "org.lucee",
			upstream: "https://cdn.lucee.org/"
		};
		structAppend(config, arguments.extra, true);
		return new mavenbridge.BridgeSupport(config);
	}

	private function urlsFor(support, string path) {
		return arguments.support.toGithubReleaseUrls(arguments.support.parseMavenPath(arguments.path));
	}

	function run(testResults, testBox) {
		describe("LDEV-6706 maven-bridge: core files from GitHub Releases", function() {

			it(title="defaults to the Lucee GitHub Releases download base", body=function() {
				expect(newSupport().getGithubReleasesUrl()).toBe(variables.gh);
			});

			it(title="only 7.1+ non-snapshot versions use GitHub Releases", body=function() {
				var s = newSupport();
				expect(s.isGithubReleaseVersion("7.1.2.184-RC")).toBeTrue();
				expect(s.isGithubReleaseVersion("7.1.1.17")).toBeTrue();
				expect(s.isGithubReleaseVersion("7.2.0.1-ALPHA")).toBeTrue();
				expect(s.isGithubReleaseVersion("8.0.0.171")).toBeTrue();
				expect(s.isGithubReleaseVersion("7.0.6.10")).toBeFalse();
				expect(s.isGithubReleaseVersion("6.2.4.24")).toBeFalse();
				expect(s.isGithubReleaseVersion("5.4.8.2")).toBeFalse();
				expect(s.isGithubReleaseVersion("7.1.2.190-SNAPSHOT")).toBeFalse();
			});

			it(title="final release uses the numeric tag only", body=function() {
				var s = newSupport();
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.jar")).toBe([
					variables.gh & "7.1.1.17/lucee-7.1.1.17.jar"
				]);
			});

			it(title="qualified release tries the numeric tag, then the full-version tag", body=function() {
				var s = newSupport();
				expect(urlsFor(s, "/org/lucee/lucee/7.1.2.184-RC/lucee-7.1.2.184-RC.jar")).toBe([
					variables.gh & "7.1.2.184/lucee-7.1.2.184-RC.jar",
					variables.gh & "7.1.2.184-RC/lucee-7.1.2.184-RC.jar"
				]);
			});

			it(title="maps light, zero, lco, war and express to the GitHub asset names", body=function() {
				var s = newSupport();
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17-light.jar")[1]).toBe(variables.gh & "7.1.1.17/lucee-light-7.1.1.17.jar");
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17-zero.jar")[1]).toBe(variables.gh & "7.1.1.17/lucee-zero-7.1.1.17.jar");
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.lco")[1]).toBe(variables.gh & "7.1.1.17/7.1.1.17.lco");
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.war")[1]).toBe(variables.gh & "7.1.1.17/lucee-7.1.1.17.war");
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17-express.zip")[1]).toBe(variables.gh & "7.1.1.17/lucee-express-7.1.1.17.zip");
			});

			it(title="6.2 / 7.0 and snapshots keep the CDN-only behaviour", body=function() {
				var s = newSupport();
				expect(urlsFor(s, "/org/lucee/lucee/7.0.6.10/lucee-7.0.6.10.jar")).toBe([]);
				expect(urlsFor(s, "/org/lucee/lucee/6.2.4.24/lucee-6.2.4.24-light.jar")).toBe([]);
				expect(urlsFor(s, "/org/lucee/lucee/7.1.2.190-SNAPSHOT/lucee-7.1.2.190-SNAPSHOT.jar")).toBe([]);
			});

			it(title="files not published on GitHub are not looked up there", body=function() {
				var s = newSupport();
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.jar.sha1")).toBe([]);
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.pom")).toBe([]);
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17-forgebox.zip")).toBe([]);
				expect(urlsFor(s, "/org/lucee/other/7.1.1.17/other-7.1.1.17.jar")).toBe([]);
			});

			it(title="an empty GitHub Releases URL disables the lookup", body=function() {
				var s = newSupport({ githubReleasesUrl: "" });
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.jar")).toBe([]);
			});

			it(title="the GitHub Releases base URL is configurable", body=function() {
				var s = newSupport({ githubReleasesUrl: "https://example.org/releases" });
				expect(urlsFor(s, "/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.jar")[1]).toBe("https://example.org/releases/7.1.1.17/lucee-7.1.1.17.jar");
			});
		});
	}
}
