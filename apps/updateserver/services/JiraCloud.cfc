/**
 * A modern CFML component for interacting with the Jira Cloud REST API (v3).
 * This component uses API token-based authentication and handles pagination correctly.
 */
component {

	/**
	 * Constructor for the JiraCloud component.
	 *
	 * @param config A struct containing the Jira connection details.
	 * 		- domain: Your Jira domain (e.g., "your-company.atlassian.net").
	 * 		- email: The email address of the user for authentication.
	 * 		- apiToken: The API token generated from the user's Atlassian account.
	 */
	public function init(required struct config) {
		variables.config = arguments.config;

		// Validate required config keys
		var requiredKeys = ["domain"];
		for (var key in requiredKeys) {
			if (!structKeyExists(variables.config, key) || isEmpty(variables.config[key])) {
				throw(type="Jira.ConfigurationException", message="Missing required configuration key: #key#");
			}
		}

		// Setup auth token only if email and apiToken are provided
		if (structKeyExists(variables.config, "email") && !isEmpty(variables.config.email) &&
			structKeyExists(variables.config, "apiToken") && !isEmpty(variables.config.apiToken)) {
			variables.config.baseAuthToken = ToBase64(variables.config.email & ":" & variables.config.apiToken, "utf-8");
		} else {
			variables.config.baseAuthToken = "";
		}

		variables.config.baseUrl = "https://" & variables.config.domain & "/rest/api/3";

		return this;
	}

	/**
	 * Searches for issues using a JQL query.
	 * This method handles pagination automatically and returns a complete array of issues.
	 * Uses the new /search/jql endpoint (as of August 2025, /search is deprecated).
	 *
	 * @param jql The JQL query string.
	 * @param fields An array of fields to return for each issue. Defaults to a common set.
	 * @param maxResults The number of issues to return per page.
	 */
	public array function searchIssues(
		required string jql,
		array fields = ["summary", "status", "issuetype", "created", "updated", "priority", "fixVersions", "labels"],
		numeric maxResults = 1000
	) {
		var allIssues = [];
		var nextPageToken = "";
		var pageNum = 1;
		var maxPages = 50; // Safety limit to prevent infinite loops

		do {
			var body = {
				"jql" = arguments.jql,
				"fields" = arguments.fields,
				"maxResults" = arguments.maxResults
			};

			// Add nextPageToken for pagination if we have one
			if ( len( nextPageToken ) ) {
				body[ "nextPageToken" ] = nextPageToken;
			}

			// Make the request using the new /search/jql endpoint
			var result = _request( method="POST", path="/search/jql", body=body );

			// Add the fetched issues to our main array
			if ( isStruct( result ) && structKeyExists( result, "issues" ) && isArray( result.issues ) ) {
				arrayAppend( allIssues, result.issues, true );
			}

			// Check if we need to continue paging using nextPageToken
			nextPageToken = result.nextPageToken ?: "";
			pageNum++;

		} while ( len( nextPageToken ) && pageNum <= maxPages );

		return allIssues;
	}

	/**
	 * Private helper function to execute HTTP requests to the Jira API.
	 */
	private struct function _request(
		required string method,
		required string path,
		struct body = {}
	) {
		var fullUrl = variables.config.baseUrl & arguments.path;

		cfhttp( method=arguments.method, url=fullUrl, result="local.result", throwOnError=false ) {
			// Add Authorization header only if a token is available
			if ( len( variables.config.baseAuthToken ) ) {
				cfhttpparam( type="header", name="Authorization", value="Basic " & variables.config.baseAuthToken );
			}
			cfhttpparam( type="header", name="Accept", value="application/json" );

			if ( structCount( arguments.body ) ) {
				cfhttpparam( type="header", name="Content-Type", value="application/json" );
				cfhttpparam( type="body", value=serializeJson( arguments.body ) );
			}
		}

		if ( local.result.statusCode != "200 OK" ) {
			throw(
				type="HTTPException",
				message="#local.result.statusCode#",
				detail="#arguments.method# #fullUrl#" & chr( 10 ) & "Response: " & local.result.fileContent
			);
		}

		return deserializeJson( local.result.fileContent );
	}

}
