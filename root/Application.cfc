component {

	this.name            = "lucee-provider";
	this.s3.accessKeyId  = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_EXTENSION_SECRET_KEY;
	this.allowReload     = IsBoolean( server.system.environment.ALLOW_RELOAD ?: "" ) && server.system.environment.ALLOW_RELOAD;

	function onApplicationStart() {
		_loadServices();
	}

	function onRequestStart() {
		if ( this.allowReload && StructKeyExists( url, "fwreinit" ) ) {
			_loadServices();
		}

		if ( Left( cgi.script_name, 5 ) != "/rest" ) {
			location url="https://www.lucee.org" addtoken=false;
		}
	}

	function _loadServices() {
		var extS3Root = server.system.environment.S3_EXTENSIONS_ROOT    ?: "s3:///extension-downloads/";
		var extCdnUrl = server.system.environment.S3_EXTENSIONS_CDN_URL ?: "https://ext.lucee.org/";

		var extMetaReader = new services.ExtensionMetadataReader(
			s3root = extS3Root
		);
		var bundleDownloadService = new services.BundleDownloadService(
			  extensionsS3root    = extS3Root
			, extensionsCdnUrl    = extCdnUrl
			, extensionMetaReader = extMetaReader
			, mavenMatcher        = new update.MavenMatcher()
		);

		extMetaReader.setBundleDownloadservice( bundleDownloadService );
		extMetaReader.loadMeta();

		application.extensionsCdnUrl      = extCdnUrl;
		application.extMetaReader         = extMetaReader;
		application.bundleDownloadService = bundleDownloadService;
	}

}