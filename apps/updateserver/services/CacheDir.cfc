component {

	/**
	 * Directory for a named on-disk cache.
	 * When CACHE_DIR is set (Cloud Run mounts a bucket at /storage and sets
	 * CACHE_DIR=/storage), files go under CACHE_DIR/<name>/. LOCAL_CACHE_DIR
	 * is a fallback alias used when CACHE_DIR is empty (the Maven only mode
	 * introduced that name). When neither is set, the caller-supplied fallback
	 * is used, so Pixl8 keeps writing next to the component as before.
	 *
	 * @name      subfolder under the cache root (ignored when no root is set)
	 * @fallback  directory used when neither CACHE_DIR nor LOCAL_CACHE_DIR is set, including the trailing slash
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
	 * Preferred cache root: CACHE_DIR, then LOCAL_CACHE_DIR when CACHE_DIR is empty.
	 *
	 * @cacheDir      override for tests; defaults to the CACHE_DIR environment variable
	 * @localCacheDir override for tests; defaults to the LOCAL_CACHE_DIR environment variable
	 */
	public static string function envCacheRoot( string cacheDir, string localCacheDir ) {
		if ( !StructKeyExists( arguments, "cacheDir" ) ) {
			arguments.cacheDir = server.system.environment.CACHE_DIR ?: "";
		}
		if ( !StructKeyExists( arguments, "localCacheDir" ) ) {
			arguments.localCacheDir = server.system.environment.LOCAL_CACHE_DIR ?: "";
		}

		var root = Trim( arguments.cacheDir );
		if ( Len( root ) ) {
			return root;
		}

		return Trim( arguments.localCacheDir );
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
