component {
	variables.NL="
";	

	variables.cacheAppendix="s3Files1_";

	variables.columnList='id,version,versionSortable,name,description,filename,image,category,author,created,'
		& 'releaseType,minLoaderVersion,minCoreVersion,price,currency,disableFull,trial,older,olderName,olderDate,'
		& 'promotionLevel,promotionText,projectUrl,sourceUrl,documentionUrl';

	public function init(s3Root) {
		variables.s3Root=arguments.s3Root;
	}

	public void function reset() {
		lock name="cache-extension-info" timeout="5" throwOnTimeout="false" {
			var keys = structKeyArray(application);
			loop array=keys item="local.v" {
				if (findNoCase(variables.cacheAppendix,v))
					structDelete(application,v,false);
			}
		}
		readExtensions(flush=true);
	}

	public function list(required string type="all",boolean flush=false,boolean withLogo=false,boolean all=false) {
		var appName=variables.cacheAppendix&(withLogo?"wl":"nl")&"_"&arguments.type&(all?"_all":"");
		if(!flush && !isNull(application[appName])) 
			return application[appName];
		setting requesttimeout="1000";
		
		var extensions = readExtensions(arguments.flush);
		if(structKeyExists(url,"raw")) return extensions;
		if ( !arguments.withLogo ) {
			for (var row=extensions.recordcount; row >= 1; row-- ) {
				querySetCell( extensions, "image", "" , row );
			}
		}

		// type
		if ( arguments.type!="all" ) {
			for(var row=extensions.recordcount;row>=1;row--) {
				if(arguments.type=="snapshot") {
					if(!findNoCase('-SNAPSHOT',extensions.version[row])) {
						queryDeleteRow(extensions,row);
					}
				}
				else if(arguments.type=="abc") {
					if(!findNoCase('-ALPHA',extensions.version[row]) 
						&& !findNoCase('-BETA',extensions.version[row])
						&& !findNoCase('-RC',extensions.version[row])
					) {
						queryDeleteRow(extensions,row);
					}
				}
				else if(arguments.type=="release") {
					if(findNoCase('-ALPHA',extensions.version[row]) 
						|| findNoCase('-BETA',extensions.version[row])
						|| findNoCase('-RC',extensions.version[row])
						|| findNoCase('-SNAPSHOT',extensions.version[row])
					) {
						//systemOutput("delete #extensions.name[row]# #extensions.version[row]# #findNoCase('-SNAPSHOT',extensions.version[row])#", true)
						queryDeleteRow(extensions,row);
					}
				}
			}
		}
		if(structKeyExists(url,"raw2")) return extensions;
		
		if ( !arguments.all ) {
			var last="";
			var collist=queryColumnList(extensions);
			var ext=queryNew(collist);
			var older=[];
			var olderName=[];
			var olderDate=[];
			loop query=extensions {
				if(last!=extensions.id) {
					if(queryRecordcount(ext)>0 && queryCurrentrow(extensions)>1) {
						ext.older[queryRecordcount(ext)]=older;
						ext.olderName[queryRecordcount(ext)]=olderName;
						ext.olderDate[queryRecordcount(ext)]=olderDate;
						older=[];
						olderName=[];
						olderDate=[];
					}
					var row=queryAddrow(ext);
					loop list=collist item="local.col" {
						querySetCell(ext,col,extensions[col],row);
					}
				}
				else {
					if(len(extensions.version)) {
						arrayAppend(older,extensions.version);
						arrayAppend(olderName,extensions.filename);
						arrayAppend(olderDate,extensions.created);
					}
					//systemOutput("------------------------ #extensions.name# #extensions.version# -------------",true)
				}
				last=extensions.id;
			}
			var last=queryRecordcount(ext);
			if(last>0){
				ext.older[last]=older;
				ext.olderName[last]=olderName;
				ext.olderDate[last]=olderDate;
			}
			extensions=ext;
		}
		lock name="cache-extension-info" timeout="5" throwOnTimeout="false" {
			application[appName]=extensions;
		}
		return extensions;
	}

	public function detail(id,version="latest",flush=false,boolean withLogo=false) output=true {
		var list=list(flush:arguments.flush,withLogo:withLogo,all:true);
		var data=structNew("linked");
		var hasVersion=!isNull(arguments.version) &&  arguments.version!="" && arguments.version!="latest";
		loop query=list {
			if(list.id==arguments.id) {
				if(!hasVersion ||  arguments.version==list.version) {
					loop array=queryColumnArray(list) item="local.col" {
						data[col]=list[col];
					}
					return data;
				}
				
			}
		}
		var msg="There is no extension at this provider with id [#encodeForHtml(arguments.id)#]";
		if (hasVersion) msg&=" in version [#encodeForHtml(arguments.version)#].";
		else msg&=".";
		systemOutput(msg,1,1);
		content type="text/plain";
		header statuscode="404" statustext="#msg#";
		echo(msg); // otherwise this creates a stack trace for forgebox stuff
		abort;
	}

	public query function readExtensions(boolean flush){
		var rootDir = getDirectoryFromPath(getCurrentTemplatePath());
		var cacheDir=rootDir & "cache/";
		var cacheFile = "extensions.json";
		if (!directoryExists(cacheDir)) 
			directoryCreate(cacheDir);
		if ( !arguments.flush && fileExists( cacheDir & cacheFile ) ){
			systemOutput("s3Ext.list readCache",1,1);
			return deserializeJSON( fileRead(cacheDir & cacheFile), false );
		}
		setting requesttimeout="2000";
		lock name="read-extension-metadata" timeout="5" throwOnTimeout="false" {
			systemOutput("s3Ext.list START #now()#",1,1);
			var c=0;
			var jsonDir=rootDir & "extension-meta/";
			if (!directoryExists(jsonDir)) directoryCreate(jsonDir);
			var tmpDir=rootDir & "extension/";
			if (!directoryExists(tmpDir)) directoryCreate(tmpDir);
			try {
				var qry=directoryList(path:variables.s3Root,sort:"name",listInfo:"query",filter:function (path){
					return listLast(path,'.')=='lex';
				});
			} catch (e) {
				systemOutput("error directory listing extensions on s3", true);
				systemOutput(e, true);
				throw "cannot read s3 directory for extensions";
			}
			queryAddColumn(qry,"versionSortable");
			loop query=qry {
				qry.versionSortable=qry.name;
			}
			
			var extensions= querynew(variables.columnList);
			loop query=qry {
				//systemOutput(qry.name, true);
				var jsonFile=jsonDir&qry.name&".json";
				var logo=jsonDir&qry.name&".png";
				var thumb=jsonDir&qry.name&"-thumb.png";
				var mf="";
				var hasJson=fileExists(jsonFile);
				var hasLogo=fileExists(logo);
				var hasThumb=fileExists(thumb);
				var src = qry.directory & server.separator.file & qry.name;
				var tmpFile = tmpDir & server.separator.file & qry.name;
					
				if (!hasJson || !hasLogo || !fileExists(tmpFile)) {
					if (!fileExists(src)) { 
						systemOutput("error reading extension #qry.name# from s3, [#src#]", true);
						throw "error reading extension #qry.name# from s3";
					} else if (!fileExists(tmpFile)) { 
						try {
							systemOutput("downloading ext: #qry.name#", true);
							fileCopy(src,tmpFile);
							hasLogo=false;
							hasJson=false;
						} catch (e) {
							systemOutput("error copying extension  [" & qry.name & "] threw error [" & e.message & "]", true );
							systemOutput(e, true);
							throw "error copying extension #qry.name#";
						}
					}
					if (!hasJson) {
						var mf=readManifest(tmpFile);
						fileWrite(jsonFile,serializeJson(mf));
					}
					if (!hasLogo) {
						var tmp="zip://"&tmpFile&"!/META-INF/logo.png";
						if(fileExists(tmp)) {
							fileCopy(tmp,logo);
							hasLogo=true;
						}
					}
				}
				try {
					if (!hasThumb && hasLogo){
						var tmpLogo  = ImageRead( logo );
						if ( false && imageInfo( logo ).width gt 130 ) {
							imageResize( name=tmpLogo, width=130 );
						}
						// reduce colour depth to 8 bit by writing to gif
						// TODO when update provider is 5.3.8 or better use new getTempFile ext option
						var tmpGif = getTempFile( getTempDirectory(), "logo");
						var tmpGifThumb = getTempFile( getTempDirectory(), "logo") & ".gif";
						imageWrite( tmpLogo, tmpGifThumb );
						imageWrite( ImageRead( tmpGifThumb ), thumb );
						// imageWrite( tmpLogo, thumb );
						try {
							fileDelete( tmpGif );
							fileDelete( tmpGifThumb );
						} catch( e ) {
							systemOutput(e, true);
							// ignore file locking
						}
						hasThumb = true;
					}
				} catch( e ) {
					systemOutput(e, true);
					echo(e);
					// ignore image problems 
				}

				if(len(mf)==0)mf=deserializeJson(fileRead(jsonFile));

				var row=queryAddRow(extensions);
				//systemOutput("   " & row & " " & qry.name, true);
				loop list=variables.columnList item="local.col" {
					querySetCell(extensions,col,structKeyExists(mf.main,col)?mf.main[col]:'',row);
				}
				querySetCell(extensions,"filename",qry.name,row);
				querySetCell(extensions,"versionSortable",structKeyExists(mf.main,"version")?toVersionSortable(mf.main["version"]):'',row);
				
				if(!len(extensions["created"][row]) && structKeyExists(mf.main,"Built-Date")) 
					querySetCell(extensions,"created",dateAdd('s',0,mf.main['Built-Date']),row);
				if(!len(extensions["minCoreVersion"][row]) && structKeyExists(mf.main,"lucee-core-version")) 
					querySetCell(extensions,"minCoreVersion",mf.main['lucee-core-version'],row);
				if(!len(extensions["minLoaderVersion"][row]) && structKeyExists(mf.main,"lucee-loader-version")) 
					querySetCell(extensions,"minLoaderVersion",mf.main['lucee-loader-version'],row);

				if(isNull(extensions["releaseType"][row]) || len(extensions["releaseType"][row])==0) { 
					if(structKeyExists(mf.main,"release-type")) 
						querySetCell(extensions,"releaseType",mf.main['release-type'],row);
					else if(structKeyExists(mf.main,"Release-Type")) 
						querySetCell(extensions,"releaseType",mf.main['Release-Type'],row);
					else querySetCell(extensions,"releaseType","all",row);
				}

				querySetCell(extensions,"trial",false,row); // TODO

				if( hasThumb ) {
					querySetCell(extensions,"image",toBase64(fileReadBinary(thumb)),row);
				}
			}

			querySort(extensions,"name,id,versionSortable","asc,asc,desc");
			fileWrite(cacheDir & cacheFile, serializeJSON(extensions, true) );
			systemOutput("s3Ext.list FINISHED #now()#",1,1);
		}
		if ( !structKeyExists( local, "extensions" ) ){
			// lock timed out, still use cache if found
			if ( fileExists( cacheDir & cacheFile ) ){
				systemOutput("s3Ext.list readCache (after lock)",1,1);
				var extensions = deserializeJSON( fileRead(cacheDir & cacheFile), false );
			} else {
				throw "lock timeout readExtensions()";
			}
		}
		return extensions;
	}

	private function readManifest(required string path) {
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
			/* no jar or invalid jar */
		}

		// is a file!
		if(!isNull(res)){
			// is it a jar?
			try {
				var zip = ZipFile.init(FileWrapper.toFile(res));
			}catch (e) {
				/* no jar or invalid jar */
			}
			
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
				catch(e) {
					throw path;
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
		if((left(str,1)==chr(8220) || left(str,1)=='"') && (right(str,1)=='"' || right(str,1)==chr(8221)))
			str=mid(str,2,len(str)-2);
		else if(left(str,1)=="'" && right(str,1)=="'")
			str=mid(str,2,len(str)-2);
		return str;
	}

	private function toVersionSortableOld(required string version) localMode=true {
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

	private function toVersionSortable(string version){
		local.arr=listToArray(arguments.version,'.');
		//systemOutput("s3Ext.toVersionSortable #version#",1,1);

		// OSGi compatible version
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			return version;
		}
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()==2 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[2];
			if(sct.qualifier_appendix=="SNAPSHOT")sct.qualifier_appendix_nbr=0;
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else {
			sct.qualifier=isNumeric(qArr[1])?qArr[1]+0:0;
			sct.qualifier_appendix_nbr=75;
		}


		return 		repStr("0",2-len(sct.major))&sct.major
					&"."&repStr("0",3-len(sct.minor))&sct.minor
					&"."&repStr("0",3-len(sct.micro))&sct.micro
					&"."&repStr("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repStr("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}

	function repStr(str,amount) {
		if(amount<1) return "";
		return repeatString(str,amount);
	}
}



