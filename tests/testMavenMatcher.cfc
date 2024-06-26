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

		});
	}
}
