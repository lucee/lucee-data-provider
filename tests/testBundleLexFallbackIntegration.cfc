/**
 * The .lex fallback against the real repositories: the axis extension .lex is found on maven.lucee-services.com
 * and its jars (org.lucee.axis.extension 1.4.0.27-SNAPSHOT among them) go into the bundle cache.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/ldev6953" : dir
		};
	}

	function run( testResults, testBox ) {
		describe( "bundles that only ship inside an extension .lex", function() {

			it( title="findLexUrls finds the axis extension 1.4.0.27-SNAPSHOT on the Lucee repository", body=function() {
				var urls = new services.legacy.MavenMatcher().findLexUrls( "org.lucee.axis.extension", "1.4.0.27-SNAPSHOT" );
				expect( urls ).toInclude( "https://maven.lucee-services.com/org/lucee/axis-extension/1.4.0.27-SNAPSHOT/axis-extension-1.4.0.27-SNAPSHOT.lex" );
			});

			it( title="findLexUrls finds mssqljdbc4 4.0.2206.100 in the mssql-jdbc-extension 4.0.2206.100 lex", body=function() {
				var urls = new services.legacy.MavenMatcher().findLexUrls( "mssqljdbc4", "4.0.2206.100" );
				expect( urls[ 1 ] ).toBe( "https://maven.lucee-services.com/org/lucee/mssql-jdbc-extension/4.0.2206.100/mssql-jdbc-extension-4.0.2206.100.lex" );
			});

			it( title="org.lucee.axis.extension 1.4.0.27-SNAPSHOT is extracted from the axis lex into the bundle cache", body=function() {
				var cache   = new ldev6953.BundleCacheMemoryStub();
				var matcher = new ldev6953.BundleLexMatcherStub(
					  "https://maven.lucee-services.com/org/lucee/axis-extension/1.4.0.27-SNAPSHOT/axis-extension-1.4.0.27-SNAPSHOT.lex"
					, [ "org.lucee.axis.extension" ]
				);
				var svc = new services.BundleDownloadService(
					  extensionsCdnUrl    = ""
					, bundleS3Root        = ""
					, bundleCdnUrl        = ""
					, extensionMetaReader = new ldev6953.LDEV6953MetaStub()
					, mavenMatcher        = matcher
					, bundleCache         = cache
				);
				var b = svc.findBundle( "org.lucee.axis.extension", "1.4.0.27-SNAPSHOT" );
				expect( b.cacheObject ).toBe( "provider/bundles/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar" );
				expect( StructCount( cache.objects ) ).toBeGTE( 2 );
			});

		});
	}

}
