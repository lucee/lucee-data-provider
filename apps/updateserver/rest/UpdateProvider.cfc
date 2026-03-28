/**
 * @rest     true
 * @restPath /update/provider
 */
component {
	static {
		static.DEBUG = (server.system.environment.DEBUG ?: false);
	}
	variables.bundleDownloadService = application.bundleDownloadService;
	variables.s3Root                = application.coreS3Root;
	variables.cdnUrl                = application.coreCdnUrl;
	variables.jiraChangelogService  = application.jiraChangelogService;

	variables.providerLog = "update-provider";
	variables.LUCEE_MAVEN_CDN = "https://cdn.lucee.org/org/lucee/lucee";

	ALL_VERSION="0.0.0.0";
	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_NEW_CHANGELOG_VERSION="5.3.0.0";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";

	private function logger( string text, any exception, type="info", boolean forceSentry=false ){
		// var log = arguments.text & chr(13) & chr(10) & callstackGet('string');
		if ( !isNull(arguments.exception ) ){
			if (static.DEBUG) {
				if ( len(arguments.text ) ) systemOutput( arguments.text, true );
				systemOutput( arguments.exception, true );
			} else {
				WriteLog( text=arguments.text, type=arguments.type, log="exception", exception=arguments.exception );
				// Send errors and warnings to Sentry (case insensitive check)
				var normalizedType = lCase( arguments.type );
				if ( normalizedType == "error" || normalizedType == "warning" || normalizedType == "warn" ) {
					try {
						application.sentryLogger.logException( exception=arguments.exception, level=arguments.type );
					} catch ( any e ) {
						// Don't let Sentry failures break anything
					}
				}
			}
		} else {
			if (static.DEBUG) {
				systemOutput( arguments.text, true);
			} else {
				WriteLog( text=arguments.text, type=arguments.type, log=variables.providerLog );
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


	/**
	* MARK: /info
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
			string language="en" restargsource="url",
			string extended=true restargsource="url")
		httpmethod="GET" restpath="info/{version}" {

		try {
			var s3 = new services.legacy.S3(variables.s3Root);
			var rawList = s3.getVersions();
			var version = services.VersionUtils::toVersion(arguments.version);
			var list = [];
			loop array=rawList index="local.el" {
				arrayAppend(list,local.el.version);
			}
			var data = s3.getLuceeVersionsDetail( version.display );
			var index = arrayFindNoCase( list, version.display );
			var latest = list[len(list)];
			var len = arrayLen( list );
			arrayDeleteAt( list,index );
			var rtn= {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"latest":latest
				,"version": data.version?:""

				,"lastModified": data.lastModified?:""
				,"size": data.size?:"0"
				,"etag": data.etag?:""
				,"lco":data.lco?:createArtifactURL("lco",data.version)
				,"jar":data.jar
				,"light":data.light?:createArtifactURL("light",data.version)
				,"zero":data.zero?:createArtifactURL("zero",data.version)
				,"express":data.express?:createArtifactURL("express",data.version)
				,"war":data.war?:createArtifactURL("war",data.version)
				,"fb":data.forgebox?:createArtifactURL("fb",data.version)
				,"fbl":data["forgebox-light"]?:createArtifactURL("fbl",data.version)
			};


			if(arguments.extended) {
				rtn["otherVersions"]=list;
			}
			// we have an update?
			if(len>index) {
				rtn["available"]=latest;
				rtn["message"]="A patch (#latest#) is available for your current version (#version.display#).";
				if(arguments.extended) rtn["changelog"]=getChangeLogs(version, services.VersionUtils::toVersion(latest));
			}
			else {
				rtn["message"]="There is no update available for your version (#version.display#). Latest version is [#latest#]."
			}
			return rtn;
		}
		catch(e){
			logger( text=e.message, exception=e, type="error" );
			return {"type":"error","message":e.message,cfcatch:e};
		}
	}

	/*
	MARK: /download
	*/
	remote function downloadCore(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="download/{version}" {

		artifactDownloader( "lco", version );
	}

	/**
	 * MARK: /core
	*/
	remote function downloadCoreAlias(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="core/{version}" {

		artifactDownloader( "lco", version );
	}

	/**
	 * MARK: /lco
	*/
	remote function downloadLco(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="lco/{version}" {

		artifactDownloader( "lco", version );
	}

	/**
	 * MARK: /loader
	*/
	remote function downloadLoader(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="loader/{version}" {

		artifactDownloader( "loader", version );
	}
	
	/**
	* only for backward compatibility
	*/
	remote function downLoaderAll(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="loader-all/{version}" {

		artifactDownloader( "loader", version );
	}

	/**
	 * MARK: /jar
	*/
	remote function downloadJar(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="jar/{version}" {

		artifactDownloader( "loader", version );
	}

	/*
	MARK: /express
	*/
	remote function downloadExpress(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="express/{version}" {

		artifactDownloader( "express", version );
	}

	/**
	 * MARK: /light
	*/
	remote function downloadLight(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="light/{version}" {

		artifactDownloader( "light", version );
	}

	/**
	 * MARK: /zero
	*/
	remote function downloadZero(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="zero/{version}" {

		artifactDownloader( "zero", version );
	}

	/**
	 * MARK: /war
	*/

	remote function downloadWar(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="war/{version}" {

		artifactDownloader( "war", version );
	}

	/*
	MARK: /forgebox
	*/
	remote function downloadForgebox(
			required string version restargsource="Path",
			string ioid="" restargsource="url",
			boolean light=false restargsource="url")
		httpmethod="GET,HEAD" restpath="forgebox/{version}" {

		artifactDownloader( light?"forgebox-light":"forgebox", version );
	}

	/*
	MARK: /fb
	*/
	remote function downloadForgeboxAlias(
			required string version restargsource="Path",
			string ioid="" restargsource="url",
			boolean light=false restargsource="url")
		httpmethod="GET,HEAD" restpath="fb/{version}" {

		artifactDownloader( "forgebox", version );
	}

	/*
		MARK: /fbl
	*/
	remote function downloadForgeboxLight(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET,HEAD" restpath="fbl/{version}" {

		artifactDownloader( "forgebox-light", version );
	}

	/*
		MARK: /localDevRepo
		only for local development when not using a s3 bucket
	*/
	remote function downloadLocalDevRepo(
			required string mavenPath restargsource="url"
		)
		httpmethod="GET,HEAD" restpath="localDevRepo/" {

		if ( left( application.coreS3Root, 3 ) == "s3:" || mavenPath contains ".."){
			header statuscode=403;
			echo("access denied");
			return;
		}
		var localMavenPath = application.coreS3Root & arguments.mavenPath;
		if ( expandPath( application.coreS3Root & arguments.mavenPath) neq localMavenPath ){
			logger("bad localMavenPath: #localMavenPath#");
			header statuscode=403;
			echo("access denied");
			return;
		}
		if ( fileExists( localMavenPath ) ) {
			header name="Content-disposition" value="attachment;filename=#listlast(localMavenPath,'\/')#";
			content file="#localMavenPath#" type="application/octet-stream";
		} else {
			logger("localMavenPath not found: #localMavenPath#");
			header statuscode=404;
			echo("file not found");
			return;
		}
	}

	/**
	 * MARK: /echo
	 * echo functions are used by the lucee test suite
	*/
	remote function echoGET(
			string statusCode="" restargsource="url",
			string mimeType="" restargsource="url",
			string charset="" restargsource="url")
		httpmethod="GET" restpath="echoGet" {

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

	/**
	 * MARK: /download/{bundlename}/{bundleversion}
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
		logger(version&"->	"&structkeyExists(info,"available"));

		if(structkeyExists(info,"available")) return info.available;
		return "";
	}

	/*
	* MARK: /changelog
	*/
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
		// logger("jiraChangelogService.getChangeLogUpdated():" & jiraChangelogService.getChangeLogUpdated());
		if (isNull(jiraChangelogService.getChangeLogUpdated())) return now();
		return DateTimeFormat(jiraChangelogService.getChangeLogUpdated());
	}

	/**
	 * MARK: /dependencies
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
			logger( exception=e, type="error" );
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
			logger( exception=e, type="error" );
			return {"type":"error","message":"The version #version# is not available."};
		}
	}

	/*
	MARK: /expressTemplates
	*/

	remote function getExpressTemplates()
		httpmethod="GET" restpath="expressTemplates" {
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

	/*
	MARK: /latest
	*/

	remote function getLatest(
			string version restargsource="path",
			string type restargsource="path", // stable rc beta snapshot all
			string distribution restargsource="path", // jar. light, zero
			string format restargsource="path" // redirect, string, url, info, filename
		) httpmethod="GET" restpath="latest/{version}/{type}/{distribution}/{format}" {

		try {
			var s3 = new services.legacy.S3(variables.s3Root);
			var versions=services.VersionUtils::versionArrayToStruct(s3.getVersions());
			if ( arguments.type eq "all" )
				arguments.type ="";
			if ( arguments.version eq 0 )
				arguments.version = "";

			var matchedVersion = services.VersionUtils::matchVersion( versions, arguments.type,
				arguments.version, arguments.distribution );  // i.e. 06.002.001.0048.000

			if ( len( matchedVersion ) eq 0 ){
				header statuscode="404";
				return "Requested version not found";
			}
			if ( len( arguments.format ) eq 0)
				arguments.format = "redirect";


			var _version = versions[ matchedVersion ].version; // i.e 6.2.1.48-SNAPSHOT

			var versionUrl = "https://cdn.lucee.org/#versions[ matchedVersion ][ arguments.distribution ]#";

			switch (arguments.format){
				case "redirect":
					header statuscode="302" statustext="Found";
					header name="Location" value=versionUrl;
					return;
				case "string":
					return _version;
				case "filename":
					return versions[ matchedVersion ][ arguments.distribution ];
				case "url":
					return versionUrl;
				case "info":
					return {
						"url": versionUrl,
						"version": _version,
						"filename": versions[ matchedVersion ][ arguments.distribution ]
					};
				default:
					header statuscode="500";
					return "error: supported formats are [ redirect, string, url, info, filename ]";
			}
		}
		catch(e){
			header statuscode="500";
			logger(text=e.message, exception=e, type="error");
			echo (e.message);
		}
	}

	/*
	MARK: /list
	*/

	remote function readList(
			boolean force=false restargsource="url",
			string type='all' restargsource="url",
			boolean extended=false restargsource="url",
			boolean flush=false restargsource="url"
		)
		httpmethod="GET" restpath="list" {

		var rtn=arguments.extended?[:]:[];
		var ignores=["6.0.0.12-SNAPSHOT","6.0.0.13-SNAPSHOT","6.0.1.82","7.0.0.202"];
		var s3 = new services.legacy.S3(variables.s3Root);
		var versions=s3.getVersions( flush );

		// when working locally, route cdn requests thru /localDevRepo
		var localMaven = (left( application.coreS3Root, 3 ) != "s3:");

		loop array=versions index="local.el" {
			try {
				if(arrayContainsNoCase(ignores,el.version)) continue;
				local.sct=services.VersionUtils::toVersion(el.version);
				if(!arguments.extended) {
					arrayAppend(rtn,
						{
							"version":sct.display,
							"vs":sct.sortable
						});
				}
				else {
					if (localMaven) el = rewriteLocalMaven(el);

					rtn[local.sct.sortable]={
						"version": sct.display,
						"lastModified": el.lastModified?:"",
						"size": el.size?:"0",
						"etag": el.etag?:"",
						"lco":el.lco ?: createArtifactURL("lco",sct.display),
						"jar":el.jar,
						"light":el.light?:createArtifactURL("light",sct.display),
						"zero":el.zero?:createArtifactURL("zero",sct.display),
						"express":el.express?:createArtifactURL("express",sct.display),
						"war":el.war?:createArtifactURL("war",sct.display),
						"fb":el.forgebox?:createArtifactURL("fb",sct.display),
						"fbl":el["forgebox-light"]?:createArtifactURL("fbl",sct.display)
					};
				}
			}
			catch (any e) {
				logger( exception=e, type="error" );
			}
		}
		return rtn;
	}



	remote function getDate(required string version restargsource="Path")
		httpmethod="GET" restpath="getdate/{version}" {
		var s3 = new services.legacy.S3(variables.s3Root);
		var detail=s3.getLuceeVersionsDetail(version);

		// TODO get data from LuceeVersionsDetail, make it availabe there
		//if(static.DEBUG)  systemOutput(LuceeVersionsDetail(version), true, true);

		return detail.lastModified?:"";
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
			logger( exception=e, type="error" );
			return {"type":"error","message":e.message};
		}
	}

	remote function listMissing(
			boolean inclFB=false restargsource="url")
		httpmethod="GET" restpath="list-missing" {
		setting requesttimeout="100";
		var s3 = new services.legacy.S3(variables.s3Root);
		var versions=services.VersionUtils::versionArrayToStruct(s3.getVersions());
		var rtn=structNew("linked");
		var list="jar,lco,war,light,express";
		if(inclFB)list&=",forgebox,forgebox-light";
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
	 * MARK: /buildLatest
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {

		var indexDir=getDirectoryFromPath(getCurrentTemplatePath())&"index/";
		if(directoryExists(indexDir)) directoryDelete(indexDir, true);

		var s3=new services.legacy.S3(variables.s3Root);
		s3.buildLatest(true);
		return "done";
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

	/*
	MARK: artifactDownloader
	*/
	
	private function artifactDownloader( type, version ) {
		var _url=createArtifactIfNecessary( type, version );
		header statuscode="302" statustext="Found";
		if (structKeyExists(local,"_url")) {
			header name="Content-disposition" value="attachment;filename=#listlast( _url, '\/' )#";
			if (left( application.coreS3Root, 3 ) == "s3:"){
				header name="Location" value=_url;
			} else {
				// route thru /localDevRepo
				header name="Location" value=rewriteLocalMaven( { _url } )._url;
			}
		} else {
			// is this reachable, need to handle local dev repo? src is obviously wrong
			header name="Location" value="#LUCEE_MAVEN_CDN#/#arguments.version#/lucee-#arguments.version#.#arguments.type#";
		}
	}

	/*
	MARK: createArtifactIfNecessary
	*/

	private function createArtifactIfNecessary( type , version ) {
		var versionData=services.VersionUtils::toVersion( arguments.version );
		var s3=new services.legacy.S3( variables.s3Root );
		var data=s3.getLuceeVersionsDetail( versionData.display );
		
		logger("createArtifactIfNecessary(#type#,#version#) ---");

		// in case we have a link for it, no action is needed
		if (!isNull(data[arguments.type])) {
			logger("--- found a match: "&data[arguments.type]);
			return data[arguments.type];
		}
		logger("--- no match found, creating artifact");

		var threadName="t"&createUUID();
		thread s3=s3 name=threadName _type=type _version=version  {
			try{
				s3.add(_type,_version);
			}
			catch(e){
				logger( exception=e, type="error" );
			}
		}

		// wait for the thread to finish
		logger("Waiting for thread #threadName# to finish...");
		threadJoin(threadName,50000);

		// check if the artifact was created
		var data=s3.getLuceeVersionsDetail(versionData.display);
		
		if(!isNull(data[arguments.type])) {
			return data[arguments.type];
		}
		content type="text/plain";
		header statuscode="429" statustext="Still Building";
		echo("artifact #encodeForHtml(type)# for version #encodeForHtml(version)# does not exist yet, but we triggered the build for it. Try again in a couple minutes.");
		abort;
	}

	private function createArtifactURL(type,version) {
		return "#getBaseURL()##arguments.type#/#arguments.version#"; 
	}
	private function getBaseURL() {
		return application.updateProviderUrl;
	}

	private function getChangeLogs(struct version, struct latestVersion) {
		try {
			var newChangeLog=services.VersionUtils::isNewer(version, services.VersionUtils::toVersion(MIN_NEW_CHANGELOG_VERSION));
			local.notes=(ALL_VERSION==version.display)?
				"":getChangeLog(version.display,latestVersion.display);

			// do we need old layout of changelog?
			if(!services.VersionUtils::isNewer(version, services.VersionUtils::toVersion(MIN_NEW_CHANGELOG_VERSION))) {
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
			logger( exception=ee, type="error" );
			local.notes="";
		}
		return local.notes;
	}

	private function rewriteLocalMaven( src ){
		var st = [=];
		var l = len ( application.coreS3Root ) + 1;
		var baseUrl = getBaseURL();
		loop collection=#src# key="local.k" value="local.v" {
			if ( left( v, 1 ) eq "/" ){
				st[k] = baseUrl & "localDevRepo?mavenPath=#mid(v,l)#";
			} else {
				st[k] = v;
			}
		}
		return st;
	}

}