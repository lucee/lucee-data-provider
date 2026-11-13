component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		variables.src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
	}

	function run( testResults, testBox ) {

		describe( "Maven UpdateProvider download routes", function() {

			it( title="core/{version} redirects to the lco artifact, not a missing downloadCoreNew", body=function() {
				expect( variables.src ).toInclude( 'restpath="core/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("lco"' );
				expect( FindNoCase( "downloadCoreNew", variables.src ) ).toBe( 0 );
			});

			it( title="loader-all/{version} redirects to the jar, not a missing downLoaderNew", body=function() {
				expect( variables.src ).toInclude( 'restpath="loader-all/{version}"' );
				expect( FindNoCase( "downLoaderNew", variables.src ) ).toBe( 0 );
			});

			it( title="zero/{version} redirects to the zero artifact", body=function() {
				expect( variables.src ).toInclude( 'restpath="zero/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("zero"' );
			});

			it( title="loader, light, download, war and express still redirect to their types", body=function() {
				expect( variables.src ).toInclude( 'restpath="loader/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("jar"' );
				expect( variables.src ).toInclude( 'restpath="light/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("light"' );
				expect( variables.src ).toInclude( 'restpath="download/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("lco"' );
				expect( variables.src ).toInclude( 'restpath="war/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("war"' );
				expect( variables.src ).toInclude( 'restpath="express/{version}"' );
				expect( variables.src ).toInclude( 'redirectToCore("express"' );
			});

		});
	}

}
