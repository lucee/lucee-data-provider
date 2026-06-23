component {
	static {
		static.DEBUG = (server.system.environment.DEBUG ?: false);
	}

	variables.providerLog = "update-provider";
	variables.NL="
";
	public function init(s3Root) {
		variables.s3Root=arguments.s3Root;
		if ( !structKeyExists( application, "s3VersionDetail" )) {
			application.s3VersionDetail = {};
		}
		if ( !structKeyExists( application, "s3Versions" )) {
			application.s3Versions = {};
		}
	}

	public void function reset() {
		logger( "s3.reset()");
		structDelete( application, "s3Versions", false );
		structDelete( application, "s3VersionDetail", false );
		structDelete( application, "expressTemplates", false );
		getVersions(flush=true);
	}

	/*
		MARK: GetVersions
	*/

	public function getVersions(boolean flush=false) {
		var rootDir = getDirectoryFromPath(getCurrentTemplatePath());
		var cacheDir=rootDir & "cache/";
		var cacheFile = "versions.json";

		lock name="check-version-cache" timeout="2" throwOnTimeout="false" {
			if (!directoryExists(cacheDir))
				directoryCreate(cacheDir);
			if ( isNull(application.s3Versions) && fileExists( cacheDir & cacheFile ) ){
				systemOutput("s3List.versions load from cache");
				application.s3Versions = deserializeJSON( fileRead(cacheDir & cacheFile), false );
			}
		}

		if ( !flush && !isEmpty(application.s3Versions) )
			return application.s3Versions;

		lock name="read-version-metadata" timeout="2" throwOnTimeout="false" {
			setting requesttimeout="1000";

			var runid = createUniqueID();
			var start = getTickCount();
			try {
				systemOutput("s3Versions.list [#runId#] START #numberFormat(getTickCount()-start)#ms",1,1);
				var data = getLuceeVersionsListS3();
				if ( len( data ) gt 0 ){ // only cache good data
					fileWrite( cacheDir & cacheFile, serializeJSON( data, false) );
					if ( serializeJson( application.s3Versions ) neq SerializeJson( data ) ){
						// only ping on change
						application.s3Versions = data;
						if ( structKeyExists( application, "downloadsUrl" ) ){
							var downloadRefeshUrl = "#application.downloadsUrl#?type=snapshots&reset=force";
							logger("Versions updated, pinging [#downloadRefeshUrl#]");
							try {
								cfhttp( url=downloadRefeshUrl );
							} catch (e){
								logger(message="error returned updating download server [#downloadRefeshUrl#]", exception=e, type="error");
							}
						} else {
							logger("Versions updated, not pinging due to missing application.downloadsUrl");
						}
					}
				}
				application.s3Versions = data;
			} catch (e){
				systemOutput( "error directory listing versions on s3", true );
				throw( message="cannot read versions from s3 directory", cause=e );
			}
			systemOutput("s3Versions.list [#runId#] FETCHED #numberFormat(getTickCount()-start)#ms, #len(data)# files on s3 found",1,1);
		}
		if ( !structKeyExists( application, "s3Versions" ) ){
			// lock timed out, still use cache if found
			if ( fileExists( cacheDir & cacheFile ) ){
				systemOutput("s3List.versions load from cache (after lock)", true);
				var data = deserializeJSON( fileRead(cacheDir & cacheFile), false );
				application.s3Versions = data;
			} else {
				throw "lock timeout readVersions() no cached found";
			}
		}
		return application.s3Versions;
	}

	// this simply gets one version from the versions list
	public function getLuceeVersionsDetail( version ) {
		if ( !structKeyExists( application, "s3VersionDetail" ) ) {
			application[ "s3VersionDetail" ] = {};
		} else if ( structKeyExists( application.s3VersionDetail, version ) ) {
			return application.s3VersionDetail[ version ];
		}

		var versionInfo = {};
		if ( left( s3Root, 3 ) == "s3:" ) {
			versionInfo = luceeVersionsDetailS3( arguments.version );
		} else {
			versionInfo = getLocalVersionsDetail( arguments.version ); // this is still faster, as it's reading from the local cache
		}
		return application.s3VersionDetail[ version ] = versionInfo;
	}
	
	// fallback handling for local testing with Lucee jar files in the root directory
	public function getJarPath( version ){
		var jarPath = variables.s3Root & "/org/lucee/lucee/#arguments.version#/lucee-#arguments.version#.jar";
		if ( left( s3Root, 3) == "s3:") {
			return jarPath;
		}
		if (!fileExists(jarPath)){
			var dir = getDirectoryFromPath(jarPath);
			if (!directoryExists(dir))
				directoryCreate(dir);
			var tmpJar = getLocalVersionsDetail(version).jar;
			logger ("local_S3: copying jar [#tmpJar#] to [#jarPath#]");
			fileCopy( tmpJar, jarPath );
			reset();
		}
		return jarPath;
	}

	public function getExpressTemplates(){
		if ( !structKeyExists( application, "expressTemplates" ) ) {
			application.expressTemplates = new expressTemplates().getExpressTemplates( s3Root );
		}
		return application.expressTemplates;
	}

	/*
		MARK: Add
	*/
	public function add(required string type, required string version) {
		setting requesttimeout="1000";

		logger("-------- add:#type# --------");
		var data = getLuceeVersionsDetail(version);
		//logger(data);
		var mr=new MavenRepo();

		// move the jar from maven if necessary
		if (isNull(data.jar)) {
			maven2S3(mr,version);
			logger("add: downloaded jar from maven:"&now());
		}
		//var vs=services.VersionUtils::toVersionSortable(version);
		// create the artifact

		try {
			if ( type != "jar" ){
				logger("add: createArtifacts (#type#):"&now());
				new ArtifactBuilder(s3Root).createArtifacts(mr,version,type,true);
				logger("add: artifact created (#type#):"&now());
			}
		} catch(e){
			logger(exception=e, text="add: error creating artifacts for version #version# type #type#", type="error");
		}
	}

	/*
		MARK: Add Missing
	*/
	public function addMissing(includingForgeBox=false, skipMaven=false) {
		setting requesttimeout="1000";
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
		getExpressTemplates();
		// create the missing artifacts
		var builder = new ArtifactBuilder(s3Root);
		loop array=s3List item="local.el" {
			builder.createArtifacts(mr,el.version,"",includingForgeBox);
		}
		systemOutput("build complete, all artifacts created in #numberFormat(getTickCount()-started)#,s",1,1);
		getVersions(true); //force reset();
	}

	public function buildLatest(includingForgeBox=false) {
		var list=getLuceeVersionsListS3( flush=true );
		var latest=list[len(list)].version;
		logger("buildLatest: " & latest);
		var mr=new MavenRepo();
		new ArtifactBuilder(s3Root).createArtifacts(mr,latest,"",includingForgeBox);
	}

	/*
		MARK: Helpers
	*/

	private function logger( string text, any exception, type="info", boolean forceSentry=false ){
		//var log = arguments.text & chr(13) & chr(10) & callstackGet('string');
		if ( !isNull(arguments.exception ) ){

			if (static.DEBUG) {
				if (len(arguments.text)) systemOutput( arguments.text, true, true );
				systemOutput( arguments.exception, true, true );
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
				systemOutput( arguments.text, true, true );
			} else {
				writeLog( text=arguments.text, type=arguments.type, log="application" );
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
	

	private function maven2S3(mr,version) {
		if(left(version,1)<5) return;
		// ignore these versions
		if(listFind("5.0.0.20-SNAPSHOT,5.0.0.255-SNAPSHOT,5.0.0.256-SNAPSHOT,5.0.0.258-SNAPSHOT,5.0.0.259-SNAPSHOT,7.0.0.202",version)) {
			logger( "maven2S3 skipping bad version: #version#" );
			return;
		}

		var trg = variables.s3Root & "/org/lucee/lucee/#version#/lucee-#version#.jar";
		lock name="download from maven-#version#" timeout="1" {
			logger( "downloading from maven-#version#" );
			// add the jar
			var info=mr.get(version, true);
			if(isNull(info.sources.jar.src)) {
				logger("404:"&version);
				return;
			}
			var src=info.sources.jar.src;
			var date=parseDateTime(info.sources.jar.date);

			if (!fileExists(src)) {
				logger("404:"&src);
				return;
			}
			// copy jar from maven to S3
			var dir = getDirectoryFromPath(trg);
			if (!directoryExists(dir))
				directoryCreate(dir);
			if (!fileExists(trg))
				fileCopy(src,trg);

			logger("200:"&trg);
		}
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

	// wrappers to allow using a local dir for testing without s3 access
	private function getLuceeVersionsListS3() {
		// TODO this currently is cached internally by lucee MAX_AGE = 10000ms
		if ( left( s3Root, 3) == "s3:") {
			return luceeVersionsListS3();
		}
		return getLocalVersionsList();
	}

	// used for testing, uses a local directory instead of s3
	private function getLocalVersionsList(){
		var versions = new S3local().listVersions(s3root);
		// systemOutput(serializeJson(var=versions, compact=false), true);
		return versions;
	}

	private function getLocalVersionsDetail( version ){
		var versions = getVersions();
		var _version = arguments.version;
		var detail = arrayFilter(versions, function(item){
			return item.version	== _version;
		});
		//systemOutput(serializeJson(var=detail, compact=false), true);
		if ( arrayLen(detail) eq 0 )
			throw "Version [#arguments.version#] not found";
		return detail[1];
	}

	/* not used
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
		var versions=getVersions(flush); // missing?
		var keys=structKeyArray(versions);
		arraySort(keys,"textnocase");
		return versions[keys[arrayLen(keys)]].version;
	}
	*/

}