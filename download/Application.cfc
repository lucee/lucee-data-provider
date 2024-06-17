component {
	this.name="lucee-downloads-page";

	this.xmlFeatures = {
		externalGeneralEntities: false,
		secure: true,
		disallowDoctypeDecl: true
	};


	//this.s3.accessKeyId = server.system.environment.S3_DOWNLOAD_ACCESS_KEY_ID;
	//this.s3.awsSecretKey = server.system.environment.S3_DOWNLOAD_SECRET_KEY;

	request.s3Root="s3:///extension-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/extension-downloads/";

	function onError(e){
 	   if (cgi.script_name contains "admin" or cgi.script_name contains "lucee"){
            header statuscode="418" statustext="nice try, you're a teapot";
            return;
        }
	    header statuscode="500" statustext="Server error";
        echo("Sorry, Server error");
    }
		
}