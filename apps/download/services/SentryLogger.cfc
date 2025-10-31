/**
 * A CFML component for logging events and errors to Sentry.
 * Supports Sentry's Store API for sending events.
 */
component {

	/**
	 * Constructor for the SentryLogger component.
	 *
	 * @param config A struct containing the Sentry connection details.
	 * 		- dsn: Your Sentry DSN (e.g., "https://key@sentry.io/project-id").
	 * 		- environment: The environment name (e.g., "production", "staging", "development"). Defaults to "production".
	 * 		- release: Optional release identifier.
	 * 		- serverName: Optional server name. Defaults to cgi.server_name.
	 */
	public function init( required struct config ) {
		variables.config = arguments.config;

		// DSN is optional - if not provided or empty, logger will exercise all code paths but not send to Sentry
		// Strip quotes in case DSN comes through as literal '""' string from environment variables
		var cleanDsn = trim( replace( variables.config.dsn ?: "", '""', '', 'all' ) );
		if ( len( cleanDsn ) && cleanDsn neq '""' ) {
			// Parse the DSN
			variables.sentryInfo = _parseDsn( cleanDsn );
			variables.hasDsn = true;
		} else {
			variables.hasDsn = false;
		}

		// Set defaults
		if ( !structKeyExists( variables.config, "environment" ) || isEmpty( variables.config.environment ) ) {
			variables.config.environment = "production";
		}

		if ( !structKeyExists( variables.config, "serverName" ) || isEmpty( variables.config.serverName ) ) {
			variables.config.serverName = cgi.server_name ?: "unknown";
		}

		return this;
	}

	/**
	 * Logs a message to Sentry.
	 *
	 * @param message The message to log.
	 * @param level The severity level: "debug", "info", "warning", "error", "fatal". Defaults to "info".
	 * @param extra Additional context data to send with the event.
	 * @param tags Tags to categorize the event.
	 * @param user User information (id, email, username, ip_address).
	 */
	public struct function logMessage(
		required string message,
		string level = "info",
		struct extra = {},
		struct tags = {},
		struct user = {}
	) {
		var event = _buildEvent(
			message = arguments.message,
			level = arguments.level,
			extra = arguments.extra,
			tags = arguments.tags,
			user = arguments.user
		);

		return _sendEvent( event );
	}

	/**
	 * Logs an exception to Sentry.
	 *
	 * @param exception The exception object (cfcatch).
	 * @param level The severity level. Defaults to "error".
	 * @param extra Additional context data to send with the event.
	 * @param tags Tags to categorize the event.
	 * @param user User information.
	 */
	public struct function logException(
		required any exception,
		string level = "error",
		struct extra = {},
		struct tags = {},
		struct user = {}
	) {
		// Handle simple values (string, number, etc) passed as exception
		var exceptionMessage = "Unknown error";
		var exceptionType = "Error";
		var exceptionStruct = arguments.exception;

		if ( !isStruct( arguments.exception ) ) {
			// Simple value passed - convert to string
			exceptionMessage = toString( arguments.exception );
			exceptionStruct = {};
		} else {
			exceptionMessage = arguments.exception.message ?: toString( arguments.exception );
			exceptionType = arguments.exception.type ?: "Error";
		}

		// Use custom logText as the main message if provided, otherwise use exception message
		var displayMessage = exceptionMessage;
		if ( structKeyExists( arguments.extra, "logText" ) && len( arguments.extra.logText ) ) {
			displayMessage = arguments.extra.logText;
			// Keep the original exception message in extra context
			arguments.extra[ "exceptionMessage" ] = exceptionMessage;
		}

		var event = _buildEvent(
			message = displayMessage,
			level = arguments.level,
			extra = arguments.extra,
			tags = arguments.tags,
			user = arguments.user
		);

		// Add exception details
		event[ "exception" ] = {
			"values" = [
				{
					"type" = exceptionType,
					"value" = exceptionMessage,
					"stacktrace" = _parseStackTrace( exceptionStruct )
				}
			]
		};

		// Add additional exception context if it's a proper exception struct
		if ( isStruct( arguments.exception ) ) {
			if ( structKeyExists( arguments.exception, "detail" ) && len( arguments.exception.detail ) ) {
				event.extra[ "detail" ] = arguments.exception.detail;
			}

			if ( structKeyExists( arguments.exception, "extendedInfo" ) && len( arguments.exception.extendedInfo ) ) {
				event.extra[ "extendedInfo" ] = arguments.exception.extendedInfo;
			}
		}

		return _sendEvent( event );
	}

	/**
	 * Builds a base event structure for Sentry.
	 */
	private struct function _buildEvent(
		required string message,
		required string level,
		required struct extra,
		required struct tags,
		required struct user
	) {
		var event = {
			"event_id" = lCase( replace( createUUID(), "-", "", "all" ) ),
			"timestamp" = _getIsoTimestamp(),
			"level" = _normalizeSentryLevel( arguments.level ),
			"message" = arguments.message,
			"platform" = "cfml",
			"environment" = variables.config.environment,
			"server_name" = variables.config.serverName,
			"extra" = arguments.extra,
			"tags" = arguments.tags
		};

		// Add release if configured
		if ( structKeyExists( variables.config, "release" ) && len( variables.config.release ) ) {
			event[ "release" ] = variables.config.release;
		}

		// Add user context if provided
		if ( structCount( arguments.user ) ) {
			event[ "user" ] = arguments.user;
		}

		// Add request context
		event[ "request" ] = _getRequestContext();

		// Add server context
		event[ "contexts" ] = _getServerContext();

		return event;
	}

	/**
	 * Sends an event to Sentry via HTTP.
	 */
	private struct function _sendEvent( required struct event ) {
		// If no DSN configured, skip the HTTP call but return success
		// This allows full code path testing in dev without sending to Sentry
		if ( !variables.hasDsn ) {
			return {
				"success" = true,
				"eventId" = arguments.event.event_id,
				"statusCode" = "200",
				"note" = "No DSN configured - event not sent to Sentry"
			};
		}

		var fullUrl = variables.sentryInfo.apiUrl;
		var timestamp = _getTimestamp();

		try {
			cfhttp( method="POST", url=fullUrl, result="local.result", throwOnError=false, timeout=5 ) {
				cfhttpparam( type="header", name="Content-Type", value="application/json" );
				cfhttpparam( type="header", name="X-Sentry-Auth", value=_buildAuthHeader( timestamp ) );
				cfhttpparam( type="body", value=serializeJson( arguments.event ) );
			}

			if ( !find( "200", local.result.statusCode ) ) {
				throw(
					type = "Sentry.HTTPException",
					message = "Sentry API returned status: #local.result.statusCode#",
					detail = "Response: " & local.result.fileContent
				);
			}

			return {
				"success" = true,
				"eventId" = arguments.event.event_id,
				"statusCode" = local.result.statusCode
			};

		} catch ( any e ) {
			// Don't let logging failures break the application
			// You could log this to a file or dump it
			return {
				"success" = false,
				"error" = e.message,
				"detail" = e.detail ?: ""
			};
		}
	}

	/**
	 * Parses a Sentry DSN into its components.
	 */
	private struct function _parseDsn( required string dsn ) {
		// DSN format: https://{publicKey}@{host}/{projectId}
		var pattern = "^(https?)://([^@]+)@([^/]+)/(.+)$";
		var matches = reFind( pattern, arguments.dsn, 1, true );

		if ( !matches.pos[ 1 ] ) {
			throw( type="Sentry.ConfigurationException", message="Invalid DSN format" );
		}

		var protocol = mid( arguments.dsn, matches.pos[ 2 ], matches.len[ 2 ] );
		var publicKey = mid( arguments.dsn, matches.pos[ 3 ], matches.len[ 3 ] );
		var host = mid( arguments.dsn, matches.pos[ 4 ], matches.len[ 4 ] );
		var projectId = mid( arguments.dsn, matches.pos[ 5 ], matches.len[ 5 ] );

		return {
			"protocol" = protocol,
			"publicKey" = publicKey,
			"host" = host,
			"projectId" = projectId,
			"apiUrl" = "#protocol#://#host#/api/#projectId#/store/"
		};
	}

	/**
	 * Builds the Sentry auth header.
	 */
	private string function _buildAuthHeader( required numeric timestamp ) {
		var parts = [
			"Sentry sentry_version=7",
			"sentry_client=cfml-sentry/1.0",
			"sentry_timestamp=#arguments.timestamp#",
			"sentry_key=#variables.sentryInfo.publicKey#"
		];

		return arrayToList( parts, ", " );
	}

	/**
	 * Gets the current timestamp in seconds.
	 */
	private numeric function _getTimestamp() {
		return fix( getTickCount() / 1000 );
	}

	/**
	 * Gets the current timestamp in ISO 8601 format.
	 */
	private string function _getIsoTimestamp() {
		return dateTimeFormat( now(), "iso8601" );
	}

	/**
	 * Extracts request context from CGI scope.
	 */
	private struct function _getRequestContext() {
		var context = {
			"url" = cgi.server_name & cgi.script_name,
			"method" = cgi.request_method,
			"query_string" = cgi.query_string,
			"headers" = {}
		};

		// Add common headers including user agent
		var headerKeys = [ "user-agent", "referer", "content-type" ];
		for ( var key in headerKeys ) {
			var cgiKey = "http_" & replace( key, "-", "_", "all" );
			if ( structKeyExists( cgi, cgiKey ) ) {
				context.headers[ key ] = cgi[ cgiKey ];
			}
		}

		return context;
	}

	/**
	 * Gets server context including Lucee and Java versions.
	 */
	private struct function _getServerContext() {
		var contexts = {
			"runtime" = {
				"name" = "Lucee",
				"version" = server.lucee.version ?: "unknown"
			},
			"os" = {
				"name" = server.os.name ?: "unknown",
				"version" = server.os.version ?: "unknown"
			}
		};

		// Add Java version
		if ( structKeyExists( server, "java" ) && structKeyExists( server.java, "version" ) ) {
			contexts[ "runtime" ][ "java_version" ] = server.java.version;
		}

		return contexts;
	}

	/**
	 * Parses CFML exception stack trace into Sentry format.
	 */
	private struct function _parseStackTrace( required any exception ) {
		var frames = [];

		if ( structKeyExists( arguments.exception, "tagContext" ) && isArray( arguments.exception.tagContext ) ) {
			for ( var frame in arguments.exception.tagContext ) {
				arrayAppend( frames, {
					"filename" = frame.template ?: "",
					"lineno" = frame.line ?: 0,
					"function" = frame.id ?: "",
					"in_app" = true
				} );
			}
		}

		return {
			"frames" = frames
		};
	}

	/**
	 * Normalizes level names to match Sentry's expected format.
	 * Handles common variations like "warn" -> "warning", "ERROR" -> "error", etc.
	 */
	private string function _normalizeSentryLevel( required string level ) {
		var normalized = lCase( trim( arguments.level ) );

		// Map common variations to Sentry levels
		switch ( normalized ) {
			case "warn":
				return "warning";
			case "fatal":
			case "critical":
				return "fatal";
			case "err":
				return "error";
			default:
				// Return as-is for: debug, info, warning, error, fatal
				return normalized;
		}
	}

}
