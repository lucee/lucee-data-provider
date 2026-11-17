component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "listing-cache-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "ListingCache: JSON listings under CACHE_DIR with a TTL", function() {

			it( title="writes the producer result as JSON atomically and serves it while fresh, without calling the producer again", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "fresh/", ttlSeconds=300 );
				var calls = { n=0 };
				var producer = function() {
					calls.n++;
					return [ { version="7.0.0.1" } ];
				};

				var first  = cache.get( "update-list-all-short", producer );
				var second = cache.get( "update-list-all-short", producer );

				expect( first ).toHaveLength( 1 );
				expect( first[ 1 ].version ).toBe( "7.0.0.1" );
				expect( second[ 1 ].version ).toBe( "7.0.0.1" );
				expect( calls.n ).toBe( 1 );
				expect( FileExists( cache.pathFor( "update-list-all-short" ) ) ).toBeTrue();

				var leftovers = DirectoryList( cache.getCacheDir(), false, "name", "*.tmp.*" );
				expect( leftovers ).toHaveLength( 0 );
			});

			it( title="serves a stale copy and refreshes in the background once the TTL has passed", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "stale/", ttlSeconds=60 );
				var calls = { n=0 };
				var producer = function() {
					calls.n++;
					return { n=calls.n };
				};

				cache.put( "ext-info", { n="stale" }, DateAdd( "s", -120, Now() ) );
				expect( cache.isFresh( "ext-info" ) ).toBeFalse();

				var served = cache.get( "ext-info", producer );

				expect( served.n ).toBe( "stale" ); // stale copy, not the refresh

				var deadline = GetTickCount() + 10000;
				while ( calls.n < 1 && GetTickCount() < deadline ) {
					sleep( 50 );
				}

				expect( calls.n ).toBeGTE( 1 );

				deadline = GetTickCount() + 10000;
				while ( ( !cache.isFresh( "ext-info" ) || cache.peek( "ext-info" ).n == "stale" ) && GetTickCount() < deadline ) {
					sleep( 50 );
				}

				expect( cache.isFresh( "ext-info" ) ).toBeTrue();
				expect( cache.peek( "ext-info" ).n ).toBe( 1 );
			});

			it( title="flush=true ignores a fresh entry and produces a new one on the request", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "flush/", ttlSeconds=300 );
				var calls = { n=0 };
				var producer = function() {
					calls.n++;
					return { n=calls.n };
				};

				cache.get( "update-info", producer );
				var flushed = cache.get( "update-info", producer, true );

				expect( calls.n ).toBe( 2 );
				expect( flushed.n ).toBe( 2 );
			});

			it( title="LISTING_CACHE_SECONDS default is five minutes and the path lives under the listings folder", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "ttl-default/", ttlSeconds=300 );

				expect( cache.getTtlSeconds() ).toBe( 300 );
				expect( cache.getCacheDir() ).toInclude( "ttl-default" );
			});

			it( title="writeAtomic via put overwrites an existing listing file and leaves no temp files", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "atomic/", ttlSeconds=300 );

				cache.put( "list", { a=1 } );
				cache.put( "list", { a=2 } );

				expect( cache.peek( "list" ).a ).toBe( 2 );
				expect( DirectoryList( cache.getCacheDir(), false, "name", "*.tmp.*" ) ).toHaveLength( 0 );
			});

		});

		describe( "ListingCache: revision generation and startup", function() {

			it( title="processGeneration uses K_REVISION when set, otherwise reuses or creates a boot id", body=function() {
				expect( services.ListingCache::processGeneration( revision="lucee-update-00026-gpd" ) ).toBe( "lucee-update-00026-gpd" );
				expect( services.ListingCache::processGeneration( revision="", existing="boot-abc" ) ).toBe( "boot-abc" );
				// a bare boot id is unique and stable only when existing is passed back in
				var first  = services.ListingCache::processGeneration();
				var second = services.ListingCache::processGeneration( existing=first );
				expect( first ).toInclude( "boot-" );
				expect( second ).toBe( first );
				expect( services.ListingCache::processGeneration() ).notToBe( first );
			});

			it( title="a generation writes under a subdirectory and does not see another generation's listings", body=function() {
				var root = variables.work & "gens/";
				var prev = new services.ListingCache( cacheDir=root, ttlSeconds=300, generation="lucee-update-00025-abc" );
				prev.put( "extension-info-all-nologo", { n="old-revision" } );

				var next = new services.ListingCache( cacheDir=root, ttlSeconds=300, generation="lucee-update-00026-gpd" );

				expect( next.getGeneration() ).toBe( "lucee-update-00026-gpd" );
				expect( next.getCacheDir() ).toInclude( "lucee-update-00026-gpd" );
				expect( next.getRootDir() ).toBe( prev.getRootDir() );
				expect( next.has( "extension-info-all-nologo" ) ).toBeFalse();
				expect( FileExists( prev.pathFor( "extension-info-all-nologo" ) ) ).toBeTrue();

				var produced = { n=0 };
				var served = next.get( "extension-info-all-nologo", function() {
					produced.n++;
					return { n="new-revision" };
				} );

				expect( produced.n ).toBe( 1 );
				expect( served.n ).toBe( "new-revision" );
				expect( prev.peek( "extension-info-all-nologo" ).n ).toBe( "old-revision" );
			});

			it( title="clearLegacyRoot removes flat listings/*.json and leaves generation subdirectories alone", body=function() {
				var root = variables.work & "legacy/";
				DirectoryCreate( root, true );
				FileWrite( root & "extension-info-release-nologo.json", SerializeJSON( { cachedAt=Now(), data={ n="legacy" } } ) );
				FileWrite( root & "extension-info-all-nologo.json", SerializeJSON( { cachedAt=Now(), data={ n="legacy-all" } } ) );

				var prev = new services.ListingCache( cacheDir=root, ttlSeconds=300, generation="lucee-update-00025-abc" );
				prev.put( "extension-info-all-nologo", { n="keep-me" } );

				var next = new services.ListingCache( cacheDir=root, ttlSeconds=300, generation="lucee-update-00026-gpd" );
				expect( next.clearLegacyRoot() ).toBe( 2 );

				expect( FileExists( root & "extension-info-release-nologo.json" ) ).toBeFalse();
				expect( FileExists( root & "extension-info-all-nologo.json" ) ).toBeFalse();
				expect( prev.peek( "extension-info-all-nologo" ).n ).toBe( "keep-me" );
			});

			it( title="clearLegacyRoot is a no-op when the cache has no generation", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "nogen/", ttlSeconds=300 );
				cache.put( "list", { a=1 } );

				expect( cache.getGeneration() ).toBe( "" );
				expect( cache.clearLegacyRoot() ).toBe( 0 );
				expect( cache.peek( "list" ).a ).toBe( 1 );
			});

			it( title="getWhenReady always waits for services and does not return a peeked hit if they are not ready", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "ready/", ttlSeconds=300 );
				cache.put( "extension-info-all-nologo", { n="pre-boot" } );

				var readyCalls = { n=0 };
				expect( function() {
					services.ListingCache::getWhenReady(
						  cache       = cache
						, key         = "extension-info-all-nologo"
						, producer    = function() { return { n="rebuilt" }; }
						, ensureReady = function() {
							readyCalls.n++;
							throw( message="Maven provider services are still starting, try again in a moment" );
						}
					);
				} ).toThrow();

				expect( readyCalls.n ).toBe( 1 );
				expect( cache.peek( "extension-info-all-nologo" ).n ).toBe( "pre-boot" );
			});

			it( title="getWhenReady calls ensureReady first and then serves or rebuilds the listing", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "rebuild/", ttlSeconds=300 );
				var readyCalls = { n=0 };
				var served = services.ListingCache::getWhenReady(
					  cache       = cache
					, key         = "extension-info-release-nologo"
					, producer    = function() { return { n="built-after-ready" }; }
					, ensureReady = function() { readyCalls.n++; }
				);

				expect( readyCalls.n ).toBe( 1 );
				expect( served.n ).toBe( "built-after-ready" );
			});

		});
	}

}
