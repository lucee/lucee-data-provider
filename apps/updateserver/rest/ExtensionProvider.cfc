/**
 * @restpath /extension/provider
 * @rest     true
 */
component {

	variables.metaReader        = application.extMetaReader;
	variables.cdnURL            = application.extensionsCdnUrl;
	variables.extensionCache    = application.extensionCache

	/**
	 * @httpmethod GET
	 * @restPath   info
	 */
	remote struct function getInfo(
		  required boolean withLogo = true      restargsource="url"
		, required string  type     = 'release' restargsource="url"
		, required boolean flush    = false     restargsource="url"
	) {
		var hostName = cgi.HTTP_HOST;
		var retVal   = { meta={
			  title       = "Lucee Association Switzerland Extension Store (#hostName#)"
			, description = ""
			, image       = "https://#hostName#/extension/extension-provider.png"
			, url         = "https://#hostName#"
			, mode        = "production"
		} };

		try {
			retVal.extensions = metaReader.list(
				  type     = ReFindNoCase( "^beta\.", hostName ) ? "abc" : arguments.type
				, flush    = arguments.flush
				, withLogo = arguments.withLogo
			);
		} catch( e ) {
			return e;
		}

		return retVal;
	}

	/**
	 * @httpmethod GET
	 * @restPath   info/{id}
	 */
	remote  function getInfoDetail(
		  required string  id               restargsource="Path"
		, required boolean withLogo = true  restargsource="url"
		,          string  version  = ""    restargsource="url"
		,          boolean flush    = false restargsource="url"
	){
		var ext = metaReader.getExtensionDetail(
			  id       = arguments.id
			, withLogo = arguments.withLogo
			, version  = arguments.version
			, flush    = arguments.flush
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
		  required string  id              restargsource="Path"
		,          string  version = ""    restargsource="url"
		,          boolean flush   = false restargsource="url"
	) {

		var ext = metaReader.getExtensionDetail(
			  id       = arguments.id
			, version  = arguments.version
			, flush    = arguments.flush
			, withLogo = false
		);

		param name="url.allowRedirect" default="";
		if ( isEmpty( url.allowRedirect ) && left( cgi.request_url, 5 ) == "http:" ){
			url.allowRedirect = false; // fall back to serving directly for older versions
		} else {
			url.allowRedirect = true;
		}

		if ( StructCount( ext ) ) {
			if ( !url.allowRedirect ){
				var path = extensionCache.getExtensionLex( variables.cdnURL & ext.filename );
				var filename = listLast( path, "/" );
				//header name="cache-control" value="public, max-age=#DateDiff( "s", Now(), expires )#";
				header name="Content-Disposition" value="attachment; filename=""#fileName#""";
				content
					reset      = true
					file       = path
					type       = "application/x-zip-compressed"
					deletefile = false;
			}
			header statuscode="302" statustext="Found";
			header name="Location" value=variables.cdnURL & ext.filename;
			return;
		}

		header statuscode="404" statustext="Not Found";
	}

	/**
	 * provides trial versions (not sure what this is - has same logic as /full/{id})
	 *
	 * @httpmethod GET
	 * @restPath   trial/{id}
	 */
	remote function getTrial(
		  required string  id              restargsource="Path"
		,          string  version = ""    restargsource="url"
		,          boolean flush   = false restargsource="url"
	) {

		var ext = metaReader.getExtensionDetail(
			  id       = arguments.id
			, version  = arguments.version
			, flush    = arguments.flush
			, withLogo = false
		);

		if ( StructCount( ext ) ) {
			header statuscode="302" statustext="Found";
			header name="Location" value=variables.cdnURL & ext.filename;
			return;
		}

		header statuscode="404" statustext="Not Found";
	}


	/**
	 * Would be good to get rid of this?
	 *
	 * @httpmethod GET
	 * @restPath   updateCache
	 */
	remote struct function updateCache(){
		try {
			return {
				  meta       = {}
				, extensions = metaReader.loadMeta()
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
		metaReader.loadMeta();
	}
}