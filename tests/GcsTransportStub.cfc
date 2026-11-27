/**
 * Records the requests of services.GcsBundleCache and answers them from [answers]: an array of
 * { match (regex on "METHOD url"), status, body }, the first match wins. The metadata token is always answered.
 */
component {

	function init( array answers=[] ) {
		variables.answers = arguments.answers;
		this.requests     = [];
		return this;
	}

	public struct function send( required string method, required string url, struct headers={}, any body="", boolean binary=false ) {
		ArrayAppend( this.requests, { method=arguments.method, url=arguments.url, headers=arguments.headers, body=arguments.body } );
		if ( FindNoCase( "metadata.google.internal", arguments.url ) ) {
			return { status=200, body='{"access_token":"tok","expires_in":3599,"token_type":"Bearer"}' };
		}
		for ( var a in variables.answers ) {
			if ( ReFindNoCase( a.match, arguments.method & " " & arguments.url ) ) {
				return { status=a.status, body=a.body ?: "" };
			}
		}
		return { status=404, body="" };
	}

	public numeric function count( string match=".*" ) {
		var n = 0;
		for ( var r in this.requests ) {
			if ( ReFindNoCase( arguments.match, r.method & " " & r.url ) ) n++;
		}
		return n;
	}

}
