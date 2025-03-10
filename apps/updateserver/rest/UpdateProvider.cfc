/**
 * @rest     true
 * @restPath /update/provider
 */
component {

	variables.bundleDownloadService = application.bundleDownloadService;
	variables.s3Root                = application.coreS3Root;
	variables.cdnUrl                = application.coreCdnUrl;
	variables.jiraChangelogService  = application.jiraChangelogService;

	variables.providerLog = "update-provider";
	
	ALL_VERSION="0.0.0.0";
	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_NEW_CHANGELOG_VERSION="5.3.0.0";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";
 	
	private function logger( string text, any exception, type="info" ){
		var log = arguments.text & chr(13) & chr(10) & callstackGet('string');
		if ( !isNull(arguments.exception ) )
			WriteLog( text=log, type=arguments.type, log=variables.providerLog, exception=arguments.exception );
		else
			WriteLog( text=log, type=arguments.type, log=variables.providerLog );
	}

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
	remote struct function getInfo(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		string language="en" restargsource="url")
		httpmethod="GET" restpath="info/{version}" {
		

		try{
			local.version=toVersion(arguments.version);

			// no updates for versions smaller than ...
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_UPDATE_VERSION))) 
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};
			


			local.s3=new services.legacy.S3(variables.s3Root);
			var versions=s3.getVersions();
			var keys=structKeyArray(versions);
			arraySort(keys,"textnocase");
			var latest = {};
			latest.version = versions[keys[arrayLen(keys)]].version;
			var latestVersion=toVersion(latest.version);
			
			// others
			latest.otherVersions=[];
			var maxSnap=400; 
			var maxRel=100;
			if(ALL_VERSION!=version.display) {
				for(var i=arrayLen(keys);i>=1;i--) {
					var el=versions[keys[i]];
					if(findNoCase("-SNAPSHOT",el.version)) {
						if ( ( --maxSnap )<=0 ) continue;
					}
					else {
						if ( ( --maxRel )<=0 ) continue;
					}
					arrayPrepend(latest.otherVersions,el.version);
				}
			}

			// no update
			if(ALL_VERSION!=version.display && !isNewer(latestVersion,version))
				return {
					"type":"info",
					"message":"There is no update available for your version (#version.display#). Latest version is [#latestVersion.display#].",
					"otherVersions":latest.otherVersions?:[]
				};

			try {
				var newChangeLog=isNewer(version,toVersion(MIN_NEW_CHANGELOG_VERSION));
				local.notes=(ALL_VERSION==version.display)?
					"":getChangeLog(version.display,latestVersion.display);

				// do we need old layout of changelog?	
				if(!isNewer(version,toVersion(MIN_NEW_CHANGELOG_VERSION))) {
					var nn=structNew("linked");
					loop struct=notes index="local.ver" item="local.dat" {
					    loop struct=dat index="local.k" item="local.v"{
					        nn[k]=v;
					    }
					} 
					notes=nn;
				}
			}
			catch(local.ee){
				local.notes="";
			}
			
			var msgAppendix="";
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_WIN_UPDATE_VERSION))) 
				msgAppendix="
				<div class=""error"">Warning! <br/>
				If this Lucee install is on a Windows based computer/server, please do not use the updater for this version due to a bug.  Instead download the latest lucee.jar from <a href=""http://stable.lucee.org/download/?type=snapshots"">here</a> and replace your existing lucee.jar with it.  This is a one-time workaround.";
			
			

			return {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"available":latestVersion.display
				,"otherVersions":latest.otherVersions?:[]
				,"message":"A patch (#latestVersion.display#) is available for your current version (#version.display#)."&msgAppendix
				,"changelog":isSimpleValue(notes)?{}:notes/*readChangeLog(newest.log)*/
			}; // TODO get the right version for given version
		}
		catch(e){
			logger( text=e.message, exception=e, type="error" );
			return {"type":"error","message":e.message,cfcatch:e};
		}
	}



	/**
	* function to download Lucee Loader file (lucee.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLoader(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET" restpath="loader/{version}" {

		createArtifactIfNecessary("jar",version);
			
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-"&arguments.version&".jar";
		return;
	}

	/**
	* function to download Light Lucee Loader file (lucee-light.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLight(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="light/{version}" {

		createArtifactIfNecessary("light",version);
	
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-light-"&arguments.version&".jar";
		return;
	}

	/**
	* only for backward compatibility
	*/
	remote function downLoaderAll(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="loader-all/{version}" {
		return downLoaderNew(version,ioid);
	}

		/**
	* only for backward compatibility
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="core/{version}" {
		return downloadCoreNew(version,ioid);
	}

	remote function echoGET(
				string statusCode="" restargsource="url",
				string mimeType="" restargsource="url",
				string charset="" restargsource="url") 
			httpmethod="GET"
			restpath="echoGet" {
		return _echo(arguments.statusCode, arguments.mimeType, arguments.charset);
	}
	remote function echoPOST() httpmethod="POST" restpath="echoPost" {return _echo();}
	remote function echoPUT() httpmethod="PUT" restpath="echoPut" {return _echo();}
	remote function echoDELETE() httpmethod="DELETE" restpath="echoDelete" {return _echo();}


	private function _echo(statusCode="", mimeType="", charset="") {
		var _cgi = {};
		loop list="request_method,server_protocol,path_info,http_user_agent" item="local.c" {
			_cgi[ local.c ] = cgi [ c ];
		}
		var sct={
			'httpRequestData':getHTTPRequestData()
			,'form':form
			,'url':url
			,'cgi': _cgi
			,'session':session
		};
		if ( !isEmpty( arguments.statusCode ) ){
			header statuscode=arguments.statusCode;
		}
		if ( !isEmpty( arguments.mimeType ) ){
			if ( !isEmpty( arguments.charset ) ){
				header name="Content-Type" value="#arguments.mimeType#;charset=#arguments.charset#";
			} else {
				header name="Content-Type" value="#arguments.mimeType#";
			}
		}
		//sct.ser=serialize(sct);
		return sct;
	}

	remote function downloadCore(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="download/{version}" {
		
		createArtifactIfNecessary("lco",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&arguments.version&".lco";
		return;
	}



	/**
	* function to download Lucee Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadWarHead(required string version restargsource="Path", string ioid="" restargsource="url")
		httpmethod="HEAD" restpath="war/{version}" {
			return downloadWar(version, ioid);
	}

	remote function downloadWar(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="war/{version}" {

		createArtifactIfNecessary("war",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-"&arguments.version&".war";
		return;
	}


	remote function downloadForgebox(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean light=false restargsource="url")
		httpmethod="GET" restpath="forgebox/{version}" {

		createArtifactIfNecessary(light?"fbl":"fb",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"forgebox-"&(light?"light-":"")&arguments.version&".zip";
		return;
	}

	/**
	 * function to load 3rd party Bundle file, for example "/antlr/2.7.6"
	 * relocate to a download URL or directly serve the download as a binary (application/zip).
	 *
	 * @httpmethod GET
	 * @restpath   download/{bundlename}/{bundleversion}
	 */
	remote function downloadBundle(
		  required string  bundleName           restargsource="Path"
		,          string  bundleVersion        restargsource="Path"
		,          boolean allowRedirect = true restargsource="url"
	) {
		if ( arguments.bundleName == 'lucee.core' ) {
			return downloadCore( arguments.bundleVersion );
		}

		var bundle = bundleDownloadService.findBundle( argumentCollection=arguments );

		if ( StructCount( bundle ) && Len( bundle.url ) ) {
			if ( arguments.allowRedirect ){
				return _relocateForDowload( bundle.url );
			}

			return _serveBundleUrlLocally( bundle.url, bundle.cacheExpires );
		}
		_doBundle404( argumentCollection=arguments );
	}

	private function _relocateForDowload( bundleUrl ) {
		header statuscode="302" statustext="Found";
		header name="Location" value=arguments.bundleUrl;
	}

	private function _serveBundleUrlLocally( bundleUrl, cacheExpires ) {
		var expires = IsDate( arguments.cacheExpires ) ? arguments.cacheExpires : DateAdd( "d", 30, Now() );
		var tmpFile = GetTempFile( GetTempDirectory(), "bundledownload" ) & "." & ListLast( bundleUrl, "." );
		var fileName = ListLast( arguments.bundleUrl, "/" );

		http url=arguments.bundleUrl file=tmpFile getasbinary=true;

		header name="cache-control" value="public, max-age=#DateDiff( "s", Now(), expires )#";
		header name="Content-Disposition" value="attachment; filename=""#fileName#""";
		content
			reset      = true
			file       = tmpFile
			type       = "application/x-zip-compressed"
			deletefile = true;
	}

	private function _doBundle404( bundleName, bundleVersion ) {
		var text = "No jar available for bundle " & arguments.bundleName & " in Version " & arguments.bundleVersion;

		logger( text=text, type="warn" );

		content reset=true;
		header statuscode="404" statustext=text;
		echo( text );
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

	remote struct function getChangeLog(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelog/{versionFrom}/{versionTo}" {
		
		return jiraChangelogService.getChangeLog( versionFrom=arguments.versionFrom, versionTo=arguments.versionTo );
	}

	remote struct function getChangeLogExtended(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelogDetailed/{versionFrom}/{versionTo}" {
		
		return jiraChangelogService.getChangeLog( versionFrom=arguments.versionFrom, versionTo=arguments.versionTo, detailed=true );
	}
	remote string function getChangeLogLastUpdated()
		httpmethod="GET" restpath="changelogLastUpdated" {
		// systemOutput("jiraChangelogService.getChangeLogUpdated():" & jiraChangelogService.getChangeLogUpdated(), true);
		return DateTimeFormat(jiraChangelogService.getChangeLogUpdated());
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function downloadDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="dependencies/{version}" {

		setting requesttimeout="1000";
		local.mr=new services.legacy.MavenRepo();
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

		setting requesttimeout="1000";
		local.mr=new services.legacy.MavenRepo();
		try {
			return mr.getOSGiDependencies(version,true);
		}
		catch(e){
			return {"type":"error","message":"The version #version# is not available."};
		}
	}

	remote function getExpressTemplates() httpmethod="GET" restpath="expressTemplates" {
		var s3 = new services.legacy.S3( variables.s3Root );
		var expressTemplates = duplicate( s3.getExpressTemplates() );
		loop collection=#expressTemplates# key="local.key" item="local.item"{
			expressTemplates[ key ] = application.coreCdnUrl & "express-templates/" & item;
		};
		return expressTemplates;
	}

	remote function reset()
		httpmethod="GET" restpath="reset" {
		new services.legacy.MavenRepo().reset();
		new services.legacy.S3(variables.s3Root).reset();
		jiraChangelogService.updateIssuesAsync(); // async
	}

	remote function getLatest(
		string version restargsource="path",
		string type restargsource="path",
		string distribution restargsource="path",
		string format restargsource="path" ) 
		httpmethod="GET" restpath="latest/{version}/{type}/{distribution}/{format}" {

		try {
			var s3 = new services.legacy.S3( variables.s3Root );
			var versions = s3.getVersions();
			var arrVersions = structKeyArray( versions ).reverse();
			var version = "";

			if ( arguments.type eq "all" )
				arguments.type ="";
			if ( arguments.version eq 0 )
				arguments.version = "";

			loop array=arrVersions index="local.i" value="local.v" {
				local.version = versions[local.v].version;
				local.type = listToArray(version, "-" );
				if ( arrayLen( type ) eq 2 && arguments.type eq "stable" ){
					version = "";
					continue;
				} else if ( len( arguments.type ) gt 0 && arguments.type neq "stable"){
					if ( arrayLen( type ) eq 1
						|| (type[ 2 ] neq arguments.type) ){
						version = "";
						continue;
					}
				}
				if ( len( arguments.version ) eq 0 ) {
					if ( structKeyExists( versions[local.v], arguments.distribution ) )
						break;
				} else if ( findNoCase(arguments.version, version ) neq 1) {
					version="";
					continue;
				} else {
					if ( structKeyExists( versions[ local.v ], arguments.distribution ) )
						break;
				}
			}
			if ( len( version ) eq 0 ){
				header statuscode="404";
				return "Requested version not found";
			}
			if ( len( arguments.format ) eq 0)
				arguments.format = "redirect";
			
			var versionUrl = "https://cdn.lucee.org/#versions[local.v][arguments.distribution]#";

			switch (arguments.format){
				case "redirect":
					header statuscode="302" statustext="Found";
					header name="Location" value=versionUrl;
					return;
				case "string":
					return version;
				case "filename":
					return versions[local.v][arguments.distribution];
				case "url":
					return versionUrl;
				case "info":
					return {
						"url": versionUrl,
						"version": version,
						"filename": versions[local.v][arguments.distribution]
					};
				default:
					header statuscode="500";
					return "error: supported formats are [ redirect, string, url, info ]";
			}	
		}
		catch(e){
			systemOutput( e, 1, 1 );
			header statuscode="500";
			logger(text=e.message, exception=e, type="error");
			echo (e.message);
		}
	}


	remote function readList(
		boolean force=false restargsource="url",
		string type='all' restargsource="url",
		boolean extended=false restargsource="url",
		boolean flush=false restargsource="url"
		)
		httpmethod="GET" restpath="list" {
		
		setting requesttimeout="1000";

		try {
			
			var s3=new services.legacy.S3(variables.s3Root);
			var versions=s3.getVersions(flush);

			if(!isNull(url.abc)){
				return versions;
			}

			var ignores=["6.0.0.12-SNAPSHOT","6.0.0.13-SNAPSHOT","6.0.1.82"];
			loop array=structKeyArray( versions ) item="local.k" {
				if ( !structKeyExists( versions[ k ], "version" ) 
						|| arrayFind( ignores, versions[k].version ) ){
					structDelete( versions, k );
				}
			}
			
			if ( extended ) return versions;
			var arr=[];
			loop struct=versions index="local.vs" item="local.data" {
				arrayAppend(arr,{'vs':vs,'version':data.version});
			}
			return arr;
		}
		catch(e){
			systemOutput( e, 1, 1 );
			logger( error=e.message, exception=e, type="error" );
			return {"type":"error","message":e.message};
		}
	}

	remote function getDate(required string version restargsource="Path")
		httpmethod="GET" restpath="getdate/{version}" {
		var mr=new services.legacy.MavenRepo();
		try{
			var info=mr.get(version,true);
			if(!isNull(info.sources.pom.date))
				return parseDateTime(info.sources.pom.date);
			else if(!isNull(info.sources.jar.date))
				return parseDateTime(info.sources.jar.date);
		} catch(e) {
			//systemOutput(e.stackTrace, true);
			var mess=  "maven.getDate() threw " & left(cfcatch.message,100);
			logger(text=mess, type="error");
			systemOutput(mess, true, true );
		}
		
		return "";
	}

	remote function readGetOnlyForDebugging(
		required string version restargsource="Path"
		,boolean extended restargsource="url")
		httpmethod="GET" restpath="get/{version}" {

		setting requesttimeout="1000";
		local.mr=new services.legacy.MavenRepo();
		try {
			return mr.get(arguments.version,arguments.extended);
		}
		catch(e){
			return {"type":"error","message":e.message};
		}
	}

	remote function downloadExpress(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="express/{version}" {
		
		createArtifactIfNecessary("express",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-express-"&arguments.version&".zip";
		return;
	}

	remote function listMissing(boolean inclFB=false restargsource="url")
		httpmethod="GET" restpath="list-missing" {
		setting requesttimeout="100";
		var s3=new services.legacy.S3(variables.s3Root);
		var versions=s3.getVersions(true);

		var rtn=structNew("linked");
		var list="jar,lco,war,light,express";
		if(inclFB)list&=",fb,fbl";
		loop list=list item="type" {
			
			loop struct=versions index="vs" item="data" {
				if(!structKeyExists(data,type) && left(data.version,1)>4) {
					if(isNull(rtn[type]))rtn[type]=[];
					arrayAppend(rtn[type],data.version);
				}
			}
		}
		return rtn;
	}

	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		
		var indexDir=getDirectoryFromPath(getCurrentTemplatePath())&"index/";
		if(directoryExists(indexDir)) directoryDelete(indexDir, true);
		
		
			var s3=new services.legacy.S3(variables.s3Root);
		s3.addMissing(true);
		return "done";
	}

	private boolean function isVersion(required string version) { 
		try{
			toVersion(version);
			return true;
		}
		catch(e) {
			return false;
		}
	}
	
	private struct function toVersion(required string version, boolean ignoreInvalidVersion=false){
		local.arr=listToArray(arguments.version,'.');
		if(arr.len()==3) {
			arr[4]="0";
		}
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			if(ignoreInvalidVersion) return {};
			throw ("version number ["&arguments.version&"] is invalid");
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
		else throw ("version number ["&arguments.version&"] is invalid");
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

	private function s3Exists(name) {
		if(!isNull(application.exists[name])) {
			return application.exists[name];
		}
		if(fileExists(variables.s3Root&name)) {
			application.exists[name]=true;
			return true;
		}
		application.exists[name]=false;
		return false;
	}

	/**
	* checks if file exists on S3 and if so redirect to it, if not it copies it to S3 and the next one will have it there.
	* So nobody has to wait that it is copied over
	*/
	private function fromS3(path,name,async=true) {
		
		// if exist we redirect to it
			if(!isNull(url.show))
				throw ((!isNull(application.exists[name]) && application.exists[name])&":"&fileExists(variables.s3Root&name)&"->"&(variables.s3Root&name));

			var hasDef=(!isNull(application.exists[name]) && application.exists[name]);
			if(hasDef || fileExists(variables.s3Root&name)) {
				application.exists[name]=true;
				header statuscode="302" statustext="Found";
				header name="Location" value=variables.cdnURL&name;
				return true;
			}
			// if not exist we make ready for the next
			else {

				if(async && isNull(url.show)) {
					thread src=path trg=variables.s3Root&name {
						lock timeout=1000 name=src {
							if(!fileExists(trg) && fileSize(src)>100000) // we do this because it was created by a thread blocking this thread
								_fileCopy(src,trg);
						}
					}
				}
				else {
					var src=path;
					var trg=variables.s3Root&name;
					lock timeout=1000 name=src {
						if(!fileExists(trg) && fileSize(src)>100000) {// we do this because it was created by a thread blocking this thread
							_fileCopy(src,trg);
							if(!isNull(url.show))
								throw ("fileExists: "&fileExists(src)&" + "&fileExists(trg));
						}
					}
				}	
			}
			return false;
	}

	private function _fileCopy(src,trg) {
		if(isSimpleValue(src) && findNoCase("http",src)==1) {
			// we do this because of 302 the function cannot handle
			http url=src result="local.res";
			if(isNull(res.statuscode) || res.statuscode!=200) {
				if(findNoCase("https://",src)) {
					src=replaceNoCase(src,"https://","http://");
					http url=src result="local.res";
				}

			}
			//throw src&":"&res.statuscode&":"&len(res.filecontent);
			if(isNull(res.statuscode) || res.statuscode!=200)
				throw (src & ":" & res.statuscode);
			if(len(res.filecontent)<1000) throw "file [#src#] is to small (#len(res.filecontent)#)";
			fileWrite(trg,res.filecontent);
		}
		else fileCopy(src,trg);
	}


	private function fileSize(path) {
	    var dir=getDirectoryFromPath(path);
	    var file=listLast(path,'\/');
	    directory filter=file name="local.res" directory=dir action="list";
	    return res.recordcount==1?res.size:0;
	}

	private function createArtifactIfNecessary(type,version) {
		var s3=new services.legacy.S3(variables.s3Root);
		var versions=s3.getVersions();
		var vs=services.VersionUtils::toVersionSortable(version);
		
		if(structKeyExists(versions,vs) && structKeyExists(versions[vs],type)) return;
		thread s3=s3 name=createUUID() _type=type _version=version  {
			try{
				setting requesttimeout="10000000";
				s3.add(_type,_version);
			}
			catch(e){
				fileWrite("error.txt",serialize(e));
			}
		}
		sleep(20000);
		versions=s3.getVersions();
		if(structKeyExists(versions,vs) && structKeyExists(versions[vs],type)) return; // all good, was built in the meantime
		content type="text/plain";
		header statuscode="429" statustext="Still Building";
		echo("artifact #encodeForHtml(type)# for version #encodeForHtml(version)# does not exist yet, but we triggered the build for it. Try again in a couple minutes.");
		abort;
	}
}