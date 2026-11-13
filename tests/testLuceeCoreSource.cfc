component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "LuceeCoreSource", function() {

			it( title="lists versions from LuceeVersionsList via the shared catalog", body=function() {
				var catalog = new services.LuceeCatalog(
					  cache        = new services.SharedDownloadCache( cacheDir=GetTempDirectory() & "core-src-" & CreateUniqueId() & "/", memory={} )
					, listVersions = function() { return [ "6.2.0.321", "7.0.0.395" ]; }
				);
				var source = new services.LuceeCoreSource( catalog=catalog );
				var found  = source.listVersions();

				expect( found.complete ).toBeTrue();
				expect( found.versions ).toHaveKey( "6.2.0.321" );
				expect( found.versions[ "6.2.0.321" ] ).toBe( [ "lucee-versions" ] );
				expect( source.hasType( "lco" ) ).toBeTrue();
				expect( source.getCoreFileName( "light", "6.2.0.321", "" ) ).toBe( "lucee-6.2.0.321-light.jar" );
			});

			it( title="prefers LuceeVersionsDetail URLs and falls back to the Maven layout for other classifiers", body=function() {
				var catalog = new services.LuceeCatalog(
					  cache         = new services.SharedDownloadCache( cacheDir=GetTempDirectory() & "core-src-" & CreateUniqueId() & "/", memory={} )
					, listVersions  = function() { return [ "6.2.0.321" ]; }
					, versionDetail = function( version ) {
						return { jar="https://maven.lucee-services.com/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar"
							, lco="https://maven.lucee-services.com/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" };
					}
				);
				var source = new services.LuceeCoreSource( catalog=catalog, mixedRepo="https://maven.lucee-services.com/" );

				expect( source.getCoreFileUrl( "jar", "6.2.0.321", [] ) )
					.toBe( "https://maven.lucee-services.com/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar" );
				expect( source.getCoreFileUrl( "light", "6.2.0.321", [] ) )
					.toBe( "https://maven.lucee-services.com/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar" );
				expect( source.getCoreFileUrl( "war", "6.2.0.321", [] ) )
					.toBe( "https://maven.lucee-services.com/org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.war" );
			});

		});
	}

}
