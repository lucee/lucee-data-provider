<cfscript>
setting showdebugoutput=false;
if (!structKeyExists(application, "bridgeProxy")) {
	application.bridgeProxy = new org.lucee.mavenbridge.proxy.BridgeProxy();
}
application.bridgeProxy.render(application.bridgeProxy.invoke("/"));
</cfscript>
