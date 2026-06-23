component {
	this.name="lucee-downloads-page";

	this.xmlFeatures = {
		externalGeneralEntities: false,
		secure: true,
		disallowDoctypeDecl: true
	};

	request.s3Root="s3:///extension-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/extension-downloads/";

	function onApplicationStart() {
		application.extensionMeta = deserializeJson( fileRead( "extensionMeta.json" ) );
		application.sentryDsn = server.system.environment.SENTRY_DSN ?: "";

		var sentryLogger = new services.SentryLogger(
			config = {
				dsn = application.sentryDsn,
				environment = server.system.environment.SENTRY_ENVIRONMENT ?: "production",
				release = server.system.environment.SENTRY_RELEASE ?: "",
				serverName = server.system.environment.SENTRY_SERVER_NAME ?: cgi.server_name
			}
		);

		application.sentryLogger = sentryLogger;
	}

	function onError( e ){
		if ( cgi.script_name contains "admin" or cgi.script_name contains "lucee" ){
			header statuscode="418" statustext="nice try, you're a teapot";
			return;
		}

		// Log to Sentry
		try {
			if ( structKeyExists( application, "sentryLogger" ) ) {
				application.sentryLogger.logException(
					exception = arguments.e,
					level = "error"
				);
			}
		} catch ( any err ) {
			// Don't let Sentry failures break error handling
			systemOutput( "Failed to log error to Sentry: #err.message#", true );
		}

		header statuscode="500" statustext="Server error";
		echo( "Sorry, Server error" );
	}

	function onRequest( string requestedPath ) output=true {
		if ( arguments.requestedPath == "/index.cfm"
				&& ( structCount( url ) == 0 || cgi.query_string == "type=snapshots&reset=force" ) ) {
			var tmpFile = getTempDirectory() & "/cachedhomepage.html";

			if ( StructKeyExists( url, "reset" ) || !FileExists( tmpFile ) ) {
				var pageContent = "";
				savecontent variable="pageContent" {
					include template=arguments.requestedPath;
				}
				FileWrite( tmpFile, Trim( pageContent ) );
				echo( Trim( pageContent ) );
				return;
			}
			echo( FileRead( tmpFile ) );
			return;
		}

		include template=arguments.requestedPath;
	}

}