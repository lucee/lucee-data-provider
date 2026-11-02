component accessors=true {

	property name="s3root"                type="string" default="";
	// LDEV-6789: extensions published only to the Maven layout (<mavenRoot>/<artifactId>/<version>/<artifactId>-<version>.lex)
	property name="mavenRoot"             type="string" default="";
	property name="mavenCdnUrl"           type="string" default="";
	// LDEV-6789: extensions published to Maven repositories (Central, snapshots, Lucee repository), see MavenExtensionSource
	property name="mavenSource"           type="any";
	property name="fetchThreads"          type="numeric" default=5; // extension files downloaded and read at the same time
	// LDEV-6795: serve the extensions that only exist in the flat S3 bucket (no copy in the Maven layout)? Maven is served first
	// either way. This is the fallback to the old flat files, to be switched off once everything is in the Maven layout.
	property name="flatFallback"          type="boolean" default=true;
	// LDEV-6795: minimum core version needed to load an extension packaged for Maven (no jars folder, see _probePackaging),
	// empty: no such minimum, the min core version of the manifest is all there is
	property name="mavenOnlyMinCore"      type="string" default="";
	// LDEV-6795: how many extension files without a known packaging are read per load, only done when mavenOnlyMinCore is set
	property name="packagingBackfillMax"  type="numeric" default=200;
	property name="extensionMeta"         type="query";
	property name="extensionVersions"     type="struct";
	property name="bundleDownloadService" type="any";

	// LDEV-6789: file name > path relative to mavenRoot, for the files that are not in the flat bucket
	variables._mavenPaths   = {};
	// LDEV-6789: file name > { artifact, version, repos } for the files that are only available from a Maven repository
	variables._mavenRemote  = {};
	// LDEV-6789: what was found out about the maven files, kept in <s3root>/extensions-maven.json so it survives a restart
	//   skipped:     maven files found to be known already (same id and version), not downloaded again
	//   artifactIds: artifact > extension id, so known versions can be skipped without downloading the file
	variables._mavenState        = { skipped={}, artifactIds={} };
	variables._mavenStateLoaded  = false;
	variables._mavenStateChanged = false;
	variables._fetchBatchSize    = 20;
	// LDEV-6795: the extension meta as it is served (flat fallback and effective min core applied), set by loadMeta()
	variables._served            = "";
	// LDEV-6795: file name > number of times it was served from the flat bucket although a Maven source is configured
	variables._flatHits          = StructNew( "sync" );

	reset();

	function reset() {
		variables._simpleCache = StructNew( "max:100" );
	}

	// the settings change what is served, so when the meta is loaded already, what is served is rebuilt
	function setFlatFallback( required boolean flatFallback ) {
		variables.flatFallback = arguments.flatFallback;
		_settingsChanged();
	}

	function setMavenOnlyMinCore( required string mavenOnlyMinCore ) {
		variables.mavenOnlyMinCore = Trim( arguments.mavenOnlyMinCore );
		_settingsChanged();
	}

	/**
	 * LDEV-6795: how often files were served from the flat bucket (fallback) since this reader was created,
	 * by file name. Only counts when a Maven source is configured.
	 */
	public struct function getFlatFallbackHits() {
		return Duplicate( variables._flatHits );
	}

	function loadMeta( query srcMeta ) {
		lock type="exclusive" name="readExtMeta" timeout=0 {
			var meta           = isQuery( arguments.srcMeta ) ? arguments.srcMeta : _readExistingMetaFileFromS3();
			_ensureColumns( meta );
			var existingByFile = _mapExtensionQueryByFilename( meta );
			var lexFiles       = _listLexFilesFromBucket();
			var mavenFiles     = _listMavenLexFiles();
			var remoteFiles    = _listRemoteMavenFiles();
			var metaChanged    = false;
			var timeoutSecs    = 600;
			var rebuild        = meta.recordCount == 0;

			if (meta.recordcount == 0){ 
				// rebuilding the index takes a while as all extensions need to be re-downloaded and processed
				timeoutSecs = Max( 600, ( lexFiles.recordcount + ArrayLen( mavenFiles.files ) + ArrayLen( remoteFiles.files ) ) * 4 ); // was the string "n*4", which can't be cast to a number
				setting requesttimeout=timeoutSecs;
			}

			for( var lexFile in lexFiles ) {
				var isNewToUs = !StructKeyExists( existingByFile, lexFile.name )
				if ( isNewToUs ) {
					_addLexFile( lexFile.name, meta );
					metaChanged = true;
				}
			}

			var knownNames = _namesFromListing( lexFiles );

			// LDEV-6789: extensions are published to Maven only, add what the flat bucket doesn't have
			// the files of the Maven folder of our bucket come first, so they are preferred over the ones of the Maven repositories
			var candidates = _mavenCandidates( mavenFiles.files, remoteFiles.files );

			if ( StructCount( candidates ) ) {
				metaChanged = _addMavenCandidates( meta, candidates, knownNames, timeoutSecs, rebuild ) || metaChanged;
				_setMavenLocations( candidates, mavenFiles.complete, remoteFiles.complete, meta );
				for ( var name in candidates ) {
					knownNames[ name ] = true;
				}
			} else {
				if ( mavenFiles.complete ) {
					variables._mavenPaths = {};
				}
				if ( remoteFiles.complete ) {
					variables._mavenRemote = {};
				}
			}

			// protect from disaster of accidentally not fetching the lex files
			// (and from dropping the maven extensions when the maven sources could not be listed)
			if ( QueryRecordCount( lexFiles ) > 100 && mavenFiles.complete && remoteFiles.complete ) {
				metaChanged = _removeRedundantExtensions( meta, knownNames ) || metaChanged;
			}

			// LDEV-6795: the packaging of the files we don't know it of yet (only needed with a min core version for Maven)
			metaChanged = _backfillPackaging( meta ) || metaChanged;

			if ( metaChanged ) {
				QuerySort( meta, "id,versionSortable", "asc,desc" );
				_writeMetaFileToS3( meta );
			}

			setExtensionMeta( meta );
			_buildServed();
			setExtensionVersions( _createExtensionAndVersionMap() );
			reset();
			_logFallbackSummary( meta );
			return meta;
		}

		variables.extensionMeta ?: _getEmptyExtensionsQuery();
	}

	public function list(
		  required string  type         = "all"
		,          boolean flush        = false
		,          boolean withLogo     = false
		,          boolean all          = false
		,          string  coreVersion  = ""
	) {
		var cacheKey = "list-"
			& ( arguments.withLogo ? "wl" : "nl" )
			& "_" & arguments.type
			& ( arguments.all ? "_all" : "" )
			& "_" & arguments.coreVersion;

		if ( arguments.flush || !StructKeyExists( variables._simpleCache, cacheKey ) ) {
			if ( !IsQuery( variables.extensionMeta ?: "" ) || arguments.flush ) {
				loadMeta();
			}

			var extensions = Duplicate( _getServed() );

			if ( len( arguments.coreVersion ) ) {
				extensions = _filterByCoreVersion( extensions, arguments.coreVersion );
			}

			// LDEV-6789: filter by release type first, so the version an extension is listed with is the newest one of
			// that type (the newest final for "release"), and its older versions are of that type too
			if ( arguments.type != "all" ) {
				_filterByReleaseType( extensions, arguments.type );
			}

			if ( !arguments.all ) {
				extensions = _stripAllButLatestVersions( extensions );
				// After grouping to latest version, sort by name (case-insensitive, and versionSortable desc for tie-breaker)
				QuerySort( extensions, function( row1, row2 ) {
					var nameCompare = compareNoCase( row1.name, row2.name );
					if ( nameCompare != 0 ) return nameCompare;
					// Tie-breaker: sort by versionSortable descending
					if ( row1.versionSortable > row2.versionSortable ) return -1;
					if ( row1.versionSortable < row2.versionSortable ) return 1;
					return 0;
				} );
			}

			if ( !arguments.withLogo ) {
				_stripExtensionLogos( extensions );
			}

			variables._simpleCache[ cacheKey ] = extensions;
		}
		return variables._simpleCache[ cacheKey ];
	}

	/**
	 * The details of an extension. Without a version (or "latest") that is the newest version of the given type
	 * (see list()) that fits the core version, "release" being the newest final. A version that is given
	 * explicitly is returned as it is, whatever its type.
	 */
	public function getExtensionDetail(
		  required string  id
		,          string  version      = "latest"
		,          boolean flush        = false
		,          boolean withLogo     = false
		,          string  coreVersion  = ""
		,          string  type         = "all"
	) {
		if ( !IsQuery( variables.extensionMeta ?: "" ) || arguments.flush ) {
			loadMeta();
		}
		var mapped = getExtensionVersions();

		if ( StructKeyExists( mapped, arguments.id ) ) {
			if ( arguments.version == "latest" || isEmpty( arguments.version ) ) {
				arguments.version = _getLatestVersion( mapped[ arguments.id ], arguments.coreVersion, arguments.type );
			}
			if ( StructKeyExists( mapped[ arguments.id ], arguments.version ) ) {
				var ext = StructCopy( mapped[ arguments.id ][ arguments.version ] );

				// LDEV-6795: a version that is asked for explicitly is not served to a core that can't load it. Without a
				// core version there is nothing to check against, so it is served as it is.
				if ( Len( arguments.coreVersion ) && !_fitsCoreVersion( ext.minCoreVersion, arguments.coreVersion ) ) {
					return {};
				}
				if ( !arguments.withLogo ) {
					ext.image = "";
				}
				_logFlatFallback( ext.filename, "details" );
				return ext;
			}
		}

		return {};
	}

	/**
	 * The url to download an extension file from. Maven first (LDEV-6795): a file that is in the Maven folder of our
	 * bucket (LDEV-6789) is served from the Maven cdn url, a file that is available from a Maven repository from
	 * there, this goes for a flat file too when the Maven layout has the same extension and version. Everything
	 * else is the fallback to the flat bucket, served from the given default (flat extensions cdn) url.
	 */
	public string function getDownloadUrl( required string fileName, required string defaultBaseUrl ) {
		var mavenPath = variables._mavenPaths[ arguments.fileName ] ?: "";

		if ( Len( mavenPath ) && Len( getMavenCdnUrl() ) ) {
			return _withTrailingSlash( getMavenCdnUrl() ) & mavenPath;
		}

		var remote = variables._mavenRemote[ arguments.fileName ] ?: "";

		if ( IsStruct( remote ) ) {
			var resolved = getMavenSource().getFileUrl( remote.artifact, remote.version, remote.repos );

			if ( Len( resolved ) ) {
				return resolved;
			}

			SystemOutput( "Could not resolve the download url of [#arguments.fileName#] in the maven repositories.", true );
		}

		_logFlatFallback( arguments.fileName, "download" );

		return arguments.defaultBaseUrl & arguments.fileName;
	}

	public function getExtensionFileMatchingBundle( required string bundleName, required string bundleVersion ) {
		var exts = _mapExtensionQueryByFilename( getExtensionMeta() );

		if ( arguments.bundleVersion == "latest" ) {
			var allMatches = [];
			for ( var lexFile in exts ) {
				if ( lexFile.startsWith( arguments.bundleName & "-" ) ) {
					return lexFile;
				}
				if ( lexFile.startsWith( Replace( arguments.bundleName, '-', '.', 'all' ) & "-" ) ) {
					return lexFile;
				}
				if ( lexFile.startsWith( Replace( arguments.bundleName, '.', '-', 'all' ) & "-" ) ) {
					return lexFile;
				}
				if ( lexFile.startsWith( Replace( arguments.bundleName, '-', '.', 'all' ) & "." ) ) {
					return lexFile;
				}
			}
			return "";
		}

		var tries = [
		      arguments.bundleName & "-" & arguments.bundleVersion & ".lex"
			, Replace( arguments.bundleName,'.','-','all' ) & "-" & arguments.bundleVersion & ".lex"
			, arguments.bundleName & "-" & Replace( arguments.bundleVersion,'.','-','all') & ".lex"
			, Replace( arguments.bundleName, '.', '-', 'all' ) & "-" & Replace( arguments.bundleVersion,'.','-','all') & ".lex"
			, Replace( arguments.bundleName, '.', '-', 'all' ) & "-" & Replace( arguments.bundleVersion,'-','.','all') & ".lex"
			, Replace( arguments.bundleName, '-', '.', 'all' ) & "-" & Replace( arguments.bundleVersion,'.','-','all') & ".lex"
			, Replace( arguments.bundleName, '-', '.', 'all' ) & "-" & Replace( arguments.bundleVersion,'-','.','all') & ".lex"
			, Replace( arguments.bundleName, '-', '.', 'all' ) & "." & Replace( arguments.bundleVersion,'-','.','all') & ".lex"
		];

		for( var name in tries ) {
			if ( StructKeyExists( exts, name ) ) {
				return name;
			}
		}

		return "";
	}

// PRIVATE HELPERS
	private function _listLexFilesFromBucket() {
		return DirectoryList(
			  path     = getS3Root()
			, sort     = "name"
			, listInfo = "query"
			, filter   = "*.lex"
		);
	}

	/**
	 * LDEV-6789: lists the extension files in the Maven layout, one folder per artifact
	 * <mavenRoot>/<artifactId>-extension/<version>/<artifactId>-extension-<version>.lex
	 * The -lite.lex variants are not extensions in their own right and are ignored.
	 * "complete" is false when part of the layout could not be listed.
	 */
	private struct function _listMavenLexFiles() {
		var result = { files=[], complete=true };
		var root   = getMavenRoot();

		if ( !Len( root ) ) {
			return result;
		}
		root = _withTrailingSlash( root );

		try {
			var artifacts = DirectoryList( path=root, listInfo="query", sort="name", type="dir" );
		} catch( any e ) {
			SystemOutput( "Error listing the maven layout [#root#]: #e.message#", true );
			result.complete = false;
			return result;
		}

		for ( var artifact in artifacts ) {
			if ( !artifact.name.endsWith( "-extension" ) ) {
				continue;
			}

			try {
				var lexFiles = DirectoryList( path=root & artifact.name, recurse=true, listInfo="query", sort="name", filter="*.lex" );
			} catch( any e ) {
				SystemOutput( "Error listing the maven layout for [#artifact.name#]: #e.message#", true );
				result.complete = false;
				continue;
			}

			for ( var lex in lexFiles ) {
				var version = ListLast( lex.directory, "/\" );

				if ( lex.type == "file" && lex.name == artifact.name & "-" & version & ".lex" ) {
					ArrayAppend( result.files, {
						  name     = lex.name
						, path     = artifact.name & "/" & version & "/" & lex.name
						, artifact = artifact.name
						, version  = version
					} );
				}
			}
		}

		return result;
	}

	private function _namesFromListing( lexFiles ) {
		var names = {};

		for ( var i=1; i<=QueryRecordCount( arguments.lexFiles ); i++ ) {
			names[ arguments.lexFiles.name[ i ] ] = true;
		}

		return names;
	}

	/**
	 * LDEV-6789: the extension files of the Maven repositories, the same structs as _listMavenLexFiles() returns
	 * (with repos instead of a path). "complete" is false when part of the repositories could not be listed.
	 */
	private struct function _listRemoteMavenFiles() {
		var result = { files=[], complete=true };

		if ( !IsObject( getMavenSource() ?: "" ) || !getMavenSource().hasRepos() ) {
			return result;
		}

		try {
			result = getMavenSource().listExtensions();
		} catch ( any e ) {
			SystemOutput( "Error listing the maven repositories: #e.message#", true );
			result = { files=[], complete=false };
		}

		return result;
	}

	/**
	 * All the files of the maven sources by file name. A file that is in the Maven folder of our bucket and in
	 * a Maven repository is taken from our bucket.
	 */
	private struct function _mavenCandidates( required array bucketFiles, required array remoteFiles ) {
		var candidates = [:];

		for ( var file in arguments.bucketFiles ) {
			candidates[ file.name ] = { name=file.name, artifact=file.artifact, version=file.version, source="bucket", path=file.path };
		}

		for ( var file in arguments.remoteFiles ) {
			if ( !StructKeyExists( candidates, file.name ) ) {
				candidates[ file.name ] = { name=file.name, artifact=file.artifact, version=file.version, source="repo", repos=file.repos };
			}
		}

		return candidates;
	}

	/**
	 * Remembers where the files of the extension meta can be had from a Maven source (LDEV-6795: Maven first). That is
	 * a file of the meta with the name of a Maven file, and a file with another name (the flat bucket has the older
	 * ones under their old names) of an id and version the Maven sources have.
	 */
	private function _setMavenLocations( candidates, bucketComplete, remoteComplete, meta ) {
		// when part of a source could not be listed, keep what we know already
		var paths  = arguments.bucketComplete ? {} : variables._mavenPaths;
		var remote = arguments.remoteComplete ? {} : variables._mavenRemote;
		var byKey  = {};

		// the id of an artifact is learned when its first file is read, see _addMavenCandidates
		for ( var name in arguments.candidates ) {
			var candidate = arguments.candidates[ name ];
			var id        = variables._mavenState.artifactIds[ candidate.artifact ] ?: "";

			if ( Len( id ) && !StructKeyExists( byKey, id & "|" & candidate.version ) ) {
				byKey[ id & "|" & candidate.version ] = candidate;
			}
		}

		for ( var i=1; i<=QueryRecordCount( arguments.meta ); i++ ) {
			var fileName = arguments.meta.filename[ i ];
			var key      = arguments.meta.id[ i ] & "|" & arguments.meta.version[ i ];
			var found    = arguments.candidates[ fileName ] ?: ( byKey[ key ] ?: "" );

			if ( !IsStruct( found ) ) {
				continue;
			}

			if ( found.source == "bucket" ) {
				paths[ fileName ] = found.path;
			} else {
				remote[ fileName ] = { artifact=found.artifact, version=found.version, repos=found.repos };
			}
		}

		variables._mavenPaths  = paths;
		variables._mavenRemote = remote;
	}

	/**
	 * Adds the files from the maven sources the extension meta doesn't have yet. The Maven sources also hold
	 * older versions (copied over from the flat bucket, partly under a different file name), so a file is
	 * only added when its id and version are not known yet. Files found to be known are remembered (also
	 * after a restart) and not looked at again.
	 *
	 * To not download all the files that are known already, the id of an extension is learned from the newest
	 * file of each artifact first, the older versions of that id are then skipped when known without a download.
	 * The files are downloaded and read in parallel, in batches.
	 */
	private function _addMavenCandidates( meta, candidates, flatNames, timeoutSecs, rebuild ) {
		var changed       = false;
		var knownFiles    = {};
		var knownVersions = {};
		var pending       = [];

		_loadMavenState( arguments.rebuild );

		for ( var i=1; i<=QueryRecordCount( arguments.meta ); i++ ) {
			knownFiles   [ arguments.meta.filename[ i ] ] = true;
			knownVersions[ arguments.meta.id[ i ] & "|" & arguments.meta.version[ i ] ] = true;
		}

		for ( var name in arguments.candidates ) {
			if (    !StructKeyExists( knownFiles, name )
				 && !StructKeyExists( arguments.flatNames, name )
				 && !StructKeyExists( variables._mavenState.skipped, name )
			) {
				ArrayAppend( pending, arguments.candidates[ name ] );
			}
		}

		pending = _skipKnownVersions( pending, knownVersions );

		if ( ArrayLen( pending ) ) {
			setting requesttimeout=Max( arguments.timeoutSecs, ArrayLen( pending ) * 4 );

			// the newest version first, the first of every artifact we don't know the id of yet goes first
			ArraySort( pending, function( a, b ) {
				return Compare( VersionUtils::sortableVersionString( b.version ), VersionUtils::sortableVersionString( a.version ) );
			} );

			var first = [];
			var rest  = [];
			var seen  = {};

			for ( var candidate in pending ) {
				if ( StructKeyExists( variables._mavenState.artifactIds, candidate.artifact ) || StructKeyExists( seen, candidate.artifact ) ) {
					ArrayAppend( rest, candidate );
				} else {
					seen[ candidate.artifact ] = true;
					ArrayAppend( first, candidate );
				}
			}

			changed = _fetchAndAdd( arguments.meta, first, knownVersions );
			rest    = _skipKnownVersions( rest, knownVersions );
			changed = _fetchAndAdd( arguments.meta, rest, knownVersions ) || changed;
		}

		_saveMavenState();

		return changed;
	}

	// drops the files of which the id of the artifact is known and the version is known too
	private array function _skipKnownVersions( required array candidates, required struct knownVersions ) {
		var remaining = [];

		for ( var candidate in arguments.candidates ) {
			var id = variables._mavenState.artifactIds[ candidate.artifact ] ?: "";

			if ( Len( id ) && StructKeyExists( arguments.knownVersions, id & "|" & candidate.version ) ) {
				_skipMavenFile( candidate.name );
			} else {
				ArrayAppend( remaining, candidate );
			}
		}

		return remaining;
	}

	private function _skipMavenFile( required string fileName ) {
		SystemOutput( "Extension file [#arguments.fileName#] has the same id and version as a known extension, ignoring it.", true );
		variables._mavenState.skipped[ arguments.fileName ] = true;
		variables._mavenStateChanged = true;
	}

	// downloads and reads the files in batches, adds them one by one (the extension meta isn't thread safe)
	private function _fetchAndAdd( required query meta, required array candidates, required struct knownVersions ) {
		var changed = false;
		var cols    = ListToArray( arguments.meta.columnList );
		var count   = ArrayLen( arguments.candidates );

		for ( var start=1; start<=count; start+=variables._fetchBatchSize ) {
			var batch   = ArraySlice( arguments.candidates, start, Min( variables._fetchBatchSize, count - start + 1 ) );
			var fetched = StructNew( "sync" );

			ArrayEach( batch, function( candidate, index ) {
				fetched[ arguments.index ] = _fetchLexFile( arguments.candidate, cols );
			}, true, getFetchThreads() );

			for ( var i=1; i<=ArrayLen( batch ); i++ ) {
				var candidate = batch[ i ];
				var result    = fetched[ i ];

				if ( StructKeyExists( result, "error" ) ) {
					// will be tried again with the next refresh
					SystemOutput( "Error processing lex file: [#candidate.name#]: #result.error#", true );
					continue;
				}

				var key = result.extMeta.id & "|" & result.extMeta.version;

				if ( Len( result.extMeta.id ) && ( variables._mavenState.artifactIds[ candidate.artifact ] ?: "" ) != result.extMeta.id ) {
					variables._mavenState.artifactIds[ candidate.artifact ] = result.extMeta.id;
					variables._mavenStateChanged = true;
				}

				if ( StructKeyExists( arguments.knownVersions, key ) ) {
					_skipMavenFile( candidate.name );
					_deleteTmpFile( result.tmpFile );
					continue;
				}

				arguments.knownVersions[ key ] = true;
				_storeLexFile( arguments.meta, candidate.name, result );
				changed = true;
			}
		}

		return changed;
	}

	private function _loadMavenState( required boolean rebuild ) {
		if ( arguments.rebuild ) {
			// the extension meta is built from scratch, so is what we know about the files
			variables._mavenState = { skipped={}, artifactIds={} };
			variables._mavenStateChanged = true;
			variables._mavenStateLoaded  = true;
		} else if ( !variables._mavenStateLoaded ) {
			var stateFile = getS3Root() & "/extensions-maven.json";

			if ( FileExists( stateFile ) ) {
				var state = DeserializeJson( FileRead( stateFile ), false );

				variables._mavenState = { skipped=state.skipped ?: {}, artifactIds=state.artifactIds ?: {} };
			}
			variables._mavenStateLoaded = true;
		}
	}

	private function _saveMavenState() {
		if ( variables._mavenStateChanged ) {
			FileWrite( getS3Root() & "/extensions-maven.json", SerializeJson( variables._mavenState ) );
			variables._mavenStateChanged = false;
		}
	}

	private function _withTrailingSlash( path ) {
		return Right( arguments.path, 1 ) == "/" ? arguments.path : arguments.path & "/";
	}

	// this happens once at startup / init
	private function _readExistingMetaFileFromS3() {
		var metaFile = getS3Root() & "/extensions.json";
		if ( FileExists( metaFile  ) ) {
			var meta = DeserializeJson( FileRead( metaFile ), false );
			return _updateExtensionSorting( meta );
		}
		return _getEmptyExtensionsQuery();
	}

	/* 
		LDEV-5699, LDEV-6089
		Reprocesses all versionSortable values on startup to apply current business rules.
		This ensures legacy data with incorrect sorting is fixed automatically.
	*/ 
	private function _updateExtensionSorting( meta ){
		for ( var i = 1; i <= meta.recordCount; i++ ) {
			if ( len( meta.version[ i ] ) ) {
				meta.versionSortable[ i ] = VersionUtils::sortableVersionString( meta.version[ i ] );
			}
		}
		QuerySort( meta, "id,versionSortable", "asc,desc" );
		return meta;
	}

	private function _writeMetaFileToS3( meta ) {
		var metaFile = getS3Root() & "/extensions.json";

		FileWrite( metaFile, SerializeJson( meta ) );
	}

	private function _getEmptyExtensionsQuery() {
		return QueryNew( "id,version,versionSortable,name,description,filename,image,category,author,created,releaseType,"
			& "minLoaderVersion,minCoreVersion,price,currency,disableFull,trial,older,olderName,"
			& "olderDate,promotionLevel,promotionText,projectUrl,sourceUrl,documentionUrl,packaging" );
	}

	// LDEV-6795: is there a Maven source to serve from? Without one everything is served from the flat bucket.
	private boolean function _hasMavenSource() {
		var source = getMavenSource() ?: "";

		return Len( getMavenRoot() ) > 0 || ( IsObject( source ) && source.hasRepos() );
	}

	// LDEV-6795: is the file served from a Maven source (Maven first), the others are the fallback to the flat bucket
	private boolean function _isMavenServed( required string fileName ) {
		return ( StructKeyExists( variables._mavenPaths, arguments.fileName ) && Len( getMavenCdnUrl() ) > 0 )
			|| StructKeyExists( variables._mavenRemote, arguments.fileName );
	}

	/**
	 * LDEV-6795: the extension meta as it is served, which is not all there is in the meta:
	 * - without the flat fallback only what is served from a Maven source (not when there is no Maven source
	 *   at all, that would leave nothing to serve)
	 * - the min core version of the packaging for Maven applied, so every list, latest and download answer is
	 *   based on the version an extension can be loaded with
	 */
	private function _buildServed() {
		var served   = Duplicate( getExtensionMeta() );
		var dropFlat = !getFlatFallback();

		if ( dropFlat && !_hasMavenSource() ) {
			SystemOutput( "The flat S3 fallback is switched off, but there is no Maven source configured. Ignoring that, the flat files are served.", true );
			dropFlat = false;
		}

		for ( var i=QueryRecordCount( served ); i>=1; i-- ) {
			if ( dropFlat && !_isMavenServed( served.filename[ i ] ) ) {
				QueryDeleteRow( served, i );
			} else {
				served.minCoreVersion[ i ] = _effectiveMinCore( served.minCoreVersion[ i ], served.packaging[ i ] );
			}
		}

		variables._served = served;
	}

	private query function _getServed() {
		if ( !IsQuery( variables._served ) ) {
			_buildServed();
		}

		return variables._served;
	}

	private function _settingsChanged() {
		if ( IsQuery( variables.extensionMeta ?: "" ) ) {
			_buildServed();
			setExtensionVersions( _createExtensionAndVersionMap() );
			reset();
		}
	}

	/**
	 * LDEV-6795: the minimum core version to load an extension, the one of its manifest, or the minimum core version
	 * for Maven packaged extensions (mavenOnlyMinCore) when that is higher and the extension is packaged for Maven.
	 */
	private string function _effectiveMinCore( required string minCore, required string packaging ) {
		var cutoff = getMavenOnlyMinCore();

		if ( !Len( cutoff ) || arguments.packaging != "maven" ) {
			return arguments.minCore;
		}
		if ( !Len( arguments.minCore ) ) {
			return cutoff;
		}

		return Compare( VersionUtils::sortableVersionString( cutoff ), VersionUtils::sortableVersionString( arguments.minCore ) ) > 0
			? cutoff : arguments.minCore;
	}

	// can a core version (of 4 parts) load an extension with the given minimum core version? When in doubt: yes
	private boolean function _fitsCoreVersion( required string minCore, required string coreVersion ) {
		var v = ListToArray( arguments.coreVersion, "." );

		if ( !Len( arguments.minCore ) || ArrayLen( v ) < 4 ) {
			return true;
		}

		return services.versionUtils::checkVersionGTE( arguments.minCore, v[ 1 ], v[ 2 ], v[ 3 ], v[ 4 ] );
	}

	// LDEV-6795: a file that is not served from a Maven source, although there is one, is served by the fallback to the flat bucket
	private function _logFlatFallback( required string fileName, required string what ) {
		if ( !_hasMavenSource() || _isMavenServed( arguments.fileName ) ) {
			return;
		}

		if ( arguments.what == "download" ) {
			variables._flatHits[ arguments.fileName ] = ( variables._flatHits[ arguments.fileName ] ?: 0 ) + 1;
		}

		SystemOutput( "Flat S3 fallback: the #arguments.what# of [#arguments.fileName#] is served from the flat bucket, it is not in the Maven layout.", true );
	}

	private function _logFallbackSummary( required query meta ) {
		if ( !_hasMavenSource() ) {
			return;
		}

		var flatOnly = 0;

		for ( var i=1; i<=QueryRecordCount( arguments.meta ); i++ ) {
			if ( !_isMavenServed( arguments.meta.filename[ i ] ) ) {
				flatOnly++;
			}
		}

		SystemOutput( "Extensions: [#flatOnly#] of [#QueryRecordCount( arguments.meta )#] files are only in the flat S3 bucket, the flat S3 fallback is [#getFlatFallback() ? 'on' : 'off'#]"
			& ( getFlatFallback() ? "." : ", they are not served." ), true );
	}

	private function _mapExtensionQueryByFilename( extensionQuery ) {
		var mapped = [:];

		for( var e in arguments.extensionQuery ) {
			mapped[ e.filename ] = e;
		}

		return mapped;
	}

	/**
	 * adds a file of the flat bucket, returns "added" or "failed"
	 */
	private function _addLexFile( fileName, extensionMetaQuery ) {
		SystemOutput( "Loading new extension file [#arguments.fileName#] from S3.", true );

		var fetched = _fetchLexFile(
			  { name=arguments.fileName, source="flat" }
			, ListToArray( arguments.extensionMetaQuery.columnList )
		);

		if ( StructKeyExists( fetched, "error" ) ) {
			// for now, just to get through them all!
			SystemOutput( "Error processing lex file: [#arguments.fileName#]: #fetched.error#", true );
			return "failed";
		}

		_storeLexFile( arguments.extensionMetaQuery, arguments.fileName, fetched );

		return "added";
	}

	/**
	 * Gets a file (from the flat bucket, the Maven folder of our bucket or a Maven repository) and reads its
	 * manifest and logo. Returns { tmpFile, extMeta } or, when that fails, { error }. Can run in parallel.
	 */
	private struct function _fetchLexFile( required struct candidate, required array cols ) {
		var tmpFile = GetTempFile( GetTempDirectory(), "lexfile", ListLast( arguments.candidate.name, "." ) );

		try {
			_downloadCandidate( arguments.candidate, tmpFile );

			var extMeta   = _initExtensionMetaFromManifest( tmpFile, arguments.cols );
			extMeta.image = _getLogoThumbnail( tmpFile );

			return { tmpFile=tmpFile, extMeta=extMeta };
		} catch ( any e ) {
			_deleteTmpFile( tmpFile );

			return { error=e.message };
		}
	}

	// gets a file of the flat bucket, the Maven folder of our bucket or a Maven repository to the given (temp) file
	private function _downloadCandidate( required struct candidate, required string target ) {
		switch ( arguments.candidate.source ) {
			case "bucket":
				FileCopy( _withTrailingSlash( getMavenRoot() ) & arguments.candidate.path, arguments.target );
			break;
			case "repo":
				getMavenSource().download( arguments.candidate.artifact, arguments.candidate.version, arguments.candidate.repos, arguments.target );
			break;
			default:
				FileCopy( getS3Root() & "/" & arguments.candidate.name, arguments.target );
		}
	}

	// adds a file got by _fetchLexFile() to the extension meta and registers its bundles
	private function _storeLexFile( required query meta, required string fileName, required struct fetched ) {
		var extMeta = arguments.fetched.extMeta;

		extMeta.filename        = arguments.fileName;
		extMeta.versionSortable = Len( extMeta.version ) ? VersionUtils::sortableVersionString( extMeta.version ) : "";
		extMeta.trial           = false; // "TODO"???
		extMeta.releaseType     = Len( extMeta.releaseType ) ? extMeta.releaseType : "all";

		QueryAddRow( arguments.meta, extMeta );

		try {
			_processExtensionJars( arguments.fetched.tmpFile );
		} catch ( any e ) {
			SystemOutput( "Error registering the bundles of lex file: [#arguments.fileName#]: #e.message#", true );
		}

		_deleteTmpFile( arguments.fetched.tmpFile );
	}

	private function _deleteTmpFile( tmpFile ) {
		try {
			FileDelete( arguments.tmpFile );
		} catch( any e ) {
			SystemOutput( e, true );
		}
	}

	private function _readLexManifest( filePath ) {
		try {
			var mf = ManifestRead( arguments.filePath );
		} catch( any e ) {}

		return mf.main ?: {};
	}

	private function _initExtensionMetaFromManifest( lexFile, cols ) {
		var mf             = _readLexManifest( arguments.lexFile );
		var meta           = {};
		var commonMappings = {
			  created          = "Built-Date"
			, minCoreVersion   = "lucee-core-version"
			, minLoaderVersion = "lucee-loader-version"
			, releaseType      = "release-type"
		};

		for( var col in arguments.cols ) {
			meta[ col ] = mf[ col ] ?: "";
		}

		for( var mapping in commonMappings ) {
			if ( !Len( meta[ mapping ] ?: "" ) && Len( mf[ commonMappings[ mapping ] ] ?: "" ) ) {
				meta[ mapping ] = mf[ commonMappings[ mapping ] ]
			}
		}

		if ( StructKeyExists( meta, "packaging" ) ) {
			meta.packaging = _probePackaging( arguments.lexFile, mf );
		}

		return meta;
	}

	/**
	 * LDEV-6795: how an extension file is packaged, "osgi" (the jars of the extension in a jars folder, which any
	 * Lucee can load), "maven" (the jars are Maven artifacts, no jars folder, which only newer Lucee versions can
	 * load) or "unknown". Unknown is treated like osgi, we don't hold back an extension when we are not sure.
	 */
	private string function _probePackaging( required string lexFile, struct manifest={} ) {
		try {
			var zip       = "zip://" & arguments.lexFile & "!";
			var hasJars   = DirectoryExists( zip & "jars/" ) && ArrayLen( DirectoryList( path=zip & "jars/", filter="*.jar" ) ) > 0;
			var hasMaven  = DirectoryExists( zip & "maven/" ) || DirectoryExists( zip & "mvn/" );
			var hasCoords = Len( arguments.manifest.groupId ?: "" ) && Len( arguments.manifest.artifactId ?: "" );

			if ( hasJars ) {
				return "osgi";
			}
			if ( hasMaven || hasCoords ) {
				return "maven";
			}
		} catch ( any e ) {
			SystemOutput( "Could not probe the packaging of [#arguments.lexFile#]: #e.message#", true );
		}

		return "unknown";
	}

	/**
	 * LDEV-6795: the packaging is only needed for the minimum core version of Maven packaged extensions, so
	 * the files in the meta that were added before it was recorded are only read for it when that minimum is set.
	 * Limited to packagingBackfillMax files per load, the rest is done by the next ones. Returns whether the meta changed.
	 */
	private boolean function _backfillPackaging( required query meta ) {
		if ( !Len( getMavenOnlyMinCore() ) ) {
			return false;
		}

		var pending = [];

		for ( var i=1; i<=QueryRecordCount( arguments.meta ) && ArrayLen( pending ) < getPackagingBackfillMax(); i++ ) {
			if ( !Len( arguments.meta.packaging[ i ] ) ) {
				ArrayAppend( pending, i );
			}
		}

		if ( !ArrayLen( pending ) ) {
			return false;
		}

		SystemOutput( "Reading the packaging of [#ArrayLen( pending )#] extension files.", true );
		setting requesttimeout=Max( 600, ArrayLen( pending ) * 4 );

		var found   = StructNew( "sync" );
		var changed = false;

		ArrayEach( pending, function( row ) {
			var candidate = _locateFile( meta.filename[ row ] );
			var tmpFile   = GetTempFile( GetTempDirectory(), "lexfile", "lex" );

			try {
				_downloadCandidate( candidate, tmpFile );
				found[ row ] = _probePackaging( tmpFile, _readLexManifest( tmpFile ) );
			} catch ( any e ) {
				// stays empty, is tried again with the next load
				SystemOutput( "Error probing the packaging of [#meta.filename[ row ]#]: #e.message#", true );
			}

			_deleteTmpFile( tmpFile );
		}, true, getFetchThreads() );

		for ( var row in found ) {
			arguments.meta.packaging[ Val( row ) ] = found[ row ];
			changed = true;
		}

		return changed;
	}

	// where the file of the given name is served from, in the form of the candidates of _mavenCandidates()
	private struct function _locateFile( required string fileName ) {
		if ( StructKeyExists( variables._mavenPaths, arguments.fileName ) ) {
			return { name=arguments.fileName, source="bucket", path=variables._mavenPaths[ arguments.fileName ] };
		}
		if ( StructKeyExists( variables._mavenRemote, arguments.fileName ) ) {
			var remote = Duplicate( variables._mavenRemote[ arguments.fileName ] );

			remote.name   = arguments.fileName;
			remote.source = "repo";

			return remote;
		}

		return { name=arguments.fileName, source="flat" };
	}

	// the extension meta of a state file written before the packaging was recorded has no such column
	private function _ensureColumns( required query meta ) {
		if ( !ListFindNoCase( arguments.meta.columnList, "packaging" ) ) {
			var values = [];

			for ( var i=1; i<=arguments.meta.recordCount; i++ ) {
				ArrayAppend( values, "" );
			}

			QueryAddColumn( arguments.meta, "packaging", "varchar", values );
		}
	}

	private function _getLogoThumbnail( lexFile ){
		var zippedPath = "zip://" & arguments.lexFile & "!/META-INF/logo.png";
		var logoBase64 = "";

		if( FileExists( zippedPath ) ) {
			// reduce colour depth to 8 bit by writing to gif
			var tmpGifThumb = GetTempFile( GetTempDirectory(), "logo", ".gif" );

			ImageWrite( ImageRead( zippedPath ), tmpGifThumb );
			logoBase64 = ToBase64( FileReadBinary( tmpGifThumb ) );

			try {
				FileDelete( tmpGifThumb );
			} catch( e ) {
				SystemOutput( e, true ); // ignore file locking
			}
		}

		return logoBase64;
	}

	private function _createExtensionAndVersionMap() {
		var raw = _getServed();
		var mapped = {};
		for( var extAndVersion in raw ) {
			mapped[ extAndVersion.id ] = mapped[ extAndVersion.id ] ?: [ _latest=extAndVersion.version ];
			mapped[ extAndVersion.id ][ extAndVersion.version ] = extAndVersion;
		}

		return mapped;
	}

	private function _processExtensionJars( lexFile ){
		var lexFileJarsDir = "zip://" & arguments.lexFile & "!jars/";

		if ( DirectoryExists( lexFileJarsDir )) {
			for( var jar in DirectoryList( path=lexFileJarsDir, listInfo="query", filter="*.jar" ) ) {
				if ( jar.type == "file" && jar.size > 0 ) {
					getBundleDownloadService().registerBundleFromExtensionJar( jar.directory, jar.name );
				}
			}
		}
	}

	private function _filterByReleaseType( extensions, type ) {
		for( var i=arguments.extensions.recordcount; i>=1; i-- ) {
			if ( !_matchesReleaseType( arguments.extensions.version[ i ], arguments.type ) ) {
				QueryDeleteRow( arguments.extensions, i );
			}
		}
	}

	/**
	 * Is a version of the given release type? "snapshot": only snapshots, "abc": only alphas, betas and release
	 * candidates, "release": finals only (none of the above), any other type, including "all": every version.
	 */
	private boolean function _matchesReleaseType( required string version, required string type ) {
		switch( arguments.type ) {
			case "snapshot":
				return FindNoCase( '-SNAPSHOT', arguments.version ) > 0;
			case "abc":
				return FindNoCase( '-ALPHA', arguments.version ) > 0
					|| FindNoCase( '-BETA' , arguments.version ) > 0
					|| FindNoCase( '-RC'   , arguments.version ) > 0;
			case "release":
				return FindNoCase( '-ALPHA'   , arguments.version ) == 0
					&& FindNoCase( '-BETA'    , arguments.version ) == 0
					&& FindNoCase( '-RC'      , arguments.version ) == 0
					&& FindNoCase( '-SNAPSHOT', arguments.version ) == 0;
		}

		return true;
	}

	private function _stripExtensionLogos( extensions, type ) {
		for ( var i=QueryRecordCount( arguments.extensions ); i >= 1; i-- ) {
			arguments.extensions.image[ i ] = "";
		}
	}

	private function _stripAllButLatestVersions( extensions ) {
		var last      = "";
		var colList   = QueryColumnList( arguments.extensions );
		var stripped  = QueryNew( colList & ",coreVersion" ); // add extra column for backwards compat
		var older     = [];
		var olderName = [];
		var olderDate = [];
		var coreVersion = [];

		for( var ext in arguments.extensions ) {
			if ( last != ext.id ) {
				var strippedCount = QueryRecordcount( stripped );
				if( strippedCount > 0 ) {
					stripped.older    [ strippedCount ] = older;
					stripped.olderName[ strippedCount ] = olderName;
					stripped.olderDate[ strippedCount ] = olderDate;
					stripped.coreVersion[ strippedCount ] = coreVersion;

					older     = [];
					olderName = [];
					olderDate = [];
					coreVersion = [];
				}

				QueryAddrow( stripped, ext );
			} else if ( Len( ext.version ) ) {
				ArrayAppend( older    ,     ext.version  );
				ArrayAppend( olderName,     ext.filename );
				ArrayAppend( olderDate,     ext.created  );
				ArrayAppend( coreVersion,   ext.minCoreVersion  );
			}

			last=ext.id;
		}

		var strippedCount = QueryRecordcount( stripped );
		if ( strippedCount ) {
			stripped.older    [ strippedCount ] = older;
			stripped.olderName[ strippedCount ] = olderName;
			stripped.olderDate[ strippedCount ] = olderDate;
			stripped.coreVersion[ strippedCount ] = coreVersion;
		}

		return stripped;
	}

	private function _removeRedundantExtensions( cachedExts, knownNames ) {
		var changed = false;

		for( var i=QueryRecordCount( arguments.cachedExts ); i>0; i-- ){
			if ( !StructKeyExists( arguments.knownNames, arguments.cachedExts.filename[ i ] ) ) {
				changed = true;
				SystemOutput( "Deleting [#arguments.cachedExts.filename[ i ]#] extension from cached query as it no longer exists in our lex file lookup.", true );
				QueryDeleteRow( arguments.cachedExts, i );
			}
		}

		return changed;
	}

	private function _filterByCoreVersion( required query extensions, required string coreVersion ) {
		var v = listToArray( arguments.coreVersion, "." );
		var filtered = queryFilter( arguments.extensions, function( row ){
			if ( len( row.minCoreVersion ) == 0 ) return true;
			var _v = v; // avoids scope cascading 4x
			return valid =services.versionUtils::checkVersionGTE( row.minCoreVersion, _v[ 1 ], _v[ 2 ], _v[ 3 ], _v[ 4 ] );
		});
		return filtered;
	}

	/**
	 * The newest version of the extension of the given release type that fits the core version, the versions are
	 * in the order of the extension meta, newest first. An empty string when there is no version of that type.
	 */
	private function _getLatestVersion( extVersions, coreVersion, type="all" ) {
		if ( len( arguments.coreVersion ) == 0 && arguments.type == "all" ) return arguments.extVersions._latest;

		var cv          = listToArray( arguments.coreVersion, "." );
		var typeMatched = false;

		loop collection="#arguments.extVersions#" key="local.k" value="local.v" {
			if (k == "_latest") continue;
			if ( !_matchesReleaseType( k, arguments.type ) ) continue;
			typeMatched = true;
			if ( len( arguments.coreVersion ) == 0 ) return k;
			if ( services.versionUtils::checkVersionGTE( v.minCoreVersion, cv[ 1 ], cv[ 2 ], cv[ 3 ], cv[ 4 ] ) )
				return k;
		}

		if ( typeMatched ) {
			throw "No extension version available for [#arguments.coreVersion#]";
		}

		return "";
	}
}
