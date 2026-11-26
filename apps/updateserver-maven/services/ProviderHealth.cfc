/**
 * How long the provider services have been failing to load, shared between
 * the main application and /healthcheck/ (a separate application) through the
 * server scope.
 *
 * /healthcheck/ only answers 503 once the services have been failing for
 * HEALTH_FAIL_AFTER_SECONDS (default 300, 0 disables it), so a container that
 * cannot recover by itself is replaced by the platform (a liveness probe on
 * /healthcheck/). It never fails while the first load is still running: that
 * is not a failure, and the clock only starts with a failed load.
 */
component {

	static {
		static.KEY       = "luceeProviderMavenFailingSince";
		static.READY_KEY = "luceeProviderMavenReady";
	}

	/**
	 * The services are loaded and requests can be served. Read by /ready/ (the startup probe), which is a separate
	 * application, so this is kept in the server scope too.
	 */
	public static void function markReady() {
		server[ static.READY_KEY ] = true;
	}

	public static boolean function isReady() {
		var ready = server[ static.READY_KEY ] ?: false;

		return IsBoolean( ready ) && ready;
	}

	// first failed load since the services were last ready, the time is kept across retries
	public static void function markFailing( numeric nowMs=GetTickCount() ) {
		if ( Val( server[ static.KEY ] ?: 0 ) <= 0 ) {
			server[ static.KEY ] = arguments.nowMs;
		}
	}

	public static void function markHealthy() {
		if ( Val( server[ static.KEY ] ?: 0 ) > 0 ) {
			server[ static.KEY ] = 0;
		}
	}

	public static numeric function failingSince() {
		return Val( server[ static.KEY ] ?: 0 );
	}

	public static numeric function thresholdSeconds() {
		var value = Trim( server.system.environment.HEALTH_FAIL_AFTER_SECONDS ?: "" );

		return IsNumeric( value ) && value >= 0 ? Int( value ) : 300;
	}

	/**
	 * @since            override for tests, defaults to failingSince()
	 * @thresholdSeconds override for tests, defaults to thresholdSeconds()
	 */
	public static boolean function isUnhealthy( numeric since, numeric thresholdSeconds, numeric nowMs=GetTickCount() ) {
		var s = StructKeyExists( arguments, "since" ) ? arguments.since : failingSince();
		var t = StructKeyExists( arguments, "thresholdSeconds" ) ? arguments.thresholdSeconds : thresholdSeconds();

		return t > 0 && s > 0 && ( arguments.nowMs - s ) >= t * 1000;
	}

}
