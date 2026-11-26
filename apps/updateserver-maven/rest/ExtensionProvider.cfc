/**
 * @restpath /extension/provider
 * @rest     true
 */
component {

	variables.bound = false;

	private boolean function _servicesReady() {
		return IsBoolean( application.servicesReady ?: false ) && application.servicesReady;
	}

	// requests only get here once the services are ready (Application.cfc answers 503 before that), the wait only
	// covers a request that was let in just before a reload
	private function _ensureServices( numeric timeoutMs=5000 ) {
		if ( variables.bound && _servicesReady() ) {
			return;
		}

		var started = GetTickCount();
		while ( !_servicesReady() && ( GetTickCount() - started ) < arguments.timeoutMs ) {
			if ( Len( application.servicesError ?: "" ) ) {
				throw( message="Maven provider services failed to load, retrying shortly: #application.servicesError#" );
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
	remote function getInfo(
		  required boolean withLogo     = true      restargsource="url"
		, required string  type         = 'release' restargsource="url"
		, required boolean flush        = false     restargsource="url"
		, required string  coreVersion  = ''        restargsource="url"
	) {
		var hostName = cgi.HTTP_HOST;
		var listType = ReFindNoCase( "^beta\.", hostName ) ? "abc" : arguments.type;
		var logo     = arguments.withLogo;
		var core     = arguments.coreVersion;

		// a client that asks for another format than JSON (Accept header, or a format extension of the url) gets the
		// response the REST layer serialises, as before
		if ( !_wantsJson() ) {
			return _infoStruct( hostName, listType, logo, core, false );
		}

		try {
			_bind();
			// flush is accepted and ignored: the meta and the listings are refreshed in the background (TTL), a
			// request never forces a rebuild. A stale meta is refreshed in the background, the listing below is
			// rebuilt once that changed it.
			variables.metaReader.refreshIfStale();

			var entry = _listingJson( listType, logo, core, false );

			// the host is part of the response (META), so it is part of the ETag
			var etag    = services.HttpCaching::weakEtag( entry.etag & "|" & hostName );
			var headers = _cacheHeaders( etag, entry.builtAt );
			if ( services.HttpCaching::isNotModified(
				  ifNoneMatch     = _requestHeader( "If-None-Match" )
				, ifModifiedSince = _requestHeader( "If-Modified-Since" )
				, etag            = etag
				, lastModified    = entry.builtAt
			) ) {
				RestSetResponse( { status=304, headers=headers } );
				return;
			}

			// META (title, image, url) is built from the current hostName on every request, it is small; the
			// cached listing is put in as it is, so the response is the same as serialising the whole struct
			var body = Replace( SerializeJSON( {
				  meta       = _infoMeta( hostName )
				, extensions = variables.listingPlaceholder
			}, "row" ), '"' & variables.listingPlaceholder & '"', entry.json, "one" );

			headers[ "Content-Type" ] = "application/json;charset=UTF-8";
			RestSetResponse( { status=200, content=body, headers=headers } );
		} catch ( any e ) {
			// not cached: the next request tries again
			return e;
		}
	}

	private string function _requestHeader( required string name ) {
		var headers = GetHttpRequestData( false ).headers;

		return StructKeyExists( headers, arguments.name ) ? Trim( headers[ arguments.name ] ) : "";
	}

	// ETag, Cache-Control and (when known) Last-Modified of a JSON response; it depends on the Accept header too
	private struct function _cacheHeaders( required string etag, any lastModified="" ) {
		var headers = {
			  "ETag"          = arguments.etag
			, "Cache-Control" = services.HttpCaching::cacheControl()
			, "Vary"          = "Accept, Accept-Encoding"
		};
		if ( IsDate( arguments.lastModified ) ) {
			headers[ "Last-Modified" ] = services.HttpCaching::httpDate( arguments.lastModified );
		}

		return headers;
	}

	// the response as a struct, for the REST layer to serialise in the format the client asked for
	private any function _infoStruct( required string hostName, required string listType, required boolean withLogo, required string coreVersion, boolean flush=false ) {
		try {
			_bind();
			variables.metaReader.refreshIfStale( force=arguments.flush );
			return {
				  meta       = _infoMeta( arguments.hostName )
				, extensions = variables.metaReader.list( type=arguments.listType, withLogo=arguments.withLogo, coreVersion=arguments.coreVersion )
			};
		} catch ( any e ) {
			return e;
		}
	}

	private struct function _infoMeta( required string hostName ) {
		return {
			  title       = "Lucee Association Switzerland Extension Store (#arguments.hostName#)"
			, description = ""
			, image       = "https://#arguments.hostName#/extension/extension-provider.png"
			, url         = "https://#arguments.hostName#"
			, mode        = "production"
		};
	}

	// Does the client get JSON from the REST layer? Yes without an Accept header, with one that names JSON, or the
	// any type wildcard without a type the REST layer would prefer. Not with a format extension in the url (info.xml).
	private boolean function _wantsJson() {
		var last = ListLast( cgi.path_info ?: "", "/" );
		if ( Find( ".", last ) ) {
			return false;
		}

		var accept = LCase( Trim( cgi.http_accept ?: "" ) );
		if ( !Len( accept ) || Find( "json", accept ) ) {
			return true;
		}
		if ( ReFind( "cfml|wddx|xml|text/plain", accept ) ) {
			return false;
		}

		return Find( "*/*", accept ) > 0;
	}

	variables.listingPlaceholder = "__LUCEE_PROVIDER_EXTENSIONS_" & Replace( CreateUUID(), "-", "", "all" ) & "__";

	/**
	 * The serialised extension listing, from memory. Keyed by the bucket of the core version (core versions that
	 * get the same listing share one entry, see ExtensionMetadataReader.coreVersionBucket()), rebuilt in the
	 * background once the meta changed.
	 */
	private struct function _listingJson( required string listType, required boolean withLogo, required string coreVersion, boolean force=false ) {
		var reader = variables.metaReader;
		var type   = arguments.listType;
		var logo   = arguments.withLogo;
		var core   = arguments.coreVersion;
		var key    = type & "|" & ( logo ? "logo" : "nologo" ) & "|" & reader.coreVersionBucket( core );

		return application.infoListingCache.get(
			  key        = key
			, generation = reader.getMetaGeneration()
			, producer   = function() {
				return SerializeJSON( reader.list( type=type, withLogo=logo, coreVersion=core ), "row" );
			}
			, force      = arguments.force
		);
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
			, flush         = false // flush is ignored, see getInfo
			, type          = arguments.type
		);

		if ( StructCount( ext ) ) {
			if ( !_wantsJson() ) {
				return ext;
			}
			// the same JSON the REST layer writes for the struct, with an ETag so a client can ask again cheaply
			var body    = SerializeJSON( ext );
			var etag    = services.HttpCaching::weakEtag( body );
			var headers = _cacheHeaders( etag );
			if ( services.HttpCaching::isNotModified( ifNoneMatch=_requestHeader( "If-None-Match" ), etag=etag ) ) {
				RestSetResponse( { status=304, headers=headers } );
				return;
			}
			headers[ "Content-Type" ] = "application/json;charset=UTF-8";
			RestSetResponse( { status=200, content=body, headers=headers } );
			return;
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
			, flush    = false // flush is ignored, see getInfo
			, withLogo = false
			, type     = arguments.type
		);

		if ( StructCount( ext ) ) {
			return _redirectToFile( ext.filename, arguments.version );
		}

		_artifactNotFound( type="extension", id=arguments.id, version=arguments.version, qualifier="lex" );
		header statuscode="404" statustext="Not Found";
		header name="Cache-Control" value=services.DownloadCaching::forNotFound();
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
			, flush    = false // flush is ignored, see getInfo
			, withLogo = false
			, type     = arguments.type
		);

		if ( StructCount( ext ) ) {
			return _redirectToFile( ext.filename, arguments.version );
		}

		_artifactNotFound( type="extension", id=arguments.id, version=arguments.version, qualifier="lex" );
		header statuscode="404" statustext="Not Found";
		header name="Cache-Control" value=services.DownloadCaching::forNotFound();
	}


	/**
	 * Kept for the callers that still ask for it, does nothing: the extension meta and the listings are refreshed
	 * in the background (see ExtensionMetadataReader.refreshIfStale and the listing cache).
	 *
	 * @httpmethod GET
	 * @restPath   updateCache
	 */
	remote function updateCache() {
		_noRefreshNeeded();
	}

	/**
	 * Kept for the callers that still ask for it (the Lucee build calls it after a publish), does nothing, see updateCache.
	 *
	 * @httpmethod GET
	 * @restPath   reset
	 */
	remote function reset() {
		_noRefreshNeeded();
	}

	private void function _noRefreshNeeded() {
		RestSetResponse( {
			  status  = 200
			, content = "Nothing to do, the extension listing is refreshed in the background"
			, headers = { "Content-Type" = "text/plain;charset=UTF-8", "Cache-Control" = "no-store" }
		} );
	}

	/**
	 * Redirects to the file of an extension. A 404 when there is no url for it, which can only be in the Maven only
	 * mode (STORAGE=maven): a file that is in no Maven repository (there is no flat bucket to serve it from).
	 */
	private function _redirectToFile( required string fileName, string version="" ) {
		var fileUrl = variables.metaReader.getDownloadUrl( arguments.fileName, variables.cdnURL );

		if ( !Len( fileUrl ) ) {
			_artifactNotFound( type="extension", id=arguments.fileName, qualifier="lex" );
			content type="text/plain";
			header statuscode="404" statustext="Not Found";
			header name="Cache-Control" value=services.DownloadCaching::forNotFound();
			echo( "The extension file [#EncodeForHtml( arguments.fileName )#] is not available from the Maven repositories" );
			return;
		}

		header statuscode="302" statustext="Found";
		header name="Location" value=fileUrl;
		// a client (or a cache in between) can follow the same redirect again without asking, see DownloadCaching
		header name="Cache-Control" value=services.DownloadCaching::forRedirect( arguments.version );
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
