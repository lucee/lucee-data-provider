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
				var issues = _fetchIssues();
				_writeIssuesToS3( issues );
				setIssues( issues );
				variables._simpleCache = {};
				setLastUpdated( now() );
			}
		}
	}

	public function getChangelog( string versionFrom, string versionTo ) {
		_checkForUpdates(); // will update in the background if needed
		var cacheKey = "#arguments.versionFrom#-#arguments.versionTo#";
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
		var age = dateDiff( "n", getLastUpdated(), now() );

		// systemOutput(" _checkForUpdates() cache is #age# mins old ", true );
		if ( age < variables.getRefreshIntervalMins() ){
			return;
		}
		lock type="exclusive" name="refresh-issues" timeout=0 {
			setLastUpdated( now() );
			updateIssuesAsync();
		}
	}

	private function _getChangelog( string versionFrom, string versionTo ){
		var from	= VersionUtils::toVersionSortable( versionFrom );
		var to      = VersionUtils::toVersionSortable( versionTo );
		var issues  = duplicate( getIssues() );
		var sct     = structNew( "linked" );
		var sorted  = queryNew( "ver,sort" );

		loop query=issues {
			loop array=issues.fixVersions item="local.fv" {
				try{
					var fvs = VersionUtils::toVersionSortable( fv );
				} catch(e) {
					continue;
				}
				if ( fvs < from || fvs > to ) continue;
				if( !structKeyExists( sct, fv ) )
					sct[ fv ] = structNew( "linked" );
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
		systemOutput("-- start fetching issues from jira --- ", true);
		var jira = new services.legacy.Jira( getJiraServer() );
		var issues = jira.listIssues( project:"LDEV", stati: [ "Deployed", "Done", "QA" ] ).issues;
		systemOutput("-- finished fetching issues from jira --- ", true);
		return issues;
	}

	private function _readExistingIssuesFromS3() {
		var issues = getS3Root() & variables.cacheFile;
		if ( FileExists( issues ) ) {
			return DeserializeJson( FileRead( issues ), false );
		}
		return _getEmptyIssuesQuery();
	}

	private function _writeIssuesToS3( issues ) {
		var issuesFile = getS3Root() & variables.cacheFile;
		FileWrite( issuesFile, SerializeJson( issues ) );
	}

	private function _getEmptyIssuesQuery() {
		return QueryNew( "id,key,summary,self,type,created,updated,priority,status,fixVersions" );
	}

}