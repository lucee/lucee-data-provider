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

		// Get it from bundles s3 bucket directly
		var bundleUrl = _searchBundleBucket( argumentCollection=arguments, bundleName=arguments.searchName );
		if ( Len( Trim( bundleUrl ) ) ) {
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
		}


		// Simple maven match
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, bundleName=arguments.searchName );
		if ( Len( Trim( bundleUrl ) ) ) {
			var cacheExpiry = arguments.bundleVersion == "latest" ? DateAdd( 'h', 1, Now() ) : "never";

			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires=cacheExpiry );
		}

		// Do we have a matching extension lex to download?
		// Question here: should we also then be looking for a
		// corresponding .jar? or do we actually download the lex
		// (we SHOULD have already discovered the jar if there was one)?
		var extensionLexFile = getExtensionMetaReader().getExtensionFileMatchingBundle(
			  bundleName    = arguments.searchName
			, bundleVersion = arguments.bundleVersion
		);
		if ( Len( Trim( extensionLexFile ) ) ) {
			bundleUrl = getExtensionsCdnUrl() & extensionLexFile;
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
		}

		// Fuller maven search
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, bundleName=arguments.searchName, rawSearch=true );
		if ( Len( Trim( bundleUrl ) ) ) {
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
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
		var bundleInfo = _getBundleNameAndVersionFromFileName( arguments.fileName );
		if ( StructIsEmpty( bundleInfo ) ) {
			return;
		}

		var s3BundlePath  = _getS3BundleFilePath( arguments.fileName );

		if ( !FileExists( s3BundlePath ) ) {
			SystemOutput( "Registering bundle jar from extension lex file. Bundle: #arguments.fileName#", true );
			var tmpFile = GetTempFile( GetTempDirectory(), "extensionjar" ) & ".jar";
			FileCopy( arguments.directory & arguments.fileName, tmpFile );
			FileCopy( tmpFile, s3BundlePath );
		}

		if ( StructIsEmpty( _cacheLookup( argumentCollection=bundleInfo ) ) ) {
			_saveToCache( argumentCollection=bundleInfo, bundleUrl=_getS3BundleUrl( arguments.fileName ), cacheExpires="never" );
		}
	}

// PRIVATE HELPERS
	private function _cacheLookup( bundleName, bundleVersion ) {
		var key       = _getCacheKey( argumentCollection=arguments );
		var fromCache = StructKeyExists( _lookupCache, key ) ? _lookupCache[ key ] : {};

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

	private function _s3Lookup( bundleName, bundleVersion ) {
		var filePath = _getS3CacheFilePath( argumentCollection=arguments );

		if ( FileExists( filePath ) ) {
			try {
				return DeserializeJson( FileRead( filePath ) );
			} catch( any e ) { /* just a cache, failing is fine */ }
		}

		return {};
	}
	private function _storeToS3( bundleName, bundleVersion, bundleInfo ) {
		try {
			FileWrite( _getS3CacheFilePath( argumentCollection=arguments ), SerializeJson( bundleInfo ) );
		} catch( any e ) { /* just a cache, failing is fine */ }
	}
	private function _removeFromS3( bundleName, bundleVersion ) {
		try {
			FileDelete( _getS3CacheFilePath( argumentCollection=arguments ) );
		} catch( any e ) { /* just a cache, failing is fine */ }
	}

	private function _getCacheKey( bundleName, bundleVersion ) {
		return "b:#arguments.bundleName#.v:#arguments.bundleVersion#";
	}

	private function _getS3CacheFilePath( bundleName, bundleVersion ) {
		var sortableVersion = VersionUtils::sortableVersionString( arguments.bundleVersion );

		return _getS3CacheDir() & "/#arguments.bundleName#.#sortableVersion#.json";
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
}