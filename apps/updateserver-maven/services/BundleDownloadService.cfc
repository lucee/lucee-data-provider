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

		// Fuller maven search (jars only). A bundle is never extracted from an extension .lex: a jar that is only
		// inside a lex is published as org.lucee:<Bundle-SymbolicName>:<Bundle-Version> (the "Upload Maven jar"
		// workflow of lucee/Lucee), which this search finds on maven.lucee-services.com.
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


	private function _createBundleInfo( bundleName, bundleVersion, bundleUrl, cacheExpires="" ) {
		return {
			  name         = arguments.bundleName
			, version      = arguments.bundleVersion
			, url          = arguments.bundleUrl
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


}
