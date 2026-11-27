component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			  "/lcmavenrest" : ExpandPath( dir & "../apps/updateserver-maven/rest" )
			, "/services"    : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.src     = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
		variables.appSrc  = FileRead( ExpandPath( dir & "../apps/updateserver-maven/Application.cfc" ) );
		variables.keys    = [ "servicesReady", "servicesError", "bundleDownloadService", "coreS3Root", "coreCdnUrl", "jiraChangelogService", "coreVersions", "coreListingCache" ];
	}

	function run( testResults, testBox ) {

		describe( "CoreVersions generation: changes only when the versions change", function() {

			it( title="keeps the generation when a load gives the same versions, a new one when they changed", body=function() {
				var state    = { versions=_versions( [ "6.2.0.321" ] ) };
				var versions = _newCoreVersions( state );

				versions.getVersions();
				var first = versions.getGeneration();

				versions.reset();
				versions.getVersions();
				expect( versions.getGeneration() ).toBe( first );

				state.versions = _versions( [ "6.2.0.321", "6.2.0.322" ] );
				versions.reset();
				versions.getVersions();
				expect( versions.getGeneration() ).notToBe( first );
			});

			it( title="reads stale versions again in the background, not on the request", body=function() {
				var state    = { versions=_versions( [ "6.2.0.321" ] ), reads=0 };
				var versions = _newCoreVersions( state, 1 );

				versions.getVersions();
				var first = versions.getGeneration();
				state.versions = _versions( [ "6.2.0.321", "6.2.0.400" ] );
				sleep( 1100 );

				// the request does not wait, the generation changes once the background read is done
				versions.refreshIfStale();
				var deadline = GetTickCount() + 10000;
				while ( versions.getGeneration() == first && GetTickCount() < deadline ) {
					sleep( 20 );
				}
				expect( versions.getGeneration() ).notToBe( first );
			});

			it( title="reads the versions on the request when they were never read", body=function() {
				var state    = { versions=_versions( [ "6.2.0.321" ] ), reads=0 };
				var versions = _newCoreVersions( state );

				versions.refreshIfStale();
				expect( state.reads ).toBe( 1 );
			});

		});

		describe( "JiraChangeLogService generation: changes only when the issues change", function() {

			it( title="keeps the generation when the same issues are loaded again, a new one when they changed", body=function() {
				var work = GetTempDirectory() & "jira-gen-" & CreateUniqueId() & "/";
				DirectoryCreate( work, true );
				try {
					var service = new services.JiraChangeLogService();
					service.setS3Root( work );
					service.loadIssues( force=false );
					var first = service.getIssuesGeneration();

					service.loadIssues( force=false );
					expect( service.getIssuesGeneration() ).toBe( first );

					var cached = QueryNew( "id,key,summary,self,type,created,updated,priority,status,fixVersions,labels" );
					QueryAddRow( cached );
					QuerySetCell( cached, "id", "1" );
					QuerySetCell( cached, "key", "LDEV-1" );
					QuerySetCell( cached, "summary", "cached" );
					QuerySetCell( cached, "fixVersions", [ "6.2.0.321" ] );
					QuerySetCell( cached, "labels", [] );
					FileWrite( work & "/issues.json", SerializeJSON( cached ) );

					service.loadIssues( force=false );
					expect( service.getIssuesGeneration() ).notToBe( first );
				} finally {
					DirectoryDelete( work, true );
				}
			});

		});

		describe( "Maven UpdateProvider info/{version} and list: cached JSON, as the extension info", function() {

			beforeEach( function() {
				variables.saved = {};
				for ( var key in variables.keys ) {
					variables.saved[ key ] = application[ key ] ?: javacast( "null", 0 );
				}
				variables.state = { versions=_versions( [ "6.1.0.1", "6.2.0.300", "6.2.0.321", "7.0.0.1" ] ), reads=0, changelogs=0, jiraGen="j1" };
				application.servicesReady         = true;
				application.servicesError         = "";
				application.bundleDownloadService = "";
				application.coreS3Root            = "";
				application.coreCdnUrl            = "";
				application.coreVersions          = _newCoreVersions( variables.state );
				application.jiraChangelogService  = _newJira( variables.state );
				application.coreListingCache      = new services.InfoListingCache();
			});

			afterEach( function() {
				for ( var key in variables.keys ) {
					if ( IsNull( variables.saved[ key ] ) ) {
						StructDelete( application, key );
					} else {
						application[ key ] = variables.saved[ key ];
					}
				}
			});

			it( title="serves the info of a version as JSON, built once while nothing changed", body=function() {
				var provider = new lcmavenrest.UpdateProvider();

				var first = provider.infoEntry( "6.1.0.1" );
				var info  = DeserializeJSON( first.json );
				expect( info.type ).toBe( "info" );
				expect( info.available ).toBe( "6.2.0.321" );
				expect( info.otherVersions ).toBe( [ "6.1.0.1", "6.2.0.300", "6.2.0.321" ] );
				expect( first.etag ).toBe( '"' & LCase( Hash( first.json, "MD5" ) ) & '"' );
				expect( IsDate( first.builtAt ) ).toBeTrue();

				var second = new lcmavenrest.UpdateProvider().infoEntry( "6.1.0.1" );
				expect( second.json ).toBe( first.json );
				expect( second.etag ).toBe( first.etag );
				expect( variables.state.changelogs ).toBe( 1 );

				// update-for/{version} answers from the same entry
				expect( provider.getInfoSimple( "6.1.0.1" ) ).toBe( "6.2.0.321" );
				expect( variables.state.changelogs ).toBe( 1 );
			});

			it( title="serves the old info once the versions changed and rebuilds it in the background", body=function() {
				var provider = new lcmavenrest.UpdateProvider();
				var first    = provider.infoEntry( "6.1.0.1" );

				variables.state.versions = _versions( [ "6.1.0.1", "6.2.0.300", "6.2.0.321", "6.2.0.400", "7.0.0.1" ] );
				application.coreVersions.reset();

				expect( provider.infoEntry( "6.1.0.1" ).json ).toBe( first.json );

				var deadline = GetTickCount() + 10000;
				while ( provider.infoEntry( "6.1.0.1" ).json == first.json && GetTickCount() < deadline ) {
					sleep( 20 );
				}
				expect( DeserializeJSON( provider.infoEntry( "6.1.0.1" ).json ).available ).toBe( "6.2.0.400" );
			});

			it( title="rebuilds the info once the Jira issues of the changelog changed", body=function() {
				var provider = new lcmavenrest.UpdateProvider();
				var first    = provider.infoEntry( "6.1.0.1" );

				variables.state.jiraGen = "j2";

				var deadline = GetTickCount() + 10000;
				while ( provider.infoEntry( "6.1.0.1" ).generation == first.generation && GetTickCount() < deadline ) {
					sleep( 20 );
				}
				expect( provider.infoEntry( "6.1.0.1" ).generation ).notToBe( first.generation );
				expect( variables.state.changelogs ).toBe( 2 );
			});

			it( title="does not cache an error answer", body=function() {
				application.coreVersions = {
					  refreshIfStale = function() {}
					, getGeneration  = function() { return "broken"; }
					, getVersions    = function() { throw( type="test", message="the versions can't be read" ); }
				};
				var provider = _quietProvider();

				var entry = provider.infoEntry( "6.1.0.1" );
				expect( entry ).toHaveKey( "error" );
				expect( entry.error.type ).toBe( "error" );
				expect( application.coreListingCache.has( "update-info-6.1.0.1-en" ) ).toBeFalse();
			});

			it( title="serves the list, short and extended, from the cache", body=function() {
				var provider = new lcmavenrest.UpdateProvider();

				var short = DeserializeJSON( provider.listEntry().json );
				expect( ArrayLen( short ) ).toBe( 4 );
				expect( short[ 1 ].version ).toBe( "6.1.0.1" );
				expect( short[ 1 ].vs ).toBe( services.VersionUtils::toVersionSortable( "6.1.0.1" ) );

				var extended = provider.listEntry( extended=true );
				expect( extended.json ).toInclude( '"version":"7.0.0.1"' );
				expect( provider.listEntry( extended=true ).etag ).toBe( extended.etag );
				expect( application.coreListingCache.size() ).toBe( 2 );
			});

			it( title="answers JSON with ETag, Last-Modified, Cache-Control and a 304, flush is ignored", body=function() {
				var fn = Mid( variables.src, Find( 'restpath="info/{version}"', variables.src ), 500 );
				expect( fn ).toInclude( "_answerListing( infoEntry( arguments.version, arguments.language ) )" );
				expect( fn ).notToInclude( "url.flush" );

				var answer = Mid( variables.src, Find( "private any function _answerListing", variables.src ), 900 );
				expect( answer ).toInclude( "services.HttpCaching::wantsJson()" );
				expect( answer ).toInclude( "services.HttpCaching::respondJson(" );
				expect( answer ).toInclude( "lastModified = arguments.entry.builtAt" );

				expect( FindNoCase( "_cachedListing", variables.src ) ).toBe( 0 );
				expect( FindNoCase( "ListingCache::getWhenReady", variables.src ) ).toBe( 0 );
				expect( variables.appSrc ).toInclude( "application.coreListingCache      = new services.InfoListingCache(" );
			});

		});

		describe( "HttpCaching response headers", function() {

			it( title="has the ETag, Cache-Control, Vary and Last-Modified of a JSON listing", body=function() {
				var built   = Now();
				var headers = services.HttpCaching::responseHeaders( 'W/"abc"', built );

				expect( headers[ "ETag" ] ).toBe( 'W/"abc"' );
				expect( headers[ "Cache-Control" ] ).toBe( services.HttpCaching::cacheControl() );
				expect( headers[ "Vary" ] ).toBe( "Accept, Accept-Encoding" );
				expect( headers[ "Last-Modified" ] ).toBe( GetHttpTimeString( built ) );
				expect( services.HttpCaching::responseHeaders( 'W/"abc"' ) ).notToHaveKey( "Last-Modified" );
			});

		});
	}

	// without the update-provider log, which only exists in the image
	private any function _quietProvider() {
		var provider = new lcmavenrest.UpdateProvider();
		provider._mixin = variables._mixin;
		provider._mixin( "logger", function() {} );

		return provider;
	}

	// called as a method of the provider, so it sets its variables scope
	function _mixin( required string name, required any fn ) {
		variables[ arguments.name ] = arguments.fn;
	}

	// { sortable version : { version, jar } }, as the flat source answers
	private struct function _versions( required array list ) {
		var result = {};
		for ( var v in arguments.list ) {
			result[ services.VersionUtils::toVersionSortable( v ) ] = { "version"=v, "jar"="lucee-#v#.jar" };
		}
		return result;
	}

	private any function _newCoreVersions( required struct state, numeric cacheSeconds=300 ) {
		var s = arguments.state;
		var source = {
			getVersions = function() {
				s.reads = ( s.reads ?: 0 ) + 1;
				return Duplicate( s.versions );
			}
		};

		return new services.CoreVersions( flatSource=source, mavenSource="", flatFallback=true, cacheSeconds=arguments.cacheSeconds );
	}

	private struct function _newJira( required struct state ) {
		var s = arguments.state;

		return {
			  getChangeLog        = function() { s.changelogs++; return {}; }
			, getIssuesGeneration = function() { return s.jiraGen; }
			, refreshIfStale      = function() {}
		};
	}

}
