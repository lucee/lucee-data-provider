/**
 * LDEV-6789: discovers extensions published to Maven repositories, the same repositories Lucee core uses
 * (releases, snapshots and the "mixed" Lucee repository).
 *
 * - the artifacts (<group>/<artifactId>-extension) are discovered from the html directory listings of the
 *   repositories, the same way core does it. Not every repository can be listed (the snapshot repository
 *   of Sonatype can't), the artifacts those hold are looked up by the name of the artifacts found elsewhere.
 * - the versions of an artifact come from the maven-metadata.xml of the repositories.
 * - the file of a snapshot version is a timestamped one (<artifactId>-<version>-<yyyyMMdd.HHmmss>-<n>.lex),
 *   which is looked up in the maven-metadata.xml of the version.
 *
 * Nothing is downloaded here, see download(), the caller decides which files it needs.
 */
component accessors=true {

	property name="group"          type="string"  default="org.lucee";
	property name="suffix"         type="string"  default="-extension";
	property name="releaseRepos"   type="array";
	property name="snapshotRepos"  type="array";
	property name="mixedRepos"     type="array";
	property name="timeout"        type="numeric" default=20;   // seconds, listing and metadata requests
	property name="downloadTimeout" type="numeric" default=120; // seconds, file downloads
	property name="maxThreads"     type="numeric" default=10;
	property name="retries"        type="numeric" default=2;    // retries of a request that failed for a reason that is likely to be temporary
	property name="retryDelay"     type="numeric" default=500;  // milliseconds, times the number of the retry
	// something that does the http requests: .get( url ) and .download( url, file ), see _defaultHttpClient()
	property name="httpClient"     type="any";

	function init(
		  array   releaseRepos    = []
		, array   snapshotRepos   = []
		, array   mixedRepos      = []
		, string  group           = "org.lucee"
		, numeric timeout         = 20
		, numeric downloadTimeout = 120
		, numeric maxThreads      = 10
		, numeric retries         = 2
		, numeric retryDelay      = 500
		, any     httpClient
	) {
		variables.releaseRepos    = _normaliseRepos( arguments.releaseRepos );
		variables.snapshotRepos   = _normaliseRepos( arguments.snapshotRepos );
		variables.mixedRepos      = _normaliseRepos( arguments.mixedRepos );
		variables.group           = arguments.group;
		variables.timeout         = arguments.timeout;
		variables.downloadTimeout = arguments.downloadTimeout;
		variables.maxThreads      = arguments.maxThreads;
		variables.retries         = arguments.retries;
		variables.retryDelay      = arguments.retryDelay;
		variables.httpClient      = arguments.httpClient ?: _defaultHttpClient();
		variables._snapshotFiles  = StructNew( "sync" ); // version metadata url > { file, time }, a snapshot is replaced by a newer one at any time
		variables._snapshotTtl    = 300; // seconds

		return this;
	}

	public boolean function hasRepos() {
		return ArrayLen( variables.releaseRepos ) + ArrayLen( variables.snapshotRepos ) + ArrayLen( variables.mixedRepos ) > 0;
	}

	/**
	 * Lists the extension versions of all the repositories. Returns
	 *   { files=[ { name, artifact, version, repos=[ repo urls the version is in, in order of preference ] } ], complete=boolean }
	 * "complete" is false when a repository or an artifact could not be read.
	 */
	public struct function listExtensions() {
		var result = { files=[], complete=true };

		if ( !hasRepos() ) {
			return result;
		}

		var listing = _listArtifacts();
		result.complete = listing.complete;

		var found = StructNew( "sync" ); // artifact index > versions, the artifacts are read in parallel

		ArrayEach( listing.artifacts, function( artifact, index ) {
			found[ index ] = _listVersions( arguments.artifact );
		}, true, variables.maxThreads );

		for ( var i=1; i<=ArrayLen( listing.artifacts ); i++ ) {
			var artifactResult = found[ i ];

			if ( !artifactResult.complete ) {
				result.complete = false;
			}

			for ( var version in artifactResult.versions ) {
				ArrayAppend( result.files, {
					  name     = listing.artifacts[ i ] & "-" & version & ".lex"
					, artifact = listing.artifacts[ i ]
					, version  = version
					, repos    = artifactResult.versions[ version ]
				} );
			}
		}

		return result;
	}

	/**
	 * The url of the extension file of a version, in the first of the repos that has it.
	 * Returns an empty string when none of the repos can say where the file is.
	 */
	public string function getFileUrl( required string artifact, required string version, required array repos ) {
		for ( var repo in arguments.repos ) {
			var fileName = _fileName( arguments.artifact, arguments.version, repo );

			if ( Len( fileName ) ) {
				return _versionUrl( repo, arguments.artifact, arguments.version ) & fileName;
			}
		}

		return "";
	}

	/**
	 * Downloads the extension file of a version to the target file, from the first repo that has it.
	 * Throws when it can't be downloaded from any of them.
	 */
	public void function download( required string artifact, required string version, required array repos, required string target ) {
		var errors = [];

		for ( var repo in arguments.repos ) {
			var fileName = _fileName( arguments.artifact, arguments.version, repo );

			if ( !Len( fileName ) ) {
				ArrayAppend( errors, "#repo#: file not found" );
				continue;
			}

			var fileUrl    = _versionUrl( repo, arguments.artifact, arguments.version ) & fileName;
			var result = _download( fileUrl, arguments.target );

			if ( result.status == 200 ) {
				return;
			}

			ArrayAppend( errors, "#fileUrl#: #result.status# #result.error#" );
		}

		throw( type="MavenExtensionSource", message="Could not download [#arguments.artifact#] [#arguments.version#]: " & ArrayToList( errors, "; " ) );
	}

	public boolean function isSnapshot( required string version ) {
		return arguments.version.endsWith( "-SNAPSHOT" );
	}

// PRIVATE HELPERS

	/**
	 * The artifacts are the "<name>-extension" folders of the group folder of the repositories, a repository that
	 * can't be read makes the result incomplete. A repository that has no listing at all (no links) is not an error.
	 */
	private struct function _listArtifacts() {
		var result = { artifacts=[], complete=true };
		var names  = {};
		var repos  = _allRepos();
		var pages  = StructNew( "sync" ); // repo index > listing page, the repos are read in parallel

		ArrayEach( repos, function( repo, index ) {
			pages[ index ] = _get( _groupUrl( arguments.repo ) );
		}, true, variables.maxThreads );

		for ( var i=1; i<=ArrayLen( repos ); i++ ) {
			var page = pages[ i ];

			if ( page.status != 200 ) {
				SystemOutput( "Maven repository [#repos[ i ]#] could not be listed: #page.status# #page.error#", true );
				result.complete = false;
				continue;
			}

			for ( var href in REMatchNoCase( 'href="[^"]*#variables.suffix#/?"', page.content ) ) {
				var name = ListLast( ReReplace( href, '^href="|/?"$', "", "all" ), "/" );

				if ( Len( name ) > Len( variables.suffix ) ) {
					names[ name ] = true;
				}
			}
		}

		result.artifacts = StructKeyArray( names );
		ArraySort( result.artifacts, "textnocase" );

		return result;
	}

	/**
	 * The versions of an artifact from the maven-metadata.xml of every repository. The release repositories
	 * only hold release versions and the snapshot repositories snapshot versions, the mixed one both.
	 * Returns { versions={ version=[ repos ] }, complete=boolean }
	 */
	private struct function _listVersions( required string artifact ) {
		var result = { versions={}, complete=true };

		for ( var repo in _allRepos() ) {
			var kind = _repoKind( repo );
			var metaUrl  = _artifactUrl( repo, arguments.artifact ) & "maven-metadata.xml";
			var page = _get( metaUrl );

			if ( page.status == 404 ) {
				continue; // the repo doesn't have the artifact
			}

			if ( page.status != 200 ) {
				SystemOutput( "Maven metadata [#metaUrl#] could not be read: #page.status# #page.error#", true );
				result.complete = false;
				continue;
			}

			try {
				var nodes = XmlSearch( XmlParse( Trim( page.content ) ), "/metadata/versioning/versions/version" );
			} catch ( any e ) {
				SystemOutput( "Maven metadata [#metaUrl#] is not valid: #e.message#", true );
				result.complete = false;
				continue;
			}

			for ( var node in nodes ) {
				var version = Trim( node.xmlText );

				if ( !Len( version ) || ( kind == "releases" && isSnapshot( version ) ) || ( kind == "snapshots" && !isSnapshot( version ) ) ) {
					continue;
				}

				result.versions[ version ] = result.versions[ version ] ?: [];

				if ( !ArrayFind( result.versions[ version ], repo ) ) {
					ArrayAppend( result.versions[ version ], repo );
				}
			}
		}

		// the repos of a version in order of preference: the repos of its kind first, then the mixed ones
		for ( var version in StructKeyArray( result.versions ) ) {
			result.versions[ version ] = _sortRepos( result.versions[ version ], isSnapshot( version ) );
		}

		return result;
	}

	private array function _sortRepos( required array repos, required boolean snapshot ) {
		var order = _allRepos( arguments.snapshot );
		var sorted = [];

		for ( var repo in order ) {
			if ( ArrayFind( arguments.repos, repo ) ) {
				ArrayAppend( sorted, repo );
			}
		}

		return sorted;
	}

	/**
	 * Name of the extension file of a version in a repository. Release files are named by artifact and version,
	 * snapshot files are timestamped on most repositories, the name is in the maven-metadata.xml of the version.
	 * Empty when the metadata can't be read.
	 */
	private string function _fileName( required string artifact, required string version, required string repo ) {
		var plain = arguments.artifact & "-" & arguments.version & ".lex";

		if ( !isSnapshot( arguments.version ) ) {
			return plain;
		}

		var metaUrl = _versionUrl( arguments.repo, arguments.artifact, arguments.version ) & "maven-metadata.xml";

		var cached = variables._snapshotFiles[ metaUrl ] ?: "";

		if ( IsStruct( cached ) && DateDiff( "s", cached.time, Now() ) < variables._snapshotTtl ) {
			return cached.file;
		}

		var page = _get( metaUrl );

		if ( page.status == 404 ) {
			return plain; // a repository that has no metadata for the version
		}

		if ( page.status != 200 ) {
			SystemOutput( "Maven snapshot metadata [#metaUrl#] could not be read: #page.status# #page.error#", true );
			return "";
		}

		var fileName = "";

		try {
			// the extension itself, not a classifier like the -lite file
			for ( var node in XmlSearch( XmlParse( Trim( page.content ) ), "/metadata/versioning/snapshotVersions/snapshotVersion" ) ) {
				if ( ( node.extension.xmlText ?: "" ) == "lex" && !StructKeyExists( node, "classifier" ) ) {
					fileName = arguments.artifact & "-" & Trim( node.value.xmlText ) & ".lex";
					break;
				}
			}
		} catch ( any e ) {
			SystemOutput( "Maven snapshot metadata [#metaUrl#] is not valid: #e.message#", true );
			return "";
		}

		if ( !Len( fileName ) ) {
			// metadata without snapshotVersions (older repositories)
			fileName = plain;
		}

		variables._snapshotFiles[ metaUrl ] = { file=fileName, time=Now() };

		return fileName;
	}

	// all repos, the ones of the kind of version (releases or snapshots) first, the mixed ones last
	private array function _allRepos( boolean snapshot=false ) {
		var repos = [];
		var first = arguments.snapshot ? variables.snapshotRepos : variables.releaseRepos;
		var other = arguments.snapshot ? variables.releaseRepos  : variables.snapshotRepos;

		for ( var list in [ first, other, variables.mixedRepos ] ) {
			for ( var repo in list ) {
				if ( !ArrayFind( repos, repo ) ) {
					ArrayAppend( repos, repo );
				}
			}
		}

		return repos;
	}

	// "releases" and "snapshots" repos only hold versions of that kind, the others (or a repo that is both) hold both
	private string function _repoKind( required string repo ) {
		var isRelease  = ArrayFind( variables.releaseRepos , arguments.repo ) > 0;
		var isSnapshot = ArrayFind( variables.snapshotRepos, arguments.repo ) > 0;

		if ( isRelease && !isSnapshot && !ArrayFind( variables.mixedRepos, arguments.repo ) ) {
			return "releases";
		}

		if ( isSnapshot && !isRelease && !ArrayFind( variables.mixedRepos, arguments.repo ) ) {
			return "snapshots";
		}

		return "mixed";
	}

	private string function _groupUrl( required string repo ) {
		return arguments.repo & Replace( variables.group, ".", "/", "all" ) & "/";
	}

	private string function _artifactUrl( required string repo, required string artifact ) {
		return _groupUrl( arguments.repo ) & arguments.artifact & "/";
	}

	private string function _versionUrl( required string repo, required string artifact, required string version ) {
		return _artifactUrl( arguments.repo, arguments.artifact ) & arguments.version & "/";
	}

	private array function _normaliseRepos( required array repos ) {
		var result = [];

		for ( var repo in arguments.repos ) {
			repo = Trim( repo );

			if ( Len( repo ) ) {
				repo = Right( repo, 1 ) == "/" ? repo : repo & "/";

				if ( !ArrayFind( result, repo ) ) {
					ArrayAppend( result, repo );
				}
			}
		}

		return result;
	}

	/**
	 * A repository answers with a 5xx (or 429) now and then, especially when it is asked a lot in parallel, or
	 * the request fails (status 0), retry those a few times. Anything else is the answer of the repository.
	 */
	private struct function _get( required string address ) {
		var result = {};

		for ( var attempt=0; attempt<=variables.retries; attempt++ ) {
			_waitForRetry( attempt );
			result = variables.httpClient.get( arguments.address, variables.timeout );

			if ( !_isTemporaryFailure( result.status ) ) {
				break;
			}
		}

		return result;
	}

	private struct function _download( required string address, required string target ) {
		var result = {};

		for ( var attempt=0; attempt<=variables.retries; attempt++ ) {
			_waitForRetry( attempt );
			result = variables.httpClient.download( arguments.address, arguments.target, variables.downloadTimeout );

			if ( !_isTemporaryFailure( result.status ) ) {
				break;
			}
		}

		return result;
	}

	private function _waitForRetry( required numeric attempt ) {
		if ( arguments.attempt > 0 && variables.retryDelay > 0 ) {
			sleep( variables.retryDelay * arguments.attempt );
		}
	}

	private boolean function _isTemporaryFailure( required numeric status ) {
		return arguments.status == 0 || arguments.status == 429 || arguments.status >= 500;
	}

	/**
	 * The http requests are made by a client with .get( url, timeout ) and .download( url, file, timeout ), both
	 * return { status, error } (get also the content), a failed request has a status of 0 or a 5xx.
	 * Redirects are followed. Tests pass a client of their own.
	 */
	private struct function _defaultHttpClient() {
		var userAgent = "lucee-data-provider extension provider (LDEV-6789)";

		return {
			get = function( required string url, required numeric timeout ) {
				http url=arguments.url method="get" timeout=arguments.timeout redirect=true useragent=userAgent getAsBinary="no" result="local.res" {}
				return {
					  status  = Val( local.res.statusCode ?: 0 )
					, error   = local.res.errordetail ?: ""
					, content = IsSimpleValue( local.res.fileContent ?: "" ) ? local.res.fileContent : ""
				};
			},
			download = function( required string url, required string file, required numeric timeout ) {
				http url=arguments.url method="get" timeout=arguments.timeout redirect=true useragent=userAgent getAsBinary="yes" path=GetDirectoryFromPath( arguments.file ) file=GetFileFromPath( arguments.file ) result="local.res" {}
				return {
					  status = Val( local.res.statusCode ?: 0 )
					, error  = local.res.errordetail ?: ""
				};
			}
		};
	}

}
