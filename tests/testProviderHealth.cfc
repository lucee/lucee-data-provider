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

			it( title="is ready once the services are loaded (the /ready/ startup probe)", body=function() {
				var key = "luceeProviderMavenReady";
				var had = StructKeyExists( server, key );
				var was = server[ key ] ?: false;
				try {
					StructDelete( server, key );
					expect( services.ProviderHealth::isReady() ).toBeFalse();
					server[ key ] = "not a boolean";
					expect( services.ProviderHealth::isReady() ).toBeFalse();
					services.ProviderHealth::markReady();
					expect( services.ProviderHealth::isReady() ).toBeTrue();
				} finally {
					if ( had ) {
						server[ key ] = was;
					} else {
						StructDelete( server, key );
					}
				}
			});

		});
	}

}
