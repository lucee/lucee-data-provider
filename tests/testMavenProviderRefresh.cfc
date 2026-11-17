component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.base      = GetTempDirectory() & "ext-fallback-" & CreateUUID() & "/";
		variables.lexDir    = base & "lex/";
		variables.releases  = "https://central.example.invalid/maven2/";
		variables.snapshots = "https://snapshots.example.invalid/repository/maven-snapshots/";
		variables.mixed     = "https://mixed.example.invalid/";
		variables.mailId    = "212BA548-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.hsqlId    = "6DD4728A-AB0C-4F67-9DCE1A91A8ACD114";

		DirectoryCreate( lexDir, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.base ) ) {
			DirectoryDelete( variables.base, true );
		}
	}

	function run( testResults, testBox ) {
		describe( "Provider listing refresh", function() {
			it( "refreshes the source after the TTL instead of serialising the startup simple cache forever", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				var before = reader.list( type="release" );
				_addRepoVersion( world, "mail-extension", "1.1.0.18", mailId, mixed );
				reader.setMetaTtl( 0.001 );
				sleep( 10 );
				reader.refreshIfStale( wait=true );
				var after = reader.list( type="release" );
				expect( _row( before, mailId ).version ).toBe( "1.1.0.17" );
				expect( _row( after, mailId ).version ).toBe( "1.1.0.18" );
			} );

			it( "serves stale metadata while a background rebuild runs and then resets the simple cache", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				reader.list( type="release" );
				_addRepoVersion( world, "mail-extension", "1.1.0.19", mailId, mixed );
				reader.setMetaTtl( 0.001 );
				sleep( 10 );
				reader.refreshIfStale();
				var deadline = GetTickCount() + 10000;
				while ( !ArrayFind( QueryColumnData( reader.getExtensionMeta(), "version" ), "1.1.0.19" ) && GetTickCount() < deadline ) {
					sleep( 25 );
				}
				reader.setMetaTtl( 0 );
				expect( _row( reader.list( type="release" ), mailId ).version ).toBe( "1.1.0.19" );
			} );

			it( "builds abc and snapshot from the same source as all, with the newest version of each type", function() {
				var world = _newWorld();
				_addRepoVersion( world, "mail-extension", "1.1.0.18-RC", mailId, mixed );
				_addRepoVersion( world, "mail-extension", "1.1.0.19-SNAPSHOT", mailId, mixed );
				var reader = _newReader( world );

				expect( _row( reader.list( type="all" ), mailId ).version ).toBe( "1.1.0.19-SNAPSHOT" );
				expect( _row( reader.list( type="release" ), mailId ).version ).toBe( "1.1.0.17" );
				expect( _row( reader.list( type="abc" ), mailId ).version ).toBe( "1.1.0.18-RC" );
				expect( _row( reader.list( type="snapshot" ), mailId ).version ).toBe( "1.1.0.19-SNAPSHOT" );
			} );

			it( "does not cache a thrown producer as a fresh listing", function() {
				var cache = new services.ListingCache( cacheDir=base & "failed/", ttlSeconds=1 );
				cache.put( "release", { version="old" }, DateAdd( "s", -10, Now() ) );
				expect( cache.get( "release", function() { throw "offline"; } ).version ).toBe( "old" );
				var deadline = GetTickCount() + 5000;
				while ( cache.isRefreshing( "release" ) && GetTickCount() < deadline ) { sleep( 25 ); }
				expect( cache.isFresh( "release" ) ).toBeFalse();
				expect( cache.peek( "release" ).version ).toBe( "old" );
				cache.get( "release", function() { return { version="new" }; } );
				deadline = GetTickCount() + 5000;
				while ( cache.isRefreshing( "release" ) && GetTickCount() < deadline ) { sleep( 25 ); }
				expect( cache.peek( "release" ).version ).toBe( "new" );
			} );
		} );

		describe( "Older versions from Central and lucee-services", function() {
			it( "retries a lucee-services metadata read that failed in the parallel pass, so its versions are listed", function() {
				var world = _newWorld();
				var metaUrl = mixed & "org/lucee/mail-extension/maven-metadata.xml";
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.1" );
				_addToMetadata( world, mixed, "mail-extension", "1.1.0.18-RC" );
				world.failTimes[ metaUrl ] = 3; // the first attempt and its two retries fail
				var found = _newSource( world ).listExtensions( latestOnly=true );

				expect( found.complete ).toBeTrue();
				expect( found.versions[ "mail-extension" ] ).toHaveKey( "1.0.0.1" );
				expect( found.versions[ "mail-extension" ] ).toHaveKey( "1.1.0.18-RC" );
			} );

			it( "keeps the versions of the last good read when lucee-services can not be read now", function() {
				var world = _newWorld();
				var metaUrl = mixed & "org/lucee/mail-extension/maven-metadata.xml";
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.1" );
				var source = _newSource( world );
				source.listExtensions();
				world.status[ metaUrl ] = 503;
				var found = source.listExtensions();

				expect( found.complete ).toBeFalse();
				expect( found.versions[ "mail-extension" ] ).toHaveKey( "1.0.0.1" );
				expect( found.versions[ "mail-extension" ][ "1.0.0.1" ] ).toBe( [ mixed ] );
			} );

			it( "lists every Central and lucee-services version of an artifact in older for type=all", function() {
				var world = _newWorld();
				_addToMetadata( world, releases, "mail-extension", "1.0.0.9" );
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.1" );
				_addToMetadata( world, mixed, "mail-extension", "1.1.0.16-RC" );
				_addToMetadata( world, snapshots, "mail-extension", "1.1.0.18-SNAPSHOT" );
				var older = _row( _newReader( world ).list( type="all" ), mailId ).older;

				expect( older ).toInclude( "1.0.0.9" );
				expect( older ).toInclude( "1.0.0.1" );
				expect( older ).toInclude( "1.1.0.16-RC" );
			} );

			it( "keeps serving the older rows of the meta after a newer version was published", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				_addRepoVersion( world, "mail-extension", "1.1.0.18", mailId, mixed );
				reader.setMetaTtl( 0.001 );
				sleep( 10 );
				reader.refreshIfStale( wait=true );
				reader.setMetaTtl( 0 );
				var versions = reader.getExtensionVersions()[ mailId ];

				expect( versions ).toHaveKey( "1.1.0.18" );
				expect( versions ).toHaveKey( "1.1.0.17" );
				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", "" ) ).toBe( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
			} );
		} );
	}

	private struct function _row( required query rows, required string id ) {
		for ( var row in arguments.rows ) {
			if ( row.id == arguments.id ) { return row; }
		}
		return {};
	}

	private struct function _newWorld() {
		var world = {
			  pages      = {}
			, files      = {}
			, status     = {}
			, headStatus = {}
			, failTimes  = {}
			, requests   = ArrayNew( 1, true )
			, heads      = ArrayNew( 1, true )
			, downloads  = ArrayNew( 1, true )
		};
		var group = "org/lucee/";

		world.pages[ releases  & group ] = _listing( [ "mail-extension", "hsqldb-jdbc-extension" ] );
		world.pages[ mixed     & group ] = _listing( [ "mail-extension", "hsqldb-jdbc-extension" ] );
		world.pages[ snapshots & group ] = "<html></html>";

		_addRepoVersion( world, "mail-extension", "1.1.0.17", mailId, releases );
		_addRepoVersion( world, "mail-extension", "1.1.0.17", mailId, mixed );

		// HSQLDB finals that live only on lucee-services (Central metadata and files are absent)
		_addRepoVersion( world, "hsqldb-jdbc-extension", "2.7.2.jdk11", hsqlId, mixed );
		_addRepoVersion( world, "hsqldb-jdbc-extension", "2.7.2.jdk8",  hsqlId, mixed );
		_addToMetadata( world, mixed, "hsqldb-jdbc-extension", "2.4.0" );

		return world;
	}

	private function _addRepoVersion( world, artifact, version, id, repo ) {
		var fileName = arguments.artifact & "-" & arguments.version & ".lex";
		var fileUrl  = arguments.repo & "org/lucee/" & arguments.artifact & "/" & arguments.version & "/" & fileName;
		var lexFile  = lexDir & CreateUUID() & ".lex";

		_createLex( lexFile, arguments.id, arguments.version );
		arguments.world.files[ fileUrl ] = lexFile;
		_addToMetadata( arguments.world, arguments.repo, arguments.artifact, arguments.version );
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

	private string function _listing( names ) {
		var html = "<html><body><a href=""../"">../</a>";
		for ( var name in arguments.names ) {
			html &= "<a href=""#name#/"">#name#/</a>";
		}
		return html & "</body></html>";
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

	private struct function _newClient( world ) {
		var world = arguments.world;

		return {
			get = function( required string url, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );
				if ( ( world.failTimes[ arguments.url ] ?: 0 ) > 0 ) {
					world.failTimes[ arguments.url ]--;
					return { status=503, error="forced burst failure", content="" };
				}
				if ( StructKeyExists( world.status, arguments.url ) ) {
					return { status=world.status[ arguments.url ], error="forced", content="" };
				}
				if ( StructKeyExists( world.pages, arguments.url ) ) {
					return { status=200, error="", content=world.pages[ arguments.url ] };
				}
				return { status=404, error="not found", content="" };
			},
			head = function( required string url, required numeric timeout ) {
				ArrayAppend( world.heads, arguments.url );
				if ( StructKeyExists( world.headStatus, arguments.url ) ) {
					return { status=world.headStatus[ arguments.url ], error="forced" };
				}
				if ( StructKeyExists( world.files, arguments.url ) || StructKeyExists( world.pages, arguments.url ) ) {
					return { status=200, error="" };
				}
				return { status=404, error="not found" };
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

	private function _newReader( world ) {
		var flat = base & "flat-" & CreateUUID() & "/";
		DirectoryCreate( flat, true );

		var reader = new services.ExtensionMetadataReader(
			  s3root        = Left( flat, Len( flat ) - 1 )
			, mavenRoot     = ""
			, mavenCdnUrl   = ""
			, mavenSource   = _newSource( arguments.world )
			, fetchThreads  = 4
			, flatFallback  = false
			, mavenOnly     = true
		);
		reader.loadMeta();
		return reader;
	}

	private function _createLex( path, id, version ) {
		var src = base & "src-" & CreateUUID() & "/";

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.id & Chr( 13 ) & Chr( 10 )
			& "name: LDEV fallback test extension" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.version & Chr( 13 ) & Chr( 10 ) & Chr( 13 ) & Chr( 10 ) );

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
