component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "info-listing-cache-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );

		variables.reader = new services.ExtensionMetadataReader( s3root=variables.work & "extensions" );
		variables.reader.loadMeta( DeserializeJSON( FileRead( dir & "staticArtifacts/testExtensionCoreVersions.json" ), false ) );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "InfoListingCache: serialised listings in memory", function() {

			it( title="builds a listing once and serves it from memory while the generation is the same", body=function() {
				var cache = new services.InfoListingCache();
				var calls = { n=0 };
				var producer = function() {
					calls.n++;
					return '{"a":1}';
				};

				var first  = cache.get( "k", "g1", producer );
				var second = cache.get( "k", "g1", producer );

				expect( first.json ).toBe( '{"a":1}' );
				expect( second.json ).toBe( '{"a":1}' );
				expect( second.etag ).toBe( first.etag );
				expect( calls.n ).toBe( 1 );
			});

			it( title="serves the old listing when the generation changed and rebuilds it in the background", body=function() {
				var cache = new services.InfoListingCache();
				var state = { value='{"v":1}' };
				var producer = function() {
					return state.value;
				};

				cache.get( "k", "g1", producer );
				state.value = '{"v":2}';

				// the stale entry right away, the rebuild runs in a thread
				expect( cache.get( "k", "g2", producer ).json ).toBe( '{"v":1}' );

				var deadline = GetTickCount() + 10000;
				while ( cache.get( "k", "g2", producer ).generation != "g2" && GetTickCount() < deadline ) {
					sleep( 20 );
				}
				var rebuilt = cache.get( "k", "g2", producer );
				expect( rebuilt.json ).toBe( '{"v":2}' );
				expect( rebuilt.generation ).toBe( "g2" );
			});

			it( title="keeps the old listing when the background rebuild fails", body=function() {
				var cache = new services.InfoListingCache();
				cache.get( "k", "g1", function() { return '{"ok":true}'; } );

				cache.get( "k", "g2", function() { throw( message="producer failed on purpose" ); } );
				var deadline = GetTickCount() + 10000;
				while ( cache.isBuilding( "k" ) && GetTickCount() < deadline ) {
					sleep( 20 );
				}

				expect( cache.get( "k", "g1", function() { return "unused"; } ).json ).toBe( '{"ok":true}' );
			});

			it( title="force builds the listing again on the request", body=function() {
				var cache = new services.InfoListingCache();
				var calls = { n=0 };
				var producer = function() {
					calls.n++;
					return '{"n":#calls.n#}';
				};

				cache.get( "k", "g1", producer );
				expect( cache.get( "k", "g1", producer, true ).json ).toBe( '{"n":2}' );
				expect( calls.n ).toBe( 2 );
			});

			it( title="the etag changes with the content", body=function() {
				var cache = new services.InfoListingCache();
				var a = cache.get( "a", "g", function() { return '{"x":1}'; } );
				var b = cache.get( "b", "g", function() { return '{"x":2}'; } );

				expect( a.etag ).notToBe( b.etag );
				expect( Left( a.etag, 1 ) ).toBe( '"' );
				expect( Right( a.etag, 1 ) ).toBe( '"' );
			});

			it( title="holds at most maxEntries listings", body=function() {
				var cache = new services.InfoListingCache( maxEntries=3 );
				for ( var i=1; i<=10; i++ ) {
					cache.get( "k#i#", "g", function() { return "{}"; } );
				}

				expect( cache.size() ).toBe( 3 );
				expect( cache.has( "k10" ) ).toBeTrue();
			});

		});

		describe( "ExtensionMetadataReader: core version buckets of the listing", function() {

			it( title="core versions that satisfy the same min core versions share a bucket and get the same listing", body=function() {
				// the min core versions of the fixture are 5.0.0.252, 5.3.0.35-ALPHA and 7.0.0.110
				var a = variables.reader.coreVersionBucket( "6.2.1.5" );
				var b = variables.reader.coreVersionBucket( "7.0.0.109" );

				expect( a ).toBe( b );
				expect( _listing( "6.2.1.5" ) ).toBe( _listing( "7.0.0.109" ) );
			});

			it( title="core versions on both sides of a min core version are different buckets and listings", body=function() {
				expect( variables.reader.coreVersionBucket( "7.0.0.109" ) ).notToBe( variables.reader.coreVersionBucket( "7.0.0.110" ) );
				expect( _listing( "7.0.0.109" ) ).notToBe( _listing( "8.0.0.0" ) );
				expect( variables.reader.coreVersionBucket( "7.0.0.110" ) ).toBe( variables.reader.coreVersionBucket( "8.0.0.0" ) );
			});

			it( title="no core version and core versions that are not a.b.c.d get a bucket of their own", body=function() {
				expect( variables.reader.coreVersionBucket( "" ) ).toBe( "any" );
				expect( variables.reader.coreVersionBucket( "7.1" ) ).toBe( "raw-7.1" );
				expect( variables.reader.coreVersionBucket( "7.1" ) ).notToBe( variables.reader.coreVersionBucket( "7.1.0.0" ) );
			});

			it( title="the meta generation changes whenever what is served is rebuilt", body=function() {
				var before = variables.reader.getMetaGeneration();
				variables.reader.reset();

				expect( variables.reader.getMetaGeneration() ).notToBe( before );
				expect( new services.ExtensionMetadataReader().getMetaGeneration() ).notToBe( variables.reader.getMetaGeneration() );
			});

		});

		describe( "the /info response built from the cached listing", function() {

			it( title="is the same as serialising the whole response in one go", body=function() {
				var listing     = variables.reader.list( type="all", withLogo=false, coreVersion="7.0.0.110" );
				var meta        = { title="t", description="", image="https://h/i.png", url="https://h", mode="production" };
				var placeholder = "__PLACEHOLDER_" & CreateUniqueId() & "__";

				var assembled = Replace( SerializeJSON( { meta=meta, extensions=placeholder }, "row" ), '"' & placeholder & '"', SerializeJSON( listing, "row" ), "one" );
				var whole     = SerializeJSON( { meta=meta, extensions=listing }, "row" );

				expect( assembled ).toBe( whole );
			});

		});
	}

	private string function _listing( required string coreVersion ) {
		return SerializeJSON( variables.reader.list( type="all", withLogo=false, coreVersion=arguments.coreVersion ), "row" );
	}

}
