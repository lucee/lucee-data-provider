component {

	function init( required string lexFile, required string artifact, required string version ) {
		variables.lexFile  = arguments.lexFile;
		variables.artifact = arguments.artifact;
		variables.version  = arguments.version;
		return this;
	}

	public boolean function hasRepos() {
		return true;
	}

	public struct function listExtensions() {
		return {
			  complete = true
			, files    = [ {
				  name     = GetFileFromPath( variables.lexFile )
				, artifact = variables.artifact
				, version  = variables.version
				, repos    = [ "https://example.invalid/" ]
			} ]
		};
	}

	public void function download( required string artifact, required string version, required array repos, required string target ) {
		FileCopy( variables.lexFile, arguments.target );
	}

}
