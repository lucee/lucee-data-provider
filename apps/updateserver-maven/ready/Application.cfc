/**
 * Separate application so GET /ready/ answers immediately and does not run the
 * Maven provider's onApplicationStart. Use it as the startup probe: it answers
 * 503 until the provider services are loaded, so a new instance gets no traffic
 * before it can serve it. The first request also starts the main application.
 */
component {

	this.name              = "lucee-provider-maven-ready";
	this.clientManagement  = false;
	this.sessionManagement = false;
	this.setClientCookies  = false;
	this.scopeCascading    = "strict";

	function onApplicationStart() {
		thread action="run" name="lucee-provider-maven-ready-warmup" {
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
		// index.cfm answers
	}

}
