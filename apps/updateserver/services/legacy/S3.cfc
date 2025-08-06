component {
	static {
		static.DEBUG=false; // TODO read from env var
	}

	variables.providerLog = "update-provider";
	variables.NL="
";
	public function init(s3Root) {
		variables.s3Root=arguments.s3Root;
	}

	public void function reset() {
		if(static.DEBUG) systemOutput( "s3.reset()", true );
		structDelete( application, "s3VersionData", false );
		structDelete( application, "expressTemplates", false );
	}

	private function logger( string text, any exception, type="info" ){
		var log = arguments.text & chr(13) & chr(10) & callstackGet('string');
		if ( !isNull(arguments.exception ) ){
			WriteLog( text=arguments.text, type=arguments.type, log=variables.providerLog, exception=arguments.exception );
			if(static.DEBUG) systemOutput( arguments.exception, true, true );
		} else {
			WriteLog( text=arguments.text, type=arguments.type, log=variables.providerLog );
			if(static.DEBUG) systemOutput( arguments.text, true, true );
		}
	}

	/*
		MARK: Get Versions
	*/

	

	private function sortVersions(data){
		var keys=structKeyArray(data);
		arraySort(keys,"textnocase");
		var _data=structNew("linked");
		loop array=keys item="local.k" {
			if ( structKeyExists( data[ k ], "version" ) && !isEmpty( data[k][ 'version' ] ) )
				_data[k] = data[k];
		}
		return _data;
	}

	public function getLatestVersion(boolean flush=false) {
		var versions=getVersions(flush);
		var keys=structKeyArray(versions);
		arraySort(keys,"textnocase");
		return versions[keys[arrayLen(keys)]].version;
	}

	public function getExpressTemplates(){
		if ( !structKeyExists( application, "expressTemplates" ) ) {
			application.expressTemplates = new expressTemplates().getExpressTemplates( s3Root );
		}
		return application.expressTemplates;
	}

	public function add(required string type, required string version) {
		setting requesttimeout="10000000";

		if(static.DEBUG) systemOutput("-------- add:#type# --------", true);
		try {
			var data=LuceeVersionsDetailS3(version);
		} 
		catch (ex) {}	
		if(static.DEBUG) systemOutput(data, true);
		var mr=new MavenRepo();

		// move the jar from maven if necessary
		if(isNull(data.jar)) {
			maven2S3(mr,version);
			if(static.DEBUG) SystemOutput("add: downloaded jar from maven:"&now(),1,1);
		}
		var vs=services.VersionUtils::toVersionSortable(version);
		// create the artifact

		try {
			if( type != "jar" ){
				if(static.DEBUG) SystemOutput("add: createArtifacts (#type#):"&now(),1,1);
				createArtifacts(mr,version,type,true);
				if(static.DEBUG) SystemOutput("add: after creating artifact (#type#):"&now(),1,1);
			}
		} catch(e){
			if(static.DEBUG) SystemOutput(e.stacktrace,1,1);
		}
	}

	/*


		MARK: Add Missing
	*/
	
	private function maven2S3(mr,version) {
		if(left(version,1)<5) return;
		// ignore this versions
		if(listFind("5.0.0.20-SNAPSHOT,5.0.0.255-SNAPSHOT,5.0.0.256-SNAPSHOT,5.0.0.258-SNAPSHOT,5.0.0.259-SNAPSHOT",version)) {
			structDelete(all,version,false);
			return;
		}

		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.jar";
		lock name="download from maven-#version#" timeout="1" {
			if(static.DEBUG) systemOutput("downloading from maven-#version#",1,1);
			// add the jar
			var info=mr.get(version, true);
			if(isNull(info.sources.jar.src)) {
				if(static.DEBUG) systemOutput("404:"&version,1,1);
				return;
			}
			var src=info.sources.jar.src;
			var date=parseDateTime(info.sources.jar.date);

			if (!fileExists(src)) {
				if(static.DEBUG) systemOutput("404:"&src,1,1);
				return;
			}
			// copy jar from maven to S3
			fileCopy(src,trg);

			if(static.DEBUG) systemOutput("200:"&trg,1,1);
		}
	}


	public function buildLatest(includingForgeBox=false) {
		var list=luceeVersionsList();
		var latest=list[len(list)];
		if(static.DEBUG) systemOutput("buildLatest: " & latest, 1, 1);
		var mr=new MavenRepo();
		createArtifacts(mr,latest,"",includingForgeBox);
	}

	/*
		MARK: Create Artifacts
	*/
	private function createArtifacts(mr,version,specType="",includingForgeBox=true) {
		if(left(version,1)<5) return;

		var jarRem = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.jar";
		try {
			var data=LuceeVersionsDetailS3(version);
		} 
		catch (ex) {}	


		try {
			lock name="build-lucee-artifacts-#version#" timeout="1" {
				try {
					// check and if necessary create other artifacts
					var list="lco,war,light,express";
					if(includingForgeBox)list&=",forgebox,forgebox-light";

					if(static.DEBUG) systemOutput("create #specType# Artifacts(#list#) Starting ( #version# )",1,1);
					var c= 0;

					loop list=list item="local.type" {
						if ( len( specType ) && specType!=type ) continue;
						if (!isNull(data[type])) continue;
						if(static.DEBUG) systemOutput("create: " & type,1,1);
						c++;
						var s = getTickCount();
						// first we need a local copy of the jar
						var lcl=getTempDirectory() & "/lucee-"&arguments.version&".jar";
						try {
							
							if(!fileExists(lcl)) fileCopy(jarRem,lcl);
						}
						catch(e) {
							if(static.DEBUG) systemOutput(e,1,1);
							continue;
						}

						// extract lco and copy to S3
						if(type=="lco") {
							var result=createLCO(lcl,arguments.version);
							if(static.DEBUG) systemOutput("lco: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
						}
						else if(type=="forgebox" || type=="fb") {
							var result=createForgeBox(lcl,arguments.version,false);
							if(static.DEBUG) systemOutput("forgebox: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
							//abort;
						}
						else if(type=="forgebox-light" || type=="fbl") {
							var result=createForgeBox(lcl,arguments.version,true);
							if(static.DEBUG) systemOutput("forgebox-light: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
						}
						// create war and copy to S3
						else if(type=="war") {
							lock name="build-lucee-war" timeout="10" {
								var result=createWar(lcl,arguments.version);
							}
							if(static.DEBUG) systemOutput("war: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
						}
						// create war and copy to S3
						else if(type=="light") {
							var result=createLight(lcl,arguments.version);
							if(static.DEBUG) systemOutput("light: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
						}
						else if(type=="express") {
							lock name="build-lucee-express" timeout="10" {
								var result=createExpress(lcl,arguments.version);
							}
							if(static.DEBUG) systemOutput("express: " & result & " took " & numberFormat(getTickCount()-s) & "ms",1,1);
						}
						else {
							if(static.DEBUG) systemOutput("unsupported: " & type &":"&arguments.version,1,1);
							c--;
						}
					}
					if(static.DEBUG) systemOutput( "--- " & arguments.version & " done #c# artifacts built",1,1);
				}
				catch (e){
					if(static.DEBUG) systemOutput("----------------------------------------------",1,1);
					if(static.DEBUG) systemOutput(cfcatch.stacktrace,1,1);
					writeLog( text=e.message, exception=e, type="error" );
				}
				finally {
					if(!isNull(lcl) && fileExists(lcl)) fileDelete(lcl);
				}
			}
		} catch(e) {
			if(static.DEBUG) systemOutput( "--- " & arguments.version & " already building, skipping, #e.message#",1,1);
		}
	}

	/*
		MARK: Create LCO
	*/
	private function createLCO( jar, version ) {
		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.lco";
		if ( fileExists( trg ) ) {
			if(static.DEBUG) systemOutput("--- " & trg & " already built, skipping", true);
		}
		try {
			var temp = getTemp( arguments.version );
			var lco= temp & "lucee-" & version & ".lco";

			fileCopy( "zip://" & jar & "!core/core.lco", lco ); // now extract
			fileMove( lco, trg );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
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
		if(static.DEBUG) systemOutput("--- createWar ---" , true);
		var war=variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.war";
		if ( fileExists( war ) ) {
			if(static.DEBUG) systemOutput("--- " & war & " already built, skipping", true);
		}
		else {
			systemOutput("--- " & war & " not found, creating", true);
		}
		var temp = getTemp( arguments.version );
		var warTmp=temp & "lucee-" & version & "-temp-" & createUniqueId() & ".war";
		var curr=getDirectoryFromPath( getCurrentTemplatePath() );
		var warTemplateFolder = getWarTemplate( arguments.version );

		try {
			// temp directory
			// create paths and dir if necessary
			var build={};
			loop list="extensions,common,website,war" item="local.name" {
				var tmp=curr & "build/" & name & "/";
				if ( name == "extensions" && !directoryExists( tmp ) )
					directoryCreate( tmp, true );
				if ( name == "war" ){
					tmp = curr & "build/" & warTemplateFolder & "/";
				}
				build[ name ] = tmp;

			}
			//if(static.DEBUG) systemOutput( "---- createWar", true );
			//if(static.DEBUG) systemOutput( build, true );

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
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return war;
	}

	/*
		MARK: Create LIGHT
	*/

	private function createLight(jar, version, boolean toS3=true, tempDir) {
		var sep=server.separator.file;
		var trg=variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#-light.jar";
		if ( fileExists( trg ) ) {
			// avoid double handling for forgebox light builds
			if(static.DEBUG) systemOutput("--- " & trg & " already built, skipping", true);
			var tempLight = getTempFile( arguments.tempDir, "lucee-light-" & version, "jar");
			fileCopy( trg, tempLight); // create a local temp file from s3
			return tempLight;
		}
		var temp = getTemp( arguments.version );
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
			local.tmpCore=temp & "lucee-core-" & createUniqueId(); // the jar
			directoryCreate(tmpCore);
			zip action="unzip" file=lcoFile destination=tmpCore;
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
			local.tmpLoaderFile=temp&"lucee-loader-"&createUniqueId()&".jar";
			zip action="zip" source=tmpLoader file=tmpLoaderFile;

			//if(fileExists(light)) fileDelete(light);
			if (toS3) fileMove(tmpLoaderFile,trg);
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return toS3?trg:tmpLoaderFile;
	}

	/*
		MARK: Create EXPRESS
	*/
	private string function createExpress(required jar,required string version) {
		var sep=server.separator.file;
		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#-express.zip";
		if ( fileExists( trg ) ) {
			if(static.DEBUG) systemOutput("--- " & trg & " already built, skipping", true);
			return trg;
		}
		var temp = getTemp( arguments.version );
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
				if(static.DEBUG) systemOutput("Using Tomcat 11", true);
				zip action="unzip" file="#local_tomcat_templates#/#expressTemplates['tomcat-11']#" destination=tmpTom;
			} else if ( checkVersionGTE( arguments.version, 6, 2 ) ) {
				if(static.DEBUG) systemOutput("Using Tomcat 10", true);
				zip action="unzip" file="#local_tomcat_templates#/#expressTemplates['tomcat-10']#" destination=tmpTom;
			} else {
				if(static.DEBUG) systemOutput("Using Tomcat 9", true);
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
			if(static.DEBUG) systemOutput("--- " & trg & " already built, skipping", true);
			return trg;
		}
		var sep = server.separator.file;
		var temp = getTemp( arguments.version );
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
			if ( light ) local.lightJar=createLight(jar, version, false, temp);

			zip action="zip" file=war overwrite=true {
				zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=( light ? lightJar: jar) entrypath="WEB-INF/lib/lucee#( light ? '-light' : '' )#.jar";
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
				if(static.DEBUG) systemOutput( "Using JakartaEE", true );
				boxJson[ "JakartaEE" ] = true;
			}
			fileWrite( json, boxJson.toJson() );
			//if(static.DEBUG) systemOutput( boxJson.toJson(), true );

			// create the war
			zip action="zip" file=zipTmp overwrite=true {
				zipparam source=war;
				zipparam source=json;
			}
			fileMove( zipTmp, trg );
		}
		catch( e ){
			logger(text=e.message, type="error", exception=e);
		}
		finally {
			if (!isNull(temp) && directoryExists(temp)) directoryDelete(temp,true);
		}
		return trg;
	}

	private function getTemp( string version ){
		var temp = getTempDirectory() & "#arguments.version#-" & createUniqueId() & "/";
		if ( directoryExists( temp ) )
			directoryDelete( temp, true );
		directoryCreate( temp );
		return temp;
	}

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

}