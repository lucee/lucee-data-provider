<cfscript>



if(!isNull(url.showAll)) {
	cookie['showAll_'&url.type]=url.showAll;
}

if(isNull(cookie.showAll_snapshots))cookie.showAll_snapshots=false;
if(isNull(cookie.showAll_releases))cookie.showAll_releases=false;

cacheLiveSpanInMinutes=5;
_url={
	releases:"http://stable.lucee.org"
	,snapshots:"http://stable.lucee.org"
};


EXTENSION_PROVIDER="http://extension.lucee.org/rest/extension/provider/info?withLogo=true";
EXTENSION_DOWNLOAD="http://extension.lucee.org/rest/extension/provider/{type}/{id}";

// texts
jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
lang.desc={
	releases:"Releases are deeply tested. Releases are recommended for production environments."
	,snapshots:"Snapshots are generated automatically with every push to the repository. Snapshots are NOT recommended for production environments."
};
lang.express="The Express version is an easy setup version which means that it does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially interesting if you e.g. would like to get to know Lucee and want to test your applications under Lucee or simply use it as development background.";
lang.war='Java Servlet engine Web ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/WAR_(file_format)">here</a>';
lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
lang.jar='Lucee jar file (and felix jar file, for older versions necessary) without dependencies Lucee needs to run. Simply copy this file(s) to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.';
lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';




	function toVersionSortable(required string version){
		local.arr=listToArray(arguments.version,'.');
		
		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
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
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else throw "version number ["&arguments.version&"] is invalid";
		


		return 		repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}


	query function getDownloads() {
		local.mr=new MavenRepo();


		// get data from server
		if(isNull(application.downloads)){
			application.downloads.query=local.downloads=mr.getAvailableVersions("all",true,false);
			application.downloads.age=now();


		}
		// get data from cache (application scope)
		else {
			local.downloads=application.downloads.query;
			// update for the next user when older than 5 minutes
			if(dateDiff("n",application.downloads.age,now())>=cacheLiveSpanInMinutes) {
				application.downloads.age=now();
				thread {
					mr=new MavenRepo();
					application.downloads.query=mr.getAvailableVersions("all",true,false);
					systemOutput("done");
				}
			}
		}

		// add version that can be sorted right (5.0.0.1-SNAPSHOT -> 5.000.000.0001-SNAPSHOT)
		if(!queryColumnExists(downloads,"v")) {
			queryAddColumn(downloads,"v");
			loop query=downloads {
				downloads.v[downloads.currentrow]=toVersionSortable(downloads.version);
			}
			// sort
			querySort(downloads,"v","desc");
		}

		return downloads;
	}


	function _getExtensions() localmode=true {
		http url=EXTENSION_PROVIDER result="http";
		if(http.status_code!=200) throw "could not connect to extension provider (#EXTENSION_PROVIDER#)";
		data=deSerializeJson(http.fileContent,false);
		return data.extensions;
	}

	function getExtensions() localmode=true {
		// get data from server
		if(isNull(application.downloadExtensions.query)){
			application.downloadExtensions.query=local.downloads=_getExtensions();
			application.downloadExtensions.age=now();
		}
		// get data from cache (application scope)
		else {
			local.downloads=application.downloadExtensions.query;
			// update for the next user when older than 5 minutes
			if(dateDiff("n",application.downloadExtensions.age,now())>=cacheLiveSpanInMinutes) {
				application.downloadExtensions.age=now();
				thread {
					application.downloadExtensions.query=_getExtensions();
					systemOutput("done");
				}
			}
		}
		return downloads;
	}


</cfscript>
