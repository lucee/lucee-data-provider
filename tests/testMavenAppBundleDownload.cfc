component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
		variables.mappingsFile = ExpandPath( dir & "../apps/updateserver-maven/services/legacy/mavenMappings.json" );
	}

	function run( testResults, testBox ) {

		describe( "Maven-app bundle resolution", function() {

			it( title="maps the antlr OSGi bundle to Maven Central antlr:antlr", body=function() {
				var mappings = DeserializeJSON( FileRead( variables.mappingsFile ) );

				expect( mappings ).toHaveKey( "antlr" );
				expect( mappings.antlr.group ).toBe( "antlr" );
				expect( mappings.antlr.artifact ).toBe( "antlr" );
			});

			it( title="rawSearchPaths for antlr 2.7.6 is the Central group/artifact layout", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths = matcher.rawSearchPaths( "antlr", "2.7.6" );

				expect( paths ).toBe( [ "/antlr/antlr/2.7.6/antlr-2.7.6.jar" ] );
			});

			it( title="rawSearchPaths for an unmapped single-segment name also tries group=artifact", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths = matcher.rawSearchPaths( "unmapped-bundle", "1.2.3" );

				expect( paths ).toBe( [
					  "/unmapped-bundle/1.2.3/unmapped-bundle-1.2.3.jar"
					, "/unmapped-bundle/unmapped-bundle/1.2.3/unmapped-bundle-1.2.3.jar"
				] );
			});

		});
	}

}
