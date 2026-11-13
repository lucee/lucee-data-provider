/**
 * The same on-disk cache as apps/download8 Util.cfc (dlCacheGet / dlCachePut):
 * one JSON file per key in the cache directory, plus an in-memory copy.
 *
 * Directory, in order: CACHE_DIRECTORY (the env var download8 uses), then
 * CACHE_DIR, then /download. Both this service and download8 mount bucket
 * lucee_downloads at /download and must set CACHE_DIRECTORY to that same folder.
 *
 * Shared keys (do not rename): luceeVersionsList, luceeVerDetail_<ver>,
 * extArtifacts_<gid>, extver_<gid>_<aid>, extdata_<gid>_<aid>_<ver>.
 * App-specific caches (REST listings, extension meta, Jira) belong under
 * the provider/ subfolder, see CacheDir, so they cannot collide with these files.
 */
component {

	function init( string cacheDir, struct memory ) {
		variables.cacheDir = arguments.cacheDir ?: "";
		variables.cache    = arguments.memory ?: {};

		return this;
	}

	/**
	 * Shared cache root. override for tests.
	 */
	public string function getCacheDirectory() {
		var dir = Trim( variables.cacheDir );
		if ( !Len( dir ) ) {
			dir = Trim( server.system.environment.CACHE_DIRECTORY ?: "" );
		}
		if ( !Len( dir ) ) {
			dir = Trim( server.system.environment.CACHE_DIR ?: "" );
		}
		if ( !Len( dir ) ) {
			dir = "/download";
		}
		if ( !DirectoryExists( dir ) ) {
			DirectoryCreate( dir, true );
		}
		variables.cacheDir = dir;

		return _withSlash( dir );
	}

	/**
	 * Read a key: memory first, then {dir}/{key}.json. Empty struct on a miss
	 * or a file that cannot be parsed, the same as download8.
	 */
	public struct function dlCacheGet( required string key ) {
		var t = GetTickCount();

		if ( StructKeyExists( variables.cache, arguments.key ) ) {
			SystemOutput( "reading data from memory [#arguments.key#] took #GetTickCount()-t#ms", true );
			return variables.cache[ arguments.key ];
		}

		var file = getCacheDirectory() & arguments.key & ".json";
		if ( FileExists( file ) ) {
			try {
				var val = DeserializeJson( FileRead( file ) );
				if ( !IsStruct( val ) ) {
					return {};
				}
				variables.cache[ arguments.key ] = val;
				SystemOutput( "reading data from file [#file#] took #GetTickCount()-t#ms", true );
				return val;
			} catch ( any e ) {
				SystemOutput( "SharedDownloadCache could not read [#file#]: #e.message#", true );
			}
		}

		return {};
	}

	/**
	 * Write a key to memory and to {dir}/{key}.json. Same lock name pattern as
	 * download8 (dlCachePut_<key>) so two services writing the same file do not
	 * interleave a write (the content is the same data either way).
	 */
	public void function dlCachePut( required string key, required any value ) {
		variables.cache[ arguments.key ] = arguments.value;
		var file = getCacheDirectory() & arguments.key & ".json";
		var json = SerializeJson( arguments.value );

		lock name="dlCachePut_#arguments.key#" type="exclusive" timeout="5" {
			try {
				FileWrite( file, json );
			} catch ( any e ) {
				SystemOutput( "SharedDownloadCache could not write [#file#]: #e.message#", true );
			}
		}
	}

	/**
	 * The same numeric version compare as download8 Util.cfc versionCompare(),
	 * used when writing extver_* so both apps store the same sorted lists.
	 */
	public numeric function versionCompare( required string v1, required string v2 ) {
		var a   = ListToArray( ListFirst( arguments.v1, "-" ), "." );
		var b   = ListToArray( ListFirst( arguments.v2, "-" ), "." );
		var len = Max( ArrayLen( a ), ArrayLen( b ) );

		for ( var i=1; i<=len; i++ ) {
			var n1 = Val( a[ i ] ?: "0" );
			var n2 = Val( b[ i ] ?: "0" );
			if ( n1 > n2 ) return 1;
			if ( n1 < n2 ) return -1;
		}

		return 0;
	}

	private string function _withSlash( required string dir ) {
		return Right( arguments.dir, 1 ) == "/" || Right( arguments.dir, 1 ) == "\" ? arguments.dir : arguments.dir & "/";
	}

}
