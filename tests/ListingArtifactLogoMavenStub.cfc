component {

	function init( required string fileName, required string artifact, required string version, required string group ) {
		variables.fileName = arguments.fileName;
		variables.artifact = arguments.artifact;
		variables.version  = arguments.version;
		variables.group    = arguments.group;
		return this;
	}

	public boolean function hasRepos() {
		return true;
	}

	public struct function listExtensions( boolean latestOnly=false ) {
		return {
			  complete = true
			, files    = [ {
				  name     = variables.fileName
				, artifact = variables.artifact
				, version  = variables.version
				, group    = variables.group
				, repos    = [ "https://example.invalid/" ]
			} ]
			, versions = {}
		};
	}

	public string function getGroup( required string artifact ) {
		return variables.group;
	}

	public void function saveState() {}

	public void function download( required string artifact, required string version, required array repos, required string target ) {
		throw( type="ListingArtifactLogoMavenStub", message="the lex file should not be downloaded again" );
	}

}
