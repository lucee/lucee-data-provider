/**
 * JSON listing cache under CACHE_DIR/listings/.
 *
 * Fresh entries (younger than ttlSeconds, default 300 / LISTING_CACHE_SECONDS)
 * are served as-is. Stale entries are still served, and a background thread
 * refreshes them. A miss (or flush=true) is refreshed on the request.
 * Writes are atomic (temp file + move) via CacheDir.writeAtomic.
 */
component {

	public function init( required string cacheDir, numeric ttlSeconds=300 ) {
		variables.cacheDir = arguments.cacheDir;
		if ( Right( variables.cacheDir, 1 ) != "/" ) {
			variables.cacheDir &= "/";
		}
		if ( !DirectoryExists( variables.cacheDir ) ) {
			DirectoryCreate( variables.cacheDir, true );
		}
		variables.ttlSeconds = Max( 1, Int( Val( arguments.ttlSeconds ) ) );
		variables.refreshing = {};

		return this;
	}

	public numeric function getTtlSeconds() {
		return variables.ttlSeconds;
	}

	public string function getCacheDir() {
		return variables.cacheDir;
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

		lock name="listing-cache-refresh-#name#" type="exclusive" timeout=1 throwOnTimeout=false {
			if ( StructKeyExists( variables.refreshing, name ) && variables.refreshing[ name ] ) {
				return;
			}
			variables.refreshing[ name ] = true;
		}

		thread
			name     = name
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
					variables.refreshing[ "listing-cache-" & _safeKey( key ) ] = false;
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
