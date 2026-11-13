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
