component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "Resolve the org.h2 OSGi bundle to Maven Central com.h2database:h2", function() {

			it( title="findBundleUrl for org.h2 1.3.172 is the Central jar", body=function(){
				var mavenMatcher = new services.legacy.MavenMatcher();
				var bundleUrl = mavenMatcher.findBundleUrl( "org.h2", "1.3.172" );
				expect( bundleUrl ).toBe( "https://repo1.maven.org/maven2/com/h2database/h2/1.3.172/h2-1.3.172.jar" );
			});

			it( title="findBundleUrl returns empty when that exact H2 version is not on Central", body=function(){
				var mavenMatcher = new services.legacy.MavenMatcher();
				var bundleUrl = mavenMatcher.findBundleUrl( "org.h2", "0.0.0" );
				expect( bundleUrl ).toBe( "" );
			});

		});
	}

}
