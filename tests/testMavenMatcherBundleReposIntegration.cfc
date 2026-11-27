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

			it( title="com.mysql.cj 8.0.19 resolves to mysql:mysql-connector-java on Maven Central", body=function() {
				var u = new services.legacy.MavenMatcher().findBundleUrl( bundleName="com.mysql.cj", bundleVersion="8.0.19", rawSearch=true );
				expect( u ).toBe( "https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.19/mysql-connector-java-8.0.19.jar" );
			});

			it( title="redis.extension 2.9.0.3-BETA resolves to the lex of org.lucee:redis-extension", body=function() {
				var u = new services.legacy.MavenMatcher().findBundleUrl( bundleName="redis.extension", bundleVersion="2.9.0.3-BETA", rawSearch=true );
				expect( u ).toBe( "https://maven.lucee-services.com/org/lucee/redis-extension/2.9.0.3-BETA/redis-extension-2.9.0.3-BETA.lex" );
			});

			it( title="Lucee builds of the bundles of older stable releases resolve on the Lucee repository", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				loop array=[ [ "fusiondebug.api.server", "1.0.20" ], [ "xmpcore", "5.1.2.0002L" ], [ "metadata.extractor", "2.8.1.0002L" ], [ "nu.xom", "1.2.5.osgi" ] ] item="local.b" {
					var u = matcher.findBundleUrl( bundleName=b[ 1 ], bundleVersion=b[ 2 ], rawSearch=true );
					expect( u ).toBe( "https://maven.lucee-services.com/org/lucee/#b[ 1 ]#/#b[ 2 ]#/#b[ 1 ]#-#b[ 2 ]#.jar" );
				}
			});

		});
	}

}
