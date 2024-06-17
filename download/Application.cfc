component {
	this.name="lucee-downloads-page";

	// set via env vars
	// this.s3.accessKeyId = "";
	// this.s3.awsSecretKey = "";

	request.s3Root="s3:///extension-downloads/";
	request.s3URL="https://s3-eu-west-1.amazonaws.com/extension-downloads/";

	function onErrors(e){
		if (cgi.script_name contains "admin" or cgi.script_name contains "lucee"){
			header statuscode="418" statustext="you're a teapot";
			return;
		}
		systemOutput(e, true);
		header statuscode="500" statustext="Server error";
		echo("Sorry, Server error");
	}
}