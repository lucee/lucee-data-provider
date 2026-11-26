/**
 * LDEV-6789: discovers extensions published to Maven repositories, the same repositories Lucee core uses
 * (releases, snapshots and the "mixed" Lucee repository).
 *
 * - the artifacts (artifactId ending in -extension) are discovered from the group-level
 *   maven-metadata.xml of the mixed Lucee repository (org.lucee and io.forgebox), or from
 *   Lucee 8's LuceeExtension(groupId) which already reads that XML first. HTML directory
 *   listings are only a fallback.
 * - the versions of an artifact come from LuceeExtension(groupId, artifactId) or the
 *   artifact-level maven-metadata.xml of the repositories.
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
	// a folder shared by the instances (Cloud Run: /download/provider/maven/), where the maven-metadata.xml reads and
	// the HEAD results are kept, empty: in memory only
	property name="cacheDir"       type="string"  default="";
	// seconds a maven-metadata.xml read (or the HTML listing of a group) is used before it is read again, 0: always read
	property name="metadataTtl"    type="numeric" default=0;

	function init(
		  array   releaseRepos    = []
		, array   snapshotRepos   = []
		, array   mixedRepos      = []
		, string  group           = "org.lucee"
		, array   groups
		, numeric timeout         = 20
		, numeric downloadTimeout = 120
		, numeric maxThreads      = 10
		, numeric retries         = 2
		, numeric retryDelay      = 500
		, any     httpClient
		, any     catalog
		, string  cacheDir        = ""
		, numeric metadataTtl     = 0
	) {
		variables.releaseRepos    = _normaliseRepos( arguments.releaseRepos );
		variables.snapshotRepos   = _normaliseRepos( arguments.snapshotRepos );
		variables.mixedRepos      = _normaliseRepos( arguments.mixedRepos );
		variables.group           = arguments.group;
		variables.groups          = arguments.groups ?: [ arguments.group ];
		if ( !ArrayFind( variables.groups, arguments.group ) ) {
			ArrayPrepend( variables.groups, arguments.group );
		}
		variables.timeout         = arguments.timeout;
		variables.downloadTimeout = arguments.downloadTimeout;
		variables.maxThreads      = arguments.maxThreads;
		variables.retries         = arguments.retries;
		variables.retryDelay      = arguments.retryDelay;
		variables.httpClient      = arguments.httpClient ?: _defaultHttpClient();
		variables.catalog         = arguments.catalog ?: "";
		variables._artifactGroups = StructNew( "sync" ); // artifactId > groupId
		variables._artifactPreferred = StructNew( "sync" ); // artifactId > { latest, release }
		variables._snapshotFiles  = StructNew( "sync" ); // version metadata url > { file, time }, a snapshot is replaced by a newer one at any time
		variables._snapshotTtl    = 300; // seconds
		variables._existing       = StructNew( "sync" ); // file url > { exists, time }
		variables._existsTtl      = 86400; // seconds, a file that is there stays there
		variables._missingTtl     = 300;   // seconds, a missing file is only cached briefly
		variables._lastVersions   = StructNew( "sync" ); // artifact metadata url > versions of the last good read of it
		variables.metadataTtl     = Max( 0, Val( arguments.metadataTtl ) );
		variables.cacheDir        = Trim( arguments.cacheDir );
		if ( Len( variables.cacheDir ) && Right( variables.cacheDir, 1 ) != "/" ) {
			variables.cacheDir &= "/";
		}
		variables._pages          = StructNew( "sync" ); // url > { status, content, time } of the metadata reads
		variables._existingSaved  = 0;                   // GetTickCount() of the last write of the HEAD results
		variables._existingDirty  = false;
		_loadExisting();

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
	public struct function listExtensions( boolean latestOnly=false ) {
		var result = { files=[], complete=true, versions={} };

		if ( !hasRepos() && !IsObject( variables.catalog ?: "" ) ) {
			return result;
		}

		var listing = _listArtifacts();
		result.complete = listing.complete;

		var found = StructNew( "sync" ); // artifact index > versions, the artifacts are read in parallel

		ArrayEach( listing.artifacts, function( artifact, index ) {
			found[ index ] = _listVersions( arguments.artifact );
		}, true, variables.maxThreads );

		// an artifact a repository could not be read for (mostly a timeout or a 429/5xx in the parallel burst) is
		// tried once more, one at a time, before the last good copy of that repository's metadata is all there is
		for ( var i=1; i<=ArrayLen( listing.artifacts ); i++ ) {
			if ( !found[ i ].complete ) {
				found[ i ] = _listVersions( listing.artifacts[ i ] );
			}
		}

		for ( var i=1; i<=ArrayLen( listing.artifacts ); i++ ) {
			var artifactResult = found[ i ];
			var artifact       = listing.artifacts[ i ];
			var group          = _groupOf( artifact );

			if ( !artifactResult.complete ) {
				result.complete = false;
			}

			result.versions[ artifact ] = artifactResult.versions;

			var versions = StructKeyArray( artifactResult.versions );
			if ( arguments.latestOnly ) {
				versions = _latestVersions( artifact, versions, artifactResult.preferred ?: [] );
			}

			for ( var version in versions ) {
				if ( !StructKeyExists( artifactResult.versions, version ) ) {
					continue;
				}
				ArrayAppend( result.files, {
					  name     = artifact & "-" & version & ".lex"
					, artifact = artifact
					, version  = version
					, group    = group
					, repos    = artifactResult.versions[ version ]
				} );
			}
		}

		return result;
	}

	/**
	 * The url of the extension file of a version, in the first of the repos that actually has the file
	 * (HEAD, cached: long for a hit, briefly for a miss). Release repos (Maven Central) are tried first
	 * unless mixedFirst is set, then the other repos of the given list. A version that the listing only
	 * knows from one repository (because another one could not be read at the time) is still looked for in
	 * the other configured repositories that can hold it (lucee-services last), so the answer is never a
	 * redirect to a file that is not there: an empty string when none of them has it.
	 */
	public string function getFileUrl( required string artifact, required string version, required array repos, boolean mixedFirst=false ) {
		var tried = {};

		for ( var repo in _withFallbackRepos( arguments.mixedFirst ? _mixedFirst( arguments.repos ) : arguments.repos, arguments.version ) ) {
			var fileName = _fileName( arguments.artifact, arguments.version, repo );

			if ( !Len( fileName ) ) {
				continue;
			}

			var fileUrl = _versionUrl( repo, arguments.artifact, arguments.version ) & fileName;

			if ( StructKeyExists( tried, fileUrl ) ) {
				continue;
			}
			tried[ fileUrl ] = true;

			if ( _fileExists( fileUrl ) ) {
				return fileUrl;
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

		for ( var repo in _withFallbackRepos( arguments.repos, arguments.version ) ) {
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

	// the given repos, then the other configured ones that can hold the version (no snapshot repo for a final, no
	// release repo for a snapshot), the mixed ones (lucee-services) last
	private array function _withFallbackRepos( required array repos, required string version ) {
		var result   = Duplicate( arguments.repos );
		var snapshot = isSnapshot( arguments.version );

		for ( var repo in _allRepos( snapshot ) ) {
			var kind = _repoKind( repo );

			if ( ArrayFind( result, repo ) || ( snapshot && kind == "releases" ) || ( !snapshot && kind == "snapshots" ) ) {
				continue;
			}
			ArrayAppend( result, repo );
		}

		return result;
	}

	// the repos, the mixed ones (the Maven bridge) first
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
	 * The artifacts whose artifactId ends in -extension, from the group-level
	 * maven-metadata.xml (org.lucee and io.forgebox) or LuceeExtension(groupId).
	 * A group that can't be read makes the result incomplete.
	 */
	private struct function _listArtifacts() {
		var result = { artifacts=[], complete=true };
		var names  = {};

		// mixed-repo group XML (latest/release hints). This is not the full
		// catalog: Maven Central has extensions (S3, Hibernate, Administrator,
		// MCP, debugger, ...) that are absent from maven.lucee-services.com's
		// group metadata, so we always also list every configured repository.
		if ( IsObject( variables.catalog ?: "" ) ) {
			try {
				var rows = variables.catalog.listCatalog();
				for ( var row in rows ) {
					var name = row.artifact;
					if ( !StructKeyExists( names, name ) ) {
						names[ name ] = true;
						ArrayAppend( result.artifacts, name );
						variables._artifactGroups[ name ] = row.group;
						variables._artifactPreferred[ name ] = {
							  latest  = row.latest  ?: ""
							, release = row.release ?: ""
						};
					}
				}
			} catch ( any e ) {
				SystemOutput( "Extension catalog could not be read: #e.message#", true );
				result.complete = false;
			}
		}

		for ( var groupId in variables.groups ) {
			var listed = _listGroupArtifacts( groupId );
			if ( !listed.complete ) {
				result.complete = false;
			}
			for ( var name in listed.artifacts ) {
				if ( !StructKeyExists( names, name ) ) {
					names[ name ] = true;
					ArrayAppend( result.artifacts, name );
					variables._artifactGroups[ name ] = groupId;
				}
			}
		}

		return result;
	}

	private struct function _listGroupArtifacts( required string groupId ) {
		var result = { artifacts=[], complete=true };
		var repos  = _allRepos();
		var pages  = StructNew( "sync" );

		ArrayEach( repos, function( repo, index ) {
			pages[ index ] = _getMetadata( _groupUrl( arguments.repo, groupId ) );
		}, true, variables.maxThreads );

		var names = {};
		for ( var i=1; i<=ArrayLen( repos ); i++ ) {
			var page = pages[ i ];

			if ( page.status != 200 ) {
				if ( page.status != 404 ) {
					SystemOutput( "Maven repository [#repos[ i ]#] could not be listed for [#arguments.groupId#]: #page.status# #page.error#", true );
					result.complete = false;
				}
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
		return result;
	}

	private string function _groupOf( required string artifact ) {
		return variables._artifactGroups[ arguments.artifact ] ?: variables.group;
	}

	/**
	 * Versions to load at startup: the newest of any type (so type=all has the overall latest) and the newest of
	 * every release type: final (type=release), alpha/beta/RC (type=abc) and snapshot (type=snapshot). type=abc and
	 * type=snapshot are filtered from the same meta as type=all, so without their newest version an extension
	 * whose overall latest is of another type would be missing from them.
	 * Group XML latest/release are often stale or themselves a pre-release;
	 * the merged version list of every repository is the source of truth.
	 */
	private array function _latestVersions( required string artifact, required array versions, required array preferred ) {
		var picked = [];
		var sorted = Duplicate( arguments.versions );
		var types  = {};

		ArraySort( sorted, function( a, b ) {
			return Compare( services.VersionUtils::sortableVersionString( b ), services.VersionUtils::sortableVersionString( a ) );
		} );

		if ( ArrayLen( sorted ) ) {
			ArrayAppend( picked, sorted[ 1 ] );
		}

		for ( var version in sorted ) {
			var type = _releaseTypeOf( version );

			if ( StructKeyExists( types, type ) ) {
				continue;
			}
			types[ type ] = true;

			if ( !ArrayFind( picked, version ) ) {
				ArrayAppend( picked, version );
			}
		}

		return picked;
	}

	// "release", "abc" or "snapshot", the same types as the type= of the listings
	private string function _releaseTypeOf( required string version ) {
		if ( FindNoCase( "-SNAPSHOT", arguments.version ) ) {
			return "snapshot";
		}
		if ( FindNoCase( "-ALPHA", arguments.version ) || FindNoCase( "-BETA", arguments.version ) || FindNoCase( "-RC", arguments.version ) ) {
			return "abc";
		}

		return "release";
	}

	private boolean function _isFinalVersion( required string version ) {
		return FindNoCase( "-ALPHA",    arguments.version ) == 0
			&& FindNoCase( "-BETA",     arguments.version ) == 0
			&& FindNoCase( "-RC",       arguments.version ) == 0
			&& FindNoCase( "-SNAPSHOT", arguments.version ) == 0;
	}

	/**
	 * The repos of one version of an artifact, for a version asked for explicitly (/full/{id}?version=):
	 * { found, repos }. A final that Maven Central's metadata lists is taken from there, lucee-services' metadata
	 * is not read for it (it stays the download fallback, see getFileUrl). Anything else reads the metadata of
	 * every repository, see listArtifactVersions(). Nothing else of the artifact is loaded.
	 */
	public struct function findVersion( required string artifact, required string version ) {
		if ( _releaseTypeOf( arguments.version ) == "release" ) {
			for ( var repo in variables.releaseRepos ) {
				var page = _getMetadata( _artifactUrl( repo, arguments.artifact ) & "maven-metadata.xml" );

				if ( page.status == 200 && _metadataHasVersion( page.content, arguments.version ) ) {
					var repos = [ repo ];
					for ( var other in _allRepos() ) {
						if ( !ArrayFind( repos, other ) && _repoKind( other ) != "snapshots" ) {
							ArrayAppend( repos, other );
						}
					}
					return { found=true, repos=repos };
				}
			}
		}

		var listed = _listVersions( arguments.artifact );

		if ( StructKeyExists( listed.versions, arguments.version ) ) {
			return { found=true, repos=listed.versions[ arguments.version ] };
		}

		return { found=false, repos=[] };
	}

	/**
	 * Writes the HEAD results (the files that are there) to the shared cache folder when they changed. Called after
	 * a meta load (in the background), never on a request: on a shared Cloud Storage mount every file access is a
	 * billed operation.
	 */
	public void function saveState() {
		if ( !Len( variables.cacheDir ) || !variables._existingDirty ) {
			return;
		}

		var data = {};
		var now  = Now();

		for ( var fileUrl in variables._existing ) {
			var entry = variables._existing[ fileUrl ] ?: "";

			// a missing file is only remembered briefly, that is kept in memory only
			if ( IsStruct( entry ) && entry.exists && DateDiff( "s", entry.time, now ) < variables._existsTtl ) {
				data[ fileUrl ] = { exists=entry.exists, time=DateTimeFormat( entry.time, "iso" ) };
			}
		}

		try {
			services.CacheDir::writeAtomic( variables.cacheDir & "maven-head.json", SerializeJson( data ) );
			variables._existingDirty = false;
			variables._existingSaved = GetTickCount();
		} catch ( any e ) {
			SystemOutput( "Maven HEAD results could not be written: #e.message#", true );
		}
	}

	/**
	 * Versions of one artifact, from the shared catalog (LuceeExtension) when
	 * available, otherwise from each repository's maven-metadata.xml.
	 */
	public struct function listArtifactVersions( required string artifact ) {
		return _listVersions( arguments.artifact );
	}

	private struct function _listVersions( required string artifact ) {
		var result = { versions={}, complete=true };

		// Catalog (LuceeExtension / mixed-repo cache) is a useful first fill,
		// but Maven Central often has newer stables than maven.lucee-services.com,
		// and some artifacts only exist on Central. Always merge every repo.
		if ( IsObject( variables.catalog ?: "" ) ) {
			try {
				var vers = variables.catalog.getExtensionVersions( _groupOf( arguments.artifact ), arguments.artifact );
				var repos = ArrayLen( variables.mixedRepos ) ? variables.mixedRepos : _allRepos();
				for ( var version in vers ) {
					// a copy: arrays are references in Lucee, the repos of other versions are appended to it below
					result.versions[ version ] = Duplicate( repos );
				}
			} catch ( any e ) {
				SystemOutput( "Extension versions for [#arguments.artifact#] from the catalog could not be read: #e.message#", true );
			}
		}

		for ( var repo in _allRepos() ) {
			var kind = _repoKind( repo );
			var metaUrl  = _artifactUrl( repo, arguments.artifact ) & "maven-metadata.xml";
			var page = _getMetadata( metaUrl );
			var repoVersions = [];

			if ( page.status == 404 ) {
				StructDelete( variables._lastVersions, metaUrl );
				continue; // the repo doesn't have the artifact
			}

			if ( page.status == 200 && ( page.stale ?: false ) ) {
				// the repository could not be read now, this is the shared copy of an earlier read
				result.complete = false;
			}

			if ( page.status == 200 ) {
				try {
					for ( var node in XmlSearch( XmlParse( Trim( page.content ) ), "/metadata/versioning/versions/version" ) ) {
						ArrayAppend( repoVersions, Trim( node.xmlText ) );
					}
					variables._lastVersions[ metaUrl ] = repoVersions;
				} catch ( any e ) {
					SystemOutput( "Maven metadata [#metaUrl#] is not valid: #e.message#", true );
					page = { status=0, error="invalid xml: " & e.message };
				}
			}

			if ( page.status != 200 ) {
				// LDEV-6789: a repository that could not be read used to be left out, so every version only it has
				// (most older lucee-services versions and its pre-releases) was missing from the listing until the
				// next restart. Its last good copy is used instead, and the listing is marked as incomplete.
				result.complete = false;
				if ( StructKeyExists( variables._lastVersions, metaUrl ) ) {
					repoVersions = variables._lastVersions[ metaUrl ];
					SystemOutput( "Maven metadata [#metaUrl#] could not be read (#page.status# #page.error#), using the last good copy of it", true );
				} else {
					SystemOutput( "Maven metadata [#metaUrl#] could not be read: #page.status# #page.error#", true );
					continue;
				}
			}

			for ( var version in repoVersions ) {

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

	private boolean function _metadataHasVersion( required string xml, required string version ) {
		try {
			for ( var node in XmlSearch( XmlParse( Trim( arguments.xml ) ), "/metadata/versioning/versions/version" ) ) {
				if ( Trim( node.xmlText ) == arguments.version ) {
					return true;
				}
			}
		} catch ( any e ) {}

		return false;
	}

	/**
	 * A maven-metadata.xml (or group listing) read, shared for metadataTtl seconds: in memory, and with a cacheDir
	 * in a file all the instances read, so they don't each ask every repository for every artifact. Only a 200 or a
	 * 404 is kept. When the repository can not be read, the last 200 is returned (also after the TTL), with stale=true.
	 */
	private struct function _getMetadata( required string address ) {
		var ttlMs = variables.metadataTtl * 1000;
		var nowMs = Now().getTime();
		var entry = variables._pages[ arguments.address ] ?: "";

		if ( Len( variables.cacheDir ) && ( !IsStruct( entry ) || ( nowMs - entry.time ) >= ttlMs ) ) {
			var shared = _readPage( arguments.address );
			if ( IsStruct( shared ) && ( !IsStruct( entry ) || shared.time > entry.time ) ) {
				entry = shared;
			}
		}

		if ( IsStruct( entry ) && ttlMs > 0 && ( nowMs - entry.time ) < ttlMs ) {
			variables._pages[ arguments.address ] = entry;
			return { status=entry.status, content=entry.content, error="" };
		}

		var page = _get( arguments.address );

		if ( page.status == 200 || page.status == 404 ) {
			if ( ttlMs > 0 || Len( variables.cacheDir ) ) {
				var fresh = { status=page.status, content=( page.status == 200 ? page.content : "" ), time=nowMs };
				variables._pages[ arguments.address ] = fresh;
				_writePage( arguments.address, fresh );
			}
			return page;
		}

		if ( IsStruct( entry ) && entry.status == 200 ) {
			SystemOutput( "Maven metadata [#arguments.address#] could not be read (#page.status# #page.error#), the copy of #DateTimeFormat( DateAdd( 'l', entry.time - nowMs, Now() ), 'yyyy-mm-dd HH:nn:ss' )# is used", true );
			return { status=200, content=entry.content, error="", stale=true };
		}

		return page;
	}

	private string function _pagePath( required string address ) {
		return variables.cacheDir & "metadata/" & LCase( Hash( arguments.address, "MD5" ) ) & ".json";
	}

	private any function _readPage( required string address ) {
		var path = _pagePath( arguments.address );

		try {
			if ( FileExists( path ) ) {
				var entry = DeserializeJson( FileRead( path ) );
				if ( IsStruct( entry ) && ( entry.url ?: "" ) == arguments.address && IsNumeric( entry.time ?: "" ) ) {
					return { status=Val( entry.status ), content=entry.content ?: "", time=entry.time };
				}
			}
		} catch ( any e ) {
			SystemOutput( "Maven metadata cache [#path#] could not be read: #e.message#", true );
		}

		return "";
	}

	private void function _writePage( required string address, required struct entry ) {
		if ( !Len( variables.cacheDir ) ) {
			return;
		}

		try {
			services.CacheDir::writeAtomic( _pagePath( arguments.address ), SerializeJson( {
				  url     = arguments.address
				, status  = arguments.entry.status
				, content = arguments.entry.content
				, time    = arguments.entry.time
			} ) );
		} catch ( any e ) {
			SystemOutput( "Maven metadata cache for [#arguments.address#] could not be written: #e.message#", true );
		}
	}

	// the HEAD results of an earlier instance, so a cold start does not HEAD every file again
	private void function _loadExisting() {
		if ( !Len( variables.cacheDir ) || !FileExists( variables.cacheDir & "maven-head.json" ) ) {
			return;
		}

		try {
			var data = DeserializeJson( FileRead( variables.cacheDir & "maven-head.json" ) );

			for ( var fileUrl in data ) {
				var entry = data[ fileUrl ];
				if ( IsStruct( entry ) && IsBoolean( entry.exists ?: "" ) && IsDate( entry.time ?: "" ) ) {
					variables._existing[ fileUrl ] = { exists=entry.exists, time=ParseDateTime( entry.time ) };
				}
			}
		} catch ( any e ) {
			SystemOutput( "Maven HEAD results could not be read: #e.message#", true );
		}
	}

	// written with the next saveState(), not on the request
	private void function _existingChanged() {
		variables._existingDirty = true;
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

		var page = _getMetadata( metaUrl );

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

	private string function _groupUrl( required string repo, string group="" ) {
		var g = Len( arguments.group ) ? arguments.group : variables.group;
		return arguments.repo & Replace( g, ".", "/", "all" ) & "/";
	}

	private string function _artifactUrl( required string repo, required string artifact ) {
		return _groupUrl( arguments.repo, _groupOf( arguments.artifact ) ) & arguments.artifact & "/";
	}

	private string function _versionUrl( required string repo, required string artifact, required string version ) {
		return _artifactUrl( arguments.repo, arguments.artifact ) & arguments.version & "/";
	}

	/**
	 * Does the repository have the file. A redirect (the Maven bridge points to where the file is) counts as
	 * the file, a 404 as no file. Anything else (the repository can't be reached or is failing) can't tell,
	 * that is logged and counts as no file, but it is not remembered.
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
			_existingChanged();
			return true;
		}

		if ( result.status == 404 ) {
			variables._existing[ arguments.fileUrl ] = { exists=false, time=Now() }; // memory only, see saveState
			return false;
		}

		SystemOutput( "Maven extension file [#arguments.fileUrl#] could not be checked: #result.status# #result.error#", true );

		return false;
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
	 * The http requests are made by a client with .get( url, timeout ), .head( url, timeout ) and .download( url, file, timeout ),
	 * all return { status, error } (get also the content), a failed request has a status of 0 or a 5xx.
	 * Redirects are followed, except by head(). Tests pass a client of their own.
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
			// LDEV-6796: does the file exist, redirects are not followed, a redirect is the answer of a repository that points to the file
			head = function( required string url, required numeric timeout ) {
				http url=arguments.url method="head" timeout=arguments.timeout redirect=false useragent=userAgent result="local.res" {}
				return {
					  status = Val( local.res.statusCode ?: 0 )
					, error  = local.res.errordetail ?: ""
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
