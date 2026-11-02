component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		variables.base      = GetTempDirectory() & "ldev6789-repos-" & CreateUUID() & "/";
		variables.lexDir    = base & "lex/";
		variables.cdnUrl    = "https://ext.example.invalid/";
		variables.mavenCdn  = "https://cdn.example.invalid/org/lucee/";
		variables.releases  = "https://central.example.invalid/maven2/";
		variables.snapshots = "https://snapshots.example.invalid/repository/maven-snapshots/";
		variables.mixed     = "https://mixed.example.invalid/";
		variables.mailId    = "212BA548-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.ftpId     = "99999999-F15A-4EBD-8B1EEDF8DD8A844D";

		DirectoryCreate( lexDir, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.base ) ) {
			DirectoryDelete( variables.base, true );
		}
	}

	function run( testResults , testBox ) {
		describe( "LDEV-6789 extensions from the Maven repositories", function() {

			it( title="lists the versions of all repositories, once", body=function() {
				var world = _newWorld();
				var found = _newSource( world ).listExtensions();
				var names = _names( found.files );

				expect( found.complete ).toBeTrue();
				expect( names ).toHaveKey( "mail-extension-1.1.0.17.lex" );
				expect( names ).toHaveKey( "ftp-extension-1.0.0.8.lex" );
				expect( names ).toHaveKey( "mail-extension-1.1.0.18-RC.lex" );
				expect( names ).toHaveKey( "mail-extension-1.1.0.19-SNAPSHOT.lex" );
				// not an extension
				expect( _names( found.files ) ).notToHaveKey( "other-library-1.0.0.lex" );
				// in two repositories, but one version: the releases repository first
				expect( found.files.filter( function( f ) { return f.name == "mail-extension-1.1.0.17.lex"; } ) ).toHaveLength( 1 );
				expect( _file( found, "mail-extension-1.1.0.17.lex" ).repos ).toBe( [ releases, mixed ] );
			});

			it( title="only takes release versions from release repositories and snapshots from snapshot repositories", body=function() {
				var names = _names( _newSource( _newWorld() ).listExtensions().files );

				expect( names ).notToHaveKey( "mail-extension-1.1.0.98-SNAPSHOT.lex" ); // a snapshot in the releases repo
				expect( names ).notToHaveKey( "mail-extension-1.1.0.99.lex" );          // a release in the snapshots repo
			});

			it( title="finds the artifacts of a repository that can't be listed by the ones of the others", body=function() {
				var world = _newWorld();
				var found = _newSource( world ).listExtensions();

				// the snapshots repository serves no links, it still provides the snapshot
				expect( _file( found, "mail-extension-1.1.0.19-SNAPSHOT.lex" ).repos ).toBe( [ snapshots, mixed ] );
			});

			it( title="resolves the file of a snapshot from the maven metadata of the version, ignoring the lite file", body=function() {
				var source = _newSource( _newWorld() );

				expect( source.getFileUrl( "mail-extension", "1.1.0.19-SNAPSHOT", [ snapshots, mixed ] ) )
					.toBe( snapshots & "org/lucee/mail-extension/1.1.0.19-SNAPSHOT/mail-extension-1.1.0.19-20261022.163826-3.lex" );
			});

			it( title="uses the plain file name of a snapshot in a repository without metadata for the version", body=function() {
				var source = _newSource( _newWorld() );

				expect( source.getFileUrl( "mail-extension", "1.1.0.19-SNAPSHOT", [ mixed ] ) )
					.toBe( mixed & "org/lucee/mail-extension/1.1.0.19-SNAPSHOT/mail-extension-1.1.0.19-SNAPSHOT.lex" );
			});

			it( title="resolves a release file from the first repository that has it", body=function() {
				var source = _newSource( _newWorld() );

				expect( source.getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] ) )
					.toBe( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
			});

			it( title="is not complete when a repository or the metadata of an artifact can't be read", body=function() {
				var world = _newWorld();
				world.status[ releases & "org/lucee/ftp-extension/maven-metadata.xml" ] = 503;
				expect( _newSource( world ).listExtensions().complete ).toBeFalse();

				world = _newWorld();
				world.status[ mixed & "org/lucee/" ] = 500;
				expect( _newSource( world ).listExtensions().complete ).toBeFalse();

				world = _newWorld();
				world.pages[ releases & "org/lucee/ftp-extension/maven-metadata.xml" ] = "<metadata><versioning>";
				expect( _newSource( world ).listExtensions().complete ).toBeFalse();
			});

			it( title="retries a request that failed for a reason that is likely to be temporary, but not a 404", body=function() {
				var world = _newWorld();
				var metaUrl = releases & "org/lucee/ftp-extension/maven-metadata.xml";

				// a 500 and a 502, then the page
				world.statusSequence[ metaUrl ] = [ 500, 502 ];
				var found = _newSource( world ).listExtensions();

				expect( found.complete ).toBeTrue();
				expect( _names( found.files ) ).toHaveKey( "ftp-extension-1.0.0.8.lex" );
				expect( world.requests.filter( function( r ) { return r == metaUrl; } ) ).toHaveLength( 3 );

				// a missing file is no temporary failure
				var missing = _newWorld();
				var target  = base & CreateUUID() & ".lex";
				try {
					_newSource( missing ).download( "mail-extension", "1.1.0.17", [ releases & "missing/" ], target );
					fail( "must not be possible" );
				}
				catch ( MavenExtensionSource e ) {
					expect( e.message ).toInclude( "404" );
				}
				expect( missing.downloads ).toHaveLength( 1 );

				// it gives up after the retries
				world = _newWorld();
				world.status[ metaUrl ] = 503;
				expect( _newSource( world ).listExtensions().complete ).toBeFalse();
				expect( world.requests.filter( function( r ) { return r == metaUrl; } ) ).toHaveLength( 3 );
			});

			it( title="adds the extensions of the repositories with the id and version of their manifest", body=function() {
				var world  = _newWorld();
				var reader = _newReader( world );
				var found  = _versions( reader.list( type="all", all=true ) );

				expect( found ).toHaveKey( mailId & "|1.1.0.17" );
				expect( found ).toHaveKey( ftpId  & "|1.0.0.8" );
				expect( found ).toHaveKey( mailId & "|1.1.0.18-RC" );
				expect( found ).toHaveKey( mailId & "|1.1.0.19-SNAPSHOT" );
			});

			it( title="filters the qualifiers of the extensions of the repositories", body=function() {
				var reader = _newReader( _newWorld() );

				expect( _versions( reader.list( type="release", all=true ) ).keyList() ).toBe( mailId & "|1.1.0.17," & ftpId & "|1.0.0.8", "," ) ;
				expect( _versions( reader.list( type="snapshot", all=true ) ) ).toHaveKey( mailId & "|1.1.0.19-SNAPSHOT" );
				expect( _versions( reader.list( type="abc", all=true ) ) ).toHaveKey( mailId & "|1.1.0.18-RC" );
			});

			it( title="serves the downloads from the repository the file is in", body=function() {
				var reader = _newReader( _newWorld() );

				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", cdnUrl ) )
					.toBe( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( reader.getDownloadUrl( "ftp-extension-1.0.0.8.lex", cdnUrl ) )
					.toBe( releases & "org/lucee/ftp-extension/1.0.0.8/ftp-extension-1.0.0.8.lex" );
				expect( reader.getDownloadUrl( "mail-extension-1.1.0.19-SNAPSHOT.lex", cdnUrl ) )
					.toBe( snapshots & "org/lucee/mail-extension/1.1.0.19-SNAPSHOT/mail-extension-1.1.0.19-20261022.163826-3.lex" );
			});

			it( title="prefers the files of our bucket over the ones of the repositories", body=function() {
				var world = _newWorld();
				var maven = base & "bucket-" & CreateUUID() & "/maven/org/lucee/";
				_createLex( maven & "mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex", mailId, "1.1.0.17" );

				var reader = _newReader( world, maven );

				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( world.downloads ).notToInclude( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				// the others still come from the repositories
				expect( reader.getDownloadUrl( "ftp-extension-1.0.0.8.lex", cdnUrl ) )
					.toBe( releases & "org/lucee/ftp-extension/1.0.0.8/ftp-extension-1.0.0.8.lex" );
			});

			it( title="ignores a version of the repositories that is known already, without downloading it", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );
				// the same id and version as the one of the repositories, under another file name
				_createLex( flat & "mail-1.1.0.18-RC.lex", mailId, "1.1.0.18-RC" );

				var reader = _newReader( world, "", flat );
				var count  = 0;
				var all    = reader.list( type="all", all=true );

				loop query=all {
					if ( all.id == mailId && all.version == "1.1.0.18-RC" ) {
						count++;
					}
				}

				expect( count ).toBe( 1 );
				expect( world.downloads ).notToInclude( releases & "org/lucee/mail-extension/1.1.0.18-RC/mail-extension-1.1.0.18-RC.lex" );
				// LDEV-6795: Maven first, the flat file is served from the repository, which has that id and version
				expect( reader.getDownloadUrl( "mail-1.1.0.18-RC.lex", cdnUrl ) )
					.toBe( releases & "org/lucee/mail-extension/1.1.0.18-RC/mail-extension-1.1.0.18-RC.lex" );
				expect( reader.getDownloadUrl( "mail-extension-1.1.0.18-RC.lex", cdnUrl ) ).toBe( cdnUrl & "mail-extension-1.1.0.18-RC.lex" );
			});

			it( title="downloads a file only once, also after a restart", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );
				_createLex( flat & "mail-1.1.0.18-RC.lex", mailId, "1.1.0.18-RC" );

				_newReader( world, "", flat );
				var firstDownloads = world.downloads.len();

				expect( firstDownloads ).toBe( 3 ); // mail 1.1.0.19-SNAPSHOT and 1.1.0.17, ftp 1.0.0.8

				// the same instance and a new one that reads the extension meta of the first
				var reader = _newReader( world, "", flat );
				reader.loadMeta();

				expect( world.downloads ).toHaveLength( firstDownloads );
				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( ftpId & "|1.0.0.8" );
			});

			it( title="downloads a new version only", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );

				var reader = _newReader( world, "", flat );
				var before = world.downloads.len();

				_addRepoVersion( world, "ftp-extension", "1.0.0.9", ftpId, releases );
				reader.loadMeta();

				expect( world.downloads ).toHaveLength( before + 1 );
				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( ftpId & "|1.0.0.9" );
			});

			it( title="retries a file that could not be downloaded with the next refresh and doesn't lose the others", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );
				world.status[ releases & "org/lucee/ftp-extension/1.0.0.8/ftp-extension-1.0.0.8.lex" ] = 503;

				var reader = _newReader( world, "", flat );
				var found  = _versions( reader.list( type="all", all=true ) );

				expect( found ).toHaveKey( mailId & "|1.1.0.17" );
				expect( found ).notToHaveKey( ftpId & "|1.0.0.8" );

				StructDelete( world.status, releases & "org/lucee/ftp-extension/1.0.0.8/ftp-extension-1.0.0.8.lex" );
				reader.loadMeta();

				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( ftpId & "|1.0.0.8" );
			});

			it( title="keeps the extensions of the repositories when a repository can't be read, removes them when they are gone", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );

				// the extension meta only drops files that are gone when there are many files in the flat bucket
				for ( var i=1; i<=101; i++ ) {
					_createLex( flat & "old-" & i & ".lex", "00000000-0000-0000-0000000000" & NumberFormat( i, "000000" ), "1.0.0." & i );
				}

				_newReader( world, "", flat );

				var broken = _newWorld();
				broken.status[ releases & "org/lucee/" ] = 503;
				var reader = _newReader( broken, "", flat );

				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( ftpId & "|1.0.0.8" );

				// the repositories answer and the version is gone
				var gone = _newWorld();
				_removeRepoVersion( gone, "ftp-extension", "1.0.0.8", releases );
				reader = _newReader( gone, "", flat );
				var found = _versions( reader.list( type="all", all=true ) );

				expect( found ).notToHaveKey( ftpId & "|1.0.0.8" );
				expect( found ).toHaveKey( mailId & "|1.1.0.17" );
			});

			it( title="does not use repositories when none is configured", body=function() {
				var world = _newWorld();
				var flat  = base & "flat-" & CreateUUID() & "/";
				DirectoryCreate( flat, true );
				_createLex( flat & "mail-1.1.0.8-RC.lex", mailId, "1.1.0.8-RC" );

				var reader = new services.ExtensionMetadataReader( s3root=Left( flat, Len( flat ) - 1 ) );
				reader.loadMeta();

				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( mailId & "|1.1.0.8-RC" );
				expect( world.requests ).toHaveLength( 0 );
			});

			it( title="does not read the same snapshot metadata more than once in a short time", body=function() {
				var world  = _newWorld();
				var source = _newSource( world );

				source.getFileUrl( "mail-extension", "1.1.0.19-SNAPSHOT", [ snapshots ] );
				source.getFileUrl( "mail-extension", "1.1.0.19-SNAPSHOT", [ snapshots ] );

				var metadataUrl = snapshots & "org/lucee/mail-extension/1.1.0.19-SNAPSHOT/maven-metadata.xml";

				expect( world.requests.filter( function( r ) { return r == metadataUrl; } ) ).toHaveLength( 1 );
			});

		});
	}

