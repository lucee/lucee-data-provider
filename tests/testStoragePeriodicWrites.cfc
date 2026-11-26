component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	// the background refreshes (catalog every 10 minutes, Maven metadata every 5) must not write the shared cache
	// folder again when nothing changed, and must not refresh the same key several times at once

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "storage-periodic-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "SharedDownloadCache.dlCachePut", function() {

			it( title="does not write the file again when only cachedAt changed", body=function() {
				var folder = variables.work & "put/";
				DirectoryCreate( folder, true );
				var cache = new services.SharedDownloadCache( cacheDir=folder, memory={} );
				var file  = folder & "extver_org.lucee_mail-extension.json";

				cache.dlCachePut( "extver_org.lucee_mail-extension", { data=[ "1.0.0.2", "1.0.0.1" ], cachedAt=DateAdd( "n", -20, Now() ) } );
				expect( FileExists( file ) ).toBeTrue();
				FileDelete( file );

				var now = Now();
				cache.dlCachePut( "extver_org.lucee_mail-extension", { data=[ "1.0.0.2", "1.0.0.1" ], cachedAt=now } );
				expect( FileExists( file ) ).toBeFalse( "unchanged data was written again" );
				// the copy in memory has the new time, so the key is not refreshed again right away
				expect( cache.dlCacheGet( "extver_org.lucee_mail-extension" ).cachedAt ).toBe( now );

				cache.dlCachePut( "extver_org.lucee_mail-extension", { data=[ "1.0.0.3", "1.0.0.2", "1.0.0.1" ], cachedAt=Now() } );
				expect( FileExists( file ) ).toBeTrue();
			});

			it( title="data read from the file is not written back unchanged", body=function() {
				var folder = variables.work & "read/";
				DirectoryCreate( folder, true );
				var file = folder & "extArtifacts_org.lucee.json";
				FileWrite( file, SerializeJson( { data=[ "mail-extension" ], cachedAt=DateAdd( "n", -30, Now() ) } ) );

				var cache = new services.SharedDownloadCache( cacheDir=folder, memory={} );
				expect( cache.dlCacheGet( "extArtifacts_org.lucee" ).data ).toBe( [ "mail-extension" ] );
				FileDelete( file );
				cache.dlCachePut( "extArtifacts_org.lucee", { data=[ "mail-extension" ], cachedAt=Now() } );
				expect( FileExists( file ) ).toBeFalse();
			});
		});

		describe( "LuceeCatalog background refresh", function() {

			it( title="a stale key is refreshed once, not once per call", body=function() {
				var folder = variables.work & "single/";
				DirectoryCreate( folder, true );
				var cache = new services.SharedDownloadCache( cacheDir=folder, memory={} );
				cache.dlCachePut( "extver_org.lucee_mail-extension", { data=[ "1.0.0.1" ], cachedAt=DateAdd( "n", -20, Now() ) } );

				var calls = { n=0 };
				var catalog = new services.LuceeCatalog(
					  cache                 = cache
					, groups                = [ "org.lucee" ]
					, listExtensionVersions = function( groupId, artifactId ) {
						calls.n++;
						sleep( 500 );
						return [ "1.0.0.1" ];
					}
				);

				for ( var i = 1; i <= 5; i++ ) {
					expect( catalog.getExtensionVersions( "org.lucee", "mail-extension" ) ).toBe( [ "1.0.0.1" ] );
				}
				var deadline = GetTickCount() + 5000;
				while ( calls.n == 0 && GetTickCount() < deadline ) sleep( 20 );
				sleep( 800 );
				expect( calls.n ).toBe( 1 );
			});
		});
	}
}
