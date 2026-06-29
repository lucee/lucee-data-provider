
<cfscript>
util = application.util;
start=getTickCount();

// ── Config ──────────────────────────────────────────────────────────
LTS_MINOR   = "6.2";
GROUP_ID    = "org.lucee";
DOCKER_DOCS = "https://docs.lucee.org/recipes/docker.html";
FORUM_URL   = "https://dev.lucee.org/c/news/release/8";

// ── Load Lucee versions (stale-while-revalidate) ─────────────────────
versCache    = util.dlCacheGet("luceeVersionsList");
allVersions  = versCache.data ?: [];
versCacheAge = structKeyExists(versCache, "cachedAt") ? dateDiff("n", versCache.cachedAt, now()) : 999;

if (!arrayLen(allVersions)) {
	// cold cache — must wait
	try { allVersions = LuceeVersionsList(); } catch(e) { allVersions = []; }
	util.dlCachePut("luceeVersionsList", { data: allVersions, cachedAt: now() });
} else if (versCacheAge >= 5) {
	// stale — serve cached, refresh in background
	thread action="run" name="refresh-versions-list-#getTickCount()#" {
		try {
			util.dlCachePut("luceeVersionsList", { data: LuceeVersionsList(), cachedAt: now() });
		} catch(e) {}
	}
}

// Group by minor → { hasRelease, hasBeta, latestRelease, latestBeta, versions[] }
minorMap = {};

for (ver in allVersions) {
	verType  = util.getType(ver);
	verMinor = util.getMinor(ver);
	if (!len(verMinor)) continue;
	
	if (verMinor=="7.2") continue;

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
		if (!len(minorMap[verMinor].latestRelease) || util.versionCompare(ver, minorMap[verMinor].latestRelease) > 0)
			minorMap[verMinor].latestRelease = ver;
	} else if (verType == "beta" || verType == "rc") {
		minorMap[verMinor].hasBeta = true;
		if (!len(minorMap[verMinor].latestBeta) || util.versionCompare(ver, minorMap[verMinor].latestBeta) > 0)
			minorMap[verMinor].latestBeta = ver;
	}
}

// Sort minors descending to find tracks
allMinors = structKeyArray(minorMap);
arraySort(allMinors, function(a,b) { return util.versionCompare(b,a); });

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

function getLuceeVersionsDetail(v) {
	local.cacheKey = "luceeVerDetail_" & v;
	local.cached   = util.dlCacheGet(local.cacheKey);
	if (!isEmpty(local.cached)) return local.cached;
	local.detail = LuceeVersionsDetail(v);
	util.dlCachePut(local.cacheKey, local.detail);
	return local.detail;
}

