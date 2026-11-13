component {

	/**
	 * Directory for a named on-disk cache.
	 * When CACHE_DIR is set (Cloud Run mounts a bucket at /storage and sets
	 * CACHE_DIR=/storage), files go under CACHE_DIR/<name>/. When it is not set,
	 * the caller-supplied fallback is used, so Pixl8 keeps writing next to the
	 * component as before.
	 *
	 * @name      subfolder under CACHE_DIR (ignored when CACHE_DIR is empty)
	 * @fallback  directory used when CACHE_DIR is not set, including the trailing slash
	 * @cacheRoot override for tests; defaults to the CACHE_DIR environment variable
	 */
	public static string function path( required string name, required string fallback, string cacheRoot ) {
		if ( !StructKeyExists( arguments, "cacheRoot" ) ) {
			arguments.cacheRoot = Trim( server.system.environment.CACHE_DIR ?: "" );
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
