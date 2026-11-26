/**
 * Conditional requests and cache headers for the REST responses (ETag, If-None-Match, Last-Modified,
 * If-Modified-Since, Cache-Control).
 *
 * The ETags are weak (W/"..."): the response is the same JSON, but Tomcat compresses it on the fly, and it only
 * does that for a response without a strong ETag.
 */
component {

	public static string function weakEtag( required string seed ) {
		return 'W/"' & LCase( Hash( arguments.seed, "MD5" ) ) & '"';
	}

	/**
	 * Does an If-None-Match header match the ETag? Weak comparison (RFC 9110 13.1.2): the W/ prefix is ignored.
	 */
	public static boolean function matchesIfNoneMatch( string header="", required string etag ) {
		var value = Trim( arguments.header );
		if ( !Len( value ) ) {
			return false;
		}
		if ( value == "*" ) {
			return true;
		}

		var wanted = _opaque( arguments.etag );
		for ( var candidate in ListToArray( value, "," ) ) {
			if ( _opaque( candidate ) == wanted ) {
				return true;
			}
		}

		return false;
	}

	/**
	 * Is the response not modified for the request? If-None-Match decides when it is sent, If-Modified-Since only
	 * without it (RFC 9110 13.2.2).
	 */
	public static boolean function isNotModified( string ifNoneMatch="", string ifModifiedSince="", required string etag, any lastModified="" ) {
		if ( Len( Trim( arguments.ifNoneMatch ) ) ) {
			return matchesIfNoneMatch( arguments.ifNoneMatch, arguments.etag );
		}

		var since = Trim( arguments.ifModifiedSince );
		if ( !Len( since ) || !IsDate( arguments.lastModified ) ) {
			return false;
		}

		try {
			var sinceDate = ParseDateTime( since );
		} catch ( any e ) {
			return false;
		}

		// HTTP dates have a resolution of one second
		return DateDiff( "s", sinceDate, arguments.lastModified ) <= 0;
	}

	public static string function httpDate( required date value ) {
		return GetHttpTimeString( arguments.value );
	}

	/**
	 * Seconds a client (or a cache in between) may use a listing before it asks again: INFO_CACHE_SECONDS, default 300.
	 */
	public static numeric function maxAge() {
		var seconds = Val( server.system.environment.INFO_CACHE_SECONDS ?: 300 );

		return seconds >= 0 ? Int( seconds ) : 300;
	}

	public static string function cacheControl() {
		return "public, max-age=" & maxAge();
	}

	private static string function _opaque( required string tag ) {
		var value = Trim( arguments.tag );
		if ( Left( value, 2 ) == "W/" ) {
			value = Mid( value, 3 );
		}

		return Trim( value );
	}

}
