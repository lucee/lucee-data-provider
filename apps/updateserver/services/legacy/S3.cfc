component {
	variables.NL="
";
	public function init(s3Root) {
		variables.s3Root=arguments.s3Root;
	}
	public void function reset() {
		structDelete(application,"s3VersionData",false);
	}
	public function getVersions(boolean flush=false) {
		var rootDir = getDirectoryFromPath(getCurrentTemplatePath());
		var cacheDir=rootDir & "cache/";
		var cacheFile = "versions.json";

		lock name="check-version-cache" timeout="2" throwOnTimeout="false" {
			if (!directoryExists(cacheDir))
				directoryCreate(cacheDir);
			if ( isNull(application.s3VersionData) && fileExists( cacheDir & cacheFile ) ){
				systemOutput("s3List.versions load from cache", true);
				application.s3VersionData =
				sortVersions(deserializeJSON( fileRead(cacheDir & cacheFile), false ));
			}
		}

		if(!flush && !isNull(application.s3VersionData))
			return application.s3VersionData;

		lock name="read-version-metadata" timeout="2" throwOnTimeout="false" {
			setting requesttimeout="1000";

			var runid = createUniqueID();
			var start = getTickCount();

			systemOutput("s3Versions.list [#runId#] START #numberFormat(getTickCount()-start)#ms",1,1);

			// systemOutput(variables.s3Root,1,1);
			try {
				var qry=directoryList(path:variables.s3Root,listInfo:"query",filter:function (path){
					var ext=listLast(path,'.');
					var name=listLast(path,'\/');

					if(ext=='lco') return true;
					if(ext=='war' && left(name,6)=='lucee-') return true;
					if(ext=='exe' && left(name,6)=='lucee-') return true; // lucee-4.5.3.020-pl0-windows-installer.exe
					if(ext=='run' && left(name,6)=='lucee-') return true; // lucee-4.5.3.020-pl0-windows-installer.exe
					if(ext=='jar' && left(name,6)=='lucee-') return true;
					if(ext=='zip' && (left(name,6)=='lucee-' || left(name,9)=='forgebox-')) return true;
					/*
					if(ext=='jar' && left(name,6)=='lucee-' || left(name,12)!='lucee-light-') {
						return true;
					}*/
					return false;
				});
			} catch (e){
				systemOutput("error directory listing versions on s3", true);
				systemOutput(e, true);
				if(isNull(application.s3VersionData))
					return application.s3VersionData;
				throw "cannot read versions from s3 directory";
			}
			systemOutput("s3Versions.list [#runId#] FETCHED #numberFormat(getTickCount()-start)#ms, #qry.recordcount# files on s3 found",1,1);
			//dump(qry);
			var data=structNew("linked");
			// first we get all
			var patterns=structNew('linked');
			patterns['express']='lucee-express-';
			patterns['light']='lucee-light-';
			patterns['zero']='lucee-zero-';
			patterns['fbl']='forgebox-light-';
			patterns['fb']='forgebox-';
			patterns['jars']='lucee-jars-';
			patterns['jar']='lucee-';

			loop query=qry {
				var ext=listLast(qry.name,'.');
				var version="";
				// core (.lco)
				var name=qry.name;
				if(ext=='lco') {
					var version=mid(qry.name,1,len(qry.name)-4);
					var type="lco";
				}
				else if(ext=='exe') {
					var version=mid(qry.name,7,len(qry.name)-10);
					version=replace(version,'-windows-x64-installer','');
					version=replace(version,'-windows-installer','');
					version=replace(version,'-pl0','');
					version=replace(version,'-pl1','');
					version=replace(version,'-pl2','');
					var type="win";
				}
				else if(ext=='run') {
					var version=mid(qry.name,7,len(qry.name)-10);
					var type=findNoCase('-x64-',version)?'lin64':'lin32';
					version=replace(version,'-linux-x64-installer','');
					version=replace(version,'-linux-installer','');
					version=replace(version,'-pl0','');
					version=replace(version,'-pl1','');
					version=replace(version,'-pl2','');
				}
				else if(ext=='war') {
					var version=mid(qry.name,7,len(qry.name)-10);
					var type="war";
				}
				// all others
				else {
					loop struct=patterns index="local.t" item="local.prefix" {
						var l=len(prefix);
						if(left(qry.name,l)==prefix) {
							var version=mid(qry.name,l+1,len(qry.name)-4-l);
							var type=t;
							if(type=="jars") type="jar";
							break;
						}
					}
				}

				// check version
				var arrVersion=listToArray(version,'.');
				if( arrayLen(arrVersion)!=4 ||
					!isNumeric(arrVersion[1]) ||
					!isNumeric(arrVersion[2]) ||
					!isNumeric(arrVersion[3])) continue;

				var arrPatch=listToArray(arrVersion[4],'-');
				if( arrayLen(arrPatch)>2 ||
					arrayLen(arrPatch)==0 ||
					!isNumeric(arrPatch[1])) continue;

				if(arrayLen(arrPatch)==2 &&
					arrPatch[2]!="SNAPSHOT" &&
					arrPatch[2]!="BETA" &&
					arrPatch[2]!="RC" &&
					arrPatch[2]!="ALPHA") continue;

				var vs=services.VersionUtils::toVersionSortable(version);
				//if(isNull(data[version])) data[version]={};
				data[vs]['version']=version;
				data[vs][type]=name;
				//data[version]['date-'&type]=qry.dateLastModified;
				//data[version]['size-'&type]=qry.size;
			}
			systemOutput("s3Versions.list [#runId#] SORT #numberFormat(getTickCount()-start)#ms, #len(data)# versions found ",1,1);
			// sort
			var _data = sortVersions(data);
			if ( len(_data) gt 0 ) // only cache good data
				fileWrite(cacheDir & cacheFile, serializeJSON(_data, false) );
			systemOutput("s3Versions.list [#runId#] END #numberFormat(getTickCount()-start)#ms, #len(_data)# versions found",1,1);

			if ( structCount(_data) eq 0 && !isNull(application.s3VersionData) )
				return application.s3VersionData; // emergency hotfix
			return application.s3VersionData=_data;
		}
		if ( !structKeyExists( application, "s3VersionData" ) ){
			// lock timed out, still use cache if found
			if ( fileExists( cacheDir & cacheFile ) ){
				systemOutput("s3List.versions load from cache (after lock)", true);
				var _data = deserializeJSON( fileRead(cacheDir & cacheFile), false );
				application.s3VersionData = sortVersions(_data);
			} else {
				throw "lock timeout readVersions() no cached found";
			}
		}
		return application.s3VersionData;
	}

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

	public function add(required string type, required string version) {
		setting requesttimeout="10000000";
		var versions=getVersions(true);
		var vs=services.VersionUtils::toVersionSortable(version);
		var mr=new MavenRepo();

		// move the jar to maven if necessary
		if(!structKeyExists(versions,vs) || !structKeyExists(versions[vs],'jar')) {
			maven2S3(mr,version,versions);
			SystemOutput("add: downloaded jar from maven:"&now(),1,1);
			versions = getVersions(true);
		}
		// create the artifact

		try {
			if( type != "jar" ){
				SystemOutput("add: createArtifacts (#type#):"&now(),1,1);
				createArtifacts(mr,versions[vs],type,true);
				versions = getVersions(true);
				SystemOutput("add: after creating artifact (#type#):"&now(),1,1);
			}
		} catch(e){
			SystemOutput(e.stacktrace,1,1);
		}
	}

	public function addMissing(includingForgeBox=false, skipMaven=false) {
		setting requesttimeout="1000000";
		systemOutput("start:"&now(),1,1);
		var started = getTickCount();

		var s3List=getVersions(true);
		systemOutput("build: getting data from S3:"&now(),1,1);
		local.mr=new MavenRepo();
		var missing={};
		if ( !arguments.skipMaven ){
			systemOutput("build: getting data from Maven:"&now(),1,1);
			var arr=mr.list('all',false);

			systemOutput("build: downloading jars:"&now(),1,1);
			var resetRequired = false;
			// get the jar if missing
			loop array=arr item="local.el" {
				if (!isNull(s3List[el.vs].jar)) continue;
				//maven2S3(mr,el.version,s3List);
				resetRequired = true;
			}
			if (resetRequired) 
				s3List = getVersions(true); //force reset();
		}
		// create the missing artifacts
		loop struct=s3List index="local.vs" item="local.el" {
			createArtifacts(mr,el,"",includingForgeBox);
		}
		systemOutput("build complete, all artifacts created in #numberFormat(getTickCount()-started)#,s",1,1);
		getVersions(true); //force reset();
	}

	private function maven2S3(mr,version,all) {
		if(left(version,1)<5) return;
		// ignore this versions
		if(listFind("5.0.0.20-SNAPSHOT,5.0.0.255-SNAPSHOT,5.0.0.256-SNAPSHOT,5.0.0.258-SNAPSHOT,5.0.0.259-SNAPSHOT",version)) {
			structDelete(all,version,false);
			return;
		}

		var trg=variables.s3Root&"lucee-"&version&".jar";

		lock name="download from maven-#version#" timeout="1" {
			systemOutput("downloading from maven-#version#",1,1);
			// add the jar
			var info=mr.get(version, true);
			if(isNull(info.sources.jar.src)) {
				systemOutput("404:"&version,1,1);
				structDelete(all,version,false);
				return;
			}
			var src=info.sources.jar.src;
			var date=parseDateTime(info.sources.jar.date);

			if (!fileExists(src)) {
				structDelete(all,version,false);
				systemOutput("404:"&src,1,1);
				return;
			}
			// copy jar from maven to S3
			fileCopy(src,trg);

			systemOutput("200:"&trg,1,1);
			all[version]['jar']=true;
			all[version]['date-jar']=date;
		}
	}

	private function createArtifacts(mr,s3,specType="",includingForgeBox=true) {
		if(left(s3.version,1)<5) return;

		var jarRem=variables.s3Root&"lucee-"&s3.version&".jar";

		try {
			lock name="build-lucee-artifacts-#s3.version#" timeout="1" {
				try {
					// check and if necessary create other artifacts
					var list="lco,war,light,express";
					if(includingForgeBox)list&=",fb,fbl";

					systemOutput("Starting ( #s3.version# )",1,1);
					var c= 0;

					loop list=list item="local.type" {
						if ( len( specType ) && specType!=type ) continue;
						if ( structKeyExists( s3, type ) ) continue;
						c++;
						var s = getTickCount();
						// first we need a local copy of the jar
						var lcl=getTempDirectory() & "/lucee-"&s3.version&".jar";
						try{
							if(!fileExists(lcl)) fileCopy(jarRem,lcl);
						}
						catch(e) {
							systemOutput(e,1,1);
							continue;
						}
						// extract lco and copy to S3
						if(type=="lco") {
							var result=createLCO(lcl,s3.version);
							systemOutput("lco: " & result & " " & numberFormat(getTickCount()-s),1,1);
						}
						else if(type=="fb") {
							var result=createForgeBox(lcl,s3.version,false);
							systemOutput("forgebox: " & result & " " & numberFormat(getTickCount()-s),1,1);
							//abort;
						}
						else if(type=="fbl") {
							var result=createForgeBox(lcl,s3.version,true);
							systemOutput("forgebox-light: " & result & " " & numberFormat(getTickCount()-s),1,1);
						}
						// create war and copy to S3
						else if(type=="war") {
							lock name="build-lucee-war" timeout="10" {
								var result=createWar(lcl,s3.version);
							}
							systemOutput("war: " & result & " " & numberFormat(getTickCount()-s),1,1);
						}
						// create war and copy to S3
						else if(type=="light") {
							var result=createLight(lcl,s3.version);
							systemOutput("light: " & result & " " & numberFormat(getTickCount()-s),1,1);
						}
						else if(type=="express") {
							lock name="build-lucee-express" timeout="10" {
								var result=createExpress(lcl,s3.version);
							}
							systemOutput("express: " & result & " " & numberFormat(getTickCount()-s),1,1);
						}
						else {
							systemOutput("unsupported: " & type &":"&s3.version,1,1);
							c--;
						}
					}
					systemOutput( "--- " & s3.version & " done #c# artifacts built",1,1);
				}
				catch (e){
					systemOutput("----------------------------------------------",1,1);
					systemOutput(cfcatch.stacktrace,1,1);
				}
				finally {
					if(!isNull(lcl) && fileExists(lcl)) fileDelete(lcl);
				}
			}
		} catch(e) {
			systemOutput( "--- " & s3.version & " already building, skipping, #e.message#",1,1);
		}
	}

	private function createLCO(jar,version) {
		var lco=getTempDirectory() & "/lucee-"&version&".lco";
		var trg=variables.s3Root&version&".lco";
		if ( fileExists( trg ) ) {
			systemOutput("--- " & trg & " already built, skipping", true);
		}
		try {
			fileCopy("zip://"&jar&"!core/core.lco",lco); // now extract
			fileMove(lco,trg);
		}
		finally {
			if(!isNull(lco) && fileExists(lco)) fileDelete(lco);
		}
		return trg;
	}

	private function createWar(jar,version) {
		var temp = getTemp( arguments.version );
		local.war=variables.s3Root&"lucee-"&version&".war";
		if ( fileExists( war ) ) {
			systemOutput("--- " & war & " already built, skipping", true);
		}
		local.warTmp=temp&"lucee-"&version&"-temp-"&createUniqueId()&".war";
		var curr=getDirectoryFromPath(getCurrenttemplatePath());

		var noLuceeServlet = checkVersionGTE( arguments.version, 6, 2 );
		systemOutput("Has LuceeServlet Version check, gte 6.2: #noLuceeServlet#", true );

		var warFolder = noLuceeServlet ? "war-6.2" : "war";

		try {
			// temp directory
			// create paths and dir if necessary
			local.build={};
			loop list="extensions,common,website,war" item="local.name" {
				local.tmp=curr & "build/" & name & "/";
				if ( name == "extensions" && !directoryExists( tmp ) ) 
					directoryCreate( tmp, true );
				if ( name == "war" ){
					tmp = curr & "build/" & warFolder & "/";
				}
				build[ name ] = tmp;
				
			}
			systemOutput( "---- createWar", true );
			systemOutput( build, true );

			// let's zip it
			zip action="zip" file=warTmp overwrite=true {
				zipparam source=build["extensions"] filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=jar entrypath="WEB-INF/lib/lucee.jar";
				zipparam source=build["common"];
				zipparam source=build["website"];
				zipparam source=build["war"];
			}
			fileMove(warTmp,war);
		}
		finally {
			if(!isNull(warTmp) && fileExists(warTmp)) fileDelete( warTmp );
		}
		return war;
	}

    private function createLight(jar, version, boolean toS3=true) {
        var sep=server.separator.file;
        var temp = getTemp( arguments.version );
		if ( directoryExists( temp ) )
			directoryDelete( temp, true );
		directoryCreate( temp );
		
		local.trg=variables.s3Root&"lucee-light-"&version&".jar";
		if ( fileExists( trg ) ) {
			// avoid double handling for forgebox light builds
			systemOutput("--- " & trg & " already built, skipping", true);
			var tempLight = getTempFile(getTempDirectory(), "lucee-light-"& version, "jar");
			fileCopy( trg, tempLight); // create a local temp file from s3
			return tempLight;
		}
		local.s = getTickCount();
        try {
            local.tmpLoader=temp&"lucee-loader-"&createUniqueId(); // the jar
            directoryCreate(tmpLoader);

            // unzip
            try{
				zip action="unzip" file=jar destination=tmpLoader;
            }
            catch(e) {
            	fileDelete(jar);
            	return "";
            }
            // rewrite trg
            var extDir=tmpLoader&sep&"extensions";
            if ( directoryExists( extDir ) ) directoryDelete(extDir,true); // deletes directory with all files inside
            directoryCreate( extDir ); // create empty dir again (maybe Lucee expect this directory to exist)

			// unzip core
            var lcoFile=tmpLoader&sep&"core"&sep&"core.lco";
            local.tmpCore=temp&"lucee-core-"&createUniqueId(); // the jar
            directoryCreate(tmpCore);
            zip action="unzip" file=lcoFile destination=tmpCore;
			// rewrite manifest
            var manifest=tmpCore&sep&"META-INF"&sep&"MANIFEST.MF";
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
        finally {
            if (toS3 && !isNull(tmpLoaderFile) && fileExists(tmpLoaderFile)) fileDelete(tmpLoaderFile);
            if (!isNull(tmpLoader) && directoryExists(tmpLoader)) directoryDelete(tmpLoader,true);
            if (!isNull(tmpCore) && directoryExists(tmpCore)) directoryDelete(tmpCore,true);
        }
        return toS3?trg:tmpLoaderFile;
    }

    private string function createExpress(required jar,required string version) {
		var sep=server.separator.file;
        var temp = getTemp( arguments.version );
		
		var trg=variables.s3Root&"lucee-express-"&version&".zip";
		if ( fileExists( trg ) ) {
			systemOutput("--- " & trg & " already built, skipping", true);
			return trg;
		}
		//todo this can overlapp?
		var curr=getDirectoryFromPath(getCurrenttemplatePath());

		// website trg
		var zipTmp=temp&"lucee-express-"&version&"-temp-"&createUniqueId()&".zip";
		var tmpTom="#temp#tomcat";
		// Create the express zip
		try {
			// extension directory
			local.extDir=local.curr&("build/extensions/");
			if (!directoryExists(extDir)) directoryCreate(extDir);

			// common directory
			local.commonDir=local.curr&("build/common/");
			//if (!directoryExists(commonDir)) directoryCreate(commonDir);

			// website directory
			local.webDir=local.curr&("build/website/");
			//if (!directoryExists(webDir)) directoryCreate(webDir);

			// unpack the servers
			zip action="unzip" file=#curr&("build/servers/tomcat.zip")# destination=tmpTom;

			// let's zip it
			zip action="zip" file=zipTmp overwrite=true {
				// tomcat server
				zipparam source=temp&"tomcat";
				// extensions to bundle
				zipparam source=extDir filter="*.lex" prefix="lucee-server/context/deploy";
				// jars
				zipparam source=jar entrypath="lib/ext/lucee.jar";
				// common files
				zipparam source=commonDir;
				// website files
				zipparam source=webDir prefix="webapps/ROOT";
			}
			fileMove( zipTmp , trg );
		}
		finally {
			if ( !isNull( zipTmp ) && fileExists( zipTmp) ) fileDelete( zipTmp );
			if ( !isNull( tmpTom ) && directoryExists( tmpTom ) ) directoryDelete( tmpTom, true );
		}
		return trg;
	}

	private string function createForgeBox(required jar,required string version, boolean light=false) {
		var sep=server.separator.file;
		var temp = getTemp( arguments.version );
		var curr=getDirectoryFromPath(getCurrenttemplatePath());
		var trg=variables.s3Root&"forgebox#( light ? '-light' : '' )#-"&version&".zip";
		if ( fileExists( trg ) ) {
			systemOutput("--- " & trg & " already built, skipping", true);
			return trg;
		}

		var zipTmp=temp&"forgebox#( light ? '-light' : '' )#-"&version&"-temp-"&createUniqueId()&".zip";
		try {
			// extension directory
			local.extDir=curr & "/build/extensions/";
			if(!directoryExists(extDir)) directoryCreate(extDir);

			// common directory
			local.commonDir=curr & "/build/common/";
			//if(!directoryExists(commonDir)) directoryCreate(commonDir);

			// war directory
			var noLuceeServlet = checkVersionGTE( arguments.version, 6, 2 );
			systemOutput("Has LuceeServlet Version check, gte 6.2: #noLuceeServlet#", true );
			local.warDir=curr & "/build/" & (noLuceeServlet ? "war-6.2" : "war") & "/";

			// create the war
			local.war=temp & "/engine.war";
			if ( light ) local.lightJar=createLight(jar, version, false);

			zip action="zip" file=war overwrite=true {
				zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=( light ? lightJar: jar) entrypath="WEB-INF/lib/lucee#( light ? '-light' : '' )#.jar";
				zipparam source=commonDir;
				zipparam source=warDir;
			}

			// create the json
			// Turn 1.2.3.4 into 1.2.3+4 and 1.2.3.4-rc into 1.2.3-rc+4
			var v=reReplace( arguments.version, '([0-9]*\.[0-9]*\.[0-9]*)(\.)([0-9]*)(-.*)?', '\1\4+\3' );
			local.json=temp&"/box.json";
			fileWrite(json,
'{
    "name":"Lucee #( light ? 'Light' : '' )# CF Engine",
    "version":"#v#",
    "createPackageDirectory":false,
    "location":"https://cdn.lucee.org/rest/update/provider/forgebox/#arguments.version##( light ? '?light=true' : '' )#",
    "slug":"lucee#( light ? '-light' : '' )#",
    "shortDescription":"Lucee #( light ? 'Light' : '' )# WAR engine for CommandBox servers.",
    "type":"cf-engines"
}');

			// create the war
			zip action="zip" file=zipTmp overwrite=true {
				zipparam source=war;
				zipparam source=json;
			}
			fileMove( zipTmp, trg );
		}
		finally {
			if(!isNull(lightJar) && fileExists(lightJar)) fileDelete(lightJar);
			if(!isNull(zipTmp) && fileExists(zipTmp)) fileDelete(zipTmp);
			if(!isNull(tmpTom) && directoryExists(tmpTom)) directoryDelete(tmpTom,true);
		}
		return trg;
	}

	private function getTemp( string version ){
		var temp = getTempDirectory() & createUniqueId() & "-#arguments.version#";
		if ( directoryExists( temp ) )
			directoryDelete( temp, true );
		directoryCreate( temp );
		return temp;
	}

	private function checkVersionGTE( version, major, minor ){
		var v = listToArray( arguments.version, "." );
		if ( v[ 1 ] gt arguments.major ) {
			return true;
		} else if ( v[ 1 ] eq arguments.major && v[ 2 ] gte arguments.minor ) {
			return true;
		}
		return false;
	}

}



