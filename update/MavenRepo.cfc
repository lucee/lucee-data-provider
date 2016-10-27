component {
	variables.listPattern=	"https://oss.sonatype.org/service/local/lucene/search?g={group}&a={artifact}";
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
	variables.ignoreVersions=["5.0.0.22","5.0.0.travis-74435522-SNAPSHOT","5.1.0.8-SNAPSHOT","5.1.0.31"];
	variables.majorBeta="5.2";

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
					try{local.tmp=getDetail(repo,g,a,v,true);}catch(e){continue;};
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
			local.info=getInfo(version,true,false); // get info for defined version
			local.dir=getArtifactDirectory();
			local.dependencies=readDependenciesFromPOM(info.pomSrc); // get dependcies
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
		local.info=getInfo(version); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-dependencies-"&info.version&".zip";
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

	/* get local path to the dependecies.zip, a zip containing all jars
	* @version version to get jars for
	*
	public string function getDependencies(required string version) {
		local.info=getInfo(version); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-dependencies-"&info.version&".zip";
		if(!fileExists(zip)) {
			local.dependencies=readDependenciesFromPOM(info.pomSrc); // get dependcies
			
			local.manifest=new Manifest();
			// first we store the file locally, if not exist locally yet
			local.maven2osgi={};
			loop array=dependencies item="local.dep" {
				//throw serialize(dep);
				local.name=dep.groupId&"-"&dep.artifactId&"-"&dep.version&".jar";
				local.trg=dir&name;//listLast(dep.jar,"/");
				
				if(!fileExists(trg))fileCopy(dep.jar,trg);

				local.dataMani=manifest.extractBundleInfo(trg);
				local.trg2=dir&replace(dataMani.name,'.','-','all')&"-"&replace(dataMani.version,'.','-','all')&".jar";
				maven2osgi[trg]=trg2;

				if(!fileExists(trg2))fileMove(trg,trg2);
			}

			// let's zip it
			zip action="zip" file=zip overwrite=true {
				
				loop array=dependencies item="local.dep" {
					local.name=dep.groupId&"-"&dep.artifactId&"-"&dep.version&".jar";
					local.trg=dir&name;//listLast(dep.jar,"/");
					zipparam source=maven2osgi[trg];
				}
			}
		}
		return zip;
	}*/


	/**
	* return information about a specific version
	* @version version to get info for
	*/
	public struct function getInfo(required string version, boolean force=false, boolean checkIgnoreMajor=true){
		if(isNull(application.infoData)) application.infoData={};
		
		if(force || isNull(application.infoData[version])) {
			local.qry= getAvailableVersions(type:'all', extended:true, onlyLatest:false,specificVersion:version,checkIgnoreMajor=arguments.checkIgnoreMajor);
			if(qry.recordcount==0) throw "no info found for version ["&version&"]";
			application.infoData[version] = QueryRowData(qry,1);

		}
		return application.infoData[version];
		
	}

	public function reset(){
		application.infoData={};
		application.repoMatch={};
		application._OSGiDependencies={};
	}

	/**
	* return information about the latest version
	* @version version to get info for
	*/
	public struct function getLatest(required string type,boolean checkIgnoreMajor=true){
		if(isNull(application.infoData)) application.infoData={};
		
		if(isNull(application.infoData["latest="&type]) || !isNull(url.abc) ) {
			local.qry= getAvailableVersions(type:type, extended:true, onlyLatest:true, checkIgnoreMajor:arguments.checkIgnoreMajor);
			if(qry.recordcount==0) throw "no info found for type ["&type&"]";
			

			local._result=QueryRowData(qry,1);
			if(true) {
				local.qry=getAvailableVersions(type:type, extended:false, onlyLatest:false, checkIgnoreMajor:false);
				local.sct={};
				loop query=qry {
					local.isSnap=findNoCase('-snapshot',qry.version);
					//if((arguments.type=='releases' && !isSnap) || (arguments.type!='releases' && isSnap) ) 
					sct[qry.vs]=qry.version;
				}

				local.keys=sct.keyArray().sort('text');
				local.arr=[];
				loop array=keys index='local.i' item='local.v' {
					arrayAppend(arr,sct[v]);
				}
				local._result.otherVersions=arr;
			}
			application.infoData["latest="&type] = local._result;
			

		}
		return application.infoData["latest="&type];
	}

	/**
	* return information about available versions
	* @type one of the following (snapshots,releases or all)
	* @extended when true also return the location of the jar and pom file, but this is slower (has to make addional http calls)
	* @onlyLatest only return the latest version
	*/
	public query function getAvailableVersions(string type='all', boolean extended=false, boolean onlyLatest=false, boolean checkIgnoreMajor=true){
		if(extended){
			setting requesttimeout="1000";
		}
		// validate input
		if(type!='all' && type!='snapshots' && type!='releases' && type!='beta')
			throw "provided type [#type#] is invalid, valid types are [all,snapshots,releases,beta]";

		// create the list URL
		local.listURL=convertPattern(listPattern,group,artifact);
		
		// get data
		http url=listURL result="local.res" {
			httpparam type="header" name="accept" value="application/json";
		}
		local.raw=deSerializeJson(res.fileContent);
		
		// repo urls
		if(extended) local.repos=getRepositories(raw.repoDetails);

		// create the list
		local.qry=queryNew("groupId,artifactId,version,vs,type"&(extended?",pomSrc,pomDate,jarSrc,jarDate":""));
		loop array=raw.data item="local.entry" {
			if(isNull(entry.artifactHits[1])) continue;
			local.ah=entry.artifactHits[1];

			// ignore list
			if(arrayContains(variables.ignoreVersions,entry.version)) continue;
			if(checkIgnoreMajor) {
				var isBeta=left(entry.version,len(variables.majorBeta))==variables.majorBeta;
				if(type=='beta') {
					if(!isBeta) continue;
				}
				else {
					// ignore major
					if(isBeta) continue;
				}
			}
			if(type=='beta') type='all'; // because there is not necessary the keyword beta, in that case only the version decides
			// check type
			if(type!="all" && type!=ah.repositoryId) continue;
			// latest
			//if(onlyLatest && entry.version!=entry.latestSnapshot && entry.version!=entry.latestRelease) continue;
			if(onlyLatest && qry.recordcount>0) break;  // TODO do better

			// specific
			if(!isNull(specificVersion) && specificVersion!=entry.version) continue;

			local.row=qry.addRow();

			if(extended)local.sources=getDetail(repos[ah.repositoryId],entry.groupId,entry.artifactId,entry.version);

			qry.setCell("groupId",entry.groupId,row);
			qry.setCell("artifactId",entry.artifactId,row);
			qry.setCell("version",entry.version,row);
			qry.setCell("vs",toVersionSortable(entry.version),row);
			qry.setCell("type",ah.repositoryId,row);
			
			if(extended) {
				if(!isNull(sources.pom.src))qry.setCell("pomSrc",sources.pom.src,row);
				if(!isNull(sources.pom.date))qry.setCell("pomDate",sources.pom.date,row);
				if(!isNull(sources.jar.src))qry.setCell("jarSrc",sources.jar.src,row);
				if(!isNull(sources.jar.date))qry.setCell("jarDate",sources.jar.date,row);
			}
			//else qry.setCell("artifacts",ah.artifactLinks,row);
		}
		if(extended)querySort(qry,"jarDate","asc");
		else querySort(qry,"version","asc");




		return qry;
	}

	function getRepositories(required array repoDetails) {
		local.repos={};
		loop array=repoDetails item="local.entry" {
			http url=entry.repositoryURL result="local.res" {
				httpparam type="header" name="accept" value="application/json";
			}
			local._raw=deSerializeJson(res.fileContent);
			repos[entry.repositoryId]=_raw.data.contentResourceURI;
		}
		return repos;
	}

	public struct function getDetail(required string repoURL,
			required string groupId,required string artifactId,required string version, 
			boolean simply=false){
		local.base=repoURL&"/"&replace(groupId,'.','/',"all")&"/"&artifactId&"/"&version;
		
		local.sources={};
		if(!simply){
			http url=base&"/maven-metadata.xml" result="local.content" {
				httpparam type="header" name="accept" value="application/json";
			}
		}
		// read the files names from xml
		if(!simply && content.status_code==200) {
			local.xml=xmlParse(content.fileContent);
			loop array=xml.XMLRoot.versioning.snapshotVersions.xmlChildren item="node" {
				local.date=toDate(node.updated.xmlText,"GMT");
				local.src=base&"/"&artifactId&"-"&node.value.xmlText&"."&node.extension.xmlText;
				sources[node.extension.xmlText]={date:date,src:src};
			}
		}
		// if there is no meta file simply assume
		else {
			// date jar
			try{
				http method="head" url=base&"/"&artifactId&"-"&version&".jar" result="local.t";
				if(t.status_code==200) {
					local.sources.jar.src=base&"/"&artifactId&"-"&version&".jar";
					local.sources.jar.date=parseDateTime(t.responseheader['Last-Modified']);
				}
			}
			catch(e){}
			// date pom
			try{
				http method="head" url=base&"/"&artifactId&"-"&version&".pom" result="local.t";
				if(t.status_code==200) {
					local.sources.pom.src=base&"/"&artifactId&"-"&version&".pom";
					local.sources.pom.date=parseDateTime(t.responseheader['Last-Modified']);
				}
			}
			catch(e){}
		}
		return sources;
	}

	private function toVersionSortable(required string version){
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



	private function convertPattern(required string pattern,string group,string artifact){
		local.rtn=replace(pattern,'{group}',group,'all');
		local.rtn=replace(rtn,'{artifact}',artifact,'all');
		return rtn;
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



	
	/**
	* this flushes the cache if the is a new version available
	* 
	*/
	public string function flushAndBuild() {
		application.repoMatch={};
		application.infoData={}
		_flushAndBuild("snapshots");
		_flushAndBuild("releases");
	}

	private string function _flushAndBuild(string type) {
		setting requesttimeout="1000";
		
		local.info=getAvailableVersions(type,true,true,false);
		local.art=getArtifactDirectory();
		local.diff=DateDiff("n",info.pomDate,now());
		
		if(diff>10) return;

		// flush
		directory action="list" directory=art name="local.dir";
		loop query=dir {
			if(find(info.version,dir.name)) {
				try{fileDelete(local.art&dir.name);}catch(e){}
				try{if(hasS3)fileDelete(toS3Path(local.art&dir.name));}catch(e){}
			}
		}
			
		// build
		getExpress(info.version); // build express gets the dependecies and the loader
		getCore(info.version); // extracts the core from the loader
		getDependencies(info.version);		
		// no longer needed getLibs(info.version); // build the libs zip
		getWar(info.version); // build the war
		getLoaderAll(info.version);

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
		if(!fileExists(jar)) fileCopy(getInfo(version:version,checkIgnoreMajor:false).jarSrc,jar); // download it to local
		return jar;
	}
	

	/**
	* returns local location for the loader (lucee.jar) of a specific version (get downloaded if necessary)
	* @version version to get jars for, can also be 
	*/
	public string function getLoaderAll(required string version, boolean doPack200=false) {
		local.jar=getArtifactDirectory()&"lucee-all-"&version&(doPack200?"-pack":"")&".jar"; // the jar
		
		if(!fileExists(jar)) {
			local.info=getInfo(version:version,checkIgnoreMajor:false); // get info for defined version
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
			//throw arrayToList(dependencies);
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


	/** THIS IS NO LONGER NEEDED BECAUSE THE lucee.jar NOW CONTAINS THE FELIX JAR
	* returns location of a zip file containing felix and lucee jar (get downloaded if necessary)
	* @version version to get jars for
	*/
	public string function getLibs(required string version) {
		local.info=getInfo(version:version,checkIgnoreMajor:false); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-libs-"&info.version&".zip";
		if(!fileExists(zip)) {
			local.felix=getFelix(version); 	// felix.jar
			local.lucee=getLoader(version);	// lucee.jar

			// let's zip it
			zip action="zip" file=zip overwrite=true {
				zipparam source=felix;
				zipparam source=lucee;
			}
		}
		return zip;
	}

	/**
	* returns local location for the felix jar used for the given version
	* @version version to get jar for
	*/
	public string function getFelix(required string version) {
		local.info=getInfo(version); // get info for defined version
		
		local.dependency=readDependenciesFromPOM(info.pomSrc,true,"org.apache.felix"); 
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
		local.info=getInfo(version); // get info for defined version
		
		local.dependency=readDependenciesFromPOM(info.pomSrc,true,"org.apache.felix"); 
		return dependency[1].jar;
	}

	//readDependenciesFromPOM(string pom, boolean extended=false,string specifivDep="")



	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getExpress(required string version) {
		local.info=getInfo(version:version,checkIgnoreMajor:false); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-express-"&info.version&".zip";
		

		local.valZip=validateArtifact(zip);

		if(valZip.len()) return valZip;
		//if(fileExists(zip)) return zip;
		
		
		// Ccreate the express zip
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
		storeToS3(zip);
		return zip;
	}

	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getWar(required string version) {
		local.info=getInfo(version:version,checkIgnoreMajor=false); // get info for defined version
		local.dir=getArtifactDirectory();
		local.war=dir&"lucee-"&info.version&".war";
		
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

	private function validateArtifact(required string path) {
		// fist we check if we have the file already on s3
		if(hasS3) {
			local.s3Path=toS3Path(path);
			if(fileExists(s3Path)) return s3Path;
		}

		// do we have it at least local?
		if(fileExists(path)) {
			storeToS3(path);
			return path;
		}
		return ""; // not exist at all
	}

	private function storeToS3(required string path) {
		// TODO syncronze this
		thread {
			if(hasS3)fileCopy(path,toS3Path(path));
		}
	}

	private function toS3Path(required string path) {
		local.fileName=listLast(path,"\/");
		return S3_DIRECTORY&fileName;
	}


}
