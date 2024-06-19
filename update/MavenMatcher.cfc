component {

	variables.mavenMappings = deserializeJSON( fileRead( "mavenMappings.json" ) );

	public function getMavenMappings(){
		return variables.mavenMappings;
	}

	public function getMatch(required string bundleName, string bundleVersion, boolean retry=true) {
		
		if ( !structKeyExists( variables.mavenMappings, arguments.bundleName ) ) {
			throw "no maven information for OSGi id [#arguments.bundleName#] found";
		}
		var mvnId=variables.mavenMappings[arguments.bundleName];
		var base="https://repo1.maven.org/maven2/";
		var base=base&replace(mvnId.group,'.','/','all')&"/"&mvnId.artifact&"/";
		
		var metaDir=getDirectoryFromPath(getCurrentTemplatePath())&"meta/";
		if(!directoryExists(metaDir)) directoryCreate(metaDir);

		var metaFile=metaDir&arguments.bundleName&".json";
		var meta = "";
		if( !fileExists(metaFile) ) {
			meta = fetchMavenMetaData( metaFile, base );
			arguments.retry = false;
		} else {
			meta = deserializeJson( fileRead( metaFile ) );
		}

		// no specific version defined
		if(isNull(arguments.bundleVersion) || isEmpty(arguments.bundleVersion) || arguments.bundleVersion=="latest") {
			return {'groupid':meta.groupId,'artifactid':meta.artifactid,'version':meta.latest
					,'url':base&meta.latest&"/"&meta.artifactid&"-"&meta.latest&".jar"
			};
		}

		// 1 to 1 match
		loop array=meta.versions item="local.version" {
			if(version==arguments.bundleVersion) {
				return {'groupid':meta.groupId,'artifactid':meta.artifactid,'version':version
				,'url':base&version&"/"&meta.artifactid&"-"&version&".jar"
				};
			}	
		}
		// removed last 0 (sometime a zero is added for osgi version numbers)
		loop array=meta.versions item="local.version" {
			if(version&".0"==arguments.bundleVersion) {
				return {'groupid':meta.groupId,'artifactid':meta.artifactid,'version':version
				,'url':base&version&"/"&meta.artifactid&"-"&version&".jar"
				};
			}
		}
		// at this point we haven't been able to match the requested bundle from the cached meta data
		var metaInfo = GetFileInfo( metaFile );
		// only retry meta data once per hour
		if ( arguments.retry && dateDiff("n", metaInfo.LastModified, now() ) gt 60 ){
			log text="Maven fetch meta data RETRY [#metafile#]" type="error";
			// maybe the local cache is out of date
			fetchMavenMetaData( metaFile, base );
			getMatch( bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion, retry=false );
		} else {
			throw "No matching maven version for OSGi version [#arguments.bundleVersion#] found, "
				& "for [mvn:#meta.groupId#:#meta.artifactId#,OSGi:#arguments.bundleName#], "
				& " available maven versions are [#arrayToList(meta.versions, ", ")#]";
		}
		//var targetURL=base&mvnVersion&"/"&mvnId.artifact&"-"&mvnVersion&".jar";
		//return targetURL;
	}

	private struct function fetchMavenMetaData( required string metaFile, required string baseUrl ){
		var metaUrl = arguments.baseUrl & "maven-metadata.xml";
		http url=metaUrl result="local.res";
		if ( res.status_code neq 200 || !isXml( res.filecontent ) ){
			log text="fetchMavenMetaData [#metaUrl#] returned [#res.statuscode#]" type="error";
			throw "fetchMavenMetaData [#metaUrl#] returned [#res.statuscode#]";
		}
		var xml = xmlParse(res.filecontent);
		var meta['versions'] = [];
		meta['groupId'] = xml.XmlRoot.groupId.XmlText;
		meta['artifactId'] = xml.XmlRoot.artifactId.XmlText;
		meta['latest'] = xml.XmlRoot.versioning.latest.XmlText;
		loop array=xml.XmlRoot.versioning.versions.XmlChildren item="local.node" {
			arrayAppend( meta.versions,node.XmlText );
		}
		fileWrite( arguments.metaFile, serializeJson(meta) );
		return meta;
	}
}