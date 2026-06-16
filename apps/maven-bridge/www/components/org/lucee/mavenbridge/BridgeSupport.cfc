component {

	variables.SNAPSHOT_SUFFIX = "-SNAPSHOT";

	public function init(required struct config) {
		variables.providerUrl = trim(config.provider);
		variables.groupId = trim(config.groupId);
		variables.upstreamUrl = normalizeUpstreamUrl(config.upstream ?: "");
		variables.cacheTtlMinutes = val(config.cacheTtlMinutes ?: 60);
		variables.timeout = val(config.timeout ?: 300);
		if (variables.cacheTtlMinutes < 1) {
			variables.cacheTtlMinutes = 60;
		}
		if (variables.timeout < 1) {
			variables.timeout = 300;
		}
		if (right(variables.providerUrl, 1) == "/") {
			variables.providerUrl = left(variables.providerUrl, len(variables.providerUrl) - 1);
		}
		return this;
	}

	public string function getProviderUrl() {
		return variables.providerUrl;
	}

	public string function getGroupId() {
		return variables.groupId;
	}

	public boolean function hasUpstream() {
		return len(variables.upstreamUrl) > 0;
	}

	public string function getUpstreamUrl() {
		return variables.upstreamUrl;
	}

	public string function toUpstreamRelativePath(required struct parsed) {
		var groupPath = replace(variables.groupId, ".", "/", "all");

		switch (arguments.parsed.type) {
			case "group-index":
				return groupPath & "/index.html";
			case "group-metadata":
				return groupPath & "/maven-metadata.xml";
			case "artifact-index":
				return groupPath & "/" & arguments.parsed.artifactId & "/index.html";
			case "artifact-metadata":
				return groupPath & "/" & arguments.parsed.artifactId & "/maven-metadata.xml";
			case "version-index":
				return groupPath & "/" & arguments.parsed.artifactId & "/" & arguments.parsed.version & "/index.html";
			case "version-metadata":
				return groupPath & "/" & arguments.parsed.artifactId & "/" & arguments.parsed.version & "/maven-metadata.xml";
			case "artifact-file":
				var fileName = arguments.parsed.artifactId & "-" & arguments.parsed.version & "." & arguments.parsed.extension;
				return groupPath & "/" & arguments.parsed.artifactId & "/" & arguments.parsed.version & "/" & fileName;
			default:
				return "";
		}
	}

	public struct function fetchUpstreamResource(required string relativePath, string method="get") {
		var rel = replace(arguments.relativePath, "\", "/", "all");
		while (left(rel, 1) == "/") {
			rel = mid(rel, 2);
		}
		var uri = variables.upstreamUrl & rel;

		cfhttp(url=uri, method=arguments.method, timeout=variables.timeout, result="local.res") {};

		var status = val(listFirst(toString(res.statusCode), " "));
		var contentType = "";
		if (structKeyExists(res, "responseheader")) {
			var headers = res.responseheader;
			if (isStruct(headers)) {
				contentType = headers["Content-Type"] ?: headers["content-type"] ?: "";
			}
		}

		return {
			"statusCode": status,
			"body": res.fileContent ?: "",
			"contentType": contentType,
			"url": uri
		};
	}

	public boolean function upstreamResourceExists(required string relativePath) {
		var fetched = fetchUpstreamResource(arguments.relativePath, "head");
		return fetched.statusCode == 200;
	}

	public struct function getCachedUpstreamContent(required string webroot, required string relativePath) {
		var rel = replace(arguments.relativePath, "\", "/", "all");
		while (left(rel, 1) == "/") {
			rel = mid(rel, 2);
		}
		var localFile = ensureTrailingSlash(arguments.webroot) & rel;
		var refresh = true;

		if (fileExists(localFile)) {
			var ageMinutes = dateDiff("n", getFileInfo(localFile).lastmodified, now());
			refresh = ageMinutes >= variables.cacheTtlMinutes;
		}

		if (refresh) {
			var fetched = fetchUpstreamResource(rel);
			if (fetched.statusCode == 404) {
				throw(message="Upstream not found [#rel#]", type="bridge.upstream.notfound");
			}
			if (fetched.statusCode != 200) {
				throw(message="Upstream [#fetched.url#] returned HTTP #fetched.statusCode#", type="bridge.upstream");
			}
			ensureDirectory(getDirectoryFromPath(localFile));
			fileWrite(localFile, fetched.body);
			return {
				"statusCode": 200,
				"body": fetched.body,
				"contentType": len(fetched.contentType) ? fetched.contentType : contentTypeForPath(rel)
			};
		}

		return {
			"statusCode": 200,
			"body": fileRead(localFile),
			"contentType": contentTypeForPath(rel)
		};
	}

	public string function contentTypeForPath(required string relativePath) {
		var path = lCase(arguments.relativePath);
		if (right(path, 4) == ".xml") {
			return "application/xml; charset=utf-8";
		}
		if (right(path, 5) == ".html") {
			return "text/html; charset=utf-8";
		}
		return "application/octet-stream";
	}

	public struct function getIndex() {
		ensureIndex();
		return application.mavenBridgeIndex[variables.groupId];
	}

	public struct function flushCache(required string webroot) {
		if (structKeyExists(application, "mavenBridgeIndex")) {
			structDelete(application.mavenBridgeIndex, variables.groupId);
		}
		syncRepository(arguments.webroot);
		return getIndex();
	}

	public struct function parseMavenPath(required string path) {
		var groupPath = replace(variables.groupId, ".", "/", "all");
		var prefix = "/" & groupPath;
		var rtn = { "type": "unknown" };

		if (arguments.path == prefix || arguments.path == prefix & "/") {
			rtn.type = "group-index";
			rtn.groupId = variables.groupId;
			return rtn;
		}

		if (left(arguments.path, len(prefix) + 1) != prefix & "/") {
			return rtn;
		}

		var remainder = mid(arguments.path, len(prefix) + 2);
		var parts = listToArray(remainder, "/");

		if (arrayLen(parts) == 1) {
			if (parts[1] == "maven-metadata.xml") {
				rtn.type = "group-metadata";
				rtn.groupId = variables.groupId;
				return rtn;
			}
			rtn.type = "artifact-index";
			rtn.groupId = variables.groupId;
			rtn.artifactId = parts[1];
			return rtn;
		}

		if (arrayLen(parts) == 2 && parts[2] == "maven-metadata.xml") {
			rtn.type = "artifact-metadata";
			rtn.groupId = variables.groupId;
			rtn.artifactId = parts[1];
			return rtn;
		}

		if (arrayLen(parts) == 2) {
			rtn.type = "version-index";
			rtn.groupId = variables.groupId;
			rtn.artifactId = parts[1];
			rtn.version = parts[2];
			return rtn;
		}

		if (arrayLen(parts) == 3 && parts[3] == "maven-metadata.xml") {
			rtn.type = "version-metadata";
			rtn.groupId = variables.groupId;
			rtn.artifactId = parts[1];
			rtn.version = parts[2];
			return rtn;
		}

		if (arrayLen(parts) == 3) {
			var fileName = parts[3];
			var version = parts[2];
			var artifactId = parts[1];
			var expectedPrefix = artifactId & "-" & version & ".";
			if (left(fileName, len(expectedPrefix)) == expectedPrefix) {
				rtn.type = "artifact-file";
				rtn.groupId = variables.groupId;
				rtn.artifactId = artifactId;
				rtn.version = version;
				rtn.extension = listLast(fileName, ".");
				return rtn;
			}
		}

		return rtn;
	}

	public string function buildGroupMetadata() {
		var index = getIndex();
		var artifactIds = structKeyArray(index.artifacts);
		arraySort(artifactIds, "textnocase");

		var xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			"  <groupId>#xmlValue(variables.groupId)#</groupId>",
			"  <artifacts>"
		];

		for (var artifactId in artifactIds) {
			var versions = listVersions(artifactId);
			if (!arrayLen(versions)) {
				continue;
			}

			var latest = versions[arrayLen(versions)];
			var release = "";
			for (var i = arrayLen(versions); i >= 1; i--) {
				if (!findNoCase(variables.SNAPSHOT_SUFFIX, versions[i])) {
					release = versions[i];
					break;
				}
			}

			arrayAppend(xml, "    <artifact>");
			arrayAppend(xml, "      <artifactId>#xmlValue(artifactId)#</artifactId>");
			arrayAppend(xml, "      <latest>#xmlValue(latest)#</latest>");
			if (len(release)) {
				arrayAppend(xml, "      <release>#xmlValue(release)#</release>");
			}
			arrayAppend(xml, "    </artifact>");
		}

		arrayAppend(xml, "  </artifacts>");
		arrayAppend(xml, "  <lastUpdated>#xmlValue(mavenTimestamp(now()))#</lastUpdated>");
		arrayAppend(xml, "</metadata>");

		return arrayToList(xml, chr(10));
	}

	public string function buildGroupIndexHtml() {
		var index = getIndex();
		var artifactIds = structKeyArray(index.artifacts);
		arraySort(artifactIds, "textnocase");

		var html = [
			"<!DOCTYPE html>",
			"<html><head><title>#encodeForHtml(variables.groupId)#</title></head><body>",
			"<h1>#encodeForHtml(variables.groupId)#</h1>",
			"<pre>",
			'<a href="maven-metadata.xml">maven-metadata.xml</a>' & chr(10)
		];

		for (var artifactId in artifactIds) {
			arrayAppend(html, '<a href="#encodeForHtml(artifactId)#/">#encodeForHtml(artifactId)#/</a>' & chr(10));
		}

		arrayAppend(html, "</pre></body></html>");
		return arrayToList(html, chr(10));
	}

	public string function buildArtifactIndexHtml(required string artifactId) {
		var versions = listVersions(arguments.artifactId);

		var html = [
			"<!DOCTYPE html>",
			"<html><head><title>#encodeForHtml(variables.groupId)#:#encodeForHtml(arguments.artifactId)#</title></head><body>",
			"<h1>#encodeForHtml(variables.groupId)#:#encodeForHtml(arguments.artifactId)#</h1>",
			"<pre>",
			'<a href="maven-metadata.xml">maven-metadata.xml</a>' & chr(10)
		];

		for (var version in versions) {
			arrayAppend(html, '<a href="#encodeForHtml(version)#/">#encodeForHtml(version)#/</a>' & chr(10));
		}

		arrayAppend(html, "</pre></body></html>");
		return arrayToList(html, chr(10));
	}

	public string function buildVersionIndexHtml(required string artifactId, required string version) {
		var baseName = arguments.artifactId & "-" & arguments.version;
		var html = [
			"<!DOCTYPE html>",
			"<html><head><title>#encodeForHtml(baseName)#</title></head><body>",
			"<h1>#encodeForHtml(baseName)#</h1>",
			"<pre>"
		];

		if (findNoCase(variables.SNAPSHOT_SUFFIX, arguments.version)) {
			arrayAppend(html, '<a href="maven-metadata.xml">maven-metadata.xml</a>' & chr(10));
		}

		arrayAppend(html, '<a href="#encodeForHtml(baseName)#.lex">#encodeForHtml(baseName)#.lex</a>' & chr(10));
		arrayAppend(html, '<a href="#encodeForHtml(baseName)#.pom">#encodeForHtml(baseName)#.pom</a>' & chr(10));
		arrayAppend(html, "</pre></body></html>");
		return arrayToList(html, chr(10));
	}

	public string function buildArtifactMetadata(required string artifactId) {
		var versions = listVersions(arguments.artifactId);
		if (!arrayLen(versions)) {
			throw(message="No versions found for [#arguments.artifactId#]", type="bridge.notfound");
		}

		var latest = versions[arrayLen(versions)];
		var release = "";
		for (var i = arrayLen(versions); i >= 1; i--) {
			if (!findNoCase(variables.SNAPSHOT_SUFFIX, versions[i])) {
				release = versions[i];
				break;
			}
		}

		var xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			"  <groupId>#xmlValue(variables.groupId)#</groupId>",
			"  <artifactId>#xmlValue(arguments.artifactId)#</artifactId>",
			"  <versioning>",
			"    <latest>#xmlValue(latest)#</latest>"
		];

		if (len(release)) {
			arrayAppend(xml, "    <release>#xmlValue(release)#</release>");
		}

		arrayAppend(xml, "    <versions>");
		for (var version in versions) {
			arrayAppend(xml, "      <version>#xmlValue(version)#</version>");
		}
		arrayAppend(xml, "    </versions>");
		arrayAppend(xml, "    <lastUpdated>#xmlValue(mavenTimestamp(now()))#</lastUpdated>");
		arrayAppend(xml, "  </versioning>");
		arrayAppend(xml, "</metadata>");

		return arrayToList(xml, chr(10));
	}

	public string function buildVersionMetadata(required string artifactId, required string version) {
		if (!findNoCase(variables.SNAPSHOT_SUFFIX, arguments.version)) {
			return buildArtifactMetadata(arguments.artifactId);
		}

		var xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			"<metadata>",
			"  <groupId>#xmlValue(variables.groupId)#</groupId>",
			"  <artifactId>#xmlValue(arguments.artifactId)#</artifactId>",
			"  <version>#xmlValue(arguments.version)#</version>",
			"  <versioning>",
			"    <snapshot>",
			"      <timestamp>#xmlValue(mavenTimestamp(now()))#</timestamp>",
			"      <buildNumber>1</buildNumber>",
			"    </snapshot>",
			"    <lastUpdated>#xmlValue(mavenTimestamp(now()))#</lastUpdated>",
			"    <snapshotVersions>",
			"      <snapshotVersion>",
			"        <extension>lex</extension>",
			"        <value>#xmlValue(arguments.version)#</value>",
			"        <updated>#xmlValue(mavenTimestamp(now()))#</updated>",
			"      </snapshotVersion>",
			"    </snapshotVersions>",
			"  </versioning>",
			"</metadata>"
		];
		return arrayToList(xml, chr(10));
	}

	public string function buildMinimalPom(required string artifactId, required string version) {
		var ext = getIndex().artifacts[arguments.artifactId].versions[arguments.version] ?: {};
		var xml = [
			'<?xml version="1.0" encoding="UTF-8"?>',
			'<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">',
			"  <modelVersion>4.0.0</modelVersion>",
			"  <groupId>#xmlValue(variables.groupId)#</groupId>",
			"  <artifactId>#xmlValue(arguments.artifactId)#</artifactId>",
			"  <version>#xmlValue(arguments.version)#</version>",
			"  <packaging>lex</packaging>",
			"  <name>#xmlValue(ext.name ?: arguments.artifactId)#</name>"
		];
		if (len(ext.description ?: "")) {
			arrayAppend(xml, "  <description>#xmlValue(ext.description)#</description>");
		}
		arrayAppend(xml, "</project>");
		return arrayToList(xml, chr(10));
	}

	public string function getDownloadUrl(required string artifactId, required string version) {
		var index = getIndex();
		if (!structKeyExists(index.artifacts, arguments.artifactId)) {
			return "";
		}
		var versions = index.artifacts[arguments.artifactId].versions;
		if (!structKeyExists(versions, arguments.version)) {
			return "";
		}
		return versions[arguments.version].downloadUrl ?: "";
	}

	public array function listVersions(required string artifactId) {
		var index = getIndex();
		if (!structKeyExists(index.artifacts, arguments.artifactId)) {
			return [];
		}
		var versions = structKeyArray(index.artifacts[arguments.artifactId].versions);
		arraySort(versions, function(a, b) {
			return compare(versionSortKey(a), versionSortKey(b));
		});
		return versions;
	}

	public string function describe() {
		var lines = "Lucee extension provider Maven bridge#chr(10)#"
			& "Provider: #variables.providerUrl##chr(10)#"
			& "GroupId:  #variables.groupId##chr(10)#";
		if (hasUpstream()) {
			lines &= "Upstream: #variables.upstreamUrl##chr(10)#";
		}
		if (!hasUpstream()) {
			var index = getIndex();
			lines &= "Artifacts: #structCount(index.artifacts)##chr(10)#"
				& "Cached at: #index.cachedAt##chr(10)#";
		} else {
			lines &= "Mode:     upstream mirror (REST fallback for missing artifacts)#chr(10)#";
		}
		lines &= "Try: /#replace(variables.groupId, '.', '/', 'all')#/";
		return lines;
	}

	public void function syncRepository(required string webroot) {
		if (hasUpstream()) {
			syncUpstreamRepository(arguments.webroot);
			return;
		}

		var groupPath = replace(variables.groupId, ".", "/", "all");
		var baseDir = ensureTrailingSlash(arguments.webroot) & groupPath & "/";

		cleanupStaleSyncArtifacts(arguments.webroot, groupPath);

		var index = getIndex();
		ensureDirectory(baseDir);
		fileWrite(baseDir & "maven-metadata.xml", buildGroupMetadata());
		fileWrite(baseDir & "index.html", buildGroupIndexHtml());

		for (var artifactId in structKeyArray(index.artifacts)) {
			var artifactDir = baseDir & artifactId & "/";
			ensureDirectory(artifactDir);
			fileWrite(artifactDir & "maven-metadata.xml", buildArtifactMetadata(artifactId));
			fileWrite(artifactDir & "index.html", buildArtifactIndexHtml(artifactId));

			for (var version in listVersions(artifactId)) {
				var versionDir = artifactDir & version & "/";
				ensureDirectory(versionDir);
				fileWrite(versionDir & "index.html", buildVersionIndexHtml(artifactId, version));
				if (findNoCase(variables.SNAPSHOT_SUFFIX, version)) {
					fileWrite(versionDir & "maven-metadata.xml", buildVersionMetadata(artifactId, version));
				}
			}
		}
	}

	// --- index loading ---

	private void function ensureIndex() {
		if (!structKeyExists(application, "mavenBridgeIndex")) {
			application.mavenBridgeIndex = {};
		}
		if (structKeyExists(application.mavenBridgeIndex, variables.groupId)) {
			var ageMinutes = dateDiff("n", application.mavenBridgeIndex[variables.groupId].cachedAt, now());
			if (ageMinutes < variables.cacheTtlMinutes) {
				return;
			}
		}
		application.mavenBridgeIndex[variables.groupId] = loadIndex();
		if (structKeyExists(application, "bridgeWebroot")) {
			syncRepository(application.bridgeWebroot);
		}
	}

	private void function syncUpstreamRepository(required string webroot) {
		var groupPath = replace(variables.groupId, ".", "/", "all");
		for (var relativePath in [
			groupPath & "/maven-metadata.xml",
			groupPath & "/index.html"
		]) {
			try {
				getCachedUpstreamContent(arguments.webroot, relativePath);
			} catch (any e) {
				// Group files may not exist yet on upstream during migration.
			}
		}
	}

	private string function normalizeUpstreamUrl(required string upstream) {
		var normalized = trim(arguments.upstream);
		if (!len(normalized)) {
			return "";
		}
		if (right(normalized, 1) != "/") {
			normalized &= "/";
		}
		return normalized;
	}

	private struct function loadIndex() {
		var uri = variables.providerUrl & "/rest/extension/provider/info?type=all&withLogo=false";
		cfhttp(url=uri, method="get", timeout=variables.timeout, result="local.res") {
			cfhttpparam(type="header", name="accept", value="application/json");
		}

		if (left(toString(res.statusCode), 3) != "200") {
			throw(message="Extension provider [#uri#] returned HTTP #res.statusCode#", type="bridge.provider");
		}

		var payload = deserializeJSON(res.fileContent);
		var extensions = normalizeExtensions(payload);
		var artifacts = {};

		for (var ext in extensions) {
			addVersionEntry(artifacts, ext);
			addOlderVersions(artifacts, ext);
		}

		return {
			"cachedAt": now(),
			"provider": variables.providerUrl,
			"groupId": variables.groupId,
			"artifacts": artifacts
		};
	}

	private array function normalizeExtensions(required struct payload) {
		if (structKeyExists(payload, "extensions") && isQuery(payload.extensions)) {
			return queryToArray(payload.extensions);
		}
		if (structKeyExists(payload, "EXTENSIONS") && isStruct(payload.EXTENSIONS)) {
			return columnsDataToArray(payload.EXTENSIONS);
		}
		throw(message="Unexpected extension provider response shape", type="bridge.provider");
	}

	private array function queryToArray(required query qry) {
		var rows = [];
		var cols = queryColumnArray(qry);
		loop query=qry {
			var row = {};
			for (var col in cols) {
				row[col] = qry[col][qry.currentRow];
			}
			arrayAppend(rows, row);
		}
		return rows;
	}

	private array function columnsDataToArray(required struct block) {
		var cols = block.COLUMNS ?: block.columns ?: [];
		var data = block.DATA ?: block.data ?: [];
		var rows = [];
		for (var rowData in data) {
			var row = {};
			for (var i = 1; i <= arrayLen(cols); i++) {
				row[cols[i]] = rowData[i];
			}
			arrayAppend(rows, row);
		}
		return rows;
	}

	private void function addVersionEntry(required struct artifacts, required struct ext) {
		if (!len(ext.version ?: "")) {
			return;
		}

		var artifactId = resolveArtifactId(ext);
		if (!len(artifactId)) {
			return;
		}

		artifacts[artifactId] = artifacts[artifactId] ?: {
			"id": ext.id ?: "",
			"name": ext.name ?: artifactId,
			"versions": {}
		};

		artifacts[artifactId].versions[ext.version] = {
			"id": ext.id ?: "",
			"name": ext.name ?: artifactId,
			"description": ext.description ?: "",
			"filename": ext.filename ?: "",
			"created": ext.created ?: "",
			"downloadUrl": resolveDownloadUrl(ext)
		};
	}

	private void function addOlderVersions(required struct artifacts, required struct ext) {
		var olderVersions = ext.older ?: [];
		var olderNames = ext.olderName ?: [];
		if (!isArray(olderVersions)) {
			olderVersions = listToArray(toString(olderVersions));
		}
		if (!isArray(olderNames)) {
			olderNames = listToArray(toString(olderNames));
		}

		for (var i = 1; i <= arrayLen(olderVersions); i++) {
			var version = trim(olderVersions[i]);
			if (!len(version)) {
				continue;
			}
			var filename = (arrayLen(olderNames) >= i) ? trim(olderNames[i]) : "";
			var pseudo = duplicate(ext);
			pseudo.version = version;
			if (len(filename)) {
				pseudo.filename = filename;
			}
			pseudo.url = "";
			addVersionEntry(artifacts, pseudo);
		}
	}

	private string function resolveArtifactId(required struct ext) {
		if (len(ext.artifactId ?: "")) {
			return normalizeArtifactId(ext.artifactId);
		}
		if (len(ext.filename ?: "") && len(ext.version ?: "")) {
			return normalizeArtifactId(filenameToArtifactId(ext.filename, ext.version));
		}
		if (len(ext.name ?: "")) {
			return normalizeArtifactId(reReplace(ext.name, "\s+", "-", "all") & "-extension");
		}
		return "";
	}

	private string function filenameToArtifactId(required string filename, required string version) {
		var base = replace(filename, ".lex", "", "all");
		var suffix = "-" & version;
		if (right(base, len(suffix)) == suffix) {
			base = left(base, len(base) - len(suffix));
		}
		return base;
	}

	private string function normalizeArtifactId(required string artifactId) {
		var id = trim(arguments.artifactId);
		id = replace(id, ".extension", "-extension", "all");
		id = replace(id, ".", "-", "all");
		if (right(id, 10) == "-extension") {
			return lCase(id);
		}
		return lCase(id) & "-extension";
	}

	private string function resolveDownloadUrl(required struct ext) {
		if (len(ext.url ?: "")) {
			return ext.url;
		}
		if (len(ext.id ?: "") && len(ext.version ?: "")) {
			return variables.providerUrl & "/rest/extension/provider/full/" & ext.id & "?version=" & urlEncodedFormat(ext.version);
		}
		return "";
	}

	private string function versionSortKey(required string version) {
		var parts = listToArray(arguments.version, ".-");
		var key = "";
		for (var part in parts) {
			if (part == "SNAPSHOT") {
				key &= ".999999";
			} else if (isNumeric(part)) {
				key &= "." & numberFormat(val(part), "00000");
			} else {
				key &= "." & part;
			}
		}
		return key;
	}

	private string function xmlValue(required string value) {
		return xmlFormat(arguments.value);
	}

	private string function mavenTimestamp(required date dt) {
		return dateTimeFormat(arguments.dt, "yyyymmddHHnnss");
	}

	private void function cleanupStaleSyncArtifacts(required string webroot, required string groupPath) {
		var segments = listToArray(arguments.groupPath, "/");
		var groupDirName = arrayPop(segments);
		var orgDir = ensureTrailingSlash(arguments.webroot) & arrayToList(segments, "/") & "/";
		if (!len(groupDirName) || !directoryExists(orgDir)) {
			return;
		}

		for (var entry in directoryList(orgDir, false, "name")) {
			if (entry == groupDirName) {
				continue;
			}
			if (left(entry, len(groupDirName)) != groupDirName) {
				continue;
			}

			var path = orgDir & entry;
			if (directoryExists(path)) {
				directoryDelete(path, true);
			} else if (fileExists(path)) {
				fileDelete(path);
			}
		}
	}

	private void function ensureDirectory(required string path) {
		var dir = ensureTrailingSlash(replace(arguments.path, "\", "/", "all"));
		if (!directoryExists(dir)) {
			directoryCreate(dir, true);
		}
	}

	private string function ensureTrailingSlash(required string path) {
		var p = arguments.path;
		if (!len(p) || right(p, 1) != "/") {
			p &= "/";
		}
		return p;
	}
}
