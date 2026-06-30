component {

	remote function onServerStart( boolean reload = false ) {
		cfApplication(action="update", componentpaths=[{
			"physical": "/var/components/",
			"archive":  "",
			"primary":  "physical"
		}]);

		if (!structKeyExists(application, "util"))
			application.util = new org.lucee.download.Util();

		application.util.info("onServerStart: warming caches");
		application.util.warmup();
	}

}
