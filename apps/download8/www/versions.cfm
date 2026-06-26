<cfscript>
LTS_MINOR   = "6.2";
GROUP_ID    = "org.lucee";
FORUM_URL   = "https://dev.lucee.org/c/news/release/8";
CDN         = "https://cdn.lucee.org/";

DL_INFO = {
	"win64":         "Windows x64 installer — guided setup wizard, installs Lucee as a Windows service with Tomcat included.",
	"linux-x64":     "Linux x64 installer — shell installer for 64-bit Linux, sets up Lucee as a system service with Tomcat.",
	"linux-aarch64": "Linux aarch64 installer — same as the x64 installer but for ARM64 (Apple Silicon, Ampere, AWS Graviton).",
	"express":       "Express ZIP — no installation needed. Unzip and run the start script. Ideal for local development or quick evaluation.",
	"jar":           "lucee.jar — drop into your servlet engine's lib/classpath folder. Lucee will download any missing dependency bundles on first start.",
	"light":         "lucee-light.jar — minimal Lucee jar with no bundled extensions. Smaller footprint; extensions are fetched on demand.",
	"lco":           "Core (.lco) — Lucee Core update file. Copy to the patches/ folder of an existing installation to update the core without reinstalling.",
	"war":           "WAR — Web ARchive for deployment on any Java Servlet container (Tomcat, Jetty, WildFly, etc.).",
	"zero":          "lucee-zero.jar — Lucee with zero bundled extensions. The smallest possible footprint; every extension is loaded on demand.",
	"docker":        "Docker Images — pre-built Lucee + Tomcat images on Docker Hub. Best for containerised and cloud deployments."
};

function cdnLinks(ver) {
	return {
		win64:           CDN & "lucee-" & ver & "-windows-x64-installer.exe",
		"linux-x64":     CDN & "lucee-" & ver & "-linux-x64-installer.run",
		"linux-aarch64": CDN & "lucee-" & ver & "-linux-aarch64-installer.run",
		express:         CDN & "lucee-express-" & ver & ".zip",
		jar:             CDN & "lucee-" & ver & ".jar",
		light:           CDN & "lucee-light-" & ver & ".jar",
		lco:             CDN & ver & ".lco",
		war:             CDN & "lucee-" & ver & ".war"
	};
}

function buildLinks(ver) {
	local.isRelease = (getType(ver) == "release");
	// start with CDN defaults for releases
	local.links = local.isRelease ? cdnLinks(formatVersion(ver)) : {};
	try {
		local.detail = LuceeVersionsDetail(ver);
		
		for (local.k in local.detail) {
			if (local.k != "lastModified" && local.k != "pom" && len(local.detail[local.k])) {
				local.links[local.k] = local.detail[local.k];
			}
		}
	} catch(e) {}
	return local.links;
}

function getMinor(ver) {
	local.base  = listFirst(ver, "-");
	local.parts = listToArray(base, ".");
	if (arrayLen(parts) >= 2) return parts[1] & "." & parts[2];
	return "";
}

function getType(ver) {
	local.v = lCase(ver);
	if (findNoCase("-snapshot", v)) return "snapshot";
	if (findNoCase("-beta",     v)) return "beta";
	if (findNoCase("-alpha",    v)) return "alpha";
	if (findNoCase("-rc",       v)) return "rc";
	return "release";
}

function formatVersion(ver) {
	return listFirst(ver, "-");
}

function versionCompare(v1, v2) {
	local.a = listToArray(listFirst(v1,"-"), ".");
	local.b = listToArray(listFirst(v2,"-"), ".");
	local.len = max(arrayLen(a), arrayLen(b));
	for (local.i = 1; i <= len; i++) {
		local.n1 = val(a[i] ?: "0");
		local.n2 = val(b[i] ?: "0");
		if (n1 > n2) return 1;
		if (n1 < n2) return -1;
	}
	return 0;
}

function parseDate(dateStr) {
	try {
		if (len(trim(dateStr))) return dateFormat(parseDateTime(dateStr), "mmm d, yyyy");
	} catch(e) {}
	return "";
}

// Determine which track/minor we are showing
track      = lCase(url.track ?: "all");
typeFilter = lCase(url.type ?: "");
minorFilter = url.minor ?: ""; // optional: restrict to a specific minor (e.g. 8.0)

try {
	allVersions = LuceeVersionsList();
} catch(e) {
	allVersions = [];
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
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>#encodeForHTML(pageTitle)# — Lucee Downloads</title>
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
						<!--- Skip snapshots unless explicitly requested --->
						<cfif vtype == "snapshot" && track != "edge" && track != "all"><cfcontinue></cfif>
						<cfset lnk = buildLinks(ver)>
						<tr>
							<td><strong>#encodeForHTML(formatVersion(ver))#</strong></td>
							<td><span class="version-type-badge #vtype#">#encodeForHTML(typeLabels[vtype] ?: vtype)#</span></td>
							<td>
								<div class="dl-links">
									<cfif structKeyExists(lnk,"win64")>
									<a href="#encodeForHTMLAttribute(lnk.win64)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['win64'])#">Windows</a>
									</cfif>
									<cfif structKeyExists(lnk,"linux-x64")>
									<a href="#encodeForHTMLAttribute(lnk['linux-x64'])#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-x64'])#">Linux x64</a>
									</cfif>
									<cfif structKeyExists(lnk,"linux-aarch64")>
									<a href="#encodeForHTMLAttribute(lnk['linux-aarch64'])#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-aarch64'])#">Linux arm64</a>
									</cfif>
									<cfif structKeyExists(lnk,"express")>
									<a href="#encodeForHTMLAttribute(lnk.express)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">Express</a>
									</cfif>
									<cfif structKeyExists(lnk,"jar")>
									<a href="#encodeForHTMLAttribute(lnk.jar)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">lucee.jar</a>
									</cfif>
									<cfif structKeyExists(lnk,"light")>
									<a href="#encodeForHTMLAttribute(lnk.light)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">lucee-light.jar</a>
									</cfif>
									<cfif structKeyExists(lnk,"zero")>
									<a href="#encodeForHTMLAttribute(lnk.zero)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">lucee-zero.jar</a>
									</cfif>
									<cfif structKeyExists(lnk,"lco")>
									<a href="#encodeForHTMLAttribute(lnk.lco)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">Core (.lco)</a>
									</cfif>
									<cfif structKeyExists(lnk,"war")>
									<a href="#encodeForHTMLAttribute(lnk.war)#" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['war'])#">WAR</a>
									</cfif>
									<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForURL(listFirst(ver,'-'))#" target="_blank" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">Docker</a>
								</div>
							</td>
						</tr>
					</cfloop>
					</tbody>
				</table>
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

</cfoutput>
</body>
</html>
