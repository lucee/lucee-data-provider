/**
 * Separate application so GET /healthcheck/ returns immediately and does not
 * run the Maven provider's onApplicationStart (service loading). The first
 * probe also kicks off a background warmup of the main app.
 */
component {

	this.name              = "lucee-provider-maven-healthcheck";
	this.clientManagement  = false;
	this.sessionManagement = false;
	this.setClientCookies  = false;
	this.scopeCascading    = "strict";

	function onApplicationStart() {
		thread action="run" name="lucee-provider-maven-warmup" {
			try {
				var port = Val( server.system.environment.PORT ?: 8080 );
				if ( port <= 0 ) {
					port = 8080;
				}
				http url="http://127.0.0.1:#port#/warmup/" timeout=2 throwonerror=false;
			} catch ( any ignore ) {}
		}
	}

	function onRequestStart() {
		// index.cfm answers OK
	}

}
