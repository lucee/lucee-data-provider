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
	this.s3.accessKeyId         = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey        = server.system.environment.S3_EXTENSION_SECRET_KEY;
	this.allowReload            = IsBoolean( server.system.environment.ALLOW_RELOAD ?: "" ) && server.system.environment.ALLOW_RELOAD;

	function onApplicationStart() {
		lock name="configure-sentry" type="exclusive" timeout=5{
			// workaround for LDEV-5371
			// if LUCEE_LOGGING_FORCE_APPENDER=console is set, sentry is bypassed
			var deploy = expandPath( '{lucee-server}/../deploy/' );
			var sentry_json = deploy & "/.CFconfig-sentry.json"; 
			if ( FileExists( sentry_json ) ){
				configImport( sentry_json, "server", "admin" );
				systemOutput("sentry.json loaded via configImport - LDEV-5371", true);
				fileDelete( sentry_json );
			}
		}
		_loadServices();
	}

	function onRequestStart() output=true {
		var sentry_dsn = "https://o1289959.ingest.us.sentry.io/api/4507452800040960/security/?sentry_key=9af63ea401ee6935d34159019b1ae765";
		var csp = [
			  "sandbox"
			, "object-src 'none'"
			, "script-src 'none'"
			, "report-uri #sentry_dsn#"
		];

		header name="Content-Security-Policy" value=ArrayToList( csp, "; " );

		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			_loadServices();
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

	private string function _withTrailingSlash( required string path ) {
		return Right( arguments.path, 1 ) == "/" ? arguments.path : arguments.path & "/";
	}

	/**
	 * LDEV-6789: the Maven repositories extensions are discovered in, the ones Lucee core uses by default, set the
	 * same way core does (comma separated urls). EXTENSIONS_MAVEN_REPOS_* take precedence, then the LUCEE_MVN_REPO_*
	 * variables of core. A value of "none" disables a repository type, EXTENSIONS_MAVEN_REPOS_ENABLED=false all.
	 */
	private function _createMavenSource() {
		var env = server.system.environment;

		if ( !( env.EXTENSIONS_MAVEN_REPOS_ENABLED ?: true ) ) {
			return "";
		}

		return new services.MavenExtensionSource(
			  releaseRepos    = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_RELEASES  ?: env.LUCEE_MVN_REPO_RELEASES  ?: "https://repo1.maven.org/maven2/" )
			, snapshotRepos   = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_SNAPSHOTS ?: env.LUCEE_MVN_REPO_SNAPSHOTS ?: "https://central.sonatype.com/repository/maven-snapshots/" )
			, mixedRepos      = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_MIXED     ?: env.LUCEE_MVN_REPO_MIXED     ?: "https://maven.lucee-services.com/" )
			, timeout         = Val( env.EXTENSIONS_MAVEN_TIMEOUT          ?: 20  )
			, downloadTimeout = Val( env.EXTENSIONS_MAVEN_DOWNLOAD_TIMEOUT ?: 120 )
			, maxThreads      = Val( env.EXTENSIONS_MAVEN_THREADS          ?: 10  )
		);
	}

	private array function _mavenRepos( required string repos ) {
		return Trim( arguments.repos ) == "none" ? [] : ListToArray( arguments.repos, "," );
	}

	function _loadServices() {
		setting requesttimeout=600;

		var coreS3Root   = server.system.environment.S3_CORE_ROOT          ?: "s3:///lucee-downloads/";
		var coreCdnUrl   = server.system.environment.S3_CORE_CDN_URL       ?: "https://cdn.lucee.org/";
		var extS3Root    = server.system.environment.S3_EXTENSIONS_ROOT    ?: "s3:///extension-downloads/";
		var extCdnUrl    = server.system.environment.S3_EXTENSIONS_CDN_URL ?: "https://ext.lucee.org/";
		// LDEV-6789: extensions published to the Maven layout of the core bucket: <coreS3Root><extMavenPath><artifactId>/<version>/
		var extMavenPath = server.system.environment.S3_EXTENSIONS_MAVEN_PATH ?: "org/lucee/";
		var bundleS3Root = server.system.environment.S3_BUNDLES_ROOT       ?: "s3:///bundle-download/";
		var bundleCdnUrl = server.system.environment.S3_BUNDLES_CDN_URL    ?: "https://bundle.lucee.org/";

		var extMetaReader = new services.ExtensionMetadataReader(
			  s3root       = extS3Root
			, mavenRoot    = Len( extMavenPath ) ? _withTrailingSlash( coreS3Root ) & extMavenPath : ""
			, mavenCdnUrl  = Len( extMavenPath ) ? _withTrailingSlash( coreCdnUrl ) & extMavenPath : ""
			, mavenSource  = _createMavenSource()
			, fetchThreads = Val( server.system.environment.EXTENSIONS_MAVEN_FETCH_THREADS ?: 5 )
		);

		var jiraChangelogService = new services.JiraChangelogService(
			s3root = coreS3Root
		);

		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsCdnUrl    = extCdnUrl
			, bundleS3Root        = bundleS3Root
			, bundleCdnUrl        = bundleCdnUrl
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new services.legacy.MavenMatcher()
		);

		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		extMetaReader.loadMeta();

		jiraChangelogService.loadIssues();
		jiraChangelogService.updateIssuesAsync();

		application.coreS3Root            = coreS3Root;
		application.coreCdnUrl            = coreCdnUrl;
		application.extensionsCdnUrl      = extCdnUrl;
		application.extensionsS3Root      = extS3Root;
		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
		application.jiraChangelogService  = jiraChangelogService;
	}

}
