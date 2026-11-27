/**
 * The release date of a core version, for /rest/update/provider/getdate/{version} (used for the dates on download.lucee.org).
 *
 * Fast and with few requests:
 *   - a version the update provider does not list is not found, without any request
 *   - the date is the "lastModified" of LuceeVersionsDetail() (services.LuceeCatalog, which already caches it), no request
 *     when that is cached
 *   - otherwise one HEAD request (short timeout) to the pom / jar / lco of the version, its Last-Modified header
 * The date of a release never changes and is kept for good, the one of a snapshot (that can be published again) for an hour,
 * a version without a date is asked again after a few minutes. Memory only.
 */
component {

	/**
	 * @coreVersions services.CoreVersions, what the update provider lists
	 * @catalog services.LuceeCatalog, getVersionDetail()
	 * @mixedRepo the Lucee repository, used when LuceeVersionsDetail() has no file URL
	 * @head function( url, timeout ) returning the Last-Modified header (a string, empty when there is none), for the tests
	 */
	function init(
		  required any coreVersions
		, required any catalog
		, string  mixedRepo         = "https://maven.lucee-services.com/"
		, numeric timeout           = 5
		, numeric missSeconds       = 300
		, numeric snapshotSeconds   = 3600
		, any     head
	) {
		variables.coreVersions    = arguments.coreVersions;
		variables.catalog         = arguments.catalog;
		variables.mixedRepo       = Right( arguments.mixedRepo, 1 ) == "/" ? arguments.mixedRepo : arguments.mixedRepo & "/";
		variables.timeout         = arguments.timeout;
		variables.missSeconds     = arguments.missSeconds;
		variables.snapshotSeconds = arguments.snapshotSeconds;
		variables.head            = arguments.head ?: "";
		variables.dates           = StructNew( "synchronized" ); // version > { date, expires (0 = never) }
		return this;
	}

	/**
	 * The release date of the version, an empty string when the version is not known or has no date.
	 */
	public any function get( required string version ) {
		var v = Trim( arguments.version );

		var cached = variables.dates[ v ] ?: {};
		if ( !StructIsEmpty( cached ) && ( cached.expires == 0 || cached.expires > GetTickCount() ) ) {
			return cached.date;
		}

		// not listed (or not a version at all): no request, nothing kept (the check costs nothing)
		var known = _isKnown( v );
		if ( known == "no" ) {
			return "";
		}

		var detail = _detail( v );
		var date   = detail.lastModified ?: "";
		if ( !IsDate( date ) ) {
			date = _fromHead( v, detail );
		}

		if ( IsDate( date ) ) {
			date = ParseDateTime( date );
			variables.dates[ v ] = { date=date, expires=( _isSnapshot( v ) ? GetTickCount() + variables.snapshotSeconds * 1000 : 0 ) };
			return date;
		}

		// listed but no date (a repository not reachable): asked again soon
		if ( known == "yes" ) {
			variables.dates[ v ] = { date="", expires=GetTickCount() + variables.missSeconds * 1000 };
		}
		return "";
	}

	/**
	 * "yes", "no", or "unknown" when the list of the versions cannot be read
	 */
	private string function _isKnown( required string version ) {
		if ( !variables.coreVersions.isOffered( arguments.version ) ) {
			return "no";
		}
		try {
			var versions = variables.coreVersions.getVersions();
		} catch ( any e ) {
			return "unknown";
		}
		loop struct=versions index="local.vs" item="local.entry" {
			if ( ( entry.version ?: "" ) == arguments.version ) {
				return "yes";
			}
		}
		return "no";
	}

	private any function _fromHead( required string version, required struct detail ) {
		var target = "";
		loop array=[ "pom", "jar", "lco" ] item="local.key" {
			var u = arguments.detail[ key ] ?: "";
			if ( IsSimpleValue( u ) && FindNoCase( "http", u ) == 1 ) {
				target = u;
				break;
			}
		}
		// LuceeVersionsDetail() had nothing: the pom in the Maven layout of the Lucee repository
		if ( !Len( target ) ) {
			if ( _isSnapshot( arguments.version ) ) return ""; // a snapshot pom has a timestamp in the name
			target = variables.mixedRepo & "org/lucee/lucee/" & arguments.version & "/lucee-" & arguments.version & ".pom";
		}
		try {
			var lm = IsCustomFunction( variables.head )
				? variables.head( target, variables.timeout )
				: _head( target );
			return IsDate( lm ) ? lm : "";
		} catch ( any e ) {
			SystemOutput( "getdate: HEAD [#target#] failed: #e.message#", true );
			return "";
		}
	}

	private struct function _detail( required string version ) {
		try {
			var detail = variables.catalog.getVersionDetail( arguments.version );
			return IsStruct( detail ) ? detail : {};
		} catch ( any e ) {
			return {};
		}
	}

	private string function _head( required string target ) {
		http method="head" url=arguments.target result="local.rsp" timeout=variables.timeout redirect=true throwOnError=false {
			httpparam type="header" name="User-Agent" value="lucee-update-provider";
		}
		if ( Val( rsp.status_code ?: 0 ) < 200 || Val( rsp.status_code ?: 0 ) >= 300 ) {
			return "";
		}
		return rsp.responseheader[ "Last-Modified" ] ?: "";
	}

	private boolean function _isSnapshot( required string version ) {
		return Right( arguments.version, 9 ) == "-SNAPSHOT";
	}

}
