component {

	variables.mavenMappings = deserializeJSON( fileRead( "mavenMappings.json" ) );
	// bundles that ship inside an extension .lex of another name: bundle name > [ org.lucee artifactId of the lex ]
	variables.lexBundles    = deserializeJSON( fileRead( "lexBundles.json" ) );
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

	public function findBundleUrl( required string bundleName, string bundleVersion="latest", rawSearch=false ) {
		if ( !arguments.rawSearch ) {
			try {
				var match = getMatch( arguments.bundleName, arguments.bundleVersion );
			} catch( maven.matcher.not.found e ) {
				return "";
			}

			return match.url ?: "";
		}

		var repositories = rawSearchRepositories();
		// "latest" of a bundle uploaded as org.lucee:<Bundle-SymbolicName>: the <latest> of its maven-metadata.xml
		if ( arguments.bundleVersion == "latest" ) {
			var latest = Len( variables.mixedRepo ) ? latestLuceeBundleVersion( arguments.bundleName ) : "";
			if ( !Len( latest ) ) {
				return "";
			}
			arguments.bundleVersion = latest;
		}
		var uris = rawSearchPaths( arguments.bundleName, arguments.bundleVersion );

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

		// org.lucee.* OSGi names are often published as org.lucee:<dashed-name>. Only jars: a bundle is never
		// extracted from an extension .lex, a jar that is only inside a lex is published as
		// org.lucee:<Bundle-SymbolicName>:<Bundle-Version> (the "Upload Maven jar" workflow of lucee/Lucee)
		if ( Left( arguments.bundleName, 10 ) == "org.lucee." ) {
			var art1 = Mid( arguments.bundleName, 11 );
			var art2 = Replace( art1, ".", "-", "all" );
			loop array=[ art2, art1 ] item="local.art" {
				ArrayAppend( uris, "/org/lucee/" & art & "/" & arguments.bundleVersion & "/" & art & "-" & arguments.bundleVersion & ".jar" );
				if ( art1 == art2 ) {
					break;
				}
			}
			// a jar of an extension that was uploaded as org.lucee:<Bundle-SymbolicName> (e.g. org.lucee:org.lucee.oracle)
			ArrayAppend( uris, _luceeBundlePath( arguments.bundleName, arguments.bundleVersion ) );
		}

		return uris;
	}

	/**
	 * The extension .lex files (org.lucee:<artifact>:<version>.lex) that can contain an OSGi bundle, for the .lex
	 * fallback of the bundle download (BundleDownloadService). The artifact is guessed from the bundle name, the
	 * same way the lookups did before the fallback was switched off:
	 *   - org.lucee.axis.extension 1.4.0.27-SNAPSHOT > org.lucee:axis-extension:1.4.0.27-SNAPSHOT (and axis.extension)
	 *   - redis.extension 2.9.0.3-BETA               > org.lucee:redis-extension:2.9.0.3-BETA
	 *   - a bundle that ships inside an extension of another name is listed in lexBundles.json
	 *     (mssqljdbc4 4.0.2206.100 > org.lucee:mssql-jdbc-extension:4.0.2206.100)
	 * Only URLs that exist are returned (one HEAD per candidate and repository until found), "latest" has none.
	 */
	public array function findLexUrls( required string bundleName, required string bundleVersion ) {
		if ( !Len( arguments.bundleVersion ) || arguments.bundleVersion == "latest" ) {
			return [];
		}
		var found = [];
		for ( var path in lexSearchPaths( arguments.bundleName, arguments.bundleVersion ) ) {
			for ( var rep in lexSearchRepositories() ) {
				if ( FileExists( rep & path ) ) {
					ArrayAppend( found, rep & path );
					break;
				}
			}
		}
		return found;
	}

	// the Lucee repository first (most extension lex files are there), then Maven Central and the snapshots
	public array function lexSearchRepositories() {
		var repositories = [];
		if ( Len( variables.mixedRepo ) ) {
			ArrayAppend( repositories, variables.mixedRepo );
		}
		ArrayAppend( repositories, "https://repo1.maven.org/maven2" );
		ArrayAppend( repositories, "https://oss.sonatype.org/content/repositories/snapshots" );
		return repositories;
	}

	public array function lexSearchPaths( required string bundleName, required string bundleVersion ) {
		var artifacts = [];
		for ( var art in variables.lexBundles[ arguments.bundleName ] ?: [] ) {
			ArrayAppend( artifacts, art );
		}
		if ( Left( arguments.bundleName, 10 ) == "org.lucee." ) {
			var art1 = Mid( arguments.bundleName, 11 );
			ArrayAppend( artifacts, Replace( art1, ".", "-", "all" ) );
			ArrayAppend( artifacts, art1 );
		} else {
			ArrayAppend( artifacts, Replace( arguments.bundleName, ".", "-", "all" ) );
		}

		var paths = [];
		var seen  = {};
		for ( var a in artifacts ) {
			if ( !Len( a ) || StructKeyExists( seen, a ) || !ReFind( "^[A-Za-z0-9._-]+$", a ) || !ReFind( "^[A-Za-z0-9._+-]+$", arguments.bundleVersion ) ) {
				continue;
			}
			seen[ a ] = true;
			ArrayAppend( paths, "/org/lucee/" & a & "/" & arguments.bundleVersion & "/" & a & "-" & arguments.bundleVersion & ".lex" );
		}
		return paths;
	}

	/**
	 * The latest version of org.lucee:<bundleName> on the Lucee repository (maven-metadata.xml, written by the
	 * "Upload Maven jar" workflow), "" when there is none.
	 */
	public string function latestLuceeBundleVersion( required string bundleName ) {
		try {
			http url=variables.mixedRepo & "/org/lucee/" & arguments.bundleName & "/maven-metadata.xml" timeout=10 throwonerror=false result="local.res";
			if ( Val( res.status_code ?: 0 ) != 200 || !IsXml( res.filecontent ) ) {
				return "";
			}
			var versioning = XmlParse( res.filecontent ).XmlRoot.versioning;
			if ( StructKeyExists( versioning, "release" ) && Len( versioning.release.XmlText ) ) {
				return versioning.release.XmlText;
			}
			if ( StructKeyExists( versioning, "latest" ) && Len( versioning.latest.XmlText ) ) {
				return versioning.latest.XmlText;
			}
		} catch ( any e ) {}
		return "";
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