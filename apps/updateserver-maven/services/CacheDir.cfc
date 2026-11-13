component {

	/**
	 * Directory for a named on-disk cache that is specific to this app.
	 *
	 * Shared download8 keys (luceeVersionsList.json, extArtifacts_*.json, …)
	 * live in the cache root itself (CACHE_DIRECTORY, default /download).
	 * This app's own files go under a separate prefix so they cannot collide:
	 *
	 *   CACHE_DIR when that env var is set (the image uses /download/provider)
	 *   otherwise LOCAL_CACHE_DIR
	 *   otherwise CACHE_DIRECTORY/provider (or /download/provider)
	 *
	 * When no root is set, the caller-supplied fallback is used, so Pixl8
	 * keeps writing next to the component as before.
	 *
	 * @name      subfolder under the cache root (ignored when no root is set)
	 * @fallback  directory used when no cache root is set, including the trailing slash
	 * @cacheRoot override for tests; defaults to envCacheRoot()
	 */
	public static string function path( required string name, required string fallback, string cacheRoot ) {
		if ( !StructKeyExists( arguments, "cacheRoot" ) ) {
			arguments.cacheRoot = envCacheRoot();
		}

		var root = Trim( arguments.cacheRoot );
		if ( Len( root ) ) {
			if ( Right( root, 1 ) != "/" ) {
				root &= "/";
			}
			root &= arguments.name & "/";
		} else {
			root = arguments.fallback;
			if ( Right( root, 1 ) != "/" ) {
				root &= "/";
			}
		}

		if ( !DirectoryExists( root ) ) {
			DirectoryCreate( root, true );
		}

		return root;
	}

	/**
	 * Preferred root for app-specific caches. See path().
	 *
	 * @cacheDir        override for tests; defaults to CACHE_DIR
	 * @localCacheDir   override for tests; defaults to LOCAL_CACHE_DIR
	 * @cacheDirectory  override for tests; defaults to CACHE_DIRECTORY
	 */
	public static string function envCacheRoot( string cacheDir, string localCacheDir, string cacheDirectory ) {
		if ( !StructKeyExists( arguments, "cacheDir" ) ) {
			arguments.cacheDir = server.system.environment.CACHE_DIR ?: "";
		}
		if ( !StructKeyExists( arguments, "localCacheDir" ) ) {
			arguments.localCacheDir = server.system.environment.LOCAL_CACHE_DIR ?: "";
		}
		if ( !StructKeyExists( arguments, "cacheDirectory" ) ) {
			arguments.cacheDirectory = server.system.environment.CACHE_DIRECTORY ?: "";
		}

		var root = Trim( arguments.cacheDir );
		if ( Len( root ) ) {
			return root;
		}

		root = Trim( arguments.localCacheDir );
		if ( Len( root ) ) {
			return root;
		}

		root = Trim( arguments.cacheDirectory );
		if ( !Len( root ) ) {
			root = "/download";
			// only use the /download default when that folder exists (Cloud Run
			// / local compose). Tests and hosts without the mount fall through.
			if ( !DirectoryExists( root ) ) {
				return "";
			}
		}
		if ( Right( root, 1 ) == "/" ) {
			root = Left( root, Len( root ) - 1 );
		}

		return root & "/provider";
	}

	/**
	 * Write a cache file via a unique temp file and rename, so a shared
	 * CACHE_DIR (several Cloud Run instances on one bucket) is not left with a
	 * half-written file.
	 */
	public static void function writeAtomic( required string path, required any content ) {
		var dir = GetDirectoryFromPath( arguments.path );
		if ( !DirectoryExists( dir ) ) {
			DirectoryCreate( dir, true );
		}

		var tmp = arguments.path & ".tmp." & CreateUniqueId();
		try {
			FileWrite( tmp, arguments.content );
			try {
				FileMove( tmp, arguments.path );
			} catch ( any moveError ) {
				// FileMove will not overwrite an existing file; some filesystems
				// (including GCS FUSE) also refuse a rename over an existing object
				if ( FileExists( arguments.path ) ) {
					FileDelete( arguments.path );
				}
				FileMove( tmp, arguments.path );
			}
		} catch ( any e ) {
			if ( FileExists( tmp ) ) {
				try { FileDelete( tmp ); } catch ( any ignore ) {}
			}
			rethrow;
		}
	}

}
