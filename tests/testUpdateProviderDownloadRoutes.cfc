component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		variables.src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
		variables.extSrc = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/ExtensionProvider.cfc" ) );
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

			it( title="the download routes answer HEAD and OPTIONS like GET (HEAD was a 404)", body=function() {
				var routes = [ "loader/{version}", "light/{version}", "zero/{version}", "loader-all/{version}", "core/{version}"
					, "download/{version}", "war/{version}", "forgebox/{version}", "express/{version}", "dependencies/{version}" ];
				for ( var route in routes ) {
					expect( variables.src ).toInclude( 'httpmethod="GET,HEAD,OPTIONS" restpath="#route#"' );
				}
				expect( variables.src ).toInclude( 'httpmethod="GET,HEAD,OPTIONS" restpath="latest/{version}/{type}/{distribution}/{format}"' );
				expect( variables.src ).toInclude( "@httpmethod GET,HEAD,OPTIONS#Chr(10)#	 * @restpath   download/{bundlename}/{bundleversion}" );
				// war had a HEAD function of its own, GET,HEAD covers it now: one function per path and method
				expect( FindNoCase( 'httpmethod="HEAD"', variables.src ) ).toBe( 0 );
				expect( FindNoCase( "downloadWarHead", variables.src ) ).toBe( 0 );
				// OPTIONS: 204 with Allow, no lookup
				expect( variables.src ).toInclude( 'header name="Allow" value="GET, HEAD, OPTIONS"' );
				expect( variables.src ).toInclude( 'header statuscode="204"' );
			});

			it( title="the extension downloads answer HEAD and OPTIONS too", body=function() {
				expect( variables.extSrc ).toInclude( "@httpmethod GET,HEAD,OPTIONS#Chr(10)#	 * @restPath   full/{id}" );
				expect( variables.extSrc ).toInclude( "@httpmethod GET,HEAD,OPTIONS#Chr(10)#	 * @restPath   trial/{id}" );
				expect( variables.extSrc ).toInclude( 'header name="Allow" value="GET, HEAD, OPTIONS"' );
			});

			it( title="a bundle is a 302 to its URL or a 404, never a jar served from the disk of this instance", body=function() {
				expect( variables.src ).toInclude( "return _relocateForDowload( bundleUrl, arguments.bundleVersion );" );
				expect( FindNoCase( "_serveLocalBundleFile", variables.src ) ).toBe( 0 );
				expect( FindNoCase( "bundle.file", variables.src ) ).toBe( 0 );
				// the redirect can be cached by the client
				expect( variables.src ).toInclude( "services.DownloadCaching::forRedirect( arguments.bundleVersion )" );
			});

			it( title="the existence check of a core artifact is cached, a redirect is no HEAD request per download", body=function() {
				expect( variables.src ).toInclude( "application.remoteArtifactExists[ arguments.artifactUrl ]" );
				expect( variables.src ).toInclude( "GetTickCount() < known.until" );
			});

		});
	}

}
