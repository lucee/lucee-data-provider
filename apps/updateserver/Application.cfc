component {

	this.name            = "lucee-provider";
	this.s3.accessKeyId  = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_EXTENSION_SECRET_KEY;
	this.allowReload     = IsBoolean( server.system.environment.ALLOW_RELOAD ?: "" ) && server.system.environment.ALLOW_RELOAD;

	function onApplicationStart() {
		_loadServices();
	}

	function onRequestStart() output=true {
		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			_loadServices();
		}

		var allowedPaths = [ "rest", "healthcheck" ];
		var requestedPath = ListFirst( Trim( cgi.script_name ), "/" );

		if ( !ArrayFindNoCase( allowedPaths, requestedPath ) ) {
			content reset=true;
			header statuscode=404;
			echo( "not found" );
			abort;
		}
	}

	function _loadServices() {
		var extS3Root    = server.system.environment.S3_EXTENSIONS_ROOT    ?: "s3:///extension-downloads/";
		var extCdnUrl    = server.system.environment.S3_EXTENSIONS_CDN_URL ?: "https://ext.lucee.org/";
		var bundleS3Root = server.system.environment.S3_BUNDLES_ROOT       ?: "s3:///bundle-download/";
		var bundleCdnUrl = server.system.environment.S3_BUNDLES_CDN_URL    ?: "https://bundle.lucee.org/";

		var extMetaReader = new services.ExtensionMetadataReader(
			s3root = extS3Root
		);
		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsCdnUrl    = extCdnUrl
			, bundleS3Root        = bundleS3Root
			, bundleCdnUrl        = bundleCdnUrl
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new services.legacy.MavenMatcher()
		);

		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		extMetaReader.loadMeta();

		application.extensionsCdnUrl      = extCdnUrl;
		application.extensionsS3Root      = extS3Root;
		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
	}

}