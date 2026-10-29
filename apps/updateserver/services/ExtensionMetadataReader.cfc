component accessors=true {

	property name="s3root"                type="string" default="";
	// LDEV-6789: extensions published only to the Maven layout (<mavenRoot>/<artifactId>/<version>/<artifactId>-<version>.lex)
	property name="mavenRoot"             type="string" default="";
	property name="mavenCdnUrl"           type="string" default="";
	// LDEV-6789: extensions published to Maven repositories (Central, snapshots, Lucee repository), see MavenExtensionSource
	property name="mavenSource"           type="any";
	property name="fetchThreads"          type="numeric" default=5; // extension files downloaded and read at the same time
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

	reset();

	function reset() {
		variables._simpleCache = StructNew( "max:100" );
	}

	function loadMeta( query srcMeta ) {
		lock type="exclusive" name="readExtMeta" timeout=0 {
			var meta           = isQuery( arguments.srcMeta ) ? arguments.srcMeta : _readExistingMetaFileFromS3();
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
				_setMavenLocations( candidates, mavenFiles.complete, remoteFiles.complete, knownNames, meta );
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

			if ( metaChanged ) {
				QuerySort( meta, "id,versionSortable", "asc,desc" );
				_writeMetaFileToS3( meta );
			}

			setExtensionMeta( meta );
			setExtensionVersions( _createExtensionAndVersionMap() );
			reset();
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

			var extensions = Duplicate( getExtensionMeta() );

			if ( len( arguments.coreVersion ) ) {
				extensions = _filterByCoreVersion( extensions, arguments.coreVersion );
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

			if ( arguments.type != "all" ) {
				_filterByReleaseType( extensions, arguments.type );
			}

			if ( !arguments.withLogo ) {
				_stripExtensionLogos( extensions );
			}

			variables._simpleCache[ cacheKey ] = extensions;
		}
		return variables._simpleCache[ cacheKey ];
	}

	public function getExtensionDetail(
		  required string  id
		,          string  version      = "latest"
		,          boolean flush        = false
		,          boolean withLogo     = false
		,          string  coreVersion  = coreVersion
	) {
		if ( !IsQuery( variables.extensionMeta ?: "" ) || arguments.flush ) {
			loadMeta();
		}
		var mapped = getExtensionVersions();

		if ( StructKeyExists( mapped, arguments.id ) ) {
			if ( arguments.version == "latest" || isEmpty( arguments.version ) ) {
				arguments.version = _getLatestversion( mapped[ arguments.id ], arguments.coreVersion );
			}
			if ( StructKeyExists( mapped[ arguments.id ], arguments.version ) ) {
				var ext = StructCopy( mapped[ arguments.id ][ arguments.version ] );
				if ( !arguments.withLogo ) {
					ext.image = "";
				}
				return ext;
			}
		}

		return {};
	}

	/**
	 * The url to download an extension file from. Files that are only available in the Maven folder of our bucket
	 * (LDEV-6789) are served from the Maven cdn url, files only available from a Maven repository from there,
	 * everything else from the given default (flat extensions cdn) url.
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

	// remembers where the files of the extension meta that only exist in the maven sources are
	private function _setMavenLocations( candidates, bucketComplete, remoteComplete, flatNames, meta ) {
		// when part of a source could not be listed, keep what we know already
		var paths  = arguments.bucketComplete ? {} : variables._mavenPaths;
		var remote = arguments.remoteComplete ? {} : variables._mavenRemote;
		var inMeta = _mapExtensionQueryByFilename( arguments.meta );

		for ( var name in arguments.candidates ) {
			var candidate = arguments.candidates[ name ];

			if ( !StructKeyExists( inMeta, name ) || StructKeyExists( arguments.flatNames, name ) ) {
				continue;
			}

			if ( candidate.source == "bucket" ) {
				paths[ name ] = candidate.path;
			} else {
				remote[ name ] = { artifact=candidate.artifact, version=candidate.version, repos=candidate.repos };
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
			& "olderDate,promotionLevel,promotionText,projectUrl,sourceUrl,documentionUrl" );
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
			switch ( arguments.candidate.source ) {
				case "bucket":
					FileCopy( _withTrailingSlash( getMavenRoot() ) & arguments.candidate.path, tmpFile );
				break;
				case "repo":
					getMavenSource().download( arguments.candidate.artifact, arguments.candidate.version, arguments.candidate.repos, tmpFile );
				break;
				default:
					FileCopy( getS3Root() & "/" & arguments.candidate.name, tmpFile );
			}

			var extMeta   = _initExtensionMetaFromManifest( tmpFile, arguments.cols );
			extMeta.image = _getLogoThumbnail( tmpFile );

			return { tmpFile=tmpFile, extMeta=extMeta };
		} catch ( any e ) {
			_deleteTmpFile( tmpFile );

			return { error=e.message };
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

		return meta;
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
		var raw = getExtensionMeta();
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
			switch( arguments.type ) {
				case "snapshot":
					if( !FindNoCase( '-SNAPSHOT', arguments.extensions.version[ i ] ) ) {
						QueryDeleteRow( arguments.extensions, i );
					}
				break;
				case "abc":
					if(    !FindNoCase( '-ALPHA', arguments.extensions.version[ i ] )
						&& !FindNoCase( '-BETA' , arguments.extensions.version[ i ] )
						&& !FindNoCase( '-RC'   , arguments.extensions.version[ i ] )
					) {
						QueryDeleteRow( arguments.extensions, i );
					}
				break;
				case "release":
					if(    FindNoCase( '-ALPHA'   , arguments.extensions.version[ i ] )
						|| FindNoCase( '-BETA'    , arguments.extensions.version[ i ] )
						|| FindNoCase( '-RC'      , arguments.extensions.version[ i ] )
						|| FindNoCase( '-SNAPSHOT', arguments.extensions.version[ i ] )
					) {
						QueryDeleteRow( arguments.extensions, i );
					}
				break;
			}
		}
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

	private function _getLatestVersion( extVersions, coreVersion ) {
		if ( len( arguments.coreVersion ) == 0 ) return arguments.extVersions._latest;
		var cv = listToArray( arguments.coreVersion, "." );
		loop collection="#arguments.extVersions#" key="local.k" value="local.v" {
			if (k == "_latest") continue;
			if ( services.versionUtils::checkVersionGTE( v.minCoreVersion, cv[ 1 ], cv[ 2 ], cv[ 3 ], cv[ 4 ] ) )
				return k;
		}
		throw "No extension version available for [#arguments.coreVersion#]";
	};
}
