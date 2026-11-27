/**
 * A service to encapsulate the manied logic
 * of bundle discovery for bundle download
 */
component accessors=true {

	property name="extensionsCdnUrl"    type="string" default="";
	property name="bundleS3Root"        type="string" default="";
	property name="bundleCdnUrl"        type="string" default="";
	property name="extensionMetaReader" type="any";
	property name="mavenMatcher"        type="any";
	// GcsBundleCache: the jars extracted from extension .lex files, <prefix><Bundle-SymbolicName>-<Bundle-Version>.jar
	property name="bundleCache"         type="any";
	// look for a bundle that is on no Maven repository inside the extension .lex files (needs the bundleCache)
	property name="lexFallback"         type="boolean" default=true;
	property name="lexMaxBytes"         type="numeric" default=104857600;
	property name="lexTimeout"          type="numeric" default=60;

	variables._lookupCache = {};
	// the .lex files this instance has unpacked into the bundle cache: url > true
	variables._lexDone     = {};

	/**
	 * Attempt to locate an osgi bundle file
	 * by looking up various locations
	 */
	public struct function findBundle( required string bundleName, required string bundleVersion, string searchName=arguments.bundleName ) {
		// Get it from cache (eventually everything will end up here)
		var bundleInfo = _cacheLookup( argumentCollection=arguments );

		if ( StructCount( bundleInfo ) ) {
			return bundleInfo;
		}

		// Get it from bundles s3 bucket directly (not in the Maven only mode, there is no bucket)
		var bundleUrl = _hasBucket() ? _searchBundleBucket( argumentCollection=arguments, bundleName=arguments.searchName ) : "";
		if ( Len( Trim( bundleUrl ) ) ) {
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
		}


		// Simple maven match
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, bundleName=arguments.searchName );
		if ( Len( Trim( bundleUrl ) ) && !_isLex( bundleUrl ) ) {
			var cacheExpiry = arguments.bundleVersion == "latest" ? DateAdd( 'h', 1, Now() ) : "never";

			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires=cacheExpiry );
		}

		// Fuller maven search (jars only). A jar that is published as org.lucee:<Bundle-SymbolicName>:<Bundle-Version>
		// (the "Upload Maven jar" workflow of lucee/Lucee) is found on maven.lucee-services.com. A jar that is only
		// inside an extension .lex is found by the .lex fallback below (bundle cache).
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, bundleName=arguments.searchName, rawSearch=true );
		if ( Len( Trim( bundleUrl ) ) && !_isLex( bundleUrl ) ) {
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires=( arguments.bundleVersion == "latest" ? DateAdd( 'h', 1, Now() ) : "never" ) );
		}

		// If we haven't already, try replacing - and .
		// e.g. "org-my-package" > "org.my.package" and vice versa
		if ( arguments.searchName == arguments.bundleName ) {
			var newSearchName = "";

			if ( arguments.bundleName contains "-" ) {
				newSearchName = Replace( arguments.bundleName, "-", ".", "all" );
			} else if ( arguments.bundleName contains "." ) {
				newSearchName = Replace( arguments.bundleName, ".", "-", "all" );
			}

			if ( Len( newSearchName ) ) {
				var renamed = findBundle( argumentCollection=arguments, searchName=newSearchName );
				if ( Len( renamed.url ?: "" ) || Len( renamed.cacheObject ?: "" ) ) {
					return renamed;
				}
			}
		}

		// Not on a Maven repository (the outer call only, after the renamed search): the jar extracted from an
		// extension .lex earlier, kept in the bundle cache (Cloud Storage), or else unpack the .lex now
		if ( arguments.searchName == arguments.bundleName ) {
			var fromCache = _fromBundleCache( arguments.bundleName, arguments.bundleVersion );
			if ( StructCount( fromCache ) ) {
				return fromCache;
			}
			var fromLex = _fromLex( arguments.bundleName, arguments.bundleVersion );
			if ( StructCount( fromLex ) ) {
				return fromLex;
			}
		}

		// Really not found, cache this result for 10m to avoid
		// repeated 404 lookups which have to go through all the hoops to get
		// here
		return _saveToCache( argumentCollection=arguments, bundleUrl="", cacheExpires=DateAdd( 'n', 10, Now() ) );
	}

	/**
	 * The bytes of a bundle jar in the bundle cache (findBundle answered a cacheObject and no url: the bucket is
	 * not public and the jar is streamed by this instance).
	 */
	public binary function readCachedBundle( required string bundleName, required string bundleVersion ) {
		try {
			return getBundleCache().read( arguments.bundleName, arguments.bundleVersion );
		} catch ( any e ) {
			// gone from the bucket: look it up again next time
			StructDelete( variables._lookupCache, _getCacheKey( arguments.bundleName, arguments.bundleVersion ) );
			rethrow;
		}
	}

	public function registerBundleFromExtensionJar(
		  required string directory
		, required string filename
	) {
		// Maven only (no bundle bucket): the jars of the extensions are not copied anywhere, the bundles come from the Maven matcher
		if ( !_hasBucket() ) {
			return;
		}

		var bundleInfo = _getBundleNameAndVersionFromFileName( arguments.fileName );
		if ( StructIsEmpty( bundleInfo ) ) {
			return;
		}

		var s3BundlePath  = _getS3BundleFilePath( arguments.fileName );

		if ( !FileExists( s3BundlePath ) ) {
			SystemOutput( "Registering bundle jar from extension lex file. Bundle: #arguments.fileName#", true );
			var tmpFile = GetTempFile( GetTempDirectory(), "extensionJar", ".jar");
			FileCopy( arguments.directory & arguments.fileName, tmpFile );
			FileCopy( tmpFile, s3BundlePath );
			FileDelete( tmpFile );
		}

		if ( StructIsEmpty( _cacheLookup( argumentCollection=bundleInfo ) ) ) {
			_saveToCache( argumentCollection=bundleInfo, bundleUrl=_getS3BundleUrl( arguments.fileName ), cacheExpires="never" );
		}
	}

