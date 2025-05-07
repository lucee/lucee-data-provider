component extends="IndexDataSupport" {

	public String function getType() {
		return "tag";
	}

	public Struct function getColumnNames() {
		return {
			"key":"url"
			,"title"="title"
			,"body"="body"
			,"custom4"="hash:"&getHash()
		};
	}

	public Query function loadData() {
		var qry=queryNew(["title","body","url"]);
		loop struct=getTagList() index="local.prefix" item="local.tags" {
			loop array=StructKeyArray(tags) item="local.name" {
				var data=getTagData(prefix,name);
				var row=queryAddRow(qry);
				var str=trim("
	## Tag #prefix##name#
	
	Json tag library descriptor for the tag #prefix##name#
	
	documentation: https://docs.lucee.org/reference/tags/#name#.html
	
	```json
	#serializeJson(var:data,compact:false)#
	```
	");         querySetCell(qry,"title","#prefix##name#",row);    
				querySetCell(qry,"body",str,row);              
				querySetCell(qry,"url","https://docs.lucee.org/reference/tags/#name#.html",row);            
				//echo(markdownToHTML(str));
				
			}
		} 
		return qry;
		//
	}

}

