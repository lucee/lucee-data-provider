component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "shared-dl-cache-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "Shared download8 cache (memory + one JSON file per key)", function() {

			it( title="writes and reads the same {data,cachedAt} shape as download8", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work, memory={} );
				var entry = { data=[ "6.2.0.321", "7.0.0.395" ], cachedAt=Now() };

				cache.dlCachePut( "luceeVersionsList", entry );

				expect( FileExists( variables.work & "luceeVersionsList.json" ) ).toBeTrue();

				var other = new services.SharedDownloadCache( cacheDir=variables.work, memory={} );
				var got   = other.dlCacheGet( "luceeVersionsList" );

				expect( got ).toHaveKey( "data" );
				expect( got ).toHaveKey( "cachedAt" );
				expect( got.data ).toBe( entry.data );
			});

			it( title="returns a memory hit without rereading the file", body=function() {
				var memory = {};
				var cache  = new services.SharedDownloadCache( cacheDir=variables.work, memory=memory );
				cache.dlCachePut( "extArtifacts_org.lucee", { data=[ "mail-extension" ], cachedAt=Now() } );

				FileDelete( variables.work & "extArtifacts_org.lucee.json" );

				var got = cache.dlCacheGet( "extArtifacts_org.lucee" );
				expect( got.data ).toBe( [ "mail-extension" ] );
			});

			it( title="returns an empty struct when the file is missing or not a struct", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "empty/", memory={} );
				expect( cache.dlCacheGet( "missing-key" ) ).toBe( {} );

				FileWrite( variables.work & "empty/not-a-struct.json", "[1,2]" );
				expect( cache.dlCacheGet( "not-a-struct" ) ).toBe( {} );
			});

			it( title="versionCompare matches download8's numeric dotted-prefix compare", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work, memory={} );
				expect( cache.versionCompare( "3.0.5", "3.0.3" ) ).toBe( 1 );
				expect( cache.versionCompare( "3.0.3", "3.0.5" ) ).toBe( -1 );
				expect( cache.versionCompare( "1.0.0.5", "1.0.0.2" ) ).toBe( 1 );
				expect( cache.versionCompare( "6.2.0.321", "6.2.0.321" ) ).toBe( 0 );
			});

		});
	}

}
