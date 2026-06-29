<cfscript>

setting requestTimeout=10000;
dump(var:server,expand:false);

started=getPageContext().getConfig().getFactory().getEngine().uptime();
started=dateAdd('l',started,createDateTime(1970,1,1,0,0,0,0,"UTC")) ;

dump(dateDiff("s",started,now())&" sec")
dump(dateDiff("n",started,now())&" min")
dump(dateDiff("h",started,now())&" h")

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
dump(label:"1 - LuceeExtension()",var:res);
flush;

// LuceeExtension("io.forgebox")
res["fastest"]=1000000000;
res["slowest"]=0;
loop times=5 {
	start=getTickCount();
	artifacts=LuceeExtension("io.forgebox");
	result=getTickCount()-start;
	if(res.slowest<result)res.slowest=result;
	if(res.fastest>result)res.fastest=result;
}
dump(label:"2 - LuceeExtension(""io.forgebox"")",var:res);
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
dump(label:"3 - LuceeExtension(""org.lucee"")",var:res);
flush;




// LuceeExtension("org.lucee",artifact)
allVersions=[:];
loop array=artifacts item="artifact" {
	res["fastest"]=1000000000;
	res["slowest"]=0;
	loop times=5 {
		start=getTickCount();
		versions=LuceeExtension("org.lucee",artifact);
		allVersions[artifact]=versions;
		result=getTickCount()-start;
		if(res.slowest<result)res.slowest=result;
		if(res.fastest>result)res.fastest=result;
	}
	dump(label:"4 - LuceeExtension(""org.lucee"",""#artifact#"")",var:res);
	flush;
}
//dump(label:"LuceeExtension(""org.lucee"",artifact)",var:res);
flush;


// LuceeExtension("org.lucee",artifact)

loop struct=allVersions index="artifact" item="versions" {
	loop array=versions item="version" {
		res["fastest"]=1000000000;
		res["slowest"]=0;
		try{
		loop times=5 {
			start=getTickCount();
			versions=LuceeExtension("org.lucee",artifact,version);
			result=getTickCount()-start;
			if(res.slowest<result)res.slowest=result;
			if(res.fastest>result)res.fastest=result;
		}
		}
		catch(ex) {
			echo(ex);
		}
		dump(label:"LuceeExtension(""org.lucee"",""#artifact#"",#version#)",var:res);
		
	}flush;
}





abort;










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
abort;



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