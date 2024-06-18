component {

	this.name            = "lucee-provider";
	this.s3.accessKeyId  = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_EXTENSION_SECRET_KEY;

	function onApplicationStart() {
		application.cdnUrl = server.system.environment.S3_CDN_URL ?: "https://ext.lucee.org/";
		_loadReader();
	}

	function onRequestStart() {
		if ( StructKeyExists( url, "fwreinit" ) ) {
			_loadReader();
		}

		if ( Left( cgi.script_name, 5 ) != "/rest" ) {
			location url="https://www.lucee.org" addtoken=false;
		}
	}

	function _loadReader() {
		var extMetaReader = new extension.services.ExtensionMetadataReader(
			s3root = server.system.environment.S3_BUCKET_ROOT ?: "s3:///extension-downloads/"
		);
		extMetaReader.loadMeta();

		application.extMetaReader = extMetaReader;
	}

}