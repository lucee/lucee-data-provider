<cfscript>
// ── Config ──────────────────────────────────────────────────────────
LTS_MINOR   = "6.2";
GROUP_ID    = "org.lucee";
DOCKER_DOCS = "https://docs.lucee.org/recipes/docker.html";
FORUM_URL   = "https://dev.lucee.org/c/news/release/8";

// ── Download format descriptions ────────────────────────────────────
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

// ── Helper functions ─────────────────────────────────────────────────
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
	return listFirst(ver, "-"); // strip suffix for display
}

function parseDate(dateStr) {
	// "June, 24 2024 08:08:41 +0000" or empty
	try {
		if (len(trim(dateStr))) return dateFormat(parseDateTime(dateStr), "mmm d, yyyy");
	} catch(e) {}
	return "";
}

function artifactDisplayName(artifactId) {
	// "administrator-extension" → "Administrator Extension"
	local.words = listToArray(artifactId, "-");
	local.result = [];
	for (local.w in words) {
		arrayAppend(result, uCase(left(w, 1)) & lCase(right(w, len(w)-1)));
	}
	return arrayToList(result, " ");
}

function versionCompare(v1, v2) {
	// compare dotted numeric version strings, returns -1/0/1
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

// ── Load Lucee versions ──────────────────────────────────────────────
try {
	allVersions = LuceeVersionsList();
} catch(e) {
	allVersions = [];
}

// Group by minor → { hasRelease, hasBeta, latestRelease, latestBeta, versions[] }
minorMap = {};

SUPPRESS_MINORS = ["7.2"];

for (ver in allVersions) {
	verType  = getType(ver);
	verMinor = getMinor(ver);
	if (!len(verMinor)) continue;
	if (arrayFindNoCase(SUPPRESS_MINORS, verMinor)) continue;

	if (!structKeyExists(minorMap, verMinor)) {
		minorMap[verMinor] = {
			hasRelease:    false,
			hasBeta:       false,
			latestRelease: "",
			latestBeta:    "",
			versions:      []
		};
	}
	arrayAppend(minorMap[verMinor].versions, ver);

	if (verType == "release") {
		minorMap[verMinor].hasRelease = true;
		if (!len(minorMap[verMinor].latestRelease) || versionCompare(ver, minorMap[verMinor].latestRelease) > 0)
			minorMap[verMinor].latestRelease = ver;
	} else if (verType == "beta" || verType == "rc") {
		minorMap[verMinor].hasBeta = true;
		if (!len(minorMap[verMinor].latestBeta) || versionCompare(ver, minorMap[verMinor].latestBeta) > 0)
			minorMap[verMinor].latestBeta = ver;
	}
}

// Sort minors descending to find tracks
allMinors = structKeyArray(minorMap);
arraySort(allMinors, function(a,b) { return versionCompare(b,a); });

edgeMinors  = [];
stableMinor = "";

for (minor in allMinors) {
	minorInfo = minorMap[minor];
	if (minor == LTS_MINOR) continue;
	// Edge: has beta/RC releases but NO stable release yet — collect ALL such minors
	if (!minorInfo.hasRelease && minorInfo.hasBeta) {
		arrayAppend(edgeMinors, minor);
	} else if (minorInfo.hasRelease && !len(stableMinor)) {
		stableMinor = minor;
	}
}
// keep backwards-compat alias for versions.cfm track filter (uses first edge minor)
edgeMinor = arrayLen(edgeMinors) ? edgeMinors[1] : "";

CDN = "https://cdn.lucee.org/";

// Build CDN download URLs for a release version
function cdnLinks(ver) {
	return {
		win64:         CDN & "lucee-" & ver & "-windows-x64-installer.exe",
		"linux-x64":   CDN & "lucee-" & ver & "-linux-x64-installer.run",
		"linux-aarch64": CDN & "lucee-" & ver & "-linux-aarch64-installer.run",
		express:       CDN & "lucee-express-" & ver & ".zip",
		jar:           CDN & "lucee-" & ver & ".jar",
		light:         CDN & "lucee-light-" & ver & ".jar",
		lco:           CDN & ver & ".lco",
		war:           CDN & "lucee-" & ver & ".war"
	};
}

function getLuceeVersionsDetail(v) cachedWithin=1000 {
	return LuceeVersionsDetail(v);
}

// Build track structs: { minor, version, isRelease, links }
function buildTrack(minor, useLatest="release") {
	if (!structKeyExists(minorMap, minor)) return {};
	local.d   = minorMap[minor];
	local.ver = (useLatest == "beta") ? d.latestBeta : d.latestRelease;
	if (!len(local.ver)) return {};
	local.isRelease = (getType(local.ver) == "release");
	try {
		local.detail = getLuceeVersionsDetail(local.ver);
	} catch(e) {
		local.detail = {};
	}
	// Start from CDN defaults for releases, then let the API override any key it provides
	local.links = local.isRelease ? cdnLinks(local.ver) : {};
	for (local.k in local.detail) {
		if (local.k != "lastModified" && local.k != "pom" && len(local.detail[local.k])) {
			local.links[local.k] = local.detail[local.k];
		}
	}
	return { minor: minor, version: local.ver, isRelease: local.isRelease, links: local.links, detail: local.detail };
}

tracks = {};
if (len(LTS_MINOR)    && structKeyExists(minorMap, LTS_MINOR) && minorMap[LTS_MINOR].hasRelease)
	tracks.lts    = buildTrack(LTS_MINOR, "release");
if (len(stableMinor)  && minorMap[stableMinor].hasRelease)
	tracks.stable = buildTrack(stableMinor, "release");
tracks.edgeList = [];
// render edge cards lowest minor first (ascending), so e.g. 7.1 before 8.0
arraySort(edgeMinors, function(a,b) { return versionCompare(a,b); });
for (em in edgeMinors) {
	if (minorMap[em].hasBeta) arrayAppend(tracks.edgeList, buildTrack(em, "beta"));
}

function getLuceeExtension(g,a,v) cachedwithin=1000 {
	return LuceeExtension(g, a, v, true);
}

// ── Load Extensions ──────────────────────────────────────────────────
function loadGroupExtensions(groupId) {
	local.result = [];
	try {
		local.artifacts = LuceeExtension(groupId);
		arrayEach(local.artifacts, function(artifactId) {
			try {
				local.extVersions = LuceeExtension(groupId, artifactId);
				local.extVersions = local.extVersions.filter(function(v) { return getType(v) != "alpha"; });
				if (!arrayIsEmpty(local.extVersions)) {
					arraySort(local.extVersions, function(a, b) { return versionCompare(b, a); });
					local.latestRelVer = "";
					for (local.ev in local.extVersions) {
						if (getType(local.ev) == "release") { local.latestRelVer = local.ev; break; }
					}
					local.pickVer   = len(local.latestRelVer) ? local.latestRelVer : local.extVersions[1];
					local.extDetail = getLuceeExtension(groupId, artifactId, local.pickVer, true);
					local.extName   = artifactDisplayName(artifactId);
					if (!isEmpty(local.extDetail.metadata.name  ?: "")) local.extName  = local.extDetail.metadata.name;
					local.extImage  = local.extDetail.metadata.image ?: "";
					arrayAppend(result, {
						groupId:      groupId,
						artifactId:   artifactId,
						displayName:  local.extName,
						image:        local.extImage,
						version:      local.extDetail.version ?: local.pickVer,
						lastModified: parseDate(local.extDetail.lastModified ?: ""),
						lex:          local.extDetail.lex ?: "",
						hasRelease:   len(local.latestRelVer)
					});
				}
			} catch(e) { /* skip broken extension */ }
		}, true, 50); // parallel=true, maxThreads=10
	} catch(e) {}
	return local.result;
}

extensions = [];
for (gid in ["org.lucee", "io.forgebox"]) {
	extensions.addAll(loadGroupExtensions(gid));
}
// sort all extensions alphabetically by display name
arraySort(extensions, function(a, b) { return compare(lCase(a.displayName), lCase(b.displayName)); });
</cfscript>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Downloads</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/download.css">
</head>
<body>

<cfoutput>

<!--- ── Header ── --->
<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Downloads</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org"     target="_blank">Docs</a>
		<a href="https://dev.lucee.org"      target="_blank">Forum</a>
		<a href="https://github.com/lucee"   target="_blank">GitHub</a>
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

<!--- ── Hero ── --->
<!--- ── Tracks ── --->
<div class="container">
<section class="tracks-section">
	<h2 class="section-title">Lucee Server</h2>

	<div class="tracks-grid">

		<!--- LTS --->
		<cfif len(tracks.lts ?: {})>
		<cfset t = tracks.lts>
		<cfset lnk = t.links>
		<article class="track-card">
			<div class="track-card-header">
				<span class="track-badge lts">LTS</span>
				<div class="track-meta">
					<h2>#formatVersion(t.version)#</h2>
					<div class="track-label">Long-Term Support — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<p class="track-desc">Production-hardened, security-patched for the long haul. Recommended for enterprise deployments.</p>
				<div class="dl-group-label">Popular downloads</div>
				<ul class="dl-list">
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">i</i></li>
					<li><a href="#lnk['linux-x64']#">Linux x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-x64'])#">i</i></li>
					<li><a href="#lnk['linux-aarch64']#">Linux aarch64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-aarch64'])#">i</i></li>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">i</i></li>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">i</i></li>
				</ul>
				<details class="dl-other-formats">
					<summary class="dl-group-label">Other downloads</summary>
					<ul class="dl-list">
						<li><a href="#lnk.win64#">Windows x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['win64'])#">i</i></li>
						<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">i</i></li>
						<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">i</i></li>
						<cfif structKeyExists(lnk,"zero")>
						<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">i</i></li>
						</cfif>
						<li><a href="#lnk.war#">WAR</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['war'])#">i</i></li>
					</ul>
				</details>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=lts">All releases <span class="icon-arrow-right"></span></a>
				<a href="/versions.cfm?track=all&minor=#encodeForURL(t.minor)#&type=snapshot" class="text-muted text-small">All snapshots</a>
			</div>
		</article>
		</cfif>

		<!--- Stable --->
		<cfif len(tracks.stable ?: {})>
		<cfset t = tracks.stable>
		<cfset lnk = t.links>
		<article class="track-card">
			<div class="track-card-header">
				<span class="track-badge stable">Stable</span>
				<div class="track-meta">
					<h2>#formatVersion(t.version)#</h2>
					<div class="track-label">Latest stable — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<p class="track-desc">The current production-ready release with the latest features and improvements.</p>
				<div class="dl-group-label">Popular downloads</div>
				<ul class="dl-list">
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">i</i></li>
					<li><a href="#lnk['linux-x64']#">Linux x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-x64'])#">i</i></li>
					<li><a href="#lnk['linux-aarch64']#">Linux aarch64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-aarch64'])#">i</i></li>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">i</i></li>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">i</i></li>
				</ul>
				<details class="dl-other-formats">
					<summary class="dl-group-label">Other downloads</summary>
					<ul class="dl-list">
						<li><a href="#lnk.win64#">Windows x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['win64'])#">i</i></li>
						<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">i</i></li>
						<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">i</i></li>
						<cfif structKeyExists(lnk,"zero")>
						<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">i</i></li>
						</cfif>
						<li><a href="#lnk.war#">WAR</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['war'])#">i</i></li>
					</ul>
				</details>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=stable">All releases <span class="icon-arrow-right"></span></a>
				<a href="/versions.cfm?track=all&minor=#encodeForURL(t.minor)#&type=snapshot" class="text-muted text-small">All snapshots</a>
			</div>
		</article>
		</cfif>

		<!--- Edge — one card per minor that has beta/RC but no stable release yet --->
		<cfloop array="#tracks.edgeList#" item="t">
		<cfset lnk = t.links>
		<article class="track-card">
			<div class="track-card-header">
				<span class="track-badge edge">Edge</span>
				<div class="track-meta">
					<h2>#formatVersion(t.version)#</h2>
					<div class="track-label">Beta preview — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<div class="notice">Beta releases — not recommended for production environments.</div>
				<p class="track-desc">Cutting-edge features in active development. Help shape the next major version.</p>
				<div class="dl-group-label">Downloads</div>
				<ul class="dl-list">
					<cfif structKeyExists(lnk,"jar")>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"light")>
					<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"zero")>
					<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"lco")>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"express")>
					<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">i</i></li>
					</cfif>
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">i</i></li>
				</ul>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=all&minor=#encodeForURL(t.minor)#">All releases <span class="icon-arrow-right"></span></a>
				<a href="/versions.cfm?track=all&minor=#encodeForURL(t.minor)#&type=snapshot" class="text-muted text-small">All snapshots</a>
			</div>
		</article>
		</cfloop>

	</div><!--- .tracks-grid --->

	<p class="text-muted text-small mt-4">
		Also available via
		<a href="https://mvnrepository.com/artifact/org.lucee/lucee" target="_blank">Maven Central</a> &middot;
		<a href="https://www.forgebox.io/view/lucee" target="_blank">CommandBox / ForgeBox</a> &middot;
		<a href="#DOCKER_DOCS#" target="_blank">Docker setup guide</a> &middot;
		<a href="/versions.cfm">All releases</a> &middot;
		<a href="/versions.cfm?track=all&type=snapshot">All snapshots</a>
	</p>

