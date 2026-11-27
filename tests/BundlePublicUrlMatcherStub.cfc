/**
 * Matcher stub for testBundlePublicUrl: the lex of org.lucee.chart.extension is found by the raw search, a public
 * jar URL is only known for the bundles in [publicUrls] (looked up with jarsOnly=true). Counts the calls.
 */
component {

	function init( required string lexFile, struct publicUrls={}, boolean failJarsOnly=false ) {
		variables.lexFile      = arguments.lexFile;
		variables.publicUrls   = arguments.publicUrls;
		variables.failJarsOnly = arguments.failJarsOnly;
		variables.calls        = [];
		return this;
	}

	public function findBundleUrl( required string bundleName, string bundleVersion="latest", boolean rawSearch=false, boolean jarsOnly=false ) {
		ArrayAppend( variables.calls, { bundleName=arguments.bundleName, bundleVersion=arguments.bundleVersion, rawSearch=arguments.rawSearch, jarsOnly=arguments.jarsOnly } );
		if ( arguments.jarsOnly ) {
			if ( variables.failJarsOnly ) {
				throw( message="repository not reachable" );
			}
			return variables.publicUrls[ arguments.bundleName & ":" & arguments.bundleVersion ] ?: "";
		}
		if ( arguments.rawSearch && arguments.bundleName == "org.lucee.chart.extension" && arguments.bundleVersion == "2.0.0.1" ) {
			return variables.lexFile;
		}
		return "";
	}

	public array function getCalls() {
		return variables.calls;
	}

	public void function resetCalls() {
		variables.calls = [];
	}

	public void function setPublicUrls( required struct publicUrls ) {
		variables.publicUrls = arguments.publicUrls;
	}

}
