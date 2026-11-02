/**
 * LDEV-6796: the Lucee core (org.lucee:lucee) in the Maven repositories, the ones the extensions are read from
 * (see MavenExtensionSource), mainly the "mixed" Lucee repository (the Maven bridge), which serves every version
 * (releases, RC, BETA, ALPHA and snapshots) with deterministic file names and redirects them to where the files are.
 *
 * - the versions come from the maven-metadata.xml of the repositories, see listVersions().
 * - the files of a version are looked up by name, see getCoreFileUrl(), a repository is asked if it has the file
 *   before it is pointed to (a repository like Maven Central has the jars, but not the .lco, .war or express files).
 *
 * Nothing is downloaded here.
 */
component extends="MavenExtensionSource" accessors=true {

	// the distributions of the core a repository can have, as the type used by the update provider: classifier and extension of the file
	variables._types = {
		  jar     : { classifier="",        extension="jar" }
		, light   : { classifier="light",   extension="jar" }
		, zero    : { classifier="zero",    extension="jar" }
		, lco     : { classifier="",        extension="lco" }
		, war     : { classifier="",        extension="war" }
		, express : { classifier="express", extension="zip" }
	};

	function init() {
		super.init( argumentCollection=arguments );

		variables._artifact     = "lucee";
		variables._existing     = StructNew( "sync" ); // file url > { exists, time }
		variables._existsTtl    = 86400; // seconds, a file that is there stays there
		variables._missingTtl   = 300;   // seconds, a file that is not there yet might be soon
		variables._coreSnapshotFiles = StructNew( "sync" ); // version metadata url > { files, time }

		return this;
	}

	// the types of core files, as { type : { classifier, extension } }
	public array function getTypes() {
		return StructKeyArray( variables._types );
	}

	public boolean function hasType( required string type ) {
		return StructKeyExists( variables._types, arguments.type );
	}

	/**
	 * The versions of the core of all the repositories. Returns
	 *   { versions={ version=[ repos the version is in, in order of preference ] }, complete=boolean }
	 * "complete" is false when a repository could not be read.
	 */
	public struct function listVersions() {
		return _listVersions( variables._artifact );
	}

	/**
	 * The name of the file of a type of a version in the repository (the Maven layout), empty when the name can't be told,
	 * which is the case for a snapshot of a repository whose metadata can't be read.
	 */
	public string function getCoreFileName( required string type, required string version, required string repo ) {
		_checkType( arguments.type );

		return _coreFileName( arguments.type, arguments.version, arguments.repo );
	}

	/**
	 * The url of the file of a type of a version, in the first of the repos that has the file, the mixed
	 * repos (the Maven bridge) first, they have all of the types. Returns an empty string when none of the repos
	 * can tell it has the file: it is not there, or the repos could not be reached (that is logged).
	 */
	public string function getCoreFileUrl( required string type, required string version, required array repos ) {
		_checkType( arguments.type );

		for ( var repo in _mixedFirst( arguments.repos ) ) {
			var fileName = _coreFileName( arguments.type, arguments.version, repo );

			if ( !Len( fileName ) ) {
				continue;
			}

			var fileUrl = _versionUrl( repo, variables._artifact, arguments.version ) & fileName;

			if ( _fileExists( fileUrl ) ) {
				return fileUrl;
			}
		}

		return "";
	}

// PRIVATE HELPERS

	private function _checkType( required string type ) {
		if ( !hasType( arguments.type ) ) {
			throw( type="MavenCoreSource", message="Unknown core file type [#arguments.type#], supported are [#ArrayToList( getTypes() )#]" );
		}
	}

	private array function _mixedFirst( required array repos ) {
		var sorted = [];

		for ( var repo in arguments.repos ) {
			if ( ArrayFind( variables.mixedRepos, repo ) ) {
				ArrayAppend( sorted, repo );
			}
		}

		for ( var repo in arguments.repos ) {
			if ( !ArrayFind( sorted, repo ) ) {
				ArrayAppend( sorted, repo );
			}
		}

		return sorted;
	}

	/**
	 * Name of the file of a type of a version in a repository: <artifactId>-<version>[-<classifier>].<extension>.
	 * The files of a snapshot are timestamped on most repositories, the name of the file is in the maven-metadata.xml of the version.
	 */
	private string function _coreFileName( required string type, required string version, required string repo ) {
		var spec  = variables._types[ arguments.type ];
		var value = arguments.version;

		if ( isSnapshot( arguments.version ) ) {
			var files = _snapshotValues( arguments.version, arguments.repo );

			if ( !IsStruct( files ) ) {
				return ""; // the metadata of the version can't be read
			}

			value = files[ spec.classifier & "|" & spec.extension ] ?: arguments.version; // not in the metadata: the plain name
		}

		return variables._artifact & "-" & value & ( Len( spec.classifier ) ? "-" & spec.classifier : "" ) & "." & spec.extension;
	}

	/**
	 * The "value" (the version of a file of a snapshot, i.e. 7.1.3.67-20261030.053501-3) of the files of a snapshot in
	 * the maven-metadata.xml of the version of a repository, by classifier|extension. An empty struct when the repository has no
	 * metadata for the version, an empty string when it can't be read.
	 */
	private any function _snapshotValues( required string version, required string repo ) {
		var metaUrl = _versionUrl( arguments.repo, variables._artifact, arguments.version ) & "maven-metadata.xml";
		var cached  = variables._coreSnapshotFiles[ metaUrl ] ?: "";

		if ( IsStruct( cached ) && DateDiff( "s", cached.time, Now() ) < variables._snapshotTtl ) {
			return cached.files;
		}

		var page = _get( metaUrl );

		if ( page.status == 404 ) {
			return {}; // a repository that has no metadata for the version
		}

		if ( page.status != 200 ) {
			SystemOutput( "Maven snapshot metadata [#metaUrl#] could not be read: #page.status# #page.error#", true );
			return "";
		}

		var files = {};

		try {
			for ( var node in XmlSearch( XmlParse( Trim( page.content ) ), "/metadata/versioning/snapshotVersions/snapshotVersion" ) ) {
				var classifier = StructKeyExists( node, "classifier" ) ? Trim( node.classifier.xmlText ) : "";

				files[ classifier & "|" & Trim( node.extension.xmlText ?: "" ) ] = Trim( node.value.xmlText );
			}
		} catch ( any e ) {
			SystemOutput( "Maven snapshot metadata [#metaUrl#] is not valid: #e.message#", true );
			return "";
		}

		variables._coreSnapshotFiles[ metaUrl ] = { files=files, time=Now() };

		return files;
	}

	/**
	 * Does the repository have the file. A redirect (the Maven bridge points to where the file is) counts as the file, a 404
	 * as no file. Anything else (the repository can't be reached or is failing) can't tell, that is logged and counts as no file,
	 * but it is not remembered.
	 */
	private boolean function _fileExists( required string fileUrl ) {
		var cached = variables._existing[ arguments.fileUrl ] ?: "";

		if ( IsStruct( cached ) && DateDiff( "s", cached.time, Now() ) < ( cached.exists ? variables._existsTtl : variables._missingTtl ) ) {
			return cached.exists;
		}

		var result = {};

		for ( var attempt=0; attempt<=variables.retries; attempt++ ) {
			_waitForRetry( attempt );
			result = variables.httpClient.head( arguments.fileUrl, variables.timeout );

			if ( !_isTemporaryFailure( result.status ) ) {
				break;
			}
		}

		if ( result.status >= 200 && result.status < 400 ) {
			variables._existing[ arguments.fileUrl ] = { exists=true, time=Now() };
			return true;
		}

		if ( result.status == 404 ) {
			variables._existing[ arguments.fileUrl ] = { exists=false, time=Now() };
			return false;
		}

		SystemOutput( "Maven file [#arguments.fileUrl#] could not be checked: #result.status# #result.error#", true );

		return false;
	}

}
