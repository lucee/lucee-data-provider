component {

	variables.collectionName="luceeai";

	function init(required array arrIndexData, collectionName="luceeai") {
		variables.arrIndexData=arguments.arrIndexData;
		variables.collectionName=arguments.collectionName;
	}

	public function augment( criteria) {
		if(!searchSupported()) return arguments.criteria;	
		createIndex();

		arguments.criteria=rereplace(arguments.criteria, "([+\-&|!(){}\[\]\^""~*?:\\\/])", "\\1", "ALL");
		
		cfsearch( 
			contextpassages=3
			contextHighlightBegin="<match>" contextHighlightEnd="</match>"
			contextBytes=3000
			contextpassageLength=1000
			name="local.searchResults"
			collection=collectionName 
			criteria=criteria
			suggestions="always"
			maxrows=3);

		var augmentedQuery="User Query: #criteria#";
		var searchResultsAsArray=[];
		var total=0;
		var maxSize4Full=100;
		loop query=searchResults  {
			var cntxt=searchResults.context;
			var pass=cntxt.passages;
			var src=searchResults.custom2;
			src=replace(src,"https://raw.githubusercontent.com/lucee/lucee-docs/master/","https://github.com/lucee/lucee-docs/blob/master/");
			var arrSrc=[];
			loop query=pass {
				arrayAppend(arrSrc, [
					"start":pass.start,
					"end":pass.end,
					"score":pass.score,
					"data": pass.original
				]);
			}

			arrayAppend(searchResultsAsArray, [
				"title":searchResults.title,
				"summary":searchResults.summary,
				"keywords":searchResults.custom1,
				"source":src,
				"score":searchResults.score,
				"rank":searchResults.rank,
				"content":arrSrc
			]);
		}
		if(len(searchResultsAsArray)) {
			augmentedQuery&="
Documentation Context: #serializeJSON(searchResultsAsArray)#";
		}
		return augmentedQuery;
	}

	private function createIndex() {
		if(!searchSupported()) return;
		createCollection();
				
		// do we have already an index for this?
		cfindex( action:"list", name:"local.indexes", collection:collectionName);
		var noIndex={};
		loop query=indexes {
			loop array=arrIndexData item="local.id" {
				if(indexes.custom4=="hash:"&id.getHash()) {
					noIndex[id.getName()]=true;
					break;
				}
			}
		}

		// index data if needed
		loop array=arrIndexData item="local.id" {
			if(structKeyExists(noIndex,id.getName())) continue; 
			
			local[id.getName()]=id.getData();
			var attrColl=id.getColumnNames();
			attrColl.action="update";
			attrColl.type="custom";
			attrColl.collection=variables.collectionName;
			attrColl.query=id.getName();

			cfindex(attributeCollection=attrColl);

		}
	}


	/**
	 * create collection if needed and possible
	 */
	private function createCollection() {
		if(!searchSupported()) return;
		
		// create if needed
		collection action= "list" name="local.collections";
		var hasColl=false;
		loop query=collections {
			if(collections.name==variables.collectionName) {
				hasColl=true;
				break;
			}
		}
		if(!hasColl) {
			// collection directory
			try {
				var collDirectory=expandPath("{lucee-config-dir}/doc/search");
				if(!directoryExists(collDirectory)) {
					directoryCreate(collDirectory,true);
				}
			}
			catch(ex) {
				dump(ex);
				var collDirectory=expandPath("{temp-directory}");
			}
			// create collection TF-IDF word2vec
			/* 
			TODO  disabled due to CI running with 6.2 not 7
			cfcollection(
				action= "Create" 
				collection=collectionName 
				path=collDirectory 
				mode="hybrid"
				embedding="TF-IDF"
				ratio="0.5");
			*/
		}	
	}

	/**
	 * is the search extension installed?
	 */
	private function searchSupported() {
		var id="EFDEB172-F52E-4D84-9CD1A1F561B3DFC8";
		if(!extensionexists(id)) return false;
		
		var info=extensionInfo(id);
		var major=listFirst(info.version,".");
		return major>=3;
	}
}