component {

	remote function onServerStart( boolean reload = false ) {
		cfApplication(action="update", componentpaths=[{
			"physical": "/var/www/components/",
			"archive": "",
			"primary": "physical"
		}]);

		if (!structKeyExists(server, "bridgeWebroot")) {
			server.bridgeWebroot = "/var/www/";
		}

		if (!structKeyExists(server, "bridgeRegistry")) {
			var config = org.lucee.mavenbridge.BridgeRegistry::readConfigFromEnvironment();
			server.bridgeRegistry = new org.lucee.mavenbridge.BridgeRegistry(
				providers=config.providers,
				sharedConfig={ cacheTtlMinutes: config.cacheTtlMinutes, timeout: config.timeout }
			);
		}

		if (!structKeyExists(server, "bridgeProxy")) {
			server.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
		}

		server.bridgeRegistry.syncAll(server.bridgeWebroot);
	}

}
