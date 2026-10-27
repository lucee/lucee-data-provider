component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll(){
		variables.root = getDirectoryFromPath(getCurrentTemplatePath());  
		variables.root = listDeleteAt(root,listLen(root,"/\"), "/\") & "/";  // getDirectoryFromPath 
		variables.mavenMappingsFile = expandPath( "../../apps/updateserver/services/legacy/mavenMappings.json" );
	};

	function run( testResults , testBox ) {
		describe( "Syntax check", function() {
			it(title="validate maven matcher json", body=function(){
				var mavenMappings =  fileRead( mavenMappingsFile );
				expect ( isJson(mavenMappings) ).toBeTrue();
			});

			it(title="validate maven matcher mappings", body=function(){
				var mavenMappings =  fileRead( mavenMappingsFile );
				expect ( isJson(mavenMappings) ).toBeTrue();
				// validate they work!;
			});

			it(title="LDEV-6738 maps both MariaDB Connector/J bundle names to maven", body=function(){
				var mavenMappings = deserializeJSON( fileRead( mavenMappingsFile ) );
				// Connector/J 2.x uses the Bundle-SymbolicName org.mariadb.jdbc, 3.x uses mariadb-java-client
				loop list="org.mariadb.jdbc,mariadb-java-client" item="local.bundleName" {
					expect( mavenMappings ).toHaveKey( bundleName );
					expect( mavenMappings[ bundleName ].group ).toBe( "org.mariadb.jdbc" );
					expect( mavenMappings[ bundleName ].artifact ).toBe( "mariadb-java-client" );
				}
			});

		});
	}
}
