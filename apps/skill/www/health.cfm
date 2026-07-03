<cfscript>
setting showdebugoutput=false;

downloadsDirectory = server.system.environment.DOWNLOADS_DIRECTORY ?: "";
if (!len(downloadsDirectory)) {
	downloadsDirectory = "/downloads";
}

if (!fileExists(downloadsDirectory & server.separator.file & "main.skill")) {
	header statuscode="503" statustext="Service Unavailable";
	writeOutput("main.skill not available");
	abort;
}

writeOutput("ok");
</cfscript>
