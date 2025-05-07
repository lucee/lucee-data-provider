component extends="IndexDataSupport" {

	public String function getType() {
		return "recipe";
	}

	public Struct function getColumnNames() {
		return {
			"key":"url"
			,"title"="title"
			,"body"="CONTENT,keywords"
			,"custom1"="keywords"
			,"custom2"="url"
			,"custom3"="local"
			,"custom4"="hash:"&getHash()
		};
	}

	public String function getHash() {
		getData();
		return variables.hash;
	}

	public Query function loadData() {
		var index=importRecipes();
		arguments.keywordsFlat=true
        loop array=index item="local.entry" {
            if(isNull(asQry)) {
				var columns=entry.keyArray();
				var asQry=QueryNew(columns);
			}
			var row=queryAddRow(asQry);
			loop array=columns item="local.col" {
				var val=entry[col];
				if(keywordsFlat && col=="keywords" && isArray(val)) val=val.toList();
				querySetCell(asQry, col, val);
			}
        }
        return asQry;
	}


	private Array function importRecipes() {
		arguments.loadContent=true;
		var tmp=listToArray(server.lucee.version,".");
		var branch=tmp[1]&"."&tmp[2];
		
	////////// read local index ////////
		var localDirectory=expandPath("{lucee-config-dir}/recipes/");
		var localIndexPath=localDirectory&"index.json";

		// create local directory if possible and needed
		var hasLocalDir=true;
		if(!fileExists(localIndexPath)) {
			try {
				if(!directoryExists(localDirectory)) {
					directorycreate(localDirectory,true);
				}
			}
			catch(e) {
				hasLocalDir=false;
			}
		}
		var localIndex=localDirectory&"index.json";
		var first=!fileExists(localIndex);

		// load local index
		if(!first) {
			var localIndexContent=trim(fileRead(localIndex));
			var localIndexData=deserializeJSON(localIndexContent);
			var localIndexHash=hash(localIndexContent);
		}
		else {
			var localIndexContent="";
			var localIndexData=[];
			var localIndexHash="";
		}
		

	////////// read remote index ////////
		var rootPath=(server.system.environment.LUCEE_DOC_RECIPES_PATH?:"https://raw.githubusercontent.com/lucee/lucee-docs/master");
		var remoteIndexPath=rootPath&"/docs/recipes/index.json";
		var remoteIndexContent=trim(get(remoteIndexPath,createTimeSpan(0,0,0,10),""));
		var offline=false;
		if(remoteIndexContent=="") {
			remoteIndexContent=localIndexContent;
			remoteIndexData=localIndexData;
			var remoteIndexHash="";
			offline=true;
		}
		else {
			remoteIndexData=deserializeJSON(remoteIndexContent);
			var remoteIndexHash=hash(remoteIndexContent);
		}

		var indexHash=localIndexHash;
		// in case the local data differs from remote or we do not have local data at all
		if(!offline && (first || localIndexHash!=remoteIndexHash)) {
			setting requesttimeout="120";
			loop array=remoteIndexData item="local.entry" label="outer" {
				entry.url=rootPath&entry.path;
				entry.local=localDirectory&listLast(entry.file,"\/");
				if(!first) {
					loop array=localIndexData item="local.e" {
						if(e.file==entry.file) {
							if( (e.hash?:"b")==(entry.hash?:"a")) {
								if(fileExists(entry.local)) {
									entry.content=readRecipe(localDirectory&listLast(entry.file,"\/"));
									continue outer;
								}
							}
							else {
								if(fileExists(entry.local)) {
									fileDelete(entry.local);
								}
							}
						}
					}
				}
			}
			try { 
				if(hasLocalDir) {
					indexHash=remoteIndexHash;
					fileWrite(localIndex, remoteIndexContent);
				}
			}
			catch(ex2) {
				log log="application" exception=ex2;
			}
			var indexData=remoteIndexData;
		}
		// we just get the local data
		else {
			loop array=localIndexData item="local.entry" {
				entry.url=rootPath&entry.path;
                entry.local=localDirectory&listLast(entry.file,"\/");
				if(fileExists(entry.local)) {
					// read existing content from local
					entry.content=readRecipe(entry.local);
				}
			}
			var indexData=localIndexData;
		}

        // SORT
        arraySort(indexData,function(l,r) {
            return compareNoCase(l.title, r.title);
        });
		if(loadContent) {
			loop array=indexData item="local.record" {
				getContent(record);
			}
		}
		variables.hash=indexHash;
		return indexData;
	}

	private function getContent(data) {
		var cannotReach="Sorry, this recipe is not avialble at the moment";
		if(isNull(data.content) || isEmpty(data.content) || data.content==cannotReach) {
			var content=get(data.url,createTimeSpan(0,0,0,5), "");
			if(!isEmpty(content)) {
				fileWrite(data.local,content);
				data.content=readRecipe(content,true);
			}
			else {
				data.content=cannotReach;
			}
		}
		return data.content;
	}

	private function readRecipe(localFile, boolean fromContent=false) {
		var content=fromContent?localFile:fileRead(localFile);
        //var hash=hash(content,"md5");
		var endIndex=find("-->", content,4);
		if(endIndex==0) return content;
		
        //var rawMeta=trim(mid(content,startIndex+5,endIndex-(startIndex+5)));
		//var json=deserializeJSON(rawMeta);
		return trim(mid(content,endIndex+3));
    }

	

	private function get(url,timeout, defaultValue) {
		http url=arguments.url timeout=arguments.timeout result="local.res";
		
		if(res.status_code>=200 && res.status_code<300) return res.filecontent;
		return arguments.defaultValue;
	}
}

