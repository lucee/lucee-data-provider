component {
	 

	this.s3.accessKeyId = server.system.environment.S3_DOWNLOAD_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_DOWNLOAD_SECRET_KEY;

	request.s3Root="s3:///lucee-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/lucee-downloads/";

	if ( left( cgi.script_name, 5 ) neq "/rest" ) {
		location url="https://www.lucee.org" addtoken=false;
	}

}