// PRIVATE HELPERS
	private function _cacheLookup( bundleName, bundleVersion ) {
		var key       = _getCacheKey( argumentCollection=arguments );
		var fromCache = StructKeyExists( _lookupCache, key ) ? _lookupCache[ key ] : {};

		// an entry from an earlier version of this cache that points to a .lex is not an OSGi bundle
		if ( StructCount( fromCache ) && Len( fromCache.url ?: "" ) && _isLex( fromCache.url ) ) {
			fromCache = {};
			StructDelete( _lookupCache, key );
		}

		if ( StructIsEmpty( fromCache ) ) {
			fromCache = _s3Lookup( argumentCollection=arguments );
			if ( StructCount( fromCache ) && Len( fromCache.url ?: "" ) && _isLex( fromCache.url ) ) {
				fromCache = {};
			}
			_put( key, fromCache );
		}

		if ( IsDate( fromCache.cacheExpires ?: "" ) && Now() > fromCache.cacheExpires ) {
			_put( _getCacheKey( argumentCollection=arguments ), {} );
			fromCache = {};
			_removeFromS3( argumentCollection=arguments );
		}

		return fromCache;
	}

	// the lookups are kept in memory, bounded so a stream of made up bundle names cannot grow it without end
	private void function _put( required string key, required struct info ) {
		if ( StructCount( _lookupCache ) >= 20000 ) {
			variables._lookupCache = {};
		}
		_lookupCache[ arguments.key ] = arguments.info;
	}

	private function _saveToCache( bundleName, bundleVersion, bundleUrl, cacheExpires, cacheObject="" ) {
		var bundleInfo = _createBundleInfo( argumentCollection=arguments );

		_put( _getCacheKey( argumentCollection=arguments ), bundleInfo );
		_storeToS3( argumentCollection=arguments, bundleInfo=bundleInfo );

		return bundleInfo;
	}

	// without a bundle bucket (STORAGE=maven) the lookups are kept in memory only
	private boolean function _hasBucket() {
		return Len( getBundleS3Root() ) > 0;
	}

	private function _s3Lookup( bundleName, bundleVersion ) {
		if ( !_hasBucket() ) {
			return {};
		}

		var filePath = _getS3CacheFilePath( argumentCollection=arguments );

		if ( FileExists( filePath ) ) {
			try {
				return DeserializeJson( FileRead( filePath ) );
			} catch( any e ) { /* just a cache, failing is fine */ }
		}

		return {};
	}
	private function _storeToS3( bundleName, bundleVersion, bundleInfo ) {
		if ( !_hasBucket() ) {
			return;
		}

		try {
			services.CacheDir::writeAtomic( _getS3CacheFilePath( argumentCollection=arguments ), SerializeJson( bundleInfo ) );
		} catch( any e ) { /* just a cache, failing is fine */ }
	}

	private function _removeFromS3( bundleName, bundleVersion ) {
		if ( !_hasBucket() ) {
			return;
		}

		try {
			FileDelete( _getS3CacheFilePath( argumentCollection=arguments ) );
		} catch( any e ) { /* just a cache, failing is fine */ }
	}

	private function _getCacheKey( bundleName, bundleVersion ) {
		return "b:#arguments.bundleName#.v:#arguments.bundleVersion#";
	}

	private function _getS3CacheFilePath( bundleName, bundleVersion ) {
		return _getS3CacheDir() & "/#arguments.bundleName#.#arguments.bundleVersion#.json";
	}

	private function _getS3CacheDir() {
		return getBundleS3root() & ".meta-cache";
	}

	private function _getBundleNameAndVersionFromFileName( fileName ) {
		var nameSansExt       = ListDeleteAt( arguments.fileName, ListLen( arguments.fileName, "." ), "." );
		var patternBase       = "([0-9]+~[0-9]+~[0-9]+.*)$"
		var versionPatterns   = [
			  "^(.*)-#Replace( patternBase, "~","\.", "all" )#"
			, "^(.*)-#Replace( patternBase, "~","-", "all" )#"
		];

		for( var pattern in versionPatterns ) {
			if ( ReFindNoCase( pattern, nameSansExt ) ) {
				return {
					  bundleName    = ReReplaceNoCase( nameSansExt, pattern, "\1" )
					, bundleVersion = ReReplaceNoCase( nameSansExt, pattern, "\2" )
				};
			}
		}

		return {};
	}

	private function _searchBundleBucket( bundleName, bundleVersion ) {
		var matchedFiles  = [];
		var matched       = false;
		var latestOnly    = arguments.bundleVersion == "latest";
		var possibleFiles = DirectoryList(
			  path     = _getS3BundlesDir()
			, filter   = "#ListFirst( arguments.bundleName, "-." )#*.jar"
			, sort     = "name"
			, listInfo = "query"
		);
		for( var f in possibleFiles ) {
			var bundleinfo = _getBundleNameAndVersionFromFileName( f.name );
			if ( StructCount( bundleInfo ) && bundleInfo.bundleName == bundleName ) {
				if ( latestOnly ) {
					matched = true;
					ArrayAppend( matchedFiles, { name=f.name, version=VersionUtils::sortableVersionString( bundleInfo.bundleVersion ) } );
				} else if ( arguments.bundleVersion == bundleInfo.bundleVersion ) {
					return _getS3BundleUrl( f.name );
				}

			} else if ( matched ) {
				break;
			}
		}

		if ( ArrayLen( matchedFiles ) ) {
			ArraySort( matchedFiles, function( a, b ){
				if ( a.version == b.version ) return 0;
				return a.version < b.version ? 1 : -1;
			} );

			return _getS3BundleUrl( matchedFiles[ 1 ].name );
		}

		return "";
	}


	private function _createBundleInfo( bundleName, bundleVersion, bundleUrl, cacheExpires="", cacheObject="" ) {
		return {
			  name         = arguments.bundleName
			, version      = arguments.bundleVersion
			, url          = arguments.bundleUrl
			, cacheExpires = arguments.cacheExpires
			// the object of the jar in the bundle cache, set when it is served from there
			, cacheObject  = arguments.cacheObject
		};
	}

	private function _getS3BundleFilePath( fileName ) {
		return _getS3BundlesDir() & "#arguments.fileName#";
	}
	private function _getS3BundlesDir() {
		return getBundleS3root();
	}
	private function _getS3BundleUrl( fileName ) {
		return getBundleCdnUrl() & arguments.fileName;
	}

	private boolean function _isLex( required string pathOrUrl ) {
		return ListLast( ListFirst( arguments.pathOrUrl, "?" ), "." ) == "lex";
	}

