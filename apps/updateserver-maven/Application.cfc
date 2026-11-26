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
		application.servicesFailedAt      = 0;
		application.servicesLoading       = false;
		application.listingCache          = _createListingCache();
		// the serialised /info listings, in memory (see services.InfoListingCache)
		application.infoListingCache      = new services.InfoListingCache();

		_startServicesLoad();
	}

	/**
	 * Load the services in a background thread. A failure (for example an IO
	 * error on the shared cache folder) is not kept: the next request after
	 * SERVICES_RETRY_SECONDS starts a new load, see _retryFailedServicesLoad().
	 */
	private function _startServicesLoad() {
		var start = false;
		lock name="lucee-provider-maven-load-services" type="exclusive" timeout=5 throwOnTimeout=false {
			if ( !( application.servicesLoading ?: false ) ) {
				application.servicesLoading = true;
				application.servicesError   = "";
				start = true;
			}
		}
		if ( !start ) {
			return;
		}

		thread action="run" name="lucee-provider-maven-load-services-#CreateUUID()#" {
			try {
				setting requesttimeout=600;
				// a storage error is often gone a few seconds later: try again right
				// away before the load counts as failed
				loaded    = false;
				lastError = "";
				for ( attempt = 1; attempt <= 3 && !loaded; attempt++ ) {
					try {
						_loadServices();
						loaded = true;
					} catch ( any e ) {
						lastError = e;
						SystemOutput( "Maven provider services load attempt #attempt# of 3 failed: #e.message#", true );
						if ( attempt < 3 ) {
							sleep( attempt * 2000 );
						}
					}
				}

				if ( loaded ) {
					application.servicesError = "";
					application.servicesReady = true;
					services.ProviderHealth::markHealthy();
					services.ProviderHealth::markReady();
					SystemOutput( "Maven provider services are ready", true );
					// Jira is filled in the background and must never gate readiness
					_refreshJiraAsync();
				} else {
					// services loaded earlier (if any) are kept and still served
					application.servicesFailedAt = GetTickCount();
					application.servicesError    = lastError.message;
					services.ProviderHealth::markFailing();
					SystemOutput( "Maven provider services failed to load, retrying in #_servicesRetrySeconds()#s: #lastError.message#", true );
					SystemOutput( lastError, true );
				}
			} catch ( any e ) {
				application.servicesFailedAt = GetTickCount();
				application.servicesError    = e.message;
				SystemOutput( "Maven provider services failed to load: #e.message#", true );
			} finally {
				application.servicesLoading = false;
			}
		}
	}

	private function _retryFailedServicesLoad() {
		if ( !Len( application.servicesError ?: "" ) ) {
			return;
		}
		if ( ( GetTickCount() - Val( application.servicesFailedAt ?: 0 ) ) < _servicesRetrySeconds() * 1000 ) {
			return;
		}
		_startServicesLoad();
	}

	private numeric function _servicesRetrySeconds() {
		var seconds = Val( server.system.environment.SERVICES_RETRY_SECONDS ?: 30 );

		return seconds > 0 ? seconds : 30;
	}

	function onRequestStart() output=true {
		// Below the platform's request timeout (Cloud Run: 300s), so a request
		// that runs too long ends with Lucee's own error, not a cut connection.
		// Slow work (service load, meta and listing refreshes) runs in threads
		// with their own timeout.
		setting requesttimeout=_requestTimeoutSeconds();
		header name="Content-Security-Policy" value="sandbox; object-src 'none'; script-src 'none'";

		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			// the services in use stay until the new ones are loaded, a failed
			// reload keeps serving them
			try {
				_loadServices();
				application.servicesError = "";
				application.servicesReady = true;
				services.ProviderHealth::markHealthy();
				services.ProviderHealth::markReady();
				_refreshJiraAsync();
			} catch ( any e ) {
				SystemOutput( "Maven provider services reload failed, the loaded services are kept: #e.message#", true );
			}
		}

		var allowedPaths = [ "rest", "healthcheck", "index.cfm", "warmup" ];
		var requestedPath = ListFirst( Trim( cgi.script_name ), "/" );

		if ( !ArrayFindNoCase( allowedPaths, requestedPath ) ) {
			content reset=true;
			header statuscode=404;
			echo( "not found" );
			abort;
		}

		// only while the services are not ready: a failed load is started again, and a REST request is answered
		// with 503 right away instead of waiting for the load (clients retry, and /ready/ keeps new instances out
		// of rotation until this is no longer the case)
		if ( !( application.servicesReady ?: false ) ) {
			_retryFailedServicesLoad();

			if ( requestedPath == "rest" ) {
				content reset=true type="text/plain";
				header statuscode=503 statustext="Service Unavailable";
				header name="Retry-After" value=_retryAfterSeconds();
				echo( "The provider is starting, try again in a moment" );
				abort;
			}
		}
	}

	private numeric function _retryAfterSeconds() {
		var seconds = Val( server.system.environment.NOT_READY_RETRY_AFTER_SECONDS ?: 30 );

		return seconds > 0 ? Int( seconds ) : 30;
	}

	private numeric function _requestTimeoutSeconds() {
		var seconds = Val( server.system.environment.REQUEST_TIMEOUT_SECONDS ?: 240 );

		return seconds > 0 ? Int( seconds ) : 240;
	}

	private function _createListingCache() {
		var seconds = Val( server.system.environment.LISTING_CACHE_SECONDS ?: 300 );
		if ( seconds <= 0 ) {
			seconds = 300;
		}

		// Cloud Run: isolate by K_REVISION so a new revision never serves the previous
		// revision's listings/*.json. Elsewhere: a per-process boot id, reused for
		// the life of this application scope.
		var generation = services.ListingCache::processGeneration(
			  revision = server.system.environment.K_REVISION ?: ""
			, existing = application.listingCacheGeneration ?: ""
		);
		application.listingCacheGeneration = generation;

		var cache = new services.ListingCache(
			  cacheDir    = services.CacheDir::path( "listings", GetTempDirectory() & "lucee-update-cache/listings/" )
			, ttlSeconds  = seconds
			, generation  = generation
		);
		// drop leftover extension-info-*.json from the pre-generation layout
		cache.clearLegacyRoot();

		return cache;
	}

	// seconds the extension meta (Maven listing) is used before it is rebuilt in the background, see ExtensionMetadataReader
	private numeric function _metaTtl() {
		var env     = server.system.environment;
		var seconds = Val( env.EXTENSIONS_META_CACHE_SECONDS ?: ( env.LISTING_CACHE_SECONDS ?: 300 ) );

		return seconds > 0 ? seconds : 300;
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
			, maxThreads      = Val( env.EXTENSIONS_MAVEN_THREADS          ?: 4   )
			// shared by the instances: maven-metadata.xml reads (MAVEN_METADATA_CACHE_SECONDS) and HEAD results
			, cacheDir        = services.CacheDir::path( "maven", GetTempDirectory() & "lucee-update-cache/maven/" )
			, metadataTtl     = Val( env.MAVEN_METADATA_CACHE_SECONDS      ?: 300 )
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
			, metaTtl              = _metaTtl()
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
		try {
			jiraChangelogService.loadIssues();
		} catch ( any e ) {
			// only the changelog cache, it is filled by updateIssuesAsync() later
			SystemOutput( "Jira issues cache could not be loaded at startup: #e.message#", true );
		}
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
