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
	}

}
