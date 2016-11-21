component restpath="/provider"  rest="true" {

	jiraListURL="https://luceeserver.atlassian.net/rest/api/2/project/LDEV/versions";
	jiraNotesURL="https://luceeserver.atlassian.net/secure/ReleaseNote.jspa?version={version-id}&styleName=Text&projectId=10000";

	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";


	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	variables.jarDirectory=variables.current&"bundles/";
	variables.artDirectory=variables.current&"artifacts/";
	variable.buildDirectory=variables.current&"builds/";

	/**
	* if there is a update the function is returning a struct like this:
	* {"type":"info"
	* ,"language":arguments.language
	* ,"current":arguments.version
	* ,"available":"5.0.0.1"
	* ,"message":"there is a update available for your version"
	* ,"changelog":{"2010":"eventhandling breaks property inheritance","2020":"SerializeJSON incorrecly outputs date"}
	* }
	* if there is no update, you get a struct like this:
	* {"type":"warning","message":"There is no update available for this version"}
	* 
	* @version current version installed
	* @ioid ioid of the requesting user
	* @langauage language f the requesting user
	*/
	remote struct function getInfo(required string version restargsource="Path",string ioid="" restargsource="url",required string language="en" restargsource="url")
		httpmethod="GET" restpath="info/{version}" {
		return _getInfo(version,ioid,language);
	}

	private struct function _getInfo(required string version ,string ioid="",required string language="en",boolean internal=false)
		httpmethod="GET" restpath="info/{version}" {
		

		if(findNoCase("snapshot",cgi.SERVER_NAME) || findNoCase("dev.",cgi.SERVER_NAME) || findNoCase("preview.",cgi.SERVER_NAME)) 
			local.type="snapshots";
		else if(findNoCase("release",cgi.SERVER_NAME) || findNoCase("stable.",cgi.SERVER_NAME) || findNoCase("www.",cgi.SERVER_NAME)) 
			local.type="releases";
		else if(findNoCase("beta",cgi.SERVER_NAME) || findNoCase("betasnap",cgi.SERVER_NAME)) 
			local.type="beta";
		else  return {
					"type":"warning",
					"message":"Version ["&version.display&"] is not supported for automatic updates."};

		try{
			local.version=toVersion(arguments.version);


			local.mr=new MavenRepo();
			local.latest=mr.getLatest(type);
			latestVersion=toVersion(latest.version);
			
			/* maintenance
			return {
					"type":"info",
					"message":"Server is down for maintance ATM, please try again later"};

			*/

			// no updates for versions smaller than ...
			if(!isNewer(version,toVersion(MIN_UPDATE_VERSION))) 
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};
			
			
			// no update
			if(!isNewer(latestVersion,version))
				return {
					"type":"info",
					"message":"There is no update available for your version (#version.display#).",
					"otherVersions":latest.otherVersions?:[]
				};


			try{local.notes=getVersionReleaseNotes(version.display,latestVersion.display,true);}catch(local.ee){local.notes="";}
			
			var msgAppendix="";
			if(!isNewer(version,toVersion(MIN_WIN_UPDATE_VERSION))) 
				msgAppendix="
				<div class=""error"">Warning! <br/>
				If this Lucee install is on a Windows based computer/server, please do not use the updater for this version due to a bug.  Instead download the latest lucee.jar from <a href=""http://stable.lucee.org/download/?type=snapshots"">here</a> and replace your existing lucee.jar with it.  This is a one-time workaround.";
			
			return {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"released":latest.jarDate
				,"available":latestVersion.display
				,"otherVersions":latest.otherVersions?:[]
				,"message":"A patch (#latestVersion.display#) is available for your current version (#version.display#)."&msgAppendix
				,"changelog":isSimpleValue(notes)?{}:notes/*readChangeLog(newest.log)*/
			}; // TODO get the right version for given version

			/*if(internal){
				rtn.file=newest.core;
			}*/

			//return rtn;
		}
		catch(e){
			log log="application" exception="#e#" type="error";
			return {"type":"error","message":e.message,cfcatch:e};
		}
	}





	remote array function getInfo2(required string version restargsource="Path",string ioid="" restargsource="url",required string language="en" restargsource="url")
		httpmethod="GET" restpath="info2/{version}" {
		return _getInfo2(version,ioid,language);
	}

	private array function _getInfo2(required string version ,string ioid="",required string language="en",boolean internal=false) {
		

		if(findNoCase("snapshot",cgi.SERVER_NAME) || findNoCase("dev.",cgi.SERVER_NAME) || findNoCase("preview.",cgi.SERVER_NAME)) 
			local.type="snapshots";
		else if(findNoCase("release",cgi.SERVER_NAME) || findNoCase("stable.",cgi.SERVER_NAME) || findNoCase("www.",cgi.SERVER_NAME)) 
			local.type="releases";
		else if(findNoCase("beta",cgi.SERVER_NAME) || findNoCase("betasnap",cgi.SERVER_NAME)) 
			local.type="beta";
		else  return {
					"type":"warning",
					"message":"Version ["&version.display&"] is not supported for automatic updates."};

		try{
			local.version=toVersion(arguments.version);


			local.mr=new MavenRepo();
			local.qry=mr.getAvailableVersions(type:type, extended:false, onlyLatest:false, checkIgnoreMajor:false);
			local.sct={};
			loop query=qry {
				sct[qry.vs]=qry.version;
			}

			local.keys=sct.keyArray().sort('text');
			local.arr=[];
			loop array=keys index='local.i' item='local.v' {
				arrayAppend(arr,sct[v]);
			}
			return arr;
/*
			// no updates for versions smaller than ...
			if(!isNewer(version,toVersion(MIN_UPDATE_VERSION))) 
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};
			
			
			// no update
			if(!isNewer(latestVersion,version))
				return {"type":"info","message":"There is no update available for your version (#version.display#)."};


			try{local.notes=getVersionReleaseNotes(version.display,latestVersion.display,true);}catch(local.ee){local.notes="";}
			
			var msgAppendix="";
			if(!isNewer(version,toVersion(MIN_WIN_UPDATE_VERSION))) 
				msgAppendix="
				<div class=""error"">Warning! <br/>
				If this Lucee install is on a Windows based computer/server, please do not use the updater for this version due to a bug.  Instead download the latest lucee.jar from <a href=""http://stable.lucee.org/download/?type=snapshots"">here</a> and replace your existing lucee.jar with it.  This is a one-time workaround.";
			
			return {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"released":latest.jarDate
				,"available":latestVersion.display

				,"message":"A patch (#latestVersion.display#) is available for your current version (#version.display#)."&msgAppendix
				,"changelog":isSimpleValue(notes)?{}:notes
			};
*/
		}
		catch(e){
			log log="application" exception="#e#" type="error";
			return {"type":"error","message":e.message,cfcatch:e};
		}
	}


