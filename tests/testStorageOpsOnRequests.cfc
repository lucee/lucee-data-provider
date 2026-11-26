component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	// on Cloud Run the cache folders are a Cloud Storage mount, where every file access is a billed operation:
	// a request is answered from memory, the folder is only read by an instance that has no copy yet

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "storage-ops-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "ListingCache serves from memory", function() {

			it( title="a cached listing is served from memory, the file is not read again", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "mem/", ttlSeconds=300 );
				var calls = { n=0 };
				var producer = function() { calls.n++; return { n=calls.n }; };

				cache.get( "update-info-7.0.0.1-en", producer );
				// another process can't change what this one serves: the file is not looked at any more
				FileWrite( cache.pathFor( "update-info-7.0.0.1-en" ), "not json" );
				expect( cache.get( "update-info-7.0.0.1-en", producer ).n ).toBe( 1 );
				expect( calls.n ).toBe( 1 );
			});

			it( title="a cold instance takes the listing another instance wrote", body=function() {
				var first = new services.ListingCache( cacheDir=variables.work & "cold/", ttlSeconds=300 );
				first.put( "update-list-all-short", [ "7.0.0.1" ] );

				var second = new services.ListingCache( cacheDir=variables.work & "cold/", ttlSeconds=300 );
				var calls = { n=0 };
				var served = second.get( "update-list-all-short", function() { calls.n++; return []; } );
				expect( served ).toBe( [ "7.0.0.1" ] );
				expect( calls.n ).toBe( 0 );
				expect( second.memorySize() ).toBe( 1 );
			});

			it( title="an unchanged listing is not written again", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "unchanged/", ttlSeconds=300 );
				cache.put( "list", { a=1 } );
				FileDelete( cache.pathFor( "list" ) );

				cache.put( "list", { a=1 } );
				expect( FileExists( cache.pathFor( "list" ) ) ).toBeFalse( "unchanged data was written again" );
				expect( cache.isFresh( "list" ) ).toBeTrue();

				cache.put( "list", { a=2 } );
				expect( FileExists( cache.pathFor( "list" ) ) ).toBeTrue();
				expect( cache.peek( "list" ).a ).toBe( 2 );
			});

			it( title="beyond maxMemoryEntries a listing is still served, from the file", body=function() {
				var cache = new services.ListingCache( cacheDir=variables.work & "bounded/", ttlSeconds=300, maxMemoryEntries=1 );
				cache.put( "a", { n="a" } );
				cache.put( "b", { n="b" } );
				expect( cache.memorySize() ).toBe( 1 );
				expect( cache.peek( "b" ).n ).toBe( "b" );
			});
		});

		describe( "SharedDownloadCache does not look up a missing key on every call", function() {

			it( title="a miss is remembered for a minute, a put ends it", body=function() {
				var folder = variables.work & "dl/";
				DirectoryCreate( folder, true );
				var cache = new services.SharedDownloadCache( cacheDir=folder, memory={} );

				expect( cache.dlCacheGet( "extver_org.lucee_x" ) ).toBe( {} );
				FileWrite( folder & "extver_org.lucee_x.json", SerializeJson( { data=[ "1.0" ] } ) );
				expect( cache.dlCacheGet( "extver_org.lucee_x" ) ).toBe( {}, "the miss is looked up again" );

				cache.dlCachePut( "extver_org.lucee_x", { data=[ "2.0" ] } );
				expect( cache.dlCacheGet( "extver_org.lucee_x" ).data ).toBe( [ "2.0" ] );
			});
		});
	}
}
