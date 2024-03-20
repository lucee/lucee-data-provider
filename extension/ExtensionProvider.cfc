component restpath="/provider"  rest="true" {

	variables.EXPIRE=300*1000; // MS

	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	variables.extensionDir=variables.current&"extensions/";
	variables.ext="lex";
	application._extensionLast=0;

	variables.columnList='id,version,versionSortable,name,description,image,category,author,created,releaseType,minLoaderVersion,minCoreVersion'
			&',price,currency,disableFull,trial,older,promotionLevel,promotionText,projectUrl,sourceUrl,documentionUrl';


	// new
	variables.s3Root=request.s3Root;//"s3:///lucee-downloads/";
	variables.cdnURL="https://ext.lucee.org/";
	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	

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
								required boolean withLogo=true restargsource="url",
								required string coreVersion="" restargsource="url",
								required type='release' restargsource="url",
								required boolean flush=false restargsource="url")
		httpmethod="GET" restpath="info" {


		if(findNoCase("beta.",cgi.SERVER_NAME)) arguments.type="abc";
		

		try{

		if(len(arguments.coreVersion))
			local.luceeVersion=toVersionSortable(arguments.coreVersion);
		
		var rtn.meta={};
		
		rtn.meta.title="Lucee Association Switzerland Extension Store ("&cgi.HTTP_HOST&")";
		rtn.meta.description="";
		rtn.meta.image="http://extension.lucee.org/extension5/extension-provider.png";
		rtn.meta.url="http://"&cgi.HTTP_HOST;
		rtn.meta.mode="production";
		rtn.extensions=new S3Ext(variables.s3Root)
			.list(type:arguments.type,flush:arguments.flush,withLogo:arguments.withLogo);

		}
		catch(e) {
			return e;
		}
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
	remote  function getInfoDetail(
								required string id restargsource="Path",
								string ioid="" restargsource="url",
								required string language="en" restargsource="url",
								required boolean withLogo=true restargsource="url"
								,string version="" restargsource="url"
								,string coreVersion="" restargsource="url",
								string type='release' restargsource="url",
								boolean flush=false restargsource="url")
		httpmethod="GET" restpath="info/{id}" {

			return new S3Ext(variables.s3Root)
			.detail(id:arguments.id,version:arguments.version,flush:arguments.flush,withLogo:arguments.withLogo);
	
	}


	/**
	* provides trial versions
	*/
	remote function getTrial(
		required string id restargsource="Path"
		,string IOid="" restargsource="url"
		,string version="" restargsource="url"
		,string coreVersion="" restargsource="url"
		,string type='release' restargsource="url",
		boolean flush=false restargsource="url")
		httpmethod="GET" restpath="trial/{id}" {


		var data= new S3Ext(variables.s3Root)
			.detail(id:arguments.id,version:arguments.version,flush:arguments.flush,withLogo:false);

		if (!isStruct(data)){
			header statuscode="404" statustext="Not Found";
		} else {
			header statuscode="302" statustext="Found";
			header name="Location" value=variables.cdnURL&data.filename;
		}
	}

	/**
	* provides full versions
	*/
	remote function getFull(
		required string id restargsource="Path"
		,string IOid="" restargsource="url"
		,string version="" restargsource="url"
		,string coreVersion="" restargsource="url"
		,string type='release' restargsource="url",
		boolean flush=false restargsource="url")
		httpmethod="GET" restpath="full/{id}" {

		var data= new S3Ext(variables.s3Root)
			.detail(id:arguments.id,version:arguments.version,flush:arguments.flush,withLogo:false);

		if (!isStruct(data)){
			header statuscode="404" statustext="Not Found";
		} else {
			header statuscode="302" statustext="Found";
			header name="Location" value=variables.cdnURL&data.filename;
		}
	}

	
	remote struct function updateCache()
		httpmethod="GET" restpath="updateCache" {

		try{
		
		var rtn.meta={};
		rtn.extensions=new S3Ext(variables.s3Root).readExtensions(flush=true);

		}
		catch(e) {
			return e;
		}
		return rtn;
	}

	remote function reset()
		httpmethod="GET" restpath="reset" {

		var data= new S3Ext(variables.s3Root).reset();
	}

	private function init() {

		if(application._extensionLast>getTickCount()-variables.EXPIRE) return;
				
		directory action="list" name="local.dir" directory="#variables.extensionDir#" filter="*.#variables.ext#" sort="asc";
		// read in all extensions (full and trial)
		//var tmpLatest.trial=structNew('linked');
		//var tmpLatest.full=structNew('linked');
		//var tmpLatest.all=structNew('linked');

		var tmpAll.trial=structNew('linked');
		var tmpAll.full=structNew('linked');
		var tmpAll.all=structNew('linked');

		try{
		loop query="#local.dir#" {
			// Read the Manifest
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
				
				/* latest
				if(structKeyExists(tmpLatest[type],main.id)) {
					if(toVersionSortable(main.version)>toVersionSortable(tmpLatest[type][main.id].manifest.version))
						tmpLatest[type][main.id]={manifest:main,filename:dir.name,version:toVersionSortable(main.version)};
				}
				else tmpLatest[type][main.id]={manifest:main,filename:dir.name,version:toVersionSortable(main.version)};
				*/
				// all
				if(!structKeyExists(tmpAll[type],main.id)) 
					tmpAll[type][main.id]=structNew('linked');
				tmpAll[type][main.id][toVersionSortable(main.version)]={
					manifest:main,
					filename:dir.name,
					version:toVersionSortable(main.version),
					rawversion:main.version
				};

				// next round at it to all
				local.type="all";
			}
		}
		}
		catch(e){
			rethrow;
			//throw serialize(e);
		}
		application._extensionLast=getTickCount();
		application.extensions=tmpAll;
		//application.extensionLatest=tmpLatest;
		//systemOutput(tmp,true,true);
		
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
	remote struct function getInfoOld( 
								string ioid="" restargsource="url",
								required string language="en" restargsource="url",
								required boolean withLogo=true restargsource="url",
								required string coreVersion="" restargsource="url",
								required type='release' restargsource="url")
		httpmethod="GET" restpath="info-old" {

		if(findNoCase("beta.",cgi.SERVER_NAME)) arguments.type="abc";

		if(len(arguments.coreVersion))
			local.luceeVersion=toVersionSortable(arguments.coreVersion);
		
		var rtn.meta={};
		
		rtn.meta.title="Lucee Association Switzerland Extension Store ("&cgi.HTTP_HOST&")";
		rtn.meta.description="";
		rtn.meta.image="http://extension.lucee.org/extension5/extension-provider.png";
		rtn.meta.url="http://"&cgi.HTTP_HOST;
		rtn.meta.mode="production";

		init();

		// now set the query
		rtn.extensions= querynew(variables.columnList); // this must come from outsite the extension
		
		// we only show full versions in the list
		loop struct="#application.extensions.full#" index="local.id" item="local.all" {
			local.coll=_getLatest(all,isNull(local.luceeVersion)?"":local.luceeVersion,arguments.type);
			if(isSimpleValue(coll)) {
				continue;
			}
			local.main=coll.manifest;
			local.filename=coll.filename;
			if(left(filename,1)=='_') continue;
			local.row=queryAddRow(rtn.extensions);

			loop list="#rtn.extensions.columnlist()#" item="local.col" {
				querySetCell(rtn.extensions,col,structKeyExists(main,col)?main[col]:'',row);
			}

			querySetCell(rtn.extensions,"versionSortable",structKeyExists(main,"version")?toVersionSortable(main["version"]):'',row);

			if(arguments.withLogo) {
				local.logo="zip://"&variables.extensionDir&filename&"!/META-INF/logo.png";
				if(fileExists(logo)) {	
					local.hash=hash(logo,"quick");
					querySetCell(rtn.extensions,"image",toBase64(fileReadBinary(logo)),row);
				}
			}
			if(!len(rtn.extensions["created"][row]) && structKeyExists(main,"Built-Date")) 
				querySetCell(rtn.extensions,"created",dateAdd('s',0,main['Built-Date']),row);
			if(!len(rtn.extensions["minCoreVersion"][row]) && structKeyExists(main,"lucee-core-version")) 
				querySetCell(rtn.extensions,"minCoreVersion",main['lucee-core-version'],row);
			if(!len(rtn.extensions["minLoaderVersion"][row]) && structKeyExists(main,"lucee-loader-version")) 
				querySetCell(rtn.extensions,"minLoaderVersion",main['lucee-loader-version'],row);

			if(isNull(rtn.extensions["releaseType"][row]) || len(rtn.extensions["releaseType"][row])==0) { 
				if(structKeyExists(main,"release-type")) 
					querySetCell(rtn.extensions,"releaseType",main['release-type'],row);
				else if(structKeyExists(main,"Release-Type")) 
					querySetCell(rtn.extensions,"releaseType",main['Release-Type'],row);
				else querySetCell(rtn.extensions,"releaseType","all",row);
			}
			
			// does also a trial version exists?
			querySetCell(rtn.extensions,"trial",!isNull(application.extensions.trial[local.id]),row);

			// older
			var _older=application.extensions.full[local.id];
			var arr=[];
			var v=toVersionSortable(queryGetCell(rtn.extensions,"version",row));
			loop struct=_older index="local._versionSortable" item="local._data" {
				if(v>toVersionSortable(_data.manifest.version) && typeMatch(_data.rawversion,arguments.type)) {
					arrayAppend(arr,_data.manifest.version)
				}
				
			}
			querySetCell(rtn.extensions,"older",arr,row);
		}

		return rtn;
	}

	private function _getLatest(struct all,string luceeVersion, string type) {
		var str="";
		loop struct=all index="local.v" item="local.data" {
			// min core version is bigger than given core version
			if( len(luceeVersion) &&
				!isNull(data.manifest['lucee-core-version']) && 
				toVersionSortable(data.manifest['lucee-core-version'])>luceeVersion) continue;

			if(!typeMatch(data.rawversion,type)) continue;
			str&=(isNull(rtnVersion)?"null":rtnVersion)&"<"&v&";";
			// no we pick the latest
			if(isNull(rtnVersion) || rtnVersion<v) {
				local.rtnVersion=v;
				local.rtn=data;
			}
		}
		return isNull(rtn)?"":rtn;
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
	remote  function getInfoDetailOld(
								required string id restargsource="Path",
								string ioid="" restargsource="url",
								required string language="en" restargsource="url",
								required boolean withLogo=true restargsource="url"
								,string version="" restargsource="url"
								,string coreVersion="" restargsource="url",
								string type='release' restargsource="url")
		httpmethod="GET" restpath="info-old/{id}" {

		if(len(arguments.coreVersion))
			local.luceeVersion=toVersionSortable(arguments.coreVersion);
		
		if(findNoCase("beta.",cgi.SERVER_NAME)) arguments.type="abc";
		
		local.type="full";
		var rtn={};

		init();

		// application.extensionLatest.full
		// with version defintion
		local.found=false;
		if(!isNull(arguments.version) && arguments.version.len()>0) {
			local.v=toVersionSortable(arguments.version);
			if(!isNull(application.extensions[type][arguments.id][v])) {
				local.found=true;
				local.data=application.extensions[type][arguments.id][v];
			}
		}
		// no version defintion
		else {
			local.data=_getLatest(application.extensions[type][arguments.id],isNull(local.luceeVersion)?"":local.luceeVersion,arguments.type);
			local.found=!isSimpleValue(data);
		}


		// not found
		if(!found) {
			var other=type=="full"?"trial":"full";

			var text="extension for id ["&arguments.id&"] "&(arguments.version.len()==0?"":("in version "&arguments.version))&" not found as "&type&" version";
			
			header statuscode="404" statustext="#text#";
			echo(text);
			return ;
		 }

		// we only show full versions in the info
			local.main=data.manifest;
			local.filename=data.filename;
			local.id=arguments.id;
			
			loop list="#variables.columnList#" item="local.col" {
				if(col=="older") continue;
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

			
			if(isNull(rtn["releaseType"]) || len(rtn["releaseType"])==0) { 
				if(structKeyExists(main,"release-type")) 
					rtn.releaseType=main['release-type'];
				else if(structKeyExists(main,"Release-Type")) 
					rtn.releaseType=main['Release-Type'];
				else 
					rtn.releaseType="all";
			}

			// does also a trial version exists?
			rtn.trial=!isNull(data.trial[local.id]);
		

		return rtn;
	}


	/**
	* provides trial versions
	*/
	remote function getTrialOld(
		required string id restargsource="Path"
		,string IOid="" restargsource="url"
		,string version="" restargsource="url"
		,string coreVersion="" restargsource="url"
		,string type='release' restargsource="url")
		httpmethod="GET" restpath="trial-old/{id}" {

		if(findNoCase("beta.",cgi.SERVER_NAME)) arguments.type="abc";

		_get(arguments.id,arguments.version,arguments.coreVersion,"trial",arguments.type);
	}

	/**
	* provides full versions
	*/
	remote function getFullOld(
		required string id restargsource="Path"
		,string IOid="" restargsource="url"
		,string version="" restargsource="url"
		,string coreVersion="" restargsource="url"
		,string type='release' restargsource="url")
		httpmethod="GET" restpath="full-old/{id}" {

		if(findNoCase("beta.",cgi.SERVER_NAME)) arguments.type="abc";

		_get(arguments.id,arguments.version,arguments.coreVersion,"full",arguments.type);
	}

	private function _get(required string id, required string version, string coreVersion, required string type, string verType='release') {

		if(len(arguments.coreVersion))
			local.luceeVersion=toVersionSortable(arguments.coreVersion);

		// init all extensions
		init();

		local.found=false;
		if(!isNull(application.extensions[type][arguments.id])) {

			// with version defintion
			if(arguments.version.len()>0) {
				local.v=toVersionSortable(arguments.version);
				if(!isNull(application.extensions[type][arguments.id][v])) {
					local.found=true;
					local.data=application.extensions[type][arguments.id][v];
				}
			}
			// no version defintion
			else {
				local.data=_getLatest(application.extensions[type][arguments.id],isNull(local.luceeVersion)?"":local.luceeVersion,arguments.verType);
				local.found=!isSimpleValue(data);
			}

			// write the extension to the response stream
			if(found) {
				file action="readBinary" file="#variables.extensionDir##data.filename#" variable="local.bin";
				header name="Content-disposition" value="attachment;filename=#data.filename#";
				content variable="#bin#" type="application/zip"; // in future version this should be handled with producer attribute
			}
		}

		// not found
		if(!found) {
			var other=type=="full"?"trial":"full";

			var text="extension for id ["&arguments.id&"] "&(arguments.version.len()==0?"":("in version "&arguments.version))&" not found as "&type&" version";
			
			header statuscode="404" statustext="#text#";
			echo(text);
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

	private boolean function typeMatch(version,type) {
		if(type=="all") return true;
		
		if(type=="snapshot") 
			return right(version,9)=="-snapshot";
		
		else if(type=="abc") 
			return right(version,5)=="-beta" || right(version,6)=="-alpha" || right(version,3)=="-rc";
		
		else if(type=="release") 
			return !find("-",version);
		
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
		if((left(str,1)==chr(8220) || left(str,1)=='"') && (right(str,1)=='"' || right(str,1)==chr(8221)))
			str=mid(str,2,len(str)-2);
		else if(left(str,1)=="'" && right(str,1)=="'")
			str=mid(str,2,len(str)-2);
		return str;
	}

	private function toVersionSortable(required string version) localMode=true {
		version=unwrap(version.trim());
		arr=listToArray(arguments.version,'.');
		
		// OSGi compatible version
		if(arr.len()==4 && isNumeric(arr[1]) && isNumeric(arr[2]) && isNumeric(arr[3])) {
			try{ return toOSGiVersion(version).sortable; }catch(local.e){};
		}

		rtn="";
		loop array=arr index="i" item="v" {
			if(len(v)<5)
			 rtn&="."&repeatString("0",5-len(v))&v;
			else
				rtn&="."&v;
		} 
		return 	rtn;
	}


	private struct function toOSGiVersion(required string version, boolean ignoreInvalidVersion=false){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			if(ignoreInvalidVersion) return {};
			throw "version number ["&arguments.version&"] is invalid";
		}
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()==2 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[2];
			if(sct.qualifier_appendix=="SNAPSHOT")sct.qualifier_appendix_nbr=0;
			else if(sct.qualifier_appendix=="ALPHA")sct.qualifier_appendix_nbr=40;
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else if(sct.qualifier_appendix=="RC")sct.qualifier_appendix_nbr=60;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else {
			sct.qualifier=arr[4];
			sct.qualifier_appendix_nbr=75;
		}
		sct.pure=
					sct.major
					&"."&sct.minor
					&"."&sct.micro
					&"."&sct.qualifier;
		sct.display=
					sct.pure
					&(sct.qualifier_appendix==""?"":"-"&sct.qualifier_appendix);
		
		var l1=2-len(sct.major);
		var l2=3-len(sct.minor);
		var l3=3-len(sct.micro);
		var l4=4-len(sct.qualifier);
		if(l4<0)l4=0; 
		sct.sortable=(l1>0?repeatString("0",l1):"")&sct.major
					&"."&(l2>0?repeatString("0",l2):"")&sct.minor
					&"."&(l3>0?repeatString("0",l3):"")&sct.micro
					&"."&(!isNumeric(sct.qualifier)?"":repeatString("0",l4))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;

		return sct;
	}

}
