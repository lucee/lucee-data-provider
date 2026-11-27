/**
 * The real MavenMatcher, with one local folder as the only repository of the raw search (no network).
 */
component extends="services.legacy.MavenMatcher" {

	function init( required string repoDir ) {
		super.init( "" );
		variables.localRepo = ReReplace( arguments.repoDir, "[/\\]+$", "" );
		return this;
	}

	public array function rawSearchRepositories() {
		return [ variables.localRepo ];
	}

}
