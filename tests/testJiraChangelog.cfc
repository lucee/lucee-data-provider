component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

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

		} );
	}

}
