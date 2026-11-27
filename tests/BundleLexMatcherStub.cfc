/**
 * MavenMatcher stand-in for the .lex fallback tests: no jar on any Maven repository, findLexUrls() answers the
 * given local .lex for the bundles in [names], and counts the calls.
 */
component {

	function init( required string lexFile, required array names ) {
		variables.lexFile = arguments.lexFile;
		variables.names   = arguments.names;
		this.lexLookups   = 0;
		return this;
	}

	public function findBundleUrl( required string bundleName, string bundleVersion="latest", boolean rawSearch=false ) {
		return "";
	}

	public array function findLexUrls( required string bundleName, required string bundleVersion ) {
		this.lexLookups++;
		return ArrayFind( variables.names, arguments.bundleName ) ? [ variables.lexFile ] : [];
	}

}
