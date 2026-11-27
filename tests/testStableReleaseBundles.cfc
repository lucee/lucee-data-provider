component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		// the bundle lookup of the Maven only app (the code of this repository), not the live update.lucee.org
		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver-maven/services" )
		};
		variables.artifacts = dir & "/artifacts";
		if ( !DirectoryExists( variables.artifacts ))
			directoryCreate( variables.artifacts );
	}

	function run( testResults , testBox ) {
		describe( "check all bundles in stable lucee release manifests are supported", function() {
			it(title="6.0.3.1", body=function(){
				checkRequiredBundlesAreSupported( "6.0.3.1" );
			});

			it(title="6.0.1.83", body=function(){
				checkRequiredBundlesAreSupported( "6.0.1.83" );
			});

			it(title="6.0.0.585", body=function(){
				checkRequiredBundlesAreSupported( "6.0.0.585" );
			});

			it(title="5.4.6.9", body=function(){
				checkRequiredBundlesAreSupported( "5.4.6.9" );
			});

			it(title="5.4.5.23", body=function(){
				checkRequiredBundlesAreSupported( "5.4.6.9" );
			});

			it(title="5.4.3.2", body=function(){
				checkRequiredBundlesAreSupported( "5.4.6.9" );
			});

			it(title="5.3.12.1", body=function(){
				checkRequiredBundlesAreSupported( "5.3.12.1" );
			});

			it(title="5.3.11.5", body=function(){
				checkRequiredBundlesAreSupported( "5.3.11.5" );
			});

			it(title="5.3.9.173", body=function(){
				checkRequiredBundlesAreSupported( "5.3.9.173" );
			});

			it(title="5.3.8.237", body=function(){
				checkRequiredBundlesAreSupported( "5.3.8.237" );
			});

			it(title="5.2.9.31", body=function(){
				checkRequiredBundlesAreSupported( "5.2.9.31" );
			});

			it(title="5.0.1.85", body=function(){
				checkRequiredBundlesAreSupported( "5.0.1.85" );
			});

			// pre osgi !!!!
			//it(title="4.5.5.017", body=function(){
			//	checkRequiredBundlesAreSupported( "4.5.5.017" );
			//});
		});
	}

	private function checkRequiredBundlesAreSupported( string version ){
		var core = fetchLuceeCore( arguments.version );
		var manifest = ManifestRead( core );
		var requiredBundles = manifest.main[ "Require-Bundle" ];
		var bundle = "";
		// var BundleDownloadService = new services.BundleDownloadService(); // needs creds
		var missing  = [];
			
		loop list=requiredBundles item="bundle" {
			// systemOutput( bundle, true );
			var result = fetchBundle( bundle );
			if ( len ( result ) ){
				arrayAppend( missing, result );
			}
		}
		if ( len( missing ) ){
			systemOutput( "", true );
			systemOutput( "#version# has unsupported bundles required", true );
		}
		for ( var m in missing ){
			systemOutput( chr(9) & m, true );
		}
		expect ( len( missing ) ).toBe( 0, version );

		fileDelete( core );
	}

	/**
	 * Resolves the bundle with the lookup the update provider (apps/updateserver-maven) runs for
	 * /rest/update/provider/download/{bundle}/{version}: BundleDownloadService.findBundle with the
	 * MavenMatcher, so Maven Central, org.lucee on maven.lucee-services.com, the dashed/dotted name variants.
	 * The extension lex lookup is not part of this test (no extension metadata here).
	 * Returns "" when the bundle is found, otherwise "name/version".
	 */
	private function fetchBundle( string bundle ) cachedWithin="request" {
		var bundleName    = listFirst( bundle, ";" );
		var bundleVersion = listLast( listLast( bundle, ";" ), "=" );
		var bundleSpec    = bundleName & "/" & bundleVersion;

		try {
			var found = getBundleService().findBundle( bundleName, bundleVersion );
			if ( structCount( found ) && ( len( found.url ?: "" ) || len( found.file ?: "" ) ) ) {
				return "";
			}
			systemOutput( "the update provider code finds no bundle for [#bundleSpec#]", true );
		} catch ( any e ) {
			systemOutput( "the update provider code threw [" & e.message & "] for [#bundleSpec#]", true );
		}
		return bundleSpec;
	}

	private function getBundleService() {
		if ( !structKeyExists( variables, "bundleService" ) ) {
			variables.bundleService = new services.BundleDownloadService(
				  extensionsCdnUrl    = ""
				, bundleS3Root        = ""
				, bundleCdnUrl        = ""
				, extensionMetaReader = new LDEV6953MetaStub()
				, mavenMatcher        = new services.legacy.MavenMatcher()
			);
		}
		return variables.bundleService;
	}

	private function fetchLuceeCore( string version ){
		if ( fileExists( variables.artifacts & "/#arguments.version#.lco" ))
			return variables.artifacts & "/#arguments.version#.lco";
		var artifact = "https://cdn.lucee.org/#arguments.version#.lco";

		systemOutput( "Downloading #artifact# (cache miss)", true);
		http url=artifact method="get" result="local.core" path=variables.artifacts;
		var file = directoryList(path=variables.artifacts, filter="#arguments.version#.lco");
		//systemOutput(file, true);
		return file[ 1 ];
	}

}
