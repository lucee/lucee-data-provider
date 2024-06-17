component {

	this.name = "lucee-extension-provider";

	
	this.s3.accessKeyId = server.system.environment.S3_EXTENSION_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_EXTENSION_SECRET_KEY;

	request.s3Root="s3:///extension-downloads/";
	request.s3URL="https://ext.lucee.org/";
		
}