component {
	 

	this.s3.accessKeyId = server.system.environment.S3_UPDATE_ACCESS_KEY_ID;
	this.s3.awsSecretKey = server.system.environment.S3_UPDATE_SECRET_KEY;

	request.s3Root="s3:///lucee-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/lucee-downloads/";

}