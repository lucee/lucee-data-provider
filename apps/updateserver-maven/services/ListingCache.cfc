/**
 * JSON listing cache under CACHE_DIR/listings/.
 *
 * Fresh entries (younger than ttlSeconds, default 300 / LISTING_CACHE_SECONDS)
 * are served as-is. Stale entries are still served, and a background thread
 * refreshes them. A miss (or flush=true) is refreshed on the request.
 * Writes are atomic (temp file + move) via CacheDir.writeAtomic.
 * A background refresh that has not finished after maxRefreshSeconds (a thread
 * that died or hangs) no longer blocks the next one, so a key cannot stay stale
 * for good. A producer that throws leaves the cached copy as it is.
 *
 * When a generation is set (Cloud Run K_REVISION, or a per-process boot id),
 * files are stored under listings/{generation}/ so a new revision never
 * serves another revision's JSON. clearLegacyRoot() removes leftover
 * listings/*.json from the pre-generation layout.
 */
component {

	public function init( required string cacheDir, numeric ttlSeconds=300, numeric maxRefreshSeconds=900, string generation="" ) {
		variables.rootDir = arguments.cacheDir;
		if ( Right( variables.rootDir, 1 ) != "/" ) {
			variables.rootDir &= "/";
		}
		var gen = Trim( arguments.generation );
		variables.generation = Len( gen ) ? _safeKey( gen ) : "";
		variables.cacheDir = Len( variables.generation ) ? variables.rootDir & variables.generation & "/" : variables.rootDir;
		if ( !DirectoryExists( variables.cacheDir ) ) {
			DirectoryCreate( variables.cacheDir, true );
		}
		variables.ttlSeconds = Max( 1, Int( Val( arguments.ttlSeconds ) ) );
		variables.maxRefreshMs = Max( 1, Val( arguments.maxRefreshSeconds ) ) * 1000;
		variables.refreshing = {}; // name > GetTickCount() of the start of the running refresh, 0 when none runs

		return this;
	}

	/**
	 * Cloud Run K_REVISION when set, otherwise the existing boot id, otherwise a new boot-{uuid}.
	 * A new process without K_REVISION never reuses another process's listing files.
	 */
	public static string function processGeneration( string revision="", string existing="" ) {
		var rev = Trim( arguments.revision );
		if ( Len( rev ) ) {
			return rev;
		}
		var prev = Trim( arguments.existing );
		if ( Len( prev ) ) {
			return prev;
		}

		return "boot-" & Replace( CreateUUID(), "-", "", "all" );
	}

	/**
	 * Wait until services are ready, then read or rebuild the listing.
	 * Never peek a cached copy first: a previous revision's JSON (or this
	 * revision's still-starting catalog) must not be returned while startup runs.
	 * /healthcheck/ is a separate application and must not call this.
	 */
	public static any function getWhenReady(
		  required any     cache
		, required string  key
		, required any     producer
		, required any     ensureReady
		,          boolean flush = false
	) {
		arguments.ensureReady();

		return arguments.cache.get( arguments.key, arguments.producer, arguments.flush );
	}

	public numeric function getTtlSeconds() {
		return variables.ttlSeconds;
	}

	public string function getCacheDir() {
		return variables.cacheDir;
	}

	public string function getRootDir() {
		return variables.rootDir;
	}

	public string function getGeneration() {
		return variables.generation;
	}

	/**
	 * Remove listings/*.json left by the pre-generation layout. Generation
	 * subdirectories (including this revision and any overlapping old revision)
	 * are left alone so a rolling deploy does not wipe a still-serving revision.
	 * No-op when this cache writes at the root (no generation).
	 */
	public numeric function clearLegacyRoot() {
		if ( !Len( variables.generation ) || !DirectoryExists( variables.rootDir ) ) {
			return 0;
		}

		var removed = 0;
		var names   = [];
		try {
			names = DirectoryList( variables.rootDir, false, "name", "*.json" );
		} catch ( any e ) {
			// only housekeeping, it must never stop the application from starting
			SystemOutput( "Listing cache could not list [#variables.rootDir#]: #e.message#", true );
		}
		for ( var name in names ) {
			var path = variables.rootDir & name;
			if ( !FileExists( path ) ) {
				continue;
			}
			try {
				FileDelete( path );
				removed++;
			} catch ( any e ) {
				SystemOutput( "Listing cache could not remove legacy file [#path#]: #e.message#", true );
			}
		}

		return removed;
	}

	public string function pathFor( required string key ) {
		return variables.cacheDir & _safeKey( arguments.key ) & ".json";
	}

	/**
	 * The cached data for a key, or an empty string when there is no file.
	 * Does not trigger a refresh.
	 */
	public any function peek( required string key ) {
		var entry = _read( arguments.key );

		return IsStruct( entry ) ? entry.data : "";
	}

	public boolean function has( required string key ) {
		return IsStruct( _read( arguments.key ) );
	}

	// is a background refresh of the key running (and not given up on)?
	public boolean function isRefreshing( required string key ) {
		var started = Val( variables.refreshing[ "listing-cache-" & _safeKey( arguments.key ) ] ?: 0 );

		return started > 0 && ( GetTickCount() - started ) <= variables.maxRefreshMs;
	}

	public boolean function isFresh( required string key, date now=Now() ) {
		var entry = _read( arguments.key );

		if ( !IsStruct( entry ) ) {
			return false;
		}

		return DateDiff( "s", entry.cachedAt, arguments.now ) < variables.ttlSeconds;
	}

	/**
	 * Serve a listing: fresh cache, or a stale copy while a background refresh
	 * runs, or a synchronous produce when there is no cache (or flush=true).
	 *
	 * @producer a function with no arguments that returns the value to cache
	 */
	public any function get( required string key, required any producer, boolean flush=false, date now=Now() ) {
		if ( !arguments.flush ) {
			var entry = _read( arguments.key );

			if ( IsStruct( entry ) ) {
				if ( DateDiff( "s", entry.cachedAt, arguments.now ) < variables.ttlSeconds ) {
					return entry.data;
				}

				_refreshAsync( arguments.key, arguments.producer );

				return entry.data;
			}
		}

		return _refreshSync( arguments.key, arguments.producer );
	}

	public any function put( required string key, required any data, date cachedAt=Now() ) {
		var path = pathFor( arguments.key );
		var payload = {
			  cachedAt = DateTimeFormat( arguments.cachedAt, "iso" )
			, data     = arguments.data
		};

		services.CacheDir::writeAtomic( path, SerializeJSON( payload ) );

		return arguments.data;
	}

	private any function _refreshSync( required string key, required any producer ) {
		var data = arguments.producer();

		put( arguments.key, data );

		return data;
	}

	private void function _refreshAsync( required string key, required any producer ) {
		var name = "listing-cache-" & _safeKey( arguments.key );

		var start = false;

		lock name="listing-cache-refresh-#name#" type="exclusive" timeout=1 throwOnTimeout=false {
			var started = Val( variables.refreshing[ name ] ?: 0 );
			if ( started <= 0 || ( GetTickCount() - started ) > variables.maxRefreshMs ) {
				variables.refreshing[ name ] = GetTickCount();
				start = true;
			}
		}

		if ( !start ) {
			return;
		}

		thread
			name     = name & "-" & CreateUUID()
			key      = arguments.key
			producer = arguments.producer
			action   = "run"
		{
			try {
				setting requesttimeout=600;
				_refreshSync( key, producer );
			} catch ( any e ) {
				SystemOutput( "Listing cache refresh failed for [#key#]: #e.message#", true );
			} finally {
				lock name="listing-cache-refresh-listing-cache-#_safeKey( key )#" type="exclusive" timeout=1 throwOnTimeout=false {
					variables.refreshing[ "listing-cache-" & _safeKey( key ) ] = 0;
				}
			}
		}
	}

	private any function _read( required string key ) {
		var path = pathFor( arguments.key );

		if ( !FileExists( path ) ) {
			return "";
		}

		try {
			var parsed = DeserializeJSON( FileRead( path ) );
			if ( !IsStruct( parsed ) || !StructKeyExists( parsed, "data" ) || !StructKeyExists( parsed, "cachedAt" ) ) {
				return "";
			}
			if ( !IsDate( parsed.cachedAt ) ) {
				try {
					parsed.cachedAt = ParseDateTime( parsed.cachedAt );
				} catch ( any ignore ) {
					return "";
				}
			}

			return parsed;
		} catch ( any e ) {
			SystemOutput( "Listing cache [#path#] could not be read: #e.message#", true );

			return "";
		}
	}

	private string function _safeKey( required string key ) {
		var safe = ReReplace( LCase( Trim( arguments.key ) ), "[^a-z0-9._-]+", "-", "all" );
		safe = ReReplace( safe, "-+", "-", "all" );
		safe = ReReplace( safe, "^[-.]+|[-.]+$", "", "all" );

		return Len( safe ) ? Left( safe, 180 ) : "listing";
	}

}
