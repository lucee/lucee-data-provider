component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "Test VersionUtils.checkVersionGTE()", function() {

			it( title="exact match returns true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.1.25", 6, 2, 1, 25 ) ).toBeTrue();
			});

			it( title="higher major returns true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "7.0.0.1", 6, 2, 1, 25 ) ).toBeTrue();
			});

			it( title="lower major returns false", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.4.7.3", 6, 2, 1, 25 ) ).toBeFalse();
			});

			it( title="higher minor returns true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.3.0.0", 6, 2, 1, 25 ) ).toBeTrue();
			});

			it( title="lower minor returns false", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.1.0.0", 6, 2, 1, 25 ) ).toBeFalse();
			});

			it( title="higher patch returns true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.2.0", 6, 2, 1, 25 ) ).toBeTrue();
			});

			it( title="lower patch returns false", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.0.99", 6, 2, 1, 25 ) ).toBeFalse();
			});

			it( title="higher build returns true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.1.26", 6, 2, 1, 25 ) ).toBeTrue();
			});

			it( title="lower build returns false", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.1.24", 6, 2, 1, 25 ) ).toBeFalse();
			});

			it( title="major only - version higher", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "7.0.4.17", 6 ) ).toBeTrue();
			});

			it( title="major only - version equal", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.0.0.0", 6 ) ).toBeTrue();
			});

			it( title="major only - version lower", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.4.7.3", 6 ) ).toBeFalse();
			});

			it( title="bug repro: 7.0.4.17 >= 7.0.0.115 should be true", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "7.0.4.17", 7, 0, 0, 115 ) ).toBeTrue();
			});

			it( title="bug repro: version with higher patch than minimum", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.4.24", 5, 3, 2, 63 ) ).toBeTrue();
			});

			// partial args - major+minor only
			it( title="major+minor only - higher minor", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.3.0.0", 6, 2 ) ).toBeTrue();
			});

			it( title="major+minor only - equal", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.0.0", 6, 2 ) ).toBeTrue();
			});

			it( title="major+minor only - lower minor", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.1.9.99", 6, 2 ) ).toBeFalse();
			});

			// partial args - major+minor+patch
			it( title="major+minor+patch only - higher patch", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.2.0", 6, 2, 1 ) ).toBeTrue();
			});

			it( title="major+minor+patch only - equal", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.1.0", 6, 2, 1 ) ).toBeTrue();
			});

			it( title="major+minor+patch only - lower patch", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "6.2.0.99", 6, 2, 1 ) ).toBeFalse();
			});

			// suffix handling - update provider always uses exact versions,
			// but suffixes appear in minCoreVersion data
			it( title="version with SNAPSHOT suffix in parts", body=function(){
				// 6.0.0.1 >= 5.3.0.35-SNAPSHOT - resolves at major+minor, never hits suffix
				expect( services.VersionUtils::checkVersionGTE( "6.0.0.1", 5, 3, 0, "35-SNAPSHOT" ) ).toBeTrue();
			});

			it( title="version with ALPHA suffix in parts", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.4.6.9", 5, 3, 0, "35-ALPHA" ) ).toBeTrue();
			});

			it( title="version with ALPHA suffix - lower major", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "4.0.0.0", 5, 3, 0, "35-ALPHA" ) ).toBeFalse();
			});

			// suffix at build level - callers use val() to strip suffixes before calling,
			// so test with val() applied to match real usage
			it( title="suffix stripped via val() - version build higher", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.3.0.40", 5, 3, 0, val( "35-SNAPSHOT" ) ) ).toBeTrue();
			});

			it( title="suffix stripped via val() - version build equal", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.3.0.35", 5, 3, 0, val( "35-ALPHA" ) ) ).toBeTrue();
			});

			it( title="suffix stripped via val() - version build lower", body=function(){
				expect( services.VersionUtils::checkVersionGTE( "5.3.0.10", 5, 3, 0, val( "35-SNAPSHOT" ) ) ).toBeFalse();
			});

		});
	}
}
