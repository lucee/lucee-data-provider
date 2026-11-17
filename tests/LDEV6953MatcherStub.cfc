component {

	function init( required string lexFile ) {
		variables.lexFile = arguments.lexFile;
		return this;
	}

	public function findBundleUrl( required string bundleName, string bundleVersion="latest", boolean rawSearch=false ) {
		if ( arguments.rawSearch && arguments.bundleName == "org.lucee.chart.extension" && arguments.bundleVersion == "2.0.0.1" ) {
			return variables.lexFile;
		}
		return "";
	}

}
