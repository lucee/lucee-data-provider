<cfscript>



if(!isNull(url.showAll)) {
	cookie['showAll_'&url.type]=url.showAll;
}

if(isNull(cookie.showAll_snapshots))cookie.showAll_snapshots=false;
if(isNull(cookie.showAll_releases))cookie.showAll_releases=false;

cacheLiveSpanInMinutes=5;
snapshots="http://snapshot.lucee.org";
_url={
	releases:"http://release.lucee.org"
	,snapshots:snapshots
};



EXTENSION_PROVIDER="http://extension.lucee.org/rest/extension/provider/info?withLogo=true";
EXTENSION_PROVIDER_BETA="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&beta=true";
EXTENSION_DOWNLOAD="http://extension.lucee.org/rest/extension/provider/{type}/{id}";

// texts

// Releases are deeply tested. Releases are recommended for production environments.

jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
lang.desc={
	releases:"Lucee 5 is currently in beta and is not ready for production environments. These beta release are however considered more stable then the snapshots."
	,snapshots:"Snapshots are generated automatically with every push to the repository. Snapshots can be unstable are NOT recommended for production environments."
};
lang.express="The Express version is an easy to setup version which does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially useful if you would like to get to know Lucee or want to test your applications under Lucee. It is also useful for use as a development environment.";
lang.war='Java Servlet engine Web ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/WAR_(file_format)">here</a>';
lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
lang.jar='Lucee jar file (and felix jar file, for older versions necessary) without dependencies Lucee needs to run. Simply copy this file(s) to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.';
lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';

lang.lib="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).";
lang.libNew="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary.";



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
		local.mr=new MavenRepo();


		// get data from server
		if(isNull(application.downloads) || !isNull(url.reset)){
			application.downloads.query=local.downloads=mr.getAvailableVersions("all",true,false);
			application.downloads.age=now();
			structDelete(application,"changelog");
			application.changelog={};
		}
		// get data from cache (application scope)
		else {
			local.downloads=application.downloads.query;
			// update for the next user when older than 5 minutes
			if(dateDiff("n",application.downloads.age,now())>=cacheLiveSpanInMinutes ||  !isNull(url.resetAsync)) {
				application.downloads.age=now();
				structDelete(application,"changelog");
				thread {
					mr=new MavenRepo();
					application.downloads.query=mr.getAvailableVersions("all",true,false);
					systemOutput("done");
				}
			}
		}

		// add version that can be sorted right (5.0.0.1-SNAPSHOT -> 5.000.000.0001-SNAPSHOT)
		local.hasV=queryColumnExists(downloads,"v");
		if(!hasV || !queryColumnExists(downloads,"versionNoAppendix")) {
			
			if(!hasV)queryAddColumn(downloads,"v");
			queryAddColumn(downloads,"versionNoAppendix");
			loop query=downloads {
				if(!hasV)downloads.v[downloads.currentrow]=toVersionSortable(downloads.version);
				downloads.versionNoAppendix[downloads.currentrow]=toVersionWithoutAppendix(downloads.version);
			}
			// sort
			querySort(downloads,"v","desc");
			
		}

		// get changelog
		if(downloads.recordcount>0 && !queryColumnExists(downloads,"changelog")) {
			local.to=downloads.version[1];
			local.from=downloads.version[downloads.recordcount];
			local.uri=snapshots&"/rest/update/provider/changelog/"&from&"/"&to;
			http url=uri result="local.http";
			if(http.status_code==200) {
				queryAddColumn(downloads,"changelog");
				data=deSerializeJson(http.fileContent,false);
				if(!isNull(url.susi)) dump(data);
				loop query=downloads {
					if(!isNull(data[downloads.versionNoAppendix]))
						downloads.changelog[downloads.currentrow]=data[downloads.versionNoAppendix];
				}
			}
		}


		return downloads;
	}


	function _getExtensions(boolean beta=false) localmode=true {
		
		local.ep=arguments.beta?EXTENSION_PROVIDER_BETA:EXTENSION_PROVIDER;
		http url=ep result="http";
		if(http.status_code!=200) throw "could not connect to extension provider (#ep#)";
		data=deSerializeJson(http.fileContent,false);
		return data.extensions;
	}

	function getExtensions(boolean beta=false) localmode=true {
		// get data from server
		if(isNull(application['downloadExtensions_'&beta].query) || !isNull(url.reset)){
			application['downloadExtensions_'&beta].query=local.downloads=_getExtensions(arguments.beta);
			application['downloadExtensions_'&beta].age=now();
		}
		// get data from cache (application scope)
		else {
			local.downloads=application['downloadExtensions_'&beta].query;
			// update for the next user when older than 5 minutes
			if(dateDiff("n",application['downloadExtensions_'&beta].age,now())>=cacheLiveSpanInMinutes) {
				application['downloadExtensions_'&beta].age=now();
				thread {
					application['downloadExtensions_'&beta].query=_getExtensions(arguments.beta);
					systemOutput("done");
				}
			}
		}
		return downloads;
	}


</cfscript>
