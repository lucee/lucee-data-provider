component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			  "/offerlegacy" : ExpandPath( dir & "../apps/updateserver/services" )
			, "/offermaven"  : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.mavenSrc  = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
		variables.legacySrc = FileRead( ExpandPath( dir & "../apps/updateserver/rest/UpdateProvider.cfc" ) );
	}

	function run( testResults, testBox ) {

		describe( "the update offered to an installed version (update-for, info)", function() {

			it( title="a stable version is never offered an alpha", body=function() {
				expect( _offer( "7.2.0.45-ALPHA", "7.0.5.41" ) ).toBe( [ false, false ] );
				expect( _offer( "7.2.0.45-ALPHA", "7.1.2.195" ) ).toBe( [ false, false ] );
				expect( _offer( "7.1.3.1-ALPHA", "7.1.2.195" ) ).toBe( [ false, false ] );
			});

			it( title="a stable version is not offered a pre-release of another major.minor", body=function() {
				expect( _offer( "7.1.3.183-SNAPSHOT", "7.0.5.41" ) ).toBe( [ false, false ] );
				expect( _offer( "7.1.2.194-RC", "7.0.5.41" ) ).toBe( [ false, false ] );
				expect( _offer( "7.1.0.1-BETA", "7.0.5.41" ) ).toBe( [ false, false ] );
				expect( _offer( "8.0.1.121-SNAPSHOT", "7.1.2.195" ) ).toBe( [ false, false ] );
			});

			it( title="a stable version is offered releases and pre-releases (not alphas) of its own major.minor", body=function() {
				expect( _offer( "7.1.2.195", "7.0.5.41" ) ).toBe( [ true, true ] );
				expect( _offer( "6.2.10.1-SNAPSHOT", "6.2.8.20" ) ).toBe( [ true, true ] );
				expect( _offer( "7.1.3.1-RC", "7.1.2.195" ) ).toBe( [ true, true ] );
			});

			it( title="a pre-release install is not restricted", body=function() {
				expect( _offer( "7.2.0.45-ALPHA", "7.1.3.183-SNAPSHOT" ) ).toBe( [ true, true ] );
				expect( _offer( "8.0.1.121-SNAPSHOT", "8.0.0.310-RC" ) ).toBe( [ true, true ] );
			});

			it( title="both update providers pick the latest version with it", body=function() {
				for ( var src in [ variables.mavenSrc, variables.legacySrc ] ) {
					expect( src ).toInclude( "services.VersionUtils::isOfferableUpdate( versions[ keys[ i ] ].version, version.display )" );
				}
			});

		});
	}

	// the answer of the legacy and of the Maven app, they have to be the same
	private array function _offer( required string candidate, required string installed ) {
		return [
			  offerlegacy.VersionUtils::isOfferableUpdate( arguments.candidate, arguments.installed )
			, offermaven.VersionUtils::isOfferableUpdate( arguments.candidate, arguments.installed )
		];
	}

}
