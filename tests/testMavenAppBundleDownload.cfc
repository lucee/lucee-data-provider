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

			it( title="rawSearchPaths for antlr 2.7.6 is the Central group/artifact layout first, then org.lucee:antlr", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths = matcher.rawSearchPaths( "antlr", "2.7.6" );

				expect( paths ).toBe( [ "/antlr/antlr/2.7.6/antlr-2.7.6.jar", "/org/lucee/antlr/2.7.6/antlr-2.7.6.jar" ] );
			});

			it( title="rawSearchPaths for an unmapped single-segment name also tries group=artifact", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths = matcher.rawSearchPaths( "unmapped-bundle", "1.2.3" );

				expect( paths ).toBe( [
					  "/unmapped-bundle/1.2.3/unmapped-bundle-1.2.3.jar"
					, "/unmapped-bundle/unmapped-bundle/1.2.3/unmapped-bundle-1.2.3.jar"
					, "/org/lucee/unmapped-bundle/1.2.3/unmapped-bundle-1.2.3.jar"
				] );
			});

			it( title="rawSearchPaths for org.lucee.chart.extension tries the dashed jar and the Bundle-SymbolicName, never a .lex", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths = matcher.rawSearchPaths( "org.lucee.chart.extension", "2.0.0.1" );

				expect( ArrayToList( paths ) ).notToInclude( ".lex" );
				expect( paths ).toInclude( "/org/lucee/chart-extension/2.0.0.1/chart-extension-2.0.0.1.jar" );
				expect( paths ).toInclude( "/org/lucee/org.lucee.chart.extension/2.0.0.1/org.lucee.chart.extension-2.0.0.1.jar" );
				// the naive dots-to-slashes guess is still first, but is not enough on its own
				expect( paths ).toInclude( "/org/lucee/chart/extension/2.0.0.1/extension-2.0.0.1.jar" );
			});

			it( title="extensionFileNamesForBundle maps org.lucee.chart.extension to chart-extension-2.0.0.1.lex", body=function() {
				var reader = new services.ExtensionMetadataReader();
				var names = reader.extensionFileNamesForBundle( "org.lucee.chart.extension", "2.0.0.1" );

				expect( names ).toInclude( "chart-extension-2.0.0.1.lex" );
				expect( names ).toInclude( "org.lucee.chart.extension-2.0.0.1.lex" );
			});

		});
	}

}
