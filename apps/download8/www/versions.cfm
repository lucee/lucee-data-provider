<cfscript>
util = application.util;

LTS_MINOR   = "6.2";
GROUP_ID    = "org.lucee";
FORUM_URL   = "https://dev.lucee.org/c/news/release/8";

function buildLinks(ver) {
	local.detail    = util.getLuceeVersionsDetail(ver);
	local.isRelease = (util.getType(ver) == "release");
	local.links = local.isRelease ? util.cdnLinks(util.formatVersion(ver)) : {};
	for (local.k in local.detail) {
		if (local.k != "lastModified" && local.k != "pom" && len(local.detail[local.k])) {
			local.links[local.k] = local.detail[local.k];
		}
	}
	// express is a GitHub release asset for every non-snapshot version
	if (util.getType(ver) != "snapshot") local.links.express = util.expressUrl(ver);
	return local.links;
}

// Determine which track/minor we are showing
track       = lCase(url.track ?: "all");
typeFilter  = lCase(url.type ?: "");
minorFilter = url.minor ?: "";

// versions list
allVersions = util.getLuceeVersionsDetail();

// Map minor → edge/stable/lts
minorTypes = {};
allMinors  = [];
minorData  = {}; // minor → sorted version list

SUPPRESS_MINORS = ["7.2"];

for (ver in allVersions) {
	if (util.getType(ver) == "alpha") continue;
	verMinor = util.getMinor(ver);
	if (arrayFindNoCase(SUPPRESS_MINORS, verMinor)) continue;
	if (!len(verMinor)) continue;
	if (!structKeyExists(minorData, verMinor)) {
		minorData[verMinor] = [];
		arrayAppend(allMinors, verMinor);
	}
	arrayAppend(minorData[verMinor], ver);
}

// Drop RC/beta/snapshot if a release with the same base version exists
for (m in allMinors) {
	releaseBaseVersions = {};
	for (v in minorData[m]) {
		if (util.getType(v) == "release") releaseBaseVersions[util.formatVersion(v)] = true;
	}
	minorData[m] = minorData[m].filter(function(v) {
		return util.getType(v) == "release" || !structKeyExists(releaseBaseVersions, util.formatVersion(v));
	});
}

// Sort minors desc
arraySort(allMinors, function(a,b) { return util.versionCompare(b,a); });

// Classify minors into tracks
edgeMinors  = [];
stableMinor = "";
for (m in allMinors) {
	if (m == LTS_MINOR) { minorTypes[m] = "lts"; continue; }
	hasR = false;
	hasB = false;
	for (v in minorData[m]) {
		vt = util.getType(v);
		if (vt == "release") hasR = true;
		if (vt == "beta" || vt == "rc") hasB = true;
	}
	if (!hasR && hasB) {
		arrayAppend(edgeMinors, m);
		minorTypes[m] = "edge";
	} else if (hasR && !len(stableMinor)) {
		stableMinor = m;
		minorTypes[m] = "stable";
	} else {
		minorTypes[m] = "history";
	}
}
edgeMinor = arrayLen(edgeMinors) ? edgeMinors[1] : "";

// Filter to requested track
if (track == "lts") {
	showMinors = [LTS_MINOR];
	pageTitle  = "LTS Releases";
	trackBadge = "lts";
} else if (track == "stable") {
	showMinors = [stableMinor];
	pageTitle  = "Stable Releases";
	trackBadge = "stable";
} else if (track == "edge") {
	showMinors = edgeMinors;
	pageTitle  = "Edge Builds";
	trackBadge = "edge";
} else {
	showMinors = allMinors;
	pageTitle  = (typeFilter == "snapshot") ? "All Snapshots" : "All Releases";
	trackBadge = "";
}

