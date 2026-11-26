component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/forgeboxmavenrest" : ExpandPath( dir & "../apps/updateserver-maven/rest" )
		};

		variables.base = "https://downloads.ortussolutions.com/lucee/lucee/";
	}

	function run( testResults, testBox ) {

		describe( "Maven UpdateProvider forgebox/{version}", function() {

			it( title="points to the engine package of the version, -light for Lucee Light", body=function() {
				var provider = new forgeboxmavenrest.UpdateProvider();

				expect( provider.forgeboxEngineLocation( "7.0.6.10" ) ).toBe( base & "7.0.6.10/cf-engine-7.0.6.10.zip" );
				expect( provider.forgeboxEngineLocation( "7.0.6.10", true ) ).toBe( base & "7.0.6.10/cf-engine-7.0.6.10-light.zip" );
				expect( provider.forgeboxEngineLocation( "7.1.3.183-SNAPSHOT" ) ).toBe( base & "7.1.3.183-SNAPSHOT/cf-engine-7.1.3.183-SNAPSHOT.zip" );
			});

			it( title="upper cases the qualifier, as in the version list", body=function() {
				var provider = new forgeboxmavenrest.UpdateProvider();

				expect( provider.forgeboxEngineLocation( "5.3.4.54-rc" ) ).toBe( base & "5.3.4.54-RC/cf-engine-5.3.4.54-RC.zip" );
			});

			it( title="does not redirect what is not a Lucee version", body=function() {
				var provider = new forgeboxmavenrest.UpdateProvider();

				for ( var bad in [ "", "7.0.6", "latest", "7.0.6.10/../x", "7.0.6.10-RC-1", "//evil.example/x", "7.0.6.10?x=1" ] ) {
					expect( provider.forgeboxEngineLocation( bad ) ).toBe( "", bad );
				}
			});

			it( title="answers with a 302 and no longer a 501", body=function() {
				var src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
				var fn  = Mid( src, Find( "function downloadForgebox", src ), 900 );

				expect( fn ).toInclude( 'header statuscode="302"' );
				expect( fn ).notToInclude( "_notWithoutS3" );
			});

		});
	}

}
