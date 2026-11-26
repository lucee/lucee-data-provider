/**
 * In-memory cache of the serialised extension listing (/rest/extension/provider/info).
 *
 * An entry is the JSON of one listing, built once and then served as it is: no file read, no parse and no new
 * serialisation per request. An entry is valid as long as the generation of the extension meta it was built from
 * is the current one. When the meta changed, the old entry is still served and rebuilt in a background thread
 * (one per key at a time). A miss is built on the request, concurrent requests for the same key wait for that
 * one build.
 */
component {

	public function init( numeric maxEntries=500, numeric maxBuildSeconds=600 ) {
		variables.entries         = StructNew( "synchronized" ); // key > { json, etag, generation, builtAt }
		variables.maxEntries      = Max( 1, Int( arguments.maxEntries ) );
		variables.maxBuildMs      = Max( 1, arguments.maxBuildSeconds ) * 1000;
		variables.building        = StructNew( "synchronized" ); // key > GetTickCount() of the running background build
		variables.lockId          = "info-listing-cache-" & CreateUUID();

		return this;
	}

	/**
	 * The entry for a key: { json, etag, generation, builtAt }.
	 *
	 * @generation the generation of the meta the listing is built from now, see ExtensionMetadataReader.getMetaGeneration()
	 * @producer   a function without arguments that returns the JSON string of the listing
	 * @force      build it on this request, whatever is cached
	 */
	public struct function get( required string key, required string generation, required any producer, boolean force=false ) {
		if ( !arguments.force ) {
			var entry = variables.entries[ arguments.key ] ?: "";
			if ( IsStruct( entry ) ) {
				if ( entry.generation != arguments.generation ) {
					_buildAsync( arguments.key, arguments.generation, arguments.producer );
				}
				return entry;
			}
		}

		lock name="#variables.lockId#-#Hash( arguments.key )#" type="exclusive" timeout=120 {
			if ( !arguments.force ) {
				// built by the request this one waited for
				var built = variables.entries[ arguments.key ] ?: "";
				if ( IsStruct( built ) ) {
					return built;
				}
			}
			return _build( arguments.key, arguments.generation, arguments.producer );
		}
	}

	public boolean function has( required string key ) {
		return StructKeyExists( variables.entries, arguments.key );
	}

	public numeric function size() {
		return StructCount( variables.entries );
	}

	public boolean function isBuilding( required string key ) {
		var started = Val( variables.building[ arguments.key ] ?: 0 );

		return started > 0 && ( GetTickCount() - started ) <= variables.maxBuildMs;
	}

	public void function clear() {
		StructClear( variables.entries );
	}

	private struct function _build( required string key, required string generation, required any producer ) {
		var json  = arguments.producer();
		var entry = {
			  json       = json
			, etag       = '"' & LCase( Hash( json, "MD5" ) ) & '"'
			, generation = arguments.generation
			, builtAt    = Now()
		};

		if ( !StructKeyExists( variables.entries, arguments.key ) && StructCount( variables.entries ) >= variables.maxEntries ) {
			// bounded: the keys come from request parameters, drop one to make room
			var keys = StructKeyArray( variables.entries );
			if ( ArrayLen( keys ) ) {
				StructDelete( variables.entries, keys[ 1 ] );
			}
		}
		variables.entries[ arguments.key ] = entry;

		return entry;
	}

	private void function _buildAsync( required string key, required string generation, required any producer ) {
		var start = false;

		lock name="#variables.lockId#-async" type="exclusive" timeout=1 throwOnTimeout=false {
			if ( !isBuilding( arguments.key ) ) {
				variables.building[ arguments.key ] = GetTickCount();
				start = true;
			}
		}

		if ( !start ) {
			return;
		}

		thread
			name       = "info-listing-build-" & CreateUUID()
			action     = "run"
			key        = arguments.key
			generation = arguments.generation
			producer   = arguments.producer
		{
			try {
				setting requesttimeout=600;
				_build( attributes.key, attributes.generation, attributes.producer );
			} catch ( any e ) {
				// the old entry is kept and served
				SystemOutput( "Extension listing rebuild failed for [#attributes.key#]: #e.message#", true );
			} finally {
				variables.building[ attributes.key ] = 0;
			}
		}
	}

}