// Optional minor filter. A bare major ("7") shows every minor of that major line
// (7.1, 7.0, …) so older releases stay reachable even after a newer minor ships; a
// full minor ("7.1") stays an exact match.
if (len(minorFilter)) {
	if (find(".", minorFilter)) {
		showMinors = showMinors.filter(function(m) { return m == minorFilter; });
	} else {
		showMinors = allMinors.filter(function(m) { return listFirst(m, ".") == minorFilter; });
		pageTitle  = "Lucee " & minorFilter & " Releases";
	}
}

// Apply type filter (e.g. snapshot-only)
if (len(typeFilter)) {
	for (fm in showMinors) {
		minorData[fm] = minorData[fm].filter(function(v) { return util.getType(v) == typeFilter; });
	}
	// drop minors with no remaining versions
	showMinors = showMinors.filter(function(m) { return !arrayIsEmpty(minorData[m]); });
}

// Sort versions within each minor desc
for (m in minorData) {
	arraySort(minorData[m], function(a,b) { return util.versionCompare(b,a); });
}

typeLabels = {
	release:  "Release",
	beta:     "Beta",
	rc:       "Release Candidate",
	snapshot: "Snapshot"
};
</cfscript>
<!DOCTYPE html>
<html lang="en">
<cfoutput>
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>#encodeForHTML(pageTitle)# — Lucee Downloads</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<cfinclude template="_lucee-head.cfm">
	<link rel="stylesheet" href="/res/download.css?v=10">
</head>
<body>



<cfinclude template="_lucee-header.cfm">

