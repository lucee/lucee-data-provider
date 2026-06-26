<cfscript>
// Try multiple version formats
d71 = LuceeVersionsDetail("7.0.4.34");
writeDump(d71);
d62 = LuceeVersionsDetail("7.1.0.199-SNAPSHOT");
writeDump(d62);
</cfscript>