/*

	*/


	/**
	* function to download Railo Loader file (lucee.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLoader(required string version restargsource="Path",string ioid="" restargsource="url", boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="loader/{version}" {
		local.mr=new MavenRepo();
		
		if(arguments.allowRedirect) {
			//return mr.getInfo(version);
			local.src=mr.getInfo(version:version,checkIgnoreMajor:false).jarSrc;
			header statuscode="302" statustext="Found";
			header name="Location" value=src;
			return;
		}



		try{
			local.path=mr.getLoader(version);
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=lucee-#version#.jar";
        content variable="#bin#" type="application/zip";
	}


	/**
	* function to download Railo Loader file (lucee-all.jar) that bundles all dependencies
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLoaderAll(required string version restargsource="Path",string ioid="" restargsource="url", boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="loader-all/{version}" {
		
		try{
			local.mr=new MavenRepo();
			setting requesttimeout="1000";
			local.path=mr.getLoaderAll(version,!isNull(url.doPack200));
		}
		catch(e){
			return {
				"type":"error"
				,"message":"The version #version# is not available."
				,"detail":e.message
				,"StackTrace":isNull(e.StackTraceAsString)?serialize(e.stacktrace):e.StackTraceAsString
				//,"cfcatch":serialize(structkeyList(e))
			};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=lucee-all-#version#.jar";
        content variable="#bin#" type="application/zip";
	}


	/**
	* function to download Railo Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean allowRedirect=false restargsource="url")
		httpmethod="GET" restpath="core/{version}" {
		return downloadCore(version,ioid,allowRedirect);
	}

	remote function echoGET() httpmethod="GET" restpath="echoGet" {return _echo();}
	remote function echoPOST() httpmethod="POST" restpath="echoPost" {return _echo();}
	remote function echoPUT() httpmethod="PUT" restpath="echoPut" {return _echo();}
	remote function echoDELETE() httpmethod="DELETE" restpath="echoDelete" {return _echo();}


	private function _echo() {
		sct={
			'httpRequestData':getHTTPRequestData()
			,'form':form
			,'url':url
			,'cgi':cgi
			,'session':session
		};
		//sct.ser=serialize(sct);
		return sct;
	}

	remote function downloadCore(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean allowRedirect=false restargsource="url")
		httpmethod="GET" restpath="download/{version}" {
		
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();

		// TODO get core and not loader
		if(false && arguments.allowRedirect) {
			local.src=mr.getInfo(version:version,checkIgnoreMajor:false).jarSrc;
			header statuscode="302" statustext="Found";
			header name="Location" value=src;
			return;
		}


		try{
			local.path=mr.getCore(version);
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=#version#.lco";
        content variable="#bin#" type="application/zip";
	}



	/**
	* function to download Railo Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadWar(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="war/{version}" {
		
		setting requesttimeout="1000";
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();
		try{
		local.path=mr.getWar(version);
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=#version#.war";
        content variable="#bin#" type="application/zip";
	}

	/** THIS IS NO LONGER NEEDED BECAUSE THE lucee.jar NOW CONTAINS THE FELIX JAR
	* function to download the files that need to go to the libs folder (felix and lucee jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadLibs(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="libs/{version}" {
		setting requesttimeout="1000";
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();
		try{
		local.path=mr.getLibs(version);
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=lucee-libs-#version#.zip";
        content variable="#bin#" type="application/zip";
	}


	/*
	* function to download Railo Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	
	remote function downloadUpdateX(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="downloadX/{version}" {
		
		local.version=toVersion(arguments.version);




		directory action="list" directory="#variable.buildDirectory#" name="local.dir" type="dir";
			
		// find the newest version
		var available="";
		loop query="#dir#" {
			local.v=toVersion(dir.name,true);
			if(!v.isEmpty() && isEqual(v,version)) {
				available=dir.directory&"/"&dir.name;
			}
		}

		if(available.isEmpty())
			return {"type":"error","message":"The version #version.display# is not available."};


		directory action="list" directory="#available#" name="local.core" type="file" filter="*.lco";
		if(core.recordcount!=1) 
			return {"type":"error","message":"The Version #version.display# is not available."};

		file action="readBinary" file="#core.directory#/#core.name#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=#version.display#.lco";
	    content variable="#bin#" type="application/zip"; // in future version this should be handled with producer attribute
	}*/

	/**
	* function to load 3 party Bundle file, for example "/antlr/2.7.6"
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadBundle(required string bundleName restargsource="Path", string bundleVersion restargsource="Path",
		string ioid="" restargsource="url",boolean allowRedirect=false restargsource="url")
		httpmethod="GET" restpath="download/{bundlename}/{bundleversion}" {
		
		// request for a core
		if(arguments.bundleName=='lucee.core') {
			return downloadCore(arguments.bundleVersion,arguments.ioid,arguments.allowRedirect);
		}

		// read json 
		var name=arguments.bundleName&"-"&arguments.bundleVersion&".json";
		var path=variables.artDirectory&name;
		var jsonPath=path;
		if(fileExists(path)) {
			var data=deserializeJson(fileRead(path));
		}

		// redirect to maven repo
		if(arguments.allowRedirect && !isNull(data.jar)) {
			header statuscode="302" statustext="Found";
			header name="Location" value=data.jar;
			return;
		}

		// first of all we look at the artifacts directory (lucee dependecies download automatically)
		var name=arguments.bundleName&"-"&arguments.bundleVersion&".jar"
		var path=variables.artDirectory&name;
		var orgName=name;
		var orgPath=path;


		if(!FileExists(path)) {
			// then we look at the bundles directory, here we have files uploaded manually
			
			// try different name patterns
			if(!FileExists(variables.jarDirectory&name)) // bundle-name-bundle.version
				name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
			if(!FileExists(variables.jarDirectory&name)) // bundle-name-bundle.version
				name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
			if(!FileExists(variables.jarDirectory&name)) // bundle.name-bundle-version
				name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
			if(!FileExists(variables.jarDirectory&name)) // bundle.name-bundle.version
				name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
			if(!FileExists(variables.jarDirectory&name)) // bundle.name.bundle.version
				name=replace(arguments.bundleName,'-','.','all')&"."&replace(arguments.bundleVersion,'-','.','all')&".jar";
			
			var path=variables.jarDirectory&name;
		}


		// download from Maven if we have a .json file
		if(!FileExists(path) && !isNull(data.jar)) {
			fileCopy(data.jar,orgPath);
			path=orgPath;
		}
		

		if(!FileExists(path)) {
			// last try, when the pattrn of the maven name matches the pattern of the osgi name we could be lucky
			var mvnRep="http://central.maven.org/maven2";
			var repositories=[
				mvnRep
				,"https://raw.githubusercontent.com/lucee/mvn/master/releases"
				,"https://oss.sonatype.org/content/repositories/snapshots"
				,"https://oss.sonatype.org/content/repositories/releases"
			];

			var uri="/"
				&replace(arguments.bundleName,'.','/','all')&"/"
				&arguments.bundleVersion&"/"
				&listLast(arguments.bundleName,'.')&"-"
				&arguments.bundleVersion&".jar";
			
			loop array=repositories item="local.rep" {
				if(fileExists(rep&uri)) {
					local.redirectURL=rep&uri;
					break;
				}
			}

			// ok an other last try, when "org.lucee" we know more about the pattern
			if(isNull(redirectURL) && left(arguments.bundleName,10)=='org.lucee.'){
				var art1=mid(arguments.bundleName,11);
				var art2=replace(art1,'.','-','all');
				
				var urls=[
					 mvnRep&"/org/lucee/"&art1&"/"&arguments.bundleVersion&"/"&art1&"-"&arguments.bundleVersion&".jar"
					,mvnRep&"/org/lucee/"&art2&"/"&arguments.bundleVersion&"/"&art2&"-"&arguments.bundleVersion&".jar"
				];
				loop array=urls item="local._url" {
					if(fileExists(_url)) {
						local.redirectURL=_url;
						break;
					}
				}
			}

				
			if(!isNull(redirectURL)){
				if(arguments.allowRedirect) {
					header statuscode="302" statustext="Found";
					header name="Location" value=redirectURL;
					return;
				}
				else {
					fileCopy(redirectURL,orgPath);
					filewrite(jsonPath,serialize({"jar":redirectURL,"local":path}));
					
					file action="readBinary" file="#orgPath#" variable="local.bin";
					header name="Content-disposition" value="attachment;filename=#name#";
			        content variable="#bin#" type="application/zip";

			        return;
				}
			}


			var text="no jar available for bundle "&arguments.bundleName&" in version "&arguments.bundleVersion;
			header statuscode="404" statustext="#text#";
			echo(text);
			// TODO write to a log
			file action="append" addnewline="yes" file="#variables.current#missing-bundles.txt"
			output="#arguments.bundleName#-#arguments.bundleVersion#->#path#" fixnewline="no";
            
		}
		else {

			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#name#";
	        content variable="#bin#" type="application/zip"; // in future version this should be handled with producer attribute
		}
	}

	/**
	* if there is a update the function is returning a sting with the available version, if not a empty string is returned
	* @version current version installed
	* @ioid ioid of the requesting user
	*/
	remote string function getInfoSimple(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="update-for/{version}" produces="application/lazy" {
		
		local.info=getInfo(version,ioid,"en");
		systemOutput(version&"->	"&structkeyExists(info,"available"),true,true);
		

		if(structkeyExists(info,"available")) return info.available;
		return "";
	}

	/**
	* if there is a update the function is returning a sting with the available version, if not a empty string is returned
	* @version current version installed
	* @ioid ioid of the requesting user
	*/
	remote struct function getChangeLog(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelog/{versionFrom}/{versionTo}" {
		
		return getVersionReleaseNotes( versionFrom, versionTo);
	}


	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function downloadDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="dependencies/{version}" {


		//local.version=toVersion(arguments.version);
		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			local.path=mr.getDependencies(version);
		}
		catch(e){
			//return e;
			return {"type":"error","message":"The version #version# is not available."};
		}

		file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=lucee-dependencies-#version#.zip";
	        content variable="#bin#" type="application/zip"; 
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function getDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="dependencies-read/{version}" {


		//local.version=toVersion(arguments.version);
		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			return mr.getOSGiDependencies(version,true);
		}
		catch(e){
			return {"type":"error","message":"The version #version# is not available."};
		}
 
	}

	/**
	* 
	*/
	remote function reset()
		httpmethod="GET" restpath="reset" {


		local.mr=new MavenRepo();
		mr.reset();
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function readInfo(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="info-read/{version}" {


		//local.version=toVersion(arguments.version);
		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			return mr.getInfo(version);
		}
		catch(e){
			return {"type":"error","message":"The version #version# is not available."};
		}
 
	}


	/**
	* function to get felix.jar for a specific version
	* @version version to get bundles for
	*/
	remote function downloadFelix(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="felix/{version}" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		

		if(arguments.allowRedirect) {
			//return mr.getInfo(version);
			local.src=mr.getFelixRemote(version);
			header statuscode="302" statustext="Found";
			header name="Location" value=src;
			return;
		}

		try{
			local.path=mr.getFelix(version);
		}
		catch(e){
			return {"type":"error","message":"Felix for the version #version# is not available."};
		}

		file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#listLast(path,'/')#";
	        content variable="#bin#" type="application/zip"; 
	}

	/**
	* function to get Lucee "express" for a specific version
	* @version version to get bundles for
	*/
	remote function downloadExpress(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="express/{version}" {


		//local.version=toVersion(arguments.version);
		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try{
			local.path=mr.getExpress(version);
		}
		catch(e){
			//throw serialize(e);
			return {"type":"error","message":"The version #version# is not available."};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=lucee-express-#version#.zip";
        content variable="#bin#" type="application/zip"; 
	}

	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		setting requesttimeout="1000";
		thread name="t#getTickCount()#" {


			local.mr=new MavenRepo();
			mr.flushAndBuild();
			application.releaseNotesItem={};
			application.releaseNotesData={};
		}
		return "done";
	}
	remote function buildLatestsync()
		httpmethod="GET" restpath="buildLatestSync" {
		setting requesttimeout="1000";
		

			local.mr=new MavenRepo();
			mr.flushAndBuild();
			application.releaseNotesItem={};
			application.releaseNotesData={};
		
		return "done";
	}


	private struct function toVersion(required string version, boolean ignoreInvalidVersion=false){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			if(ignoreInvalidVersion) return {};
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
		else throw "version number ["&arguments.version&"] is invalid";
		sct.pure=
					sct.major
					&"."&sct.minor
					&"."&sct.micro
					&"."&sct.qualifier;
		sct.display=
					sct.pure
					&(sct.qualifier_appendix==""?"":"-"&sct.qualifier_appendix);
		
		sct.sortable=repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;



		return sct;


	}

	private boolean function isNewer(required struct left, required struct right ){
		// major
		if(left.major>right.major) return true;
		if(left.major<right.major) return false;
		
		// minor
		if(left.minor>right.minor) return true;
		if(left.minor<right.minor) return false;
		
		// micro
		if(left.micro>right.micro) return true;
		if(left.micro<right.micro) return false;

		// qualifier
		if(left.qualifier>right.qualifier) return true;
		if(left.qualifier<right.qualifier) return false;
		
		if(left.qualifier_appendix_nbr>right.qualifier_appendix_nbr) return true;
		if(left.qualifier_appendix_nbr<right.qualifier_appendix_nbr) return false;
		
		if(left.qualifier_appendix_nbr==75 && right.qualifier_appendix_nbr==75) {
			if(left.qualifier_appendix>right.qualifier_appendix) return true;
			if(left.qualifier_appendix<right.qualifier_appendix) return false; // not really necessary
		}
		return false;
	}

	private boolean function isEqual(required struct left, required struct right ){
		if(left.major!=right.major) return false;
		if(left.minor!=right.minor) return false;
		if(left.micro!=right.micro) return false;
		if(left.qualifier!=right.qualifier) return false;
		if(left.qualifier_appendix!=right.qualifier_appendix) return false;

		return true;
	}

	/*private struct function readChangeLog(required string path){
		file action="read" file="#path#" variable="local.content";

		var res={};
		var arr=listToArray(content.trim(),"
");
		loop array="#arr#" item="local.v" {
			var i1=find('[',v);
			var i2=find(']',v);
			if(i1==0 || i2==0) continue;
			local.k=mid(v,i1+1,i2-2).replace('##','').trim();
			if(!isNumeric(k)) continue;
			res[k]=mid(v,i2+1).trim();
		}
		return res;
	}*/

	


/** returns version information from JIRA */
private function getVersionInfoFromJira( string version="" ) {
	// remove appendix
	local.version=len(version)?toVersion(arguments.version).pure:"";

	var empty = { id: 0, name: "", released: false, self: "" };

	try {
		http url=jiraListURL result="local.http";
		var raw = deserializeJSON( http.fileContent );

		var result = structNew("linked");
		for ( var ai in raw ) {
			var v = ai.name CT '(' ? listGetAt( ai.name, 2, "()" ) : ai.name;
			try{v=toVersion(v).pure;}catch(local.e){continue;}
			if(!isNumeric(listFirst(v,'.'))) continue;
			if(!isNull(ai.releaseDate))ai.releaseDate=dateAdd("m",0,ai.releaseDate);
			if ( len( version ) && v == version )
				return ai;
			result[ v ] = ai;
		}
		if ( len( version ))return empty;
		return result;

	}
	catch( ex ) {
		rethrow;
	}
}




/** 
* retruns the Release Notes from JIRA
* 
* @version - the Railo version, e.g. 4.0.3.005
*/
private struct function getVersionReleaseNotes( required string versionFrom, string versionTo="", boolean simple=false) {

	if(isNull(application.releaseNotesData)) application.releaseNotesData={};
	var coll=application.releaseNotesData;
		
	local.key=versionFrom&":"&versionTo;
	//if(!isNull(coll[key].data) && DateDiff('n',coll[key].date,now())<60)
	if(!isNull(coll[key].data))
		return coll[key].data;

	local.vFrom=toVersion(arguments.versionFrom);
	// single version
	if(versionTo=="")
		return _getVersionReleaseNotes(GetVersionInfoFromJira( vFrom.pure ));
	
	local.vTo=toVersion(arguments.versionTo);	

	// 05.000.000.0197.000...05.000.000.0206.000
	// ,05.000.000.0197.100,05.000.000.0205.100
	// multiple versions
	local.res=structNew("linked");
	local.versionInfo=GetVersionInfoFromJira();
	
	loop struct=versionInfo index="local.k" item="local.item" { 
		local.v=toVersion(item.name).sortable;
		// sct.sortable

		if(v >= vFrom.sortable && v <= vTo.sortable) {
			if(simple) _getVersionReleaseNotes(item,res);
			else res[item.name]=_getVersionReleaseNotes(item);
		}
	}
	application.releaseNotesData[key]={data:res,date:now()};
	return application.releaseNotesData[key].data;
}

private struct function _getVersionReleaseNotes( versionInfo ,struct fillHere=structNew("linked")) {
	if(versionInfo.id) {
		if(isNull(application.releaseNotesItem)) 
			application.releaseNotesItem={};
		
		var coll=application.releaseNotesItem;
		
		//if(!isNull(coll[versionInfo.id].data) && DateDiff('n',coll[versionInfo.id].date,now())<60) {
		if(!isNull(coll[versionInfo.id].data)) {
			loop struct=coll[versionInfo.id].data index="local.k" item="local.v" {
				fillHere[k]=v;
			}
			return coll[versionInfo.id].data;
		}
		
		local.res=structNew("linked");
		try {
			http url=replace( jiraNotesURL, "{version-id}", versionInfo.id ) result="Local.http";
			var raw = http.fileContent;
			var pos = find( "</textarea>", raw );
			raw = left( raw, pos - 1 );
			pos = find( "<textarea", raw );
			raw = mid( raw, pos );
			pos = find( ">", raw );
			raw = trim( mid( raw, pos + 1 ) );
			//var res = ;
			loop list=raw delimiters="#chr(13)##chr(10)#" index="Local.li" {
				pos = find( "[LDEV-", li );
				if ( pos==0 ) continue;
				
				local.v=trim( mid( li, pos ) );

				var i1=find('[',v);
				var i2=find(']',v);
				if(i1==0 || i2==0) continue;
				local.k=mid(v,i1+1,i2-2).replace('##','').trim();
				v=mid(v,i2+1).trim()
				if(left(v,1)=='-')v=mid(v,2).trim();
				//if(!isNumeric(k)) continue;
				res[k]=v;
				fillHere[k]=v;
			}
			application.releaseNotesItem[versionInfo.id]={data:res,date:now()}

			return application.releaseNotesItem[versionInfo.id].data;
		}
		catch ( ex ) {
			rethrow;
		}
	}

	return {};
}



}