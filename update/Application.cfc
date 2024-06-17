component {

	this.name="lucee-update-provider";

	this.s3.accessKeyId = "...";
	this.s3.awsSecretKey = "...";

	this.xmlFeatures = {
		externalGeneralEntities: false,
		secure: true,
		disallowDoctypeDecl: true
	};


	request.s3Root="s3:///lucee-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/lucee-downloads/";
		
}