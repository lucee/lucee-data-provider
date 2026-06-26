<cfscript>
Thread=createObject("java","java.lang.Thread");
it=Thread.getAllStackTraces().keySet().iterator();

ignores=[
	"org.apache.tomcat.util.net.NioEndpoint.serverSocketAccept"
	,"java.lang.Thread.getStackTrace(Thread.java:1559)"
	,"org.apache.tomcat.util.net.NioBlockingSelector$BlockPoller.run"
	,"org.apache.tomcat.util.net.NioEndpoint$Poller.run"
	,"org.apache.catalina.startup.Bootstrap.start"
];

// loop threads
loop collection=it item="t" label="outer" {
	st=t.getStackTrace();
	state=t.getState().toString();
	str="";
	// loop stacktraces
	loop array=st item="ste" {
		str&=ste;
		str&="
";
	}

	//if(state=="WAITING" || state=="TIMED_WAITING") continue;

	loop array=ignores item="ignore" {
		if(find(ignore,str))continue "outer";
	}
	if(isEmpty(str)) continue;

	
	echo("<h2>"&t.name&" ("&state&")</h2>");// PageContextImpl
	echo("<pre>");
	echo(str);
	echo("</pre>");
}

</cfscript>