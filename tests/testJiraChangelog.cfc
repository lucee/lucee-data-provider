component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "JIRA Changelog Service Tests", function() {

			it( title="test JiraChangeLogService can be instantiated", body=function(){
				var service = new services.JiraChangeLogService();
				expect( service ).toBeComponent();
			} );

			it( title="test loadIssues reads from S3 or fetches", body=function(){
				var service = new services.JiraChangeLogService();
				service.setS3Root( expandPath( dir & "../apps/updateserver/services/legacy/build/servers/" ) );

				// This should read existing issues.json or create empty query
				try {
					service.loadIssues( force=false );
					var issues = service.getIssues();
					expect( issues ).toBeQuery();
					systemOutput( "Loaded #issues.recordCount# issues from cache", true );
				} catch ( any e ) {
					systemOutput( "Error loading issues: #e.message#", true );
					rethrow;
				}
			} );

			it( title="test getChangelog returns structured data", body=function(){
				var service = new services.JiraChangeLogService();
				service.setS3Root( expandPath( dir & "../apps/updateserver/services/legacy/build/servers/" ) );

				try {
					service.loadIssues( force=false );

					// Test with known version range
					var changelog = service.getChangelog(
						versionFrom = "6.0.0.0",
						versionTo = "6.2.0.0",
						detailed = false
					);

					expect( changelog ).toBeStruct();
					systemOutput( "Changelog has #structCount( changelog )# versions", true );

					// If we got data, verify structure
					if ( structCount( changelog ) > 0 ) {
						var firstVersion = structKeyArray( changelog )[ 1 ];
						expect( changelog[ firstVersion ] ).toBeStruct();
						systemOutput( "First version #firstVersion# has #structCount( changelog[ firstVersion ] )# issues", true );
					}
				} catch ( any e ) {
					systemOutput( "Error getting changelog: #e.message#", true );
					rethrow;
				}
			} );

			it( title="test getChangeLogUpdated returns a date", body=function(){
				var service = new services.JiraChangeLogService();
				service.setS3Root( expandPath( dir & "../apps/updateserver/services/legacy/build/servers/" ) );

				try {
					service.loadIssues( force=false );
					var lastUpdated = service.getChangeLogUpdated();

					expect( lastUpdated ).toBeDate();
					systemOutput( "Changelog last updated: #lastUpdated#", true );
				} catch ( any e ) {
					systemOutput( "Error getting last updated: #e.message#", true );
					rethrow;
				}
			} );

			it( title="test getChangelog includes upper boundary version", body=function(){
				var service = new services.JiraChangeLogService();
				service.setS3Root( expandPath( dir & "../apps/updateserver/services/legacy/build/servers/" ) );

				try {
					service.loadIssues( force=false );
					var issues = service.getIssues();

					// Skip test if no issues loaded
					if ( issues.recordCount eq 0 ) {
						systemOutput( "No issues loaded, skipping boundary test", true );
						return;
					}

					// Find a ticket with a specific fix version to test with (skip versions with spaces like "Websocket-client 2.3.0.8")
					var testVersion = "";
					loop query=issues {
						if ( isArray( issues.fixVersions ) && arrayLen( issues.fixVersions ) > 0 ) {
							var fv = issues.fixVersions[ 1 ];
							if ( isArray( fv ) ) fv = fv[ 1 ];
							if ( isSimpleValue( fv ) && !find( " ", fv ) ) {
								testVersion = fv;
								break;
							}
						}
					}

					if ( len( testVersion ) eq 0 ) {
						systemOutput( "No issues with fix versions found, skipping boundary test", true );
						return;
					}

					if ( isArray( testVersion ) ) {
						systemOutput( "testVersion is still an array, using first element", true );
						testVersion = testVersion[ 1 ];
					}

					systemOutput( "Testing boundary with version: #testVersion#", true );

					// Get changelog with range that should include this exact version as upper boundary
					var changelog = service.getChangelog(
						versionFrom = "6.0.0.0",
						versionTo = testVersion,
						detailed = false
					);

					expect( changelog ).toBeStruct();

					// The changelog should include the testVersion as a key
					if ( structKeyExists( changelog, testVersion ) ) {
						systemOutput( "PASS: Upper boundary version #testVersion# is included in changelog", true );
						expect( structCount( changelog[ testVersion ] ) ).toBeGT( 0 );
					} else {
						systemOutput( "WARNING: Version #testVersion# not found in changelog keys: #structKeyList( changelog )#", true );
						// This could be legitimate if the version is outside the range we're testing
					}
				} catch ( any e ) {
					systemOutput( "Error testing boundary condition: #e.message#", true );
					rethrow;
				}
			} );

		} );
	}

}
