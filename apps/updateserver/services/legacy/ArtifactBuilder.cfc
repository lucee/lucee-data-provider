component {
	static {
		static.DEBUG = (server.system.environment.DEBUG ?: false);
	}

	variables.providerLog = "application";
	variables.NL="
";
	public function init(s3Root) {
		variables.s3Root=arguments.s3Root;
	}

	/*
		MARK: Create Artifacts
	*/
	public function createArtifacts(mr, string version, specType="",includingForgeBox=true) {
		if(left(version,1)<5) return;
		var s3 = new services.legacy.S3(variables.s3Root);

		var jarRem = s3.getJarPath(version);
		var data = s3.getLuceeVersionsDetail(version);

		var list = "";
		if ( len( arguments.specType ) ) {
			list = arguments.specType;
			if ( !isNull( data[ arguments.specType ] ) ) return; // already built
		} else {
			// zero is built by the build process and not handled here
			list="lco,war,light,express";
			if (includingForgeBox)
				list&=",forgebox,forgebox-light";
		}

		try {
			lock name="build-lucee-artifacts-#version#" timeout="1" {
				try {

					logger("create Artifacts (#list#) starting ( #version# )");
					var c= 0;
					var batchStart = getTickCount();

					// first we need a local copy of the jar, used for all builds
					var localLuceeJar=getTempDirectory() & "/lucee-"&arguments.version&".jar";
					try {
						if ( !fileExists( localLuceeJar ) )
							fileCopy( jarRem, localLuceeJar );
					} catch( e ) {
						if ( fileExists( localLuceeJar ) )
							fileDelete( localLuceeJar );
						logger(exception=e, text="ERROR copying jar from S3 for version: " & arguments.version & " skipping artifact type: " & type );
						return;
					}

					loop list=list item="local.type" {
						if ( !isNull( data[type] ) ) continue; // already built
						logger("create: " & type);
						c++;
						var s = getTickCount();


						// build artifact and copy to S3
						if (type=="lco") {
							var result=createLCO( localLuceeJar, arguments.version );
							logger("lco: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else if(type=="forgebox" || type=="fb") {
							var result=createForgeBox( localLuceeJar, arguments.version, false );
							logger("forgebox: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
							//abort;
						}
						else if(type=="forgebox-light" || type=="fbl") {
							var result=createForgeBox( localLuceeJar, arguments.version, true );
							logger("forgebox-light: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else if(type=="war") {
							lock name="build-lucee-war" timeout="10" {
								var result=createWar( localLuceeJar, arguments.version );
							}
							logger("war: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else if(type=="light") {
							var result=createLight( localLuceeJar, arguments.version );
							logger("light: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else if (type=="zero") {
							var result=createLight( jar=localLuceeJar, version=arguments.version, noArchives=true );
							logger("zero: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else if(type=="express") {
							lock name="build-lucee-express" timeout="10" {
								var result=createExpress( localLuceeJar, arguments.version );
							}
							logger("express: " & result & " took " & numberFormat(getTickCount()-s) & "ms");
						}
						else {
							logger(text="ERROR unsupported artifact type: [" & type &"] " & arguments.version, type="ERROR" );
							c--;
						}
					}
					logger( "--- " & arguments.version & " done #c# artifacts built in " & numberFormat(getTickCount()-batchStart) & "ms");
					if ( c > 0 ) s3.reset(); // update version cache with new artifacts from s3
				}
				catch (e){
					logger("----------------------------------------------");
					logger(cfcatch.stacktrace);
					writeLog( text=e.message, exception=e, type="error" );
				}
				finally {
					if( !isNull( localLuceeJar ) && fileExists( localLuceeJar ) )
						fileDelete( localLuceeJar );
				}
			}
		} catch(e) {
			logger( "--- " & arguments.version & " already building, skipping, #e.message#");
		}
	}

	/*
		MARK: Create LCO
	*/
	private function createLCO( jar, version ) {
		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.lco";
		if ( fileExists( trg ) ) {
			logger("--- " & trg & " already built, skipping" );
			return trg;
		}
		try {
			var temp = getTempDirectory( arguments.version );
			var lco= temp & "lucee-" & version & ".lco";

			fileCopy( "zip://" & jar & "!core/core.lco", lco ); // now extract
			fileMove( lco, trg );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
			trg = e.message;
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return trg;
	}

	/*
		MARK: Create WAR
	*/
	private function createWar( jar, version ) {
		//logger("--- createWar ---" );
		var war=variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.war";
		if ( fileExists( war ) ) {
			logger("--- " & war & " already built, skipping" );
			return war;
		}
		else {
			logger("--- " & war & " not found, creating");
		}
		var temp = getTempDirectory( arguments.version );
		var warTmp=temp & "lucee-" & version & "-temp-" & createUniqueId() & ".war";
		var curr=getDirectoryFromPath( getCurrentTemplatePath() );
		var warTemplateFolder = getWarTemplate( arguments.version );

		try {
			// temp directory
			// create paths and dir if necessary
			var build={};
			loop list="extensions,common,website,war" item="local.name" {
				var tmp=curr & "build/" & name & "/";
				if ( !directoryExists( tmp ) ){
					if ( name == "extensions" ){ 
						directoryCreate( tmp, true );
					} else {
						throw( message="Required build directory missing: " & tmp );
					}
				}
				if ( name == "war" ){
					tmp = curr & "build/" & warTemplateFolder & "/";
				}
				build[ name ] = tmp;

			}
			//logger( "---- createWar", t);
			//logger( build, t);

			// let's zip it
			zip action="zip" file=warTmp overwrite=true {
				zipparam source=build["extensions"] filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=jar entrypath="WEB-INF/lib/lucee.jar";
				zipparam source=build["common"];
				zipparam source=build["website"];
				zipparam source=build["war"];
			}
			fileMove (warTmp, war );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
			trg = e.message;
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return war;
	}

	/*
		MARK: Create LIGHT
		@param boolean noArchives aka zero
	*/

	private function createLight(jar, version, boolean toS3=true, tempDir, boolean noArchives=false) {
		var sep=server.separator.file;
		var suffix = arguments.noArchives ? "zero" : "light";

		var trg=variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#-#suffix#.jar";
		if ( fileExists( trg ) ) {
			// avoid double handling for forgebox light builds
			logger("--- " & trg & " already built, skipping" );
			if ( len( arguments.tempDir ) ) {
				var tempLight = getTempFile( arguments.tempDir, "lucee-#suffix#-" & version, "jar");
				fileCopy( trg, tempLight); // create a local temp file from s3
				return tempLight;
			} else {
				return trg;
			}
		}
		var temp = getTempDirectory( arguments.version );
		var s = getTickCount();
		try {
			var tmpLoader=temp & "lucee-loader-" & createUniqueId(); // the jar
			directoryCreate( tmpLoader );

			// unzip
			try{
				zip action="unzip" file=jar destination=tmpLoader;
			}
			catch(e) {
				fileDelete(jar);
				return "";
			}
			// rewrite trg
			var extDir=tmpLoader & sep & "extensions";
			if ( directoryExists( extDir ) ) directoryDelete(extDir,true); // deletes directory with all files inside
			directoryCreate( extDir ); // create empty dir again (maybe Lucee expect this directory to exist)

			// unzip core
			var lcoFile=tmpLoader & sep & "core" & sep & "core.lco";
			var tmpCore=temp & "lucee-core-" & createUniqueId(); // the jar
			directoryCreate(tmpCore);
			zip action="unzip" file=lcoFile destination=tmpCore;

			if ( arguments.noArchives ) {
				// delete the lucee-admin.lar and lucee-docs.lar, i.e. lucee zero
				var lightContext = tmpCore & sep & "resource/context" & sep;
				loop list="lucee-admin.lar,lucee-doc.lar" item="local.larFile" {
					fileDelete( lightContext & larFile );
				}
			}

			// rewrite manifest
			var manifest=tmpCore & sep & "META-INF" & sep&"MANIFEST.MF";
			var content=fileRead(manifest);
			var index=find('Require-Extension',content);
			if(index>0) content=mid(content,1,index-1)&variables.NL;
			fileWrite(manifest,content);

			// zip core
			if ( fileExists( lcoFile ) ) fileDelete( lcoFile );
			zip action="zip" source=tmpCore file=lcoFile;
			// zip loader
			var tmpLoaderFile=temp&"lucee-loader-"&createUniqueId()&".jar";
			zip action="zip" source=tmpLoader file=tmpLoaderFile;

			//if(fileExists(light)) fileDelete(light);
			if ( arguments.toS3 ) {
				fileMove( tmpLoaderFile, trg );
			} else if ( len( arguments.tempDir ) ) {
				// forgebox light build needs a local copy, finally delete that working directory
				var tempLight = getTempFile( arguments.tempDir, "lucee-#suffix#-" & version, "jar");
				fileMove( tmpLoaderFile, tempLight);
				tmpLoaderFile = tempLight;
			}
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
			trg = e.message;
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return arguments.toS3 ? trg : tmpLoaderFile;
	}

	/*
		MARK: Create EXPRESS
	*/
	private string function createExpress(required jar,required string version) {
		var sep=server.separator.file;
		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#-express.zip";
		if ( fileExists( trg ) ) {
			logger("--- " & trg & " already built, skipping" );
			return trg;
		}
		var temp = getTempDirectory( arguments.version );
		//todo this can overlapp?
		var curr=getDirectoryFromPath(getCurrentTemplatePath());

		// website trg
		var zipTmp=temp & "lucee-express-" & version & "-temp-" &createUniqueId() & ".zip";
		var tmpTom="#temp#tomcat";
		// Create the express zip
		try {
			// extension directory
			var extDir = curr & ("build/extensions/");
			if (!directoryExists(extDir)) directoryCreate(extDir);

			// common directory
			var commonDir = curr & ("build/common/");
			//if (!directoryExists(commonDir)) directoryCreate(commonDir);

			// website directory
			var webDir = curr & ("build/website/");
			//if (!directoryExists(webDir)) directoryCreate(webDir);

			var expressTemplates = getExpressTemplates(); // at this point it should be already cached in the application scope
			// unpack the lucee tomcat template
			var local_tomcat_templates = curr & "build/servers"
			if ( checkVersionGTE( arguments.version, 6, 2, 1 ) ) {
				logger("Using Tomcat 11" );
				if ( !structKeyExists( expressTemplates, 'tomcat-11' ) )
					throw( message="No Tomcat 11 express template found for version #arguments.version#" );
				zip action="unzip" file="#local_tomcat_templates#/#expressTemplates['tomcat-11']#" destination=tmpTom;
			} else if ( checkVersionGTE( arguments.version, 6, 2 ) ) {
				logger("Using Tomcat 10" );
				if ( !structKeyExists( expressTemplates, 'tomcat-10' ) )
					throw( message="No Tomcat 10 express template found for version #arguments.version#" );
				zip action="unzip" file="#local_tomcat_templates#/#expressTemplates['tomcat-10']#" destination=tmpTom;
			} else {
				logger("Using Tomcat 9" );
				if ( !structKeyExists( expressTemplates, 'tomcat-9' ) )
					throw( message="No Tomcat 9 express template found for version #arguments.version#" );
				zip action="unzip" file="#local_tomcat_templates#/#expressTemplates['tomcat-9']#" destination=tmpTom;
			}

			// let's zip it
			zip action="zip" file=zipTmp overwrite=true {
				// tomcat server
				zipparam source=temp&"tomcat";
				// extensions to bundle
				zipparam source=extDir filter="*.lex" prefix="lucee-server/context/deploy";
				// jars
				zipparam source=jar entrypath="lib/ext/#listLast(jar, "/\")#";
				// common files
				zipparam source=commonDir;
				// website files
				zipparam source=webDir prefix="webapps/ROOT";
			}
			fileMove( zipTmp , trg );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
			trg = e.message;
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return trg;
	}

	/*
		MARK: Create FORGEBOX
	*/
	private string function createForgeBox(required jar,required string version, boolean light=false) {
		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#-forgebox#( light ? '-light' : '' )#.zip";
		if ( fileExists( trg ) ) {
			logger("--- " & trg & " already built, skipping" );
			return trg;
		}
		var sep = server.separator.file;
		var temp = getTempDirectory( arguments.version );
		var curr = getDirectoryFromPath(getCurrentTemplatePath());

		var zipTmp=temp & "forgebox#( light ? '-light' : '' )#-" & version & "-temp-" & createUniqueId() & ".zip";
		try {
			// extension directory
			var extDir=curr & "/build/extensions/";
			if(!directoryExists(extDir)) directoryCreate(extDir);

			// common directory
			var commonDir=curr & "/build/common/";
			//if(!directoryExists(commonDir)) directoryCreate(commonDir);

			// war directory
			var warDir = curr & "/build/" & getWarTemplate( arguments.version ) & "/";

			// create the war
			var war=temp & "/engine.war";
			if ( arguments.light ) {
				var lightJar = createLight(jar, version, false, temp);
				if ( !fileExists( lightJar ) )
					throw "ERROR: forgebox light, createLight didn't produce a jar [#lightJar#]";
			}

			zip action="zip" file=war overwrite=true {
				zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=( light ? lightJar: jar) entrypath="WEB-INF/lib/lucee#( arguments.light ? '-light' : '' )#.jar";
				zipparam source=commonDir;
				zipparam source=warDir;
			}

			// create the json
			// Turn 1.2.3.4 into 1.2.3+4 and 1.2.3.4-rc into 1.2.3-rc+4
			var v=reReplace( arguments.version, '([0-9]*\.[0-9]*\.[0-9]*)(\.)([0-9]*)(-.*)?', '\1\4+\3' );
			var json = temp & "/box.json";
			var boxJson = [
				"name":"Lucee #( light ? 'Light' : '' )# CF Engine",
				"version":"#v#",
				"createPackageDirectory":false,
				//"location":"https://cdn.lucee.org/rest/update/provider/forgebox/#arguments.version##( light ? '?light=true' : '' )#",
				"slug":"lucee#( light ? '-light' : '' )#",
				"shortDescription":"Lucee #( light ? 'Light' : '' )# WAR engine for CommandBox servers.",
				"type":"cf-engines"
			];
			if ( checkVersionGTE( arguments.version, 7 ) ){
				//logger( "Using JakartaEE" );
				boxJson[ "JakartaEE" ] = true;
			}
			fileWrite( json, boxJson.toJson() );
			//logger( boxJson.toJson(), t);

			// create the war
			zip action="zip" file=zipTmp overwrite=true {
				zipparam source=war;
				zipparam source=json;
			}
			fileMove( zipTmp, trg );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
			trg = e.message;
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return trg;
	}

	/*
		MARK: Helpers
	*/

	private function checkVersionGTE( version, major, minor, patch="" ){
		var v = listToArray( arguments.version, "." );
		if ( v[ 1 ] gt arguments.major ) {
			return true;
		} else if ( v[ 1 ] eq arguments.major && v[ 2 ] gte arguments.minor ) {
			if ( len( arguments.patch ) )
				return v[ 3 ] gte arguments.patch;
			else
				return true;
		}
		return false;
	}

	private function getWarTemplate( version ){
		if ( checkVersionGTE( arguments.version, 7 ) )
			return "war-7.0";  // jakarta, no lucee servlet
		else if ( checkVersionGTE( arguments.version, 6, 2 ) )
			return "war-6.2"; // javax & jakarta, no lucee servlet
		else
			return "war"; // javax
	}

	private function logger( string text, any exception, type="info", boolean forceSentry=false ){
		// var log = arguments.text & chr(13) & chr(10) & callstackGet('string');
		if ( !isNull(arguments.exception ) ){
			if (static.DEBUG) {
				if ( len(arguments.text ) ) systemOutput( arguments.text, true );
				systemOutput( arguments.exception, true );
			} else {
				writeLog( text=arguments.text, type=arguments.type, log="exception", exception=arguments.exception );
				// Send errors and warnings to Sentry (case insensitive check)
				var normalizedType = lCase( arguments.type );
				if ( normalizedType == "error" || normalizedType == "warning" || normalizedType == "warn" ) {
					try {
						var sentryExtra = {};
						// Include custom text as context if provided
						if ( len( arguments.text ) ) {
							sentryExtra[ "logText" ] = arguments.text;
						}
						application.sentryLogger.logException(
							exception = arguments.exception,
							level = arguments.type,
							extra = sentryExtra
						);
					} catch ( any e ) {
						// Don't let Sentry failures break anything
					}
				}
			}
		} else {
			if (static.DEBUG) {
				systemOutput( arguments.text, true);
			} else {
				writeLog( text=arguments.text, type=arguments.type, log=variables.providerLog );
				// Send to Sentry if forceSentry is true
				if ( arguments.forceSentry ) {
					try {
						application.sentryLogger.logMessage( message=arguments.text, level=arguments.type );
					} catch ( any e ) {
						// Don't let Sentry failures break anything
					}
				}
			}
		}
	}

	public function getExpressTemplates(){
		if ( !structKeyExists( application, "expressTemplates" ) ) {
			application.expressTemplates = new expressTemplates().getExpressTemplates( s3Root );
		}
		return application.expressTemplates;
	}

}