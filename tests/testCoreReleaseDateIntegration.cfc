component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/releasedateintservices" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "getdate/{version} against Maven Central", function() {

			it( title="one HEAD to the pom on Maven Central gives the release date of 6.2.3.35", body=function() {
				var real = new releasedateintservices.CoreVersions( flatSource="" );
				var coreVersions = {
					  isOffered   : function( version ) { return real.isOffered( version ); }
					, getVersions : function() { return { "x"={ version="6.2.3.35" } }; }
				};
				var catalog = {
					getVersionDetail : function( version ) {
						return { pom="https://repo1.maven.org/maven2/org/lucee/lucee/6.2.3.35/lucee-6.2.3.35.pom" };
					}
				};
				var rd = new releasedateintservices.CoreReleaseDate( coreVersions=coreVersions, catalog=catalog );

				var t = GetTickCount();
				var d = rd.get( "6.2.3.35" );
				expect( IsDate( d ) ).toBeTrue();
				expect( Year( d ) ).toBe( 2025 );
				expect( GetTickCount() - t ).toBeLT( 6000 );
			});

		});
	}

}
