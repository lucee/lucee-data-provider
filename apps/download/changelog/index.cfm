<cfscript>
	stMajorVersion = {
		"4.5": false,
		"5.0": false,
		"5.1": false,
		"5.2": false,
		"5.3": false,
		"5.4": "LTS",
		"6.0": true,
		"6.1": true,
		"6.2": true,
		"7.0": true,
		"7.1": true
	}; // todo pull this out of known verions
	defaultMajorVersion = "7.0";
	param name="url.version" default="";
	if ( !structKeyExists( stMajorVersion, url.version ) ){
		if (structKeyExists( stMajorVersion, left( url.version, 3 ) ) )
			location url="?version=#left( url.version, 3 )#" addtoken=false;
		else
			location url="?version=#defaultMajorVersion#" addtoken=false;
	}

	if ( structKeyExists( application, "changeLogReport" )
			&& structKeyExists( application.changelogReport, url.version )){
		echo( application.changelogReport[ url.version ] );
		abort;
	} else if (structKeyExists( application, "changeLogReportOld")
			&& structKeyExists( application.changelogReportOld, url.version )){
		// changelog is being updated!
		echo( application.changelogReportOld[ url.version ] );
		abort;
	}
</cfscript>
<!---
<script>
	$( document ).ready(function() {
		$(".issue-type").onClick(function(el){
			console.log(el);
		});
	});
