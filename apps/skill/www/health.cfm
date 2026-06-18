<cfscript>
setting showdebugoutput=false;

if (!fileExists(expandPath("main.skill"))) {
	header statuscode="503" statustext="Service Unavailable";
	writeOutput("main.skill not available");
	abort;
}

writeOutput("ok");
</cfscript>
