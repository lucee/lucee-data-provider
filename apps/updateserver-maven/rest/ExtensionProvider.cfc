/**
 * @restpath /extension/provider
 * @rest     true
 */
component {

	variables.bound = false;

	private boolean function _servicesReady() {
		return IsBoolean( application.servicesReady ?: false ) && application.servicesReady;
	}

	private function _ensureServices( numeric timeoutMs=120000 ) {
		if ( variables.bound && _servicesReady() ) {
			return;
		}

		var started = GetTickCount();
		while ( !_servicesReady() && ( GetTickCount() - started ) < arguments.timeoutMs ) {
			if ( Len( application.servicesError ?: "" ) ) {
				throw( message="Maven provider services failed to load: #application.servicesError#" );
			}
			sleep( 100 );
		}

		if ( !_servicesReady() ) {
			throw( message="Maven provider services are still starting, try again in a moment" );
		}

		variables.metaReader = application.extMetaReader;
		variables.cdnURL     = application.extensionsCdnUrl ?: "";
		variables.bound      = true;
	}

	private function _bind() {
		_ensureServices();
	}

	private any function _cachedListing( required string key, required any producer, boolean flush=false ) {
		var cache = application.listingCache;

		if ( !arguments.flush && !_servicesReady() ) {
			var hit = cache.peek( arguments.key );
			if ( !IsSimpleValue( hit ) || Len( hit ) ) {
				return hit;
			}
			_ensureServices();
		} else {
			_ensureServices();
		}

		return cache.get( arguments.key, arguments.producer, arguments.flush );
	}

	private void function _artifactNotFound( required string type, string version="", string qualifier="", string id="" ) {
		services.ArtifactNotFound::log(
			  type      = arguments.type
			, version   = arguments.version
			, qualifier = arguments.qualifier
			, id        = arguments.id
		);
	}


	/**
	 * @httpmethod GET
	 * @restPath   info
	 */
	remote struct function getInfo(
		  required boolean withLogo     = true      restargsource="url"
		, required string  type         = 'release' restargsource="url"
		, required boolean flush        = false     restargsource="url"
		, required string  coreVersion  = ''        restargsource="url"
	) {
		var hostName = cgi.HTTP_HOST;
		var listType = ReFindNoCase( "^beta\.", hostName ) ? "abc" : arguments.type;
		var cacheKey = "extension-info-" & listType & "-" & ( arguments.withLogo ? "logo" : "nologo" ) & "-" & arguments.coreVersion;

		return _cachedListing( cacheKey, function() {
			var retVal = { meta={
				  title       = "Lucee Association Switzerland Extension Store (#hostName#)"
				, description = ""
				, image       = "https://#hostName#/extension/extension-provider.png"
				, url         = "https://#hostName#"
				, mode        = "production"
			} };
			try {
				retVal.extensions = variables.metaReader.list(
					  type        = listType
					, flush       = flush
					, withLogo    = withLogo
					, coreVersion = coreVersion
				);
			} catch ( e ) {
				return e;
			}
			return retVal;
		}, arguments.flush );
	}

	/**
	 * @httpmethod GET
	 * @restPath   info/{id}
	 */
	remote  function getInfoDetail(
		  required string  id                  restargsource="Path"
		, required boolean withLogo = true     restargsource="url"
		,          string  version  = ""       restargsource="url"
		,          string  coreVersion = ""    restargsource="url"
		,          boolean flush    = false    restargsource="url"
		,          string  type     = "release" restargsource="url" // the type of version to answer with when no version is given
	){
		_bind();
		var ext = _getDetail(
			  id       	    = arguments.id
			, withLogo      = arguments.withLogo
			, version       = arguments.version
			, coreVersion   = arguments.coreVersion
			, flush         = arguments.flush
			, type          = arguments.type
		);

		if ( StructCount( ext ) ) {
			return ext;
		}

		var msg = "There is no extension at this provider with id [#EncodeForHtml( arguments.id )#]";
		if ( Len( arguments.version ) ) {
			 msg &= " in version [#EncodeForHtml( arguments.version )#].";
		} else {
			msg &= ".";
		}

		_artifactNotFound( type="extension", id=arguments.id, version=arguments.version, qualifier=arguments.type );
		content type="text/plain";
		header statuscode=404 statustext="msg";
		echo( msg ); // otherwise this creates a stack trace for forgebox stuff
	}


	/**
	 * provides trial versions ??!
	 *
	 * @httpmethod GET
	 * @restPath   full/{id}
	 */
	remote function getFull(
		  required string  id               restargsource="Path"
		,          string  version = ""     restargsource="url"
		,          string  coreVersion = "" restargsource="url"
		,          boolean flush   = false  restargsource="url"
		,          string  type    = "release" restargsource="url" // the type of version to answer with when no version is given
	) {
		_bind();
		var ext = _getDetail(
			  id       = arguments.id
			, version  = arguments.version
			, coreVersion   = arguments.coreVersion
			, flush    = arguments.flush
			, withLogo = false
			, type     = arguments.type
		);

		if ( StructCount( ext ) ) {
			return _redirectToFile( ext.filename );
		}

		_artifactNotFound( type="extension", id=arguments.id, version=arguments.version, qualifier="lex" );
		header statuscode="404" statustext="Not Found";
	}

	/**
	 * provides trial versions (not sure what this is - has same logic as /full/{id})
	 *
	 * @httpmethod GET
	 * @restPath   trial/{id}
	 */
	remote function getTrial(
		  required string  id              	restargsource="Path"
		,          string  version = ""     restargsource="url"
		,          string  coreVersion = "" restargsource="url"
		,          boolean flush   = false  restargsource="url"
		,          string  type    = "release" restargsource="url" // the type of version to answer with when no version is given
	) {
		_bind();
		var ext = _getDetail(
			  id       = arguments.id
			, version  = arguments.version
			, coreVersion   = arguments.coreVersion
			, flush    = arguments.flush
			, withLogo = false
			, type     = arguments.type
		);

		if ( StructCount( ext ) ) {
			return _redirectToFile( ext.filename );
		}

		_artifactNotFound( type="extension", id=arguments.id, version=arguments.version, qualifier="lex" );
		header statuscode="404" statustext="Not Found";
	}


	/**
	 * Would be good to get rid of this?
	 *
	 * @httpmethod GET
	 * @restPath   updateCache
	 */
	remote struct function updateCache(){
		_bind();
		try {
			return {
				  meta       = {}
				, extensions = variables.metaReader.loadMeta()
			}
		} catch( any e ) {
			return e;
		}
	}

	/**
	 * Would be good to get rid of this?
	 *
	 * @httpmethod GET
	 * @restPath   reset
	 */
	remote function reset() {
		_bind();
		variables.metaReader.loadMeta();
	}

	/**
	 * Redirects to the file of an extension. A 404 when there is no url for it, which can only be in the Maven only
	 * mode (STORAGE=maven): a file that is in no Maven repository (there is no flat bucket to serve it from).
	 */
	private function _redirectToFile( required string fileName ) {
		var fileUrl = variables.metaReader.getDownloadUrl( arguments.fileName, variables.cdnURL );

		if ( !Len( fileUrl ) ) {
			_artifactNotFound( type="extension", id=arguments.fileName, qualifier="lex" );
			content type="text/plain";
			header statuscode="404" statustext="Not Found";
			echo( "The extension file [#EncodeForHtml( arguments.fileName )#] is not available from the Maven repositories" );
			return;
		}

		header statuscode="302" statustext="Found";
		header name="Location" value=fileUrl;
	}

	/**
	 * LDEV-6795: the details of an extension, empty when there is none for the arguments. That includes the
	 * case that there are versions, but none that the core version can load: that is a 404, as for a version
	 * that is not there, not an error.
	 */
	private struct function _getDetail() {
		try {
			_bind();
			return variables.metaReader.getExtensionDetail( argumentCollection=arguments );
		} catch ( any e ) {
			if ( e.message contains "No extension version available" ) {
				return {};
			}
			rethrow;
		}
	}

}
