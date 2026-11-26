component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "cache-dir-maven-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "CACHE_DIR for the Maven-only Cloud Run app", function() {

			it( title="puts listings, maven-index and extensions under CACHE_DIR when a cache root is set", body=function() {
				var root = variables.work & "storage/";
				var listings = services.CacheDir::path( "listings", variables.work & "unused/", root );
				var maven    = services.CacheDir::path( "maven-index", variables.work & "unused/", root );
				var ext      = services.CacheDir::path( "extensions", variables.work & "unused/", root );

				expect( listings ).toBe( root & "listings/" );
				expect( maven ).toBe( root & "maven-index/" );
				expect( ext ).toBe( root & "extensions/" );
				expect( DirectoryExists( listings ) ).toBeTrue();
			});

			it( title="writeAtomic writes and overwrites a cache file", body=function() {
				var path = variables.work & "atomic/list.json";
				services.CacheDir::writeAtomic( path, "{""n"":1}" );
				services.CacheDir::writeAtomic( path, "{""n"":2}" );
				expect( FileRead( path ) ).toBe( "{""n"":2}" );
				expect( DirectoryList( GetDirectoryFromPath( path ), false, "name", "*.tmp.*" ) ).toHaveLength( 0 );
			});

			it( title="readText treats a missing or unreadable cache file as a cache miss", body=function() {
				var path = variables.work & "read/list.json";
				expect( services.CacheDir::readText( path ) ).toBe( "" );

				services.CacheDir::writeAtomic( path, "{""n"":1}" );
				expect( services.CacheDir::readText( path ) ).toBe( "{""n"":1}" );

				// a path that exists but cannot be read as a file
				var dir = variables.work & "read/folder.json";
				DirectoryCreate( dir, true );
				expect( services.CacheDir::readText( dir ) ).toBe( "" );
			});

			it( title="readText reads again with a fresh open when a read fails", body=function() {
				var path = variables.work & "retry/meta.json";
				services.CacheDir::writeAtomic( path, "{""n"":3}" );
				var calls = { n=0 };
				var reader = function( p ) {
					calls.n++;
					if ( calls.n < 3 ) {
						throw( type="java.io.IOException", message="Stale file handle" );
					}
					return FileRead( arguments.p );
				};
				expect( services.CacheDir::readText( path, false, reader ) ).toBe( "{""n"":3}" );
				expect( calls.n ).toBe( 3 );
			});

			it( title="readText uses the local copy when the shared file cannot be read", body=function() {
				var path = variables.work & "mirror/extensions.json";
				services.CacheDir::writeAtomic( path, "{""good"":true}", true );
				expect( FileExists( services.CacheDir::mirrorPath( path ) ) ).toBeTrue();

				var failing = function( p ) {
					throw( type="java.io.IOException", message="Stale file handle" );
				};
				expect( services.CacheDir::readText( path, true, failing ) ).toBe( "{""good"":true}" );
				// without the local copy it is a cache miss
				expect( services.CacheDir::readText( path, false, failing ) ).toBe( "" );

				FileDelete( services.CacheDir::mirrorPath( path ) );
			});

			it( title="readText refreshes the local copy after a good read", body=function() {
				var path = variables.work & "mirror2/issues.json";
				services.CacheDir::writeAtomic( path, "v1" );
				expect( services.CacheDir::readText( path, true ) ).toBe( "v1" );
				expect( FileRead( services.CacheDir::mirrorPath( path ) ) ).toBe( "v1" );
				FileDelete( services.CacheDir::mirrorPath( path ) );
			});

			it( title="nests app caches under provider/ when only CACHE_DIRECTORY is set", body=function() {
				var shared = variables.work & "download";
				var root = services.CacheDir::envCacheRoot( cacheDir="", localCacheDir="", cacheDirectory=shared );
				expect( root ).toBe( shared & "/provider" );

				var listings = services.CacheDir::path( "listings", variables.work & "unused/", root );
				expect( listings ).toBe( shared & "/provider/listings/" );
			});

			it( title="prefers an explicit CACHE_DIR over CACHE_DIRECTORY for app-specific files", body=function() {
				var root = services.CacheDir::envCacheRoot(
					  cacheDir       = variables.work & "provider-explicit"
					, localCacheDir  = ""
					, cacheDirectory = variables.work & "download"
				);
				expect( root ).toBe( variables.work & "provider-explicit" );
			});

		});
	}

}
