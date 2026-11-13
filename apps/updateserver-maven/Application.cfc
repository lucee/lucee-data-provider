/**
 * Maven-only REST update/extension provider for Cloud Run.
 * No S3, no S3 credentials, no Sentry.
 *
 * Shared cache (same files as apps/download8): CACHE_DIRECTORY, default
 * /download (bucket lucee_downloads, the same mount as download8).
 * App-specific caches (listings, extension meta, Jira) go under CACHE_DIR,
 * default /download/provider, so they cannot collide with download8's keys.
 *
 * /healthcheck/ is a separate application so it can answer before this one
 * has loaded its services.
 */
component {

	this.name                   = "lucee-provider-maven";
	this.clientManagement       = "no";
	this.clientStorage          = "file";
	this.scriptProtect          = "all";
	this.sessionManagement      = "yes";
	this.sessionStorage         = "memory";
	this.sessionTimeout         = "#createTimeSpan(0,0,0,30)#";
	this.sessionCookie.httpOnly = true;
	this.sessionCookie.sameSite = "strict";
	this.searchImplicitScopes   = false;
	this.searchResults          = false;
	this.scopeCascading         = "strict";
	this.allowReload            = IsBoolean( server.system.environment.ALLOW_RELOAD ?: "" ) && server.system.environment.ALLOW_RELOAD;

	function onApplicationStart() {
		application.storageMode           = "maven";
		application.coreS3Root            = "";
		application.coreCdnUrl            = "";
		application.extensionsCdnUrl      = "";
		application.extensionsS3Root      = "";
		application.servicesReady         = false;
		application.servicesError         = "";
		application.listingCache          = _createListingCache();

		thread action="run" name="lucee-provider-maven-load-services" {
			try {
				setting requesttimeout=600;
				_loadServices();
				application.servicesReady = true;
				SystemOutput( "Maven provider services are ready", true );
				// Jira is filled in the background and must never gate readiness
				_refreshJiraAsync();
			} catch ( any e ) {
				application.servicesError = e.message;
				SystemOutput( "Maven provider services failed to load: #e.message#", true );
				SystemOutput( e, true );
			}
		}
	}

	function onRequestStart() output=true {
		// Cold start can take a couple of minutes (Maven metadata). The default
		// 50s request timeout would otherwise 500 waiting requests.
		setting requesttimeout=600;
		header name="Content-Security-Policy" value="sandbox; object-src 'none'; script-src 'none'";

		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			application.servicesReady = false;
			_loadServices();
			application.servicesReady = true;
			_refreshJiraAsync();
		}

		var allowedPaths = [ "rest", "healthcheck", "index.cfm", "warmup" ];
		var requestedPath = ListFirst( Trim( cgi.script_name ), "/" );

		if ( !ArrayFindNoCase( allowedPaths, requestedPath ) ) {
			content reset=true;
			header statuscode=404;
			echo( "not found" );
			abort;
		}
	}

	private function _createListingCache() {
		var seconds = Val( server.system.environment.LISTING_CACHE_SECONDS ?: 300 );
		if ( seconds <= 0 ) {
			seconds = 300;
		}

		return new services.ListingCache(
			  cacheDir   = services.CacheDir::path( "listings", GetTempDirectory() & "lucee-update-cache/listings/" )
			, ttlSeconds = seconds
		);
	}

	private function _createCatalog() {
		var env  = server.system.environment;
		var args = _mavenSourceArguments();
		var mixed = ArrayLen( args.mixedRepos ) ? args.mixedRepos[ 1 ] : "https://maven.lucee-services.com/";

		return new services.LuceeCatalog(
			  cache     = new services.SharedDownloadCache()
			, groups    = [ "org.lucee", "io.forgebox" ]
			, mixedRepo = mixed
			, timeout   = args.timeout
		);
	}

	private function _createMavenSource( required any catalog ) {
		var args = _mavenSourceArguments();
		if ( StructIsEmpty( args ) ) {
			return "";
		}
		args.catalog = arguments.catalog;
		args.groups  = arguments.catalog.getGroups();

		return new services.MavenExtensionSource( argumentCollection=args );
	}

	private function _createCoreMavenSource( required any catalog ) {
		var args  = _mavenSourceArguments();
		var mixed = ArrayLen( args.mixedRepos ) ? args.mixedRepos[ 1 ] : "https://maven.lucee-services.com/";

		return new services.LuceeCoreSource( catalog=arguments.catalog, mixedRepo=mixed );
	}

	private struct function _mavenSourceArguments() {
		var env = server.system.environment;

		return {
			  releaseRepos    = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_RELEASES  ?: env.LUCEE_MVN_REPO_RELEASES  ?: "https://repo1.maven.org/maven2/" )
			, snapshotRepos   = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_SNAPSHOTS ?: env.LUCEE_MVN_REPO_SNAPSHOTS ?: "https://central.sonatype.com/repository/maven-snapshots/" )
			, mixedRepos      = _mavenRepos( env.EXTENSIONS_MAVEN_REPOS_MIXED     ?: env.LUCEE_MVN_REPO_MIXED     ?: "https://maven.lucee-services.com/" )
			, timeout         = Val( env.EXTENSIONS_MAVEN_TIMEOUT          ?: 20  )
			, downloadTimeout = Val( env.EXTENSIONS_MAVEN_DOWNLOAD_TIMEOUT ?: 120 )
			, maxThreads      = Val( env.EXTENSIONS_MAVEN_THREADS          ?: 10  )
		};
	}

	private boolean function _envBoolean( required string name, required boolean fallback ) {
		var value = Trim( server.system.environment[ arguments.name ] ?: "" );

		return IsBoolean( value ) ? value : arguments.fallback;
	}

	private array function _mavenRepos( required string repos ) {
		return Trim( arguments.repos ) == "none" ? [] : ListToArray( arguments.repos, "," );
	}

	private string function _localCacheDir( required string name ) {
		return services.CacheDir::path( arguments.name, GetTempDirectory() & "lucee-update-cache/" );
	}

	private function _refreshJiraAsync() {
		if ( StructKeyExists( application, "jiraChangelogService" ) && !IsNull( application.jiraChangelogService ) ) {
			try {
				application.jiraChangelogService.updateIssuesAsync();
			} catch ( any e ) {
				SystemOutput( "Jira changelog refresh could not be started: #e.message#", true );
			}
		}
	}

	private function _stepStart( required string name ) {
		var started = GetTickCount();
		SystemOutput( "Maven provider: starting #arguments.name#", true );
		return started;
	}

	private function _stepEnd( required string name, required numeric started ) {
		SystemOutput( "Maven provider: finished #arguments.name# in #GetTickCount()-arguments.started#ms", true );
	}

	private function _loadServices() {
		setting requesttimeout=600;

		SystemOutput( "Storage mode [maven]: serving from the Maven repositories only, S3 is not used", true );

		var t = _stepStart( "catalog" );
		var catalog = _createCatalog();
		_stepEnd( "catalog", t );

		t = _stepStart( "extension metadata reader" );
		var extMetaReader = new services.ExtensionMetadataReader(
			  s3root               = _localCacheDir( "extensions" )
			, mavenRoot            = ""
			, mavenCdnUrl          = ""
			, mavenSource          = _createMavenSource( catalog )
			, fetchThreads         = Val( server.system.environment.EXTENSIONS_MAVEN_FETCH_THREADS ?: 5 )
			, flatFallback         = false
			, mavenOnly            = true
			, mavenOnlyMinCore     = Trim( server.system.environment.EXTENSIONS_MAVEN_ONLY_MIN_CORE ?: "" )
			, packagingBackfillMax = Val( server.system.environment.EXTENSIONS_PACKAGING_BACKFILL_MAX ?: 200 )
		);
		_stepEnd( "extension metadata reader", t );

		t = _stepStart( "core versions" );
		var coreVersions = new services.CoreVersions(
			  flatSource    = ""
			, mavenSource   = _createCoreMavenSource( catalog )
			, flatUrl       = ""
			, flatFallback  = false
			, versionFilter = Trim( server.system.environment.UPDATES_VERSION_FILTER ?: "major" )
			, cacheSeconds  = Val( server.system.environment.UPDATES_MAVEN_CACHE_SECONDS ?: 300 )
		);
		try {
			coreVersions.getVersions();
		} catch ( any e ) {
			SystemOutput( "Core versions could not be read at startup: #e.message#", true );
			SystemOutput( e, true );
		}
		_stepEnd( "core versions", t );

		t = _stepStart( "bundle download service" );
		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsCdnUrl    = ""
			, bundleS3Root        = ""
			, bundleCdnUrl        = ""
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new services.legacy.MavenMatcher()
		);
		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		_stepEnd( "bundle download service", t );

		t = _stepStart( "extension metadata (latest per artifact)" );
		extMetaReader.loadMeta();
		_stepEnd( "extension metadata (latest per artifact)", t );

		t = _stepStart( "jira cache (no remote fetch)" );
		var jiraChangelogService = new services.JiraChangelogService(
			s3root = _localCacheDir( "jira" )
		);
		// Cache only: an empty file is left empty here. The live Jira
		// fetch runs in updateIssuesAsync() after servicesReady is set.
		jiraChangelogService.loadIssues();
		_stepEnd( "jira cache (no remote fetch)", t );

		application.coreS3Root            = "";
		application.coreCdnUrl            = "";
		application.coreVersions          = coreVersions;
		application.extensionsCdnUrl      = "";
		application.extensionsS3Root      = "";
		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
		application.jiraChangelogService  = jiraChangelogService;
		application.catalog               = catalog;
		application.storageMode           = "maven";
	}

}
