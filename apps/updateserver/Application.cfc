component {

	this.name                   = "lucee-provider";
	this.clientManagement       = "no";
	this.clientStorage          = "file";
	this.scriptProtect          = "all";
	this.sessionManagement      = "yes";
	this.sessionStorage         = "memory";
	this.sessionTimeout         = "#createTimeSpan(0,0,0,30)#";
	this.sessionCookie.httpOnly = true; // prevent access to session cookies from javascript
	this.sessionCookie.sameSite = "strict";
	this.searchImplicitScopes   = false;
	this.searchResults          = false;
	this.scopeCascading         = 'strict';
	this.s3.accessKeyId         = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID ?: "";
	this.s3.awsSecretKey        = server.system.environment.S3_EXTENSION_SECRET_KEY ?: "";
	this.allowReload            = IsBoolean( server.system.environment.ALLOW_RELOAD ?: "" ) && server.system.environment.ALLOW_RELOAD;

	function onApplicationStart() {
		systemOutput( "[#dateTimeFormat(now(), "long")#] onApplicationStart() called for lucee-provider", true );
		application.state = "init";

		application.state = "starting";
		var success = _loadServices();
		application.state = success ? "loaded" : "failed";

		systemOutput( "[#dateTimeFormat(now(), "long")#] onApplicationStart() finished, state: #application.state#", true );
		return success;
	}

	function onRequestStart() output=true {
		var csp = [
			  "sandbox"
			, "object-src 'none'"
			, "script-src 'none'"
			, "report-uri #application.sentryDsn#"
		];

		header name="Content-Security-Policy" value=ArrayToList( csp, "; " );

		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			application.state = "starting";
			var success = _loadServices();
			application.state = success ? "loaded" : "failed";
		}

		var allowedPaths = [ "rest", "healthcheck", "index.cfm" ];
		var requestedPath = ListFirst( Trim( cgi.script_name ), "/" );

		if ( !ArrayFindNoCase( allowedPaths, requestedPath ) ) {
			content reset=true;
			header statuscode=404;
			echo( "not found" );
			abort;
		}
	}

	function onError( required any exception, required string eventName ) {
		// Log uncaught errors to Sentry
		try {
			if ( structKeyExists( application, "sentryLogger" ) ) {
				application.sentryLogger.logException(
					exception = arguments.exception,
					level = "error",
					tags = { "eventName" = arguments.eventName }
				);
			}
		} catch ( any e ) {
			// Don't let Sentry failures break error handling
			systemOutput( "Failed to log error to Sentry: #e.message#", true );
		}

		// Rethrow the original exception so it's still logged locally
		throw(
			type = arguments.exception.type,
			message = arguments.exception.message,
			detail = arguments.exception.detail ?: "",
			cause = arguments.exception
		);
	}

	function _loadServices() {
		setting requesttimeout=600;

		application.coreS3Root              = server.system.environment.S3_CORE_ROOT          ?: "s3:///lucee-downloads/";
		application.coreCdnUrl              = server.system.environment.S3_CORE_CDN_URL       ?: "https://cdn.lucee.org/";
		application.extensionsS3Root        = server.system.environment.S3_EXTENSIONS_ROOT    ?: "s3:///extension-downloads/";
		application.extensionsCdnUrl        = server.system.environment.S3_EXTENSIONS_CDN_URL ?: "https://ext.lucee.org/";
		application.bundleS3Root            = server.system.environment.S3_BUNDLES_ROOT       ?: "s3:///bundle-download/";
		application.bundleCdnUrl            = server.system.environment.S3_BUNDLES_CDN_URL    ?: "https://bundle.lucee.org/";
		application.downloadsUrl            = server.system.environment.DOWNLOADS_URL         ?: "https://download.lucee.org/";
		application.updateProviderUrl       = server.system.environment.UPDATE_PROVIDER       ?: "https://update.lucee.org/rest/update/provider/";
		application.extensionProviderUrl    = server.system.environment.EXTENSION_PROVIDER    ?: "https://extensions.lucee.org/rest/extension/provider/";
		application.sentryDsn               = server.system.environment.SENTRY_DSN            ?: "";

		if ( left( application.coreS3Root, 3 ) == "s3:"
				&& ( len( this.s3.awsSecretKey ) == 0 || len( this.s3.accessKeyId ) == 0) ) {
			var s3Error = "ERROR: S3 Credentials Required [ S3_EXTENSION_ACCESS_KEY_ID, S3_EXTENSION_SECRET_KEY ],"
				& " for local testing set S3_CORE_ROOT [#application.coreS3Root#] to a directory";
			systemOutput( s3Error, true );
			return false;
		} else {
			// always delete local cache to start with a clean slate
			var versionsCache ="services/legacy/cache/versions.json";
			if ( fileExists( versionsCache ) ){
				systemOutput("LOCAL_S3: purging version cache [#versionsCache#]", true);
				fileDelete( versionsCache );
			}
		}

		var extMetaReader = new services.ExtensionMetadataReader(
			s3root = application.extensionsS3Root
		);

		var jiraChangelogService = new services.JiraChangelogService(
			s3root = application.coreS3Root
		);

		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsCdnUrl    = application.extensionsCdnUrl
			, bundleS3Root        = application.bundleS3Root
			, bundleCdnUrl        = application.bundleCdnUrl
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new services.legacy.MavenMatcher()
		);

		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		extMetaReader.loadMeta();

		jiraChangelogService.loadIssues();
		jiraChangelogService.updateIssuesAsync();
		new services.legacy.MavenRepo().list();

		var sentryLogger = new services.SentryLogger(
			config = {
				dsn = application.sentryDsn,
				environment = server.system.environment.SENTRY_ENVIRONMENT ?: "production",
				release = server.system.environment.SENTRY_RELEASE ?: "",
				serverName = server.system.environment.SENTRY_SERVER_NAME ?: cgi.server_name
			}
		);

		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
		application.jiraChangelogService  = jiraChangelogService;
		application.sentryLogger          = sentryLogger;

		return true;
	}

}