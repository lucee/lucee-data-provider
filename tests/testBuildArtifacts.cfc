component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		var servicesDir = expandPath( dir & "../apps/updateserver/services" );
		application action="update" mappings={
			"/services" : servicesDir
		};
		variables.artifacts = servicesDir & "/legacy/build/servers/";
		if ( !DirectoryExists( variables.artifacts ))
			directoryCreate( variables.artifacts );
	}

	function run( testResults , testBox ) {
		describe( "test build artifacts", function() {
			// javax, tomcat 9
			it(title="check valid artifacts are produced, 6.0.3.1", body=function(){
				buildArtifacts( "lucee-6.0.3.1" );
			});
			// jakarta & javax, tomcat 10
			it(title="check valid artifacts are produced, 6.2.0.30-SNAPSHOT", body=function(){
				buildArtifacts( "lucee-6.2.0.30-SNAPSHOT" );
			});

			// jakarta, tomcat 11
			it(title="check valid artifacts are produced, 7.0.0.159-SNAPSHOT", body=function(){
				buildArtifacts( "lucee-7.0.0.159-SNAPSHOT" );
			});
		});
	}

	private function fetch( string filename, string extraDir="" ){
		if ( fileExists( variables.artifacts & "/#arguments.filename#" ))
			return variables.artifacts & "/#arguments.filename#";
		var artifact = "https://cdn.lucee.org/#arguments.extraDir##arguments.filename#";

		systemOutput( "Downloading #artifact# (cache miss)", true);
		http url=artifact method="get" result="local.core" file=arguments.filename path=variables.artifacts throwonerror="true";
		var file = directoryList(path=variables.artifacts, filter="#arguments.filename#");
		systemOutput(file, true);
		return file[ 1 ];
	}

	private function buildArtifacts( version ){

		systemOutput( "--- buildArtifacts [#arguments.version#] ", true);

		var buildDir = getTempDirectory() & "/build-artifacts-#createUUID()#/";
		if ( DirectoryExists( buildDir ) )
			directoryDelete( buildDir, true );
		directoryCreate( buildDir, true );
		directoryCreate( buildDir & "express-templates", true );

		var srcJar = fetch( arguments.version  & ".jar" );
		FileCopy( srcJar, buildDir & listLast( srcJar, "/\" ) );

		/* 
		could use https://update.lucee.org/rest/update/provider/expressTemplates for now rely on these existing on s3
		*/

		loop list="lucee-tomcat-9.0.100-template.zip,lucee-tomcat-10.1.36-template.zip,lucee-tomcat-11.0.5-template.zip" item="local.expressTemplate" {
			if ( !fileExists( buildDir & "express-templates/" & expressTemplate ) ){
				var template = fetch( expressTemplate, "express-templates/" );
				FileCopy( template, buildDir & "express-templates/" & expressTemplate );
			}
		}

		var s3 = new services.legacy.S3( buildDir );
		s3.addMissing( includingForgeBox=true, skipMaven=true );

		var produced = directoryList( path=buildDir, recurse=false, listinfo="query", type="file" );
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
