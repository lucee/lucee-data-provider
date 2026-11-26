<cfscript>
	// Startup probe: 200 once the provider services are loaded, 503 before that.
	// Answers immediately and never waits for the main application.
	ready = false;
	try {
		ready = services.ProviderHealth::isReady();
	} catch ( any ignore ) {}

	content type="text/plain";
	header name="Cache-Control" value="no-store";
	if ( ready ) {
		echo( "READY" );
	} else {
		header statuscode=503;
		header name="Retry-After" value="10";
		echo( "STARTING" );
	}
</cfscript>
