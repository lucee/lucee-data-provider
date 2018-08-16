component restpath="/provider"  rest="true" {


	variables.s3Root=request.s3Root;//"s3:///lucee-downloads/";
	variables.s3URL="https://s3-eu-west-1.amazonaws.com/lucee-downloads/";
	variables.cdnURL="https://cdn.lucee.org/";

	jiraListURL="https://luceeserver.atlassian.net/rest/api/2/project/LDEV/versions";
	jiraNotesURL="https://luceeserver.atlassian.net/secure/ReleaseNote.jspa?version={version-id}&styleName=Text&projectId=10000";

	ALL_VERSION="0.0.0.0";
	MIN_UPDATE_VERSION="5.0.0.254";
	MIN_WIN_UPDATE_VERSION="5.0.1.27";
 
	variables.mavenMappings={
		'com.mysql.jdbc':{'group':'mysql','artifact':'mysql-connector-java'}
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
	};

	variables.extMappings={
		'hibernate.extension':{lex:'hibernate-orm',jar:'lucee-hibernate'}
		,'mongodb.extension':{lex:'mongodb-extension',jar:'mongodb-extension'}
		,'s3.extension':{lex:'s3-extension',jar:'s3-extension'}
		,'extension-memcached':{lex:'extension-memcached',jar:'lucee-extension-memcached'}

	};

	variables.current=getDirectoryFromPath(getCurrentTemplatePath());
	variables.jarDirectory=variables.current&"bundles/";
	variables.artDirectory=variables.current&"artifacts/";
	variable.buildDirectory=variables.current&"builds/";
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
		

		if(findNoCase("stable.",cgi.SERVER_NAME) || findNoCase("update.",cgi.SERVER_NAME)) 
			local.type="all";
		else if(findNoCase("snapshot",cgi.SERVER_NAME) || findNoCase("dev.",cgi.SERVER_NAME) || findNoCase("preview.",cgi.SERVER_NAME)) 
			local.type="snapshots";
		else if(findNoCase("release",cgi.SERVER_NAME) || findNoCase("www.",cgi.SERVER_NAME)) 
			local.type="releases";
		else if(findNoCase("beta",cgi.SERVER_NAME) || findNoCase("betasnap",cgi.SERVER_NAME)) 
			local.type="beta";
		else  return {
					"type":"warning",
					"message":"Version ["&version.display&"] is not supported for automatic updates."};


		try{
			local.version=toVersion(arguments.version);


			local.mr=new MavenRepo();
			var list=mr.list(type:type);
			var latest= list[arrayLen(list)];
			var latestVersion=toVersion(latest.version);
			var sources=mr.getSources(latest.repository,latest.version);


			// no updates for versions smaller than ...
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_UPDATE_VERSION))) 
				return {
					"type":"warning",
					"message":"Version ["&version.display&"] can not be updated from within the Lucee Administrator.  Please update Lucee by replacing the lucee.jar, which can be downloaded from [http://download.lucee.org]"};
			
			
			// others
			latest.otherVersions=[];
			var maxSnap=400; 
			var maxRel=100;
			if(ALL_VERSION!=version.display) {
				for(var i=arrayLen(list);i>=1;i--) {
					var el=list[i];
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


			try{local.notes=(ALL_VERSION==version.display)?"":getVersionReleaseNotes(version.display,latestVersion.display,true);}catch(local.ee){local.notes="";}
			
			var msgAppendix="";
			if(ALL_VERSION!=version.display && !isNewer(version,toVersion(MIN_WIN_UPDATE_VERSION))) 
				msgAppendix="
				<div class=""error"">Warning! <br/>
				If this Lucee install is on a Windows based computer/server, please do not use the updater for this version due to a bug.  Instead download the latest lucee.jar from <a href=""http://stable.lucee.org/download/?type=snapshots"">here</a> and replace your existing lucee.jar with it.  This is a one-time workaround.";
			
			

			return {
				"type":"info"
				,"language":arguments.language
				,"current":version.display
				,"released":sources.jar.date
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
			string ioid="" restargsource="url", 
			boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="loader/{version}" {

		local.mr=new MavenRepo();
		
		// redirect to maven source
		if(arguments.allowRedirect) {
			var data=mr.get(version:version,extended:true);
			header statuscode="302" statustext="Found";
			header name="Location" value=data.sources.jar.src;
			return;
		}

		try{
			local.path=mr.getLoader(version);
			var name="lucee-#version#.jar";
			if(fromS3(path,name)) return;
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=#name#";
        content variable="#bin#" type="application/zip";
	}


	/**
	* function to download Light Lucee Loader file (lucee-light.jar)
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downLight(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		boolean deliver=true restargsource="url", 
		boolean s3=true restargsource="url")
		httpmethod="GET" restpath="light/{version}" {
		local.mr=new MavenRepo();

		try{
			local.path=mr.getLightLoader(version);
			var name="lucee-light-#version#.jar";
			if(arguments.s3 && fromS3(path,name,deliver)) return;
		}
		catch(e){
			//application.test123=now()&" - "&serialize(e);
			return {
				"type":"error",
				"message":"The version #version# is not available as a light version.",
				"detail":e.message};
		}
		if(deliver) {
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#name#";
	        content variable="#bin#" type="application/zip";
	    }
	}



	/**
	* function to download Lucee Loader file (lucee-all.jar) that bundles all dependencies
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	* 
	* used by old version 
	*/
	remote function downLoaderAll(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean allowRedirect=true restargsource="url", 
		boolean deliver=true restargsource="url")
		httpmethod="GET" restpath="loader-all/{version}" {
		
		try{
			local.mr=new MavenRepo();
			setting requesttimeout="1000";
			local.path=mr.getLoaderAll(version,!isNull(url.doPack200));
		}
		catch(e){
			return {
				"type":"error"
				,"message":"The version #version# is not available."
				,"detail":e.message
				,"StackTrace":isNull(e.StackTraceAsString)?serialize(e.stacktrace):e.StackTraceAsString
				//,"cfcatch":serialize(structkeyList(e))
			};
		}
		if(deliver) {
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=lucee-all-#version#.jar";
	        content variable="#bin#" type="application/zip";
	    }
	}


	/**
	* function to download Lucee Core file
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadCoreAlias(
		required string version restargsource="Path",
		string ioid="" restargsource="url", 
		boolean allowRedirect=true restargsource="url")
		httpmethod="GET" restpath="core/{version}" {
		return downloadCore(version,ioid,allowRedirect);
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
		string ioid="" restargsource="url", 
		boolean allowRedirect=false restargsource="url",
		boolean deliver=true restargsource="url")
		httpmethod="GET" restpath="download/{version}" {
		
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();

		try{
			local.path=mr.getCore(version);
			var name="#version#.lco";
			if(allowRedirect && fromS3(path,name,deliver)) return;
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}
		if(deliver) {
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#name#";
	        content variable="#bin#" type="application/zip";
	    }
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
		string ioid="" restargsource="url",
		boolean deliver=true restargsource="url", 
		boolean s3=true restargsource="url")
		httpmethod="GET" restpath="war/{version}" {
		
		setting requesttimeout="1000";
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();
		try{
			local.path=mr.getWar(version);
			var name="lucee-#version#.war";
			if(s3 && fromS3(path,name,deliver)) return;
			//if(fromS3Deep(path,version,"war")) return;
		}
		catch(e){
			rethrow;
			//application.test123=now()&" - "&serialize(e);
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}
		if(deliver) {
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#name#";
	        content variable="#bin#" type="application/zip";
	    }
	}



	/**
	* function to download Lucee as a forgebox bundle
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadForgebox(required string version restargsource="Path",string ioid="" restargsource="url")
		httpmethod="GET" restpath="forgebox/{version}" {
		
		setting requesttimeout="1000";
		//local.version=toVersion(arguments.version);
		local.mr=new MavenRepo();
		try{
		local.path=mr.getForgeBox(version);
		}
		catch(e){
			return {
				"type":"error",
				"message":"The version #version# is not available.",
				"detail":e.message};
		}

		file action="readBinary" file="#path#" variable="local.bin";
		header name="Content-disposition" value="attachment;filename=cf-engine-#version#.zip";
        content variable="#bin#" type="application/zip";
	}

	/**
	* function to load 3 party Bundle file, for example "/antlr/2.7.6"
	* return the download as a binary (application/zip), if there is no download available, the functions throws a exception
	*/
	remote function downloadBundle(required string bundleName restargsource="Path", string bundleVersion restargsource="Path",
		string ioid="" restargsource="url",boolean allowRedirect=false restargsource="url")
		httpmethod="GET" restpath="download/{bundlename}/{bundleversion}" {
		
		if(arguments.bundleVersion=='latest') {
			return downloadLatestBundle(arguments.bundleName);
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
			fileCopy(data.jar,orgPath);
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
			if(structKeyExists(variables.extMappings,arguments.bundleName)) {
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
			if(isDefined("url.xc")) throw name&" "&FileExists(variables.extDirectory&name)&" "&useMapping;
			if(FileExists(variables.extDirectory&name)) {

				// extract jars
				var dir="zip://"&variables.extDirectory&name&"!jars/";
				
				if(directoryExists(dir)) {
					directory filter="*.jar" name="local.jars" action="list" directory=dir;
					local.fff="";
					loop query=jars {
						if(!FileExists(variables.jarDirectory&jars.name)) {
							fileCopy(jars.directory&jars.name,variables.jarDirectory&jars.name);
							found=true;
						}
						if(structKeyExists(variables.extMappings,arguments.bundleName)) {
							if(isDefined("url.xc10")) throw "we have a mapping "&serialize(variables.extMappings[arguments.bundleName]);
							var map=variables.extMappings[arguments.bundleName];
							var trgName=arguments.bundleName&"-"&arguments.bundleVersion&".jar";
							fff&=jars.name&":"&(len(jars.name)>len(map.jar))&":"&left(jars.name,len(map.jar))&" :: "&jars.name&">"&map.jar&";";
							if(len(jars.name)>len(map.jar) && left(jars.name,len(map.jar))==map.jar && !FileExists(variables.jarDirectory&trgName)) {
								if(isDefined("url.xc11")) throw jars.directory&jars.name&" -> "&variables.jarDirectory&trgName;
								fileCopy(jars.directory&jars.name,variables.jarDirectory&trgName);
								found=true;
							}
						}
					}
					if(isDefined("url.xc20")) throw "->"&fff;
			
				}
				
			}
			var path=checkForJar(arguments.bundleName,arguments.bundleVersion);
			if(isDefined("url.xc2")) throw path&" "&fileExists(path);
			

		}
		if(len(path)==0 || !FileExists(path)) {
			// last try, when the pattrn of the maven name matches the pattern of the osgi name we could be lucky
			var mvnRep="http://central.maven.org/maven2";
			var repositories=[
				mvnRep
				,"https://raw.githubusercontent.com/lucee/mvn/master/releases"
				,"https://oss.sonatype.org/content/repositories/snapshots"
				,"https://oss.sonatype.org/content/repositories/releases"
			];

			// /mysql/mysql-connector-java/5.1.44/mysql-connector-java-5.1.44.jar
			// 'com.mysql.jdbc':{'group':'mysql','artifact':'mysql-connector-java'}

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
			if(isDefined('url.xc60')) throw "-->"&uri;
			loop array=repositories item="local.rep" {
				if(fileExists(rep&uri)) {
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
				if(arguments.allowRedirect) {
					header statuscode="302" statustext="Found";
					header name="Location" value=redirectURL;
					return;
				}
				else {
					fileCopy(redirectURL,orgPath);
					filewrite(jsonPath,serialize({"jar":redirectURL,"local":path}));
					
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

	private function downloadLatestBundle(required string bundleName) {

		// first we get all matching bundles
		var file="";
		//var str="";
		loop list=variables.artDirectory&","&variables.jarDirectory item="local.dir" {
			directory action="list" name="local.children" directory=dir filter="*.jar";
			var bn1=arguments.bundleName&"-";
			var bn2=replace(arguments.bundleName,'-','.','all')&"-";
			var bn3=replace(arguments.bundleName,'.','-','all')&"-";
			var lbn=len(bn1);
			loop query=children {
				if(left(children.name,lbn)==bn1 || left(children.name,lbn)==bn2 || left(children.name,lbn)==bn3) {
					v=mid(children.name,lbn+1);
					v=left(v,len(v)-4); // remove .jar
					//str&="-"&v&isVersion(v);
					if(isVersion(v)) {

						var vs=toVersion(v);
						if(!isStruct(file) || isNewer(vs,file.version)) {
							file={
								dir:dir
								,filename:children.name
								,name:left(children.name,lbn)
								,version:vs
							};
						}
					}
				}

			}
		}

		if(isStruct(file)) {
			file action="readBinary" file="#file.dir#/#file.filename#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#file.filename#";
	        content variable="#bin#" type="application/zip"; 
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
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;

		// try different name patterns
		name=replace(arguments.bundleName,'.','-','all')&"-"&arguments.bundleVersion&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=arguments.bundleName&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		

		name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'.','-','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'.','-','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"-"&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
		if(FileExists(variables.artDirectory&name)) return variables.artDirectory&name;
		
		name=replace(arguments.bundleName,'-','.','all')&"."&replace(arguments.bundleVersion,'-','.','all')&".jar";
		if(FileExists(variables.jarDirectory&name)) return variables.jarDirectory&name;
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

	/**
	* if there is a update the function is returning a sting with the available version, if not a empty string is returned
	* @version current version installed
	* @ioid ioid of the requesting user
	*/
	remote struct function getChangeLog(
		required string versionFrom restargsource="Path",
		required string versionTo restargsource="Path")
		httpmethod="GET" restpath="changelog/{versionFrom}/{versionTo}" {
		
		return getVersionReleaseNotes( versionFrom, versionTo);
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

	/**
	* 
	*/
	remote function reset()
		httpmethod="GET" restpath="reset" {


		local.mr=new MavenRepo();
		mr.reset();
	}

	/**
	* function to get all dependencies (bundles) for a specific version
	* @version version to get bundles for
	*/
	remote function readList(
		boolean force=false restargsource="url",
		string type='all' restargsource="url",
		boolean extended=false restargsource="url"
		)
		httpmethod="GET" restpath="list" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try {

			var arr=mr.list(arguments.type,arguments.extended);
			if(arguments.extended) {
				for(var i=arrayLen(arr);i>0;i--) {
					arr[i].s3Express=s3Exists("lucee-express-#arr[i].version#.zip");
					arr[i].s3Core=s3Exists("#arr[i].version#.lco");
					arr[i].s3Light=s3Exists("lucee-light-#arr[i].version#.jar");
					arr[i].s3War=s3Exists("lucee-#arr[i].version#.war");
				}
			}
			return arr;
		}
		catch(e){
			return {"type":"error","message":e.getMessage()};
		}
	}


	remote function readListAsync(
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
			return {"type":"error","message":e.getMessage()};
		}
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
			return {"type":"error","message":e.getMessage()};
		}
 
	}

	/**
	* function to get Lucee "express" for a specific version
	* @version version to get bundles for
	*/
	remote function downloadExpress(
		required string version restargsource="Path",
		string ioid="" restargsource="url",
		boolean deliver=true restargsource="url")
		httpmethod="GET" restpath="express/{version}" {

		setting requesttimeout="1000";
		local.mr=new MavenRepo();
		try{
			local.path=mr.getExpress(version);
		}
		catch(e){
			return {"type":"error","message":"The version #version# is not available.","exception":e};
		}
		
			
		var name="lucee-express-#version#.zip";
		if(fromS3(path,name,deliver)) {
			return;
		}
		if(deliver) {
			file action="readBinary" file="#path#" variable="local.bin";
			header name="Content-disposition" value="attachment;filename=#name#";
	        content variable="#bin#" type="application/zip";
    	}
	}

	/*remote function buildLatestX()
		httpmethod="GET" restpath="buildLatestX" {
		return application.test123;
	}*/


	/**
	* this functions triggers that everything is prepared/build for future requests
	* @version version to get bundles for
	*/
	remote function buildLatest()
		httpmethod="GET" restpath="buildLatest" {
		
		setting requesttimeout="10000";
		
		local.mr=new MavenRepo();
		mr.flushAndBuild();

		_buildLatest("snapshots",mr);
		_buildLatest("releases",mr);

		//application.exists={};
		application.releaseNotesItem={};
		application.releaseNotesData={};
		
		return "done";
	}



	private function _buildLatest(type,mr) {
		var list=mr.list(type:type);
		var latest= list[arrayLen(list)];
		
		// clean cache for that version
		if(!isNull(application.exists)) {		
			loop struct=application.exists index="local.k" item="local.v" {
				if(findNoCase(latest.version,k)) 
					structDelete( application.exists, k, false );
			}
		}
		if(!isNull(application.detail)) {		
			loop struct=application.detail index="local.k" item="local.v" {
				if(findNoCase(latest.version,k)) 
					structDelete(application.detail, k, false );
			}
		}
		var file=mr.getDetailFile(latest.version);
		if(fileExists(file)) fileDelete(file);

		// express
		thread name="buildLatest_express_#latest.version#" cfc=this vs=latest.version {
			cfc.downloadExpress(version:vs,deliver:false);
		}
		// core
		thread name="buildLatest_core_#latest.version#" cfc=this vs=latest.version {
			cfc.downloadCore(version:vs,allowRedirect:true,deliver:false);
		}
		// war
		thread name="buildLatest_war_#latest.version#" cfc=this vs=latest.version {
			cfc.downloadWar(version:vs,deliver:false);
		}
		// light
		thread name="buildLatest_light_#latest.version#" cfc=this vs=latest.version {
			cfc.downLight(version:vs,deliver:false);
		}
		// all
		thread name="buildLatest_all_#latest.version#" cfc=this vs=latest.version {
			cfc.downLoaderAll(version:vs,deliver:false);
		}
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

	/** returns version information from JIRA */
	private function getVersionInfoFromJira( string version="" ) {
		// remove appendix
		local.version=len(version)?toVersion(arguments.version).pure:"";

		var empty = { id: 0, name: "", released: false, self: "" };

		try {
			http url=jiraListURL result="local.http";
			var raw = deserializeJSON( http.fileContent );

			var result = structNew("linked");
			for ( var ai in raw ) {
				var v = ai.name CT '(' ? listGetAt( ai.name, 2, "()" ) : ai.name;
				try{v=toVersion(v).pure;}catch(local.e){continue;}
				if(!isNumeric(listFirst(v,'.'))) continue;
				if(!isNull(ai.releaseDate))ai.releaseDate=dateAdd("m",0,ai.releaseDate);
				if ( len( version ) && v == version )
					return ai;
				result[ v ] = ai;
			}
			if ( len( version ))return empty;
			return result;

		}
		catch( ex ) {
			rethrow;
		}
	}




	/** 
	* retruns the Release Notes from JIRA
	* 
	* @version - the Lucee version, e.g. 5.0.3.005
	*/
	private struct function getVersionReleaseNotes( required string versionFrom, string versionTo="", boolean simple=false) {

		if(isNull(application.releaseNotesData)) application.releaseNotesData={};
		var coll=application.releaseNotesData;
			
		local.key=versionFrom&":"&versionTo;
		//if(!isNull(coll[key].data) && DateDiff('n',coll[key].date,now())<60)
		if(!isNull(coll[key].data))
			return coll[key].data;

		local.vFrom=toVersion(arguments.versionFrom);
		// single version
		if(versionTo=="")
			return _getVersionReleaseNotes(GetVersionInfoFromJira( vFrom.pure ));
		
		local.vTo=toVersion(arguments.versionTo);	

		// 05.000.000.0197.000...05.000.000.0206.000
		// ,05.000.000.0197.100,05.000.000.0205.100
		// multiple versions
		local.res=structNew("linked");
		local.versionInfo=GetVersionInfoFromJira();
		
		loop struct=versionInfo index="local.k" item="local.item" { 
			local.v=toVersion(item.name).sortable;
			// sct.sortable

			if(v >= vFrom.sortable && v <= vTo.sortable) {
				if(simple) _getVersionReleaseNotes(item,res);
				else res[item.name]=_getVersionReleaseNotes(item);
			}
		}
		application.releaseNotesData[key]={data:res,date:now()};
		return application.releaseNotesData[key].data;
	}

	private struct function _getVersionReleaseNotes( versionInfo ,struct fillHere=structNew("linked")) {
		if(versionInfo.id) {
			if(isNull(application.releaseNotesItem)) 
				application.releaseNotesItem={};
			
			var coll=application.releaseNotesItem;
			
			//if(!isNull(coll[versionInfo.id].data) && DateDiff('n',coll[versionInfo.id].date,now())<60) {
			if(!isNull(coll[versionInfo.id].data)) {
				loop struct=coll[versionInfo.id].data index="local.k" item="local.v" {
					fillHere[k]=v;
				}
				return coll[versionInfo.id].data;
			}
			
			local.res=structNew("linked");
			try {
				http url=replace( jiraNotesURL, "{version-id}", versionInfo.id ) result="Local.http";
				var raw = http.fileContent;
				var pos = find( "</textarea>", raw );
				raw = left( raw, pos - 1 );
				pos = find( "<textarea", raw );
				raw = mid( raw, pos );
				pos = find( ">", raw );
				raw = trim( mid( raw, pos + 1 ) );
				//var res = ;
				loop list=raw delimiters="#chr(13)##chr(10)#" index="Local.li" {
					pos = find( "[LDEV-", li );
					if ( pos==0 ) continue;
					
					local.v=trim( mid( li, pos ) );

					var i1=find('[',v);
					var i2=find(']',v);
					if(i1==0 || i2==0) continue;
					local.k=mid(v,i1+1,i2-2).replace('##','').trim();
					v=mid(v,i2+1).trim()
					if(left(v,1)=='-')v=mid(v,2).trim();
					//if(!isNumeric(k)) continue;
					res[k]=v;
					fillHere[k]=v;
				}
				application.releaseNotesItem[versionInfo.id]={data:res,date:now()}

				return application.releaseNotesItem[versionInfo.id].data;
			}
			catch ( ex ) {
				rethrow;
			}
		}

		return {};
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

			if((!isNull(application.exists[name]) && application.exists[name]) || fileExists(variables.s3Root&name)) {
				application.exists[name]=true;
				header statuscode="302" statustext="Found";
				header name="Location" value=variables.cdnURL&name;
				return true;
			}
			// if not exist we make ready for the next
			else {

				if(async) {
					thread src=path trg=variables.s3Root&name {
						lock timeout=100 name=src {
							if(!fileExists(trg)) // we do this because it was created by a thread blocking this thread
								fileCopy(src,trg);
						}
					}
				}
				else {
					var src=path;
					var trg=variables.s3Root&name;
					lock timeout=100 name=src {
						
						if(!fileExists(trg)) {// we do this because it was created by a thread blocking this thread
							fileCopy(src,trg);
						}
					}
				}	
			}
			return false;
	}

}