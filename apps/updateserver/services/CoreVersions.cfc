/**
 * LDEV-6796: the Lucee core versions the update provider offers, and where their files are.
 *
 * - the versions come from the Maven layout first (MavenCoreSource, the maven-metadata.xml of org.lucee:lucee, in
 *   the repositories that are configured), and so do the files, the update provider redirects to them.
 * - the old flat files of S3 (flatSource, services.legacy.S3) are the fallback: with the fallback on (the default) the
 *   versions and files that are only in there are served from there, so nothing old disappears. Every time
 *   that happens it is logged and counted, see getFlatFallbackHits(). With the fallback off the flat files are not used.
 *   Without a Maven source, or when no version could be read from it, the flat files are served even with the fallback off.
 * - the versions that are shown to a calling Lucee are limited to the ones it can load, see filterForCaller().
 */
component accessors=true {

	property name="flatFallback"       type="boolean" default=true;
	property name="flatFallbackHits"   type="struct";
	property name="versionFilter"      type="string"  default="major";
	property name="cacheSeconds"       type="numeric" default=300;

	/**
	 * @flatSource    something with getVersions( flush ), the flat S3 files (services.legacy.S3)
	 * @mavenSource   a MavenCoreSource, empty for none
	 * @flatUrl       the url the flat files are served from (the cdn)
	 * @flatFallback  serve what is not in the Maven layout from the flat files
	 * @versionFilter which versions are shown to a calling Lucee: "major" (the default, the versions of its major), "none" (all of
	 *                them) or rules ( "<caller major>:<allowed major>[-<allowed major>]", comma separated, i.e. "6:6-7,7:7",
	 *                a caller major that has no rule gets its own major).
	 * @cacheSeconds how long the versions of the Maven repositories are kept
	 */
	function init(
		  required any     flatSource
		, any     mavenSource  = ""
		, string  flatUrl      = ""
		, boolean flatFallback = true
		, string  versionFilter = "major"
		, numeric cacheSeconds = 300
	) {
		variables.flatSource     = arguments.flatSource;
		variables.mavenSource    = arguments.mavenSource;
		variables.flatUrl        = Len( arguments.flatUrl ) ? _withTrailingSlash( arguments.flatUrl ) : "";
		variables.flatFallback   = arguments.flatFallback;
		variables.cacheSeconds   = arguments.cacheSeconds;
		variables.flatFallbackHits = {}; // file name > how often it was served from the flat files
		variables.cache          = "";
		variables.sources        = {};
		_parseVersionFilter( arguments.versionFilter );

		return this;
	}

	/**
	 * All the versions, a linked struct sorted by version (services.VersionUtils::toVersionSortable), the same as the one of services.legacy.S3.getVersions()
	 *   { sortable version : { version, <type> : file name, ... } }
	 * the types are jar, light, zero, lco, war and express, and the ones only the flat files have (forgebox, installers).
	 */
	public struct function getVersions( boolean flush=false ) {
		if ( arguments.flush ) {
			variables.cache = "";
		}

		if ( _isFresh() ) {
			return variables.cache.versions;
		}

		var stale = variables.cache;

		lock name="core-versions-refresh" timeout="30" throwOnTimeout="false" {
			if ( !_isFresh() ) {
				try {
					_load();
				} catch ( any e ) {
					if ( !IsStruct( stale ) ) {
						rethrow;
					}

					// the versions of before are better than none, asked again soon
					SystemOutput( "Core versions could not be refreshed, keeping the ones of before: #e.message#", true );
					SystemOutput( e, true );
					variables.cache = stale;
					variables.cache.time = Now();
					variables.cache.ttl  = Min( variables.cacheSeconds, 60 );
				}
			}
		}

		if ( !IsStruct( variables.cache ) ) {
			throw( type="CoreVersions", message="Could not read the core versions" );
		}

		return variables.cache.versions;
	}

	public void function reset() {
		variables.cache = "";
	}

	/**
	 * Where the file of a type (jar, light, zero, lco, war, express, ...) of a version is. Returns
	 *   { url, source="maven"|"flat", present=boolean }
	 * "present" is false for a flat file that is not there (yet), the caller can have it built. An empty struct when
	 * the file is nowhere. The Maven layout is asked first, the flat files are used when that has no file and the fallback is on.
	 * A flat file is logged and counted.
	 */
	public struct function resolveFile( required string type, required string version ) {
		var versions = getVersions();
		var vs       = services.VersionUtils::toVersionSortable( arguments.version );
		var source   = variables.sources[ vs ] ?: { maven=false, repos=[], flatTypes={} };

		if ( source.maven && _hasMaven() && variables.mavenSource.hasType( arguments.type ) ) {
			var mavenUrl = variables.mavenSource.getCoreFileUrl( arguments.type, arguments.version, source.repos );

			if ( Len( mavenUrl ) ) {
				return { url=mavenUrl, source="maven", present=true };
			}
		}

		if ( !_flatAllowed() || !Len( variables.flatUrl ) ) {
			return {};
		}

		var present  = StructKeyExists( source.flatTypes, arguments.type );
		var fileName = present ? source.flatTypes[ arguments.type ] : flatFileName( arguments.type, arguments.version );

		if ( !Len( fileName ) ) {
			return {};
		}

		_logFlatFallback( "file", fileName );

		return { url=variables.flatUrl & fileName, source="flat", present=present };
	}

	/**
	 * The name of the file of a type in the flat files of S3, empty when the type is not known
	 */
	public string function flatFileName( required string type, required string version ) {
		switch ( arguments.type ) {
			case "jar":     return "lucee-" & arguments.version & ".jar";
			case "light":   return "lucee-light-" & arguments.version & ".jar";
			case "zero":    return "lucee-zero-" & arguments.version & ".jar";
			case "lco":     return arguments.version & ".lco";
			case "war":     return "lucee-" & arguments.version & ".war";
			case "express": return "lucee-express-" & arguments.version & ".zip";
		}

		return "";
	}

	/**
	 * The versions a calling Lucee gets to see, a copy of the versions of getVersions() limited to the ones it can load,
	 * see the versionFilter of init().
	 * @caller the version of the calling Lucee, a struct with a major (the result of toVersion() of the update provider), or the version as string
	 */
	public struct function filterForCaller( required struct versions, required any caller ) {
		if ( variables.filterMode == "none" ) {
			return arguments.versions;
		}

		var callerMajor = IsStruct( arguments.caller ) ? Val( arguments.caller.major ) : Val( ListFirst( arguments.caller, "." ) );
		var allowed     = variables.filterRules[ callerMajor ] ?: { min=callerMajor, max=callerMajor };
		var filtered    = StructNew( "linked" );

		for ( var key in arguments.versions ) {
			var major = Val( ListFirst( arguments.versions[ key ].version, "." ) );

			if ( major >= allowed.min && major <= allowed.max ) {
				filtered[ key ] = arguments.versions[ key ];
			}
		}

		return filtered;
	}

	/**
	 * Is the version one the update provider offers: 4 numbers of which the last one can have the appendix SNAPSHOT, BETA, RC or ALPHA,
	 * the same as for the flat files of S3.
	 */
	public boolean function isOffered( required string version ) {
		var arrVersion = ListToArray( arguments.version, "." );

		if ( ArrayLen( arrVersion ) != 4 || !IsNumeric( arrVersion[ 1 ] ) || !IsNumeric( arrVersion[ 2 ] ) || !IsNumeric( arrVersion[ 3 ] ) ) {
			return false;
		}

		// hide 7.0.0.202 stable
		if ( arrVersion[ 1 ] == 7 && arrVersion[ 2 ] == 0 && arrVersion[ 3 ] == 0 && arrVersion[ 4 ] == 202 ) {
			return false;
		}

		var arrPatch = ListToArray( arrVersion[ 4 ], "-" );

		if ( ArrayLen( arrPatch ) > 2 || ArrayLen( arrPatch ) == 0 || !IsNumeric( arrPatch[ 1 ] ) ) {
			return false;
		}

		return ArrayLen( arrPatch ) == 1 || ArrayFind( [ "SNAPSHOT", "BETA", "RC", "ALPHA" ], arrPatch[ 2 ] ) > 0;
	}

// PRIVATE HELPERS

	private boolean function _isFresh() {
		return IsStruct( variables.cache ) && DateDiff( "s", variables.cache.time, Now() ) < variables.cache.ttl;
	}

	private boolean function _hasMaven() {
		return IsObject( variables.mavenSource ) && variables.mavenSource.hasRepos();
	}

	// flat files are used with the fallback on, or when the Maven layout has no versions at all (nothing to serve otherwise)
	private boolean function _flatAllowed() {
		return variables.flatFallback || !( IsStruct( variables.cache ) && variables.cache.mavenCount > 0 );
	}

	/**
	 * Reads the versions of both sources and merges them: the versions of the Maven layout, with the flat ones that are not in there added
	 * (the flat fallback). The result is kept for cacheSeconds, a short time when the Maven layout could not be read.
	 */
	private void function _load() {
		var maven = { versions={}, complete=true };

		if ( _hasMaven() ) {
			try {
				maven = variables.mavenSource.listVersions();
			} catch ( any e ) {
				SystemOutput( "Core versions could not be read from the Maven repositories: #e.message#", true );
				SystemOutput( e, true );
				maven.complete = false;
			}
		}

		var previous = IsStruct( variables.cache ) ? variables.cache : "";

		// the Maven repositories were not readable (or only some of them): what was read before is not lost
		if ( !maven.complete && IsStruct( previous ) && previous.mavenCount > StructCount( maven.versions ) ) {
			for ( var version in previous.mavenVersions ) {
				maven.versions[ version ] = maven.versions[ version ] ?: previous.mavenVersions[ version ];
			}
		}

		var mavenVersions = {};

		for ( var version in maven.versions ) {
			if ( isOffered( version ) ) {
				mavenVersions[ version ] = maven.versions[ version ];
			}
		}

		var useFlat = variables.flatFallback || StructCount( mavenVersions ) == 0;

		if ( !variables.flatFallback && useFlat ) {
			SystemOutput( "Flat S3 fallback is off but the Maven layout has no core versions: serving the flat files", true );
		}

		var flat = {};
		var flatFailed = false;

		if ( useFlat ) {
			try {
				var flatVersions = variables.flatSource.getVersions();

				if ( !IsNull( flatVersions ) ) {
					flat = flatVersions;
				}
			} catch ( any e ) {
				if ( StructCount( mavenVersions ) == 0 ) {
					rethrow;
				}

				SystemOutput( "The flat S3 versions could not be read, serving the ones of the Maven layout: #e.message#", true );
				SystemOutput( e, true );
				flatFailed = true;
			}
		}

		var merged  = {};
		var sources = {};

		for ( var vs in flat ) {
			merged[ vs ] = Duplicate( flat[ vs ] );
			sources[ vs ] = { maven=false, repos=[], flatTypes=_flatTypes( flat[ vs ] ) };
		}

		for ( var version in mavenVersions ) {
			var vs = services.VersionUtils::toVersionSortable( version );

			merged[ vs ] = merged[ vs ] ?: { version=version };
			sources[ vs ] = sources[ vs ] ?: { maven=false, repos=[], flatTypes={} };

			sources[ vs ].maven = true;
			sources[ vs ].repos = mavenVersions[ version ];

			for ( var type in variables.mavenSource.getTypes() ) {
				merged[ vs ][ type ] = merged[ vs ][ type ] ?: flatFileName( type, version );
			}
		}

		var keys = StructKeyArray( merged );
		ArraySort( keys, "textnocase" );

		var sorted = StructNew( "linked" );

		for ( var key in keys ) {
			if ( Len( merged[ key ].version ?: "" ) ) {
				sorted[ key ] = merged[ key ];
			}
		}

		if ( StructCount( sorted ) == 0 ) {
			throw( type="CoreVersions", message="No core versions found, in the Maven layout or in the flat files" );
		}

		var flatOnly = 0;

		for ( var vs in sources ) {
			if ( !sources[ vs ].maven ) {
				flatOnly++;
			}
		}

		SystemOutput( "Core versions loaded: [#StructCount( sorted )#] in total, [#StructCount( mavenVersions )#] in the Maven layout, [#flatOnly#] only in the flat S3 files (flat S3 fallback #variables.flatFallback ? 'on' : 'off'#)", true );

		variables.sources = sources;
		variables.cache   = {
			  versions      = sorted
			, mavenVersions = mavenVersions
			, mavenCount    = StructCount( mavenVersions )
			, time          = Now()
			// a Maven layout that is not (completely) readable is asked again soon
			, ttl           = ( ( maven.complete && StructCount( mavenVersions ) > 0 ) || !_hasMaven() ) && !flatFailed ? variables.cacheSeconds : Min( variables.cacheSeconds, 60 )
		};
	}

	private struct function _flatTypes( required struct entry ) {
		var types = {};

		for ( var key in arguments.entry ) {
			if ( key != "version" && IsSimpleValue( arguments.entry[ key ] ) ) {
				types[ key ] = arguments.entry[ key ];
			}
		}

		return types;
	}

	private void function _logFlatFallback( required string what, required string fileName ) {
		variables.flatFallbackHits[ arguments.fileName ] = ( variables.flatFallbackHits[ arguments.fileName ] ?: 0 ) + 1;
		SystemOutput( "Flat S3 fallback: the #arguments.what# [#arguments.fileName#] is served from the flat files, it is not in the Maven layout.", true );
	}

	private string function _withTrailingSlash( required string path ) {
		return Right( arguments.path, 1 ) == "/" ? arguments.path : arguments.path & "/";
	}

	/**
	 * "major" (or empty): the versions of the major of the caller. "none" (or off, all): all versions. Otherwise rules, comma separated:
	 * <caller major>:<allowed major> or <caller major>:<first allowed major>-<last allowed major>, i.e. "6:6-7,7:7".
	 * A value that is none of those is logged and the default is used.
	 */
	private void function _parseVersionFilter( required string spec ) {
		var value = LCase( Trim( arguments.spec ) );

		variables.filterMode  = "major";
		variables.filterRules = {};
		variables.versionFilter = "major";

		if ( !Len( value ) || value == "major" ) {
			return;
		}

		if ( ArrayFind( [ "none", "off", "all" ], value ) ) {
			variables.filterMode = "none";
			variables.versionFilter = "none";
			return;
		}

		var rules = {};

		for ( var rule in ListToArray( value, "," ) ) {
			var match = ReFind( "^\s*(\d+)\s*:\s*(\d+)\s*(?:-\s*(\d+)\s*)?$", rule, 1, true );

			if ( match.pos[ 1 ] == 0 ) {
				SystemOutput( "The version filter [#arguments.spec#] is not valid, rule [#Trim( rule )#] is not <caller major>:<allowed major>[-<allowed major>]: using the default (major)", true );
				return;
			}

			var low  = Val( Mid( rule, match.pos[ 3 ], match.len[ 3 ] ) );
			var high = match.pos[ 4 ] > 0 ? Val( Mid( rule, match.pos[ 4 ], match.len[ 4 ] ) ) : low;

			if ( high < low ) {
				SystemOutput( "The version filter [#arguments.spec#] is not valid, rule [#Trim( rule )#] ends before it starts: using the default (major)", true );
				return;
			}

			rules[ Val( Mid( rule, match.pos[ 2 ], match.len[ 2 ] ) ) ] = { min=low, max=high };
		}

		variables.filterMode    = "rules";
		variables.filterRules   = rules;
		variables.versionFilter = value;
	}

}
