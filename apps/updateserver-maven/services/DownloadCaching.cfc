/**
 * Cache-Control of the extension download answers (/full/{id}, /trial/{id}).
 *
 * - a redirect to the file of an explicitly given version: that file never changes, DOWNLOAD_CACHE_SECONDS
 *   (default 86400)
 * - a redirect without a version (latest of a type): the target changes with the next release,
 *   LATEST_CACHE_SECONDS (default 300)
 * - not found: NOT_FOUND_CACHE_SECONDS (default 300), the time a miss is remembered on the server as well
 */
component {

	public static string function forRedirect( string version="" ) {
		var v = Trim( arguments.version );
		var pinned = Len( v ) && v != "latest";

		return "public, max-age=" & ( pinned ? _seconds( "DOWNLOAD_CACHE_SECONDS", 86400 ) : _seconds( "LATEST_CACHE_SECONDS", 300 ) );
	}

	public static string function forNotFound() {
		return "public, max-age=" & _seconds( "NOT_FOUND_CACHE_SECONDS", 300 );
	}

	private static numeric function _seconds( required string name, required numeric fallback ) {
		var env = server.system.environment;
		if ( !StructKeyExists( env, arguments.name ) || !IsNumeric( env[ arguments.name ] ) || env[ arguments.name ] < 0 ) {
			return arguments.fallback;
		}

		return Int( env[ arguments.name ] );
	}

}
