component {

	this.name = "MavenBridge";
	this.sessionManagement = false;
	this.requestTimeout = createTimeSpan(0, 0, 0, val(server.system.environment.TIMEOUT ?: 300));

	// Only needed for the ensureBridgeReady() fallback below — normal requests just
	// call methods on the server-scoped singletons Server.cfc already created.
	this.componentpaths = [
		{
			"physical": getDirectoryFromPath(getCurrentTemplatePath()) & "components/",
			"archive": "",
			"primary": "physical",
			"inspectTemplate": "always"
		}
	];

	public boolean function onRequestStart() {
		ensureBridgeReady();

		if (isFlushRequest()) {
			request.cacheFlushed = true;
			rebuildBridge();
			server.bridgeRegistry.flushAll(server.bridgeWebroot);
		}

		var path = currentRequestPath();
		if (isMavenRepoPath(path)) {
			server.bridgeProxy.render(server.bridgeProxy.invoke(path));
			return false;
		}

		return true;
	}

	public boolean function onMissingTemplate(required string targetPage) {
		ensureBridgeReady();
		server.bridgeProxy.render(server.bridgeProxy.invoke(normalizeTargetPage(arguments.targetPage)));
		return true;
	}

	// Server.cfc builds server.bridgeRegistry on server start; this only covers the
	// case where its startup sync (a live HTTP call per provider) failed or hasn't
	// completed yet when the first request arrives.
	private void function ensureBridgeReady() {
		if (structKeyExists(server, "bridgeRegistry")) {
			return;
		}
		lock name="mavenbridge-bootstrap" timeout="30" {
			if (structKeyExists(server, "bridgeRegistry")) {
				return;
			}
			server.bridgeWebroot = getWebroot();
			var config = org.lucee.mavenbridge.BridgeRegistry::readConfigFromEnvironment();
			server.bridgeRegistry = new org.lucee.mavenbridge.BridgeRegistry(
				providers=config.providers,
				sharedConfig={ cacheTtlMinutes: config.cacheTtlMinutes, timeout: config.timeout }
			);
			server.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
			server.bridgeRegistry.syncAll(server.bridgeWebroot);
		}
	}

	// Recreate the server-scoped singletons from current source so code changes
	// take effect via ?flush without a server restart.
	private void function rebuildBridge() {
		lock name="mavenbridge-bootstrap" timeout="30" {
			server.bridgeWebroot = getWebroot();
			var config = org.lucee.mavenbridge.BridgeRegistry::readConfigFromEnvironment();
			server.bridgeRegistry = new org.lucee.mavenbridge.BridgeRegistry(
				providers=config.providers,
				sharedConfig={ cacheTtlMinutes: config.cacheTtlMinutes, timeout: config.timeout }
			);
			server.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
		}
	}

	private boolean function isFlushRequest() {
		if (!structKeyExists(url, "flush")) {
			return false;
		}
		if (isBoolean(url.flush)) {
			return url.flush;
		}
		return listFindNoCase("1,true,yes,force", trim(toString(url.flush))) > 0;
	}

	private string function getWebroot() {
		return getDirectoryFromPath(getCurrentTemplatePath());
	}

	private string function currentRequestPath() {
		// cgi.script_name/path_info depend on the servlet mapping that matched
		// (under the /org/* prefix mapping path_info loses the /org segment);
		// the request URI always carries the full original path
		var path = "";
		try {
			var req = getPageContext().getHttpServletRequest();
			path = trim(req.getRequestURI() ?: "");
			var ctx = trim(req.getContextPath() ?: "");
			if (len(ctx) && ctx != "/" && left(path, len(ctx)) == ctx) {
				path = mid(path, len(ctx) + 1);
			}
		} catch (any e) {
			path = "";
		}
		if (!len(path)) {
			path = trim(cgi.path_info ?: "");
			if (!len(path) || path == "/") {
				path = trim(cgi.script_name ?: "");
			}
		}
		return normalizeTargetPage(path);
	}

	private boolean function isMavenRepoPath(required string path) {
		// also match the bare segments (/org, /io) — normalizeTargetPage strips the trailing slash
		return reFindNoCase("^/(org|io)(/|$)", arguments.path) == 1;
	}

	private string function normalizeTargetPage(required string targetPage) {
		var p = replace(arguments.targetPage, "\", "/", "all");
		while (find("//", p)) {
			p = replace(p, "//", "/", "all");
		}
		if (left(p, 1) != "/") {
			p = "/" & p;
		}
		if (left(p, 11) == "/index.cfm/") {
			p = mid(p, 11);
		}
		if (len(p) > 1 && right(p, 1) == "/") {
			p = left(p, len(p) - 1);
		}
		return len(p) ? p : "/";
	}
}
