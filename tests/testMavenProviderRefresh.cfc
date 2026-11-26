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

			it( "lists only versions the requested core can load in older", function() {
				var world = _newWorld();
				// the newest version needs a newer core, it is read at startup (latest), so its minimum core is known
				_addRepoVersion( world, "mail-extension", "1.2.0.0-SNAPSHOT", mailId, snapshots, "7.0.0.0" );
				// only in the metadata, their minimum core is not known: one newer, one older than the listed version
				_addToMetadata( world, mixed, "mail-extension", "1.1.0.18-RC" );
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.1" );
				world.pages[ snapshots & "org/lucee/" ] = _listing( [ "mail-extension" ] );
				var reader = _newReader( world );

				var old = _row( reader.list( type="all", coreVersion="5.4.8.2" ), mailId );
				expect( old.version ).toBe( "1.1.0.17" );
				expect( old.older ).notToInclude( "1.2.0.0-SNAPSHOT" );
				expect( old.older ).notToInclude( "1.1.0.18-RC" );
				expect( old.older ).toInclude( "1.0.0.1" );

				var current = _row( reader.list( type="all", coreVersion="7.1.0.0" ), mailId );
				expect( current.version ).toBe( "1.2.0.0-SNAPSHOT" );
				expect( current.older ).toInclude( "1.1.0.18-RC" );
				expect( current.older ).toInclude( "1.1.0.17" );
				expect( current.older ).toInclude( "1.0.0.1" );

				var noCore = _row( reader.list( type="all" ), mailId );
				expect( noCore.older ).toInclude( "1.1.0.18-RC" );
				expect( noCore.older ).toInclude( "1.0.0.1" );
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

		_downloadFallbackSpecs();

		describe( "Load: what a request and a cold start ask the repositories for", function() {
			it( "loads only the version that is asked for, without listing every artifact again", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				_addRepoVersion( world, "mail-extension", "1.0.0.1", mailId, mixed );
				ArrayClear( world.requests );
				ArrayClear( world.downloads );

				var ext = reader.getExtensionDetail( id=mailId, version="1.0.0.1" );

				expect( ext.version ).toBe( "1.0.0.1" );
				expect( world.downloads ).toBe( [ mixed & "org/lucee/mail-extension/1.0.0.1/mail-extension-1.0.0.1.lex" ] );
				expect( world.requests ).notToInclude( releases & "org/lucee/" ); // no group listing, no loadMeta
				expect( _metadataReads( world ).filter( function( r ) { return !r.contains( "mail-extension" ); } ) ).toHaveLength( 0 );
				expect( _row( reader.list( type="release" ), mailId ).version ).toBe( "1.1.0.17" );
			} );

			it( "remembers a version no repository has and does not look it up again", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				ArrayClear( world.requests );

				expect( reader.getExtensionDetail( id=mailId, version="9.9.9.9" ) ).toBeEmpty();
				var first = ArrayLen( world.requests );
				expect( first ).toBeGT( 0 );
				expect( reader.getExtensionDetail( id=mailId, version="9.9.9.9" ) ).toBeEmpty();
				expect( ArrayLen( world.requests ) ).toBe( first );
				expect( world.downloads ).toHaveLength( 0 );
			} );

			it( "does not download a version that is listed but has no file", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.2" );
				ArrayClear( world.downloads );

				expect( reader.getExtensionDetail( id=mailId, version="1.0.0.2" ) ).toBeEmpty();
				expect( world.downloads ).toHaveLength( 0 );
			} );

			it( "a version asked for does not wait for a running meta load, which then adds it", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				_addRepoVersion( world, "mail-extension", "1.0.0.1", mailId, mixed );
				var holder = "hold-ext-meta-" & CreateUUID();
				thread name=holder {
					lock type="exclusive" name="readExtMeta" timeout=5 {
						sleep( 4000 );
					}
				}
				sleep( 300 );

				var started = GetTickCount();
				var ext = reader.getExtensionDetail( id=mailId, version="1.0.0.1" );
				var took = GetTickCount() - started;
				thread action="join" name=holder;

				expect( ext.version ).toBe( "1.0.0.1" );
				expect( took ).toBeLT( 3500 );
				expect( reader.getDownloadUrl( ext.filename, "" ) ).toBe( mixed & "org/lucee/mail-extension/1.0.0.1/mail-extension-1.0.0.1.lex" );

				reader.loadMeta();
				expect( reader.getExtensionVersions()[ mailId ] ).toHaveKey( "1.0.0.1" );
			} );

			it( "does not read lucee-services metadata for a final Central lists", function() {
				var world = _newWorld();
				var found = _newSource( world ).findVersion( "mail-extension", "1.1.0.17" );

				expect( found.found ).toBeTrue();
				expect( found.repos[ 1 ] ).toBe( releases );
				expect( found.repos ).toInclude( mixed ); // the download fallback
				expect( world.requests ).toBe( [ releases & "org/lucee/mail-extension/maven-metadata.xml" ] );
			} );

			it( "shares maven-metadata.xml reads between instances through the cache folder, within the TTL", function() {
				var dir = base & "shared-" & CreateUUID() & "/";
				var first = _newWorld();
				_newSource( first, dir, 300 ).listExtensions();
				expect( _metadataReads( first ) ).notToBeEmpty();

				var second = _newWorld();
				_newSource( second, dir, 300 ).listExtensions();
				expect( _metadataReads( second ) ).toHaveLength( 0 );
			} );

			it( "uses the shared copy of a maven-metadata.xml when the repository can not be read after the TTL", function() {
				var dir = base & "stale-" & CreateUUID() & "/";
				var world = _newWorld();
				_addToMetadata( world, mixed, "mail-extension", "1.0.0.1" );
				_newSource( world, dir, 1 ).listExtensions();
				sleep( 1100 );

				var later = _newWorld();
				later.status[ mixed & "org/lucee/mail-extension/maven-metadata.xml" ] = 503;
				var found = _newSource( later, dir, 1 ).listExtensions();

				expect( found.versions[ "mail-extension" ] ).toHaveKey( "1.0.0.1" );
				expect( found.complete ).toBeFalse();
			} );

			it( "keeps the HEAD results for the next instance", function() {
				var dir = base & "head-" & CreateUUID() & "/";
				var first = _newWorld();
				var source = _newSource( first, dir, 300 );
				expect( source.getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] ) ).notToBe( "" );
				source.saveState();

				var second = _newWorld();
				expect( _newSource( second, dir, 300 ).getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] ) )
					.toBe( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( second.heads ).toHaveLength( 0 );
			} );

			it( "runs one loadMeta at a time, the calls that come in meanwhile get its result", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				ArrayClear( world.requests );
				reader.loadMeta();
				var once = ArrayLen( world.requests );
				ArrayClear( world.requests );
				world.delay = 20;

				var names = [];
				for ( var i=1; i<=3; i++ ) {
					var name = "single-flight-#i#-#CreateUUID()#";
					ArrayAppend( names, name );
					thread name=name r=reader {
						attributes.r.loadMeta();
					}
				}
				thread action="join" name=ArrayToList( names );
				world.delay = 0;

				expect( ArrayLen( world.requests ) ).toBeLT( once * 3 );
			} );
		} );
	}

	private function _downloadFallbackSpecs() {
		describe( "Downloads only redirect to a file that is there", function() {
			it( "falls back to lucee-services for a version the listing only had from Central (Ajax 1.0.0.5)", function() {
				var world = _newWorld();
				var centralUrl = releases & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex";
				var mixedUrl   = mixed    & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex";
				world.headStatus[ centralUrl ] = 404;
				world.files[ mixedUrl ] = "x";

				expect( _newSource( world ).getFileUrl( "ajax-extension", "1.0.0.5", [ releases ] ) ).toBe( mixedUrl );
				expect( world.heads ).toBe( [ centralUrl, mixedUrl ] );
			} );

			it( "never answers with a url nobody has, and does not look in the snapshot repository for a final", function() {
				var world = _newWorld();
				var centralUrl = releases & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex";

				expect( _newSource( world ).getFileUrl( "ajax-extension", "1.0.0.5", [ releases ] ) ).toBe( "" );
				expect( world.heads ).toBe( [ centralUrl, mixed & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex" ] );
			} );

			it( "a /full/ download of a listed version that Central does not have goes to lucee-services", function() {
				var world = _newWorld();
				var reader = _newReader( world );
				var centralUrl = releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex";
				world.headStatus[ centralUrl ] = 404;

				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", "" ) )
					.toBe( mixed & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
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

	private function _addRepoVersion( world, artifact, version, id, repo, string minCore="" ) {
		var fileName = arguments.artifact & "-" & arguments.version & ".lex";
		var fileUrl  = arguments.repo & "org/lucee/" & arguments.artifact & "/" & arguments.version & "/" & fileName;
		var lexFile  = lexDir & CreateUUID() & ".lex";

		_createLex( lexFile, arguments.id, arguments.version, arguments.minCore );
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

	private any function _newSource( world, string cacheDir="", numeric metadataTtl=0 ) {
		return new services.MavenExtensionSource(
			  releaseRepos  = [ releases ]
			, snapshotRepos = [ snapshots ]
			, mixedRepos    = [ mixed ]
			, retryDelay    = 0
			, httpClient    = _newClient( arguments.world )
			, cacheDir      = arguments.cacheDir
			, metadataTtl   = arguments.metadataTtl
		);
	}

	private array function _metadataReads( world ) {
		return arguments.world.requests.filter( function( r ) { return r.endsWith( "maven-metadata.xml" ); } );
	}

	private struct function _newClient( world ) {
		var world = arguments.world;

		return {
			get = function( required string url, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );
				if ( ( world.delay ?: 0 ) > 0 ) {
					sleep( world.delay );
				}
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

	private function _createLex( path, id, version, string minCore="" ) {
		var src = base & "src-" & CreateUUID() & "/";

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.id & Chr( 13 ) & Chr( 10 )
			& "name: LDEV fallback test extension" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.version & Chr( 13 ) & Chr( 10 )
			& ( Len( arguments.minCore ) ? "lucee-core-version: " & arguments.minCore & Chr( 13 ) & Chr( 10 ) : "" )
			& Chr( 13 ) & Chr( 10 ) );

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
