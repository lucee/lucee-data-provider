component {

	variables.mavenMappings = deserializeJSON( fileRead( "mavenMappings.json" ) );
	variables.mixedRepo     = "https://maven.lucee-services.com";

	/**
	 * @mixedRepo the Lucee repository (maven.lucee-services.com) that holds the org.lucee bundles which are not
	 *            on Maven Central, for example the ones published with the "Upload Maven jar" workflow of lucee/Lucee
	 */
	public function init( string mixedRepo="https://maven.lucee-services.com/" ) {
		variables.mixedRepo = ReReplace( Trim( arguments.mixedRepo ), "/+$", "" );
		return this;
	}

	/**
	 * Repositories of the raw search, in that order: Maven Central first, the Lucee repository after it
	 */
	public array function rawSearchRepositories() {
		var repositories = [
			  "https://repo1.maven.org/maven2"
			, "https://raw.githubusercontent.com/lucee/mvn/master/releases"
		];
		if ( Len( variables.mixedRepo ) ) {
			ArrayAppend( repositories, variables.mixedRepo );
		}
		ArrayAppend( repositories, "https://oss.sonatype.org/content/repositories/snapshots" );
		return repositories;
	}

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

	/**
	 * @jarsOnly only look for a jar, never answer a .lex (used to find a public URL for a jar that was extracted from a lex)
	 */
	public function findBundleUrl( required string bundleName, string bundleVersion="latest", rawSearch=false, boolean jarsOnly=false ) {
		if ( !arguments.rawSearch ) {
			try {
				var match = getMatch( arguments.bundleName, arguments.bundleVersion );
			} catch( maven.matcher.not.found e ) {
				return "";
			}

			return match.url ?: "";
		}

		var repositories = rawSearchRepositories();
		var uris = rawSearchPaths( arguments.bundleName, arguments.bundleVersion );
		if ( arguments.jarsOnly ) {
			uris = uris.filter( function( uri ) {
				return Right( uri, 4 ) == ".jar";
			} );
		}

		for( var rep in repositories ) {
			for ( var candidate in uris ) {
				if ( FileExists( rep & candidate ) ) {
					return rep & candidate;
				}
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
			if ( !arguments.jarsOnly ) {
				ArrayAppend( urls, repositories[ 1 ] & "/org/lucee/" & art1 & "/" & arguments.bundleVersion & "/" & art1 & "-" & arguments.bundleVersion & ".lex" );
				ArrayAppend( urls, repositories[ 1 ] & "/org/lucee/" & art2 & "/" & arguments.bundleVersion & "/" & art2 & "-" & arguments.bundleVersion & ".lex" );
			}

			for( var _url in urls ) {
				if( FileExists( _url ) ) {
					return _url;
				}
			}
		}

		return "";
	}


	/**
	 * Maven layout paths to try for a raw Central/OSGi lookup, starting with
	 * a slash (the repository base is prepended by findBundleUrl).
	 * A single-segment name like "antlr" is also tried as groupId+artifactId
	 * (/antlr/antlr/2.7.6/antlr-2.7.6.jar), not only /antlr/2.7.6/antlr-2.7.6.jar.
	 */
	public array function rawSearchPaths( required string bundleName, required string bundleVersion ) {
		var uris = [];

		if ( StructKeyExists( variables.mavenMappings, arguments.bundleName ) ) {
			var mvnId = variables.mavenMappings[ arguments.bundleName ];
			ArrayAppend( uris, "/" & Replace( mvnId.group, '.', '/', 'all' ) & "/" & mvnId.artifact
				& "/" & arguments.bundleVersion
				& "/" & mvnId.artifact & "-" & arguments.bundleVersion & ".jar" );
			// older versions of a bundle can be published under other coordinates (com.mysql.cj 8.0.19 is mysql:mysql-connector-java,
			// com.mysql:mysql-connector-j starts at 8.0.31)
			for ( var alt in ( mvnId.alt ?: [] ) ) {
				ArrayAppend( uris, "/" & Replace( alt.group, '.', '/', 'all' ) & "/" & alt.artifact
					& "/" & arguments.bundleVersion
					& "/" & alt.artifact & "-" & arguments.bundleVersion & ".jar" );
			}
			// a Lucee build of a mapped bundle (e.g. xmpcore 5.1.2.0002L) is not in the mapped group, it is published as org.lucee:<Bundle-SymbolicName>
			if ( Left( arguments.bundleName, 10 ) != "org.lucee." && mvnId.group != "org.lucee" ) {
				ArrayAppend( uris, _luceeBundlePath( arguments.bundleName, arguments.bundleVersion ) );
			}
			return uris;
		}

		ArrayAppend( uris, "/" & Replace( arguments.bundleName, '.', '/', 'all' )
			& "/" & arguments.bundleVersion
			& "/" & ListLast( arguments.bundleName, '.' )
			& "-" & arguments.bundleVersion & ".jar" );

		if ( ListLen( arguments.bundleName, "." ) == 1 ) {
			ArrayAppend( uris, "/" & arguments.bundleName & "/" & arguments.bundleName
				& "/" & arguments.bundleVersion
				& "/" & arguments.bundleName & "-" & arguments.bundleVersion & ".jar" );
		}

		// a bundle that is on no public Maven repository is published as org.lucee:<Bundle-SymbolicName>:<Bundle-Version>
		// (the "Upload Maven jar" workflow of lucee/Lucee), e.g. org.lucee:apache.lucene.analyzers:2.4.1
		if ( Left( arguments.bundleName, 10 ) != "org.lucee." ) {
			ArrayAppend( uris, _luceeBundlePath( arguments.bundleName, arguments.bundleVersion ) );
		}

		// the bundle of an extension (e.g. redis.extension 2.9.0.3-BETA) is in the lex of org.lucee:<dashed-name>, the
		// listing only has the latest version of an extension, the older ones are found through the Maven layout
		if ( Left( arguments.bundleName, 10 ) != "org.lucee." ) {
			var lexArt = Replace( arguments.bundleName, ".", "-", "all" );
			ArrayAppend( uris, "/org/lucee/" & lexArt & "/" & arguments.bundleVersion & "/" & lexArt & "-" & arguments.bundleVersion & ".lex" );
		}

		// org.lucee.* OSGi names are often published as org.lucee:<dashed-name>
		// with a .lex (the extension) rather than a .jar. Try both.
		if ( Left( arguments.bundleName, 10 ) == "org.lucee." ) {
			var art1 = Mid( arguments.bundleName, 11 );
			var art2 = Replace( art1, ".", "-", "all" );
			loop array=[ art2, art1 ] item="local.art" {
				var base = "/org/lucee/" & art & "/" & arguments.bundleVersion & "/" & art & "-" & arguments.bundleVersion;
				ArrayAppend( uris, base & ".jar" );
				ArrayAppend( uris, base & ".lex" );
				if ( art1 == art2 ) {
					break;
				}
			}
		}

		return uris;
	}

	// org.lucee:<Bundle-SymbolicName>:<Bundle-Version>, the layout of the "Upload Maven jar" workflow of lucee/Lucee
	private string function _luceeBundlePath( required string bundleName, required string bundleVersion ) {
		return "/org/lucee/" & arguments.bundleName & "/" & arguments.bundleVersion
			& "/" & arguments.bundleName & "-" & arguments.bundleVersion & ".jar";
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
		loop array=xml.XmlRoot.versioning.versions.XmlChildren item="local.node" {
			arrayAppend( meta.versions, node.XmlText );
		}

		try {
			meta['latest'] = xml.XmlRoot.versioning.latest.XmlText;
		} catch ( e ){ // some like apache oro don't have latest?
			meta['latest'] = meta.versions[ len( meta.versions) ];
		}

		fileWrite( arguments.metaFile, serializeJson(meta) );
		return meta;
	}

	public struct function findLuceeBundles( string artifact ) cachedWithin="request" {

		systemOutput("searching for lucee bundles [#artifact#]", true);

		http url="https://search.maven.org/solrsearch/select" result="local.res" {
			httpparam type="url" name="q" value="q=a:#arguments.artifact#+AND+g:org.lucee";
			httpparam type="url" name="rows" value="20";
			httpparam type="url" name="wt" value="json";
		};

		var result = {
			success: false,
			statusCode = ( res.status_code ?: 0 ),
			error: "",
			mapping: {}
		}

		if ( res.status_code neq 200 || !isJson( res.filecontent )){
			result.error = res.filecontent;
			return result;
		}

		var json = deserializeJSON ( res.filecontent );

		if ( isNull( json.response.numFound ) || json.response.numFound < 1  ){
			result.error= "no candidate matches returned" ;
			return result;
		}

		for ( var b in json.response.docs ){
			if (b.artifact == arguments.artifact ){
				result.success = true;
				result.mapping = {
					"group": b.g,
					"artifact": b.a,
					"latest": b.latestVersion
				}
				return result;
			}
		}

		result.error= "no matches found within returned results" ;
		return result;
	}
}