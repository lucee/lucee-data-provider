<cfscript>
function artifactDisplayName(artifactId) {
	local.words  = listToArray(artifactId, "-");
	local.result = [];
	for (local.w in local.words) {
		arrayAppend(local.result, uCase(left(local.w,1)) & lCase(right(local.w, len(local.w)-1)));
	}
	return arrayToList(local.result, " ");
}

function versionCompare(v1, v2) {
	local.a = listToArray(listFirst(v1,"-"), ".");
	local.b = listToArray(listFirst(v2,"-"), ".");
	local.len = max(arrayLen(local.a), arrayLen(local.b));
	for (local.i = 1; local.i <= local.len; local.i++) {
		local.n1 = val(local.a[local.i] ?: "0");
		local.n2 = val(local.b[local.i] ?: "0");
		if (local.n1 > local.n2) return 1;
		if (local.n1 < local.n2) return -1;
	}
	return 0;
}

function getType(ver) {
	local.v = lCase(ver);
	if (findNoCase("-snapshot", local.v)) return "snapshot";
	if (findNoCase("-beta",     local.v)) return "beta";
	if (findNoCase("-alpha",    local.v)) return "alpha";
	if (findNoCase("-rc",       local.v)) return "rc";
	return "release";
}

function parseDate(dateStr) {
	try {
		if (len(trim(dateStr))) return dateFormat(parseDateTime(dateStr), "mmm d, yyyy");
	} catch(e) {}
	return "";
}

// Params
groupId    = url.groupId    ?: "org.lucee";
artifactId = url.artifactId ?: "";

if (!len(artifactId)) {
	location("/", false);
}

displayName  = artifactDisplayName(artifactId);
mavenCoords  = groupId & ":" & artifactId;

// Load all versions for this extension, sorted newest first, no alpha
try {
	allVersions = LuceeExtension(groupId, artifactId);
	allVersions = allVersions.filter(function(v) { return getType(v) != "alpha"; });
	arraySort(allVersions, function(a, b) { return versionCompare(b, a); });
} catch(e) {
	allVersions = [];
}

// Fetch metadata (name, description, image, minCoreVersion) from latest version
extName           = artifactDisplayName(artifactId);
extDescription    = "";
extImage          = "";
extId             = "";
extMinCoreVersion = "";

if (!arrayIsEmpty(allVersions)) {
	try {
		latestMeta = LuceeExtension(groupId, artifactId, allVersions[1], true);
		if (structKeyExists(latestMeta, "metadata")) {
			meta = latestMeta.metadata;
			if (!isEmpty(meta.name            ?: "")) extName           = meta.name;
			if (!isEmpty(meta.description     ?: "")) extDescription    = meta.description;
			if (!isEmpty(meta.image           ?: "")) extImage          = meta.image;
			if (!isEmpty(meta.id              ?: "")) extId             = meta.id;
			if (!isEmpty(meta.MinCoreVersion  ?: "")) extMinCoreVersion = meta.MinCoreVersion;
		}
	} catch(e) { /* metadata unavailable */ }
}

// Pick the best version for install snippets: latest release, else latest overall
snippetVer = "";
for (sv in allVersions) {
	if (getType(sv) == "release") { snippetVer = sv; break; }
}
if (!len(snippetVer) && !arrayIsEmpty(allVersions)) snippetVer = allVersions[1];

// Group versions by type, fetching full metadata (download=true) for each
groups = {
	release:  [],
	rc:       [],
	beta:     [],
	snapshot: []
};

for (ver in allVersions) {
	verType  = getType(ver);
	groupKey = verType;
	if (!structKeyExists(groups, groupKey)) groups[groupKey] = [];
	verMinCore = "";
	try {
		verMeta = LuceeExtension(groupId, artifactId, ver, true);
		if (structKeyExists(verMeta, "metadata") && !isEmpty(verMeta.metadata.MinCoreVersion ?: "")) {
			verMinCore = verMeta.metadata.MinCoreVersion;
		}
		arrayAppend(groups[groupKey], {
			version:      verMeta.version      ?: ver,
			lastModified: parseDate(verMeta.lastModified ?: ""),
			lex:          verMeta.lex          ?: "",
			type:         verType,
			minCore:      verMinCore
		});
	} catch(e) {
		arrayAppend(groups[groupKey], {
			version:      ver,
			lastModified: "",
			lex:          "",
			type:         verType,
			minCore:      ""
		});
	}
}

