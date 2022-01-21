component {
    request.s3Root  = server.system.environment["LUCEE_DATA_PROVIDER_S3ROOT"] ?: "s3:///lucee-downloads/";
	request.s3URL   = server.system.environment["LUCEE_DATA_PROVIDER_S3URL"] ?: "https://s3-eu-west-1.amazonaws.com/lucee-downloads/";
}