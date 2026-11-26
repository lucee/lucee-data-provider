component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			  "/depsmavenrest" : ExpandPath( dir & "../apps/updateserver-maven/rest" )
			, "/services"      : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
		variables.keys = [ "servicesReady", "servicesError", "bundleDownloadService", "coreS3Root", "coreCdnUrl", "jiraChangelogService", "coreVersions", "dependencyBuilds" ];
	}

	function run( testResults, testBox ) {

		describe( "Maven UpdateProvider dependencies/{version} and dependencies-read/{version}", function() {

			beforeEach( function() {
				variables.saved = {};
				for ( var key in variables.keys ) {
					variables.saved[ key ] = application[ key ] ?: javacast( "null", 0 );
				}
				application.servicesReady         = true;
				application.servicesError         = "";
				application.bundleDownloadService = "";
				application.coreS3Root            = "";
				application.coreCdnUrl            = "";
				application.jiraChangelogService  = {};
				application.coreVersions          = { getVersions=function() { return { "07.000.006.0010.100"={ version="7.0.6.10" } }; } };
				application.dependencyBuilds      = {};
			});

			afterEach( function() {
				for ( var key in variables.keys ) {
					if ( IsNull( variables.saved[ key ] ) ) {
						StructDelete( application, key );
					} else {
						application[ key ] = variables.saved[ key ];
					}
				}
			});

			it( title="answers a version that is not a core version right away", body=function() {
				var provider = new depsmavenrest.UpdateProvider();
				var started  = GetTickCount();

				var rsp = provider.getDependencies( "1.2.3.4" );
				// the 404 was set on the response of the test request
				expect( getPageContext().getResponse().getStatus() ).toBe( 404 );
				getPageContext().getResponse().setStatus( 200 );
				expect( rsp.type ).toBe( "error" );
				expect( rsp.message ).toInclude( "1.2.3.4" );
				expect( GetTickCount() - started ).toBeLT( 2000 );
			});

			it( title="waits for the build at most DEPENDENCIES_WAIT_SECONDS, the build goes on in the background", body=function() {
				expect( variables.src ).toInclude( "DEPENDENCIES_WAIT_SECONDS" );
				expect( variables.src ).toInclude( 'thread name="dependencies-' );
				expect( variables.src ).toInclude( 'header name="Retry-After" value="30"' );
				// no request builds the dependencies itself anymore
				var fn = Mid( variables.src, Find( 'restpath="dependencies/{version}"', variables.src ), 600 );
				expect( fn ).notToInclude( "mr.getDependencies" );
			});

			it( title="returns the dependencies of a listed version that is already built", body=function() {
				getPageContext().getResponse().setStatus( 200 );
				application.dependencyBuilds = {
					"list:7.0.6.10"={ status="done", ended=Now(), result=[ "org.lucee.commons-io-2.16.1.jar" ] }
				};
				var provider = new depsmavenrest.UpdateProvider();
				var rsp = provider.getDependencies( "7.0.6.10" );
				expect( getPageContext().getResponse().getStatus() ).toBe( 200 );
				expect( rsp ).toBe( [ "org.lucee.commons-io-2.16.1.jar" ] );
			});

			it( title="does not report a listed version whose build failed as missing", body=function() {
				getPageContext().getResponse().setStatus( 200 );
				application.dependencyBuilds = {
					"list:7.0.6.10"={ status="failed", ended=Now(), error="No POM with <dependencies> is available for version 7.0.6.10" }
				};
				var provider = new depsmavenrest.UpdateProvider();
				var rsp = provider.getDependencies( "7.0.6.10" );
				expect( getPageContext().getResponse().getStatus() ).toBe( 500 );
				getPageContext().getResponse().setStatus( 200 );
				expect( rsp.type ).toBe( "error" );
				expect( rsp.message ).toInclude( "7.0.6.10" );
				expect( rsp.message ).toInclude( "could not be built" );
				expect( rsp.message ).notToInclude( "is not available" );
			});

		});
	}

}
