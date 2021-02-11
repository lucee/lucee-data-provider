component restpath="/provider"  rest="true" {


	variables.s3Root=request.s3Root;//"s3:///lucee-downloads/";
	variables.s3URL="https://s3-eu-west-1.amazonaws.com/lucee-downloads/";
	variables.cdnURL="https://cdn.lucee.org/";

	jiraDomain="luceeserver.atlassian.net";
	
	ALL_VERSION="0.0.0.0";
	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_NEW_CHANGELOG_VERSION="5.3.0.0";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";
 	
	variables.mavenMappings={
		'com.mysql.cj':{'group':'mysql','artifact':'mysql-connector-java'}
		,'com.mysql.jdbc':{'group':'mysql','artifact':'mysql-connector-java'}
		,'aws-java-sdk-osgi':{'group':'com.amazonaws','artifact':'aws-java-sdk-osgi'}
		,'com.sun.jna':{'group':'net.java.dev.jna','artifact':'jna'}
		,'org.apache.commons.pool2':{'group':'org.apache.commons','artifact':'commons-pool2'}
		,'org.jgroups':{'group':'org.jgroups','artifact':'jgroups'}
		,'com.microsoft.sqlserver.mssql-jdbc':{'group':'com.microsoft.sqlserver','artifact':'mssql-jdbc'}
		,'org.apache.tika.parsers':{'group':'org.apache.tika','artifact':'tika-parsers'}
		,'activiti-osgi':{'group':'org.activiti','artifact':'activiti-osgi'}
		,'activiti-engine':{'group':'org.activiti','artifact':'activiti-engine'}
		,'org.apache.tika.core':{'group':'org.apache.tika','artifact':'tika-core'}
		,'org.apache.tika.parsers':{'group':'org.apache.tika','artifact':'tika-parsers'}
		,'org.apache.commons.commons-text':{'group':'org.apache.commons','artifact':'commons-text'}
		,'javax.mail.activation':{'group':'javax.mail','artifact':'mail'}
		,'apache.http.components.client':{'group':'org.apache.httpcomponents','artifact':'httpclient'}
		,'apache.http.components.mime':{'group':'org.apache.httpcomponents','artifact':'httpmime'}
		,'apache.http.components.core':{'group':'org.apache.httpcomponents','artifact':'httcore'}
		,'org.mariadb.jdbc':{'group':'org.mariadb.jdbc','artifact':'mariadb-java-client'}
		,'javax.websocket-api':{'group':'javax.websocket','artifact':'javax.websocket-api'}
		,'org.mariadb.jdbc':{'group':'org.mariadb.jdbc','artifact':'mariadb-java-client'}
	};

	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	variables.artDirectory=variables.current&"artifacts/";
	variables.extDirectory="/var/www/sites/extension/extension5/extensions/"; // TODO make more dynamic

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
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		string language="en" restargsource="url")
		httpmethod="GET" restpath="info/{version}" {
		

		try{
			local.version=toVersion(arguments.version);

			// no updates for versions smaller than ...
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_UPDATE_VERSION))) 
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};
			


			local.s3=new S3(variables.s3Root);
			var versions=s3.getVersions();
			var keys=structKeyArray(versions);
			arraySort(keys,"textnocase");
			var latest.version = versions[keys[arrayLen(keys)]].version;
			var latestVersion=toVersion(latest.version);
			
			// others
			latest.otherVersions=[];
			var maxSnap=400; 
			var maxRel=100;
			if(ALL_VERSION!=version.display) {
				for(var i=arrayLen(keys);i>=1;i--) {
					var el=versions[keys[i]];
					if(findNoCase("-SNAPSHOT",el.version)) {
						if((--maxSnap)<=0) continue;
					}
					else {
						if((--maxRel)<=0) continue;
					}
					arrayPrepend(latest.otherVersions,el.version);
				}
			}

			// no update
			if(ALL_VERSION!=version.display && !isNewer(latestVersion,version))
				return {
					"type":"info",
					"message":"There is no update available for your version (#version.display#). Latest version is [#latestVersion.display#].",
					"otherVersions":latest.otherVersions?:[]
				};

			try {
				var newChangeLog=isNewer(version,toVersion(MIN_NEW_CHANGELOG_VERSION));
				local.notes=(ALL_VERSION==version.display)?
					"":getChangeLog(version.display,latestVersion.display);

				// do we need old layout of changelog?	
				if(!isNewer(version,toVersion(MIN_NEW_CHANGELOG_VERSION))) {
					var nn={};
					loop struct=notes index="local.ver" item="local.dat" {
					    loop struct=dat index="local.k" item="local.v"{
					        nn[k]=v;
					    }
					} 
					notes=nn;
				}
			}
			catch(local.ee){
				local.notes="";
			}
			
			var msgAppendix="";
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_WIN_UPDATE_VERSION))) 
				msgAppendix="
				<div class=""error"">Warning! <br/>
				If this Lucee install is on a Windows based computer/server, please do not use the updater for this version due to a bug.  Instead download the latest lucee.jar from <a href=""http://stable.lucee.org/download/?type=snapshots"">here</a> and replace your existing lucee.jar with it.  This is a one-time workaround.";
			
			

			return {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"available":latestVersion.display
				,"otherVersions":latest.otherVersions?:[]
				,"message":"A patch (#latestVersion.display#) is available for your current version (#version.display#)."&msgAppendix
				,"changelog":isSimpleValue(notes)?{}:notes/*readChangeLog(newest.log)*/
			}; // TODO get the right version for given version
		}
		catch(e){
			log log="application" exception="#e#" type="error";
			return {"type":"error","message":e.message,cfcatch:e};
		}
	}



	/**
	* function to download Lucee Loader file (lucee.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLoader(
			required string version restargsource="Path",
			string ioid="" restargsource="url")
		httpmethod="GET" restpath="loader/{version}" {

		createArtifactIfNecessary("jar",version);
			
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-"&arguments.version&".jar";
		return;
	}

	/**
	* function to download Light Lucee Loader file (lucee-light.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLight(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="light/{version}" {

		createArtifactIfNecessary("light",version);
	
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-light-"&arguments.version&".jar";
		return;
	}

	/**
	* only for backward compatibility
	*/
	remote function downLoaderAll(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="loader-all/{version}" {
		return downLoaderNew(version,ioid);
	}

		/**
	* only for backward compatibility
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="core/{version}" {
		return downloadCoreNew(version,ioid);
	}


	remote function echoGET() httpmethod="GET" restpath="echoGet" {return _echo();}
	remote function echoPOST() httpmethod="POST" restpath="echoPost" {return _echo();}
	remote function echoPUT() httpmethod="PUT" restpath="echoPut" {return _echo();}
	remote function echoDELETE() httpmethod="DELETE" restpath="echoDelete" {return _echo();}


	private function _echo() {
		sct={
			'httpRequestData':getHTTPRequestData()
			,'form':form
			,'url':url
			,'cgi':cgi
			,'session':session
		};
		//sct.ser=serialize(sct);
		return sct;
	}

	remote function downloadCore(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="download/{version}" {
		
		createArtifactIfNecessary("lco",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&arguments.version&".lco";
		return;
	}



	/**
	* function to download Lucee Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadWarHead(required string version restargsource="Path", string ioid="" restargsource="url")
		httpmethod="HEAD" restpath="war/{version}" {
			return downloadWar(version, ioid);
	}

	remote function downloadWar(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="war/{version}" {

		createArtifactIfNecessary("war",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-"&arguments.version&".war";
		return;
	}


	remote function downloadForgebox(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean light=false restargsource="url")
		httpmethod="GET" restpath="forgebox/{version}" {

		createArtifactIfNecessary(light?"fbl":"fb",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"forgebox-"&(light?"light-":"")&arguments.version&".zip";
		return;
	}

	/**
	* function to load 3 party Bundle file, for example "/antlr/2.7.6"
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadBundle(required string bundleName restargsource="Path", 
		string bundleVersion restargsource="Path",
		string ioid="" restargsource="url",boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="download/{bundlename}/{bundleversion}" {
try{

		try {
			var mm=new MavenMatcher();
			var bv=isNull(arguments.bundleVersion)?"latest":arguments.bundleVersion;
			var match=mm.getMatch(arguments.bundleName,bv);
			
			FileAppend("log-maven-download-ok.log",arguments.bundleName&":"&bv&"
");
			//http url=match.url result="local.cfhttp";
			//if(cfhttp.status_code!=200) throw match.url&" "&serialize(cfhttp);
			if(!isNull(url.abc)) throw match.url;
			header statuscode="302" statustext="Found";
			header name="Location" value=match.url;
			return;
		}catch(e) {
			FileAppend("log-maven-download.log",
				arguments.bundleName&":"&arguments.bundleVersion&" "&
				e.message&"
");	
		}
		
		if(arguments.bundleVersion=='latest') {
			arguments.bundleVersion= getLatestBundle(arguments.bundleName);

		}

		// request for a core
		if(arguments.bundleName=='lucee.core') {
			return downloadCore(arguments.bundleVersion,arguments.ioid,arguments.allowRedirect);
		}

		// read json 
		var name=arguments.bundleName&"-"&arguments.bundleVersion&".json";
		var path=variables.artDirectory&name;
		var jsonPath=path;
		if(fileExists(path)) {
			var data=deserializeJson(fileRead(path));
		}

		// redirect to maven repo
		if(arguments.allowRedirect && !isNull(data.jar)) {
			var jarPath=variables.artDirectory&arguments.bundleName&"-"&arguments.bundleVersion&".jar";
			if(fileExists(jarPath)) {
				fileDelete(jarPath);
			}
			header statuscode="302" statustext="Found";
			header name="Location" value=data.jar;
			return;
		}

		// first of all we look at the artifacts directory (lucee dependecies download automatically)
		var orgName=arguments.bundleName&"-"&arguments.bundleVersion&".jar";
		var orgPath=variables.artDirectory&orgName;
		var path=checkForJar(arguments.bundleName,arguments.bundleVersion);

		// download from Maven if we have a .json file
		if(len(path)==0 && !isNull(data.jar)) {
			_fileCopy(data.jar,orgPath);
			path=orgPath;
		}

		// extension jar?
		if(len(path)==0) {
			// get the extension
			var name=arguments.bundleName&"-"&arguments.bundleVersion&".lex"
			if(!FileExists(variables.extDirectory&name)) // bundle-name-bundle.version
				name=replace(arguments.bundleName,'.','-','all')&"-"&arguments.bundleVersion&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle-name-bundle.version
				name=arguments.bundleName&"-"&replace(arguments.bundleVersion,'.','-','all')&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle-name-bundle.version
				name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle-name-bundle.version
				name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle.name-bundle-version
				name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle.name-bundle.version
				name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".lex";
			if(!FileExists(variables.extDirectory&name)) // bundle.name.bundle.version
				name=replace(arguments.bundleName,'-','.','all')&"."&replace(arguments.bundleVersion,'-','.','all')&".lex";

			var useMapping=false;
			if(!isnull(variables.extMappings) && structKeyExists(variables.extMappings,arguments.bundleName)) {
				if(!FileExists(variables.extDirectory&name)) {
					name=variables.extMappings[arguments.bundleName].lex&"-"&arguments.bundleVersion&".lex";
					useMapping=true;
				}	
				if(!FileExists(variables.extDirectory&name)) {
					name=variables.extMappings[arguments.bundleName].lex&"-"&replace(arguments.bundleVersion,'.','-','all')&".lex";
					useMapping=true;
				}
			}
			

			var found=false;
			if(FileExists(variables.extDirectory&name)) {

				// extract jars
				var dir="zip://"&variables.extDirectory&name&"!jars/";
				
				if(directoryExists(dir)) {
					directory filter="*.jar" name="local.jars" action="list" directory=dir;
					local.fff="";
					loop query=jars {
						if(!FileExists(variables.artDirectory&jars.name)) {
							_fileCopy(jars.directory&jars.name,variables.artDirectory&jars.name);
							found=true;
						}
						if(!isnull(variables.extMappings) && structKeyExists(variables.extMappings,arguments.bundleName)) {
							if(isDefined("url.xc10")) throw "we have a mapping "&serialize(variables.extMappings[arguments.bundleName]);
							var map=variables.extMappings[arguments.bundleName];
							var trgName=arguments.bundleName&"-"&arguments.bundleVersion&".jar";
							fff&=jars.name&":"&(len(jars.name)>len(map.jar))&":"&left(jars.name,len(map.jar))&" :: "&jars.name&">"&map.jar&";";
							if(len(jars.name)>len(map.jar) && left(jars.name,len(map.jar))==map.jar && !FileExists(variables.artDirectory&trgName)) {
								_fileCopy(jars.directory&jars.name,variables.artDirectory&trgName);
								found=true;
							}
						}
					}
				}
				
			}
			var path=checkForJar(arguments.bundleName,arguments.bundleVersion);
		}
		if(len(path)==0 || !FileExists(path) || !isNull(url.ignoreLocal)) {
			// last try, when the pattrn of the maven name matches the pattern of the osgi name we could be lucky
			var mvnRep="https://repo1.maven.org/maven2";
			var repositories=[
				mvnRep,
				"http://raw.githubusercontent.com/lucee/mvn/master/releases"
				,"http://oss.sonatype.org/content/repositories/snapshots"
				//,"https://repo1.maven.org/maven2"
			];

			if(structKeyExists(variables.mavenMappings,arguments.bundleName)) {
				var mvnId=variables.mavenMappings[arguments.bundleName];
				var uri="/"&replace(mvnId.group,'.','/','all')&"/"&mvnId.artifact&
						"/"&arguments.bundleVersion&
						"/"&mvnId.artifact&"-"&arguments.bundleVersion&".jar";
			}
			else {
				var uri="/"
					&replace(arguments.bundleName,'.','/','all')&"/"
					&arguments.bundleVersion&"/"
					&listLast(arguments.bundleName,'.')&"-"
					&arguments.bundleVersion&".jar";
			}
			loop array=repositories item="local.rep" {
				http url=rep&uri result="local.tmp";
				if(isNull(tmp.status_code)) tmp.status_code=404;
				if(tmp.status_code>=200 && tmp.status_code<300) {
					local.redirectURL=rep&uri;
					break;
				}
			}
			
			// ok an other last try, when "org.lucee" we know more about the pattern
			if(isNull(redirectURL) && left(arguments.bundleName,10)=='org.lucee.'){
				var art1=mid(arguments.bundleName,11);
				var art2=replace(art1,'.','-','all');
				
				var urls=[
					 mvnRep&"/org/lucee/"&art1&"/"&arguments.bundleVersion&"/"&art1&"-"&arguments.bundleVersion&".jar"
					,mvnRep&"/org/lucee/"&art2&"/"&arguments.bundleVersion&"/"&art2&"-"&arguments.bundleVersion&".jar"
				];
				loop array=urls item="local._url" {
					if(fileExists(_url)) {
						local.redirectURL=_url;
						break;
					}
				}
			}

				
			if(!isNull(redirectURL)){
				if(isDefined("url.xa1")) throw jsonPath&":"&redirectURL;
				filewrite(
					jsonPath,
					serialize({"jar":redirectURL,"local":path}));

				if(arguments.allowRedirect) {
					header statuscode="302" statustext="Found";
					header name="Location" value=redirectURL;
					return;
				}
				else {
					_fileCopy(redirectURL,orgPath);
					
					file action="readBinary" file="#orgPath#" variable="local.bin";
					header name="Content-disposition" value="attachment;filename=#orgName#";
			        content variable="#bin#" type="application/zip";

			        return;
				}
			}


			var text="no jar available for bundle "&arguments.bundleName&" in Version "&arguments.bundleVersion;
			header statuscode="404" statustext="#text#";
			echo(text);
			// TODO write to a log
			file action="append" addnewline="yes" file="#variables.current#missing-bundles.txt"
			output="#arguments.bundleName#-#arguments.bundleVersion#->#path#" fixnewline="no";
            
		}
		else {
			
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#orgName#";
	        content variable="#bin#" type="application/zip"; // in future version this should be handled with producer attribute
		}
}
catch(e) { return e;}
	}

	private function getLatestBundle(required string bundleName) {

		// first we get all matching bundles
		var file="";
		//var str="";
		local.dir=variables.artDirectory;
		
		directory action="list" name="local.children" directory=dir filter=function(path) {
			var ext=listLast(arguments.path,'.');
			return ext=='jar' || ext=='json';
		};
		var bn1=arguments.bundleName&"-";
		var bn2=replace(arguments.bundleName,'-','.','all')&"-";
		var bn3=replace(arguments.bundleName,'.','-','all')&"-";
		var lbn=len(bn1);
		loop query=children {
			if(left(children.name,lbn)==bn1 || 
				left(children.name,lbn)==bn2 || 
				left(children.name,lbn)==bn3) {

		
				v=mid(children.name,lbn+1);
				v=left(v,len(v)- (right(v,4)==".jar"?4:5)); // remove .jar
				//str&="-"&v&isVersion(v);
				if(isVersion(v)) {

					var vs=toVersion(v);
					if(!isStruct(file) || isNewer(vs,file.version)) {
						file={
							dir:dir
							,filename:children.name
							,name:left(children.name,lbn)
							,version:vs
							,v:v
						};
					}
				}
			}
		}
		

		if(isStruct(file)) {
			return file.v;
			//if(!isNull(url.test))throw ""&serialize(file);
			//file action="readBinary" file="#file.dir#/#file.filename#" variable="local.bin";
			//header name="Content-disposition" value="attachment;filename=#file.filename#";
	        //content variable="#bin#" type="application/zip"; 
		}
		else {
			var text="no jar available for bundle "&arguments.bundleName;
			header statuscode="404" statustext="#text#";
			echo(text);
			// TODO write to a log
			file action="append" addnewline="yes" file="#variables.current#missing-bundles.txt"
			output="#arguments.bundleName#-latest-version" fixnewline="no";
		}
	}

	private function checkForJar(bundleName,bundleVersion, ext='jar') {
		
		var name=arguments.bundleName&"-"&arguments.bundleVersion&"."&ext;
		if(isDefined("url.xc3"))throw name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;

		// try different name patterns
		name=replace(arguments.bundleName,'.','-','all')&"-"&arguments.bundleVersion&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=arguments.bundleName&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		

		name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"."&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		return "";
	}


	/**
	* if there is a update the function is returning a sting with the available version, if not a empty string is returned
	* @version current version installed
	* @ioid ioid of the requesting user
	*/
	remote string function getInfoSimple(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="update-for/{version}" produces="application/lazy" {
		
		local.info=getInfo(version,ioid,"en");
		systemOutput(version&"->	"&structkeyExists(info,"available"),true,true);
		

		if(structkeyExists(info,"available")) return info.available;
		return "";
	}

	remote struct function getChangeLog(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelog/{versionFrom}/{versionTo}" {
		
		var from=toVersionSortable(versionFrom);
		var to=toVersionSortable(versionTo);

		var jira=new Jira("luceeserver.atlassian.net");
		var issues=jira.listIssues(project:"LDEV",stati:["Deployed","Done"]).issues;
		var sct=structNew("linked");
		loop query=issues {
			loop array=issues.fixVersions item="local.fv" {
				try{var fvs=toVersionSortable(fv);}catch(e) {continue;}
				if(fvs<from || fvs>to) continue;
				if(!structKeyExists(sct,fv)) sct[fv]=structNew("linked");
				sct[fv][issues.key]=issues.summary;
			}
			
		}
		return sct;
	}


	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function downloadDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="dependencies/{version}" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			local.path=mr.getDependencies(version);
		}
		catch(e){
			//return e;
			return {"type":"error","message":"The version #version# is not available."};
		}

		file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=lucee-dependencies-#version#.zip";
	        content variable="#bin#" type="application/zip"; 
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function getDependencies(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="dependencies-read/{version}" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			return mr.getOSGiDependencies(version,true);
		}
		catch(e){
			return {"type":"error","message":"The version #version# is not available."};
		}
 
	}

	remote function reset()
		httpmethod="GET" restpath="reset" {
		new MavenRepo().reset();
		new S3(variables.s3Root).reset();
	}

	remote function readList(
		boolean force=false restargsource="url",
		string type='all' restargsource="url",
		boolean extended=false restargsource="url",
		boolean flush=false restargsource="url"
		)
		httpmethod="GET" restpath="list" {

		setting requesttimeout="1000";

		try {
			var s3=new S3(request.s3Root);
			var versions=s3.getVersions(flush);
			var ignores=["6.0.0.12-SNAPSHOT","6.0.0.13-SNAPSHOT"];
			loop array=structKeyArray(versions) item="local.k" {
				if(arrayFind(ignores,versions[k].version))structDelete(versions,k);
			}
			
			if(extended) return versions;
			var arr=[];
			loop struct=versions index="local.vs" item="local.data" {
				arrayAppend(arr,{'vs':vs,'version':data.version});
			}
			return arr;
		}
		catch(e){
			return {"type":"error","message":e.message};
		}
	}

	/*remote function readListAsync(
		boolean force=false restargsource="url",
		string type='all' restargsource="url",
		boolean extended=false restargsource="url"
		)
		httpmethod="GET" restpath="listAsync" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {

			var arr=mr.list(arguments.type,arguments.extended);
			if(arguments.extended) {
				thread cfc=this arr=arr {
					for(var i=arrayLen(arr);i>0;i--) {
						arr[i].s3Express=cfc.s3Exists("lucee-express-#arr[i].version#.zip");
						arr[i].s3Core=cfc.s3Exists("#arr[i].version#.lco");
						arr[i].s3Light=cfc.s3Exists("lucee-light-#arr[i].version#.jar");
						arr[i].s3War=cfc.s3Exists("lucee-#arr[i].version#.war");
					}
				}
			}
			return arr;
		}
		catch(e){
			return {"type":"error","message":e.message};
		}
	}*/


	remote function getDate(required string version restargsource="Path")
		httpmethod="GET" restpath="getdate/{version}" {
		var mr=new MavenRepo();
		var info=mr.get(version,true);
		try{
			if(!isNull(info.sources.pom.date))
				return parseDateTime(info.sources.pom.date);
			else if(!isNull(info.sources.jar.date))
				return parseDateTime(info.sources.jar.date);
		}catch(e) {}
		
		return "";
	}



	

	remote function readGetOnlyForDebugging(
		required string version restargsource="Path"
		,boolean extended restargsource="url")
		httpmethod="GET" restpath="get/{version}" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {
			return mr.get(arguments.version,arguments.extended);
		}
		catch(e){
			return {"type":"error","message":e.message};
		}
 
	}

	remote function downloadExpress(
		required string version restargsource="Path",
		string ioid="" restargsource="url")
		httpmethod="GET" restpath="express/{version}" {
		
		createArtifactIfNecessary("express",version);
		
		header statuscode="302" statustext="Found";
		header name="Location" value=variables.cdnURL&"lucee-express-"&arguments.version&".zip";
		return;
	}

	remote function listMissing(boolean inclFB=false restargsource="url")
		httpmethod="GET" restpath="list-missing" {
		setting requesttimeout="100";
		var s3=new S3(variables.s3Root);
		var versions=s3.getVersions(true);

		var rtn=structNew("linked");
		var list="jar,lco,war,light,express";
		if(inclFB)list&=",fb,fbl";
		loop list=list item="type" {
			
			loop struct=versions index="vs" item="data" {
				if(!structKeyExists(data,type) && left(data.version,1)>4) {
					if(isNull(rtn[type]))rtn[type]=[];
					arrayAppend(rtn[type],data.version);
				}
			}
		}
		return rtn;
	}

	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		var s3=new S3(variables.s3Root);
		s3.addMissing(true);
		s3.reset();
		return "done";
	}



	private boolean function isVersion(required string version) { 
		try{
			toVersion(version);
			return true;
		}
		catch(e) {
			return false;
		}
	}
	
	private struct function toVersion(required string version, boolean ignoreInvalidVersion=false){
		local.arr=listToArray(arguments.version,'.');
		if(arr.len()==3) {
			arr[4]="0";
		}
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
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else throw "version number ["&arguments.version&"] is invalid";
		sct.pure=
					sct.major
					&"."&sct.minor
					&"."&sct.micro
					&"."&sct.qualifier;
		sct.display=
					sct.pure
					&(sct.qualifier_appendix==""?"":"-"&sct.qualifier_appendix);
		
		sct.sortable=repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;



		return sct;


	}

	private boolean function isNewer(required struct left, required struct right ){
		// major
		if(left.major>right.major) return true;
		if(left.major<right.major) return false;
		
		// minor
		if(left.minor>right.minor) return true;
		if(left.minor<right.minor) return false;
		
		// micro
		if(left.micro>right.micro) return true;
		if(left.micro<right.micro) return false;

		// qualifier
		if(left.qualifier>right.qualifier) return true;
		if(left.qualifier<right.qualifier) return false;
		
		if(left.qualifier_appendix_nbr>right.qualifier_appendix_nbr) return true;
		if(left.qualifier_appendix_nbr<right.qualifier_appendix_nbr) return false;
		
		if(left.qualifier_appendix_nbr==75 && right.qualifier_appendix_nbr==75) {
			if(left.qualifier_appendix>right.qualifier_appendix) return true;
			if(left.qualifier_appendix<right.qualifier_appendix) return false; // not really necessary
		}
		return false;
	}

	private boolean function isEqual(required struct left, required struct right ){
		if(left.major!=right.major) return false;
		if(left.minor!=right.minor) return false;
		if(left.micro!=right.micro) return false;
		if(left.qualifier!=right.qualifier) return false;
		if(left.qualifier_appendix!=right.qualifier_appendix) return false;

		return true;
	}

	private function s3Exists(name) {
		if(!isNull(application.exists[name])) {
			return application.exists[name];
		}
		if(fileExists(variables.s3Root&name)) {
			application.exists[name]=true;
			return true;
		}
		application.exists[name]=false;
		return false;
	}
	

	/**
	* checks if file exists on S3 and if so redirect to it, if not it copies it to S3 and the next one will have it there.
	* So nobody has to wait that it is copied over
	*/
	private function fromS3(path,name,async=true) {
		
		// if exist we redirect to it
			if(!isNull(url.show)) throw (!isNull(application.exists[name]) && application.exists[name])&":"&fileExists(variables.s3Root&name)&"->"&(variables.s3Root&name);

			var hasDef=(!isNull(application.exists[name]) && application.exists[name]);
			if(hasDef || fileExists(variables.s3Root&name)) {
				application.exists[name]=true;
				header statuscode="302" statustext="Found";
				header name="Location" value=variables.cdnURL&name;
				return true;
			}
			// if not exist we make ready for the next
			else {

				if(async && isNull(url.show)) {
					thread src=path trg=variables.s3Root&name {
						lock timeout=1000 name=src {
							if(!fileExists(trg) && fileSize(src)>100000) // we do this because it was created by a thread blocking this thread
								_fileCopy(src,trg);
						}
					}
				}
				else {
					var src=path;
					var trg=variables.s3Root&name;
					lock timeout=1000 name=src {
						if(!fileExists(trg) && fileSize(src)>100000) {// we do this because it was created by a thread blocking this thread
							_fileCopy(src,trg);
							if(!isNull(url.show)) throw "fileExists: "&fileExists(src)&" + "&fileExists(trg);
						}
					}
				}	
			}
			return false;
	}

	private function _fileCopy(src,trg) {
		if(isSimpleValue(src) && findNoCase("http",src)==1) {
			// we do this because of 302 the function cannot handle
			http url=src result="local.res";
			if(isNull(res.statuscode) || res.statuscode!=200) {
				if(findNoCase("https://",src)) {
					src=replaceNoCase(src,"https://","http://");
					http url=src result="local.res";
				}

			}
			//throw src&":"&res.statuscode&":"&len(res.filecontent);
			if(isNull(res.statuscode) || res.statuscode!=200) throw src&":"&res.statuscode;
			if(len(res.filecontent)<1000) throw "file [#src#] is to small (#len(res.filecontent)#)";
			fileWrite(trg,res.filecontent);
		}
		else fileCopy(src,trg);
	}


	private function fileSize(path) {
	    var dir=getDirectoryFromPath(path);
	    var file=listLast(path,'\/');
	    directory filter=file name="local.res" directory=dir action="list";
	    return res.recordcount==1?res.size:0;
	}

	private function createArtifactIfNecessary(type,version) {
		var s3=new S3(variables.s3Root);
		var versions=s3.getVersions();
		var vs=toVersionSortable(version);
		
		if(structKeyExists(versions,vs) && structKeyExists(versions[vs],type)) return;
		thread s3=s3 name=createUUID() _type=type _version=version  {
			try{
				setting requesttimeout="10000000";
				s3.add(_type,_version);
			}
			catch(e){
				fileWrite("error.txt",serialize(e));
			}
		}
		s3.reset();
		throw "artifact #type# for version #version# does not exist yet, but we triggered the build for it. Try again in a couple minutes.";
		//setting requesttimeout="10000000";
		//sleep(60000);
	}

	private function toVersionSortable(string version){
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
		else {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix_nbr=75;
		}


		return 		repeatString("0",2-len(sct.major))&sct.major
					&"."&repeatString("0",3-len(sct.minor))&sct.minor
					&"."&repeatString("0",3-len(sct.micro))&sct.micro
					&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}
}
