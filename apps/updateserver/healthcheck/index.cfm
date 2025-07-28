<cfscript>
	if ( !structKeyExists( application, "state" ) || application.state != "loaded" ) {
		var state = application.state ?: 'undefined';
		systemOutput( "healthcheck FAILED: Application not ready. State: #state#", true );
		header statuscode="503" statustext="Service Unavailable";
		echo( "Application not ready. State: #state#" );
		abort;
	}

	echo( "OK" );
</cfscript>