component {
	variables.listPattern=	"https://oss.sonatype.org/service/local/lucene/search?g={group}&a={artifact}";
	//defaultRepo="https://oss.sonatype.org/content/repositories/releases";
	variables.defaultRepo="http://central.maven.org/maven2";
	variables.group="org.lucee";
	variables.artifact="lucee";
	variables.NL="
";
	// this are version that should not be used in any case
	variables.ignoreVersions=["5.0.0.22","5.0.0.travis-74435522-SNAPSHOT"];

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
	* return information about a specific version
	* @version version to get info for
	*/
	public struct function getInfo(required string version){
		if(isNull(application.infoData)) application.infoData={};
		
		if(isNull(application.infoData[version])) {
			local.qry= getAvailableVersions(type:'all', extended:true, onlyLatest:false,specificVersion:version);
			if(qry.recordcount==0) throw "no info found for version ["&version&"]";
			application.infoData[version] = QueryRowData(qry,1);

		}
		return application.infoData[version];
		
	}

	/**
	* return information about available versions
	* @type one of the following (snapshots,releases or all)
	* @extended when true also return the location of the jar and pom file, but this is slower (has to make addional http calls)
	* @onlyLatest only return the latest version
	*/
	public query function getAvailableVersions(string type='all', boolean extended=false, boolean onlyLatest=false){
		if(extended){
			setting requesttimeout="1000";
		}
		// validate input
		if(type!='all' && type!='snapshots' && type!='releases')
			throw "provided type [#type#] is invalid, valid types are [all,snapshots,releases]";

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
		local.qry=queryNew("groupId,artifactId,version,type"&(extended?",pomSrc,pomDate,jarSrc,jarDate":""));
		loop array=raw.data item="local.entry" {
			if(isNull(entry.artifactHits[1])) continue;
			local.ah=entry.artifactHits[1];

			// ignore list
			if(arrayContains(variables.ignoreVersions,entry.version)) continue;
			// check type
			if(type!="all" && type!=ah.repositoryId) continue;
			// latest
			if(onlyLatest && entry.version!=entry.latestSnapshot && entry.version!=entry.latestRelease) continue;
			// specific
			if(!isNull(specificVersion) && specificVersion!=entry.version) continue;

			local.row=qry.addRow();
			if(extended)local.sources=getDetail(repos[ah.repositoryId],entry.groupId,entry.artifactId,entry.version);

			//dump(sources);
			qry.setCell("groupId",entry.groupId,row);
			qry.setCell("artifactId",entry.artifactId,row);
			qry.setCell("version",entry.version,row);
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

	private function getTempDirectory(){
		local.dir=getDirectoryFromPath(getCurrenttemplatePath())&"temp#getTickCount()#/";
		if(!directoryExists(dir))directoryCreate(dir);
		return dir
	}



	
	/**
	* this flushes the cache if the is a new version available
	* 
	*/
	public string function flushAndBuild() {
		_flushAndBuild("snapshots");
		_flushAndBuild("releases");
	}

	private string function _flushAndBuild(string type) {
		setting requesttimeout="1000";
		
		local.info=getAvailableVersions(type,true,true);
		local.art=getArtifactDirectory();
		// flush
		directory action="list" directory=art name="local.dir";
		loop query=dir {
			if(find("lucee-"&info.version,dir.name)==1) {
				fileDelete(local.art&dir.name);
			}
		}
			
		// build
		getExpress(info.version); // build express gets the dependecies and the loader
		getCore(info.version); // extracts the core from the loader
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
		if(!fileExists(jar)) fileCopy(getInfo(version).jarSrc,jar); // get it local
		return jar;
	}


	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get jars for
	*/
	public string function getDependencies(required string version) {
		local.info=getInfo(version); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-"&info.version&"-dependencies.zip";
		if(!fileExists(zip)) {
			local.dependencies=readDependenciesFromPOM(info.pomSrc); // get dependcies

			// first we store the file locally, if not exist locally yet
			loop array=dependencies item="local.dep" {
					local.trg=dir&listLast(dep.jar,"/");
					if(!fileExists(trg))
						fileCopy(dep.jar,trg);

			}

			// let's zip it
			zip action="zip" file=zip overwrite=true {
				loop array=dependencies item="local.dep" {
					local.trg=dir&listLast(dep.jar,"/");
					zipparam source=trg;
				}
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

	//readDependenciesFromPOM(string pom, boolean extended=false,string specifivDep="")



	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getExpress(required string version) {
		local.info=getInfo(version); // get info for defined version
		local.dir=getArtifactDirectory();
		local.zip=dir&"lucee-"&info.version&"-express.zip";
		
		
		if(!fileExists(zip)) {
			try {
				// temp directory
				local.temp=getTempDirectory();

				// extension directory
				local.extDir=ExpandPath("build/extensions/");
				if(!directoryExists(extDir))directoryCreate(extDir);

				// common directory
				local.commonDir=ExpandPath("build/common/");
				if(!directoryExists(commonDir))directoryCreate(commonDir);

				// website directory
				local.webDir=ExpandPath("build/website/");
				if(!directoryExists(webDir))directoryCreate(webDir);

				// get the jars for that release
				local.jarsDir="#temp#jars";
				if(!directoryExists(jarsDir))directoryCreate(jarsDir);
				zip action="unzip" file="#getDependencies(version)#" destination=jarsDir;
				
				// unpack the servers
				zip action="unzip" file="#ExpandPath("build/servers/tomcat.zip")#" destination="#temp#tomcat";
				
				// let's zip it
				zip action="zip" file=zip overwrite=true {

				// tomcat server
					zipparam source=temp&"tomcat";

				// extensions to bundle
					zipparam source=extDir filter="*.lex" prefix="lucee-server/context/deploy";
				// jars
					// dependencies
					zipparam source="#temp#jars" filter="*.jar" prefix="lucee-server/bundles";
					// loader
					zipparam source=getLoader(version) entrypath="lib/ext/lucee.jar";

					// felix 
					zipparam source=getFelix(version) prefix="lib/ext/";
	       
				// common files
					zipparam source=commonDir;
				
				// website files
					zipparam source=webDir prefix="webapps/ROOT";

				}
			}
			finally {
				if(directoryExists(temp))directoryDelete(temp,true);
			}
		}
		return zip;
	}

	/**
	* returns local location for the core of a specific version (get downloaded if necessary)
	* @version version to get the express for 
	*/
	public string function getWar(required string version) {
		local.info=getInfo(version); // get info for defined version
		local.dir=getArtifactDirectory();
		local.war=dir&"lucee-"&info.version&".war";
		
		if(!fileExists(war)) {
			try {
				// temp directory
				local.temp=getTempDirectory();

				// extension directory
				local.extDir=ExpandPath("build/extensions/");
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
				local.jarsDir="#temp#jars";
				if(!directoryExists(jarsDir))directoryCreate(jarsDir);
				zip action="unzip" file="#getDependencies(version)#" destination=jarsDir;
				
				// let's zip it
				zip action="zip" file=war overwrite=true {

				// extensions to bundle
					zipparam source=extDir filter="*.lex" prefix="WEB-INF/lucee/deploy";
				// jars
					// dependencies
					zipparam source=jarsDir filter="*.jar" prefix="WEB-INF/lucee/bundles";

					// loader
					zipparam source=getLoader(version) entrypath="WEB-INF/lib/lucee.jar";

					// felix 
					zipparam source=getFelix(version) prefix="WEB-INF/lib/";
	       
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


}
