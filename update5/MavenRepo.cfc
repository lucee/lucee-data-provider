component {
	variables.listPattern=	"https://oss.sonatype.org/service/local/lucene/search";
	//defaultRepo="https://oss.sonatype.org/content/repositories/releases";
	variables.defaultRepo="http://central.maven.org/maven2";
	variables.group="org.lucee";
	variables.artifact="lucee";
	variables.NL="
";
	
	variables.hasS3=false;
	// S3_DIRECTORY


	// TODO genrate this dynamically as sson this code runs on Lucee 5 with help of the function ManifestRead
	//variables.mavenOsgi={"apache.lucene.analyzers-2-4-1.jar":"apache.lucene.analyzers-2.4.1.jar","commons-compress-1.9.jar":"org.apache.commons.compress-1.9.0.jar","commons-net-3.3.jar":"org.apache.commons.net-3.3.0.jar","ldapbp-1.2.4.jar":"sun.jndi.ldapbp-1.2.4.jar","oro-2.0.8.jar":"org.apache.oro-2.0.8.jar","sun.activation-1-1-1.jar":"sun.activation-1.1.1.jar","apache.lucene.similarity-2-4-1.jar":"apache.lucene.similarity-2.4.1.jar","s3.extension-0-0-0-26.jar":"s3.extension-0.0.0.26.jar","activation-1.1.0.jar":"sun.activation-1.1.0.jar","dom-1.1.0.jar":"w3c.dom-1.1.0.jar","core-1.2.1.jar":"sun.jai.core-1.2.1.jar","ant-1.4.0.jar":"apache.ws.axis.ant-1.4.0.jar","org.apache.commons.codec-1-9-0.jar":"org.apache.commons.codec-1.9.0.jar","apache.lucene.spellchecker-2-4-1.jar":"apache.lucene.spellchecker-2.4.1.jar","mail-1.3.3.01.jar":"sun.mail-1.3.3.01.jar","gpl-3.51.12.jar":"jpedal.gpl-3.51.12.jar","server-1.0.20.jar":"fusiondebug.api.server-1.0.20.jar","jcifs-1.3.17.jar":"jcifs-1.3.17.jar","axis-1.4.0.L004.jar":"apache.ws.axis-1.4.0.L004.jar","java.xmlbuilder-1-1-0.jar":"java.xmlbuilder-1.1.0.jar","adapters-1.1.1.jar":"org.apache.commons.logging.adapters-1.1.1.jar","xalan-2.7.1.jar":"apache.xml.xalan-2.7.1.jar","time-2.1.0.jar":"org.joda.time-2.1.0.jar","jackson-mapper-asl-1-9-13.jar":"jackson-mapper-asl-1.9.13.jar","extractors-3.8.0.jar":"apache.poi.tm.extractors-3.8.0.jar","concurrent-2.2.0.jar":"backport.util.concurrent-2.2.0.jar","api-1.1.1.jar":"org.apache.commons.logging.api-1.1.1.jar","core-4.4.1.jar":"apache.http.components.core-4.4.1.jar","apache.lucene.misc-2-4-1.jar":"apache.lucene.misc-2.4.1.jar","log4j-1.2.17.jar":"log4j-1.2.17.jar","jacob-1.16.1.jar":"jacob-1.16.1.jar","apache.poi-3-8-0.jar":"apache.poi-3.8.0.jar","apache.lucene.highlighter-2-4-1.jar":"apache.lucene.highlighter-2.4.1.jar","jaas-1.2.4.jar":"sun.security.jaas-1.2.4.jar","xerces-2.11.0.jar":"apache.xml.xerces-2.11.0.jar","asm-all-4.2.jar":"org.objectweb.asm.all-4.2.jar","ESAPI-2.1.0.jar":"ESAPI-2.1.0.jar","hsqldb-1.8.0.jar":"hsqldb-1.8.0.jar","jcommon-1.0.10.jar":"jcommon-1.0.10.jar","com.mysql.jdbc-5-1-20.jar":"com.mysql.jdbc-5.1.20.jar","codec-1.6.0.jar":"org.apache.commons.codec-1.6.0.jar","resolver-1.2.0.jar":"resolver-1.2.0.jar","ojdbc14-0.0.0.jar":"ojdbc14-0.0.0.jar","client-4.5.0.0002L.jar":"apache.http.components.client-4.5.0.0002L.jar","slf4j-api-1.7.12.jar":"slf4j.api-1.7.12.jar","xmlparserv2-1.2.2.jar":"xmlparserv2-1.2.2.jar","ldap-1.2.4.jar":"sun.jndi.ldap-1.2.4.jar","commons-httpclient-3.1.jar":"org.lucee.commons-httpclient-3.1.jar","mime-4.5.0.jar":"apache.http.components.mime-4.5.0.jar","mx4j-3-0-2.jar":"mx4j-3.0.2.jar","apis-1.3.2.jar":"xml.apis-1.3.2.jar","sanselan-0.97-incubator.jar":"org.apache.sanselan.sanselan-0.97.0.incubator.jar","ehcache-2.10.0.jar":"net.sf.ehcache-2.10.0.jar","ldapsec-1.2.4.jar":"sun.jndi.ldapsec-1.2.4.jar","commons-discovery-0.5.jar":"org.apache.commons.discovery-0.5.jar","xdb-1.0.0.jar":"xdb-1.0.0.jar","apache.poi.ooxml-3-8-0.jar":"apache.poi.ooxml-3.8.0.jar","apache.lucene-2-4-1.jar":"apache.lucene-2.4.1.jar","PDFBox-0-7-3.jar":"PDFBox-0.7.3.jar","extractor-2.6.4.jar":"metadata.extractor-2.6.4.jar","logging-1.1.1.jar":"org.apache.commons.logging-1.1.1.jar","wsdl4j-1.5.1.jar":"sun.xml.wsdl4j-1.5.1.jar","providerutil-1.2.4.jar":"sun.jndi.providerutil-1.2.4.jar","saaj-1.2.1.jar":"sun.xml.saaj-1.2.1.jar","codec-1.1.2.jar":"sun.jai.codec-1.1.2.jar","jtds-1-2-5.jar":"jtds-1.2.5.jar","javasysmon-0.3.3.jar":"javasysmon-0.3.3.jar","jackson-core-asl-1-9-13.jar":"jackson-core-asl-1.9.13.jar","oswego-concurrent-1.3.4.jar":"org.lucee.oswego-concurrent-1.3.4.jar","serializer-2.7.1.jar":"serializer-2.7.1.jar","org.apache.commons.logging-1-2-0.jar":"org.apache.commons.logging-1.2.0.jar","microsoft.sqljdbc-4-0-0.jar":"microsoft.sqljdbc-4.0.0.jar","apache.lucene.snowball-2-4-1.jar":"apache.lucene.snowball-2.4.1.jar","schemas-3.8.0.jar":"apache.poi.ooxml.schemas-3.8.0.jar","postgresql-9-1-902.jar":"postgresql-9.1.902.jar","jets3t-0-9-4.jar":"jets3t-0.9.4.jar","tika-core-1.10.jar":"org.apache.tika.core-1.10.0.jar","bcprov-1-52-0.jar":"bcprov-1.52.jar","jaxrpc-1.2.1.jar":"sun.xml.jaxrpc-1.2.1.jar","slf4j-nop-1.7.12.jar":"slf4j.nop-1.7.12.jar","log4j-1-2-16.jar":"log4j-1.2.16.jar","javaparser-1.0.8.jar":"javaparser-1.0.8.jar","fileupload-1.2.1.jar":"org.apache.commons.fileupload-1.2.1.jar","ooxml-3.8.0.jar":"org.apache.poi.ooxml-3.8.0.jar","commons-collections4-4.0.jar":"org.apache.commons.collections4-4.0.0.jar","lucene.search.extension-1-0-0-22.jar":"lucene.search.extension-1.0.0.22.jar","api-1.0.1.jar":"stax.api-1.0.1.jar","xmlbeans-2.3.0.r540734.jar":"xmlbeans-2.3.0.r540734.jar","jencrypt-1.4.2.04.jar":"jencrypt-1.4.2.04.jar","jfreechart-1.0.12.jar":"jfreechart-1.0.12.jar","tagsoup-1.2.1.jar":"tagsoup-1.2.1.jar","sun.mail-1-4-7.jar":"sun.mail-1.4.7.jar","commons-lang-2.6.jar":"org.apache.commons.lang-2.6.jar","commons-io-2.4.jar":"org.apache.commons.io-2.4.0.jar","css2-0.9.4.jar":"ss.css2-0.9.4.jar","commons-email-1.2.jar":"org.apache.commons.email-1.2.jar","jffmpeg-1.4.2.09.jar":"jffmpeg-1.4.2.09.jar","poi-3.8.0.jar":"org.apache.poi-3.8.0.jar","patch-1.0.12.jar":"jfreechart.patch-1.0.12.jar"};

	// this are version that should not be used in any case
	variables.ignoreVersions=["5.3.0.34-ALPHA","5.3.0.0-ALPHA-SNAPSHOT","5.2.3.30-RC","5.0.0.22","5.0.0.travis-74435522-SNAPSHOT","5.1.0.8-SNAPSHOT","5.1.0.31","5.2.1.7","5.2.1.8","5.1.4.18","5.2.0.11-ALPHA"];
	variables.majorBeta="5.3";

	public function readDependenciesFromPOM(string pom, boolean extended=false,string specifivDep=""){
		

		local.content=fileRead(pom);
		local.xml=xmlParse(content);

		// custom repositories
		local.repos=[defaultRepo];
		local.xmlRepos=xml.xmlRoot.repositories.xmlChildren;
		loop array=xmlRepos item="local.xmlRepo" {
			arrayAppend(repos,xmlRepo.url.xmlText);
		}
		// dependencies
		local.dependencies=xml.xmlRoot.dependencies.xmlChildren;
		local.arr=[];
		if(isNull(application.repoMatch))application.repoMatch={};
		loop array=dependencies item="local.dependency" {
			local.g=dependency.groupId.xmlText;
			local.a=dependency.artifactId.xmlText;
			local.v=dependency.version.xmlText;
			local.id=g&":"&a&":"&v;
			
			if(	len(specifivDep)==0 && ("org.apache.felix"==g || 
				"junit"==g || 
				"javax.servlet"==g || 
				"javax.servlet.jsp"==g || 
				"javax.el"==g ||
				"org.apache.ant"==g)) continue;

			if(len(specifivDep) && specifivDep!=g) continue;


			
			
			// find the right repo
			//dump(id);
			// TODO store physically
			if(!isNull(application.repoMatch[id&":"&extended])) {
				local.detail=application.repoMatch[id&":"&extended];
			}
			else {
				local.start=getTickCount();
				local.detail={};
				loop array=repos item="local.repo" {
					try{local.tmp=getSources(repo,v,g,a);}catch(e){continue;};
					if(!isNull(tmp.jar.src)) {
						detail.jar=tmp.jar.src;
						if(!isNull(tmp.pom.src))detail.pom=tmp.pom.src;

						application.repoMatch[id&":"&extended]=detail;
						break;
					}
				}
				local.detail.groupId=g;
				local.detail.artifactId=a;
				local.detail.version=v;
				systemOutput(id&":"&(getTickCount()-start),true,true);
				
			}
			arrayAppend(arr,detail);
		}
		return arr;
	}

	/**
	* returns local location for the loader (lucee.jar) of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public array function getOSGiDependencies(required string version, boolean force=false) {
		if(force || isNull(application._OSGiDependencies[version])) {
			local.rtn=[];
			var data=get(version,true)
			local.dir=getArtifactDirectory();
			local.dependencies=readDependenciesFromPOM(data.sources.pom.src); // get dependcies
			local.manifest=new Manifest();
			//return dependencies;
			loop array=dependencies item="local.dep" {
				// first we store the file locally, if not exist locally yet
				local.trg=dir&"mvn-"&dep.groupId&"-"&dep.artifactId&"-"&dep.version&".jar";
				if(!fileExists(trg)) fileCopy(dep.jar,trg);

				// now we read the manifest
				try{
					local.data=manifest.extractBundleInfo(trg);
					local.trg2=dir&data.name&"-"&data.version&".jar";
					if(!fileExists(trg2)) fileMove(trg,trg2);
					arrayAppend(rtn,trg2);

					// now we store a txt file cntaining this link info
					local.trg3=dir&data.name&"-"&data.version&".json";
					if(!fileExists(trg3)) fileWrite(trg3,serializeJson(dep));
				}
				catch(e){
					arrayAppend(rtn,trg);
				}
			}
			application._OSGiDependencies[version]=rtn;
		}
		return application._OSGiDependencies[version];
	}


	/**
	* get local path to the dependecies.zip, a zip containing all jars
	* @version version to get jars for
	*/
	public string function getDependencies(required string version) {
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-dependencies-"&version&".zip";
		if(!fileExists(zip)) {
			local.dependencies=getOSGiDependencies(version,true);
			// let's zip it
			zip action="zip" file=zip overwrite=true {
				loop array=dependencies item="local.dep" {
					zipparam source=dep;
				}
			}
		}
		return zip;
	}

	public function toVersionSortable(required string version){
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



	private function convertPattern(required string pattern,string group,string artifact, numeric from=1, numeric count=-1){
		pattern=pattern&"?g="&group&"&a="&artifact;
		if(from>0) pattern=pattern&"&from="&from;
		if(count>0) pattern=pattern&"&count="&count;
		return pattern;
	}

	private function toDate(string str,string timeZone){
		return createDateTime(
				mid(str,1,4),
				mid(str,5,2),
				mid(str,7,2),
				mid(str,9,2),
				mid(str,11,2),
				mid(str,13,2),0,timezone
		);

	}

	private function getArtifactDirectory(){
		local.dir=getDirectoryFromPath(getCurrenttemplatePath())&"artifacts/";
		if(!directoryExists(dir))directoryCreate(dir);
		return dir
	}

	private function getTempDir(){
		local.dir=getDirectoryFromPath(getCurrenttemplatePath())&"temp#getTickCount()#/";
		if(!directoryExists(dir))directoryCreate(dir);
		return dir
	}





	public function reset(){
		application.repoMatch={};
		application._OSGiDependencies={};

		application.repos={};
		application.detail={};
		application.info={};
	}
	
	/**
	* this flushes the cache if the is a new version available
	* 
	*/
	public string function flushAndBuild() {
		reset();
		_flushAndBuild("snapshots");
		_flushAndBuild("releases");
	}

	private string function _flushAndBuild(string type) {
		setting requesttimeout="1000";

		var list=list(type:type);
		var latest= list[arrayLen(list)];
		var data=get(latest.version,true);

		local.art=getArtifactDirectory();
		local.diff=DateDiff("n",data.sources.pom.date,now());
		
		if(diff>10) return;

		// flush
		directory action="list" directory=art name="local.dir";
		loop query=dir {
			if(find(latest.version,dir.name)) {
				try{fileDelete(local.art&dir.name);}catch(e){}
			}
		}
			
		// build
		//getDependencies(latest.version);		
		//getLoaderAll(latest.version);

	}

	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public string function getCore(required string version) {
		local.lco=getArtifactDirectory()&"lucee-"&version&".lco" // target lco file
		if(!fileExists(lco)) fileCopy("zip://"&getLoader(version)&"!core/core.lco",lco); // now extract 
		return lco;
	}
	

	/**
	* returns local location for the loader (lucee.jar) of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public string function getLoader(required string version) {
		local.jar=getArtifactDirectory()&"lucee-"&version&".jar"; // the jar
		if(!fileExists(jar)) {
			var data=get(version:version,extended:true);
			fileCopy(data.sources.jar.src,jar); // download it to local
		}
		return jar;
	}



	/**
	* returns local location for the loader (lucee.jar) of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public string function getLightLoader(required string version) { 
		local.jar=getArtifactDirectory()&"lucee-light-"&version&".jar"; // the jar
		if(fileExists(jar)) return jar;

		var loader=getLoader(version);
		try {
			// make a copy to work on
			local.tmpLoader=getArtifactDirectory()&"lucee-tmp-"&createUniqueId()&".jar"; // the jar
			fileCopy(loader,tmpLoader);

			// remove extensions
			var extDir="zip://"&tmpLoader&"!/extensions";
			directoryDelete(extDir,true); // deletes directory with all files inside
			directoryCreate(extDir); // create empty dir again (maybe Lucee expect this directory to exist)

			// update Manifest from the core file
			var lcoFile="zip://"&tmpLoader&"!/core/core.lco";
			local.tmpCore=getArtifactDirectory()&"lucee-tmp-"&createUniqueId()&".lco"; // the jar
			fileCopy(lcoFile,tmpCore);
			var manifest="zip://"&tmpCore&"!/META-INF/MANIFEST.MF";
			var content=fileRead(manifest);
			var index=find('Require-Extension',content);
			if(index>0) content=mid(content,1,index-1)&variables.NL;
			fileWrite(manifest,content);
			fileCopy(tmpCore,lcoFile);

			fileMove(tmpLoader,jar);

		}
		finally {
			if(!isNull(tmpLoader) && fileExists(tmpLoader)) fileDelete(tmpLoader);
			if(!isNull(tmpCore) && fileExists(tmpCore)) fileDelete(tmpCore);
		}
		return jar;
	}

	/**
	* returns local location for the loader (lucee.jar) of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public string function getLoaderAll(required string version, boolean doPack200=false) {
		local.jar=getArtifactDirectory()&"lucee-all-"&version&(doPack200?"-pack":"")&".jar"; // the jar
		
		if(!fileExists(jar)) {
			//var data=get(version:version);
			local.dir=getArtifactDirectory();
			local.dependencies=getOSGiDependencies(version); // get dependcies


			// first we create pack200 if requested
			if(doPack200) {
				local.pack200=new Pack200();
				loop array=dependencies item="local.dep" {
					local.trgp200=dep&".pack.gz";
					if(!fileExists(trgp200)) {
						try{
							pack200.jar2pack(dep,trgp200);
						}
						catch(e){
							if(fileExists(trgp200))
								fileDelete(trgp200)
							rethrow;
						}
					}
				}
			}

			// now we get the lucee.jar
			try {
				fileCopy(getLoader(version),jar); // get a copy of the loader
				
				if(!directoryExists(getPageContext().getConfig().getTempDirectory()))
					directoryCreate(getPageContext().getConfig().getTempDirectory());
				// let's zip it
				zip action="zip" file=jar overwrite=false {
					loop array=dependencies item="local.dep" {
						zipparam prefix="bundles/" source=dep&(doPack200?".pack.gz":"");
					}
				}
			}
			catch(e) {
				if(fileExists(jar))fileDelete(jar);
				rethrow;
			}
		}
		return jar;
	}

	/**
	* returns local location for the felix jar used for the given version
	* @version version to get jar for
	*/
	public string function getFelix(required string version) {
		var data=get(version,true);
		
		local.dependency=readDependenciesFromPOM(data.sources.pom.src,true,"org.apache.felix"); 
		local.remote=dependency[1].jar;
		local.jar=getArtifactDirectory()&listLast(remote,'/');
		
		if(!fileExists(jar)) fileCopy(remote,jar);
		
		return jar;
	}

	/**
	* returns remote location for the felix jar used for the given version
	* @version version to get jar for
	*/
	public string function getFelixRemote(required string version) {
		var data=get(version,true);
		
		local.dependency=readDependenciesFromPOM(data.sources.pom.src,true,"org.apache.felix"); 
		return dependency[1].jar;
	}

	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getExpress(required string version) {
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-express-"&version&".zip";
		
		if(fileExists(zip)) return zip;

		// Create the express zip
		try {
			// temp directory
			local.temp=getTempDir();

			local.curr=getDirectoryFromPath(getCurrenttemplatePath());

			// extension directory
			local.extDir=local.curr&("build/extensions/");
			if(!directoryExists(extDir))directoryCreate(extDir);

			// common directory
			local.commonDir=local.curr&("build/common/");
			if(!directoryExists(commonDir))directoryCreate(commonDir);

			// website directory
			local.webDir=local.curr&("build/website/");
			if(!directoryExists(webDir))directoryCreate(webDir);

			// get the jars for that release
			//local.jarsDir="#temp#jars";
			//if(!directoryExists(jarsDir))directoryCreate(jarsDir);
			//zip action="unzip" file="#getDependencies(version)#" destination=jarsDir;
			//throw getTempDirectory();

			// unpack the servers
			if(!isNull(url.test)) throw temp;
			zip action="unzip" file="#getDirectoryFromPath(getCurrenttemplatePath())&("build/servers/tomcat.zip")#" destination="#temp#tomcat";
			
			// let's zip it
			zip action="zip" file=zip overwrite=true {

			// tomcat server
				zipparam source=temp&"tomcat";

			// extensions to bundle
				zipparam source=extDir filter="*.lex" prefix="lucee-server/context/deploy";
			// jars
				// dependencies
				// zipparam source="#temp#jars" filter="*.jar" prefix="lucee-server/bundles";
				// loader
				zipparam source=getLoader(version) entrypath="lib/ext/lucee.jar";

				// felix 
				// zipparam source=getFelix(version) prefix="lib/ext/"; // this is no longer necessary because this is bundled with the lucee.jar
       
			// common files
				zipparam source=commonDir;
			
			// website files
				zipparam source=webDir prefix="webapps/ROOT";

			}
		}
		finally {
			if(!isNull(temp) && directoryExists(temp))directoryDelete(temp,true);
		}
		return zip;
	}

	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getWar(required string version) {
		local.dir=getArtifactDirectory();
		local.war=dir&"lucee-"&version&".war";
		
		if(!fileExists(war)) {
			try {
				// temp directory
				local.temp=getTempDir();

				// extension directory
				local.extDir=("build/extensions/");
				if(!directoryExists(extDir))directoryCreate(extDir);

				// common directory
				local.commonDir=ExpandPath("build/common/");
				if(!directoryExists(commonDir))directoryCreate(commonDir);

				// website directory
				local.webDir=ExpandPath("build/website/");
				if(!directoryExists(webDir))directoryCreate(webDir);

				// war directory
				local.warDir=ExpandPath("build/war/");
				if(!directoryExists(warDir))directoryCreate(warDir);

				// get the jars for that release
				//local.jarsDir=temp&"jars";
				//if(!directoryExists(jarsDir))directoryCreate(jarsDir);
				//zip action="unzip" file="#getDependencies(version)#" destination=jarsDir;
				
				// let's zip it
				zip action="zip" file=war overwrite=true {

				// extensions to bundle
					zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
				// jars
					// dependencies
					// do not add jars zipparam source=jarsDir filter="*.jar" prefix="WEB-INF/lucee-server/bundles";

					// loader
					zipparam source=getLoader(version) entrypath="WEB-INF/lib/lucee.jar";

					// felix 
					//zipparam source=getFelix(version) prefix="WEB-INF/lib/"; this is bundled with the lucee.jar
	       
				// common files
					zipparam source=commonDir;
				
				// website files
					zipparam source=webDir;
				
				// war files
					zipparam source=warDir;

				}
			}
			finally {
				if(directoryExists(temp))directoryDelete(temp,true);
			}
		}
		return war;
	}


	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getForgeBox(required string version) {
		local.dir=getArtifactDirectory();
		local.zip=dir&"forgebox-"&version&".zip";
		
		if(!fileExists(zip)) {
			try {
				// temp directory
				local.temp=getTempDir();

				// extension directory
				local.extDir=("build/extensions/");
				if(!directoryExists(extDir))directoryCreate(extDir);

				// common directory
				local.commonDir=ExpandPath("build/common/");
				if(!directoryExists(commonDir))directoryCreate(commonDir);

				// war directory
				local.warDir=ExpandPath("build/war/");
				if(!directoryExists(warDir))directoryCreate(warDir);

				// create the war
				local.war=dir&"engine.war";
				zip action="zip" file=war overwrite=true {
					zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee-server/context/deploy";
					zipparam source=getLoader(version) entrypath="WEB-INF/lib/lucee.jar";
					zipparam source=commonDir;
					zipparam source=warDir;
				}

				// create the json
				var v=reReplace( arguments.version, '([0-9]*\.[0-9]*\.[0-9]*)(\.)([0-9]*)', '\1+\3' );
				local.json=dir&"box.json";
				fileWrite(json,
'{
    "name":"Lucee CF Engine",
    "version":"#v#",
    "createPackageDirectory":false,
    "location":"http://cdn.lucee.org/rest/update/provider/forgebox/#arguments.version#",
    "slug":"lucee",
    "shortDescription":"Lucee WAR engine for CommandBox servers.",
    "type":"cf-engines"
}');


				// create the war
				zip action="zip" file=zip overwrite=true {
					zipparam source=war;
					zipparam source=json;
				}

			}
			finally {
				if(directoryExists(temp))directoryDelete(temp,true);
			}
		}
		return zip;
	}

	// TODO remove, no longer needed just for testing
	public function get(required string version, boolean extended=false) localmode=true {
		arr=list();
		loop array=arr item="sct" {
			if(sct.version==arguments.version) {
				if(extended) sct.sources=getSources(sct.repository,sct.version);
				return sct;
			}
		}
		throw "version [#arguments.version#] is not available";
	}

	public function list(string type='all', boolean extended=false) localmode=true {
		if(type!='all' && type!='snapshots' && type!='releases' && type!='abc')
			throw "provided type [#type#] is invalid, valid types are [all,snapshots,releases,abc]";


		curr=getDirectoryFromPath(getCurrenttemplatePath());
		dir=curr&"index/";
		if(!directoryExists(dir)) directoryCreate(dir);


		// collect the size of the index=
		infoURL=convertPattern(listPattern,group,artifact,1,1);
		if(!structKeyExists(application,"info") || !structKeyExists(application.info,infoURL)) {
			inc();
			http url=infoURL result="local.res" {
				httpparam type="header" name="accept" value="application/json";
			}
			info=deserializeJSON(res.fileContent);
			application.info[infoURL]=info;
		}
		else info=application.info[infoURL];

		data=[];
		repos=structNew("linked");
		from=1;
		max=200;
		count=0;
		last=false;
		e=0;n=0;
		while(true) {

			to=from+max;
			if(to>=info.totalCount) {
				to=info.totalCount;
				last=true;
			}
			file=dir&group&"-"&artifact&"-"&from&"-"&to&".json";
			
			// do we have locally?
			if(fileExists(file)) {
				raw=evaluate(fileRead(file));
				e++;
			}
			else {
				n++;
				listURL=convertPattern(listPattern,group,artifact,from,max);
				inc();
				http url=listURL result="local.res" {
					httpparam type="header" name="accept" value="application/json";
				}
				raw=deserializeJSON(res.fileContent);
				fileWrite(file,res.fileContent);
			}
			extractData(repos,data,raw,dir,type,extended);
 			from=to;


			if(last) break;
			if(count++>1000) throw "something went wrong!";
		}
		arraySort(data,function(l,r) {
			return compare(l.vs,r.vs);
		});

		return data;//{data:data,repos:repos};
	}


	private function extractRepos(repos,raw) {
		loop array=raw.repoDetails item="local.entry" {
			if(structKeyExists(repos,entry.repositoryId)) continue;
			if(!isnull(application.repos[entry.repositoryId])) {
				repos[entry.repositoryId]=application.repos[entry.repositoryId];
				continue;
			}

			inc();
			http url=entry.repositoryURL result="local.res" {
				httpparam type="header" name="accept" value="application/json";
			}
			local._raw=deSerializeJson(res.fileContent);
			repos[entry.repositoryId]=_raw.data.contentResourceURI;
			application.repos[entry.repositoryId]=_raw.data.contentResourceURI;
		}
	}

	private function extractData(repos,data,raw,dir,type, extended=false) {
		
		extractRepos(repos,raw);

		// create the list
		loop array=raw.data item="local.entry" {

			if(isNull(entry.artifactHits[1])) continue;
			if(arrayFindNoCase(variables.ignoreVersions,entry.version)) continue;

			
			local.hasApendix=find('-',entry.version);
			if(hasApendix) {
				if(right(entry.version,9)=="-SNAPSHOT") 
					local._type="snapshots";
				else
					local._type="abc";
			}
			else local._type="releases";
			

			if(type!='all' && type!=_type) continue;
			
			// "GROUPID","ARTIFACTID","VERSION","VS","TYPE","POMSRC","POMDATE","JARSRC","JARDATE"
			local.ah=entry.artifactHits[1];
			sct={};
			sct.groupId=entry.groupId;
			sct.artifactId=entry.artifactId;
			sct.version=entry.version;
			sct.vs=toVersionSortable(entry.version);
			//sct.repositoryId=ah.repositoryId;
			sct.repository=repos[ah.repositoryId];
			if(extended) sct.sources=getSources(sct.repository,sct.version);
				
			sct.hits=len(entry.artifactHits);
			sct.g=g();

			arrayAppend(data,sct);
			//data[sct.vs]=sct;
		}
		
	}

	public struct function getSources(required string repoURL, required string version, string group="", string artifact="") {
		if(len(arguments.group)==0) arguments.group=variables.group;
		if(len(arguments.artifact)==0) arguments.artifact=variables.artifact;

		local.base=repoURL&"/"&replace(group,'.','/',"all")&"/"&artifact&"/"&version;
		

		if(!isNull(application.detail[base]))
			;//return application.detail[base];


		curr=getDirectoryFromPath(getCurrenttemplatePath());
		dir=curr&"detail/";
		if(!directoryExists(dir)) directoryCreate(dir);

		file=dir&version&".json";
		if(fileExists(file)) {
			var data=deSerializeJson(fileRead(file));
			application.detail[base]=data;
			return data;
		}


		local.sources={};
		inc();
		http url=base&"/maven-metadata.xml" result="local.content" {
			httpparam type="header" name="accept" value="application/json";
		}
		//throw base&"/maven-metadata.xml";
		
		// read the files names from xml
		if(!isNull(content.status_code) &&  content.status_code==200) {
			local.xml=xmlParse(content.fileContent);
			loop array=xml.XMLRoot.versioning.snapshotVersions.xmlChildren item="node" {
				local.date=toDate(node.updated.xmlText,"GMT");
				local.src=base&"/"&artifact&"-"&node.value.xmlText&"."&node.extension.xmlText;
				sources[node.extension.xmlText]={date:date,src:src};
			}
		}
		// if there is no meta file simply assume
		else {
			// date jar
			try{
				inc();
				http method="head" url=base&"/"&artifact&"-"&version&".jar" result="local.t";
				//throw (base&"/"&artifact&"-"&version&".jar ")&serialize(t);
				if(!isNull(t.status_code) && t.status_code==200) {
					local.sources.jar.src=base&"/"&artifact&"-"&version&".jar";
					local.sources.jar.date=parseDateTime(t.responseheader['Last-Modified']);
				}
			}
			catch(e){}
			// date pom
			try{
				inc();
				http method="head" url=base&"/"&artifact&"-"&version&".pom" result="local.t";
				if(!isNull(t.status_code) && t.status_code==200) {
					local.sources.pom.src=base&"/"&artifact&"-"&version&".pom";
					local.sources.pom.date=parseDateTime(t.responseheader['Last-Modified']);
				}
			}
			catch(e){}
		}

		fileWrite(file,SerializeJson(sources));
			
		application.detail[base]=sources;
		/* cache 
		if(structCount(sources))fileWrite(file,serializeJson(sources));
		*/

		return sources;
	}

	private function  inc() {
		if(!structKeyExists(application,'httpCounter')) application.httpCounter=1;
		else application.httpCounter++;
		 
	}
	private function  g() {
		if(!structKeyExists(application,'httpCounter')) 
			application.httpCounter=0;
		return application.httpCounter;
		 
	}

}
