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

		describe( "Extension downloads fall back from Maven Central to lucee-services", function() {

			it( title="redirects to Central when the file is there", body=function() {
				var world  = _newWorld();
				var source = _newSource( world );
				var fileUrl = source.getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] );

				expect( fileUrl ).toBe( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( world.heads ).toInclude( releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( world.heads ).notToInclude( mixed & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
			});

			it( title="falls back to lucee-services when Central does not have the file (HSQLDB 2.7.2.jdk8)", body=function() {
				var world = _newWorld();
				var centralUrl = releases & "org/lucee/hsqldb-jdbc-extension/2.7.2.jdk8/hsqldb-jdbc-extension-2.7.2.jdk8.lex";
				var mixedUrl   = mixed    & "org/lucee/hsqldb-jdbc-extension/2.7.2.jdk8/hsqldb-jdbc-extension-2.7.2.jdk8.lex";
				world.headStatus[ centralUrl ] = 404;

				var source = _newSource( world );
				var fileUrl = source.getFileUrl( "hsqldb-jdbc-extension", "2.7.2.jdk8", [ releases, mixed ] );

				expect( fileUrl ).toBe( mixedUrl );
				expect( world.heads ).toInclude( centralUrl );
				expect( world.heads ).toInclude( mixedUrl );
			});

			it( title="returns an empty string when neither Central nor lucee-services has the file", body=function() {
				var world = _newWorld();
				var centralUrl = releases & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex";
				var mixedUrl   = mixed    & "org/lucee/ajax-extension/1.0.0.5/ajax-extension-1.0.0.5.lex";
				world.headStatus[ centralUrl ] = 404;
				world.headStatus[ mixedUrl ]   = 404;

				var source = _newSource( world );

				expect( source.getFileUrl( "ajax-extension", "1.0.0.5", [ releases, mixed ] ) ).toBe( "" );
			});

			it( title="caches a HEAD miss briefly and a HEAD hit, so a second resolve does not ask again", body=function() {
				var world = _newWorld();
				var source = _newSource( world );
				var fileUrl = releases & "org/lucee/mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex";

				expect( source.getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] ) ).toBe( fileUrl );
				expect( source.getFileUrl( "mail-extension", "1.1.0.17", [ releases, mixed ] ) ).toBe( fileUrl );
				expect( world.heads.filter( function( r ) { return r == fileUrl; } ) ).toHaveLength( 1 );
			});

			it( title="merges versions from Central and lucee-services metadata, including a version only on lucee-services", body=function() {
				var world  = _newWorld();
				var found  = _newSource( world ).listExtensions();

				expect( found.versions ).toHaveKey( "hsqldb-jdbc-extension" );
				expect( found.versions[ "hsqldb-jdbc-extension" ] ).toHaveKey( "2.7.2.jdk8" );
				expect( found.versions[ "hsqldb-jdbc-extension" ] ).toHaveKey( "2.7.2.jdk11" );
				expect( found.versions[ "hsqldb-jdbc-extension" ] ).toHaveKey( "2.4.0" );
				expect( found.versions[ "hsqldb-jdbc-extension" ][ "2.7.2.jdk8" ] ).toBe( [ mixed ] );
				expect( found.versions[ "hsqldb-jdbc-extension" ][ "2.7.2.jdk11" ] ).toBe( [ mixed ] );
				expect( found.versions[ "mail-extension" ][ "1.1.0.17" ] ).toBe( [ releases, mixed ] );
			});

			it( title="lists older Maven versions from merged metadata without downloading every historical file", body=function() {
				var world   = _newWorld();
				var reader  = _newReader( world );
				var listed  = reader.list( type="release" );
				var current = "";
				var older   = [];

				loop query=listed {
					if ( listed.id == hsqlId ) {
						current = listed.version;
						older   = listed.older;
						break;
					}
				}

				expect( ArrayFind( [ "2.7.2.jdk11", "2.7.2.jdk8" ], current ) ).toBeGT( 0 );
				expect( older ).toBeArray();
				if ( current != "2.7.2.jdk8" ) {
					expect( older ).toInclude( "2.7.2.jdk8" );
				}
				if ( current != "2.7.2.jdk11" ) {
					expect( older ).toInclude( "2.7.2.jdk11" );
				}
				expect( older ).toInclude( "2.4.0" );
				expect( world.downloads ).notToInclude( mixed & "org/lucee/hsqldb-jdbc-extension/2.4.0/hsqldb-jdbc-extension-2.4.0.lex" );

				expect( reader.getDownloadUrl( "hsqldb-jdbc-extension-" & current & ".lex", "https://cdn.example.invalid/" ) )
					.toBe( mixed & "org/lucee/hsqldb-jdbc-extension/" & current & "/hsqldb-jdbc-extension-" & current & ".lex" );
			});

		});
	}

	private struct function _newWorld() {
		var world = {
			  pages      = {}
			, files      = {}
			, status     = {}
			, headStatus = {}
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
