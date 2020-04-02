<cfscript>        
    request.changelogs = true;
    param name="url.type" default="releases";
    if (not ListFind("releases,snapshots,rc,beta", url.type))
        location url="#cgi.script_name#?type=releases" addtoken=false;    
    cfinclude(template="index.cfm");
</cfscript>