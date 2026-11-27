/**
 * @rest     true
 * @restPath /update/provider
 */
component {

	// Maven-only Cloud Run app: services are loaded in a background thread.
	// List/info requests wait for readiness, then use this revision's listing cache.
	// /healthcheck/ is a separate application and returns immediately.
	variables.mavenOnly   = true;
	variables.providerLog = "update-provider";
	variables.bound       = false;

	ALL_VERSION="0.0.0.0";
	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_NEW_CHANGELOG_VERSION="5.3.0.0";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";

	// forgebox/{version} redirects to the CommandBox engine package of that version
	variables.forgeboxEngineUrl = server.system.environment.FORGEBOX_ENGINE_URL ?: "https://downloads.ortussolutions.com/lucee/lucee/";
	if ( Right( variables.forgeboxEngineUrl, 1 ) != "/" ) variables.forgeboxEngineUrl &= "/";

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

	// requests only get here once the services are ready (Application.cfc answers 503 before that), the wait only
	// covers a request that was let in just before a reload
	private function _ensureServices( numeric timeoutMs=5000 ) {
		if ( variables.bound && _servicesReady() ) {
			return;
		}

		var started = GetTickCount();
		while ( !_servicesReady() && ( GetTickCount() - started ) < arguments.timeoutMs ) {
			if ( Len( application.servicesError ?: "" ) ) {
				throw( message="Maven provider services failed to load, retrying shortly: #application.servicesError#" );
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

	/**
	 * The serialised JSON of a listing (/info/{version}, /list), from memory (services.InfoListingCache), as the
	 * extension provider serves its /info: valid as long as the data it was built from is the same (the generation),
	 * once that changed the old one is still served and rebuilt in the background. An error answer is not cached,
	 * it is returned as "error" (the struct) so the next request tries again.
	 */
	private struct function _listingEntry( required string key, required string generation, required any producer ) {
		var make   = arguments.producer;
		var failed = {};
		try {
			return application.coreListingCache.get(
				  key        = arguments.key
				, generation = arguments.generation
				, producer   = function() {
					var data = make();
					if ( IsStruct( data ) && ( data.type ?: "" ) == "error" ) {
						failed.data = data;
						throw( type="UpdateProvider.NotCached", message=data.message ?: "error" );
					}
					return SerializeJSON( data );
				}
			);
		} catch ( UpdateProvider.NotCached e ) {
			if ( StructKeyExists( failed, "data" ) ) {
				return { error=failed.data };
			}
			rethrow;
		}
	}

	/**
	 * Answers a listing entry: the cached JSON as it is with ETag, Last-Modified and Cache-Control (or a 304), the
	 * data for the REST layer to serialise when the client wants another format than JSON, an error as before.
	 */
	private any function _answerListing( required struct entry ) {
		if ( StructKeyExists( arguments.entry, "error" ) ) {
			return arguments.entry.error;
		}
		if ( !services.HttpCaching::wantsJson() ) {
			return DeserializeJSON( arguments.entry.json );
		}
		services.HttpCaching::respondJson(
			  body         = arguments.entry.json
			, etag         = services.HttpCaching::weakEtag( arguments.entry.etag )
			, lastModified = arguments.entry.builtAt
		);
	}

	// the versions served (Maven metadata), a stale one is read again in the background
	private string function _versionsGeneration() {
		try {
			variables.coreVersions.refreshIfStale();
		} catch ( any e ) {
			logger( text="Core versions refresh could not be started: #e.message#", exception=e, type="error" );
		}

		return variables.coreVersions.getGeneration();
	}

	// the Jira issues the changelogs are built from, stale issues are fetched again in the background
	private string function _issuesGeneration() {
		var jira = variables.jiraChangelogService;

		try {
			jira.refreshIfStale();
		} catch ( any e ) {
			logger( text="Jira changelog refresh could not be started: #e.message#", exception=e, type="error" );
		}

		return jira.getIssuesGeneration();
	}

	// /info also has the changelog (Jira issues)
	private string function _infoGeneration() {
		return _versionsGeneration() & "|" & _issuesGeneration();
	}

	/**
	 * The cached changelog/{versionFrom}/{versionTo} (changelogDetailed with detailed) answer: { json, etag,
	 * generation, builtAt }. It only depends on the Jira issues, not on the core versions.
	 */
	public struct function changelogEntry( required string versionFrom, required string versionTo, boolean detailed=false ) {
		_ensureServices();

		var jira = variables.jiraChangelogService;
		var vf   = arguments.versionFrom;
		var vt   = arguments.versionTo;
		var det  = arguments.detailed;

		return _listingEntry( "update-changelog-" & vf & "-" & vt & "-" & ( det ? "detailed" : "short" ), _issuesGeneration(), function() {
			return jira.getChangeLog( versionFrom=vf, versionTo=vt, detailed=det );
		} );
	}

	/**
	 * The cached /info/{version} answer: { json, etag, generation, builtAt }, or { error } for an error answer.
	 */
	public struct function infoEntry( required string version, string language="en" ) {
		_ensureServices();

		var v    = arguments.version;
		var lang = arguments.language;

		return _listingEntry( "update-info-" & v & "-" & lang, _infoGeneration(), function() {
			return _getInfoUncached( v, "", lang );
		} );
	}

	/**
	 * The cached /list answer: { json, etag, generation, builtAt }, or { error } for an error answer.
	 */
	public struct function listEntry( string type="all", boolean extended=false ) {
		_ensureServices();

		var t   = arguments.type;
		var ext = arguments.extended;

		return _listingEntry( "update-list-" & t & "-" & ( ext ? "extended" : "short" ), _versionsGeneration(), function() {
			return _readListUncached( false, t, ext, false );
		} );
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
	remote function getInfo(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		string language="en" restargsource="url")
		httpmethod="GET" restpath="info/{version}" {

		// ioid is not part of the answer; flush is accepted and ignored, the answer is rebuilt in the background once
		// the versions or the changelog changed
		return _answerListing( infoEntry( arguments.version, arguments.language ) );
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
			// a stable install is never offered an alpha, nor a pre-release of another major.minor
			var latestKey = keys[ arrayLen( keys ) ];
			if ( ALL_VERSION!=version.display ) {
				latestKey = "";
				for ( var i=arrayLen( keys ); i>=1; i-- ) {
					if ( services.VersionUtils::isOfferableUpdate( versions[ keys[ i ] ].version, version.display ) ) {
						latestKey = keys[ i ];
						break;
					}
				}
			}
			// nothing to offer: the installed version is the latest one, so it is answered as "no update"
			latest.version = Len( latestKey ) ? versions[ latestKey ].version : version.display;
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
					"":variables.jiraChangelogService.getChangeLog( versionFrom=version.display, versionTo=latestVersion.display );

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
		httpmethod="GET,HEAD,OPTIONS" restpath="loader/{version}" {
		if ( _answerOptions() ) return;
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
		httpmethod="GET,HEAD,OPTIONS" restpath="light/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("light",arguments.version);
		return;
	}

	/**
	* function to download Zero Lucee Loader file (lucee-zero.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downZero(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="zero/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("zero",arguments.version);
		return;
	}

	/**
	* only for backward compatibility
	*/
	remote function downLoaderAll(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="loader-all/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("jar",arguments.version);
		return;
	}

		/**
	* only for backward compatibility
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="core/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("lco",arguments.version);
		return;
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
		httpmethod="GET,HEAD,OPTIONS" restpath="download/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("lco",arguments.version);
		return;
	}



	remote function downloadWar(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="war/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("war",arguments.version);
		return;
	}


	remote function downloadForgebox(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		boolean light=false restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="forgebox/{version}" {
		if ( _answerOptions() ) return;
		// a plain redirect, it needs no services and no storage
		var redirect = forgeboxEngineLocation( arguments.version, arguments.light );

		if ( !Len( redirect ) ) {
			content reset=true type="text/plain";
			header statuscode="404" statustext="Not Found";
			echo( "version [#arguments.version#] is not a Lucee version" );
			return;
		}

		header statuscode="302" statustext="Found";
		header name="Location" value=redirect;
		// a published version does not change
		header name="Cache-Control" value="public, max-age=86400";
		return;
	}

	/**
	 * Location of the CommandBox engine package of a Lucee version, "" if [version] is not a Lucee version.
	 * The qualifier is upper case, as in the version list (5.3.4.54-rc is 5.3.4.54-RC).
	 */
	public string function forgeboxEngineLocation( required string version, boolean light=false ) {
		var v = UCase( Trim( arguments.version ) );

		if ( !REFind( "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(-[A-Z]+)?$", v ) ) {
			return "";
		}

		return variables.forgeboxEngineUrl & v & "/cf-engine-" & v & ( arguments.light ? "-light" : "" ) & ".zip";
	}

	/**
	 * function to load 3rd party Bundle file, for example "/antlr/2.7.6"
	 * relocate to a download URL or directly serve the download as a binary (application/zip).
	 *
	 * A 302 to the jar on Maven Central or the Lucee repository (maven.lucee-services.com). A jar that is only inside
	 * an extension .lex is extracted once and kept in the bundle cache (Cloud Storage,
	 * <prefix><Bundle-SymbolicName>-<Bundle-Version>.jar): a 302 to it when the bucket has a public URL
	 * (BUNDLE_CACHE_PUBLIC_URL), otherwise the jar is sent from the bucket. Otherwise a 404.
	 * allowRedirect=false streams the jar from its URL instead of the redirect.
	 * HEAD answers like GET (Tomcat sends no body), OPTIONS answers the allowed methods.
	 *
	 * @httpmethod GET,HEAD,OPTIONS
	 * @restpath   download/{bundlename}/{bundleversion}
	 */
	remote function downloadBundle(
		  required string  bundleName           restargsource="Path"
		,          string  bundleVersion        restargsource="Path"
		,          boolean allowRedirect = true restargsource="url"
	) {
		if ( _answerOptions() ) return;
		_bind();
		if ( arguments.bundleName == 'lucee.core' ) {
			return downloadCore( arguments.bundleVersion );
		}

		var bundle = bundleDownloadService.findBundle( argumentCollection=arguments );
		if ( !StructCount( bundle ) ) {
			_doBundle404( argumentCollection=arguments );
			return;
		}

		// a .lex is not an OSGi bundle
		var bundleUrl = Len( bundle.url ?: "" ) && ListLast( ListFirst( bundle.url, "?" ), "." ) != "lex" ? bundle.url : "";
		if ( !Len( bundleUrl ) && Len( bundle.cacheObject ?: "" ) ) {
			// extracted from an extension .lex, in the bundle cache bucket that has no public URL
			return _serveCachedBundle( arguments.bundleName, arguments.bundleVersion );
		}
		if ( !Len( bundleUrl ) ) {
			_doBundle404( argumentCollection=arguments );
			return;
		}
		if ( arguments.allowRedirect ) {
			return _relocateForDowload( bundleUrl, arguments.bundleVersion );
		}
		return _serveBundleUrlLocally( bundleUrl, bundle.cacheExpires ?: "" );
	}

	/**
	 * OPTIONS on a download route: 204 with the allowed methods, no lookup and no services needed.
	 */
	private boolean function _answerOptions() {
		if ( UCase( cgi.request_method ?: "" ) != "OPTIONS" ) {
			return false;
		}
		content reset=true;
		header statuscode="204" statustext="No Content";
		header name="Allow" value="GET, HEAD, OPTIONS";
		header name="Cache-Control" value="public, max-age=86400";
		return true;
	}

	private function _relocateForDowload( required string bundleUrl, string bundleVersion="" ) {
		content reset=true;
		header statuscode="302" statustext="Found";
		header name="Location" value=arguments.bundleUrl;
		// a pinned bundle version does not change, a client (or a cache in between) can follow the redirect again
		header name="Cache-Control" value=services.DownloadCaching::forRedirect( arguments.bundleVersion );
	}

	/**
	 * A jar from the bundle cache (Cloud Storage, a bucket without public access): read from the bucket and sent.
	 * HEAD answers the headers only, without reading the jar.
	 */
	private function _serveCachedBundle( required string bundleName, required string bundleVersion ) {
		var fileName = arguments.bundleName & "-" & arguments.bundleVersion & ".jar";
		var bytes    = "";
		if ( UCase( cgi.request_method ?: "" ) != "HEAD" ) {
			try {
				bytes = bundleDownloadService.readCachedBundle( arguments.bundleName, arguments.bundleVersion );
			} catch ( any e ) {
				SystemOutput( "Could not read [#fileName#] from the bundle cache: #e.message#", true );
				_doBundle404( argumentCollection=arguments );
				return;
			}
		}
		content reset=true;
		// a jar of a bundle version does not change
		header name="Cache-Control" value="public, max-age=2592000";
		header name="Content-Disposition" value="attachment; filename=""#fileName#""";
		if ( IsBinary( bytes ) ) {
			content type="application/java-archive" variable=bytes;
		} else {
			content type="application/java-archive";
		}
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

		var entry = infoEntry( arguments.version, "en" );
		local.info = StructKeyExists( entry, "error" ) ? entry.error : DeserializeJSON( entry.json );
		systemOutput(version&"->	"&structkeyExists(info,"available"),true,true);


		if(structkeyExists(info,"available")) return info.available;
		return "";
	}

	// cached as JSON with ETag, as info/{version}, see changelogEntry()
	remote function getChangeLog(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelog/{versionFrom}/{versionTo}" {

		// another format than JSON: the REST layer serialises the changelog as before (dates of the detailed one stay dates)
		if ( !services.HttpCaching::wantsJson() ) {
			_bind();
			return variables.jiraChangelogService.getChangeLog( versionFrom=arguments.versionFrom, versionTo=arguments.versionTo );
		}
		return _answerListing( changelogEntry( arguments.versionFrom, arguments.versionTo, false ) );
	}

	remote function getChangeLogExtended(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelogDetailed/{versionFrom}/{versionTo}" {

		// another format than JSON: the REST layer serialises the changelog as before (dates of the detailed one stay dates)
		if ( !services.HttpCaching::wantsJson() ) {
			_bind();
			return variables.jiraChangelogService.getChangeLog( versionFrom=arguments.versionFrom, versionTo=arguments.versionTo, detailed=true );
		}
		return _answerListing( changelogEntry( arguments.versionFrom, arguments.versionTo, true ) );
	}

	remote string function getChangeLogLastUpdated()
		httpmethod="GET" restpath="changelogLastUpdated" {
		_bind();
		// systemOutput("jiraChangelogService.getChangeLogUpdated():" & jiraChangelogService.getChangeLogUpdated(), true);
		return DateTimeFormat(variables.jiraChangelogService.getChangeLogUpdated());
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function downloadDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="dependencies/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		var build = _dependencies( "zip", arguments.version );
		if ( build.status != "done" ) {
			return _dependenciesNotReady( build, arguments.version );
		}
		local.path = build.result;

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

		var build = _dependencies( "list", arguments.version );
		if ( build.status != "done" ) {
			return _dependenciesNotReady( build, arguments.version );
		}
		return build.result;
	}

	/**
	 * The dependencies of a core version are built from all the jars of its pom, which can take minutes.
	 * A request waits for that at most DEPENDENCIES_WAIT_SECONDS (default 180, kept below the
	 * request timeout) and returns the zip or the list itself when the build finishes in time.
	 * The build goes on in the background, one per version and kind; a request only answers 503
	 * with Retry-After when that wait is exceeded. A version that is not a core version is
	 * answered right away.
	 *
	 * A build left in "running" after its thread has died, or for longer than
	 * DEPENDENCIES_STALE_SECONDS (default 600), is started again instead of answering 503 forever.
	 */
	private struct function _dependencies( required string kind, required string version ) {
		if ( !StructKeyExists( variables.coreVersions.getVersions(), services.VersionUtils::toVersionSortable( arguments.version ) ) ) {
			return { status="unknown" };
		}

		var key = arguments.kind & ":" & arguments.version;
		var deadline = GetTickCount() + ( _dependenciesWaitSeconds() * 1000 );
		var build = {};

		while ( true ) {
			lock name="update-provider-dependencies" type="exclusive" timeout=5 {
				if ( !StructKeyExists( application, "dependencyBuilds" ) ) {
					application.dependencyBuilds = {};
				}
				build = application.dependencyBuilds[ key ] ?: {};
				// empty, a failed build after a minute, or a stale running build: start one
				if ( StructIsEmpty( build ) || _dependenciesShouldRestart( build ) ) {
					build = _dependenciesStart( key, arguments.kind, arguments.version );
				}
			}
			if ( build.status != "running" || GetTickCount() >= deadline ) {
				return build;
			}
			sleep( 100 );
		}
	}

	private struct function _dependenciesStart( required string key, required string kind, required string version ) {
		var threadName = "dependencies-#Hash( arguments.key )#-#CreateUUID()#";
		var build = { status="running", started=Now(), threadName=threadName };
		application.dependencyBuilds[ arguments.key ] = build;
		// thread attributes are copies, the thread updates the entry of the application scope
		thread name="#threadName#" action="run" key=arguments.key kind=arguments.kind version=arguments.version threadName=threadName {
			local.entry = application.dependencyBuilds[ attributes.key ];
			try {
				local.entry.javaThread = CreateObject( "java", "java.lang.Thread" ).currentThread();
				local.mr = new services.legacy.MavenRepo();
				local.result = attributes.kind == "zip" ? local.mr.getDependencies( attributes.version ) : local.mr.getOSGiDependencies( attributes.version, true );
				// a newer start of the same key must not be overwritten by this thread
				if ( ( application.dependencyBuilds[ attributes.key ].threadName ?: "" ) != attributes.threadName ) {
					return;
				}
				local.entry.result = local.result;
				local.entry.ended  = Now();
				local.entry.status = "done";
			}
			catch ( any e ) {
				if ( ( application.dependencyBuilds[ attributes.key ].threadName ?: "" ) != attributes.threadName ) {
					return;
				}
				local.entry.error  = e.message;
				local.entry.ended  = Now();
				local.entry.status = "failed";
				WriteLog( text="dependencies #attributes.kind# #attributes.version#: #e.message#", type="error", log="update-provider" );
			}
		}
		return build;
	}

	private boolean function _dependenciesShouldRestart( required struct build ) {
		if ( arguments.build.status == "failed" && DateDiff( "s", arguments.build.ended, Now() ) > 60 ) {
			return true;
		}
		if ( arguments.build.status != "running" ) {
			return false;
		}
		if ( !StructKeyExists( arguments.build, "started" ) || DateDiff( "s", arguments.build.started, Now() ) > _dependenciesStaleSeconds() ) {
			return true;
		}
		return !_dependenciesThreadIsAlive( arguments.build );
	}

	private boolean function _dependenciesThreadIsAlive( required struct build ) {
		if ( StructKeyExists( arguments.build, "javaThread" ) ) {
			try {
				return arguments.build.javaThread.isAlive();
			}
			catch ( any e ) {
				return false;
			}
		}
		// the worker has not stored its Java thread yet; only treat it as dead after a short grace
		return DateDiff( "s", arguments.build.started, Now() ) < 15;
	}

	private numeric function _dependenciesWaitSeconds() {
		var seconds = Val( server.system.environment.DEPENDENCIES_WAIT_SECONDS ?: 180 );
		if ( seconds <= 0 ) {
			seconds = 180;
		}
		var requestTimeout = Val( server.system.environment.REQUEST_TIMEOUT_SECONDS ?: 240 );
		if ( requestTimeout <= 0 ) {
			requestTimeout = 240;
		}
		// stay under the request timeout so Lucee does not kill the wait itself
		var maxWait = requestTimeout > 10 ? requestTimeout - 10 : requestTimeout;
		if ( seconds > maxWait ) {
			return maxWait;
		}
		return seconds;
	}

	private numeric function _dependenciesStaleSeconds() {
		var seconds = Val( server.system.environment.DEPENDENCIES_STALE_SECONDS ?: 600 );
		return seconds > 0 ? seconds : 600;
	}

	private function _dependenciesNotReady( required struct build, required string version ) {
		if ( arguments.build.status == "running" ) {
			header statuscode="503" statustext="Service Unavailable";
			header name="Retry-After" value="30";
			return { "type":"info", "message":"The dependencies of version #arguments.version# are being prepared, try again in a moment." };
		}
		if ( arguments.build.status == "failed" ) {
			header statuscode="500" statustext="Internal Server Error";
			var reason = arguments.build.error ?: "the dependencies could not be built";
			return { "type":"error", "message":"The dependencies of version #arguments.version# could not be built: #reason#" };
		}
		header statuscode="404" statustext="Not Found";
		return { "type":"error", "message":"The version #arguments.version# is not available." };
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
		) httpmethod="GET,HEAD,OPTIONS" restpath="latest/{version}/{type}/{distribution}/{format}" {
		if ( _answerOptions() ) return;
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

		// the debug answer (?abc) is not cached
		if ( StructKeyExists( url, "abc" ) ) {
			_ensureServices();
			return _readListUncached( false, arguments.type, arguments.extended, false );
		}

		// force and flush are accepted and ignored, the list is rebuilt in the background once the versions changed
		return _answerListing( listEntry( arguments.type, arguments.extended ) );
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

			// lower case keys, as the legacy provider answers them
			if ( extended ) return services.LowerKeys::copy( versions );
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
		try {
			return application.coreReleaseDate.get( arguments.version );
		}
		catch ( CoreReleaseDate.NotFound e ) {
			header statuscode="404" statustext="Not Found";
			return "";
		}
		catch ( e ) {
			var mess=  "maven.getDate() threw " & left(cfcatch.message,100);
			logger(text=mess, type="error");
			systemOutput(mess, true, true );
			return "";
		}
	}

	remote function readGetOnlyForDebugging(
		required string version restargsource="Path"
		,boolean extended restargsource="url")
		httpmethod="GET" restpath="get/{version}" {
		_bind();

		local.mr=new services.legacy.MavenRepo();
		try {
			return services.LowerKeys::copy( mr.get(arguments.version,arguments.extended) );
		}
		catch(e){
			return {"type":"error","message":e.message};
		}
	}

	remote function downloadExpress(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET,HEAD,OPTIONS" restpath="express/{version}" {
		if ( _answerOptions() ) return;
		_bind();

		redirectToCore("express",arguments.version);
		return;
	}

	remote function listMissing(boolean inclFB=false restargsource="url")
		httpmethod="GET" restpath="list-missing" {
		// no flat files, so nothing is missing
		return {};
	}

	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		// release builds still call this, there is nothing to build: the versions come from Maven
		return _nothingToDo();
	}

	/**
	 * the legacy provider deletes forgebox-*-SNAPSHOT.zip from S3, this provider has no S3 and builds no zips
	 */
	remote struct function cleanupForgeboxSnapshots(
		string token="" restargsource="url",
		boolean dryRun=false restargsource="url"
	) httpmethod="GET" restpath="cleanupForgeboxSnapshots" {
		return _nothingToDo();
	}

	remote struct function cleanupForgeboxSnapshotsPost(
		string token="" restargsource="url",
		boolean dryRun=false restargsource="url"
	) httpmethod="POST" restpath="cleanupForgeboxSnapshots" {
		return _nothingToDo();
	}

	// 200 for the maintenance calls of the legacy provider, this one serves from Maven and keeps no flat files
	private struct function _nothingToDo() {
		return { "type":"info", "message":"Nothing to do, this update provider serves from the Maven repositories only." };
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

		// the Maven layout fallback always builds a URL; 5.4.x has no zero jar, so
		// confirm the file is really there before sending the client to it
		if(structIsEmpty(file) || !_remoteArtifactExists(file.url ?: "")) {
			_artifactNotFound( type="core", version=arguments.version, qualifier=arguments.type );
			content type="text/plain";
			header statuscode="404" statustext="Not Found";
			echo("artifact #encodeForHtml(type)# for version #encodeForHtml(version)# does not exist");
			return;
		}

		header statuscode="302" statustext="Found";
		header name="Location" value=file.url;
		header name="Cache-Control" value=services.DownloadCaching::forRedirect( arguments.version );
	}

	/**
	 * Does the core artifact exist? The answer is kept in memory per URL (a found file for a day, a missing one for
	 * NOT_FOUND_CACHE_SECONDS, default 300), so a redirect costs no HEAD request to the repository on every download.
	 */
	private boolean function _remoteArtifactExists(required string artifactUrl) {
		if(!Len(arguments.artifactUrl)) {
			return false;
		}
		if ( !StructKeyExists( application, "remoteArtifactExists" ) ) {
			application.remoteArtifactExists = StructNew( "synchronized" );
		}
		var known = application.remoteArtifactExists[ arguments.artifactUrl ] ?: {};
		if ( StructCount( known ) && GetTickCount() < known.until ) {
			return known.exists;
		}

		var exists = true;
		var ttl    = 86400;
		try {
			http method="head" url=arguments.artifactUrl timeout=10 redirect=true throwonerror=false result="local.res";
			var code = Val(ListFirst(res.statuscode ?: (res.status_code ?: "0"), " "));
			exists = code >= 200 && code < 400;
			if ( !exists ) {
				var nf = Val( server.system.environment.NOT_FOUND_CACHE_SECONDS ?: 300 );
				ttl = nf > 0 ? nf : 300;
			}
		}
		catch(any e) {
			// if the check itself fails, still redirect rather than hide a real file, and ask again soon
			exists = true;
			ttl    = 60;
		}
		// bounded, a stream of made up versions cannot grow it without end
		if ( StructCount( application.remoteArtifactExists ) >= 5000 ) {
			StructClear( application.remoteArtifactExists );
		}
		application.remoteArtifactExists[ arguments.artifactUrl ] = { exists=exists, until=GetTickCount() + ( ttl * 1000 ) };
		return exists;
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
