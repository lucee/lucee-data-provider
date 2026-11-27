component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "bundles older Lucee versions ask the update provider for", function() {

			it( title="bcprov-lts8on 2.73.4 resolves to Maven Central", body=function() {
				var u = new services.legacy.MavenMatcher().findBundleUrl( "bcprov-lts8on", "2.73.4" );
				expect( u ).toBe( "https://repo1.maven.org/maven2/org/bouncycastle/bcprov-lts8on/2.73.4/bcprov-lts8on-2.73.4.jar" );
			});

			it( title="apache.lucene.analyzers 2.4.1 resolves to org.lucee on the Lucee repository", body=function() {
				var u = new services.legacy.MavenMatcher().findBundleUrl( bundleName="apache.lucene.analyzers", bundleVersion="2.4.1", rawSearch=true );
				expect( u ).toBe( "https://maven.lucee-services.com/org/lucee/apache.lucene.analyzers/2.4.1/apache.lucene.analyzers-2.4.1.jar" );
			});

		});
	}

}
