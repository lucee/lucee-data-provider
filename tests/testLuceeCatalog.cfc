component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "lucee-catalog-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "Group-level maven-metadata.xml", function() {

			it( title="keeps only artifactIds ending in -extension, with latest and release", body=function() {
				var catalog = _newCatalog();
				var xml = '<?xml version="1.0" encoding="UTF-8"?>'
					& '<metadata><groupId>org.lucee</groupId><artifacts>'
					& '<artifact><artifactId>mysql-extension</artifactId><latest>9.1.1.lcl</latest><release>8.0.33</release></artifact>'
					& '<artifact><artifactId>lucee</artifactId><latest>6.2.0.321</latest><release>6.2.0.321</release></artifact>'
					& '<artifact><artifactId>cfspreadsheet-extension</artifactId><latest>3.0.3</latest><release>3.0.3</release></artifact>'
					& '</artifacts></metadata>';

				var rows = catalog.parseGroupMetadata( xml, "org.lucee" );
				var byId = {};
				for ( var row in rows ) {
					byId[ row.artifact ] = row;
				}

				expect( rows ).toHaveLength( 2 );
				expect( byId ).toHaveKey( "mysql-extension" );
				expect( byId ).toHaveKey( "cfspreadsheet-extension" );
				expect( byId ).notToHaveKey( "lucee" );
				expect( byId[ "mysql-extension" ].group ).toBe( "org.lucee" );
				expect( byId[ "mysql-extension" ].latest ).toBe( "9.1.1.lcl" );
				expect( byId[ "mysql-extension" ].release ).toBe( "8.0.33" );
				expect( byId[ "cfspreadsheet-extension" ].latest ).toBe( "3.0.3" );
			});

		});

		describe( "download8-compatible cache keys and never-cache-empty rules", function() {

			it( title="caches LuceeVersionsList under luceeVersionsList as {data,cachedAt} and never caches an empty list", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "versions/", memory={} );
				var catalog = _newCatalog( cache=cache, listVersions=function() { return []; } );

				expect( catalog.getVersionList() ).toBe( [] );
				expect( FileExists( variables.work & "versions/luceeVersionsList.json" ) ).toBeFalse();

				var calls = { n=0 };
				catalog = _newCatalog( cache=cache, listVersions=function() {
					calls.n++;
					return [ "6.2.0.321", "7.0.0.395" ];
				} );
				expect( catalog.getVersionList() ).toBe( [ "6.2.0.321", "7.0.0.395" ] );

				var raw = DeserializeJson( FileRead( variables.work & "versions/luceeVersionsList.json" ) );
				expect( raw ).toHaveKey( "data" );
				expect( raw ).toHaveKey( "cachedAt" );
				expect( raw.data ).toBe( [ "6.2.0.321", "7.0.0.395" ] );

				var cached = catalog.getVersionList();
				expect( cached ).toBe( [ "6.2.0.321", "7.0.0.395" ] );
				expect( calls.n ).toBe( 1 );
			});

			it( title="caches extension artifacts under extArtifacts_<gid> and never caches an empty result", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "arts/", memory={} );
				var catalog = _newCatalog(
					  cache          = cache
					, listExtensions = function( groupId ) { return []; }
					, httpClient     = { get=function( address, timeout ) { return { status=404, content="", error="missing" }; } }
				);

				expect( catalog.getExtensionArtifacts( "org.lucee" ) ).toBe( [] );
				expect( FileExists( variables.work & "arts/extArtifacts_org.lucee.json" ) ).toBeFalse();

				catalog = _newCatalog(
					  cache          = cache
					, listExtensions = function( groupId ) { return [ "mail-extension", "ftp-extension" ]; }
				);
				expect( catalog.getExtensionArtifacts( "org.lucee" ) ).toBe( [ "mail-extension", "ftp-extension" ] );

				var raw = DeserializeJson( FileRead( variables.work & "arts/extArtifacts_org.lucee.json" ) );
				expect( raw.data ).toBe( [ "mail-extension", "ftp-extension" ] );
				expect( raw ).toHaveKey( "cachedAt" );
			});

			it( title="caches versions under extver_<gid>_<aid>, drops -alpha, sorts descending", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "vers/", memory={} );
				var catalog = _newCatalog(
					  cache                 = cache
					, listExtensionVersions = function( groupId, artifactId ) {
						return [ "3.0.3", "3.0.5-alpha", "3.0.1" ];
					}
				);

				var list = catalog.getExtensionVersions( "io.forgebox", "cfspreadsheet-extension" );
				expect( list ).toBe( [ "3.0.3", "3.0.1" ] );

				var raw = DeserializeJson( FileRead( variables.work & "vers/extver_io.forgebox_cfspreadsheet-extension.json" ) );
				expect( raw.data ).toBe( [ "3.0.3", "3.0.1" ] );
				expect( raw ).toHaveKey( "cachedAt" );
			});

			it( title="stores extension detail under extdata_<gid>_<aid>_<ver> as the meta struct itself", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "data/", memory={} );
				var meta  = { name="Mail", version="1.1.0.17", jar="https://example.invalid/mail.jar" };
				var catalog = _newCatalog(
					  cache           = cache
					, extensionDetail = function( groupId, artifactId, version, download ) { return meta; }
				);

				expect( catalog.getExtensionDetail( "org.lucee", "mail-extension", "1.1.0.17" ) ).toBe( meta );

				var raw = DeserializeJson( FileRead( variables.work & "data/extdata_org.lucee_mail-extension_1.1.0.17.json" ) );
				expect( raw ).toBe( meta );
				expect( raw ).notToHaveKey( "data" );
				expect( raw ).notToHaveKey( "cachedAt" );
			});

			it( title="listCatalog reads latest and release from group XML of org.lucee and io.forgebox", body=function() {
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & "cat/", memory={} );
				var pages = {
					  "https://maven.lucee-services.com/org/lucee/maven-metadata.xml" =
						'<?xml version="1.0"?><metadata><artifacts>'
						& '<artifact><artifactId>mail-extension</artifactId><latest>1.1.0.19-SNAPSHOT</latest><release>1.1.0.17</release></artifact>'
						& '</artifacts></metadata>'
					, "https://maven.lucee-services.com/io/forgebox/maven-metadata.xml" =
						'<?xml version="1.0"?><metadata><artifacts>'
						& '<artifact><artifactId>cfspreadsheet-extension</artifactId><latest>3.0.3</latest><release>3.0.3</release></artifact>'
						& '</artifacts></metadata>'
				};
				var catalog = _newCatalog(
					  cache      = cache
					, httpClient = { get=function( address, timeout ) {
						if ( StructKeyExists( pages, arguments.address ) ) {
							return { status=200, content=pages[ arguments.address ], error="" };
						}
						return { status=404, content="", error="" };
					} }
				);

				var rows = catalog.listCatalog();
				var byId = {};
				for ( var row in rows ) {
					byId[ row.artifact ] = row;
				}

				expect( byId[ "mail-extension" ].group ).toBe( "org.lucee" );
				expect( byId[ "mail-extension" ].latest ).toBe( "1.1.0.19-SNAPSHOT" );
				expect( byId[ "mail-extension" ].release ).toBe( "1.1.0.17" );
				expect( byId[ "cfspreadsheet-extension" ].group ).toBe( "io.forgebox" );
				expect( byId[ "cfspreadsheet-extension" ].latest ).toBe( "3.0.3" );

				var raw = DeserializeJson( FileRead( variables.work & "cat/extArtifacts_org.lucee.json" ) );
				expect( raw.data ).toInclude( "mail-extension" );
			});

		});
	}

	private any function _newCatalog() {
		var args = arguments;

		if ( !StructKeyExists( args, "cache" ) ) {
			args.cache = new services.SharedDownloadCache( cacheDir=variables.work & "anon/", memory={} );
		}

		return new services.LuceeCatalog( argumentCollection=args );
	}

}
