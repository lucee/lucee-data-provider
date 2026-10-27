component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );
		application action="update" mappings={
			"/update" : expandPath( dir & "../apps/updateserver/" )
		};
	}

	function run( testResults, testBox ) {
		describe( "LDEV-6738 resolve MariaDB Connector/J bundles to maven", function() {

			it( title="resolves the 3.x bundle name mariadb-java-client", body=function(){
				var mavenMatcher = new update.services.legacy.MavenMatcher();
				var bundleUrl = mavenMatcher.findBundleUrl( "mariadb-java-client", "3.5.11" );
				expect( bundleUrl ).toInclude( "/org/mariadb/jdbc/mariadb-java-client/3.5.11/mariadb-java-client-3.5.11.jar" );
			});

			it( title="still resolves the 2.x bundle name org.mariadb.jdbc", body=function(){
				var mavenMatcher = new update.services.legacy.MavenMatcher();
				var bundleUrl = mavenMatcher.findBundleUrl( "org.mariadb.jdbc", "2.7.12" );
				expect( bundleUrl ).toInclude( "/org/mariadb/jdbc/mariadb-java-client/2.7.12/mariadb-java-client-2.7.12.jar" );
			});

		});
	}

}
