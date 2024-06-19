component {

	variables.mavenMappings = deserializeJSON( fileRead( "mavenMappings.json" ) );

	public function getMavenMappings(){
		return variables.mavenMappings;
	}

	public function getMatch(required string bundleName, string bundleVersion, boolean retry=true) {
		if ( !structKeyExists( variables.mavenMappings, arguments.bundleName ) ) {
			throw( type="maven.matcher.not.found", message="no maven information for OSGi id [#arguments.bundleName#] found" );
		}

		var mvnId = variables.mavenMappings[arguments.bundleName];
		var base  = "https://repo1.maven.org/maven2/";
		var base  = base & replace( mvnId.group, '.', '/', 'all' ) & "/" & mvnId.artifact & "/";
		
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
			throw( type="maven.matcher.not.found", message="No matching maven version for OSGi version [#arguments.bundleVersion#] found, "
				& "for [mvn:#meta.groupId#:#meta.artifactId#,OSGi:#arguments.bundleName#], "
				& " available maven versions are [#arrayToList(meta.versions, ", ")#]" );
		}
		//var targetURL=base&mvnVersion&"/"&mvnId.artifact&"-"&mvnVersion&".jar";
		//return targetURL;
	}

	public function findBundleUrl( required string bundleName, string bundleVersion="latest", rawSearch=false ) {
		if ( !arguments.rawSearch ) {
			try {
				var match = getMatch( arguments.bundleName, arguments.bundleVersion );
			} catch( maven.matcher.not.found e ) {
				return "";
			}

			return match.url ?: "";
		}

		var repositories = [
			  "https://repo1.maven.org/maven2"
			, "https://raw.githubusercontent.com/lucee/mvn/master/releases"
			, "https://oss.sonatype.org/content/repositories/snapshots"
		];
		var uri = "";

		if ( StructKeyExists( variables.mavenMappings, arguments.bundleName ) ) {
			var mvnId = variables.mavenMappings[ arguments.bundleName ];
			uri = "/" & Replace( mvnId.group, '.', '/', 'all' ) & "/" & mvnId.artifact &
			      "/" & arguments.bundleVersion &
			      "/" & mvnId.artifact & "-" & arguments.bundleVersion & ".jar";

		} else {
			uri = "/" & Replace( arguments.bundleName, '.', '/', 'all' ) &
			      "/" & arguments.bundleVersion &
			      "/" & ListLast( arguments.bundleName, '.' ) &
			      "-" & arguments.bundleVersion & ".jar";
		}

		for( var rep in repositories ) {
			if ( FileExists( rep & uri ) ) {
				return rep & uri;
			}
		}

		// if an org.lucee bundle, we have some other guesses
		if( Left( arguments.bundleName, 10 ) == 'org.lucee.' ) {
			var art1 = Mid( arguments.bundleName, 11 );
			var art2 = Replace( art1, '.', '-', 'all' );
			var urls=[
				  repositories[ 1 ] & "/org/lucee/" & art1 & "/" & arguments.bundleVersion & "/" & art1 & "-" & arguments.bundleVersion & ".jar"
				, repositories[ 1 ] & "/org/lucee/" & art2 & "/" & arguments.bundleVersion & "/" & art2 & "-" & arguments.bundleVersion & ".jar"
			];

			for( var _url in urls ) {
				if( FileExists( _url ) ) {
					return _url;
				}
			}
		}

		return "";
	}

	private struct function fetchMavenMetaData( required string metaFile, required string baseUrl ){
		var metaUrl = arguments.baseUrl & "maven-metadata.xml";
		http url=metaUrl result="local.res";
		if ( res.status_code neq 200 || !isXml( res.filecontent ) ){
			throw( type="maven.matcher.not.found", message="fetchMavenMetaData [#metaUrl#] returned [#res.statuscode#]" );
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