/**
 * LDEV-6953 extracted the OSGi jars of an extension lex and served them from the disk of the instance. That is
 * switched off: a bundle that is only inside a lex is not found (a 404), the jar is published as
 * org.lucee:<Bundle-SymbolicName>:<Bundle-Version> with the "Upload Maven jar" workflow of lucee/Lucee instead.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/ldev6953" : dir
		};
	}

	function run( testResults, testBox ) {
		describe( "bundles are never extracted from an extension lex", function() {

			it( title="findBundle does not answer a lex, and serves no file", body=function() {
				// the stub answers a .lex for the raw search of org.lucee.chart.extension 2.0.0.1
				var lexFile = GetTempDirectory() & "ldev6953-" & CreateUniqueId() & ".lex";
				var svc = new services.BundleDownloadService(
					  extensionsCdnUrl    = ""
					, bundleS3Root        = ""
					, bundleCdnUrl        = ""
					, extensionMetaReader = new ldev6953.LDEV6953MetaStub()
					, mavenMatcher        = new ldev6953.LDEV6953MatcherStub( lexFile )
				);

				var chart = svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				expect( chart.url ?: "" ).toBe( "" );
				expect( chart ).notToHaveKey( "file" );
			});

			it( title="the service has no lex extraction left", body=function() {
				var src = FileRead( ExpandPath( variables.dir & "../apps/updateserver-maven/services/BundleDownloadService.cfc" ) );
				expect( FindNoCase( "_bundlesFromLex", src ) ).toBe( 0 );
				expect( FindNoCase( "java.util.zip.ZipFile", src ) ).toBe( 0 );
				expect( FindNoCase( "getExtensionFileMatchingBundle", src ) ).toBe( 0 );
			});

		});
	}

}
