/**
 * A service to encapsulate the manied logic
 * of bundle discovery for bundle download
 */
component accessors=true {

	property name="s3root" type="string" default="";

	variables._cache = {};


	/**
	 * Attempt to locate an osgi bundle file
	 * by looking up various locations, including
	 * an S3 backed up local cache
	 */
	public struct function findBundle( required string bundleName, required string bundleVersion ) {

	}

}