component {

	variables.EXTENSION_PROVIDER="https://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=all";
	//variables.EXTENSION_PROVIDER="http://127.0.0.1:8889/rest/extension/provider/info?withLogo=true&type=all";

	variables.EXTENSION_DOWNLOAD="https://extension.lucee.org/rest/extension/provider/{type}/{id}";

	variables.UPDATE_PROVIDER = "https://update.lucee.org/rest/update/provider";

	//variables.UPDATE_PROVIDER = "http://127.0.0.1:8889/rest/update/provider";


	function getExtensions(flush=false) localmode=true {
		if ( arguments.flush || isNull( application.extInfo ) ) {
			http url=EXTENSION_PROVIDER&"&flush="&arguments.flush result="http";

			if ( isNull( http.status_code ) || http.status_code != 200 )
				throw "could not connect to extension provider (#EXTENSION_PROVIDER#)";

			var data = deSerializeJson( http.fileContent, false );
			if (!structKeyExists( data, "meta" ) ) {
				systemOutput( "error fetching extensions, falling back on cache", true);
				http url=EXTENSION_PROVIDER result="http";

				if ( isNull( http.status_code ) || http.status_code != 200 )
					throw "could not connect to extension provider (#EXTENSION_PROVIDER#)";

				data = deSerializeJson( http.fileContent, false );
				application.extInfo = data.extensions;
			} else {
				application.extInfo = data.extensions;
			}
		}
		return application.extInfo;
	}

	function extractVersions( qry ) localmode=true {
		// To make a call this function once per extension rather than three times
		var data = {};
		data["release"]=structNew("linked");
		data["abc"]=structNew("linked");
		data["snapshot"]=structNew("linked");

		// first we get the current version
		// if(variables.is(arguments.type,arguments.qry.version)) {
		// 	data[arguments.qry.version]={'filename':arguments.qry.fileName,'date':arguments.qry.created};
		// }

		var _other = arguments.qry.older;
		var _otherName = arguments.qry.olderName;
		var _otherDate = arguments.qry.olderDate;
		var _coreVersion = arguments.qry.coreVersion;

		var arrExt = [];
		loop array=_other index="local.i" item="local.version" {
			arrExt[i] = {
				'version':version,
				'filename':_otherName[i],
				'date':_otherDate[i],
				'minCoreVersion': _coreVersion[i]
			};
		}
		// appends current into other because some current version is not newer.
		arrayAppend(arrExt, {
			'version':arguments.qry.version,
			'filename':arguments.qry.fileName,
			'date':arguments.qry.created,
			'minCoreVersion': arguments.qry.minCoreVersion
		});

		// sorts by version
		arraySort(arrExt, function(e1, e2){
			return compare(toSort(arguments.e2.version), toSort(arguments.e1.version));
		});

		loop array=arrExt index="i" item="local.ext" {
			if (variables.is("release",ext.version)) {
				data["release"][ext.version]={'filename':ext.filename,'date':ext.date, meta: ext};
			} else if (variables.is("abc",ext.version)) {
				data["abc"][ext.version]={'filename':ext.filename,'date':ext.date, meta: ext};
			} else if (variables.is("snapshot",ext.version)) {
				data["snapshot"][ext.version]={'filename':ext.filename,'date':ext.date, meta: ext};
			}
		}
		return data;
	}

	function toSort( required String version) localmode=true {
		var listLength = listLen(arguments.version, "-");
		var arr = [];
		if (listLength == 3)
			arr = listToArray(listDeleteAt(arguments.version, listLength, "-"), ".,-"); // ESAPI extension has 5 parameters
		else
			arr  = listToArray(listFirst(arguments.version, "-"), ".");

		var rtn="";
		loop array=arr index="local.i" item="local.v" {
			if ( len( v ) < 5 )
				rtn &= "." & repeatString( "0", 5-len( v ) ) & v;
			else
				rtn &= "." & v;
		}
		return rtn;
	}

	function is(type, val) {
		if (arguments.type=="all" || arguments.type=="")
			return true;
		if (arguments.type=="snapshot"){
			return findNoCase('-SNAPSHOT', arguments.val);
		} else if (arguments.type=="abc") {
			if (findNoCase('-ALPHA', arguments.val)
				|| findNoCase('-BETA', arguments.val)
				|| findNoCase('-RC', arguments.val)
			) return true;
			return false;
		} else if (arguments.type=="release")  {
			if (!findNoCase('-ALPHA', arguments.val)
				&& !findNoCase('-BETA', arguments.val)
				&& !findNoCase('-RC', arguments.val)
				&& !findNoCase('-SNAPSHOT', arguments.val)
			) return true;
		return false;
		}
	}

	function getVersions(flush) {
		if(!structKeyExists(application,"extVer") || arguments.flush) {
			var flushParam = arguments.flush ? "&flush=true" : "";
			var requestUrl = UPDATE_PROVIDER & "/list/?extended=true" & flushParam;
			//systemOutput("getVersions() fetching fresh data from: " & requestUrl, true);
			http url="#requestUrl#" result="local.res" throwOnError=true;
			var versions = deserializeJson(res.fileContent);
			if ( isStruct(versions) && structKeyExists(versions, "message") ) {
				//systemOutput("download page falling back on cached versions", true);
				http url=listURL&"?extended=true" result="local.res";
				versions = deserializeJson(res.fileContent);
			}
			//var keys = structKeyArray( versions );
			//systemOutput("getVersions() returned " & arrayLen(keys) & " versions, first: " & keys[1] & ", last: " & keys[arrayLen(keys)], true);
			application.extVer = versions;
		} else {
			//systemOutput("getVersions() returning cached data from application.extVer", true);
		}
		return application.extVer;
	}

	function getReleaseDate(version,flush=false) {
		if ( isNull( application.mavenDates ) ) {
			application.mavenDates = {};
		}
		if ( !arguments.flush && _releaseDateCached( arguments.version ) ) {
			return _releaseDateValue( arguments.version );
		}

		var formatted = "";
		try {
			var lastModified = _headJarLastModified( arguments.version );
			if ( Len( lastModified ) ) {
				formatted = LsDateFormat( ParseDateTime( lastModified ) );
			}
		}
		catch ( e ) {
			formatted = "";
		}

		_storeReleaseDate( arguments.version, formatted );
		return formatted;
	}

	// Last-Modified of the jar in the Maven repository, not the update provider date endpoint.
	private string function _headJarLastModified( required string version ) {
		var fileUrl = _jarMavenUrl( arguments.version );
		var timeout = 5;
		var result  = "";

		if ( !IsNull( variables.httpClient ) ) {
			result = variables.httpClient.head( fileUrl, timeout );
		}
		else {
			http url=fileUrl method="head" timeout=timeout redirect=true useragent="lucee-downloads-page" result="local.res" {}
			var headers = local.res.responseHeader ?: {};
			result = {
				  status       = Val( local.res.statusCode ?: 0 )
				, lastModified = headers[ "Last-Modified" ] ?: ( headers[ "last-modified" ] ?: "" )
			};
		}

		var status = Val( result.status ?: 0 );
		if ( status < 200 || status >= 400 ) {
			return "";
		}
		return Trim( result.lastModified ?: "" );
	}

	private string function _jarMavenUrl( required string version ) {
		var base = variables.jarMavenBase ?: "https://maven.lucee-services.com/";
		if ( Right( base, 1 ) != "/" ) {
			base &= "/";
		}
		return base & "org/lucee/lucee/" & arguments.version & "/lucee-" & arguments.version & ".jar";
	}

	private boolean function _isSnapshotVersion( required string version ) {
		return FindNoCase( "-SNAPSHOT", arguments.version ) > 0;
	}

	// tests set these; assignment to download.httpClient does not set variables.httpClient
	public void function setHttpClient( required any httpClient ) {
		variables.httpClient = arguments.httpClient;
	}

	public void function setNowFn( required any nowFn ) {
		variables.nowFn = arguments.nowFn;
	}

	private any function _now() {
		if ( !IsNull( variables.nowFn ) ) {
			return variables.nowFn();
		}
		return Now();
	}

	private boolean function _releaseDateCached( required string version ) {
		if ( IsNull( application.mavenDates ) || !StructKeyExists( application.mavenDates, arguments.version ) ) {
			return false;
		}
		var entry = application.mavenDates[ arguments.version ];
		if ( !IsStruct( entry ) ) {
			return true;
		}
		if ( Val( entry.ttl ?: 0 ) > 0 && DateDiff( "s", entry.time, _now() ) >= entry.ttl ) {
			StructDelete( application.mavenDates, arguments.version );
			return false;
		}
		return true;
	}

	private string function _releaseDateValue( required string version ) {
		var entry = application.mavenDates[ arguments.version ];
		if ( IsStruct( entry ) ) {
			return entry.value ?: "";
		}
		return entry ?: "";
	}

	private void function _storeReleaseDate( required string version, required string value ) {
		var ttl = 300; // failed or header-less HEAD, retry after 5 minutes
		if ( Len( arguments.value ) ) {
			ttl = _isSnapshotVersion( arguments.version ) ? 3600 : 0;
		}
		application.mavenDates[ arguments.version ] = {
			  value = arguments.value
			, time  = _now()
			, ttl   = ttl
		};
	}

	// not currently used
	function getInfo(version,flush=false) {
		if (arguments.flush || isNull(application.mavenInfo[version])) {
			var res="";
			try {
				http url="#UPDATE_PROVIDER#/info/"&version result="local.res";
				var res= deserializeJson(res.fileContent);
				application.mavenInfo[version]= res;
			}
			catch(e) {}
			if (len(res)==0) return "";
		}
		return application.mavenInfo[version]?:"";
	}

	function getChangelog(versionFrom,versionTo,flush=false,detailed=false) {
		var id=arguments.versionFrom & "-" & arguments.versionTo & "-" & detailed;
		if (arguments.flush || isNull(application.jiraChangeLog[ id ])) {
			var restMethod = "changelog";
			if (arguments.detailed)
				restMethod &= "Detailed";
			var changeLogUrl = UPDATE_PROVIDER & "/" & restMethod & "/" & arguments.versionFrom & "/" & arguments.versionTo;
			//systemOutput("getChangelog() fetching fresh data from: " & changeLogUrl & " (id: " & id & ")", true);
			var res="";
			try{
				http url="#changeLogUrl#" result="local.res" throwOnError="true";
				var res= deserializeJson(res.fileContent);
				//if ( isStruct(res) && structCount(res) gt 0 ) {
				//	var versions = structKeyArray( res );
				//	systemOutput("getChangelog() returned data for " & arrayLen(versions) & " version(s), first: " & versions[1] & ", last: " & versions[arrayLen(versions)], true);
				//} else {
				//	systemOutput("getChangelog() returned empty or invalid data", true);
				//}
				application.jiraChangeLog[ id ]= res;
			}catch(e) {
				//systemOutput("getChangelog() HTTP call failed: " & e.message, true);
			}
			if (len(res)==0) return "";
		} else {
			//systemOutput("getChangelog() returning cached data for id: " & id, true);
		}
		return application.jiraChangeLog[ id ]?:"";
	}

	function changelogLastUpdated() {
		var res="dunno";
		try{
			http url="#UPDATE_PROVIDER#/changelogLastUpdated/" result="local.res";
			var res= deserializeJson(res.fileContent);
		}catch(e) {}
		return res;
	}

	function getLatestVersionForType(versions, _type){
		loop struct="#versions#" index="local.vs" item="local.data"{
			if (data.type==_type) return vs;
		}
		return "";
	}

	function reset(){
		lock type="exclusive" timeout=0.1 throwOnTimeout=false name="downloadReset" {
			systemOutput("url.reset=true clearing caches", true);

			var lastUpdated = changelogLastUpdated();
			if ( !structKeyExists(application, "changelogLastUpdated" )
					|| application[ "changelogLastUpdated" ] != lastUpdated ){
				application.jiraChangeLog = {};
				if ( structKeyExists( application, "changeLogReport" ) ){
					// served the old one, until the new one is generated under a lock
					application[ "changeLogReportOld" ] = duplicate( application[ "changeLogReport" ] );
					structDelete( application, "changeLogReport" );
				}
				systemOutput("changeLog changed, rebuilding", true);
			} else {
				systemOutput("changeLog unchanged", true);
			}
			application[ "changelogLastUpdated" ] = lastUpdated;
			// application.mavenInfo = {};  // not currently used
			// dates from a jar HEAD: keep known dates, drop empty ones so they can be retried
			if ( !IsNull( application.mavenDates ) ) {
				loop collection="#application.mavenDates#" key="local.version" value="local.date" {
					var stored = IsStruct( date ) ? ( date.value ?: "" ) : date;
					if ( Len( stored ) eq 0 ) StructDelete( application.mavenDates, version );
				}
			}

		}
	}

}