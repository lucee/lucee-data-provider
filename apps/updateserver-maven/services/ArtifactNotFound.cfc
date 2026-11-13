/**
 * One greppable WARN line when a requested artifact cannot be provided.
 * Written to the console (Cloud Run logging) and to the application log.
 *
 * Format (single line, space-separated key=value fields; ua is quoted):
 *   ARTIFACT_NOT_FOUND type=core path=/rest/update/provider/download/9.9.9.9 version=9.9.9.9 qualifier=lco id= ip=1.2.3.4 ua="Lucee (CFML)"
 *
 * Filter in Cloud Logging with: ARTIFACT_NOT_FOUND
 */
component {

	public static string function PREFIX() {
		return "ARTIFACT_NOT_FOUND";
	}

	/**
	 * Build the log line. Missing optional fields are left empty (key=).
	 */
	public static string function line(
		  required string type
		,          string path      = ""
		,          string id        = ""
		,          string version   = ""
		,          string qualifier = ""
		,          string ip        = ""
		,          string ua        = ""
	) {
		return PREFIX()
			& " type=#_clean( arguments.type )#"
			& " path=#_clean( arguments.path )#"
			& " id=#_clean( arguments.id )#"
			& " version=#_clean( arguments.version )#"
			& " qualifier=#_clean( arguments.qualifier )#"
			& " ip=#_clean( arguments.ip )#"
			& " ua=""#_clean( arguments.ua )#""";
	}

	/**
	 * Write the line at WARN. Path, IP and user-agent default to this request
	 * (cgi / X-Forwarded-For) when they are not passed.
	 */
	public static void function log(
		  required string type
		,          string path      = ""
		,          string id        = ""
		,          string version   = ""
		,          string qualifier = ""
		,          string ip        = ""
		,          string ua        = ""
	) {
		if ( !Len( arguments.path ) ) {
			arguments.path = _requestPath();
		}
		if ( !Len( arguments.ip ) ) {
			arguments.ip = _requestIp();
		}
		if ( !Len( arguments.ua ) ) {
			arguments.ua = Trim( cgi.http_user_agent ?: "" );
		}

		var msg = line( argumentCollection=arguments );

		SystemOutput( msg, true );
		WriteLog( text=msg, type="warn", log="application" );
	}

	public static string function requestPath() {
		return _requestPath();
	}

	public static string function requestIp() {
		return _requestIp();
	}

	private static string function _requestPath() {
		var script = Trim( cgi.script_name ?: "" );
		var info   = Trim( cgi.path_info ?: "" );
		var qs     = Trim( cgi.query_string ?: "" );
		var path   = script;

		if ( Len( info ) && !FindNoCase( info, script ) ) {
			path &= info;
		}
		if ( Len( qs ) ) {
			path &= "?" & qs;
		}

		return path;
	}

	private static string function _requestIp() {
		var forwarded = Trim( cgi.http_x_forwarded_for ?: "" );
		if ( Len( forwarded ) ) {
			return Trim( ListFirst( forwarded ) );
		}

		return Trim( cgi.remote_addr ?: "" );
	}

	private static string function _clean( required string value ) {
		// keep the line greppable: no quotes, newlines or extra spaces in values
		return ReReplace( Replace( Replace( arguments.value, """", "", "all" ), Chr( 10 ), " ", "all" ), "\s+", " ", "all" );
	}

}
