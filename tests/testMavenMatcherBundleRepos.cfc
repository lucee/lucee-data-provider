component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "bundle downloads that are not in the bundle bucket (Maven only)", function() {

			it( title="maps the Bouncy Castle LTS bundles to org.bouncycastle on Maven Central", body=function() {
				var matcher  = new services.legacy.MavenMatcher();
				var mappings = matcher.getMavenMappings();
				loop list="bcprov,bcpkix,bcutil,bcpg,bctls,bcmail,bcjmail" item="local.name" {
					var bundleName = name & "-lts8on";
					expect( mappings ).toHaveKey( bundleName );
					expect( mappings[ bundleName ].group ).toBe( "org.bouncycastle" );
					expect( mappings[ bundleName ].artifact ).toBe( bundleName );
				}
				var paths = matcher.rawSearchPaths( "bcprov-lts8on", "2.73.4" );
				expect( paths[ 1 ] ).toBe( "/org/bouncycastle/bcprov-lts8on/2.73.4/bcprov-lts8on-2.73.4.jar" );
			});

			it( title="looks for a bundle that is on no public repository as org.lucee:<Bundle-SymbolicName>", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var paths   = matcher.rawSearchPaths( "apache.lucene.analyzers", "2.4.1" );
				expect( paths ).toInclude( "/org/lucee/apache.lucene.analyzers/2.4.1/apache.lucene.analyzers-2.4.1.jar" );
				// org.lucee.* names keep their own guesses, no doubled org/lucee/org.lucee.* path
				var own = matcher.rawSearchPaths( "org.lucee.janinocc", "3.1.9" );
				expect( ArrayToList( own ) ).notToInclude( "/org/lucee/org.lucee.janinocc/" );
			});

			it( title="a mapped bundle in a Lucee build (e.g. xmpcore 5.1.2.0002L) is also looked up as org.lucee:<Bundle-SymbolicName>", body=function() {
				var paths = new services.legacy.MavenMatcher().rawSearchPaths( "xmpcore", "5.1.2.0002L" );
				expect( paths ).toBe( [
					  "/com/adobe/xmp/xmpcore/5.1.2.0002L/xmpcore-5.1.2.0002L.jar"
					, "/org/lucee/xmpcore/5.1.2.0002L/xmpcore-5.1.2.0002L.jar"
				] );
			});

			it( title="the raw search asks Maven Central first and the Lucee repository after it", body=function() {
				var repos = new services.legacy.MavenMatcher().rawSearchRepositories();
				expect( repos[ 1 ] ).toBe( "https://repo1.maven.org/maven2" );
				expect( repos ).toInclude( "https://maven.lucee-services.com" );
				expect( ArrayFind( repos, "https://maven.lucee-services.com" ) ).toBeGT( 1 );

				var custom = new services.legacy.MavenMatcher( mixedRepo="https://example.org/repo/" ).rawSearchRepositories();
				expect( custom ).toInclude( "https://example.org/repo" );

				var none = new services.legacy.MavenMatcher( mixedRepo="" ).rawSearchRepositories();
				expect( ArrayToList( none ) ).notToInclude( "lucee-services" );
			});

		});
	}

}
