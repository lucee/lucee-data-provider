component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function run( testResults , testBox ) {
		describe( "check that the production server can be accessed with java U/As", function() {
			it(title="check user agents can access https://update.lucee.org/", body=function(){

				// update provider is nehind cloudflare, their default WAF blocks onlder java clients etc
				var userAgents = [
					"Java/1.8.0_151",
					"Apache-HttpClient/4.5.13 (Java/17.0.2)",
					"Apache-HttpClient/4.5.2 (Java/1.8.0_282)",
					"Apache-HttpClient/4.5.2 (Java/1.8.0_162)",
					"Java/1.8.0_282",
					"Apache-HttpClient/4.5.13 (Java/1.8.0_231)",
					"Apache-HttpClient/4.5.6 (Java/21.0.1)",
					"Apache-HttpClient/4.5.14 (Java/17.0.8)",
					"Apache-HttpClient/4.5.13+(Java/1.8.0_402)",
					"Java-http-client/11.0.22.0.101",
					"Java/1.8.0_391",
					"Apache-HttpClient/5.2.1 (Java/11.0.22)",
					"Apache-HttpClient/4.5.12 (Java/1.8.0_382)",
					"Apache-HttpClient/4.5.13 (Java/11.0.15)",
					"Java/11.0.15",
					"Java-http-client/21.0.2",
					"Apache-HttpClient/5.3 (Java/21)",
					"Java/11.0.14.1",
					"Java/1.8.0_332",
					"Java/11.0.22",
					"Java/18.0.1.1",
					"Apache-HttpClient/4.5.13 (Java/11.0.22.0.0.1)",
					"Lucee",
					"Lucee 6.0.3.1",
					"CFSCHEDULE"
				];

				var failed = [];
				var res = "";

				for ( var UA in userAgents ){
					http url="https://update.lucee.org/" userAgent=#UA# result="res";
					if ( res.status_code ?: 0 neq 200 ){
						arrayAppend( failed, "cfhttp with [#UA#] returned #res.status_code#" );
					}
				}

				if ( len( failed ) gt 0 ) {
					for (failure in failed){
						systemOutput( failure, true );
					}
				}
				expect( len( failed ) ).toBe( 0 );
			});

		});
	}

}
