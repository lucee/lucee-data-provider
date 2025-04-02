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
		"7.0": true
	}; // todo pull this out of known verions
	defaultMajorVersion = "6.2";
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

		major = {};
		preRelease = {};
		// add types
		//releases,snapshots,rc,beta
		loop struct=versions index="vs" item="data" {
			if(findNoCase("-snapshot",data.version)) data['type']="snapshots";
			else if(findNoCase("-rc",data.version)) data['type']="rc";
			else if(findNoCase("-beta",data.version)) data['type']="beta";
			else if(findNoCase("-alpha",data.version)) data['type']="alpha";
			else data['type']="releases";
			data['versionNoAppendix']=data.version;
			if ( data.type != "snapshots" ) {
				major[ vs ] = data;
			} else {
				// need to find latest pre release builds
				if ( structKeyExists( data, "versionSorted" ) ){
					v = ArrayToList( ArraySlice( listToArray( data.versionSorted,"." ), 1 , 2 ), "." );
					preRelease[ v ] = {
						versionSorted: data.versionSorted,
						versionNoAppendix: data.versionNoAppendix
					};
				}
			}
		}
		// avoid showingh a snapshot for a release etc
		structEach( preRelease, function( k, v ) {
			var releaseVersionSorted = left( v.versionSorted, len( v.versionSorted ) -4 );
			// check for RC / BETA / SNAPSHOT with the same version
			arrayEach( [ ".050",".100",".075" ], function( i ){
				if ( structKeyExists( major, releaseVersionSorted & arguments.i ) )
					structDelete( preRelease, k );
			});
		});
		structEach( preRelease, function( k, v ) {
			major[ v.versionSorted ] = {
				version: v.versionNoAppendix,
				type: "snapshot"
			};
		});

		arrVersions = structKeyArray(major).reverse().sort("text","desc");
		arrChangeLogs = [];

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
				<cfloop array="#arrVersions#" item="_version" index="idx">
					<cfscript>
						version = versions[ _version ].version;
						if (idx lt ArrayLen(arrVersions)){
							prevVersion = versions[arrVersions[ idx + 1 ]].version;
						} else {
							prevVersion = structKeyArray(versions);
							prevVersion = versions[prevVersion[arrayLen(prevVersion)]].version;
						}
						versionTitle = version;
						switch(versions[_version].type){
							case "releases":
								header="h2";
								versionTitle &= " Stable";
								break;
							default:
								header="h4";
						}
						changelog = {};
						versionReleaseDate = "";
						if ( left( version, 3 ) eq url.version ){
							changeLog = download.getChangelog( prevVersion, version, false, true );
							versionReleaseDate = download.getReleaseDate(version);
						}
						if (!isStruct(changelog))
							changelog = {};

						arrayAppend(arrChangeLogs, {
							version: version,
							_version: _version,
							type: versions[_version].type,
							prevVersion: prevVersion,
							versionReleaseDate = versionReleaseDate,
							changelog: changelog,
							header: header,
							versionTitle: versionTitle
						});
						/*
						structEach(changeLog, function(cl){
							structEach(changeLog[cl], function( ticket ){
								var _type= changeLog[ cl ][ ticket ].type;
								if ( !structKeyExists( ticketTypes, _type ) )
									ticketTypes[ _type ]=0;
								ticketTypes[ _type ]++;

								var _labels = changeLog [cl ][ ticket ].labels;
								arrayEach(_labels, function(_label) {
									if (!structKeyExists( ticketLabels, _label ) )
										ticketLabels[_label]=0;
									ticketLabels[_label]++;
								});
							});
						});
						*/
						
					</cfscript>
				</cfloop>
				<cfset lastMajor = "">
				<div class="versionList">
					<cfloop array="#arrChangeLogs#" item="luceeVersion">
						<cfif lastMajor neq left(luceeVersion.version, 3) and luceeVersion.type neq "snapshots">
							<cfif len(lastMajor) eq 0>
								Lucee Releases:
							</cfif>
							<cfset lastMajor = left(LuceeVersion.version, 3)>
							<b><a href="?version=#left(luceeVersion.version,3)#">#left(LuceeVersion.version, 3)#</a>&nbsp;</b>&nbsp;
							<a href="?version=#left(luceeVersion.version,3)####luceeVersion.version#">#luceeVersion.version#</a>&nbsp;
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
						<cfif structcount(lv.changelog) and left(lv.version,3) eq url.version>
							<cfif row neq 0>
								<tr>
									<td colspan="4"><hr></td>
								</tr>
							</cfif>
							<cfset row=1>
							<tr>
								<td colspan="4">
								<#lv.header# class="modal-title" id="#lv.version#">
									<b><a href="?version=#left(lv.version,3)####lv.version#">Lucee #lv.versionTitle#</a></b>
									<small>
										<span class="mr-2">#lv.versionReleaseDate#</span>
										<a href="../?#lv.type#=#lv._version###core" title="Jump to Downloads"><span class="glyphicon glyphicon-download-alt"></span></a>
									</small>
								</#lv.header#>
								</td>
							</tr>
							<cfset changelogTicketList = {}>
							<cfloop struct="#lv.changelog#" index="ver" item="tickets">
								<cfloop struct="#tickets#" index="id" item="ticket">
									<cfif !StructKeyExists(changelogTicketList, ticket.id)>
										<tr valign="top">
											<td nowrap><a href="https://bugs.lucee.org/browse/#id#" target="blank" class="mr-1">#id#</a></td>
											<td><span class="label label-#getBadgeForType(ticket.type)# mr-1" data-ticket-type="#ticket.type#">#ticket.type#</span></td>
											<td>#encodeForHtml(wrap(ticket.summary,70))#
											<cfif len(ticket.labels)>
												<br>
												<cfloop array="#ticket.labels#" item="label">
													<span class="label label-default">#encodeForHtml(label)#</span>
												</cfloop>
											</cfif>
											</td>
											<td style="max-width:250px;">#encodeForHtml(wrap(arrayToList(ticket.fixVersions,", "),15))#</td>
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
