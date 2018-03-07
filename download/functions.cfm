<cfscript>



if(!isNull(url.showAll)) {
	cookie['showAll_'&url.type]=url.showAll;
}

if(isNull(cookie.showAll_snapshots))cookie.showAll_snapshots=false;
if(isNull(cookie.showAll_releases))cookie.showAll_releases=false;

cacheLiveSpanInMinutes=5;
extcacheLiveSpanInMinutes=1000;
snapshots="http://snapshot.lucee.org";
_url={
	releases:"http://release.lucee.org"
	,abc:"http://release.lucee.org"
	,snapshots:snapshots
};



EXTENSION_PROVIDER="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=release";
EXTENSION_PROVIDER_ABC="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=abc";
EXTENSION_PROVIDER_SNAPSHOT="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=snapshot";
EXTENSION_DOWNLOAD="http://extension.lucee.org/rest/extension/provider/{type}/{id}";

// texts

// Releases are deeply tested. Releases are recommended for production environments.

jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
lang.desc={
	abc:"Beta and Release Candidates are a preview for upcoming versions and not ready for production environments."
	,releases:"Releases are ready for production environments."
	,snapshots:"Snapshots are generated automatically with every push to the repository. 
	Snapshots can be unstable are NOT recommended for production environments."
};

lang.express="The Express version is an easy to setup version which does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially useful if you would like to get to know Lucee or want to test your applications under Lucee. It is also useful for use as a development environment.";
lang.war='Java Servlet engine Web ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/WAR_(file_format)">here</a>';
lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
lang.jar='Lucee jar file (and felix jar file, for older versions necessary) without dependencies Lucee needs to run. Simply copy this file(s) to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.';
lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';

lang.lib="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).";
lang.libNew="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary. You can have this Jar in 2 flavors, a version containing all Core Extension (like Hibernate, Lucene or Axis) and a version with no Extension bundled.";

lang.installer.win="Windows";
lang.installer.lin64="Linux (64b)";
lang.installer.lin32="Linux (32b)";

	function toVersionSortable(required string version){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			throw "version number ["&arguments.version&"] is invalid";
		}
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
				thread {
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
		lock name="download#year(n)&":"&month(n)&":"&day(n)&":"&hour(n)#" timeout=10 {
			try{
				local.mr=new MavenRepo();
				flush;
				local.start=getTickCount();
				local.qry=mr.getAvailableVersions("all",true,false);
				
				// add version that can be sorted right (5.0.0.1-SNAPSHOT -> 5.000.000.0001-SNAPSHOT)
				queryAddColumn(qry,"v");
				queryAddColumn(qry,"versionNoAppendix");
				loop query=qry {
					qry.v[qry.currentrow]=toVersionSortable(qry.version);
					qry.versionNoAppendix[qry.currentrow]=toVersionWithoutAppendix(qry.version);
				}
				// merge with existing data (if exist), because sometime maven does not deliver all data
				qry=merge(qry);
				// sort
				querySort(qry,"v","desc");

				// get changelog
				if(qry.recordcount>0) {
					local.to=qry.version[1];
					local.from=qry.version[qry.recordcount];
					local.uri=snapshots&"/rest/update/provider/changelog/"&from&"/"&to;
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
							if(!isNull(data[qry.versionNoAppendix]))
								qry.changelog[qry.currentrow]=data[qry.versionNoAppendix];
						}
					}
					else {
						fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"http.txt",local.uri&":"&serialize(http));
					}
				}
				// store as file
				fileWrite(getDirectoryFromPath(getCurrentTemplatePath())&"downloads.ser",serialize(qry));
			}
			catch(ex) {
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
		var host="http://cdn.lucee.org";
		var uriWin="/lucee-"&version&"-pl0-windows-installer.exe";
		var uriLin64="/lucee-"&version&"-pl0-linux-x64-installer.run";
		var uriLin32="/lucee-"&version&"-pl0-linux-installer.run";

		/*
direct links
		var host="http://lucee.viviotech.net";
 		var uriWin="/downloader.cfm/id/200/file/lucee-"&version&"-pl0-windows-installer.exe";
 		var uriLin64="/downloader.cfm/id/199/file/lucee-"&version&"-pl0-linux-x64-installer.run";
 		var uriLin32="/downloader.cfm/id/198/file/lucee-"&version&"-pl0-linux-installer.run";
		*/

		var sct={};
		application.installers[version]=sct;

		if(is200(host&uriWin)) sct.win = host&uriWin;
		if(is200(host&uriLin64)) sct.lin64 = host&uriLin64;
		if(is200(host&uriLin32)) sct.lin32 = host&uriLin32;

		application.installerCheck[version]=now();
		return sct;
	}

	function is200(url) {
		http url=arguments.url method="head" result="local.result";
		return (result.status_code?:404)==200;
	}
	
	function toCDN(_url) {
		_url=replace(_url,'lucee.viviotech.net','cdn.lucee.org');
		_url=replace(_url,'release.lucee.org','cdn.lucee.org');
		_url=replace(_url,'snapshot.lucee.org','cdn.lucee.org');
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
