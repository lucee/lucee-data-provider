component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
		variables.artifacts = dir & "/artifacts";
		if ( !DirectoryExists( variables.artifacts ))
			directoryCreate( variables.artifacts );
	}

	function run( testResults , testBox ) {
		describe( "test build artifacts", function() {
			it(title="check valid artifacts are produced, 6.0.3.1", body=function(){
				buildArtifacts( "lucee-6.0.3.1" );
			});

			it(title="check valid artifacts are produced, 6.2.0.30-SNAPSHOT", body=function(){
				buildArtifacts( "lucee-6.2.0.30-SNAPSHOT" );
			});
		});
	}

	private function fetchLuceeJar( string version ){
		if ( fileExists( variables.artifacts & "/#arguments.version#.jar" ))
			return variables.artifacts & "/#arguments.version#.jar";
		var artifact = "https://cdn.lucee.org/#arguments.version#.jar";

		systemOutput( "Downloading #artifact# (cache miss)", true);
		http url=artifact method="get" result="local.core" path=variables.artifacts throwonerror="true";
		var file = directoryList(path=variables.artifacts, filter="#arguments.version#.jar");
		systemOutput(file, true);
		return file[ 1 ];
	}

	private function buildArtifacts( version ){

		var buildDir = getTempDirectory() & "/build-artifacts-#createUUID()#/";
		if ( DirectoryExists( buildDir ) )
			directoryDelete( buildDir, true );
		directoryCreate( buildDir, true );

		systemOutput( "--- buildArtifacts [#arguments.version#] ", true);
		var srcJar = fetchLuceeJar( arguments.version );
		FileCopy( srcJar, buildDir & listLast( srcJar, "/\" ) );

		var s3 = new services.legacy.S3();
		s3.init( buildDir );
		s3.addMissing( includingForgeBox=true, skipMaven=true );

		var produced = directoryList( path=buildDir, recurse=true, listinfo="query" );
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
					if ( listLast( z.name, "." ) eq "war" ){
						dumpWarContents( "#f.directory#/#f.name#", true );
					}
				}
			}
		}
	}

	private function dumpWarContents( zip, recurse=true ){
		var warDir = getTempDirectory() & "/build-war-#createUUID()#/";
		if ( DirectoryExists( warDir ) )
			directoryDelete( warDir, true );
		directoryCreate( warDir, true );
		zip action="unzip" file=arguments.zip destination=wardir;

		if ( arguments.recurse ) {
			var wars = directoryList( path=warDir, recurse=true, listinfo="query", filter="*.war" );
			for (var war in wars ){
				if ( listLast( war.name, ".") eq "war" ){
					dumpWarContents( zip=(war.directory & "/" & war.name), recurse=false );
				}
			}
		} else {
			var warContents = directoryList( path=warDir, recurse=true, listinfo="query" );
			for ( var f in warContents ){
				systemOutput( "#chr(9)##chr(9)##mid(f.directory,len(warDir))#/#f.name#, #numberFormat( f.size )#", true );
			}
		}
	}

}