// BUNDLE CACHE (Cloud Storage) AND .LEX FALLBACK

	private boolean function _hasBundleCache() {
		if ( !StructKeyExists( variables, "bundleCache" ) || IsNull( variables.bundleCache ) || IsSimpleValue( variables.bundleCache ) ) {
			return false;
		}
		return variables.bundleCache.isEnabled();
	}

	/**
	 * The jar in the bundle cache: a public URL (a 302 to the bucket) when the bucket has one, otherwise the object
	 * name (streamed by this instance). A jar of a bundle version does not change, it is remembered for good.
	 */
	private struct function _fromBundleCache( required string bundleName, required string bundleVersion ) {
		if ( arguments.bundleVersion == "latest" || !_hasBundleCache() ) {
			return {};
		}
		var cache = getBundleCache();
		var found = false;
		try {
			found = cache.exists( arguments.bundleName, arguments.bundleVersion );
		} catch ( any e ) {
			SystemOutput( "Bundle cache lookup of [#arguments.bundleName#] [#arguments.bundleVersion#] failed: #e.message#", true );
		}
		if ( !found ) {
			return {};
		}
		return _saveToCache(
			  bundleName    = arguments.bundleName
			, bundleVersion = arguments.bundleVersion
			, bundleUrl     = cache.publicUrl( arguments.bundleName, arguments.bundleVersion )
			, cacheExpires  = "never"
			, cacheObject   = cache.objectName( arguments.bundleName, arguments.bundleVersion )
		);
	}

	/**
	 * Find the extension .lex files that can contain the bundle (MavenMatcher.findLexUrls(), and the extension
	 * listing by file name), unpack each one at most once per instance, put every OSGi jar of it into the bundle
	 * cache under its Bundle-SymbolicName and Bundle-Version (never overwriting), and answer the requested one.
	 * Requests for the jars of one .lex wait for one unpack (a named lock), the ones waiting find the jars in the
	 * cache. "latest" is not looked up in .lex files.
	 */
	private struct function _fromLex( required string bundleName, required string bundleVersion ) {
		if ( !getLexFallback() || arguments.bundleVersion == "latest" || !_hasBundleCache() ) {
			return {};
		}
		if ( !Len( getBundleCache().objectName( arguments.bundleName, arguments.bundleVersion ) ) ) {
			return {};
		}

		for ( var lexUrl in _lexCandidates( arguments.bundleName, arguments.bundleVersion ) ) {
			if ( !StructKeyExists( variables._lexDone, lexUrl ) ) {
				lock name="lucee-bundle-lex-#Hash( lexUrl, "MD5" )#" type="exclusive" timeout=( getLexTimeout() * 2 ) throwOnTimeout=false {
					// another request may have unpacked it while this one waited
					if ( !StructKeyExists( variables._lexDone, lexUrl ) && _unpackLexToCache( lexUrl, arguments.bundleName, arguments.bundleVersion ) ) {
						if ( StructCount( variables._lexDone ) >= 1000 ) {
							variables._lexDone = {};
						}
						variables._lexDone[ lexUrl ] = true;
					}
				}
			}
			var found = _fromBundleCache( arguments.bundleName, arguments.bundleVersion );
			if ( StructCount( found ) ) {
				return found;
			}
		}
		return {};
	}

	private array function _lexCandidates( required string bundleName, required string bundleVersion ) {
		var found = { urls=[], seen={} };

		// the extension listing (the newest version of each extension), by file name
		try {
			if ( StructKeyExists( variables, "extensionMetaReader" ) && !IsNull( variables.extensionMetaReader ) && !IsSimpleValue( variables.extensionMetaReader ) ) {
				var reader  = variables.extensionMetaReader;
				var lexFile = reader.getExtensionFileMatchingBundle( bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion );
				if ( Len( Trim( lexFile ) ) ) {
					_addLexCandidate( found, reader.getDownloadUrl( lexFile, getExtensionsCdnUrl() ) );
				}
			}
		} catch ( any e ) {
			SystemOutput( "Extension listing lookup for bundle [#arguments.bundleName#] [#arguments.bundleVersion#] failed: #e.message#", true );
		}

		// the Maven layout: org.lucee:<artifact>:<version>.lex, also the older versions of an extension
		try {
			for ( var u in getMavenMatcher().findLexUrls( arguments.bundleName, arguments.bundleVersion ) ) {
				_addLexCandidate( found, u );
			}
		} catch ( any e ) {
			SystemOutput( "Maven .lex lookup for bundle [#arguments.bundleName#] [#arguments.bundleVersion#] failed: #e.message#", true );
		}

		return found.urls;
	}

	private void function _addLexCandidate( required struct found, required string lexUrl ) {
		if ( Len( arguments.lexUrl ) && _isLex( arguments.lexUrl ) && !StructKeyExists( arguments.found.seen, arguments.lexUrl ) ) {
			arguments.found.seen[ arguments.lexUrl ] = true;
			ArrayAppend( arguments.found.urls, arguments.lexUrl );
		}
	}

	/**
	 * Download (or open, for a local path) a .lex, read the manifest of every jar in it and put the OSGi bundles into
	 * the bundle cache, the requested one first. Nothing is kept on the disk of the instance. Returns whether the
	 * .lex could be read.
	 */
	private boolean function _unpackLexToCache( required string lexUrl, required string bundleName, required string bundleVersion ) {
		var lexFile    = arguments.lexUrl;
		var downloaded = false;

		if ( ReFindNoCase( "^https?://", arguments.lexUrl ) ) {
			lexFile    = _downloadLex( arguments.lexUrl );
			downloaded = Len( lexFile ) > 0;
		}
		if ( !Len( lexFile ) || !FileExists( lexFile ) ) {
			return false;
		}

		var ok   = false;
		var jars = [];
		try {
			jars = _readLexJars( lexFile, arguments.lexUrl, arguments.bundleName, arguments.bundleVersion );
			ok   = true;
		} catch ( any e ) {
			SystemOutput( "Could not read the extension [#arguments.lexUrl#]: #e.message#", true );
		}
		if ( downloaded ) {
			_deleteQuietly( lexFile );
		}

		for ( var jar in jars ) {
			try {
				getBundleCache().put( jar.bundleName, jar.bundleVersion, jar.file );
			} catch ( any e ) {
				SystemOutput( "Could not put [#jar.bundleName#] [#jar.bundleVersion#] of [#arguments.lexUrl#] into the bundle cache: #e.message#", true );
			}
			_deleteQuietly( jar.file );
		}
		if ( ok ) {
			SystemOutput( "Bundle cache: #ArrayLen( jars )# bundle jar(s) of [#arguments.lexUrl#]", true );
		}
		return ok;
	}

	// the OSGi jars of a .lex as temp files: [ { bundleName, bundleVersion, file } ], the requested bundle first
	private array function _readLexJars( required string lexFile, required string lexUrl, required string bundleName, required string bundleVersion ) {
		var jars    = [];
		var zipFile = CreateObject( "java", "java.util.zip.ZipFile" ).init( arguments.lexFile );
		try {
			var entries = zipFile.entries();
			while ( entries.hasMoreElements() ) {
				var info = _readLexEntry( zipFile, entries.nextElement(), arguments.lexUrl );
				if ( !StructCount( info ) ) {
					// not a jar or not an OSGi bundle
				} else if ( info.bundleName == arguments.bundleName && info.bundleVersion == arguments.bundleVersion ) {
					// the requested bundle first, so it is in the cache even when a later upload fails
					ArrayPrepend( jars, info );
				} else {
					ArrayAppend( jars, info );
				}
			}
		} catch ( any e ) {
			for ( var jar in jars ) {
				_deleteQuietly( jar.file );
			}
			zipFile.close();
			rethrow;
		}
		zipFile.close();
		return jars;
	}

	// one entry of a .lex: { bundleName, bundleVersion, file } for an OSGi jar (copied to a temp file), else {}
	private struct function _readLexEntry( required any zipFile, required any entry, required string lexUrl ) {
		var name = arguments.entry.getName();
		if ( arguments.entry.isDirectory() || LCase( Right( name, 4 ) ) != ".jar" ) {
			return {};
		}
		var tmp  = GetTempFile( GetTempDirectory(), "lexjar" );
		var info = {};
		try {
			_copyZipEntry( arguments.zipFile, arguments.entry, tmp );
			info = _readBundleManifest( tmp );
		} catch ( any e ) {
			SystemOutput( "Could not read [#name#] of [#arguments.lexUrl#]: #e.message#", true );
			info = {};
		}
		if ( !StructCount( info ) ) {
			_deleteQuietly( tmp );
			return {};
		}
		info.file = tmp;
		return info;
	}

	private string function _downloadLex( required string lexUrl ) {
		var tmp    = GetTempFile( GetTempDirectory(), "bundlelex" );
		var status = 0;
		var size   = 0;
		try {
			http url=arguments.lexUrl method="GET" file=GetFileFromPath( tmp ) path=GetDirectoryFromPath( tmp ) getasbinary="yes" timeout=getLexTimeout() throwonerror=false result="local.res";
			status = Val( res.status_code ?: 0 );
			size   = FileExists( tmp ) ? Val( GetFileInfo( tmp ).size ) : 0;
		} catch ( any e ) {
			SystemOutput( "Could not download the extension [#arguments.lexUrl#]: #e.message#", true );
		}
		if ( status == 200 && size > 0 && size <= getLexMaxBytes() ) {
			return tmp;
		}
		SystemOutput( "Could not download the extension [#arguments.lexUrl#]: status #status#, #size# bytes", true );
		_deleteQuietly( tmp );
		return "";
	}

	private void function _copyZipEntry( required any zipFile, required any entry, required string dest ) {
		var stream = arguments.zipFile.getInputStream( arguments.entry );
		var bytes  = "";
		try {
			bytes = stream.readAllBytes();
		} catch ( any e ) {
			stream.close();
			rethrow;
		}
		stream.close();
		FileWrite( arguments.dest, bytes );
	}

	// Bundle-SymbolicName (without its directives) and Bundle-Version of a jar, {} when it is not an OSGi bundle
	private struct function _readBundleManifest( required string jarFile ) {
		var jar      = CreateObject( "java", "java.util.jar.JarFile" ).init( arguments.jarFile );
		var symbolic = "";
		var version  = "";
		try {
			var mf = jar.getManifest();
			if ( !IsNull( mf ) ) {
				var attrs = mf.getMainAttributes();
				symbolic  = attrs.getValue( "Bundle-SymbolicName" ) ?: "";
				version   = attrs.getValue( "Bundle-Version" ) ?: "";
			}
		} catch ( any e ) {
			jar.close();
			rethrow;
		}
		jar.close();
		symbolic = Trim( ListFirst( symbolic, ";" ) );
		version  = Trim( version );
		if ( !Len( symbolic ) || !Len( version ) ) {
			return {};
		}
		return { bundleName=symbolic, bundleVersion=version };
	}

	private void function _deleteQuietly( required string file ) {
		try {
			if ( Len( arguments.file ) && FileExists( arguments.file ) ) {
				FileDelete( arguments.file );
			}
		} catch ( any ignore ) {}
	}


}
