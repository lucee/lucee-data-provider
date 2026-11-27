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

	variables._lookupCache = {};

	/**
	 * Attempt to locate an osgi bundle file
	 * by looking up various locations
	 */
	public struct function findBundle( required string bundleName, required string bundleVersion, string searchName=arguments.bundleName ) {
		var found = _findBundle( argumentCollection=arguments );
		// the outer call only: a jar that is only on the disk of this instance (extracted from a lex) is redirected to
		// when the same jar has a public URL, see _preferPublicUrl()
		if ( arguments.searchName == arguments.bundleName ) {
			return _preferPublicUrl( found, arguments.bundleName, arguments.bundleVersion );
		}
		return found;
	}

	/**
	 * A jar that was extracted from a lex (bundle.file, only on the disk of this instance) gets the public URL of the
	 * same bundle when there is one, so the download can be a 302 instead of this instance serving the bytes.
	 * The URL lookup runs once per bundle and instance, its result is kept in the lookup cache: a found URL for good,
	 * a miss is looked up again after a day (an hour when the lookup failed), so a jar that was uploaded later
	 * (the "Upload Maven jar" workflow of lucee/Lucee, org.lucee:<Bundle-SymbolicName>:<Bundle-Version>) is picked up.
	 * A cached answer (url or a miss that is not due) costs no network call.
	 */
	private struct function _preferPublicUrl( required struct info, required string bundleName, required string bundleVersion ) {
		if ( !StructCount( arguments.info ) || Len( arguments.info.url ?: "" ) || !Len( arguments.info.file ?: "" ) ) {
			return arguments.info;
		}
		// "latest" is the newest jar of the lex, a URL of the newest Maven version can be another version
		if ( arguments.bundleVersion == "latest" || !_urlCheckDue( arguments.info ) ) {
			return arguments.info;
		}

		var key = _getCacheKey( arguments.bundleName, arguments.bundleVersion );
		lock name="lucee-bundle-url-#Hash( key, "MD5" )#" type="exclusive" timeout=30 throwOnTimeout=false {
			// another request may have looked it up while this one waited
			var current = StructKeyExists( variables._lookupCache, key ) ? variables._lookupCache[ key ] : arguments.info;
			if ( !Len( current.file ?: "" ) ) {
				current = arguments.info;
			}
			if ( Len( current.url ?: "" ) || !_urlCheckDue( current ) ) {
				return current;
			}

			var publicUrl  = "";
			var retryHours = 24;
			try {
				publicUrl = _findPublicJarUrl( arguments.bundleName, arguments.bundleVersion );
			} catch ( any e ) {
				retryHours = 1;
				SystemOutput( "Could not look up a public URL for bundle [#arguments.bundleName#] [#arguments.bundleVersion#]: #e.message#", true );
			}

			var updated = StructCopy( current );
			updated.url           = publicUrl;
			updated.urlCheckAfter = Len( publicUrl ) ? "" : DateAdd( "h", retryHours, Now() );
			_put( key, updated );
			return updated;
		}
		return arguments.info;
	}

	private boolean function _urlCheckDue( required struct info ) {
		var due = arguments.info.urlCheckAfter ?: "";
		return !IsDate( due ) || Now() >= due;
	}

	// a jar (never a lex) on Maven Central or the Lucee repositories, the same lookups findBundle uses
	private string function _findPublicJarUrl( required string bundleName, required string bundleVersion ) {
		var u = getMavenMatcher().findBundleUrl( bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion );
		if ( Len( Trim( u ) ) && !_isLex( u ) && ReFindNoCase( "^https?://", u ) ) {
			return u;
		}
		u = getMavenMatcher().findBundleUrl( bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion, rawSearch=true, jarsOnly=true );
		if ( Len( Trim( u ) ) && !_isLex( u ) && ReFindNoCase( "^https?://", u ) ) {
			return u;
		}
		return "";
	}

	private struct function _findBundle( required string bundleName, required string bundleVersion, string searchName=arguments.bundleName ) {
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
		if ( Len( Trim( bundleUrl ) ) ) {
			if ( _isLex( bundleUrl ) ) {
				var fromMappedLex = _bundlesFromLex( lexUrl=bundleUrl, lexName=ListLast( bundleUrl, "/" ), bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion );
				if ( StructCount( fromMappedLex ) ) {
					return fromMappedLex;
				}
			} else {
				var cacheExpiry = arguments.bundleVersion == "latest" ? DateAdd( 'h', 1, Now() ) : "never";

				return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires=cacheExpiry );
			}
		}

		// Do we have a matching extension lex to download?
		// Never serve the lex as the OSGi bundle: extract the inner jar whose
		// Bundle-SymbolicName and version match, and index every jar in the lex.
		var extensionLexFile = getExtensionMetaReader().getExtensionFileMatchingBundle(
			  bundleName    = arguments.searchName
			, bundleVersion = arguments.bundleVersion
		);
		if ( Len( Trim( extensionLexFile ) ) ) {
			bundleUrl = getExtensionMetaReader().getDownloadUrl( extensionLexFile, getExtensionsCdnUrl() );
			var fromLex = _bundlesFromLex( lexUrl=bundleUrl, lexName=extensionLexFile, bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion );
			if ( StructCount( fromLex ) ) {
				return fromLex;
			}
		}

		// Fuller maven search (jars and, for org.lucee.*, .lex files)
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, bundleName=arguments.searchName, rawSearch=true );
		if ( Len( Trim( bundleUrl ) ) ) {
			if ( _isLex( bundleUrl ) ) {
				var fromRawLex = _bundlesFromLex( lexUrl=bundleUrl, lexName=ListLast( bundleUrl, "/" ), bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion );
				if ( StructCount( fromRawLex ) ) {
					return fromRawLex;
				}
			} else {
				return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
			}
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
				return _findBundle( argumentCollection=arguments, searchName=newSearchName );
			}
		}

		// Really not found, cache this result for 10m to avoid
		// repeated 404 lookups which have to go through all the hoops to get
		// here
		return _saveToCache( argumentCollection=arguments, bundleUrl="", cacheExpires=DateAdd( 'n', 10, Now() ) );
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

		// A jar that was extracted from a lex lives in the temp folder of this instance, when it is gone (the folder
		// is not kept) it is looked up again. An entry from an earlier version of this cache that points to a
		// .lex is not an OSGi bundle either. Both checks are local, nothing goes to the storage.
		if ( StructCount( fromCache ) ) {
			var staleFile = Len( fromCache.file ?: "" ) && !FileExists( fromCache.file );
			var lexUrl    = Len( fromCache.url ?: "" ) && _isLex( fromCache.url );
			if ( staleFile && !lexUrl && Len( fromCache.url ?: "" ) ) {
				// the jar is gone from the temp folder, but it has a public URL: keep that, no new lookup
				fromCache = StructCopy( fromCache );
				fromCache.file = "";
				_put( key, fromCache );
			} else if ( staleFile || lexUrl ) {
				fromCache = {};
				StructDelete( _lookupCache, key );
			}
		}

		if ( StructIsEmpty( fromCache ) ) {
			var disk = _cachedJarPath( arguments.bundleName, arguments.bundleVersion );
			if ( FileExists( disk ) ) {
				fromCache = _createBundleInfo( argumentCollection=arguments, bundleUrl="", file=disk, cacheExpires="never" );
				_put( key, fromCache );
				return fromCache;
			}

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

	private function _saveToCache( bundleName, bundleVersion, bundleUrl, cacheExpires ) {
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


	private function _createBundleInfo( bundleName, bundleVersion, bundleUrl, cacheExpires="", file="" ) {
		return {
			  name          = arguments.bundleName
			, version       = arguments.bundleVersion
			, url           = arguments.bundleUrl
			, file          = arguments.file
			, cacheExpires  = arguments.cacheExpires
			// a file without url: when to look for a public URL of it (again), "" is right away, see _preferPublicUrl()
			, urlCheckAfter = ""
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

	/**
	 * Download or open a .lex, extract every jars/*.jar, index them by
	 * Bundle-SymbolicName and Bundle-Version in the temp folder of this instance
	 * (never on the shared storage mount: reading or listing there is a billed
	 * storage operation per request), and return the jar that matches the
	 * requested bundle (never the lex). The lex itself is not kept, the lookups
	 * are in memory and the jars are served from the local disk.
	 */
	private struct function _bundlesFromLex( string lexUrl="", string lexName="", required string bundleName, required string bundleVersion ) {
		if ( Len( arguments.lexUrl ) && !_isLex( arguments.lexUrl ) ) {
			return {};
		}

		// one download per lex at a time, the ones waiting find the jars indexed by the first
		lock name="lucee-bundle-lex-#Hash( arguments.lexName & "|" & arguments.lexUrl, "MD5" )#" type="exclusive" timeout="120" {
			var known = _cacheLookup( arguments.bundleName, arguments.bundleVersion );
			if ( Len( known.file ?: "" ) ) {
				return known;
			}

			var lexFile    = "";
			var downloaded = false;

			if ( Len( arguments.lexUrl ) && FileExists( arguments.lexUrl ) && !ReFindNoCase( "^https?://", arguments.lexUrl ) ) {
				lexFile = arguments.lexUrl;
			} else if ( Len( arguments.lexUrl ) ) {
				lexFile    = _downloadLex( arguments.lexUrl );
				downloaded = Len( lexFile ) > 0;
			}

			if ( !Len( lexFile ) || !FileExists( lexFile ) ) {
				return {};
			}

			var indexed = [];
			try {
				indexed = _indexJarsFromLex( lexFile );
			} finally {
				if ( downloaded && FileExists( lexFile ) ) {
					try { FileDelete( lexFile ); } catch ( any ignore ) {}
				}
			}

			return _pickIndexed( indexed, arguments.bundleName, arguments.bundleVersion );
		}
	}

	/**
	 * The jar of a lex for the requested bundle. An exact name and version is found by the lookup, "latest" is the
	 * newest version of that name in the lex. The result is remembered under the requested name and version too.
	 */
	private struct function _pickIndexed( required array indexed, required string bundleName, required string bundleVersion ) {
		var found = _cacheLookup( arguments.bundleName, arguments.bundleVersion );
		if ( Len( found.file ?: "" ) ) {
			return found;
		}

		var wanted = _normalizeBundleName( arguments.bundleName );
		var best   = {};
		for ( var jar in arguments.indexed ) {
			if ( _normalizeBundleName( jar.bundleName ) != wanted ) {
				continue;
			}
			if ( arguments.bundleVersion != "latest" && jar.bundleVersion != arguments.bundleVersion ) {
				continue;
			}
			if ( StructIsEmpty( best ) || Compare( VersionUtils::sortableVersionString( jar.bundleVersion ), VersionUtils::sortableVersionString( best.bundleVersion ) ) > 0 ) {
				best = jar;
			}
		}

		if ( StructIsEmpty( best ) ) {
			return {};
		}

		var expires = arguments.bundleVersion == "latest" ? DateAdd( "h", 1, Now() ) : "never";
		_rememberJar( arguments.bundleName, arguments.bundleVersion, best.file, expires );
		return _cacheLookup( arguments.bundleName, arguments.bundleVersion );
	}

	private string function _normalizeBundleName( required string name ) {
		return LCase( Replace( arguments.name, "-", ".", "all" ) );
	}

	// the lex is downloaded to a temp file, the caller deletes it once the jars are extracted
	private string function _downloadLex( required string lexUrl ) {
		var tmp = GetTempFile( GetTempDirectory(), "bundlelex", ".lex" );
		try {
			http url=arguments.lexUrl file=tmp getasbinary=true timeout=60;
			if ( !FileExists( tmp ) || Val( GetFileInfo( tmp ).size ) == 0 ) {
				if ( FileExists( tmp ) ) {
					try { FileDelete( tmp ); } catch ( any ignore ) {}
				}
				return "";
			}
			return tmp;
		} catch ( any e ) {
			SystemOutput( "Could not download the extension lex [#arguments.lexUrl#]: #e.message#", true );
			if ( FileExists( tmp ) ) {
				try { FileDelete( tmp ); } catch ( any ignore ) {}
			}
			return "";
		}
	}

	private array function _indexJarsFromLex( required string lexFile ) {
		var indexed = [];
		var dir     = _bundleJarDir();
		if ( !DirectoryExists( dir ) ) {
			DirectoryCreate( dir, true );
		}

		var zipFile = CreateObject( "java", "java.util.zip.ZipFile" ).init( arguments.lexFile );
		try {
			var entries = zipFile.entries();
			while ( entries.hasMoreElements() ) {
				var entry = entries.nextElement();
				var name  = entry.getName();
				if ( entry.isDirectory() || Right( name, 4 ) != ".jar" ) {
					continue;
				}
				var tmp = GetTempFile( GetTempDirectory(), "lexjar", ".jar" );
				try {
					_copyZipEntry( zipFile, entry, tmp );
					var info = _readBundleManifest( tmp );
					if ( StructCount( info ) ) {
						var dest = _cachedJarPath( info.bundleName, info.bundleVersion );
						FileCopy( tmp, dest );
						_rememberJar( info.bundleName, info.bundleVersion, dest );
						ArrayAppend( indexed, { bundleName=info.bundleName, bundleVersion=info.bundleVersion, file=dest } );
					}
				} catch ( any e ) {
					SystemOutput( "Could not index [#name#] from [#arguments.lexFile#]: #e.message#", true );
				} finally {
					if ( FileExists( tmp ) ) {
						try { FileDelete( tmp ); } catch ( any ignore ) {}
					}
				}
			}
		} finally {
			zipFile.close();
		}

		return indexed;
	}

	private void function _copyZipEntry( required any zipFile, required any entry, required string dest ) {
		var stream = arguments.zipFile.getInputStream( arguments.entry );
		try {
			FileWrite( arguments.dest, stream.readAllBytes() );
		} finally {
			stream.close();
		}
	}

	private struct function _readBundleManifest( required string jarFile ) {
		var zipFile = CreateObject( "java", "java.util.zip.ZipFile" ).init( arguments.jarFile );
		try {
			var entry = zipFile.getEntry( "META-INF/MANIFEST.MF" );
			if ( IsNull( entry ) ) {
				return {};
			}
			var stream = zipFile.getInputStream( entry );
			try {
				var bytes = stream.readAllBytes();
				var text  = ToString( bytes, "UTF-8" );
			} finally {
				stream.close();
			}
		} finally {
			zipFile.close();
		}

		var headers = {};
		var last    = "";
		for ( var raw in ListToArray( Replace( text, Chr( 13 ), "", "all" ), Chr( 10 ), true ) ) {
			if ( Left( raw, 1 ) == " " && Len( last ) ) {
				headers[ last ] &= Mid( raw, 2 );
				continue;
			}
			var colon = Find( ":", raw );
			if ( colon < 2 ) {
				continue;
			}
			last = Trim( Left( raw, colon - 1 ) );
			headers[ last ] = Trim( Mid( raw, colon + 1 ) );
		}

		var symbolic = headers[ "Bundle-SymbolicName" ] ?: "";
		var version  = headers[ "Bundle-Version" ] ?: "";
		if ( !Len( symbolic ) || !Len( version ) ) {
			return {};
		}

		return {
			  bundleName    = ListFirst( symbolic, ";" )
			, bundleVersion = version
		};
	}

	private void function _rememberJar( required string bundleName, required string bundleVersion, required string file, any cacheExpires="never" ) {
		var key = _getCacheKey( arguments.bundleName, arguments.bundleVersion );
		// a public URL that is already known for this bundle is kept, see _preferPublicUrl()
		var known = StructKeyExists( variables._lookupCache, key ) ? variables._lookupCache[ key ] : {};
		var info = _createBundleInfo(
			  bundleName    = arguments.bundleName
			, bundleVersion = arguments.bundleVersion
			, bundleUrl     = ( Len( known.url ?: "" ) && !_isLex( known.url ) ) ? known.url : ""
			, file          = arguments.file
			, cacheExpires  = arguments.cacheExpires
		);
		info.urlCheckAfter = known.urlCheckAfter ?: "";
		_put( key, info );
	}

	private string function _cachedJarPath( required string bundleName, required string bundleVersion ) {
		var safeName = ReReplace( arguments.bundleName, "[^A-Za-z0-9._-]", "_", "all" );
		var safeVer  = ReReplace( arguments.bundleVersion, "[^A-Za-z0-9._-]", "_", "all" );
		return _bundleJarDir() & safeName & "-" & safeVer & ".jar";
	}

	// the temp folder of this instance, see _bundlesFromLex()
	private string function _bundleJarDir() {
		return GetTempDirectory() & "lucee-update-cache/bundle-jars/";
	}

}
