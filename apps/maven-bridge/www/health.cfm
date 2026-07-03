<cfscript>
setting showdebugoutput=false;
server.bridgeProxy.render(server.bridgeProxy.invoke("/health"));
</cfscript>
