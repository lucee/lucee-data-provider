component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "jira-lazy-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "Maven Jira changelog does not block on an empty cache", function() {

			it( title="loadIssues without force leaves an empty cache empty and does not fetch Jira", body=function() {
				var service = new services.JiraChangeLogService();
				service.setS3Root( variables.work );
				service.loadIssues( force=false );

				var issues = service.getIssues();
				expect( issues ).toBeQuery();
				expect( issues.recordCount ).toBe( 0 );
				expect( FileExists( variables.work & "/issues.json" ) ).toBeFalse();
			});

			it( title="loadIssues reads a cached issues file when one is present", body=function() {
				var cached = QueryNew( "id,key,summary,self,type,created,updated,priority,status,fixVersions,labels" );
				QueryAddRow( cached );
				QuerySetCell( cached, "id", "1" );
				QuerySetCell( cached, "key", "LDEV-1" );
				QuerySetCell( cached, "summary", "cached" );
				QuerySetCell( cached, "self", "" );
				QuerySetCell( cached, "type", "Bug" );
				QuerySetCell( cached, "created", Now() );
				QuerySetCell( cached, "updated", Now() );
				QuerySetCell( cached, "priority", "High" );
				QuerySetCell( cached, "status", "Deployed" );
				QuerySetCell( cached, "fixVersions", [ "6.2.0.321" ] );
				QuerySetCell( cached, "labels", [] );
				FileWrite( variables.work & "/issues.json", SerializeJson( cached ) );

				var service = new services.JiraChangeLogService();
				service.setS3Root( variables.work );
				service.loadIssues( force=false );

				expect( service.getIssues().recordCount ).toBe( 1 );
				expect( service.getIssues().key ).toBe( "LDEV-1" );
			});

		});
	}

}
