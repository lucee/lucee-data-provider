<cfinclude template="../functions.cfm">
<cfscript>
LTS_MINOR   = "6.2";
GROUP_ID    = "org.lucee";
FORUM_URL   = "https://dev.lucee.org/c/news/release/8";

function buildLinks(ver) {
	local.cacheKey = "luceeVerDetail_" & ver;
	local.detail   = application[local.cacheKey] ?: {};
	if (isEmpty(local.detail)) {
		try {
			local.detail = LuceeVersionsDetail(ver);
			application[local.cacheKey] = local.detail;
		} catch(e) { local.detail = {}; }
	}
	// start with CDN defaults for releases, then overlay API data
	local.isRelease = (getType(ver) == "release");
	local.links = local.isRelease ? cdnLinks(formatVersion(ver)) : {};
	for (local.k in local.detail) {
		if (local.k != "lastModified" && local.k != "pom" && len(local.detail[local.k])) {
			local.links[local.k] = local.detail[local.k];
		}
	}
	return local.links;
}

// Determine which track/minor we are showing
track       = lCase(url.track ?: "all");
typeFilter  = lCase(url.type ?: "");
minorFilter = url.minor ?: "";

// versions list — stale-while-revalidate (shared cache with index.cfm)
versCache    = application["luceeVersionsList"] ?: {};
allVersions  = versCache.data ?: [];
versCacheAge = structKeyExists(versCache, "cachedAt") ? dateDiff("n", versCache.cachedAt, now()) : 999;

if (!arrayLen(allVersions)) {
	try { allVersions = LuceeVersionsList(); } catch(e) { allVersions = []; }
	application["luceeVersionsList"] = { data: allVersions, cachedAt: now() };
} else if (versCacheAge >= 5) {
	thread action="run" name="refresh-versions-list-v-#getTickCount()#" {
		try {
			application["luceeVersionsList"] = { data: LuceeVersionsList(), cachedAt: now() };
		} catch(e) {}
	}
}

// Map minor → edge/stable/lts
minorTypes = {};
allMinors  = [];
minorData  = {}; // minor → sorted version list

SUPPRESS_MINORS = ["7.2"];

for (ver in allVersions) {
	if (getType(ver) == "alpha") continue;
	verMinor = getMinor(ver);
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
		if (getType(v) == "release") releaseBaseVersions[formatVersion(v)] = true;
	}
	minorData[m] = minorData[m].filter(function(v) {
		return getType(v) == "release" || !structKeyExists(releaseBaseVersions, formatVersion(v));
	});
}

// Sort minors desc
arraySort(allMinors, function(a,b) { return versionCompare(b,a); });

// Classify minors into tracks
edgeMinors  = [];
stableMinor = "";
for (m in allMinors) {
	if (m == LTS_MINOR) { minorTypes[m] = "lts"; continue; }
	hasR = false;
	hasB = false;
	for (v in minorData[m]) {
		vt = getType(v);
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
	pageTitle  = "LTS Releases — #LTS_MINOR#.x";
	trackBadge = "lts";
} else if (track == "stable") {
	showMinors = [stableMinor];
	pageTitle  = "Stable Releases — #stableMinor#.x";
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

// Optional minor filter (e.g. from Edge card footer link)
if (len(minorFilter)) {
	showMinors = showMinors.filter(function(m) { return m == minorFilter; });
	pageTitle  = pageTitle & " — #minorFilter#.x";
}

// Apply type filter (e.g. snapshot-only)
if (len(typeFilter)) {
	for (fm in showMinors) {
		minorData[fm] = minorData[fm].filter(function(v) { return getType(v) == typeFilter; });
	}
	// drop minors with no remaining versions
	showMinors = showMinors.filter(function(m) { return !arrayIsEmpty(minorData[m]); });
}

// Sort versions within each minor desc
for (m in minorData) {
	arraySort(minorData[m], function(a,b) { return versionCompare(b,a); });
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
	<link rel="stylesheet" href="/res/download.css">
</head>
<body>



<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Downloads</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org"   target="_blank">Docs</a>
		<a href="https://dev.lucee.org"    target="_blank">Forum</a>
		<a href="https://github.com/lucee" target="_blank">GitHub</a>
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
		<a href="https://mcp.lucee-services.com/" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/></svg>
			MCP Server
		</a>
		<a href="https://skill.lucee-services.com/" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
			Skills
		</a>
	</nav>
</header>

<div class="container">
	<div class="page-header">
		<div class="breadcrumb"><a href="/">Downloads</a> › Lucee Server</div>
		<h1>
			#encodeForHTML(pageTitle)#
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
						<cfset vtype = getType(ver)>
						<!--- Skip snapshots unless explicitly requested via type=snapshot --->
						<cfif vtype == "snapshot" && typeFilter != "snapshot"><cfcontinue></cfif>
						<cfset rowNum++>
						<cfif rowNum lte 10>
							<!--- First 10: render with full download links --->
							<cfset lnk = buildLinks(ver)>
							<tr>
								<td><strong>#encodeForHTML(formatVersion(ver))#</strong></td>
								<td><span class="version-type-badge #vtype#">#encodeForHTML(typeLabels[vtype] ?: vtype)#</span></td>
								<td>
									<div class="dl-links">
										<cfif structKeyExists(lnk,"win64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=win64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['win64'])#">Windows</a>
										</cfif>
										<cfif structKeyExists(lnk,"linux-x64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-x64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-x64'])#">Linux x64</a>
										</cfif>
										<cfif structKeyExists(lnk,"linux-aarch64")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-aarch64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-aarch64'])#">Linux arm64</a>
										</cfif>
										<cfif structKeyExists(lnk,"express")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=express" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">Express</a>
										</cfif>
										<cfif structKeyExists(lnk,"jar")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=jar" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">lucee.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"light")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=light" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">lucee-light.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"zero")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=zero" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">lucee-zero.jar</a>
										</cfif>
										<cfif structKeyExists(lnk,"lco")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=lco" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">Core (.lco)</a>
										</cfif>
										<cfif structKeyExists(lnk,"war")>
										<a href="/download.cfm?version=#encodeForURL(ver)#&type=war" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['war'])#">WAR</a>
										</cfif>
										<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForURL(listFirst(ver,'-'))#" target="_blank" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">Docker</a>
									</div>
								</td>
							</tr>
						<cfelse>
							<!--- Beyond first 10: lazy row, links fetched on demand --->
							<tr class="ver-lazy" data-version="#encodeForHTMLAttribute(ver)#" style="display:none">
								<td><strong>#encodeForHTML(formatVersion(ver))#</strong></td>
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
