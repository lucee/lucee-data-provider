/**
 * An in-memory stand-in for services.GcsBundleCache (the bundle cache bucket), for the .lex fallback tests.
 */
component {

	function init( string prefix="provider/bundles/", string publicBaseUrl="" ) {
		variables.prefix        = arguments.prefix;
		variables.publicBaseUrl = arguments.publicBaseUrl;
		this.objects            = {};
		this.puts               = [];
		this.reads              = 0;
		return this;
	}

	public boolean function isEnabled() {
		return true;
	}

	public string function objectName( required string bundleName, required string bundleVersion ) {
		return variables.prefix & arguments.bundleName & "-" & arguments.bundleVersion & ".jar";
	}

	public string function publicUrl( required string bundleName, required string bundleVersion ) {
		return Len( variables.publicBaseUrl ) ? variables.publicBaseUrl & objectName( arguments.bundleName, arguments.bundleVersion ) : "";
	}

	public boolean function exists( required string bundleName, required string bundleVersion ) {
		return StructKeyExists( this.objects, objectName( arguments.bundleName, arguments.bundleVersion ) );
	}

	public boolean function put( required string bundleName, required string bundleVersion, required string file ) {
		var name = objectName( arguments.bundleName, arguments.bundleVersion );
		ArrayAppend( this.puts, name );
		// ifGenerationMatch=0: never overwrite
		if ( !StructKeyExists( this.objects, name ) ) {
			this.objects[ name ] = FileReadBinary( arguments.file );
		}
		return true;
	}

	public binary function read( required string bundleName, required string bundleVersion ) {
		this.reads++;
		return this.objects[ objectName( arguments.bundleName, arguments.bundleVersion ) ];
	}

}
