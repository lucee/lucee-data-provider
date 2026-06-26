<cfscript>
f=expandPath("/lucee-server/context/Server.cfc");
dump(f);
f=expandPath("/lucee/Server.cfc");
dump(f);
dump(fileExists(f));
dump(fileRead(f));
dump(new lucee.Server().onServerStart());


dump(server.lucee.version);
flush;




// LuceeExtension()
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	LuceeExtension();
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"LuceeExtension()",var:res);
flush;

// LuceeExtension("org.lucee")
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	artifacts=LuceeExtension("org.lucee");
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"LuceeExtension(""org.lucee"")",var:res);
flush;

// LuceeExtension("org.lucee",artifact)
res["fastest"]=1000000000;
res["slowest"]=0;
loop array=artifacts item="artifact" {
	start=getTickCount();
	
	versions=LuceeExtension("org.lucee",artifact);
	data=LuceeExtension("org.lucee",artifact,versions[len(versions)],true);
	
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
	dump(label:artifact,var:data);
	flush;
}
dump(label:"LuceeExtension(""org.lucee"",artifact)",var:res);
flush;




// LuceeExtension("io.forgebox")
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	LuceeExtension("io.forgebox");
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"LuceeExtension(""io.forgebox"")",var:res);
flush;



// LuceeVersionsList()
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	versions=LuceeVersionsList();
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"LuceeVersionsList()",var:res);
flush;



// LuceeVersionsDetail()
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	detail=LuceeVersionsDetail(versions[randrange(1,len(versions))]);
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"LuceeVersionsDetail(...)",var:res);
flush;


</cfscript>