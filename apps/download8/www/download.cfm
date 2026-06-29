<cfinclude template="../functions.cfm">
<cfscript>
groupId    = url.groupId    ?: "";
artifactId = url.artifactId ?: "";
version    = url.version    ?: "";
dlType     = url.type       ?: ""; // for server downloads: win64, linux-x64, jar, etc.

// ── Server version download ───────────────────────────────────────────
// triggered when type is provided but no artifactId (or artifactId is "lucee")
if (len(version) && len(dlType) && !len(artifactId)) {
	dlUrl = "";

	// check application cache first (populated by versions.cfm / index.cfm)
	cacheKey = "luceeVerDetail_" & version;
	detail   = application[cacheKey] ?: {};

	if (isEmpty(detail)) {
		try {
			detail = LuceeVersionsDetail(version);
			application[cacheKey] = detail;
		} catch(e) { detail = {}; }
	}

	// get URL from detail, fall back to CDN pattern for releases
	if (structKeyExists(detail, dlType) && len(detail[dlType])) {
		dlUrl = detail[dlType];
	} else if (getType(version) == "release") {
		cdn = cdnLinks(formatVersion(version));
		dlUrl = cdn[dlType] ?: "";
	}

	if (!len(dlUrl)) {
		cfheader(statusCode=404, statusText="Not Found");
		writeOutput("Download URL not available.");
		abort;
	}
	location(dlUrl, false);
	abort;
}

// ── Extension download ────────────────────────────────────────────────
if (!len(groupId) || !len(artifactId)) {
	cfheader(statusCode=400, statusText="Bad Request");
	writeOutput("Missing parameters.");
	abort;
}

// If no version given, find the latest release (or latest overall)
if (!len(version)) {
	try {
		versions = LuceeExtension(groupId, artifactId);
		versions = versions.filter(function(v) { return getType(v) != "alpha"; });
		arraySort(versions, function(a, b) { return versionCompare(b, a); });
		for (v in versions) {
			if (getType(v) == "release") { version = v; break; }
		}
		if (!len(version) && !arrayIsEmpty(versions)) version = versions[1];
	} catch(e) {}
}

if (!len(version)) {
	cfheader(statusCode=404, statusText="Not Found");
	writeOutput("No version available.");
	abort;
}

try {
	meta   = LuceeExtension(groupId, artifactId, version, true);
	lexUrl = meta.lex ?: "";
} catch(e) {
	lexUrl = "";
}

// fallback: construct Maven URL directly from coordinates
if (!len(lexUrl)) {
	lexUrl = "https://maven.lucee-services.com/"
		& replace(groupId, ".", "/", "all")
		& "/" & artifactId
		& "/" & version
		& "/" & artifactId & "-" & version & ".lex";
}

location(lexUrl, false);
</cfscript>
