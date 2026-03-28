component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll(){
	}

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		var servicesDir = expandPath( dir & "../apps/updateserver/services" );
		application action="update" mappings={
			"/services" : servicesDir
		};
		// Use a fake DSN for testing
		variables.testDsn = "https://test-public-key@test-host.sentry.io/12345";
	}

	function run( testResults, testBox ) {
		describe( "SentryLogger Tests", function() {

			it( title="should initialize with valid DSN", body=function(){
				var logger = new services.SentryLogger(
					config = {
						dsn = testDsn,
						environment = "test"
					}
				);
				expect( logger ).toBeInstanceOf( "services.SentryLogger" );
			});

			it( title="should work with missing DSN (dev mode)", body=function(){
				var logger = new services.SentryLogger(
					config = {}
				);
				expect( logger ).toBeInstanceOf( "services.SentryLogger" );

				// Should not actually send to Sentry but returns success
				var result = logger.logMessage(
					message = "Test message without DSN",
					level = "info"
				);
				expect( result ).toBeStruct();
				expect( result ).toHaveKey( "success" );
				expect( result.success ).toBeTrue(); // Returns true but doesn't send
				expect( result ).toHaveKey( "note" ); // Should have a note explaining why
			});

			it( title="should work with empty DSN string", body=function(){
				var logger = new services.SentryLogger(
					config = { dsn = "" }
				);
				expect( logger ).toBeInstanceOf( "services.SentryLogger" );

				var result = logger.logMessage(
					message = "Test message with empty DSN",
					level = "info"
				);
				expect( result ).toBeStruct();
				expect( result.success ).toBeTrue(); // Returns true but doesn't send
				expect( result ).toHaveKey( "note" ); // Should explain no DSN
			});

			it( title="should fail with invalid DSN format", body=function(){
				expect( function(){
					new services.SentryLogger(
						config = { dsn = "invalid-dsn-format" }
					);
				}).toThrow( type="Sentry.ConfigurationException" );
			});

			it( title="should parse DSN correctly", body=function(){
				var logger = new services.SentryLogger(
					config = { dsn = testDsn }
				);

				// Access private sentryInfo via reflection or test public behavior
				var result = logger.logMessage(
					message = "Test message",
					level = "info"
				);

				// Should return a struct with success/error info
				expect( result ).toBeStruct();
				expect( result ).toHaveKey( "success" );
			});

			it( title="should log message without throwing", body=function(){
				var logger = new services.SentryLogger(
					config = {
						dsn = testDsn,
						environment = "test"
					}
				);

				var result = logger.logMessage(
					message = "Test info message",
					level = "info"
				);

				expect( result ).toBeStruct();
			});

			it( title="should log exception without throwing", body=function(){
				var logger = new services.SentryLogger(
					config = {
						dsn = testDsn,
						environment = "test"
					}
				);

				try {
					throw( type="TestException", message="This is a test exception" );
				} catch ( any e ) {
					var result = logger.logException(
						exception = e,
						level = "error"
					);

					expect( result ).toBeStruct();
					expect( result ).toHaveKey( "success" );
				}
			});

			it( title="should accept tags and extra data", body=function(){
				var logger = new services.SentryLogger(
					config = {
						dsn = testDsn,
						environment = "test"
					}
				);

				var result = logger.logMessage(
					message = "Test with metadata",
					level = "info",
					tags = { "component" = "test", "action" = "testing" },
					extra = { "userId" = 123, "debugInfo" = "some data" }
				);

				expect( result ).toBeStruct();
			});

			it( title="should accept user context", body=function(){
				var logger = new services.SentryLogger(
					config = {
						dsn = testDsn,
						environment = "test"
					}
				);

				var result = logger.logMessage(
					message = "Test with user",
					level = "info",
					user = { "id" = "user123", "email" = "test@example.com" }
				);

				expect( result ).toBeStruct();
			});

			it( title="should use default environment if not specified", body=function(){
				var logger = new services.SentryLogger(
					config = { dsn = testDsn }
				);

				var result = logger.logMessage(
					message = "Test default environment",
					level = "info"
				);

				expect( result ).toBeStruct();
			});

			it( title="should handle different severity levels", body=function(){
				var logger = new services.SentryLogger(
					config = { dsn = testDsn }
				);

				var levels = [ "debug", "info", "warning", "error", "fatal" ];

				for ( var level in levels ) {
					var result = logger.logMessage(
						message = "Test #level# level",
						level = level
					);
					expect( result ).toBeStruct();
				}
			});

		});
	}
}
