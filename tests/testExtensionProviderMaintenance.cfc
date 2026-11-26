component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/rest"     : ExpandPath( dir & "../apps/updateserver-maven/rest" )
		};
	}

	function run( testResults, testBox ) {

		describe( "ExtensionProvider: /reset and /updateCache are kept but do nothing", function() {

			it( title="reset and updateCache do not touch the extension meta", body=function() {
				var calls  = { n=0 };
				var reader = {
					  loadMeta       = function() { calls.n++; throw( message="must not be called" ); }
					, refreshIfStale = function() { calls.n++; throw( message="must not be called" ); }
				};
				var hadReader = StructKeyExists( application, "extMetaReader" );
				var oldReader = application.extMetaReader ?: "";
				var hadReady  = StructKeyExists( application, "servicesReady" );
				var oldReady  = application.servicesReady ?: "";
				application.extMetaReader = reader;
				application.servicesReady = true;
				try {
					var provider = new rest.ExtensionProvider();
					for ( var method in [ "reset", "updateCache" ] ) {
						try {
							invoke( provider, method );
						} catch ( any e ) {
							// RestSetResponse is only available within a REST request, that is all that may fail here
							expect( e.message ).notToInclude( "must not be called" );
						}
					}
				} finally {
					if ( hadReader ) application.extMetaReader = oldReader; else StructDelete( application, "extMetaReader" );
					if ( hadReady ) application.servicesReady = oldReady; else StructDelete( application, "servicesReady" );
				}

				expect( calls.n ).toBe( 0 );
			});

		});
	}

}
