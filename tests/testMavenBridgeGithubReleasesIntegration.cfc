component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/mavenbridge": expandPath(dir & "../apps/maven-bridge/www/components/org/lucee/mavenbridge/")
		};
		variables.gh = "https://github.com/lucee/Lucee/releases/download/";
		variables.support = new mavenbridge.BridgeSupport({
			provider: "https://extension.lucee.org",
			groupId: "org.lucee",
			upstream: "https://cdn.lucee.org/",
			timeout: 30
		});
	}

	private string function resolve(string path) {
		return variables.support.findGithubReleaseUrl(variables.support.parseMavenPath(arguments.path));
	}

	function run(testResults, testBox) {
		describe("LDEV-6706 maven-bridge: resolve core files on GitHub Releases", function() {

			it(title="RC published under the numeric tag", body=function() {
				expect(resolve("/org/lucee/lucee/7.1.2.184-RC/lucee-7.1.2.184-RC.jar")).toBe(variables.gh & "7.1.2.184/lucee-7.1.2.184-RC.jar");
			});

			it(title="backfilled RC published under the full-version tag", body=function() {
				expect(resolve("/org/lucee/lucee/7.1.1.17-RC/lucee-7.1.1.17-RC-light.jar")).toBe(variables.gh & "7.1.1.17-RC/lucee-light-7.1.1.17-RC.jar");
			});

			it(title="final release lco", body=function() {
				expect(resolve("/org/lucee/lucee/7.1.1.17/lucee-7.1.1.17.lco")).toBe(variables.gh & "7.1.1.17/7.1.1.17.lco");
			});

			it(title="missing asset resolves to nothing, so the CDN fallback is used", body=function() {
				expect(resolve("/org/lucee/lucee/7.1.0.0/lucee-7.1.0.0.jar")).toBe("");
			});
		});

		describe("LDEV-6706 maven-bridge: core pom from the Maven layout", function() {

			it(title="core pom of a published build resolves to the upstream Maven layout", body=function() {
				var parsed = variables.support.parseMavenPath("/org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.pom");
				expect(variables.support.findUpstreamFileUrl(parsed)).toBe("https://cdn.lucee.org/org/lucee/lucee/8.0.0.294-RC/lucee-8.0.0.294-RC.pom");
			});

			it(title="missing core file resolves to nothing", body=function() {
				var parsed = variables.support.parseMavenPath("/org/lucee/lucee/7.1.0.0/lucee-7.1.0.0.pom");
				expect(variables.support.findUpstreamFileUrl(parsed)).toBe("");
			});
		});
	}
}
