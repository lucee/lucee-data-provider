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

			it( title="the jars of extensions that were uploaded as org.lucee:<Bundle-SymbolicName> resolve on the Lucee repository", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				loop array=[ [ "redis.extension", "2.9.0.3-BETA" ], [ "memcached.extension", "3.0.2.29" ], [ "ehcache.extension", "2.10.0.30" ] ] item="local.b" {
					var u = matcher.findBundleUrl( bundleName=b[ 1 ], bundleVersion=b[ 2 ], rawSearch=true );
					expect( u ).toBe( "https://maven.lucee-services.com/org/lucee/#b[ 1 ]#/#b[ 2 ]#/#b[ 1 ]#-#b[ 2 ]#.jar" );
				}
			});

			it( title="org.lucee.oracle 23.26.0.0-ojdbc11 resolves to org.lucee:oracle on Maven Central", body=function() {
				var u = new services.legacy.MavenMatcher().findBundleUrl( bundleName="org.lucee.oracle", bundleVersion="23.26.0.0-ojdbc11", rawSearch=true );
				expect( u ).toBe( "https://repo1.maven.org/maven2/org/lucee/oracle/23.26.0.0-ojdbc11/oracle-23.26.0.0-ojdbc11.jar" );
			});

			it( title="latest of a bundle published as org.lucee:<Bundle-SymbolicName> is the version of its maven-metadata.xml", body=function() {
				var matcher = new services.legacy.MavenMatcher();
				var latest  = matcher.latestLuceeBundleVersion( "org.lucee.oracle" );
				expect( latest ).notToBe( "" );
				var u = matcher.findBundleUrl( bundleName="org.lucee.oracle", bundleVersion="latest", rawSearch=true );
				expect( u ).toInclude( "/" & latest & "/" );
				expect( u ).toInclude( ".jar" );
				// no metadata, no latest
				expect( matcher.findBundleUrl( bundleName="no.such.bundle.lucee", bundleVersion="latest", rawSearch=true ) ).toBe( "" );
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
