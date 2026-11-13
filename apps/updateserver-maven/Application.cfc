/**
 * Maven-only REST update/extension provider for Cloud Run.
 * No S3, no S3 credentials, no Sentry. Listings are cached as JSON under
 * CACHE_DIR (default /storage). /healthcheck/ is a separate application so it
 * can answer before this one has loaded its services.
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
			} catch ( any e ) {
				application.servicesError = e.message;
				SystemOutput( "Maven provider services failed to load: #e.message#", true );
				SystemOutput( e, true );
			}
		}
	}

	function onRequestStart() output=true {
		header name="Content-Security-Policy" value="sandbox; object-src 'none'; script-src 'none'";

		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			application.servicesReady = false;
			_loadServices();
			application.servicesReady = true;
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

	private function _createMavenSource() {
		var args = _mavenSourceArguments();

		return StructIsEmpty( args ) ? "" : new services.MavenExtensionSource( argumentCollection=args );
	}

	private function _createCoreMavenSource() {
		var args = _mavenSourceArguments();

		return StructIsEmpty( args ) ? "" : new services.MavenCoreSource( argumentCollection=args );
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

	private function _loadServices() {
		setting requesttimeout=600;

		SystemOutput( "Storage mode [maven]: serving from the Maven repositories only, S3 is not used", true );

		var extMetaReader = new services.ExtensionMetadataReader(
			  s3root               = _localCacheDir( "extensions" )
			, mavenRoot            = ""
			, mavenCdnUrl          = ""
			, mavenSource          = _createMavenSource()
			, fetchThreads         = Val( server.system.environment.EXTENSIONS_MAVEN_FETCH_THREADS ?: 5 )
			, flatFallback         = false
			, mavenOnly            = true
			, mavenOnlyMinCore     = Trim( server.system.environment.EXTENSIONS_MAVEN_ONLY_MIN_CORE ?: "" )
			, packagingBackfillMax = Val( server.system.environment.EXTENSIONS_PACKAGING_BACKFILL_MAX ?: 200 )
		);

		var coreVersions = new services.CoreVersions(
			  flatSource    = ""
			, mavenSource   = _createCoreMavenSource()
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

		var jiraChangelogService = new services.JiraChangelogService(
			s3root = _localCacheDir( "jira" )
		);

		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsCdnUrl    = ""
			, bundleS3Root        = ""
			, bundleCdnUrl        = ""
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new services.legacy.MavenMatcher()
		);

		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		extMetaReader.loadMeta();

		jiraChangelogService.loadIssues();
		jiraChangelogService.updateIssuesAsync();

		application.coreS3Root            = "";
		application.coreCdnUrl            = "";
		application.coreVersions          = coreVersions;
		application.extensionsCdnUrl      = "";
		application.extensionsS3Root      = "";
		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
		application.jiraChangelogService  = jiraChangelogService;
		application.storageMode           = "maven";
	}

}
