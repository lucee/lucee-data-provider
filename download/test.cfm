<cfscript>
	start=getTickCount();
	UPDATE_PROVIDER="http://update.lucee.org/rest/update/provider/list?extended=true";


	http url=UPDATE_PROVIDER result="res";
	dump(getTickCount()-start);
	data=deserializeJSON(res.fileContent);
	dump(getTickCount()-start);


	to=data[1].version;
	from=data[arrayLen(data)].version;
	uri="http://snapshot.lucee.org/rest/update/provider/changelog/"&from&"/"&to;
	http url=uri result="res2";

	dump(getTickCount()-start);

	
	dump(res);
	//dump(data);
	dump(res2);


	dump(getTickCount()-start);

	
</cfscript>
