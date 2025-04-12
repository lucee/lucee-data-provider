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

	function onApplicationStart() {
		lock name="configure-sentry" type="exclusive" timeout=5{
			// workaround for LDEV-5371
			// if LUCEE_LOGGING_FORCE_APPENDER=console is set, sentry is bypassed
			var deploy = expandPath( '{lucee-server}/../deploy/' );
			var sentry_json = deploy & "/.CFconfig-sentry.json"; 
			if ( FileExists( sentry_json ) ){
				configImport( sentry_json, "server", "admin" );
				systemOutput("sentry.json loaded via configImport - LDEV-5371", true);
				fileDelete( sentry_json );
			}
		}
		application.extensionMeta = deserializeJson(fileRead("extensionMeta.json"));
	}

	function onError(e){
 		if (cgi.script_name contains "admin" or cgi.script_name contains "lucee"){
			header statuscode="418" statustext="nice try, you're a teapot";
			return;
		}
		header statuscode="500" statustext="Server error";
		echo("Sorry, Server error");
	}

	function onRequest( string requestedPath ) output=true {
		if ( arguments.requestedPath == "/index.cfm"
				&& ( structCount( url ) == 0 || cgi.query_string == "type=snapshots&reset=force" ) ) {
			var tmpFile = getTempDirectory() & "/cachedhomepage.html";

			if ( StructKeyExists( url, "reset" ) || !FileExists( tmpFile ) ) {
				var pageContent = "";
				savecontent variable="pageContent" {
					include template=arguments.requestedPath;
				}
				FileWrite( tmpFile, Trim( pageContent ) );
				echo( Trim( pageContent ) );
				return;
			}
			echo( FileRead( tmpFile ) );
			return;
		}

		include template=arguments.requestedPath;
	}

}