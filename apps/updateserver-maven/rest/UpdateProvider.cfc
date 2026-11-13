/**
 * @rest     true
 * @restPath /update/provider
 */
component {

	// Maven-only Cloud Run app: services are loaded in a background thread and
	// bound lazily so a request can be served from the listing cache first.
	variables.mavenOnly   = true;
	variables.providerLog = "update-provider";
	variables.bound       = false;

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

	private boolean function _servicesReady() {
		return IsBoolean( application.servicesReady ?: false ) && application.servicesReady;
	}

	private function _ensureServices( numeric timeoutMs=120000 ) {
		if ( variables.bound && _servicesReady() ) {
			return;
		}

		var started = GetTickCount();
		while ( !_servicesReady() && ( GetTickCount() - started ) < arguments.timeoutMs ) {
			if ( Len( application.servicesError ?: "" ) ) {
				throw( message="Maven provider services failed to load: #application.servicesError#" );
			}
			sleep( 100 );
		}

		if ( !_servicesReady() ) {
			throw( message="Maven provider services are still starting, try again in a moment" );
		}

		variables.bundleDownloadService = application.bundleDownloadService;
		variables.s3Root                = application.coreS3Root ?: "";
		variables.cdnUrl                = application.coreCdnUrl ?: "";
		variables.jiraChangelogService  = application.jiraChangelogService;
		variables.coreVersions          = application.coreVersions;
		variables.bound                 = true;
	}

	private function _bind() {
		_ensureServices();
	}

	private any function _cachedListing( required string key, required any producer, boolean flush=false ) {
		var cache = application.listingCache;

		if ( !arguments.flush && !_servicesReady() ) {
			var hit = cache.peek( arguments.key );
			if ( !IsSimpleValue( hit ) || Len( hit ) ) {
				return hit;
			}
			_ensureServices();
		} else {
			_ensureServices();
		}

		return cache.get( arguments.key, arguments.producer, arguments.flush );
	}

	private void function _artifactNotFound( required string type, string version="", string qualifier="", string id="" ) {
		services.ArtifactNotFound::log(
			  type      = arguments.type
			, version   = arguments.version
			, qualifier = arguments.qualifier
			, id        = arguments.id
		);
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

		var flush = StructKeyExists( url, "flush" ) && ( IsBoolean( url.flush ) && url.flush );
		var key   = "update-info-" & arguments.version & "-" & arguments.language;

		return _cachedListing( key, function() {
			return _getInfoUncached( version, ioid, language );
		}, flush );
	}

	private struct function _getInfoUncached( required string version, string ioid="", string language="en" ) {
		try{
			local.version=toVersion(arguments.version);

			// no updates for versions smaller than ...
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_UPDATE_VERSION)))
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};



			var versions=variables.coreVersions.getVersions();

			// LDEV-6796: only the versions the calling Lucee can load, all of them for ALL_VERSION
			if(ALL_VERSION!=version.display)
				versions=variables.coreVersions.filterForCaller(versions,version);

			var keys=structKeyArray(versions);
			arraySort(keys,"textnocase");

			if(arrayLen(keys)==0)
				return {
					"type":"info",
					"message":"There is no update available for your version (#version.display#).",
					"otherVersions":[]
				};

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
		_bind();

		redirectToCore("jar",arguments.version);
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
		_bind();

		redirectToCore("light",arguments.version);
		return;
	}

	/**
	* only for backward compatibility
	*/
	remote function downLoaderAll(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="loader-all/{version}" {
		_bind();
		return downLoaderNew(version,ioid);
	}

		/**
	* only for backward compatibility
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="core/{version}" {
		_bind();
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
		_bind();

		redirectToCore("lco",arguments.version);
		return;
	}



	/**
	* function to download Lucee Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadWarHead(required string version restargsource="Path", string ioid="" restargsource="url")
		httpmethod="HEAD" restpath="war/{version}" {
		_bind();
			return downloadWar(version, ioid);
	}

	remote function downloadWar(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="war/{version}" {
		_bind();

		redirectToCore("war",arguments.version);
		return;
	}


	remote function downloadForgebox(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		boolean light=false restargsource="url")
		httpmethod="GET" restpath="forgebox/{version}" {
		_bind();
		return _notWithoutS3( "The forgebox download" );
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
		_bind();
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

		_artifactNotFound( type="bundle", id=arguments.bundleName, version=arguments.bundleVersion, qualifier="jar" );
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
		_bind();

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
		_bind();

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
		_bind();
		// the express templates are only in S3; this app has no S3
		return _notWithoutS3( "The list of the express templates" );
	}

	remote function reset()
		httpmethod="GET" restpath="reset" {
		_bind();
		new services.legacy.MavenRepo().reset();
		variables.coreVersions.reset();
		variables.jiraChangelogService.updateIssuesAsync(); // async
	}

	remote function getLatest(
			string version restargsource="path",
			string type restargsource="path", // stable rc beta snapshot all
			string distribution restargsource="path", // jar. light, zero
			string format restargsource="path" // redirect, string, url, info, filename
		) httpmethod="GET" restpath="latest/{version}/{type}/{distribution}/{format}" {
		_bind();

		try {
			var versions = variables.coreVersions.getVersions();

			if ( arguments.type eq "all" )
				arguments.type ="";
			if ( arguments.version eq 0 )
				arguments.version = "";

			// LDEV-6796: the version has to have the file, in the Maven layout or (the fallback) the flat files. If it hasn't, the next one is looked for
			var candidates = versions;
			var copied = false;
			var matchedVersion = "";
			var file = {};

			for ( var attempt=1; attempt<=10; attempt++ ) {
				matchedVersion = services.VersionUtils::matchVersion( candidates, arguments.type,
					arguments.version, arguments.distribution );  // i.e. 06.002.001.0048.000

				if ( len( matchedVersion ) eq 0 )
					break;

				file = variables.coreVersions.resolveFile( arguments.distribution, candidates[ matchedVersion ].version );

				// a flat file that is not there yet is not good enough here, it is only built for the downloads
				if ( !structIsEmpty( file ) && ( file.source eq "maven" || file.present ) )
					break;

				file = {};

				if ( !copied ) {
					candidates = duplicate( versions, false );
					copied = true;
				}

				structDelete( candidates, matchedVersion );
			}

			if ( len( matchedVersion ) eq 0 || structIsEmpty( file ) ){
				header statuscode="404";
				return "Requested version not found";
			}
			if ( len( arguments.format ) eq 0)
				arguments.format = "redirect";


			var _version = versions[ matchedVersion ].version; // i.e 6.2.1.48-SNAPSHOT

			var versionUrl = file.url;

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

		var cacheKey = "update-list-" & arguments.type & "-" & ( arguments.extended ? "extended" : "short" );

		return _cachedListing( cacheKey, function() {
			return _readListUncached( force, type, extended, flush );
		}, arguments.flush );
	}

	private function _readListUncached( boolean force=false, string type="all", boolean extended=false, boolean flush=false ) {
		try {

			var versions=duplicate(variables.coreVersions.getVersions(flush));

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
		_bind();
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
		_bind();

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
		_bind();

		redirectToCore("express",arguments.version);
		return;
	}

	remote function listMissing(boolean inclFB=false restargsource="url")
		httpmethod="GET" restpath="list-missing" {
		_bind();
		return _notWithoutS3( "The list of the missing flat files" );
	}

	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		_bind();
		return _notWithoutS3( "Building the flat files" );
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

	/**
	* LDEV-6796: redirects to the file of a type (jar, light, lco, war, express) of a version. The file in the Maven layout is the first
	* choice, the flat file on S3 is only the fallback (it is built when it is not there yet), see CoreVersions.
	*/
	private function redirectToCore(required string type, required string version) {
		_bind();
		var file=variables.coreVersions.resolveFile(type,version);

		if(structIsEmpty(file)) {
			_artifactNotFound( type="core", version=arguments.version, qualifier=arguments.type );
			content type="text/plain";
			header statuscode="404" statustext="Not Found";
			echo("artifact #encodeForHtml(type)# for version #encodeForHtml(version)# does not exist");
			abort;
		}

		header statuscode="302" statustext="Found";
		header name="Location" value=file.url;
	}

	/**
	* STORAGE=maven: what needs the flat files of S3 (reading, building or writing them) is not there, a 501
	*/
	private function _notWithoutS3(required string what) {
		content type="text/plain";
		header statuscode="501" statustext="Not Implemented";
		echo("#what# is not available, this update provider serves from the Maven repositories only (STORAGE=maven), without S3.");
	}

	private function createArtifactIfNecessary(type,version) {
		// Maven-only: never builds or writes flat files
		return;
	}
}
