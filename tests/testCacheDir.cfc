component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver/services" )
		};

		variables.work = GetTempDirectory() & "cache-dir-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "CACHE_DIR: on-disk caches for the update provider", function() {

			it( title="uses the fallback directory next to the component when CACHE_DIR is empty, so Pixl8 is unchanged", body=function() {
				var fallback = variables.work & "fallback-s3/";
				var path = services.CacheDir::path( "s3-versions", fallback, "" );

				expect( path ).toBe( fallback );
				expect( DirectoryExists( path ) ).toBeTrue();
			});

			it( title="uses CACHE_DIR/<name>/ when a cache root is set, with a trailing slash added if needed", body=function() {
				var root = variables.work & "storage";
				var path = services.CacheDir::path( "s3-versions", variables.work & "unused/", root );

				expect( path ).toBe( root & "/s3-versions/" );
				expect( DirectoryExists( path ) ).toBeTrue();
			});

			it( title="keeps each cache in its own subfolder of CACHE_DIR", body=function() {
				var root = variables.work & "shared/";
				var s3     = services.CacheDir::path( "s3-versions", variables.work & "unused/", root );
				var maven  = services.CacheDir::path( "maven-index", variables.work & "unused/", root );

				expect( s3 ).toBe( root & "s3-versions/" );
				expect( maven ).toBe( root & "maven-index/" );
				expect( s3 ).notToBe( maven );
			});

			it( title="writeAtomic writes the file and can overwrite an existing one", body=function() {
				var path = variables.work & "atomic/versions.json";
				services.CacheDir::writeAtomic( path, "{""n"":1}" );
				expect( FileRead( path ) ).toBe( "{""n"":1}" );

				services.CacheDir::writeAtomic( path, "{""n"":2}" );
				expect( FileRead( path ) ).toBe( "{""n"":2}" );

				var leftovers = DirectoryList( GetDirectoryFromPath( path ), false, "name", "*.tmp.*" );
				expect( leftovers ).toHaveLength( 0 );
			});

		});
	}

}