// FAKE MAVEN REPOSITORIES
	/**
	 * pages: url > content, files: url > the lex file served there, status: url > http status to answer with,
	 * requests: the urls requested, downloads: the urls of the files downloaded
	 */
	private struct function _newWorld() {
		var world = {
			  pages     = {}
			, files     = {}
			, status    = {}
			, statusSequence = {}
			, requests  = ArrayNew( 1, true )
			, downloads = ArrayNew( 1, true )
		};
		var group = "org/lucee/";

		// the listings, the snapshots repo has no links at all
		world.pages[ releases  & group ] = _listing( [ "mail-extension", "ftp-extension", "other-library" ] );
		world.pages[ mixed     & group ] = _listing( [ "mail-extension", "ftp-extension" ] );
		world.pages[ snapshots & group ] = "<html><body><div id=""app""></div></body></html>";

		_addRepoVersion( world, "mail-extension", "1.1.0.17"     , mailId, releases );
		_addRepoVersion( world, "mail-extension", "1.1.0.17"     , mailId, mixed );
		_addRepoVersion( world, "mail-extension", "1.1.0.18-RC"  , mailId, releases );
		_addRepoVersion( world, "mail-extension", "1.1.0.18-RC"  , mailId, mixed );
		_addRepoVersion( world, "ftp-extension" , "1.0.0.8"      , ftpId , releases );

		// snapshots, the mixed repository serves a plain file, the snapshot repository a timestamped one
		_addRepoVersion( world, "mail-extension", "1.1.0.19-SNAPSHOT", mailId, mixed );
		_addRepoVersion( world, "mail-extension", "1.1.0.19-SNAPSHOT", mailId, snapshots, "1.1.0.19-20261022.163826-3" );

		// what a repository must not provide: a snapshot in the releases and a release in the snapshots repo
		_addToMetadata( world, releases , "mail-extension", "1.1.0.98-SNAPSHOT" );
		_addToMetadata( world, snapshots, "mail-extension", "1.1.0.99" );

		// not an extension
		world.pages[ releases & group & "other-library/maven-metadata.xml" ] = _metadata( "other-library", [ "1.0.0" ] );

		return world;
	}

	private function _addRepoVersion( world, artifact, version, id, repo, timestamped="" ) {
		var fileName = Len( arguments.timestamped ) ? arguments.artifact & "-" & arguments.timestamped & ".lex" : arguments.artifact & "-" & arguments.version & ".lex";
		var fileUrl  = arguments.repo & "org/lucee/" & arguments.artifact & "/" & arguments.version & "/" & fileName;
		var lexFile  = lexDir & CreateUUID() & ".lex";

		_createLex( lexFile, arguments.id, arguments.version );
		arguments.world.files[ fileUrl ] = lexFile;

		_addToMetadata( arguments.world, arguments.repo, arguments.artifact, arguments.version );

		if ( Len( arguments.timestamped ) ) {
			arguments.world.pages[ arguments.repo & "org/lucee/" & arguments.artifact & "/" & arguments.version & "/maven-metadata.xml" ] =
				"<?xml version=""1.0"" encoding=""UTF-8""?><metadata><groupId>org.lucee</groupId><artifactId>#arguments.artifact#</artifactId><version>#arguments.version#</version><versioning>"
				& "<snapshot><timestamp>20261022.163826</timestamp><buildNumber>3</buildNumber></snapshot><lastUpdated>20261022163826</lastUpdated><snapshotVersions>"
				& "<snapshotVersion><classifier>lite</classifier><extension>lex</extension><value>1.1.0.19-20261022.163826-2</value><updated>20261022163826</updated></snapshotVersion>"
				& "<snapshotVersion><extension>pom</extension><value>#arguments.timestamped#</value><updated>20261022163826</updated></snapshotVersion>"
				& "<snapshotVersion><extension>lex</extension><value>#arguments.timestamped#</value><updated>20261022163826</updated></snapshotVersion>"
				& "</snapshotVersions></versioning></metadata>";
		}
	}

	private function _removeRepoVersion( world, artifact, version, repo ) {
		var metaUrl = arguments.repo & "org/lucee/" & arguments.artifact & "/maven-metadata.xml";
		var versions = [];

		for ( var node in XmlSearch( XmlParse( arguments.world.pages[ metaUrl ] ), "/metadata/versioning/versions/version" ) ) {
			if ( node.xmlText != arguments.version ) {
				ArrayAppend( versions, node.xmlText );
			}
		}

		arguments.world.pages[ metaUrl ] = _metadata( arguments.artifact, versions );
	}

	private function _addToMetadata( world, repo, artifact, version ) {
		var metaUrl  = arguments.repo & "org/lucee/" & arguments.artifact & "/maven-metadata.xml";
		var versions = [];

		if ( StructKeyExists( arguments.world.pages, metaUrl ) ) {
			for ( var node in XmlSearch( XmlParse( arguments.world.pages[ metaUrl ] ), "/metadata/versioning/versions/version" ) ) {
				ArrayAppend( versions, node.xmlText );
			}
		}

		if ( !ArrayFind( versions, arguments.version ) ) {
			ArrayAppend( versions, arguments.version );
		}

		arguments.world.pages[ metaUrl ] = _metadata( arguments.artifact, versions );
	}

	private string function _metadata( artifact, versions ) {
		var xml = "<?xml version=""1.0"" encoding=""UTF-8""?><metadata><groupId>org.lucee</groupId><artifactId>#arguments.artifact#</artifactId><versioning><versions>";

		for ( var version in arguments.versions ) {
			xml &= "<version>#version#</version>";
		}

		return xml & "</versions></versioning></metadata>";
	}

	// the html listing of a repository: parent folder, the artifacts and a file
	private string function _listing( names ) {
		var html = "<html><body><a href=""../"">../</a>";

		for ( var name in arguments.names ) {
			html &= "<a href=""#name#/"" title=""#name#/"">#name#/</a>";
		}

		return html & "<a href=""maven-metadata.xml"">maven-metadata.xml</a></body></html>";
	}

	private any function _newSource( world ) {
		return new services.MavenExtensionSource(
			  releaseRepos  = [ releases ]
			, snapshotRepos = [ snapshots ]
			, mixedRepos    = [ mixed ]
			, retryDelay    = 0
			, httpClient    = _newClient( arguments.world )
		);
	}

	// the http client of the source, answers from the world
	private struct function _newClient( world ) {
		var world = arguments.world;

		return {
			get = function( required string url, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );

				if ( StructKeyExists( world.statusSequence, arguments.url ) && ArrayLen( world.statusSequence[ arguments.url ] ) ) {
					// the next of the answers to give, 0 to give the page
					var next = world.statusSequence[ arguments.url ][ 1 ];
					ArrayDeleteAt( world.statusSequence[ arguments.url ], 1 );

					if ( next > 0 ) {
						return { status=next, error="forced", content="" };
					}
				}
				if ( StructKeyExists( world.status, arguments.url ) ) {
					return { status=world.status[ arguments.url ], error="forced", content="" };
				}
				if ( StructKeyExists( world.pages, arguments.url ) ) {
					return { status=200, error="", content=world.pages[ arguments.url ] };
				}
				return { status=404, error="not found", content="" };
			},
			download = function( required string url, required string file, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );
				ArrayAppend( world.downloads, arguments.url );

				if ( StructKeyExists( world.status, arguments.url ) ) {
					return { status=world.status[ arguments.url ], error="forced" };
				}
				if ( StructKeyExists( world.files, arguments.url ) ) {
					FileCopy( world.files[ arguments.url ], arguments.file );
					return { status=200, error="" };
				}
				return { status=404, error="not found" };
			}
		};
	}

	private function _newReader( world, mavenRoot="", flat="" ) {
		if ( !Len( arguments.flat ) ) {
			arguments.flat = base & "flat-" & CreateUUID() & "/";
			DirectoryCreate( arguments.flat, true );
		}

		var reader = new services.ExtensionMetadataReader(
			  s3root       = Left( arguments.flat, Len( arguments.flat ) - 1 )
			, mavenRoot    = arguments.mavenRoot
			, mavenCdnUrl  = mavenCdn
			, mavenSource  = _newSource( arguments.world )
			, fetchThreads = 4
		);
		reader.loadMeta();
		return reader;
	}

	private struct function _names( files ) {
		var names = {};

		for ( var file in arguments.files ) {
			names[ file.name ] = true;
		}

		return names;
	}

	private struct function _file( found, name ) {
		for ( var file in arguments.found.files ) {
			if ( file.name == arguments.name ) {
				return file;
			}
		}

		throw( message="[#arguments.name#] not found" );
	}

	private struct function _versions( extensions ) {
		var found = [:];

		loop query=arguments.extensions {
			found[ arguments.extensions.id & "|" & arguments.extensions.version ] = true;
		}

		return found;
	}

	// an extension file is a zip with a manifest
	private function _createLex( path, id, version ) {
		var src = base & "src-" & CreateUUID() & "/";

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.id & Chr( 13 ) & Chr( 10 )
			& "name: LDEV-6789 test extension" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.version & Chr( 13 ) & Chr( 10 ) & Chr( 13 ) & Chr( 10 ) );

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
