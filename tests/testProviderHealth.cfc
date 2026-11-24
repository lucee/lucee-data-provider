component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function afterAll() {
		services.ProviderHealth::markHealthy();
	}

	function run( testResults, testBox ) {

		describe( "Maven provider health check", function() {

			it( title="is healthy while nothing has failed (also during the first load)", body=function() {
				expect( services.ProviderHealth::isUnhealthy( since=0, thresholdSeconds=300, nowMs=1000000 ) ).toBeFalse();
			});

			it( title="stays healthy until the services have failed for the threshold", body=function() {
				var since = 1000000;
				expect( services.ProviderHealth::isUnhealthy( since=since, thresholdSeconds=300, nowMs=since + 299000 ) ).toBeFalse();
				expect( services.ProviderHealth::isUnhealthy( since=since, thresholdSeconds=300, nowMs=since + 300000 ) ).toBeTrue();
			});

			it( title="a threshold of 0 disables the failing answer", body=function() {
				expect( services.ProviderHealth::isUnhealthy( since=1, thresholdSeconds=0, nowMs=999999999 ) ).toBeFalse();
			});

			it( title="keeps the first failure time across retries and clears it once ready", body=function() {
				services.ProviderHealth::markHealthy();
				services.ProviderHealth::markFailing( 5000 );
				services.ProviderHealth::markFailing( 9000 );
				expect( services.ProviderHealth::failingSince() ).toBe( 5000 );
				services.ProviderHealth::markHealthy();
				expect( services.ProviderHealth::failingSince() ).toBe( 0 );
			});

		});
	}

}
