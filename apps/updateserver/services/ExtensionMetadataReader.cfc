component accessors=true {

	property name="s3root"                type="string" default="";
	// LDEV-6789: extensions published only to the Maven layout (<mavenRoot>/<artifactId>/<version>/<artifactId>-<version>.lex)
	property name="mavenRoot"             type="string" default="";
	property name="mavenCdnUrl"           type="string" default="";
	property name="extensionMeta"         type="query";
	property name="extensionVersions"     type="struct";
	property name="bundleDownloadService" type="any";

	// LDEV-6789: file name > path relative to mavenRoot, for the files that are not in the flat bucket
	variables._mavenPaths   = {};
	// LDEV-6789: maven files already checked and found to be known (same id and version)
	variables._mavenSkipped = {};

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
			var metaChanged    = false;

			if (meta.recordcount == 0){ 
				// rebuilding the index takes a while as all extensions need to be re-downloaded and processed
				setting requesttimeout=Max( 600, ( lexFiles.recordcount + ArrayLen( mavenFiles.files ) ) * 4 ); // was the string "n*4", which can't be cast to a number
			}

			for( var lexFile in lexFiles ) {
				var isNewToUs = !StructKeyExists( existingByFile, lexFile.name )
				if ( isNewToUs ) {
					_addLexFile( lexFile.name, meta );
					metaChanged = true;
				}
			}

			var knownNames = _namesFromListing( lexFiles );

			// LDEV-6789: extensions are published to the Maven layout only, add what the flat bucket doesn't have
			if ( ArrayLen( mavenFiles.files ) ) {
				metaChanged = _addMavenLexFiles( meta, mavenFiles.files, knownNames ) || metaChanged;
				_setMavenPaths( mavenFiles, knownNames, meta );
				for ( var mavenFile in mavenFiles.files ) {
					knownNames[ mavenFile.name ] = true;
				}
			} else if ( mavenFiles.complete ) {
				variables._mavenPaths = {};
			}

			// protect from disaster of accidentally not fetching the lex files
			// (and from dropping the maven extensions when the maven layout could not be listed)
			if ( QueryRecordCount( lexFiles ) > 100 && mavenFiles.complete ) {
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
	 * The url to download an extension file from. Files that are only available in the Maven layout (LDEV-6789)
	 * are served from the Maven cdn url, everything else from the given default (flat extensions cdn) url.
	 */
	public string function getDownloadUrl( required string fileName, required string defaultBaseUrl ) {
		var mavenPath = variables._mavenPaths[ arguments.fileName ] ?: "";

		if ( Len( mavenPath ) && Len( getMavenCdnUrl() ) ) {
			return _withTrailingSlash( getMavenCdnUrl() ) & mavenPath;
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
						  name = lex.name
						, path = artifact.name & "/" & version & "/" & lex.name
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

	// remembers where the files of the extension meta that only exist in the maven layout are
	private function _setMavenPaths( mavenFiles, flatNames, meta ) {
		// when part of the layout could not be listed, keep what we know already
		var paths = arguments.mavenFiles.complete ? {} : variables._mavenPaths;
		var inMeta = _mapExtensionQueryByFilename( arguments.meta );

		for ( var mavenFile in arguments.mavenFiles.files ) {
			if ( StructKeyExists( inMeta, mavenFile.name ) && !StructKeyExists( arguments.flatNames, mavenFile.name ) ) {
				paths[ mavenFile.name ] = mavenFile.path;
			}
		}

		variables._mavenPaths = paths;
	}

	/**
	 * Adds the files from the Maven layout the extension meta doesn't have yet. The Maven layout also holds
	 * older versions (copied over from the flat bucket, partly under a different file name), so a file is
	 * only added when its id and version are not known yet. Files found to be known are not looked at again
	 * until the next restart.
	 */
	private function _addMavenLexFiles( meta, mavenFiles, flatNames ) {
		var changed       = false;
		var knownFiles    = {};
		var knownVersions = {};

		for ( var i=1; i<=QueryRecordCount( arguments.meta ); i++ ) {
			knownFiles   [ arguments.meta.filename[ i ] ] = true;
			knownVersions[ arguments.meta.id[ i ] & "|" & arguments.meta.version[ i ] ] = true;
		}

		for ( var mavenFile in arguments.mavenFiles ) {
			if (    StructKeyExists( knownFiles, mavenFile.name )
				 || StructKeyExists( arguments.flatNames, mavenFile.name )
				 || StructKeyExists( variables._mavenSkipped, mavenFile.name )
			) {
				continue;
			}

			var result = _addLexFile(
				  fileName           = mavenFile.name
				, extensionMetaQuery = arguments.meta
				, remoteFile         = _withTrailingSlash( getMavenRoot() ) & mavenFile.path
				, knownVersions      = knownVersions
			);

			if ( result == "added" ) {
				changed = true;
			} else if ( result == "known" ) {
				variables._mavenSkipped[ mavenFile.name ] = true;
			}
		}

		return changed;
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
	 * returns "added", "failed" or, when knownVersions is passed and the id and version of the file are
	 * in there already, "known" (the file is not added)
	 */
	private function _addLexFile( fileName, extensionMetaQuery, remoteFile="", struct knownVersions ) {
		SystemOutput( "Loading new extension file [#arguments.fileName#] from S3.", true );

		try {
			var tmpFile  = _copyRemoteFileToTmpFile( arguments.fileName, arguments.remoteFile );
			var qryCols  = ListToArray( arguments.extensionMetaQuery.columnList );
			var extMeta  = _initExtensionMetaFromManifest( tmpFile, qryCols );

			if ( StructKeyExists( arguments, "knownVersions" ) ) {
				if ( StructKeyExists( arguments.knownVersions, extMeta.id & "|" & extMeta.version ) ) {
					SystemOutput( "Extension file [#arguments.fileName#] has the same id and version as a known extension, ignoring it.", true );
					_deleteTmpFile( tmpFile );
					return "known";
				}
				arguments.knownVersions[ extMeta.id & "|" & extMeta.version ] = true;
			}

			extMeta.filename        = arguments.fileName;
			extMeta.versionSortable = Len( extMeta.version ) ? VersionUtils::sortableVersionString( extMeta.version ) : "";
			extMeta.trial           = false; // "TODO"???
			extMeta.releaseType     = Len( extMeta.releaseType ) ? extMeta.releaseType : "all";
			extMeta.image           = _getLogoThumbnail( tmpFile );

			QueryAddRow( arguments.extensionMetaQuery, extMeta );

			_processExtensionJars( tmpFile );
			_deleteTmpFile( tmpFile );

			return "added";
		} catch( any e ) {
			// for now, just to get through them all!
			SystemOutput( "Error processing lex file: [#arguments.fileName#]: #e.message#", true );
		}

		return "failed";
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

	private function _copyRemoteFileToTmpFile( fileName, remoteFile="" ) {
		var source  = Len( arguments.remoteFile ) ? arguments.remoteFile : getS3Root() & "/" & arguments.fileName;
		var tmpFile = GetTempFile( GetTempDirectory(), "lexfile", Listlast( arguments.fileName, "." ) );
		FileCopy( source, tmpFile );
		return tmpFile;
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
