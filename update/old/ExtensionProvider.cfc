component restpath="/provider"  rest="true" {

	variables.EXPIRE=300*1000; // MS

	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	variables.extensionDir=variables.current&"extensions/";
	variables.ext="lex";
	application.extensionLast=0;
	variables.columnList='id,version,name,description,image,category,author,created,releaseType,minLoaderVersion,minCoreVersion'
			&',price,currency,disableFull,trial,promotionLevel,promotionText';

	private function init() {

		if(application.extensionLast>getTickCount()-variables.EXPIRE) return;
				
		directory action="list" name="local.dir" directory="#variables.extensionDir#" filter="*.#variables.ext#" sort="asc";

		// fread in all extensions (full and trial)
		var tmp.trial=structNew('linked');
		var tmp.full=structNew('linked');
		var tmp.all=structNew('linked');
		try{
		loop query="#local.dir#" {
			try{
				local.manifest=ReadManifest(variables.extensionDir&dir.name);
			}
			catch(e){
				throw "failing to read Manifest file from ["&dir.name&"] with exception:"&e.message;
			}
			local.main=manifest.main;

			// trial or full?
			local.type=!isNull(main.trial) && isBoolean(main.trial) and main.trial?"trial":"full";
			
			// there is already a extension with this id (trial|full)
			loop times="2" {
				systemOutput(type,true,true);
				if(structKeyExists(tmp[type],main.id)) {
					if(toVersionSortable(main.version)>toVersionSortable(tmp[type][main.id].manifest.version))
						tmp[type][main.id]={manifest:main,filename:dir.name};
				}
				else tmp[type][main.id]={manifest:main,filename:dir.name};
				local.type="all";
			}
		}
		}
		catch(e){
			rethrow;
			//throw serialize(e);
		}
		application.extensionLast=getTickCount();
		application.extensions=tmp;
		systemOutput(tmp,true,true);

	}
	
	/**
	* if there is a update the function is returning a struct like this:
	* {"type":"info"
	* ,"language":arguments.language
	* ,"current":arguments.version
	* ,"available":"5.0.0.1"
	* ,"message":"there is a update available for your version"
	* ,"changelog":{"2010":"eventhandling breaks property inheritance","2020":"SerializeJSON incorrecly outputs date"}
	* }
	* if there is no update, you get a struct like this:
	* {"type":"warning","message":"There is no update available for this version"}
	* 
	* @version current version installed
	* @ioid ioid of the requesting user
	* @langauage language f the requesting user
	*/
	remote struct function getInfo(
								string ioid="" restargsource="url",
								required string language="en" restargsource="url",
								required boolean withLogo=true restargsource="url")
		httpmethod="GET" restpath="info" {

		
		var rtn.meta={};
		
		rtn.meta.title="Lucee Assosication Switzerland Extension Store ("&cgi.HTTP_HOST&")";
		rtn.meta.description="";
		rtn.meta.image="http://extension.lucee.org/extension5/extension-provider.png";
		rtn.meta.url="http://"&cgi.HTTP_HOST;
		rtn.meta.mode="develop";

		init();


		// now set the query
		rtn.extensions= querynew(variables.columnList); // this must come from outsite the extension
		
		// we only show full versions in the list
		loop struct="#application.extensions.full#" index="local.id" item="local.coll" {
			local.main=coll.manifest;
			local.filename=coll.filename;
			queryAddRow(rtn.extensions);

			loop list="#rtn.extensions.columnlist()#" item="local.col" {
				querySetCell(rtn.extensions,col,structKeyExists(main,col)?main[col]:'');
			}

			if(arguments.withLogo) {
				local.logo="zip://"&variables.extensionDir&filename&"!/META-INF/logo.png";
				if(fileExists(logo)) {	
					local.hash=hash(logo,"quick");
					querySetCell(rtn.extensions,"image",toBase64(fileReadBinary(logo)));
				}
			}
			if(!len(rtn.extensions["created"]) && structKeyExists(main,"Built-Date")) 
				querySetCell(rtn.extensions,"created",dateAdd('s',0,main['Built-Date']));
			if(!len(rtn.extensions["minCoreVersion"]) && structKeyExists(main,"lucee-core-version")) 
				querySetCell(rtn.extensions,"minCoreVersion",main['lucee-core-version']);
			if(!len(rtn.extensions["minLoaderVersion"]) && structKeyExists(main,"lucee-loader-version")) 
				querySetCell(rtn.extensions,"minLoaderVersion",main['lucee-loader-version']);

			if(!len(rtn.extensions["releaseType"])) { 
				if(structKeyExists(main,"Release-Type")) querySetCell(rtn.extensions,"releaseType",main['Release-Type']);
				else querySetCell(rtn.extensions,"releaseType","all");
			}

			// does also a trial version exists?
			querySetCell(rtn.extensions,"trial",!isNull(application.extensions.trial[local.id]));

			//querySetCell(rtn.extensions,"trial",true);
		}
		
		//systemOutput(queryColumnData(rtn,'trial'),true,true);
		return rtn;
	}


	/**
	* if there is a update the function is returning a struct like this:
	* {"type":"info"
	* ,"language":arguments.language
	* ,"current":arguments.version
	* ,"available":"5.0.0.1"
	* ,"message":"there is a update available for your version"
	* ,"changelog":{"2010":"eventhandling breaks property inheritance","2020":"SerializeJSON incorrecly outputs date"}
	* }
	* if there is no update, you get a struct like this:
	* {"type":"warning","message":"There is no update available for this version"}
	* 
	* @version current version installed
	* @ioid ioid of the requesting user
	* @langauage language f the requesting user
	*/
	remote struct function getInfoDetail(
								required string id restargsource="Path",
								string ioid="" restargsource="url",
								required string language="en" restargsource="url",
								required boolean withLogo=true restargsource="url")
		httpmethod="GET" restpath="info/{id}" {

		
		var rtn={};
		
		init();

		// we only show full versions in the info
		loop struct="#application.extensions.full#" index="local.id" item="local.coll" {
			if(local.id!=arguments.id) continue;
			local.main=coll.manifest;
			local.filename=coll.filename;
			
			loop list="#variables.columnList#" item="local.col" {
				rtn[col]=structKeyExists(main,col)?main[col]:'';
			}

			if(arguments.withLogo) {
				local.logo="zip://"&variables.extensionDir&filename&"!/META-INF/logo.png";
				if(fileExists(logo)) {	
					local.hash=hash(logo,"quick");
					rtn.image=toBase64(fileReadBinary(logo));
				}
			}
			if(!len(rtn["created"]) && structKeyExists(main,"Built-Date")) 
				rtn.created=dateAdd('s',0,main['Built-Date']);
			if(!len(rtn["minCoreVersion"]) && structKeyExists(main,"lucee-core-version")) 
				rtn.minCoreVersion=main['lucee-core-version'];
			if(!len(rtn["minLoaderVersion"]) && structKeyExists(main,"lucee-loader-version")) 
				rtn.minLoaderVersion=main['lucee-loader-version'];

			if(!len(rtn["releaseType"])) { 
				if(structKeyExists(main,"Release-Type")) 
					rtn.releaseType=main['Release-Type'];
				else 
					rtn.releaseTyp="all";
			}

			// does also a trial version exists?
			rtn.trial=!isNull(application.extensions.trial[local.id]);
		}
		if(!StructCount(rtn)){	
			text="This version is not available!";
			header statuscode="404" statustext="#text#";
			echo(text);
		}
		return rtn;
	}


	/**
	* provides trial versions
	*/
	remote function getTrial(required string id restargsource="Path",string IOid="" restargsource="url")
		httpmethod="GET" restpath="trial/{id}" {
		_get(arguments.id,"trial");
	}

	/**
	* provides full versions
	*/
	remote function getFull(required string id restargsource="Path",string IOid="" restargsource="url")
		httpmethod="GET" restpath="full/{id}" {
		_get(arguments.id,"full");
	}

	private function _get(required string id, required string type) {

		// init all extensions
		init();
		
		// not found
		if(isNull(application.extensions[type][arguments.id])) {
			var other=type=="full"?"trial":"full";

			var text="extension for id ["&arguments.id&"] not found as "&type&" version";
			if(isNull(application.extensions[other][arguments.id]))
				text&=", but there is a "&other&" version available";
			else
				text&=" and there is also no "&other&" version available";

			header statuscode="404" statustext="#text#";
			echo(text);
		}
		else {
			local.data=application.extensions[type][arguments.id];
			file action="readBinary" file="#variables.extensionDir##data.filename#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#data.filename#";
	        
			content variable="#bin#" type="application/zip"; // in future version this should be handled with producer attribute
		}
	}

	private function readManifest(string path) {
		// Lucee >5 is supporting this build in
		if(left(server.lucee.version,1)>=5) return ManifestRead(path);
	
		var ResourceUtil=createObject('java','lucee.commons.io.res.util.ResourceUtil');
		var ZipFile=createObject('java','java.util.zip.ZipFile');
		var Manifest=createObject('java','java.util.jar.Manifest');
		var IOUtil=createObject('java','lucee.commons.io.IOUtil');
		var StringUtil=createObject('java','lucee.commons.lang.StringUtil');
		var FileWrapper=createObject('java','lucee.commons.io.res.util.FileWrapper');
		
		
		try {
			var res = ResourceUtil.toResourceExisting(getPageContext(), path);
		}
		catch (e) {

		/* no jar or invalid jar */}

		// is a file!
		if(!isNull(res)){
			// is it a jar?
			try {
				var zip = ZipFile.init(FileWrapper.toFile(res));
			}catch (e) {/* no jar or invalid jar */}
			
			// it is a jar
			if(!isNull(zip)) {
				try {
					var ze = zip.getEntry("META-INF/MANIFEST.MF");
					if(isNull(ze)) throw "zip file ["+str+"] has no entry with name [META-INF/MANIFEST.MF]";
					
					var is = zip.getInputStream(ze);
					manifest=Manifest.init(is);
					
				}
				finally {
					IOUtil.closeEL(is);
					IOUtil.closeEL(zip);
				}
			}
			// is it a Manifest file?
			else {
				try {
					var is=res.getInputStream();
					manifest=Manifest.init(is);
				}
				finally {
					IOUtil.closeEL(is);
				}
			}
		}
		
		// was not a file
		if(isNull(manifest)) throw "path is not a file!";
		
		var sct={};
		// set the main attributes
		_set(StringUtil,sct,"main",manifest.getMainAttributes());
		
		// all the others
		set = manifest.getEntries().entrySet();
		if(set.size()>0) {
			var it = set.iterator();
			
			var sec={};
			sct["sections"]=sec;
			var e;
			while(it.hasNext()){
				e = it.next();
				_set(StringUtil,sec,e.getKey(),e.getValue());
			}
		}
		return sct;
	}

	private function _set(StringUtil,Struct parent, String key, attrs) {
		var sct={};
		parent[key]=sct;
		
		var it = attrs.entrySet().iterator();
		while(it.hasNext()){
			var e = it.next();
			sct[e.getKey()]=unwrap(e.getValue());
		}
	}

	private function unwrap(String str) {
		str = str.trim();
		if(left(str,1)=='"' && right(str,1)=='"')
			str=mid(str,2,len(str)-2);
		else if(left(str,1)=="'" && right(str,1)=="'")
			str=mid(str,2,len(str)-2);
		return str;
	}

	private function toVersionSortable(required string version) localMode=true {
		arr=listToArray(arguments.version,'.');
		rtn="";
		loop array=arr index="i" item="v" {
			if(len(v)<5)
			 rtn&="."&repeatString("0",5-len(v))&v;
		} 
		return 	rtn;
	}
}