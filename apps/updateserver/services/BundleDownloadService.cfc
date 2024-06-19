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
	public struct function findBundle( required string bundleName, required string bundleVersion ) {
		// Get it from cache
		var bundleInfo = _cacheLookup( argumentCollection=arguments );

		if ( StructCount( bundleInfo ) ) {
			return bundleInfo;
		}

		// Simple maven match
		var bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments );
		if ( Len( Trim( bundleUrl ) ) ) {
			var cacheExpiry = arguments.bundleVersion == "latest" ? DateAdd( 'h', 1, Now() ) : "never";

			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires=cacheExpiry );
		}

		// Do we have a matching extension lex to download?
		// Question here: should we also then be looking for a
		// corresponding .jar? or do we actually download the lex
		// (we SHOULD have already discovered the jar if there was one)?
		var extensionLexFile = getExtensionMetaReader().getExtensionFileMatchingBundle(
			  bundleName    = arguments.bundleName
			, bundleVersion = arguments.bundleVersion
		);
		if ( Len( Trim( extensionLexFile ) ) ) {
			bundleUrl = getExtensionsCdnUrl() & extensionLexFile;
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
		}

		// Fuller maven search
		bundleUrl = getMavenMatcher().findBundleUrl( argumentCollection=arguments, rawSearch=true );
		if ( Len( Trim( bundleUrl ) ) ) {
			return _saveToCache( argumentCollection=arguments, bundleUrl=bundleUrl, cacheExpires="never" );
		}

		// Not found
		return {};
	}

	public function registerBundleFromExtensionJar(
		  required string directory
		, required string filename
	) {
		var bundleInfo = _getBundleNameAndVersionFromFileName( arguments.fileName );
		if ( StructIsEmpty( bundleInfo ) ) {
			return;
		}

		var s3JarPath  = _getS3ExtensionJarFilePath( arguments.fileName );

		if ( !FileExists( s3JarPath ) ) {
			SystemOutput( "Registering bundle jar from extension lex file. Bundle: #arguments.fileName#", true );
			var tmpFile = GetTempFile( GetTempDirectory(), "extensionjar" ) & ".jar";
			FileCopy( arguments.directory & arguments.fileName, tmpFile );
			FileCopy( tmpFile, s3JarPath );
		}

		if ( StructIsEmpty( _cacheLookup( argumentCollection=bundleInfo ) ) ) {
			_saveToCache( argumentCollection=bundleInfo, bundleUrl=_getS3ExtensionJarUrl( arguments.fileName ), cacheExpires="never" );
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
		var patternBase       = "([1-9]+[0-9]*~[1-9]+[0-9]*~[1-9]+[0-9]*~[^~]+)$"
		var versionPatterns   = [
			  "^(.*)\-#Replace( patternBase, "~","\.", "all" )#"
			, "^(.*)\-#Replace( patternBase, "~","\-", "all" )#"
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

	private function _createBundleInfo( bundleName, bundleVersion, bundleUrl, cacheExpires="" ) {
		return {
			  name         = arguments.bundleName
			, version      = arguments.bundleVersion
			, url          = arguments.bundleUrl
			, cacheExpires = arguments.cacheExpires
		};
	}

	private function _getS3ExtensionJarFilePath( fileName ) {
		return _getS3ExtensionJarsDir() & "#arguments.fileName#";
	}
	private function _getS3ExtensionJarsDir() {
		return getBundleS3root();
	}
	private function _getS3ExtensionJarUrl( fileName ) {
		return getBundleCdnUrl() & arguments.fileName;
	}
}