</section>
<cfflush>
<hr class="section-divider">

<!--- ── Extensions ── --->
<section class="extensions-section" id="extensions">
	<div class="ext-section-header">
		<h2 class="section-title" style="margin-bottom:0;">Extensions</h2>
		<div class="ext-search-wrap">
			<input type="search" id="ext-search" class="ext-search" placeholder="Search extensions…" autocomplete="off">
		</div>
	</div>
	<p class="text-muted text-small" style="margin-bottom:24px;">
		Drop a <code>.lex</code> file into <code>/lucee-server/deploy/</code> or install via the Lucee Administrator under <em>Extension › Applications</em>.
	</p>

	<cfif arrayIsEmpty(extensions)>
		<p class="text-muted">Could not load extensions — please try again later.</p>
	<cfelse>
		<p class="text-muted text-small" id="ext-no-results" style="display:none;">No extensions match your search.</p>
		<div class="ext-grid" id="ext-grid">
		<cfloop array="#extensions#" item="ext">
			<cfflush>
			<article class="ext-card" data-name="#lCase(encodeForHTMLAttribute(ext.displayName))#">
				<div class="ext-card-header">
					<cfif len(ext.image)>
					<img class="ext-card-logo"
						src="<cfif left(ext.image,4) eq 'http'>#encodeForHTMLAttribute(ext.image)#<cfelse>data:image/png;base64,#encodeForHTMLAttribute(ext.image)#</cfif>"
						alt="#encodeForHTMLAttribute(ext.displayName)# logo">
					</cfif>
					<div>
						<h3>#encodeForHTML(ext.displayName)#</h3>
						<div class="ext-artifact">#encodeForHTML(ext.groupId)#:#encodeForHTML(ext.artifactId)#</div>
					</div>
				</div>
				<div class="ext-card-body">
					<div class="ext-version-row">
						<span class="ext-version">#encodeForHTML(ext.version)#</span>
						<cfif len(ext.lastModified)>
						<span class="ext-date">#encodeForHTML(ext.lastModified)#</span>
						</cfif>
					</div>
					<cfif !ext.hasRelease>
					<div class="text-small" style="margin-top:4px;color:##c0392b;">No release yet</div>
					</cfif>
				</div>
				<div class="ext-card-footer">
					<cfif len(ext.lex)>
					<a class="btn-dl primary" href="#encodeForHTMLAttribute(ext.lex)#">Download</a>
					</cfif>
					<a href="/extension.cfm?groupId=#encodeForURL(ext.groupId)#&artifactId=#encodeForURL(ext.artifactId)#">All versions <span class="icon-arrow-right"></span></a>
					<a href="https://mvnrepository.com/artifact/#encodeForURL(ext.groupId)#/#encodeForURL(ext.artifactId)#" target="_blank" class="text-muted text-small">Maven</a>
				</div>
			</article>
		</cfloop>
		</div>
	</cfif>

	<p class="text-muted text-small mt-4">
		Extension updates and changelogs are posted in the
		<a href="https://dev.lucee.org/c/hacking/extensions/5" target="_blank">Extensions forum category</a>.
	</p>
</section>
</div><!--- .container --->

<!--- ── Footer ── --->
<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a> &middot;
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
	</span>
</footer>

</cfoutput>
<script>
(function() {
	var input   = document.getElementById('ext-search');
	var grid    = document.getElementById('ext-grid');
	var noRes   = document.getElementById('ext-no-results');
	if (!input || !grid) return;
	input.addEventListener('input', function() {
		var q = input.value.trim().toLowerCase();
		var cards = grid.querySelectorAll('.ext-card');
		var visible = 0;
		cards.forEach(function(card) {
			var match = !q || card.dataset.name.indexOf(q) !== -1;
			card.style.display = match ? '' : 'none';
			if (match) visible++;
		});
		noRes.style.display = (q && visible === 0) ? '' : 'none';
	});
})();
</script>
</body>
</html>
