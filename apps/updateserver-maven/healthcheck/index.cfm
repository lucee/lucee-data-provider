<cfscript>
	// Answers immediately and never waits for the main application.
	// 503 only after the services have failed to load for HEALTH_FAIL_AFTER_SECONDS,
	// see services/ProviderHealth.cfc. Any error in this check itself answers OK,
	// so the health check can never be what takes the service down.
	unhealthy = false;
	try {
		unhealthy = services.ProviderHealth::isUnhealthy();
	} catch ( any ignore ) {}

	if ( unhealthy ) {
		header statuscode=503;
		echo( "FAILING" );
	} else {
		echo( "OK" );
	}
</cfscript>
