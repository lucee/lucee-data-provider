<cfscript>



if(!isNull(url.showAll)) {
	cookie['showAll_'&url.type]=url.showAll;
}

if(isNull(cookie.showAll_snapshots))cookie.showAll_snapshots=false;
if(isNull(cookie.showAll_releases))cookie.showAll_releases=false;

cacheLiveSpanInMinutes=5;
extcacheLiveSpanInMinutes=1000;
snapshots="https://release.lucee.org";
_url={
	releases:"https://release.lucee.org"
	,abc:"https://release.lucee.org"
	,beta:"https://release.lucee.org"
	,rc:"https://release.lucee.org"
	,snapshots:snapshots
};



UPDATE_PROVIDER="http://update.lucee.org/rest/update/provider/list?extended=true";
EXTENSION_PROVIDER="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=release";
EXTENSION_PROVIDER_ABC="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=abc";
EXTENSION_PROVIDER_SNAPSHOT="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=snapshot";
EXTENSION_DOWNLOAD="https://extension.lucee.org/rest/extension/provider/{type}/{id}";

// texts

// Releases are deeply tested. Releases are recommended for production environments.

jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
lang.desc={
	abc:"Beta and Release Candidates are a preview for upcoming versions and not ready for production environments."
	,beta:"Beta are a preview for upcoming versions and not ready for production environments."
	,rc:"Release Candidates are candidates to get ready for production environments."
	,releases:"Releases are ready for production environments."
	,snapshots:"Snapshots are generated automatically with every push to the repository. 
	Snapshots can be unstable are NOT recommended for production environments."
};

lang.express="The Express version is an easy to setup version which does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially useful if you would like to get to know Lucee or want to test your applications under Lucee. It is also useful for use as a development environment.";
lang.war='Java Servlet engine Web ARchive';
lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
lang.jar='Lucee jar file without dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.';
lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';

lang.lib="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).";
lang.libNew="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary. You can have this Jar in 2 flavors, a version containing all Core Extension (like Hibernate, Lucene or Axis) and a version with no Extension bundled.";