// Build track structs: { minor, version, isRelease, links }
function buildTrack(minor, useLatest="release") {
	if (!structKeyExists(minorMap, minor)) return {};
	local.d   = minorMap[minor];
	local.ver = (useLatest == "beta") ? d.latestBeta : d.latestRelease;
	if (!len(local.ver)) return {};
	local.isRelease = (util.getType(local.ver) == "release");
	try {
		local.detail = getLuceeVersionsDetail(local.ver);
	} catch(e) {
		local.detail = {};
	}
	// Start from util.CDN defaults for releases, then let the API override any key it provides
	local.links = local.isRelease ? util.cdnLinks(local.ver) : {};
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
arraySort(edgeMinors, function(a,b) { return util.versionCompare(a,b); });
for (em in edgeMinors) {
	if (minorMap[em].hasBeta) arrayAppend(tracks.edgeList, buildTrack(em, "beta"));
}
// ── Load Extensions ──────────────────────────────────────────────────
function loadGroupExtensions(groupId) {
	local.result = [];
	try {
		local.artifacts = LuceeExtension(groupId);
		arrayEach(local.artifacts, function(artifactId) {
			local.cacheKey = "extMeta_" & groupId & "_" & artifactId;
			local.cached   = util.dlCacheGet(local.cacheKey);
			local.name      = local.cached.displayName   ?: "";
			local.image     = local.cached.image         ?: "";
			local.latestVer = local.cached.latestVersion ?: "";

			if (!len(local.name)) {
				// not cached yet — use slug name and fire a background thread to populate cache
				local.name = util.artifactDisplayName(artifactId);
				thread action="run" name="cache-ext-#groupId#-#artifactId#" gid=groupId aid=artifactId ckey=local.cacheKey {
					try {
						local.versions = LuceeExtension(attributes.gid, attributes.aid);
						local.versions = local.versions.filter(function(v) {
							local.t = lCase(v);
							return !findNoCase("-alpha", local.t);
						});
						if (!arrayIsEmpty(local.versions)) {
							arraySort(local.versions, function(a,b) {
								local.a = listToArray(listFirst(a,"-"), ".");
								local.b = listToArray(listFirst(b,"-"), ".");
								local.len = max(arrayLen(local.a), arrayLen(local.b));
								for (local.i=1; local.i<=local.len; local.i++) {
									local.n1 = val(local.a[local.i] ?: "0");
									local.n2 = val(local.b[local.i] ?: "0");
									if (local.n1 > local.n2) return -1;
									if (local.n1 < local.n2) return 1;
								}
								return 0;
							});
							local.pickVer = local.versions[1];
							local.meta    = LuceeExtension(attributes.gid, attributes.aid, local.pickVer, true);
							util.dlCachePut(attributes.ckey, {
								displayName:   local.meta.metadata.name  ?: "",
								image:         local.meta.metadata.image ?: "",
								latestVersion: local.pickVer,
								cachedAt:      now()
							});
						}
					} catch(e) {}
				}
			}

			arrayAppend(result, {
				groupId:      groupId,
				artifactId:   artifactId,
				displayName:  local.name,
				image:        local.image,
				latestVersion: local.latestVer
			});
		}, true, 20);
	} catch(e) {}
	return local.result;
}

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
					<h2>#util.formatVersion(t.version)#</h2>
					<div class="track-label">Long-Term Support — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<p class="track-desc">Production-hardened, security-patched for the long haul. Recommended for enterprise deployments.</p>
				<div class="dl-group-label">Popular downloads</div>
				<ul class="dl-list">
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['docker'])#">i</i></li>
					<li><a href="#lnk['linux-x64']#">Linux x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-x64'])#">i</i></li>
					<li><a href="#lnk['linux-aarch64']#">Linux aarch64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-aarch64'])#">i</i></li>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['jar'])#">i</i></li>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['lco'])#">i</i></li>
				</ul>
				<details class="dl-other-formats">
					<summary class="dl-group-label">Other downloads</summary>
					<ul class="dl-list">
						<li><a href="#lnk.win64#">Windows x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['win64'])#">i</i></li>
						<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['express'])#">i</i></li>
						<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['light'])#">i</i></li>
						<cfif structKeyExists(lnk,"zero")>
						<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['zero'])#">i</i></li>
						</cfif>
						<li><a href="#lnk.war#">WAR</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['war'])#">i</i></li>
					</ul>
				</details>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=lts&minor=#encodeForURL(t.minor)#">All releases <span class="icon-arrow-right"></span></a>
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
					<h2>#util.formatVersion(t.version)#</h2>
					<div class="track-label">Latest stable — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<p class="track-desc">The current production-ready release with the latest features and improvements.</p>
				<div class="dl-group-label">Popular downloads</div>
				<ul class="dl-list">
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['docker'])#">i</i></li>
					<li><a href="#lnk['linux-x64']#">Linux x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-x64'])#">i</i></li>
					<li><a href="#lnk['linux-aarch64']#">Linux aarch64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['linux-aarch64'])#">i</i></li>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['jar'])#">i</i></li>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['lco'])#">i</i></li>
				</ul>
				<details class="dl-other-formats">
					<summary class="dl-group-label">Other downloads</summary>
					<ul class="dl-list">
						<li><a href="#lnk.win64#">Windows x64</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['win64'])#">i</i></li>
						<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['express'])#">i</i></li>
						<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['light'])#">i</i></li>
						<cfif structKeyExists(lnk,"zero")>
						<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['zero'])#">i</i></li>
						</cfif>
						<li><a href="#lnk.war#">WAR</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['war'])#">i</i></li>
					</ul>
				</details>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=stable&minor=#encodeForURL(t.minor)#">All releases <span class="icon-arrow-right"></span></a>
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
					<h2>#util.formatVersion(t.version)#</h2>
					<div class="track-label">Beta preview — #t.minor#.x</div>
				</div>
			</div>
			<div class="track-card-body">
				<div class="notice">Beta releases — not recommended for production environments.</div>
				<p class="track-desc">Cutting-edge features in active development. Help shape the next major version.</p>
				<div class="dl-group-label">Downloads</div>
				<ul class="dl-list">
					<cfif structKeyExists(lnk,"jar")>
					<li><a href="#lnk.jar#">lucee.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['jar'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"light")>
					<li><a href="#lnk.light#">lucee-light.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['light'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"zero")>
					<li><a href="#lnk.zero#">lucee-zero.jar</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['zero'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"lco")>
					<li><a href="#lnk.lco#">Core (.lco)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['lco'])#">i</i></li>
					</cfif>
					<cfif structKeyExists(lnk,"express")>
					<li><a href="#lnk.express#">Express (ZIP)</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['express'])#">i</i></li>
					</cfif>
					<li><a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForHTMLAttribute(t.version)#" target="_blank">Docker Images</a> <i class="info-icon" data-tooltip="#encodeForHTMLAttribute(util.DL_INFO['docker'])#">i</i></li>
				</ul>
			</div>
			<div class="track-card-footer">
				<a href="/versions.cfm?track=edge&minor=#encodeForURL(t.minor)#">All releases <span class="icon-arrow-right"></span></a>
				<a href="/versions.cfm?track=edge&minor=#encodeForURL(t.minor)#&type=snapshot" class="text-muted text-small">All snapshots</a>
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
<cfscript>
extensions = [];
for (gid in ["org.lucee", "io.forgebox"]) {
	extensions.addAll(loadGroupExtensions(gid));
}

// sort all extensions alphabetically by display name
arraySort(extensions, function(a, b) { return compare(lCase(a.displayName), lCase(b.displayName)); });


</cfscript>

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
			<div class="ext-card" role="link" tabindex="0"
				onclick="location.href='/extension.cfm?groupId=#encodeForURL(ext.groupId)#&artifactId=#encodeForURL(ext.artifactId)#'"
				data-name="#lCase(encodeForHTMLAttribute(ext.displayName))#">
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
					<cfif len(ext.latestVersion)>
					<span class="ext-card-version">#encodeForHTML(ext.latestVersion)#</span>
					</cfif>
					<span class="ext-card-arrow">→</span>
				</div>
				<div class="ext-card-footer">
					<a class="ext-dl-btn" href="/download.cfm?groupId=#encodeForURL(ext.groupId)#&artifactId=#encodeForURL(ext.artifactId)#" onclick="event.stopPropagation()">Download .lex</a>
				</div>
			</div>
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
