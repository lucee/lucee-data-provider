<cfscript>
setting showdebugoutput=false;

skillFile = expandPath("main.skill");
info = {
	source: "https://docs.lucee.org/lucee.skill",
	target: "/main.skill",
	available: fileExists(skillFile)
};

if (info.available) {
	fileInfo = getFileInfo(skillFile);
	info.lastModified = fileInfo.lastModified;
	info.size = fileInfo.size;
	info.ageMinutes = dateDiff("n", fileInfo.lastModified, now());
	info.refreshInMinutes = max(0, 60 - info.ageMinutes);
}

header name="Content-Type" value="application/json; charset=utf-8";
writeOutput(serializeJSON(info));
</cfscript>
