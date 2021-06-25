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
		if(!flush && !isNull(application.s3VersionData)) return application.s3VersionData;
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
		//dump(qry);
		var data=structNew("linked");
		// first we get all 
		patterns=structNew('linked');
		patterns['express']='lucee-express-';
		patterns['light']='lucee-light-';
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

			var vs=toVersionSortable(version);
			//if(isNull(data[version])) data[version]={};
			data[vs]['version']=version;
			data[vs][type]=name;
			//data[version]['date-'&type]=qry.dateLastModified;
			//data[version]['size-'&type]=qry.size;
		}
		
		// sort
		var keys=structKeyArray(data);
		arraySort(keys,"textnocase");
		_data=structNew("linked");
		loop array=keys item="local.k" {
			_data[k]=data[k];
		}

		return application.s3VersionData=_data;
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
		var vs=toVersionSortable(version);
		var mr=new MavenRepo();

		// move the jar to maven if necessary
		if(!structKeyExists(versions,vs) || !structKeyExists(versions[vs],'jar')) {
			maven2S3(mr,version,versions);
			SystemOutput("after creating jar:"&now(),1,1);
		}
		// create the artifact
		if(type!="jar"){
			createArtifacts(mr,versions[vs],type,true);
			SystemOutput("after creating artifact (#type#):"&now(),1,1);
		}
		reset();
		SystemOutput("reset:"&now(),1,1);
	}

	public function addMissing(includingForgeBox=false) {

		setting requesttimeout="1000000";
		systemOutput("start:"&now(),1,1);

		
		var s3List=getVersions(true);
		systemOutput("after getting data from S3:"&now(),1,1);
		local.mr=new MavenRepo();
		var missing={};
		
		var arr=mr.list('all',false);
		systemOutput("after getting data from Maven:"&now(),1,1);
		
		// get the jar if missing
		loop array=arr item="local.el" {
			if(!isNull(s3List[el.vs].jar)) continue;
			maven2S3(mr,el.version,s3List);
		}
		systemOutput("after creating all jars:"&now(),1,1);

		// create the missing artifacts
		loop struct=s3List index="local.vs" item="local.el" {
			createArtifacts(mr,el,"",includingForgeBox);
		}
		systemOutput("after creating all artifacts:"&now(),1,1);
		reset();
	}

	private function maven2S3(mr,version,all) {
		if(left(version,1)<5) return;
		// ignore this versions
		if(listFind("5.0.0.20-SNAPSHOT,5.0.0.255-SNAPSHOT,5.0.0.256-SNAPSHOT,5.0.0.258-SNAPSHOT,5.0.0.259-SNAPSHOT",version)) {
			structDelete(all,version,false);
			return;
		}
		
		var trg=variables.s3Root&"lucee-"&version&".jar";

		// add the jar
		var info=mr.get(version, true);
		if(isNull(info.sources.jar.src)) {
			systemOutput("404:"&version,1,1);
			structDelete(all,version,false);
			return;
		}
		var src=info.sources.jar.src;
		var date=parseDateTime(info.sources.jar.date);
		
		if(!fileExists(src)) {
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

	private function createArtifacts(mr,s3,specType="",includingForgeBox=true) {
		if(left(s3.version,1)<5) return;

		var jarRem=variables.s3Root&"lucee-"&s3.version&".jar";
		
		try {
			// check and if necessary create other artifacts 
			var list="lco,war,light,express";
			if(includingForgeBox)list&=",fb,fbl";

			loop list=list item="local.type" {
				if(len(specType) && specType!=type) continue;
				if(structKeyExists(s3,type)) continue;


				systemOutput("check(#type#):"&s3.version,1,1);
				// first we need a local copy of the jar
				var lcl=expandPath("{temp-directory}/lucee-"&s3.version&".jar");
				try{
					if(!fileExists(lcl))fileCopy(jarRem,lcl);
				}
				catch(e) {
					systemOutput(e,1,1);
					continue;
				}
				

				// extract lco and copy to S3
				if(type=="lco") {
					var result=createLCO(lcl,s3.version);
					systemOutput("lco:"&result,1,1);
				}
				// create war and copy to S3
				else if(type=="war") {
					var result=createWar(lcl,s3.version);
					systemOutput("war:"&result,1,1);
				}
				// create war and copy to S3
				else if(type=="light") {
					var result=createLight(lcl,s3.version);
					systemOutput("light:"&result,1,1);
				}
				else if(type=="express") {
					var result=createExpress(lcl,s3.version);
					systemOutput("express:"&result,1,1);
				}
				else if(type=="fb") {
					var result=createForgeBox(lcl,s3.version,false);
					systemOutput("forgebox:"&result,1,1);
					//abort;
				}
				else if(type=="fbl") {
					var result=createForgeBox(lcl,s3.version,true);
					systemOutput("forgebox-light:"&result,1,1);
					//abort;
				}
				else {
					//systemOutput(type&":"&s3.version,1,1);
				}
			}
		}
		finally {
			if(!isNull(lcl) && fileExists(lcl))fileDelete(lcl);
		}
	}


	private function createLCO(jar,version) {
		var lco=expandPath("{temp-directory}/lucee-"&version&".lco");
		var trg=variables.s3Root&version&".lco";
		try {
			fileCopy("zip://"&jar&"!core/core.lco",lco); // now extract 
			fileMove(lco,trg);
		}
		finally {
			if(!isNull(lco) && fileExists(lco))fileDelete(lco);
		}
		return trg;
	}

	private function createWar(jar,version) {
		local.temp=expandPath("{temp-directory}/");
		local.war=variables.s3Root&"lucee-"&version&".war";
		local.warTmp=temp&"lucee-"&version&"-temp-"&createUniqueId()&".war";
		
		try {
			// temp directory

			// create pathes and dir if necessary
			local.build={};
			loop list="extensions,common,website,war" item="local.name" {
				local.tmp=expandPath("build/"&name&"/");
				if(!directoryExists(tmp))directoryCreate(tmp,true);
				build[name]=tmp;
			}
			
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
			if(!isNull(warTmp) && fileExists(warTmp))fileDelete(warTmp);
		}
		return war;
	}


    private function createLight(jar, version, boolean toS3=true) {
        var sep=server.separator.file;
        local.temp=expandPath("{temp-directory}/");
		local.trg=variables.s3Root&"lucee-light-"&version&".jar";
		

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
            

            // remove extensions
            var extDir=tmpLoader&sep&"extensions";
            if(directoryExists(extDir))directoryDelete(extDir,true); // deletes directory with all files inside
            directoryCreate(extDir); // create empty dir again (maybe Lucee expect this directory to exist)

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
            if(fileExists(lcoFile))fileDelete(lcoFile);
            zip action="zip" source=tmpCore file=lcoFile;
            
            // zip loader
            local.tmpLoaderFile=temp&"lucee-loader-"&createUniqueId()&".jar";
            zip action="zip" source=tmpLoader file=tmpLoaderFile;

			//if(fileExists(light)) fileDelete(light);
            if(toS3)fileMove(tmpLoaderFile,trg);
        }
        finally {
            if(toS3 && !isNull(tmpLoaderFile) && fileExists(tmpLoaderFile)) fileDelete(tmpLoaderFile);
            if(!isNull(tmpLoader) && directoryExists(tmpLoader)) directoryDelete(tmpLoader,true);
            if(!isNull(tmpCore) && directoryExists(tmpCore)) directoryDelete(tmpCore,true);
        }
        return toS3?trg:tmpLoaderFile;
    }

    private string function createExpress(required jar,required string version) {
		var sep=server.separator.file;
        var temp=expandPath("{temp-directory}/");
		var trg=variables.s3Root&"lucee-express-"&version&".zip";
		var curr=getDirectoryFromPath(getCurrenttemplatePath());

		
		var zipTmp=temp&"lucee-express-"&version&"-temp-"&createUniqueId()&".zip";
		var tmpTom="#temp#tomcat";
		// Create the express zip
		try {
			
			// extension directory
			local.extDir=local.curr&("build/extensions/");
			if(!directoryExists(extDir))directoryCreate(extDir);

			// common directory
			local.commonDir=local.curr&("build/common/");
			if(!directoryExists(commonDir))directoryCreate(commonDir);

			// website directory
			local.webDir=local.curr&("build/website/");
			if(!directoryExists(webDir))directoryCreate(webDir);

			// unpack the servers
			zip action="unzip" file="#curr&("build/servers/tomcat.zip")#" destination=tmpTom;
			
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
			fileMove(zipTmp,trg);
		}
		finally {
            if(!isNull(zipTmp) && fileExists(zipTmp)) fileDelete(zipTmp);
            if(!isNull(tmpTom) && directoryExists(tmpTom)) directoryDelete(tmpTom,true);
		}


		return trg;
	}

	private string function createForgeBox(required jar,required string version, boolean light=false) {
		var sep=server.separator.file;
        var temp=expandPath("{temp-directory}/");
		var trg=variables.s3Root&"forgebox#( light ? '-light' : '' )#-"&version&".zip";

		var zipTmp=temp&"forgebox#( light ? '-light' : '' )#-"&version&"-temp-"&createUniqueId()&".zip";

		try {
			// extension directory
			local.extDir=expandPath("build/extensions/");
			if(!directoryExists(extDir))directoryCreate(extDir);

			// common directory
			local.commonDir=expandPath("build/common/");
			if(!directoryExists(commonDir))directoryCreate(commonDir);

			// war directory
			local.warDir=expandPath("build/war/");
			if(!directoryExists(warDir))directoryCreate(warDir);

			// create the war
			local.war=temp&"engine.war";
			if(light) local.lightJar=createLight(jar, version, false);
			zip action="zip" file=war overwrite=true {
				zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				zipparam source=( light ? lightJar: jar) entrypath="WEB-INF/lib/lucee#( light ? '-light' : '' )#.jar";
				zipparam source=commonDir;
				zipparam source=warDir;
			}

				// create the json
				// Turn 1.2.3.4 into 1.2.3+4 and 1.2.3.4-rc into 1.2.3-rc+4
				var v=reReplace( arguments.version, '([0-9]*\.[0-9]*\.[0-9]*)(\.)([0-9]*)(-.*)?', '\1\4+\3' );
				local.json=temp&"box.json";
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
				fileMove(zipTmp,trg);
			}
			finally {
	            if(!isNull(lightJar) && fileExists(lightJar)) fileDelete(lightJar);
	            if(!isNull(zipTmp) && fileExists(zipTmp)) fileDelete(zipTmp);
	            if(!isNull(tmpTom) && directoryExists(tmpTom)) directoryDelete(tmpTom,true);
			}

		
		return trg;
	}

	private function toVersionSortable(string version){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			throw "version number ["&arguments.version&"] is invalid";
		}
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()==2 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[2];
			if(sct.qualifier_appendix=="SNAPSHOT")sct.qualifier_appendix_nbr=0;
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix_nbr=75;
		}


		return 		repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}
}



