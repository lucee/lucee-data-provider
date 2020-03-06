<cfscript>

function list() {
	var qry=directoryList(path:request.s3Root,listInfo:"query",filter:function (path){
		if(right(path,4)!=".lco") return false; 
		return true;
	});

	var data={};
	loop query=qry {

		var version=mid(qry.name,1,len(qry.name)-4);
		data[version]={
			'version':version,
			'date':qry.dateLastModified,
			'size':qry.size};
	}
	dump(versions);

}
list();
 




	
</cfscript>
