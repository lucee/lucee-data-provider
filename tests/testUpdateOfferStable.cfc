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
				for ( var utils in [ _legacy(), _maven() ] ) {
					expect( utils.isOfferableUpdate( "7.2.0.45-ALPHA", "7.0.5.41" ) ).toBeFalse();
					expect( utils.isOfferableUpdate( "7.2.0.45-ALPHA", "7.1.2.195" ) ).toBeFalse();
					expect( utils.isOfferableUpdate( "7.1.3.1-ALPHA", "7.1.2.195" ) ).toBeFalse();
				}
			});

			it( title="a stable version is not offered a pre-release of another major.minor", body=function() {
				for ( var utils in [ _legacy(), _maven() ] ) {
					expect( utils.isOfferableUpdate( "7.1.3.183-SNAPSHOT", "7.0.5.41" ) ).toBeFalse();
					expect( utils.isOfferableUpdate( "7.1.2.194-RC", "7.0.5.41" ) ).toBeFalse();
					expect( utils.isOfferableUpdate( "7.1.0.1-BETA", "7.0.5.41" ) ).toBeFalse();
					expect( utils.isOfferableUpdate( "8.0.1.121-SNAPSHOT", "7.1.2.195" ) ).toBeFalse();
				}
			});

			it( title="a stable version is offered releases and pre-releases (not alphas) of its own major.minor", body=function() {
				for ( var utils in [ _legacy(), _maven() ] ) {
					expect( utils.isOfferableUpdate( "7.1.2.195", "7.0.5.41" ) ).toBeTrue();
					expect( utils.isOfferableUpdate( "6.2.10.1-SNAPSHOT", "6.2.8.20" ) ).toBeTrue();
					expect( utils.isOfferableUpdate( "7.1.3.1-RC", "7.1.2.195" ) ).toBeTrue();
				}
			});

			it( title="a pre-release install is not restricted", body=function() {
				for ( var utils in [ _legacy(), _maven() ] ) {
					expect( utils.isOfferableUpdate( "7.2.0.45-ALPHA", "7.1.3.183-SNAPSHOT" ) ).toBeTrue();
					expect( utils.isOfferableUpdate( "8.0.1.121-SNAPSHOT", "8.0.0.310-RC" ) ).toBeTrue();
				}
			});

			it( title="both update providers pick the latest version with it", body=function() {
				for ( var src in [ variables.mavenSrc, variables.legacySrc ] ) {
					expect( src ).toInclude( "services.VersionUtils::isOfferableUpdate( versions[ keys[ i ] ].version, version.display )" );
				}
			});

		});
	}

	private any function _legacy() {
		return new offerlegacy.VersionUtils();
	}

	private any function _maven() {
		return new offermaven.VersionUtils();
	}

}
