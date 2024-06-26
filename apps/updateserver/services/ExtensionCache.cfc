component accessors=true {

	property name="extensionCache"        type="any" default="cache/extensions/";

	function getExtensionLex( extensionUrl ){
		var filename = listLast( arguments.extensionUrl, "/");
		var cachedir =  expandPath( variables.extensionCache );

		if ( !directoryExists( cachedir ) ){
			directoryCreate( cachedir );
		} else if ( fileExists ( cachedir & filename )) {
			return cachedir & filename;
		}
		lock name="ext-#filename#" type="exclusive" timeout=10 {
			 return _fetchExtensionLex( cachedir, arguments.extensionUrl )
		}

		if ( fileExists ( cachedir & filename ) ) {
			return cachedir & filename;
		}
		throw "unable to find extension [#filename#]";
	}

	private function _fetchExtensionLex( string cachedir, string extensionUrl ){
		var filename = listLast( arguments.extensionUrl, "/");
		if ( fileExists ( cachedir & filename )) {
			return cachedir & filename;
		}
		systemOutput( "Downloading #arguments.extensionUrl# (cache miss)", true);
		http url=arguments.extensionUrl method="get" result="local.core" path=cachedir;
		var file = directoryList(path=cachedir, filter="#filename#");
		// systemOutput(file, true);
		return file[ 1 ];
	}

}