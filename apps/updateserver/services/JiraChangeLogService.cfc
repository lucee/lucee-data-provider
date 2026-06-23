component accessors=true {

	property name="s3root"                type="string"     default="";
	property name="issues"                type="query";
	property name="lastUpdated"           type="date";
	property name="refreshIntervalMins"   type="numeric"    default=15;
	property name="jiraServer"            type="string"     default="luceeserver.atlassian.net";

	variables._simpleCache = {};
	variables.cacheFile = "/issues.json";

	function loadIssues( boolean force=false ) {
		lock type="exclusive" name="readIssues" timeout=0 {
			setLastUpdated( now() );
			var issues = _readExistingIssuesFromS3();
			if ( !issues.recordcount || arguments.force ){
				setIssues( issues ); // in case there's a problem, let's ensure there's data
				issues = _fetchIssues();
				_writeIssuesToS3( issues );
			}
			setIssues( issues );
		}
	}

	public function updateIssuesAsync() {
		thread name="fetch-issues-#createUUID()#" {
			lock type="exclusive" name="fetch-issues-async" timeout=0 {
				systemOutput("updateIssuesAsync()", true );
				var issues = _fetchIssues();
				_writeIssuesToS3( issues );
				setIssues( issues );
				variables._simpleCache = {};
				setLastUpdated( now() );
			}
		}
	}

	public function getChangeLogUpdated(){
		return getLastUpdated();
	}

	public function getChangelog( string versionFrom, string versionTo, detailed=false ) {
		_checkForUpdates(); // will update in the background if needed
		var cacheKey = "#arguments.versionFrom#-#arguments.versionTo#-#arguments.detailed#";
		if ( structKeyExists( variables._simpleCache, cacheKey ) ){
			try {
				return variables._simpleCache[ cacheKey ];
			} catch ( e ) {
				// race with an update, regenerate
			}
		}
		lock type="exclusive" name="generateChangeLog-#cacheKey#" timeout=5 {
			var changelog = _getChangelog( argumentCollection=arguments );
			variables._simpleCache[ cacheKey ] = changelog;
			return changelog;
		}
		return variables._simpleCache[ cacheKey ];
	}

// PRIVATE HELPERS

	private function _checkForUpdates() {
		if ( !isNull( getLastUpdated() ) ){
			var age = dateDiff( "n", getLastUpdated(), now() );

			//systemOutput("jira._checkForUpdates() cache is #age# mins old, max is #getRefreshIntervalMins()#", true );
			if ( age < variables.getRefreshIntervalMins() ){
				return;
			}
		}
		lock type="exclusive" name="refresh-issues" timeout=0 {
			setLastUpdated( now() );
			updateIssuesAsync();
		}
	}

	private function _getChangelog( string versionFrom, string versionTo, detailed=false ){
		var from	= VersionUtils::toVersionSortable( versionFrom );
		var to      = VersionUtils::toVersionSortable( versionTo );
		var issues  = duplicate( getIssues( arguments.detailed ) );
		var sct     = structNew( "linked" );
		var sorted  = queryNew( "ver,sort" );

		loop query=issues {
			loop array=issues.fixVersions item="local.fv" {
				try{
					var fvs = VersionUtils::toVersionSortable( fv );
				} catch(e) {
					continue;
				}
				if ( fvs <= from || fvs > to ) continue;
				if( !structKeyExists( sct, fv ) )
					sct[ fv ] = structNew( "linked" );
				if (arguments.detailed)
					sct[ fv ][ issues.key ] = queryRowData( issues, issues.currentRow );
				else
					sct[ fv ][ issues.key ]= issues.summary;
				var row = queryAddRow( sorted );
				querySetCell( sorted, "ver", fv, row );
				querySetCell( sorted, "sort", fvs, row );
			}
		}
		QuerySort( sorted, 'sort', 'desc' );
		var result = structNew("linked" );
		loop query=sorted {
			result[ sorted.ver ] = sct[ sorted.ver ];
		}
		return result;
	}

	private function _fetchIssues() {
		systemOutput( "[#dateTimeFormat(now(), "long")#] -- start fetching issues from jira --- ", true);
		var jira = new services.JiraCloud({ domain: getJiraServer() });
		var issuesArray = jira.searchIssues(jql="project=LDEV AND status in (Deployed, Done, QA, Resolved)");
		var issuesQuery = _issuesArrayToQuery(issuesArray);
		systemOutput( "[#dateTimeFormat(now(), "long")#] -- finished fetching issues from jira --- ", true);
		return issuesQuery;
	}

	private query function _issuesArrayToQuery(required array issues) {
		var qry = _getEmptyIssuesQuery();

		loop array=arguments.issues item="issue" {
			queryAddRow( qry );
			querySetCell( qry, "id", issue.id );
			querySetCell( qry, "key", issue.key );
			querySetCell( qry, "summary", issue.fields.summary ?: "" );
			querySetCell( qry, "self", issue.self );
			querySetCell( qry, "type", issue.fields.issuetype.name ?: "" );
			querySetCell( qry, "created", len( issue.fields.created ?: "" ) ? parseDateTime( issue.fields.created ) : "" );
			querySetCell( qry, "updated", len( issue.fields.updated ?: "" ) ? parseDateTime( issue.fields.updated ) : "" );
			querySetCell( qry, "priority", issue.fields.priority.name ?: "" );
			querySetCell( qry, "status", issue.fields.status.name ?: "" );
			
			var fixVersions = [];
			if (isArray(issue.fields.fixVersions)) {
				loop array=issue.fields.fixVersions item="fv" {
					arrayAppend(fixVersions, fv.name);
				}
			}
			querySetCell(qry, "fixVersions", fixVersions);
			querySetCell(qry, "labels", issue.fields.labels ?: []);
		}

		return qry;
	}

	private function _readExistingIssuesFromS3() {
		var issues = getS3Root() & variables.cacheFile;
		if ( FileExists( issues ) ) {
			systemOutput("jira._readExistingIssuesFromS3", true);
			return DeserializeJson( FileRead( issues ), false );
		} else {
			systemOutput("jira._readExistingIssuesFromS3 - no existing issues file [#issues#]", true);
		}
		return _getEmptyIssuesQuery();
	}

	private function _writeIssuesToS3( issues ) {
		var issuesFile = getS3Root() & variables.cacheFile;
		FileWrite( issuesFile, SerializeJson( issues ) );
	}

	private function _getEmptyIssuesQuery() {
		return QueryNew( "id,key,summary,self,type,created,updated,priority,status,fixVersions,labels" );
	}

}