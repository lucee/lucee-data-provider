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
			try {
				DirectoryCreate( root, true );
			} catch ( any e ) {
				// a storage error here must not stop the services from loading: a
				// read from the folder is then a cache miss and a write is skipped
				SystemOutput( "Cache folder [#root#] could not be created: #e.message#", true );
			}
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
	 * Read a cache file. A file that cannot be read (for example "Stale file
	 * handle" when another instance replaced the object on the shared Cloud
	 * Storage FUSE mount while it was open) is read again, each time with a
	 * fresh open, after 100, 400 and 1000 ms. When it still fails:
	 *   - with mirror=true, the last good copy this instance read or wrote is
	 *     used (a local file under the temp directory, see mirrorPath())
	 *   - otherwise it is a cache miss: an empty string is returned and the
	 *     caller rebuilds the data
	 * A missing file is a cache miss right away. The normal path does the same
	 * work as FileExists() + FileRead(), plus a local copy when mirror=true.
	 *
	 * @mirror keep / use a local copy of the last good content
	 * @reader for tests: a function( path ) used instead of FileRead()
	 */
	public static string function readText( required string path, boolean mirror=false, any reader ) {
		var delays    = [ 100, 400, 1000 ];
		var lastError = "";

		for ( var attempt = 1; attempt <= ArrayLen( delays ) + 1; attempt++ ) {
			try {
				if ( !FileExists( arguments.path ) ) {
					return "";
				}
				var content = IsNull( arguments.reader ) ? FileRead( arguments.path ) : arguments.reader( arguments.path );
				if ( arguments.mirror ) {
					writeMirror( arguments.path, content );
				}
				return content;
			} catch ( any e ) {
				lastError = e.message;
				if ( attempt <= ArrayLen( delays ) ) {
					sleep( delays[ attempt ] );
				}
			}
		}

		if ( arguments.mirror ) {
			var localCopy = mirrorPath( arguments.path );
			try {
				if ( FileExists( localCopy ) ) {
					SystemOutput( "Cache file [#arguments.path#] could not be read (#lastError#), the local copy is used", true );
					return FileRead( localCopy );
				}
			} catch ( any ignore ) {}
		}

		SystemOutput( "Cache file [#arguments.path#] could not be read, treated as a cache miss: #lastError#", true );
		return "";
	}

	/**
	 * Local copy (in the container, not on the shared mount) of a cache file.
	 */
	public static string function mirrorPath( required string path ) {
		return GetTempDirectory() & "lucee-provider-mirror/" & LCase( Hash( arguments.path, "MD5" ) ) & "-" & GetFileFromPath( arguments.path );
	}

	/**
	 * Keep the last good content of a cache file locally. Never throws.
	 */
	public static void function writeMirror( required string path, required any content ) {
		try {
			writeAtomic( mirrorPath( arguments.path ), arguments.content );
		} catch ( any e ) {
			SystemOutput( "Local copy of [#arguments.path#] could not be written: #e.message#", true );
		}
	}

	/**
	 * Write a cache file via a unique temp file and rename, so a shared
	 * CACHE_DIR (several Cloud Run instances on one bucket) is not left with a
	 * half-written file.
	 */
	public static void function writeAtomic( required string path, required any content, boolean mirror=false ) {
		if ( arguments.mirror ) {
			// the local copy first, so it is there even when the shared write fails
			writeMirror( arguments.path, arguments.content );
		}

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
