<cfscript>
setting showdebugoutput=false;
application.bridgeProxy.render(application.bridgeProxy.invoke("/health"));
</cfscript>