lang.installer.win="Windows";
lang.installer.lin64="Linux (64b)";
lang.installer.lin32="Linux (32b)";

	function toVersionSortable(required string version){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()>4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			throw "version number ["&arguments.version&"] is invalid";
		}
		if(arr.len()==3) arrayAppend(arr,0); 
		if(arr.len()==3) arrayAppend(arr,0); 
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()>1 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[qArr.len()];
			if(sct.qualifier_appendix=="SNAPSHOT")sct.qualifier_appendix_nbr=0;
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT

			sct.qualifier_appendix=listRest(arr[4],'-');
		}
		else throw "version number ["&arguments.version&"] is invalid";
		


		return 		repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}

	function toVersionWithoutAppendix(required string version){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			throw "version number ["&arguments.version&"] is invalid";
		}
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()>=1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else throw "version number ["&arguments.version&"] is invalid";
		
		return 	sct.major&"."&sct.minor&"."&sct.micro&"."&sct.qualifier;
	}

	private function toKeySortable(key) {
		var arr=listToArray(key,'-');
		while(len(arr[2])<5) {
			arr[2]="0"&arr[2];
		}
		return arr[1]&"-"&arr[2];
	}

	query function getDownloadFor(type) {
		if(isNull(url.reset) && !isNull(application.download[arguments.type]))
			return application.download[arguments.type];

		var tmpDownloads=getDownloads();
		var downloads=queryNew(tmpDownloads.columnlist);
		var arrColumns=tmpDownloads.columnArray();
		
		loop query=tmpDownloads {
			if(
				( arguments.type==tmpDownloads.type && tmpDownloads.state=="" )
				||
				( arguments.type=="abc" && tmpDownloads.state!="" )
				||
				( arguments.type=="beta" && tmpDownloads.state=="beta" ) 
				||
				( arguments.type=="rc" && tmpDownloads.state=="rc" ) 
			) {
				var row=downloads.addRow();
				loop array=arrColumns item="col" {
					if(col=="changelog") {
						var _changelog=tmpDownloads[col];
						if(!isStruct(_changelog))_changelog={};
						else _changelog=duplicate(_changelog);
						downloads.setCell(col,_changelog,row);
					}
					else downloads.setCell(col,tmpDownloads[col],row);
				}
				//downloads.setCell('test',listLen(tmpDownloads.version,'-'),row);

				if(downloads.recordcount>=MAX) break;
			}
			else if(!isNull(_changelog) && isStruct(tmpDownloads.changelog)) {
				loop struct=tmpDownloads.changelog index="key" item="ver" {
					_changelog[key]=ver;
				}
			}
		}
		if(!isNull(url.kkk)){dump(downloads);abort;}
		if(queryColumnExists(downloads,"changelog")) {
			loop query=downloads {
				var cl=downloads.changelog;
				if(isStruct(cl) && structCount(cl)>1) {
					var q=queryNew('k,ks,v');
					loop struct=cl index="local.key" item="local.val" {
						var r=queryAddRow(q);
						querySetCell(q,"k",key,r);
						querySetCell(q,"ks",toKeySortable(key),r);
						querySetCell(q,"v",val,r);
					}
					querySort(q,"ks","desc");
					var sct=structNew("linked");
					loop query=q {
						sct[q.k]=q.v;
					}
					downloads.changelog=sct;
				}
			}
		}
		application.download[arguments.type]=downloads;
		return downloads;
	}


	struct function getLatestDownloads() {
		//if(isNull(url.reset) && !isNull(application.latestDownloads))
		//	return application.latestDownloads;


		var downloads=getDownloads();
		//var rtn=queryNew(downloads.columnlist);
		var sct={};
		loop query=downloads {
			if("snapshots"==downloads.type) {
				if(isNull(sct.snapshots) || sct.snapshots.vs<downloads.vs) {
					sct.snapshots=toStruct(downloads,downloads.currentrow);
				}
			}
			else if("beta"==downloads.state){
				if(isNull(sct.beta) || sct.beta.vs<downloads.vs) {
					sct.beta=toStruct(downloads,downloads.currentrow);
				}
			}
			else if("rc"==downloads.state){
				if(isNull(sct.rc) || sct.rc.vs<downloads.vs) {
					sct.rc=toStruct(downloads,downloads.currentrow);
				}
			}
			else if(""==downloads.state){
				if(isNull(sct.releases) || sct.releases.vs<downloads.vs) {
					sct.releases=toStruct(downloads,downloads.currentrow);
				}
			}
		}

		application.latestDownload=sct;
		return sct;
	}

	function toStruct(qry,row) {
		var sct={};
		loop array=queryColumnArray(qry) item="local.k" {
			sct[k]=qry[k][row];
		}
		return sct;
	}

	query function getDownloads() {
		setting requesttimeout="1000";
		// get data from server
		var path=getDirectoryFromPath(getCurrentTemplatePath())&"downloads.ser";
		var force=!isNull(url.reset) && url.reset=='force';


		if(isNull(application.download) || force) {
			if(fileExists(path) && !force) {
				var c=fileRead(path);
				application.download.query=evaluate(c);
				local.tmp=-cacheLiveSpanInMinutes;
				tmp++;	
				application.download.age=dateAdd("n",tmp,now());
			}
			else {
				application.download.query=_download();
				application.download.age=now();
			}

		}
		// get data from cache (application scope)
		else {
			// update for the next user when older than 5 minutes
			if(!isNull(url.reset)) {
				application.download.age=now();
				thread name="t-#getTickCount()#" {
					setting requesttimeout=1000000;
					application.download.query=_download();
				}
			}
		}
		//fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"downloads.ser",serialize(application.download.query));

		return application.download.query;
	}


	query function merge(qry) {
		var dir=getDirectoryFromPath(getCurrentTemplatePath());
		var file=dir&"downloads.ser";
		if(!fileExists(file)) return qry;
		
		// existing
		var c=fileRead(file);
		var qryEx=evaluate(c);
		var sct={};
		loop query=qryEx {
			sct[qryEx.version]=querySlice(qryEx,qryEx.currentrow,1);
		}

		// new
		loop query=qry {
			sct[qry.version]=querySlice(qry,qry.currentrow,1);
		}

		// now convert back to a query
		var colNames=qry.columnlist;
		var qryNew=queryNew(colNames);
		loop struct=sct index="local.k" item="local.q" {
			var row=queryAddRow(qryNew);
			loop list=colNames item="local.colName" {
				querySetCell(qryNew,colName,q[colName],row);
			}
		}
		return qryNew;
	}

	query function _download() {

		var n=now();
		lock name="download-#year(n)&":"&month(n)&":"&day(n)&":"&hour(n)#" timeout=100 {
			try{
				flush;
				local.start=getTickCount();
				
				http url=UPDATE_PROVIDER result="local.res";
				var arr=deserializeJSON(res.fileContent);
				var qry=queryNew('id,groupId,artifactId,version,vs,type,jarDate,src,s3War,s3Express,s3Light,s3Core,state,t');
				for(var r=arrayLen(arr);r>=1;r--) {
					row=arr[r];
					
					var date="";
					if(!isNull(row.date)) date=parseDateTime(row.date);
					else if(!isNull(row.sources.jar.date)) date=parseDateTime(row.sources.jar.date);
					else if(!isNull(row.sources.pom.date)) date=parseDateTime(row.sources.pom.date);

					if(!isDate(date)) continue;

					//dump(row.sources);abort;
					qr=queryAddRow(qry);
					querySetCell(qry,"groupId",row.groupId,qr);
					querySetCell(qry,"artifactId",row.artifactId,qr);
					querySetCell(qry,"version",row.version,qr);
					querySetCell(qry,"vs",row.vs,qr);
					querySetCell(qry,"type",listLast(row.repository,'/'),qr);
					querySetCell(qry,"src",row.sources.jar.src?:"",qr);
					querySetCell(qry,"s3War",row.s3War,qr);
					querySetCell(qry,"s3Express",row.s3Express,qr);
					querySetCell(qry,"s3Light",row.s3Light,qr);
					querySetCell(qry,"s3Core",row.s3Core,qr);

					if(findNoCase("snapshot",row.version)) {
						querySetCell(qry,"t","snapshots",qr);
					}
					else if(findNoCase("alpha",row.version)) {
						querySetCell(qry,"state","alpha",qr); 
						querySetCell(qry,"t","alpha",qr);
					}
					else if(findNoCase("beta",row.version)) {
						querySetCell(qry,"state","beta",qr);
						querySetCell(qry,"t","beta",qr);
					}
					else if(findNoCase("rc",row.version) || findNoCase("ReleaseCandidate",row.version)) {
						querySetCell(qry,"state","rc",qr);
						querySetCell(qry,"t","rc",qr);
					}
					else {
						querySetCell(qry,"t","releases",qr);
					}

					
					// state
					

					
					querySetCell(qry,"jarDate",date,qr);
					querySetCell(qry,"id",hash(row.version&":"&date),qr);



					//querySetCell(qry,"pomSrc",row.sources.pom.src);
					//querySetCell(qry,"pomDate",parseDateTime(row.sources.pom.date));
					
				}

				// add version that can be sorted right (5.0.0.1-SNAPSHOT -> 5.000.000.0001-SNAPSHOT)
				//queryAddColumn(qry,"v");
				queryAddColumn(qry,"versionNoAppendix");
				loop query=qry {
					//qry.v[qry.currentrow]=toVersionSortable(qry.version);
					qry.versionNoAppendix[qry.currentrow]=toVersionWithoutAppendix(qry.version);
				}
				// merge with existing data (if exist), because sometime maven does not deliver all data
				//qry=merge(qry);
				// sort
				querySort(qry,"vs","desc");

				// get changelog
				if(qry.recordcount>0) {
					local.to=qry.version[1];
					local.from=qry.version[qry.recordcount];
					local.uri=snapshots&"/rest/update/provider/changelog/"&from&"/"&to;
					if(!isNull(url.abcd))throw uri;
					http url=uri result="local.http";
					_http=getDirectoryFromPath(getCurrentTemplatePath())&"http.ser";
					if(!isNull(http.status_code) && http.status_code==200) {
						local._fileContent=http.fileContent;
						fileWrite(_http,http.fileContent);
					}
					else if(fileExists(_http)) {
						local._fileContent=fileRead(_http);
					}

					if(!isNull(local._fileContent)) {
						queryAddColumn(qry,"changelog");
						data=deSerializeJson(local._fileContent,false);
						loop query=qry {
							if(!isNull(data[qry.versionNoAppendix])) {

							cl=data[qry.versionNoAppendix];
							/*
							if(isStruct(cl) && structCount(cl)>1) {
								q=queryNew('k,ks,v');
								loop struct=cl index="key" item="val" {
									r=queryAddRow(q);
									querySetCell(q,"k",key,r);
									querySetCell(q,"ks",toKeySortable(key),r);
									querySetCell(q,"v",val,r);
								}
								querySort(q,"ks","desc");
								sct=structNew("linked");
								loop query=q {
									sct[q.k]=q.v;
								}
								qry.changelog[qry.currentrow]=sct;


							}
							else qry.changelog[qry.currentrow]=isSimpleVAlue(cl)?{}:cl; // TODO i think it is alwyys a simple value
							*/
							qry.changelog[qry.currentrow]=cl; 

								
							}
						}
					}
					else {
						fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"http.txt",local.uri&":"&serialize(http));
					}
				}
				// store as file
				fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"downloads.ser",serialize(qry));
			}
			catch(ex) {rethrow;
				fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"err.txt",serialize(ex));
			}
			return qry;
		}
	}

	function _getExtensions(required string type) localmode=true {
		if(arguments.type=="snapshot") local.ep=EXTENSION_PROVIDER_SNAPSHOT;
		else if(arguments.type=="abc") local.ep=EXTENSION_PROVIDER_ABC;
		else local.ep=EXTENSION_PROVIDER;
		//dump(type&"-"&ep);abort;

		http url=ep result="http";
		if(isNull(http.status_code) || http.status_code!=200) throw "could not connect to extension provider (#ep#)";
		data=deSerializeJson(http.fileContent,false);
		return data.extensions;
	}

	function getExtensions(required string type) localmode=true {
		// get data from server
		if(isNull(application['downloadExtensions_'&type].query) || !isNull(url.reset) || !isNull(url.resetExtension)){
			application['downloadExtensions_'&type].query=local.downloads=_getExtensions(arguments.type);
			application['downloadExtensions_'&type].age=now();
		}
		// get data from cache (application scope)
		else {
			local.downloads=application['downloadExtensions_'&type].query;
			// update for the next user when older than 5 minutes
			if(dateDiff("n",application['downloadExtensions_'&type].age,now())>=extcacheLiveSpanInMinutes) {
				application['downloadExtensions_'&type].age=now();
				thread {
					application['downloadExtensions_'&type].query=_getExtensions(arguments.type);
					systemOutput("done");
				}
			}
		}
		return downloads;
	}

	struct function getInstaller(required string version) {
		var reset=!isNull(url.reset) || !isNull(url.resetInstaller);
		if (reset) {
			structDelete(application, "installers");
			structDelete(application, "installerCheck");
		}

		var arr=listToArray(version,'.');
		if(arr.len()!=4 || find('-',arr[4])) return {};
		
		// set the right version pattern
		while(arr[4].len()<3) arr[4]="0"&arr[4];
		version=arr[1]&"."&arr[2]&"."&arr[3]&"."&arr[4];
		
		// has already the link
		if(!isnull(application.installers[version])) {
			// if null it was not found, we only search for it every 5 minutes
			if(structCount(application.installers[version])==0) {
				if(!isNull(application.installerCheck[version]) && dateAdd('n',5,application.installerCheck[version])>now())
					return application.installers[version];
			}
			else return application.installers[version];
		}

		// look for the version
		var host="https://cdn.lucee.org";
		var uriWin="/lucee-"&version&"-pl0-windows-installer.exe";
		var uriLin64="/lucee-"&version&"-pl0-linux-x64-installer.run";
		var uriLin32="/lucee-"&version&"-pl0-linux-installer.run";
		
		var uriWinPref="/lucee-"&version&"-pl1-windows-installer.exe";
		var uriLin64Pref="/lucee-"&version&"-pl1-linux-x64-installer.run";
		var uriLin32Pref="/lucee-"&version&"-pl1-linux-installer.run";

		//throw "-->"&version;
		/*
direct links
		var host="http://lucee.viviotech.net";
 		var uriWin="/downloader.cfm/id/200/file/lucee-"&version&"-pl0-windows-installer.exe";
 		var uriLin64="/downloader.cfm/id/199/file/lucee-"&version&"-pl0-linux-x64-installer.run";
 		var uriLin32="/downloader.cfm/id/198/file/lucee-"&version&"-pl0-linux-installer.run";
		*/

		var sct={};
		application.installers[version]=sct;
		// Windows
		if(isDefined("url.pref") && is200(host&uriWinPref)) sct.win = host&uriWinPref;
		else if(is200(host&uriWin)) sct.win = host&uriWin;
		
		// Linux 64
		if(isDefined("url.pref") && is200(host&uriLin64Pref)) sct.lin64 = host&uriLin64Pref;
		else if(is200(host&uriLin64)) sct.lin64 = host&uriLin64;
		
		// Linux 32
		if(isDefined("url.pref") && is200(host&uriLin32Pref)) sct.lin32 = host&uriLin32Pref;
		else if(is200(host&uriLin32)) sct.lin32 = host&uriLin32;

		application.installerCheck[version]=now();
		return sct;
	}

	function is200(url) {
		http url=replace(arguments.url,'https://','http://') method="head" result="local.result";
		return (result.status_code?:404)==200;
	}
	
	function toCDN(_url) {
		if(true || isDefined("url.doCDN") && !url.doCDN) return _url;

		_url=replace(_url,'lucee.viviotech.net','cdn.lucee.org');
		_url=replace(_url,'release.lucee.org','cdn.lucee.org');
		_url=replace(_url,'snapshot.lucee.org','cdn.lucee.org');
		_url=replace(_url,'http://','https://');
		return _url;

	}

	function makeComparable(str) {
		if(left(str,5)=="LDEV-") {
			var s=listLast(str,'-');
			while(len(s)<5)s="0"&s;
			return s;
		}
		var s=mid(str,2);
		while(len(s)<10)s="0"&s;
		return s;
	}


</cfscript>
