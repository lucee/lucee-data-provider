component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "DownloadCaching: Cache-Control of the download answers", function() {

			it( title="a redirect to an explicitly given version is cached for a day", body=function() {
				expect( services.DownloadCaching::forRedirect( "3.0.2.29" ) ).toBe( "public, max-age=86400" );
				expect( services.DownloadCaching::forRedirect( "1.0.0.71-SNAPSHOT" ) ).toBe( "public, max-age=86400" );
			});

			it( title="a redirect to the latest version is only cached briefly, the next release changes it", body=function() {
				expect( services.DownloadCaching::forRedirect( "" ) ).toBe( "public, max-age=300" );
				expect( services.DownloadCaching::forRedirect( "latest" ) ).toBe( "public, max-age=300" );
			});

			it( title="not found is cached as long as the server remembers the miss", body=function() {
				expect( services.DownloadCaching::forNotFound() ).toBe( "public, max-age=300" );
			});

		});
	}

}
