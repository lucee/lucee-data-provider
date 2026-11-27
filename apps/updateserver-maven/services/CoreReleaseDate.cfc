/**
 * Release date for /rest/update/provider/getdate/{version}.
 *
 * The old path went through MavenRepo.get(), which asked the retired Sonatype
 * search index, then followed up with metadata and checksum requests, retried
 * over http, set no timeouts, and did not cache a miss. An unlisted version
 * such as 6.2.3.34 took around 16-18 seconds and still returned "".
 *
 * This looks the version up in the catalog first (already in memory):
 * - not in the list: 404, no network request
 * - lastModified on the catalog detail: that date
 * - otherwise one HEAD request, with a 5 second timeout
 *
 * Results stay in memory: releases indefinitely, SNAPSHOT versions for an
 * hour, and a listed version that still has no date for 5 minutes.
 */
component {

	function init(
		  any     catalog
		, any     httpClient
		, string  mixedRepo = "https://maven.lucee-services.com/"
		, numeric timeout   = 5
		, any     nowFn
		, struct  cache
	) {
		variables.catalog    = arguments.catalog;
		variables.httpClient = arguments.httpClient ?: _defaultHttpClient();
		variables.mixedRepo  = Right( arguments.mixedRepo, 1 ) == "/" ? arguments.mixedRepo : arguments.mixedRepo & "/";
		variables.timeout    = arguments.timeout;
		variables.nowFn      = arguments.nowFn ?: function() { return Now(); };
		variables.cache      = arguments.cache ?: StructNew( "sync" );
		variables.releaseTtl = 0;      // seconds, 0 = keep forever
		variables.snapshotTtl = 3600;  // 1 hour
		variables.missingTtl  = 300;   // 5 minutes, listed but no date yet

		return this;
	}

	/**
	 * The release date of a listed version, or an empty string when the
	 * version is listed but the date is not known yet. Throws
	 * CoreReleaseDate.NotFound when the version is not in the catalog.
	 */
	public any function get( required string version ) {
		var ver    = Trim( arguments.version );
		var cached = _cached( ver );

		if ( !IsNull( cached ) ) {
			return cached;
		}

		if ( !_isListed( ver ) ) {
			throw( type="CoreReleaseDate.NotFound", message="Version [#ver#] is not in the catalog" );
		}

		var date = _dateFromCatalog( ver );

		if ( !IsDate( date ) ) {
			date = _dateFromHead( ver );
		}

		if ( IsDate( date ) ) {
			_store( ver, date, _isSnapshot( ver ) ? variables.snapshotTtl : variables.releaseTtl );
			return date;
		}

		_store( ver, "", variables.missingTtl );
		return "";
	}

// PRIVATE HELPERS

	private any function _cached( required string version ) {
		var entry = variables.cache[ arguments.version ] ?: "";

		if ( !IsStruct( entry ) ) {
			return;
		}

		if ( Val( entry.ttl ?: 0 ) > 0 && DateDiff( "s", entry.time, variables.nowFn() ) >= entry.ttl ) {
			StructDelete( variables.cache, arguments.version );
			return;
		}

		return entry.date;
	}

	private void function _store( required string version, required any date, required numeric ttl ) {
		variables.cache[ arguments.version ] = {
			  date = arguments.date
			, time = variables.nowFn()
			, ttl  = arguments.ttl
		};
	}

	private boolean function _isListed( required string version ) {
		var list = variables.catalog.getVersionList();

		for ( var entry in list ) {
			if ( IsSimpleValue( entry ) && entry == arguments.version ) {
				return true;
			}
			if ( IsStruct( entry ) && ( entry.version ?: "" ) == arguments.version ) {
				return true;
			}
		}

		return false;
	}

	private any function _dateFromCatalog( required string version ) {
		try {
			var detail = variables.catalog.getVersionDetail( arguments.version );
		} catch ( any e ) {
			return "";
		}

		if ( !IsStruct( detail ) ) {
			return "";
		}

		return _asDate( detail.lastModified ?: "" );
	}

	private any function _dateFromHead( required string version ) {
		var fileUrl = _headUrl( arguments.version );

		if ( !Len( fileUrl ) ) {
			return "";
		}

		try {
			var result = variables.httpClient.head( fileUrl, variables.timeout );
		} catch ( any e ) {
			return "";
		}

		var status = Val( result.status ?: 0 );
		if ( status < 200 || status >= 400 ) {
			return "";
		}

		return _asDate( result.lastModified ?: "" );
	}

	private string function _headUrl( required string version ) {
		try {
			var detail = variables.catalog.getVersionDetail( arguments.version );
			if ( IsStruct( detail ) ) {
				for ( var key in [ "pom", "jar" ] ) {
					if ( Len( detail[ key ] ?: "" ) && IsSimpleValue( detail[ key ] ) && ReFindNoCase( "^https?://", detail[ key ] ) ) {
						return detail[ key ];
					}
				}
			}
		} catch ( any e ) {
			// fall through to the Maven layout
		}

		return variables.mixedRepo & "org/lucee/lucee/" & arguments.version & "/lucee-" & arguments.version & ".pom";
	}

	private any function _asDate( required any value ) {
		if ( IsDate( arguments.value ) ) {
			return arguments.value;
		}
		if ( !IsSimpleValue( arguments.value ) || !Len( Trim( arguments.value ) ) ) {
			return "";
		}
		try {
			return ParseDateTime( arguments.value );
		} catch ( any e ) {
			return "";
		}
	}

	private boolean function _isSnapshot( required string version ) {
		return FindNoCase( "-SNAPSHOT", arguments.version ) > 0;
	}

	private struct function _defaultHttpClient() {
		var userAgent = "lucee-data-provider getdate";

		return {
			head = function( required string fileUrl, required numeric timeout ) {
				http url=arguments.fileUrl method="head" timeout=arguments.timeout redirect=true useragent=userAgent result="local.res" {}
				var headers = local.res.responseHeader ?: {};
				return {
					  status        = Val( local.res.statusCode ?: 0 )
					, error         = local.res.errordetail ?: ""
					, lastModified  = headers[ "Last-Modified" ] ?: ( headers[ "last-modified" ] ?: "" )
				};
			}
		};
	}

}
