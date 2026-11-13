component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "ARTIFACT_NOT_FOUND: greppable WARN line for a missing artifact", function() {

			it( title="formats a single line with the ARTIFACT_NOT_FOUND prefix and the requested type, path, id, version, qualifier, ip and ua", body=function() {
				var line = services.ArtifactNotFound::line(
					  type      = "core"
					, path      = "/rest/update/provider/download/9.9.9.9"
					, id        = ""
					, version   = "9.9.9.9"
					, qualifier = "lco"
					, ip        = "203.0.113.4"
					, ua        = "Lucee (CFML Engine)"
				);

				expect( line ).toInclude( "ARTIFACT_NOT_FOUND" );
				expect( Left( line, Len( "ARTIFACT_NOT_FOUND" ) ) ).toBe( "ARTIFACT_NOT_FOUND" );
				expect( line ).toInclude( "type=core" );
				expect( line ).toInclude( "path=/rest/update/provider/download/9.9.9.9" );
				expect( line ).toInclude( "version=9.9.9.9" );
				expect( line ).toInclude( "qualifier=lco" );
				expect( line ).toInclude( "ip=203.0.113.4" );
				expect( line ).toInclude( "ua=""Lucee (CFML Engine)""" );
				expect( ListLen( line, Chr( 10 ) ) ).toBe( 1 );
			});

			it( title="formats an extension miss with the id and version, and strips quotes and newlines so the line stays greppable", body=function() {
				var line = services.ArtifactNotFound::line(
					  type      = "extension"
					, path      = "/rest/extension/provider/full/missing-id"
					, id        = "missing-id"
					, version   = "1.0.0"
					, qualifier = "lex"
					, ip        = "198.51.100.10"
					, ua        = "Bad" & Chr( 10 ) & "Agent ""quoted"""
				);

				expect( line ).toInclude( "ARTIFACT_NOT_FOUND type=extension" );
				expect( line ).toInclude( "id=missing-id" );
				expect( line ).toInclude( "qualifier=lex" );
				expect( Find( Chr( 10 ), line ) ).toBe( 0 );
				expect( line ).notToInclude( "Agent ""quoted""" );
				expect( line ).toInclude( "ua=""Bad Agent quoted""" );
			});

			it( title="the PREFIX helper is exactly ARTIFACT_NOT_FOUND so Cloud Logging can filter on it", body=function() {
				expect( services.ArtifactNotFound::PREFIX() ).toBe( "ARTIFACT_NOT_FOUND" );
			});

		});
	}

}