// sort each group descending (allVersions already sorted, but groups built in loop order)
for (gk in groups) {
	arraySort(groups[gk], function(a, b) { return versionCompare(b.version, a.version); });
}

groupMeta = {
	release:  { label: "Releases",            badge: "release"  },
	rc:       { label: "Release Candidates",   badge: "rc"       },
	beta:     { label: "Betas",                badge: "beta"     },
	snapshot: { label: "Snapshots",            badge: "snapshot" }
};

typeOrder = ["release","rc","beta","snapshot"];
VERSIONS_PREVIEW = 5;
</cfscript>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>#encodeForHTML(displayName)# Extension — Lucee Downloads</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/download.css">
</head>
<body>

<cfoutput>

<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Downloads</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org"   target="_blank">Docs</a>
		<a href="https://dev.lucee.org"    target="_blank">Forum</a>
		<a href="https://github.com/lucee" target="_blank">GitHub</a>
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

	<div class="ext-detail-header">
		<div class="breadcrumb"><a href="/">Downloads</a> › <a href="/##extensions">Extensions</a></div>

		<div class="ext-detail-title-row">
			<cfif len(extImage)>
			<img class="ext-detail-logo" style="background:white"
				src="<cfif left(extImage,4) eq 'http'>#encodeForHTMLAttribute(extImage)#<cfelse>data:image/png;base64,#encodeForHTMLAttribute(extImage)#</cfif>"
				alt="#encodeForHTMLAttribute(extName)# logo">
			</cfif>
			<div>
				<h1>#encodeForHTML(extName)#</h1>
				<code class="maven-coords">#encodeForHTML(mavenCoords)#</code>
			</div>
		</div>

		<cfif len(extDescription)>
		<p class="ext-detail-desc">#encodeForHTML(extDescription)#</p>
		</cfif>

		<cfif len(extMinCoreVersion) || len(extId)>
		<div class="ext-detail-meta-row">
			<cfif len(extMinCoreVersion)>
			<span class="ext-meta-chip">
				<span class="ext-meta-label">Requires Lucee</span>
				<strong>#encodeForHTML(extMinCoreVersion)#+</strong>
			</span>
			</cfif>
			<cfif len(extId)>
			<span class="ext-meta-chip text-muted text-small">
				<span class="ext-meta-label">ID</span>
				#encodeForHTML(extId)#
			</span>
			</cfif>
		</div>
		</cfif>
	</div>

	<!--- ── Installation snippets ── --->
	<cfif len(snippetVer)>
	<div class="install-section">
		<h2 class="section-title">Installation</h2>

		<div class="install-tabs">
			<input type="radio" name="itab-#encodeForHTMLAttribute(artifactId)#" id="itab-cfg" checked>
			<input type="radio" name="itab-#encodeForHTMLAttribute(artifactId)#" id="itab-env">
			<div class="install-tab-bar">
				<label for="itab-cfg">.CFConfig.json</label>
				<label for="itab-env">Environment variable</label>
			</div>

			<div class="install-panel" id="panel-cfg">
				<div class="install-col-grid">
					<div>
						<div class="install-col-label">Lucee 8+</div>
						<div class="code-block">
							<button class="copy-btn" data-copy="cfg8-#encodeForHTMLAttribute(artifactId)#">Copy</button>
							<pre id="cfg8-#encodeForHTMLAttribute(artifactId)#">{
  "extensions": [
    {
      "maven": "#encodeForHTML(groupId)#:#encodeForHTML(artifactId)#:#encodeForHTML(snippetVer)#"
    }
  ]
}</pre>
						</div>
					</div>
					<div>
						<div class="install-col-label">Lucee 7 and older</div>
						<div class="code-block">
							<button class="copy-btn" data-copy="cfg7-#encodeForHTMLAttribute(artifactId)#">Copy</button>
							<pre id="cfg7-#encodeForHTMLAttribute(artifactId)#">{
  "extensions": [
    {
      <cfif len(extId)>"id": "#encodeForHTML(extId)#",
      </cfif>"name": "#encodeForHTML(extName)#",
      "version": "#encodeForHTML(snippetVer)#"
    }
  ]
}</pre>
						</div>
					</div>
				</div>
			</div>

			<div class="install-panel" id="panel-env">
				<div class="install-col-grid">
					<div>
						<div class="install-col-label">Lucee 8+</div>
						<div class="code-block">
							<button class="copy-btn" data-copy="env8-#encodeForHTMLAttribute(artifactId)#">Copy</button>
							<pre id="env8-#encodeForHTMLAttribute(artifactId)#">export LUCEE_EXTENSIONS="#encodeForHTML(groupId)#:#encodeForHTML(artifactId)#:#encodeForHTML(snippetVer)#"</pre>
						</div>
					</div>
					<div>
						<div class="install-col-label">Lucee 7 and older</div>
						<div class="code-block">
							<button class="copy-btn" data-copy="env7-#encodeForHTMLAttribute(artifactId)#">Copy</button>
							<pre id="env7-#encodeForHTMLAttribute(artifactId)#">export LUCEE_EXTENSIONS="<cfif len(extId)>#encodeForHTML(extId)#;version=#encodeForHTML(snippetVer)#;<cfelse>#encodeForHTML(artifactId)#;version=#encodeForHTML(snippetVer)#;</cfif>"</pre>
						</div>
					</div>
				</div>
			</div>
		</div>
	</div>
	</cfif>

	<cfif arrayIsEmpty(allVersions)>
		<p class="text-muted">No versions found for this extension.</p>
	<cfelse>
		<cfloop array="#typeOrder#" item="groupKey">
			<cfif !structKeyExists(groups, groupKey) || arrayIsEmpty(groups[groupKey])>
				<cfcontinue>
			</cfif>
			<cfset gm = groupMeta[groupKey]>
			<div class="version-group">
				<div class="version-group-title">
					#encodeForHTML(gm.label)#
					<span class="version-type-badge #gm.badge#">#uCase(gm.badge)#</span>
				</div>

				<cfset grpId = "grp-" & groupKey>
				<table class="versions-table">
					<thead>
						<tr>
							<th>Version</th>
							<th>Released</th>
							<th>Requires Lucee</th>
							<th>Download</th>
						</tr>
					</thead>
					<tbody>
					<cfloop array="#groups[groupKey]#" item="ext" index="extIdx">
						<tr<cfif extIdx gt VERSIONS_PREVIEW> class="ver-hidden" data-group="#encodeForHTMLAttribute(grpId)#"</cfif>>
							<td><strong>#encodeForHTML(ext.version)#</strong></td>
							<td class="text-muted">#len(ext.lastModified) ? encodeForHTML(ext.lastModified) : "—"#</td>
							<td class="text-muted">#len(ext.minCore) ? encodeForHTML(ext.minCore) & "+" : "—"#</td>
							<td>
								<div class="dl-links">
									<cfif len(ext.lex)>
									<a class="btn-dl primary" href="#encodeForHTMLAttribute(ext.lex)#">Download</a>
									</cfif>
								</div>
							</td>
						</tr>
					</cfloop>
					</tbody>
				</table>
				<cfif arrayLen(groups[groupKey]) gt VERSIONS_PREVIEW>
				<button class="show-more-btn" data-group="#encodeForHTMLAttribute(grpId)#"
					data-total="#arrayLen(groups[groupKey])#">
					Show #arrayLen(groups[groupKey]) - VERSIONS_PREVIEW# older versions
				</button>
				</cfif>
			</div>
		</cfloop>
	</cfif>

	<p class="text-muted text-small mt-4">
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

</cfoutput>
<script>
document.querySelectorAll('.show-more-btn').forEach(function(btn) {
	btn.addEventListener('click', function() {
		var grp = btn.dataset.group;
		document.querySelectorAll('.ver-hidden[data-group="' + grp + '"]').forEach(function(row) {
			row.classList.remove('ver-hidden');
		});
		btn.remove();
	});
});

document.querySelectorAll('.copy-btn').forEach(function(btn) {
	btn.addEventListener('click', function() {
		var pre = document.getElementById(btn.dataset.copy);
		if (!pre) return;
		navigator.clipboard.writeText(pre.textContent).then(function() {
			btn.textContent = 'Copied!';
			btn.classList.add('copied');
			setTimeout(function() {
				btn.textContent = 'Copy';
				btn.classList.remove('copied');
			}, 2000);
		});
	});
});
</script>
</body>
</html>
