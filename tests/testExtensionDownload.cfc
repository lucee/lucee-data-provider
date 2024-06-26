component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
		variables.artifacts = dir & "/artifacts";
		if ( !DirectoryExists( variables.artifacts ))
			directoryCreate( variables.artifacts );

		variables.buildDir = getTempDirectory() & "/build-test-#createUniqueId()#/";
		if ( DirectoryExists( variables.buildDir ) )
			directoryDelete( variables.buildDir, true );
		directoryCreate( variables.buildDir, true );

	}

	function run( testResults , testBox ) {
		describe( "extensions need to be served directly for older lucee versions", function() {
			it(title="check local extension cache works", body=function(){
				var extensionCache = new services.extensionCache();
				var path = extensionCache.getExtensionLex( "https://ext.lucee.org/compress-extension-1.0.0.15.lex" );
				systemOutput( path, true )
				expect( fileExists( path ) ).toBeTrue();
			});

			it(title="check local extension cache works (from cache)", body=function(){
				var extensionCache = new services.extensionCache();
				var path = extensionCache.getExtensionLex( "https://ext.lucee.org/compress-extension-1.0.0.15.lex" );
				// systemOutput( path, true )
				expect( fileExists( path ) ).toBeTrue();
			});

		});
	}

}