<div class="container">
	<div class="page-header">
		<div class="breadcrumb"><a href="/">Downloads</a> › Lucee Server</div>
		<h1>
			#encodeForHTML(pageTitle)#
			<cfif arrayLen(showMinors) == 1 && structKeyExists(minorData, showMinors[1]) && !arrayIsEmpty(minorData[showMinors[1]])>
				<cfset vMinors = minorData[showMinors[1]]>
				#encodeForHTML(showMinors[1])#
				(#encodeForHTML(util.formatVersion(vMinors[arrayLen(vMinors)]))# &mdash; #encodeForHTML(util.formatVersion(vMinors[1]))#)
			</cfif>
			<cfif len(trackBadge)><span class="track-badge #trackBadge#" style="font-size:13px;vertical-align:middle;">#uCase(trackBadge)#</span></cfif>
		</h1>
	</div>

	<cfif arrayIsEmpty(allVersions)>
		<p class="text-muted">Could not load versions — please try again later.</p>
	<cfelse>
		<cfloop array="#showMinors#" item="minor">
			<cfif !structKeyExists(minorData, minor) || arrayIsEmpty(minorData[minor])><cfcontinue></cfif>

			<div class="version-group">
				<div class="version-group-title">
					#encodeForHTML(minor)#.x
					<cfset mtype = minorTypes[minor] ?: "">
					<cfif len(mtype)><span class="track-badge #mtype#">#uCase(mtype)#</span></cfif>
				</div>

				<cfset rowNum = 0>
				<table class="versions-table">
					<thead>
						<tr>
							<th>Version</th>
							<th>Type</th>
							<th>Downloads</th>
						</tr>
					</thead>
					<tbody>
					<cfloop array="#minorData[minor]#" item="ver">
						<cfset vtype = util.getType(ver)>
						<!--- Skip snapshots unless explicitly requested via type=snapshot --->
						<cfif vtype == "snapshot" && typeFilter != "snapshot"><cfcontinue></cfif>
						<cfset rowNum++>
						<cfif rowNum lte 10>
							<!--- First 10: render with full download links --->
							<cfset lnk = buildLinks(ver)>
							<tr>
								<td><strong>#encodeForHTML(util.formatVersion(ver))#</strong></td>
								<td><span class="version-type-badge #vtype#">#encodeForHTML(typeLabels[vtype] ?: vtype)#</span></td>
								<td>
									<div class="dl-links">
										<cfif structKeyExists(lnk,"win64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=win64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['win64'])#">Windows</a>
										</cfif>
										<cfif structKeyExists(lnk,"linux-x64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-x64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-x64'])#">Linux x64</a>
										</cfif>
										<cfif structKeyExists(lnk,"linux-aarch64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-aarch64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-aarch64'])#">Linux arm64</a>
										</cfif>
										<cfif structKeyExists(lnk,"express")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=express" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['express'])#">Express</a>
										</cfif>
										<cfif structKeyExists(lnk,"jar")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=jar" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['jar'])#">lucee.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"light")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=light" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['light'])#">lucee-light.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"zero")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=zero" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['zero'])#">lucee-zero.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"lco")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=lco" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['lco'])#">Core (.lco)</a>
										</cfif>
										<cfif structKeyExists(lnk,"war")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=war" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['war'])#">WAR</a>
										</cfif>
										<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForURL(listFirst(ver,'-'))#" target="_blank" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['docker'])#">Docker</a>
										<a href="/changelog.cfm?version=#encodeForURL(ver)#" class="dl-changelog has-tooltip" data-tooltip="Changelog — issues fixed in this version">Changelog</a>
									</div>
								</td>
							</tr>
						<cfelse>
							<!--- Beyond first 10: lazy row, links fetched on demand --->
							<tr class="ver-lazy" data-version="#encodeForHTMLAttribute(ver)#" style="display:none">
								<td><strong>#encodeForHTML(util.formatVersion(ver))#</strong></td>
								<td><span class="version-type-badge #vtype#">#encodeForHTML(typeLabels[vtype] ?: vtype)#</span></td>
								<td class="dl-lazy"><span class="text-muted">Loading…</span></td>
							</tr>
						</cfif>
					</cfloop>
					</tbody>
				</table>
				<cfif rowNum gt 10>
				<button class="show-more-versions" data-shown="10" data-per-page="10">Show more versions (#rowNum - 10# remaining)</button>
				</cfif>
			</div>
		</cfloop>
	</cfif>

	<cfif typeFilter eq "snapshot">
	<div class="notice" style="margin-top:24px;">
		<strong>Snapshots are temporary.</strong> Snapshot builds are only guaranteed to remain
		available for <strong>90&nbsp;days</strong> after they are published. Any URL referencing a
		snapshot may stop working once that build is purged from the repository. Use snapshots only
		for testing and short-term evaluation — do not link to, or depend on, a snapshot download
		over the long term. For anything lasting, use a <a href="/versions.cfm">stable release</a>.
	</div>
	</cfif>

	<p class="text-muted text-small mt-4">
		Release announcements and changelogs:
		<a href="#FORUM_URL#" target="_blank">Lucee Forum — Releases</a>
	</p>
	<p class="text-muted text-small" style="margin-top:8px;">
		<a href="/">← Back to Downloads</a>
	</p>
</div>

<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a>
	</span>
</footer>

<script>
document.querySelectorAll('.show-more-versions').forEach(function(btn) {
	btn.addEventListener('click', function() {
		var table  = btn.previousElementSibling;
		var lazy   = Array.from(table.querySelectorAll('tr.ver-lazy[style*="display:none"]'));
		var perPage = parseInt(btn.dataset.perPage) || 10;
		var batch  = lazy.slice(0, perPage);

		batch.forEach(function(tr) {
			tr.style.display = '';
			var ver  = tr.dataset.version;
			var cell = tr.querySelector('.dl-lazy');
			fetch('/versionlinks.cfm?version=' + encodeURIComponent(ver))
				.then(function(r) { return r.text(); })
				.then(function(html) { cell.innerHTML = html; })
				.catch(function() { cell.innerHTML = ''; });
		});

		var remaining = lazy.length - batch.length;
		if (remaining > 0) {
			btn.textContent = 'Show more versions (' + remaining + ' remaining)';
		} else {
			btn.remove();
		}
	});
});
</script>
</cfoutput>
</body>
</html>