</script>
--->
<cflock type="exclusive" name="changelogReport-#url.version#" timeout=1 throwontimeout="false">
	<cfsilent>
	<cfscript>
		buildStarted = getTickCount();
		systemOutput("building changelog for #url.version#, please wait......", true);
		download=CreateObject("component", "download");
		versions = download.getVersions( structKeyExists( url, "reset" ) );
		if ( structKeyExists( url, "reset" ) ){
			systemOutput("url.reset=true clearing caches", true);
			application.jiraChangeLog = {};
			application.mavenInfo = {};
			//application.mavenDates = {};
		}
		keys=structKeyArray(versions);
		tmp=structNew('linked');
		for(i=arrayLen(keys);i>0;i--) {
			k=keys[i];
			//if(left(k,6)=="06.001" && right(k,4)==".000") continue; // .000=SNAPSHOT
			tmp[k]=versions[k];
		}
		versions=tmp;

		// Use changelog.cfc to process versions
		changelogService = CreateObject( "component", "changelog" ).init( download );
		processedVersions = changelogService.processVersions( versions );
		major = processedVersions.major;

		arrVersions = changelogService.getSortedVersions( major );

		// Build changelog data array using the new method
		arrChangeLogs = changelogService.buildChangelogData( major, arrVersions, url.version );

		function getBadgeForType( type ) {
			switch(arguments.type){
				case "bug":
					return "danger";
				case "enhancement":
					return "success";
			}
			return "info";
		}

		//ticketTypes={};
		//ticketLabels={};
	</cfscript>
	</cfsilent>
	<cfsavecontent variable="changelog_report">
		<cfoutput>
			<!DOCTYPE html>
			<html>
			<head>
				<title>Lucee Server Changelogs - #url.version#</title>
				<cfinclude template="../_header.cfm">
			</head>
			<body class="container py-3">
				<div class="bg-primary jumbotron text-white">
					<cfinclude template="../_linkbar.cfm">
					<h2 class="display-3">Lucee Server Changelogs - #url.version#</h2>
				</div>
				<cfset lastMajor = "">
				<div class="versionList">
					<cfloop array="#arrChangeLogs#" item="luceeVersion">
						<cfif lastMajor neq left(luceeVersion.version, 3) and luceeVersion.type neq "snapshots" and (structcount(luceeVersion.changelog) or luceeVersion.type eq "releases" or luceeVersion.type eq "rc")>
							<cfif len(lastMajor) eq 0>
								Lucee Releases:
							</cfif>
							<cfset lastMajor = left(LuceeVersion.version, 3)>
							<b><a href="?version=#left(luceeVersion.version,3)#"
								data-version="#left(LuceeVersion.version, 3)#"
								data-status="#stMajorVersion[left(LuceeVersion.version, 3)] ?: 'Active'#"
								title="View all #left(LuceeVersion.version, 3)# releases - Status: #stMajorVersion[left(LuceeVersion.version, 3)] ?: 'Active'#">#left(LuceeVersion.version, 3)#</a>&nbsp;</b>&nbsp;
							<!--- Only show detailed versions for 5.4 and above --->
							<cfif val( left( luceeVersion.version, 3 ) ) gte 5.4>
								<a href="?version=#left(luceeVersion.version,3)####luceeVersion.version#"
									data-version="#luceeVersion.version#"
									data-type="#luceeVersion.type#"
									data-release-date="#luceeVersion.versionReleaseDate#"
									data-git-tag="https://github.com/lucee/Lucee/tree/#listFirst(luceeVersion.version, '-')#"
									title="View changelog for #luceeVersion.version# - Type: #luceeVersion.type# - Released: #luceeVersion.versionReleaseDate#"
									>#luceeVersion.version#</a>&nbsp;
							<cfelse>
								&nbsp;
							</cfif>
						</cfif>
					</cfloop>
				</div>
				<cfif stMajorVersion[ url.version ] eq "false">
					<div class="alert alert-danger mt-2 lead" role="alert">
						<h4>
							<span class="glyphicon glyphicon-warning-sign mr-2"></span>
							This Lucee Release is EOL (End of life) and no longer supported, please upgrade to a supported release.
						</h4>
					</div>
				<cfelseif stMajorVersion[ url.version ] eq "LTS">
					<div class="alert alert-warning mt-2 lead" role="alert">
						<h4>
							<span class="glyphicon glyphicon-warning-sign mr-2"></span>
							This Lucee Release is now LTS and is only receiving security updates.
						</h4>
					</div>
				</cfif>
				<!---
				<cfset delim="">
				<div class="versionList issue-types">
					Issue Types:
					<cfloop collection=#ticketTypes# item="type">
						#delim# <span class="issue-label" data-type="#encodeForHtmlAttribute(type)#"> #type# (#ticketTypes[type]#)</span>
						<cfset delim=",">
					</cfloop>
				</div>
				<cfset delim="">
				<div class="versionList">
					Issue Labels:
					<cfloop collection=#ticketLabels# item="label">
						#delim# <span class="issue-label" data-label="#encodeForHtmlAttribute(label)#">#encodeForHtml(label)# (#ticketLabels[label]#)</span>
						<cfset delim="">
					</cfloop>
				</div>

				--->
				<cfset row=0>
				<hr>
				<table cellSpacing=0 border=0 cellPadding=2 width="100%" class="changelogs table-striped">
					<cfloop array="#arrChangeLogs#" item="lv">
						<cfif (structcount(lv.changelog) or lv.type eq "releases" or lv.type eq "rc") and left(lv.version,3) eq url.version>
							<cfif row neq 0>
								<tr>
									<td colspan="4"><hr></td>
								</tr>
							</cfif>
							<cfset row=1>
							<tr>
								<td colspan="4">
								<#lv.header# class="modal-title" id="#lv.version#">
									<b><a href="?version=#left(lv.version,3)####lv.version#"
										data-version="#lv.version#"
										data-type="#lv.type#"
										data-release-date="#lv.versionReleaseDate#"
										data-status="#stMajorVersion[left(lv.version,3)] ?: 'Active'#"
										data-git-tag="https://github.com/lucee/Lucee/tree/#listFirst(lv.version, '-')#"
										title="Lucee #lv.version# Details - Type: #uCase(left(lv.type,1)) & right(lv.type, len(lv.type)-1)# - Released: #lv.versionReleaseDate# - Status: #stMajorVersion[left(lv.version,3)] ?: 'Active'#">Lucee #lv.versionTitle#</a></b>
									<cfif lv.type eq "releases">
										<span class="badge badge-success ml-1" title="Production Ready">STABLE</span>
									<cfelseif lv.type eq "rc">
										<span class="badge badge-warning ml-1" title="Release Candidate - Pre-release">RC</span>
									<cfelseif lv.type eq "beta">
										<span class="badge badge-info ml-1" title="Beta Version - Testing">BETA</span>
									<cfelseif lv.type eq "snapshots">
										<span class="badge badge-secondary ml-1" title="Development Build - Not for Production">SNAPSHOT</span>
									<cfelseif lv.type eq "alpha">
										<span class="badge badge-dark ml-1" title="Alpha Version - Early Testing">ALPHA</span>
									</cfif>
									<small>
										<time class="mr-2" datetime="#lv.versionReleaseDate#" data-release-date="#lv.versionReleaseDate#">#lv.versionReleaseDate#</time>
										<a href="../?#lv.type#=#lv._version###core" title="Jump to Downloads for #lv.version#"><span class="glyphicon glyphicon-download-alt"></span></a>
									</small>
								</#lv.header#>
								</td>
							</tr>
							<cfset changelogTicketList = {}>
							<cfset sortedVersionKeys = changelogService.getSortedChangelogVersions( lv.changelog, url.version )>
							<cfloop array="#sortedVersionKeys#" index="ver">
								<cfset tickets = lv.changelog[ ver ]>
								<cfloop struct="#tickets#" index="id" item="ticket">
									<cfif !StructKeyExists(changelogTicketList, ticket.id)>
										<tr valign="top" 
											data-ticket-id="#id#" 
											data-ticket-type="#ticket.type#" 
											data-fix-versions="#arrayToList(ticket.fixVersions, ',')#"
											<cfif len(ticket.labels)>data-labels="#arrayToList(ticket.labels, ',')#"</cfif>>
											<td nowrap><a href="https://bugs.lucee.org/browse/#id#" target="blank" class="mr-1" 
												data-ticket-id="#id#"
												title="View #ticket.type# ticket #id# on JIRA">#id#</a></td>
											<td><span class="label label-#getBadgeForType(ticket.type)# mr-1" 
												data-ticket-type="#ticket.type#"
												title="#ticket.type# - #ticket.summary#">#ticket.type#</span></td>
											<td>#encodeForHtml(wrap(ticket.summary,70))#
											<cfif len(ticket.labels)>
												<br>
												<div class="ticket-labels">
													<cfloop array="#ticket.labels#" item="label">
														<span class="label label-default">#encodeForHtml(label)#</span>
													</cfloop>
												</div>
											</cfif>
											</td>
											<td style="max-width:250px;" data-fix-versions="#encodeForHtmlAttribute(arrayToList(ticket.fixVersions, ', '))#"
												title="Fixed in versions: #arrayToList(ticket.fixVersions, ', ')#">
												<cfloop array="#ticket.fixVersions#" item="fixVersion" index="i">
													<span data-git-tag="https://github.com/lucee/Lucee/tree/#listFirst(fixVersion, '-')#">#fixVersion#</span><cfif i lt arrayLen(ticket.fixVersions)>, </cfif>
												</cfloop>
											</td>
										</tr>
										<cfset changelogTicketList[ticket.id] = true>
									</cfif>
								</cfloop>
							</cfloop>
						</cfif>
					</cfloop>
				</table>
				<hr>
				<p><em>Last Updated: #lsDateTimeFormat(now())#</em></p>
			</body>
			</html>
		</cfoutput>
	</cfsavecontent>
	<cfscript>
		systemOutput("Changelog for [#url.version#] built in #numberFormat(getTickCount()-buildStarted)#ms", true);
		if ( !structKeyExists( application, "changeLogReport" ) )
			application.changeLogReport = {};
		// cleanup excessive whitespace while preserving readability
		changelog_report = rereplace( changelog_report, "\t+", "", "all" );
		changelog_report = rereplace( changelog_report, " {2,}", " ", "all" );
		changelog_report = rereplace( changelog_report, "\n\s+", chr(10), "all" );
		application.changeLogReport[ url.version ] = changelog_report;
		if ( structKeyExists(application, "changeLogReportOld" ) )
			structDelete( application[ "changeLogReportOld" ], url.version );
		echo( changelog_report );
		abort;
	</cfscript>
</cflock>
<cfscript>
	if ( structKeyExists(application, "changeLogReport")
			&& structKeyExists(application.changelogReport, url.version )){
		echo( application.changelogReport[ url.version ] );
	} else {
		echo("<em>Lucee change log is begin generated, please be patient....</em>")
	}
</cfscript>
