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
		describe( "test build artifacts", function() {
			it(title="check valid files are produced", body=function(){

				var srcJar = fetchLuceeJar( "lucee-6.0.3.1" );
				FileCopy( srcJar, variables.buildDir & listLast( srcJar, "/\" ) );

				var s3 = new services.legacy.S3();
				s3.init( variables.buildDir );
				s3.addMissing( includingForgeBox=true, skipMaven=true );

				var produced = directoryList( path=variables.buildDir, recurse=true, listinfo="query" );
				for (var f in produced ) {
					systemOutput( "", true );
					var fileCount = -1;
					var zip = queryNew("");
					try {
						zip action="list" file="#f.directory#/#f.name#" name="local.zip";
						fileCount = zip.recordcount;
					} catch ( e ) {
						systemOutput( f, true );
						systemOutput( e.stacktrace, true );
					}
					systemOutput( "#f.name#, #numberFormat( f.size )#, #fileCount# files", true );
					var type = listLast( f.name, "." );
					if ( zip.recordCount && type != "jar" && type != "lco" ){
						for (var z in zip ){
							systemOutput( "#chr(9)# #z.name#, #numberFormat( z.size )#", true );
						}
					}
				}

			});
		});
	}

	private function fetchLuceeJar( string version ){
		if ( fileExists( variables.artifacts & "/#arguments.version#.jar" ))
			return variables.artifacts & "/#arguments.version#.jar";
		var artifact = "https://cdn.lucee.org/#arguments.version#.jar";

		systemOutput( "Downloading #artifact# (cache miss)", true);
		http url=artifact method="get" result="local.core" path=variables.artifacts;
		var file = directoryList(path=variables.artifacts, filter="#arguments.version#.jar");
		//systemOutput(file, true);
		return file[ 1 ];
	}


}
