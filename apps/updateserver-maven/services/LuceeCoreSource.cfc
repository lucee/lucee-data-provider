/**
 * Core versions for the Maven-only update provider, from Lucee 8's
 * LuceeVersionsList() / LuceeVersionsDetail(), cached in the shared
 * download8 cache (see LuceeCatalog). Implements the same methods
 * CoreVersions expects of MavenCoreSource: hasRepos, hasType, getTypes,
 * listVersions, getCoreFileName, getCoreFileUrl.
 */
component {

	function init( any catalog, string mixedRepo="https://maven.lucee-services.com/" ) {
		variables.catalog   = arguments.catalog ?: new services.LuceeCatalog();
		variables.mixedRepo = Right( arguments.mixedRepo, 1 ) == "/" ? arguments.mixedRepo : arguments.mixedRepo & "/";
		variables._types    = {
			  jar     : { classifier="",        extension="jar" }
			, light   : { classifier="light",   extension="jar" }
			, zero    : { classifier="zero",    extension="jar" }
			, lco     : { classifier="",        extension="lco" }
			, war     : { classifier="",        extension="war" }
			, express : { classifier="express", extension="zip" }
		};

		return this;
	}

	public boolean function hasRepos() {
		return true;
	}

	public boolean function hasType( required string type ) {
		return StructKeyExists( variables._types, arguments.type );
	}

	public array function getTypes() {
		return StructKeyArray( variables._types );
	}

	/**
	 * { versions={ version=[ "lucee-versions" ] }, complete=boolean }
	 */
	public struct function listVersions() {
		var list   = variables.catalog.getVersionList();
		var result = { versions={}, complete=!ArrayIsEmpty( list ) };

		for ( var version in list ) {
			result.versions[ version ] = [ "lucee-versions" ];
		}

		return result;
	}

	public string function getCoreFileName( required string type, required string version, required string repo ) {
		if ( !hasType( arguments.type ) ) {
			return "";
		}
		var spec = variables._types[ arguments.type ];

		return "lucee-" & arguments.version & ( Len( spec.classifier ) ? "-" & spec.classifier : "" ) & "." & spec.extension;
	}

	/**
	 * URL of a distribution file. Prefer LuceeVersionsDetail() (shared cache),
	 * otherwise the deterministic Maven layout on the mixed Lucee repository.
	 */
	public string function getCoreFileUrl( required string type, required string version, required array repos ) {
		if ( !hasType( arguments.type ) ) {
			return "";
		}

		var detail = variables.catalog.getVersionDetail( arguments.version );
		if ( StructKeyExists( detail, arguments.type ) && Len( detail[ arguments.type ] ) && IsSimpleValue( detail[ arguments.type ] ) ) {
			return detail[ arguments.type ];
		}

		// LuceeVersionsDetail often only has jar / lco / pom; the other
		// classifiers live in the Maven layout under the same version folder.
		return variables.mixedRepo & "org/lucee/lucee/" & arguments.version & "/" & getCoreFileName( arguments.type, arguments.version, "" );
	}

}
