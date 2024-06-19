component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function run( testResults , testBox ) {
		describe( "check all bundles in manifest are supported", function() {
			it(title="6.0.31", body=function(){
				fetchLuceeCore( "6.0.3.1" );
			});
		});
	}

	private function fetchLuceeCore ( version ){
		http url="https://cdn.lucee.org/#arguments.version#lco" method="get" result="local.core" path=getTempDirectory();
		systemOutput(core, json);
		return core;
	}

	private function extractManifest ( coreFile ){
	}
}
