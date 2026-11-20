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
		// Get it from cache (eventually everything will end up here)
		var bundleInfo = _cacheLookup( argumentCollection=arguments );

		if ( StructCount( bundleInfo ) && ( Len( bundleInfo.file ?: "" ) || Len( bundleInfo.url ?: "" ) ) ) {
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
				return findBundle( argumentCollection=arguments, searchName=newSearchName );
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

		if ( StructIsEmpty( fromCache ) || ( !Len( fromCache.file ?: "" ) && !Len( fromCache.url ?: "" ) ) ) {
			var disk = _cachedJarPath( arguments.bundleName, arguments.bundleVersion );
			if ( Len( disk ) && FileExists( disk ) ) {
				fromCache = _createBundleInfo( argumentCollection=arguments, bundleUrl="", file=disk, cacheExpires="never" );
				_lookupCache[ key ] = fromCache;
				return fromCache;
			}
		}

		if ( StructIsEmpty( fromCache ) ) {
			_lookupCache[ key ] = fromCache = _s3Lookup( argumentCollection=arguments );
		}

		if ( IsDate( fromCache.cacheExpires ?: "" ) && Now() > fromCache.cacheExpires ) {
			_lookupCache[ key ] = fromCache = {};
			_removeFromS3( argumentCollection=arguments );
		}

		return fromCache;
	}

	private function _saveToCache( bundleName, bundleVersion, bundleUrl, cacheExpires ) {
		var bundleInfo = _createBundleInfo( argumentCollection=arguments );

		_lookupCache[ _getCacheKey( argumentCollection=arguments ) ] = bundleInfo;
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
			FileWrite( _getS3CacheFilePath( argumentCollection=arguments ), SerializeJson( bundleInfo ) );
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
			  name         = arguments.bundleName
			, version      = arguments.bundleVersion
			, url          = arguments.bundleUrl
			, file         = arguments.file
			, cacheExpires = arguments.cacheExpires
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
	 * Bundle-SymbolicName and Bundle-Version under CACHE_DIRECTORY, and
	 * return the jar that matches the requested bundle (never the lex).
	 */
	private struct function _bundlesFromLex( string lexUrl="", string lexName="", required string bundleName, required string bundleVersion ) {
		var lexFile = "";

		if ( Len( arguments.lexUrl ) && !_isLex( arguments.lexUrl ) ) {
			return {};
		}

		if ( Len( arguments.lexUrl ) && FileExists( arguments.lexUrl ) && !ReFindNoCase( "^https?://", arguments.lexUrl ) ) {
			lexFile = arguments.lexUrl;
		} else if ( Len( arguments.lexUrl ) ) {
			lexFile = _downloadLex( arguments.lexUrl, arguments.lexName );
		}

		if ( !Len( lexFile ) || !FileExists( lexFile ) ) {
			return {};
		}

		_indexJarsFromLex( lexFile );

		return _cacheLookup( arguments.bundleName, arguments.bundleVersion );
	}

	private string function _downloadLex( required string lexUrl, string lexName="" ) {
		var name = Len( arguments.lexName ) ? ListLast( arguments.lexName, "/\\" ) : ListLast( ListFirst( arguments.lexUrl, "?" ), "/" );
		if ( !Len( name ) || ListLast( name, "." ) != "lex" ) {
			name = "bundle.lex";
		}
		var dest = _bundleJarDir() & "lex-" & ReReplace( name, "[^A-Za-z0-9._-]", "_", "all" );
		if ( FileExists( dest ) ) {
			return dest;
		}

		var tmp = GetTempFile( GetTempDirectory(), "bundlelex", ".lex" );
		try {
			http url=arguments.lexUrl file=tmp getasbinary=true timeout=60;
			if ( !FileExists( tmp ) || Val( GetFileInfo( tmp ).size ) == 0 ) {
				return "";
			}
			FileCopy( tmp, dest );
			return dest;
		} catch ( any e ) {
			SystemOutput( "Could not download the extension lex [#arguments.lexUrl#]: #e.message#", true );
			return "";
		} finally {
			if ( FileExists( tmp ) ) {
				try { FileDelete( tmp ); } catch ( any ignore ) {}
			}
		}
	}

	private void function _indexJarsFromLex( required string lexFile ) {
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

	private void function _rememberJar( required string bundleName, required string bundleVersion, required string file ) {
		_lookupCache[ _getCacheKey( arguments.bundleName, arguments.bundleVersion ) ] = _createBundleInfo(
			  bundleName    = arguments.bundleName
			, bundleVersion = arguments.bundleVersion
			, bundleUrl     = ""
			, file          = arguments.file
			, cacheExpires  = "never"
		);
	}

	private string function _cachedJarPath( required string bundleName, required string bundleVersion ) {
		var safeName = ReReplace( arguments.bundleName, "[^A-Za-z0-9._-]", "_", "all" );
		var safeVer  = ReReplace( arguments.bundleVersion, "[^A-Za-z0-9._-]", "_", "all" );
		return _bundleJarDir() & safeName & "-" & safeVer & ".jar";
	}

	private string function _bundleJarDir() {
		if ( !StructKeyExists( variables, "_bundleJarDir" ) ) {
			variables._bundleJarDir = services.CacheDir::path( "bundle-jars", GetTempDirectory() & "lucee-update-cache/bundle-jars/" );
			if ( Right( variables._bundleJarDir, 1 ) != "/" ) {
				variables._bundleJarDir &= "/";
			}
		}
		return variables._bundleJarDir;
	}

}
