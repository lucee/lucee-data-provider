component extends="IndexDataSupport" {

	public String function getType() {
		return "function";
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
		loop array=structKeyArray(getFunctionList()) item="local.name" {
			var row=queryAddRow(qry);
			var data=getFunctionData(name);
			
	
	// put the string together
			var str=trim("
	## Function #name#
	
	Json function library descriptor for the function #name#
	
	documentation: https://docs.lucee.org/reference/functions/#name#.html
	
	```json
	#serializeJson(var:data,compact:false)#
	```
	");
			querySetCell(qry,"title",name,row);    
			querySetCell(qry,"body",str,row);              
			querySetCell(qry,"url","https://docs.lucee.org/reference/functions/#name#.html",row);            
			// echo(markdownToHTML(str));
			// echo("<hr>");
		}
		return qry;
	}

}

