component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/noopmavenrest" : ExpandPath( dir & "../apps/updateserver-maven/rest" )
		};
	}

	function run( testResults, testBox ) {

		describe( "Maven UpdateProvider buildLatest, list-missing and cleanupForgeboxSnapshots", function() {

			it( title="buildLatest does nothing and says so, without the services", body=function() {
				var rsp = new noopmavenrest.UpdateProvider().buildLatest();

				expect( rsp.type ).toBe( "info" );
				expect( rsp.message ).toInclude( "Nothing to do" );
			});

			it( title="list-missing has nothing missing", body=function() {
				expect( new noopmavenrest.UpdateProvider().listMissing() ).toBe( {} );
			});

			it( title="cleanupForgeboxSnapshots does nothing for GET and POST, with or without a token", body=function() {
				var provider = new noopmavenrest.UpdateProvider();

				expect( provider.cleanupForgeboxSnapshots().type ).toBe( "info" );
				expect( provider.cleanupForgeboxSnapshots( token="x", dryRun=true ).type ).toBe( "info" );
				expect( provider.cleanupForgeboxSnapshotsPost( token="x" ).type ).toBe( "info" );
			});

		});
	}

}
