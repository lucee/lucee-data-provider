component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "ext-discovery-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "Group-level extension discovery for org.lucee and io.forgebox", function() {

			it( title="lists artifacts from both groups and only the latest and release when latestOnly is set", body=function() {
				var catalog = _catalogWithRows( [
					  { group="org.lucee", artifact="mail-extension", latest="1.1.0.19-SNAPSHOT", release="1.1.0.17" }
					, { group="io.forgebox", artifact="cfspreadsheet-extension", latest="3.0.3", release="3.0.3" }
				] );
				var source = _source( catalog );

				var all = source.listExtensions();
				expect( _names( all.files ) ).toHaveKey( "mail-extension-1.1.0.19-SNAPSHOT.lex" );
				expect( _names( all.files ) ).toHaveKey( "mail-extension-1.1.0.17.lex" );
				expect( _names( all.files ) ).toHaveKey( "mail-extension-1.1.0.16.lex" );
				expect( _names( all.files ) ).toHaveKey( "cfspreadsheet-extension-3.0.3.lex" );
				expect( _file( all.files, "cfspreadsheet-extension-3.0.3.lex" ).group ).toBe( "io.forgebox" );

				var latest = source.listExtensions( latestOnly=true );
				expect( _names( latest.files ) ).toHaveKey( "mail-extension-1.1.0.19-SNAPSHOT.lex" );
				expect( _names( latest.files ) ).toHaveKey( "mail-extension-1.1.0.17.lex" );
				expect( _names( latest.files ) ).notToHaveKey( "mail-extension-1.1.0.16.lex" );
				expect( _names( latest.files ) ).toHaveKey( "cfspreadsheet-extension-3.0.3.lex" );
				expect( latest.files ).toHaveLength( 3 );
			});

			it( title="also discovers artifacts that are only in a repository HTML listing (e.g. Maven Central)", body=function() {
				var catalog = _catalogWithRows( [
					{ group="org.lucee", artifact="mail-extension", latest="1.1.0.19-SNAPSHOT", release="1.1.0.17" }
				] );
				var world = {
					  pages    = {}
					, files    = {}
					, status   = {}
					, requests = ArrayNew( 1, true )
				};
				var central = "https://repo1.example.invalid/";
				world.pages[ central & "org/lucee/" ] = '<html><a href="debugger-extension/">debugger-extension/</a><a href="mail-extension/">mail-extension/</a></html>';
				world.pages[ central & "org/lucee/debugger-extension/maven-metadata.xml" ] =
					'<?xml version="1.0"?><metadata><versioning><versions><version>3.0.0.8</version></versions></versioning></metadata>';
				world.pages[ central & "org/lucee/mail-extension/maven-metadata.xml" ] =
					'<?xml version="1.0"?><metadata><versioning><versions><version>1.1.0.17</version></versions></versioning></metadata>';

				var source = new services.MavenExtensionSource(
					  mixedRepos   = [ "https://maven.lucee-services.com/" ]
					, releaseRepos = [ central ]
					, groups       = [ "org.lucee", "io.forgebox" ]
					, catalog      = catalog
					, httpClient   = { get=function( address, timeout ) {
						if ( StructKeyExists( world.pages, arguments.address ) ) {
							return { status=200, content=world.pages[ arguments.address ], error="" };
						}
						return { status=404, content="", error="" };
					} }
				);

				var names = _names( source.listExtensions( latestOnly=true ).files );
				expect( names ).toHaveKey( "mail-extension-1.1.0.19-SNAPSHOT.lex" );
				expect( names ).toHaveKey( "mail-extension-1.1.0.17.lex" );
				expect( names ).toHaveKey( "debugger-extension-3.0.0.8.lex" );
			});

			it( title="latestOnly loads the newest final version even when group XML latest and release are pre-releases", body=function() {
				var catalog = _catalogWithRows( [
					{ group="org.lucee", artifact="s3-extension", latest="2.2.0.5-SNAPSHOT", release="2.2.0.3-RC" }
				] );
				// versions include a newer stable than the group-XML release, as on Maven Central
				var versions = { "s3-extension" = [ "2.2.0.5-SNAPSHOT", "2.2.0.3-RC", "2.1.0.15", "2.0.3.6" ] };
				var cache = new services.SharedDownloadCache( cacheDir=variables.work & CreateUniqueId() & "/", memory={} );
				var catalog = new services.LuceeCatalog(
					  cache                 = cache
					, listExtensionVersions = function( groupId, artifactId ) {
						return versions[ arguments.artifactId ] ?: [];
					}
					, httpClient = { get=function( address, timeout ) {
						var xml = '<?xml version="1.0"?><metadata><artifacts>'
							& '<artifact><artifactId>s3-extension</artifactId><latest>2.2.0.5-SNAPSHOT</latest><release>2.2.0.3-RC</release></artifact>'
							& '</artifacts></metadata>';
						return { status=200, content=xml, error="" };
					} }
				);
				var source = _source( catalog );
				var latest = source.listExtensions( latestOnly=true );
				expect( _names( latest.files ) ).toHaveKey( "s3-extension-2.2.0.5-SNAPSHOT.lex" );
				expect( _names( latest.files ) ).toHaveKey( "s3-extension-2.1.0.15.lex" );
				expect( _names( latest.files ) ).notToHaveKey( "s3-extension-2.2.0.3-RC.lex" );
				expect( _names( latest.files ) ).notToHaveKey( "s3-extension-2.0.3.6.lex" );
			});

			it( title="builds io.forgebox artifact URLs from the artifact's own group, not org.lucee", body=function() {
				var catalog = _catalogWithRows( [
					{ group="io.forgebox", artifact="cfspreadsheet-extension", latest="3.0.3", release="3.0.3" }
				] );
				var source = _source( catalog );
				source.listExtensions( latestOnly=true ); // learn the artifact's group
				var fileUrl = source.getFileUrl( "cfspreadsheet-extension", "3.0.3", [ "https://maven.lucee-services.com/" ] );

				expect( fileUrl ).toInclude( "io/forgebox/cfspreadsheet-extension/3.0.3/" );
				expect( fileUrl ).notToInclude( "org/lucee/cfspreadsheet-extension" );
			});

		});
	}

	private any function _catalogWithRows( required array rows ) {
		var versions = {
			  "mail-extension"           = [ "1.1.0.19-SNAPSHOT", "1.1.0.17", "1.1.0.16" ]
			, "cfspreadsheet-extension"  = [ "3.0.3" ]
		};
		var cache = new services.SharedDownloadCache( cacheDir=variables.work & CreateUniqueId() & "/", memory={} );

		return new services.LuceeCatalog(
			  cache                 = cache
			, listExtensionVersions = function( groupId, artifactId ) {
				return versions[ arguments.artifactId ] ?: [];
			}
			, httpClient = { get=function( address, timeout ) {
				var xml = '<?xml version="1.0"?><metadata><artifacts>';
				for ( var row in rows ) {
					if ( FindNoCase( Replace( row.group, ".", "/", "all" ) & "/maven-metadata.xml", arguments.address ) ) {
						xml &= "<artifact><artifactId>#row.artifact#</artifactId><latest>#row.latest#</latest><release>#row.release#</release></artifact>";
					}
				}
				xml &= "</artifacts></metadata>";
				return { status=200, content=xml, error="" };
			} }
		);
	}

	private any function _source( required any catalog ) {
		return new services.MavenExtensionSource(
			  mixedRepos = [ "https://maven.lucee-services.com/" ]
			, groups     = [ "org.lucee", "io.forgebox" ]
			, catalog    = arguments.catalog
			, httpClient = { get=function( address, timeout ) { return { status=404, content="", error="" }; } }
		);
	}

	private struct function _names( files ) {
		var names = {};
		for ( var file in arguments.files ) {
			names[ file.name ] = true;
		}
		return names;
	}

	private struct function _file( files, name ) {
		for ( var file in arguments.files ) {
			if ( file.name == arguments.name ) {
				return file;
			}
		}
		throw( message="[#arguments.name#] not found" );
	}

}
