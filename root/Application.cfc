component {

	this.name = "lucee-extension-provider";
	
	this.s3.accessKeyId = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_EXTENSION_SECRET_KEY;

	if ( left( cgi.script_name, 5 ) neq "/rest" ) {
		location url="https://www.lucee.org" addtoken=false;
	}
}