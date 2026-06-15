component {

	this.name = "MavenBridge";
	this.sessionManagement = false;
	this.requestTimeout = createTimeSpan(0, 0, 0, val(server.system.environment.TIMEOUT ?: 300));

	this.componentpaths = [
		{
			"physical": getDirectoryFromPath(getCurrentTemplatePath()) & "components/",
			"archive": "",
			"primary": "physical",
			"inspectTemplate": "always"
		}
	];

	public function onApplicationStart() {
		ensureBridgeConfig();
		application.bridgeWebroot = getWebroot();
		application.bridgeRegistry = createBridgeRegistry(application.bridgeConfig);
		application.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
		return true;
	}

	public boolean function onRequestStart() {
		if (!structKeyExists(application, "bridgeWebroot")) {
			onApplicationStart();
		}
		if (!structKeyExists(application, "bridgeSynced")) {
			application.bridgeRegistry.syncAll(application.bridgeWebroot);
			application.bridgeSynced = true;
		}
		if (isFlushRequest()) {
			request.cacheFlushed = true;
			flushBridgeCache();
		}
		return true;
	}

	public boolean function onMissingTemplate(required string targetPage) {
		ensureBridgeConfig();
		ensureBridgeComponents();

		var path = normalizeTargetPage(arguments.targetPage);
		application.bridgeProxy.render(application.bridgeProxy.invoke(path));
		return true;
	}

	private void function ensureBridgeConfig() {
		if (!structKeyExists(application, "bridgeConfig")) {
			application.bridgeConfig = {
				providers: parseBridgeProviders(),
				cacheTtlMinutes: val(server.system.environment.CACHE_TTL_MINUTES ?: 60),
				timeout: val(server.system.environment.TIMEOUT ?: 300)
			};
		}
	}

	private array function parseBridgeProviders() {
		var raw = trim(server.system.environment.EXTENSION_PROVIDERS ?: "");
		if (len(raw)) {
			return parseProviderEnv(raw);
		}

		var provider = trim(server.system.environment.EXTENSION_PROVIDER ?: "");
		var groupId = trim(server.system.environment.GROUP_ID ?: "");
		if (len(provider) || len(groupId)) {
			return [{
				provider: len(provider) ? provider : "https://extension.lucee.org",
				groupId: len(groupId) ? groupId : "org.lucee"
			}];
		}

		return defaultBridgeProviders();
	}

	private array function defaultBridgeProviders() {
		return [
			{ "provider": "https://www.forgebox.io", "groupId": "io.forgebox" },
			{ "provider": "https://extension.lucee.org", "groupId": "org.lucee" }
		];
	}

	private array function parseProviderEnv(required string env) {
		var raw = trim(arguments.env);
		if (!len(raw)) {
			return [];
		}
		if (left(raw, 1) == "[") {
			return normalizeProviderEntries(deserializeJSON(raw));
		}
		return normalizeProviderEntries(listToArray(raw));
	}

	private array function normalizeProviderEntries(required array entries) {
		var providers = [];
		for (var entry in arguments.entries) {
			if (isStruct(entry)) {
				if (len(trim(entry.provider ?: "")) && len(trim(entry.groupId ?: ""))) {
					arrayAppend(providers, {
						"provider": trim(entry.provider),
						"groupId": trim(entry.groupId)
					});
				}
				continue;
			}
			var pair = trim(toString(entry));
			if (!len(pair)) {
				continue;
			}
			var pos = find("|", pair);
			if (pos < 2) {
				continue;
			}
			arrayAppend(providers, {
				"provider": trim(left(pair, pos - 1)),
				"groupId": trim(mid(pair, pos + 1))
			});
		}
		return providers;
	}

	private function createBridgeRegistry(required struct config) {
		return new org.lucee.mavenbridge.BridgeRegistry(
			providers=config.providers,
			sharedConfig={
				cacheTtlMinutes: config.cacheTtlMinutes,
				timeout: config.timeout
			}
		);
	}

	private void function ensureBridgeComponents() {
		if (!structKeyExists(application, "bridgeRegistry")) {
			application.bridgeRegistry = createBridgeRegistry(application.bridgeConfig);
		}
		if (!structKeyExists(application, "bridgeProxy")) {
			application.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
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

	private void function flushBridgeCache() {
		ensureBridgeConfig();
		application.bridgeRegistry = createBridgeRegistry(application.bridgeConfig);
		application.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
		application.bridgeRegistry.flushAll(application.bridgeWebroot);
	}

	private string function getWebroot() {
		return getDirectoryFromPath(getCurrentTemplatePath());
	}

	private string function normalizeTargetPage(required string targetPage) {
		var p = replace(arguments.targetPage, "\", "/", "all");
		while (find("//", p)) {
			p = replace(p, "//", "/", "all");
		}
		if (left(p, 1) != "/") {
			p = "/" & p;
		}
		if (len(p) > 1 && right(p, 1) == "/") {
			p = left(p, len(p) - 1);
		}
		return len(p) ? p : "/";
	}
}
