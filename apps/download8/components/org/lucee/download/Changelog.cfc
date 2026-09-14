/**
 * Builds a per-version Lucee changelog straight from Jira (anonymous, no credentials).
 *
 * "Changelog for release X" = every LDEV ticket whose fixVersion falls in (previousRelease, X].
 * Jira tags a ticket with one fixVersion per build, and there are thousands of builds between two
 * Lucee releases, so a single fixVersion=X match is not enough — we collect all the build
 * fixVersions in the range and query for tickets carrying any of them.
 */
component accessors="false" {

	variables.JIRA_HOST   = "luceeserver.atlassian.net";
	variables.JIRA_PROJECT = "LDEV";
	variables.JIRA_STATUS  = "Deployed, Done, QA, Resolved";
	variables.BROWSE_URL   = "https://luceeserver.atlassian.net/browse/";

	public function init(required util) {
		variables.util = arguments.util;
		return this;
	}

	public string function browseUrl(key) {
		return variables.BROWSE_URL & arguments.key;
	}

	// Version → zero-padded sortable string (mirrors Lucee's VersionUtils.toVersionSortable).
	// Returns "" for anything that is not a 4-part version, so callers can skip it.
	public string function toSortable(version) {
		var arr = listToArray(listFirst(arguments.version, "-"), ".");
		if (arrayLen(arr) != 4) return "";
		for (var p in arr) if (!isNumeric(p)) return "";
		var suffix = find("-", arguments.version) ? listLast(arguments.version, "-") : "";
		var appNbr = 100; // no suffix = final release, ranks highest
		switch (uCase(suffix)) {
			case "":         appNbr = 100; break;
			case "SNAPSHOT": appNbr = 0;   break;
			case "BETA":     appNbr = 50;  break;
			default:         appNbr = 75;  // RC and anything else beats SNAPSHOT/BETA
		}
		return numberFormat(arr[1], "00") & "." & numberFormat(arr[2], "000") & "."
			 & numberFormat(arr[3], "000") & "." & numberFormat(val(listFirst(arr[4], "-")), "0000")
			 & "." & numberFormat(appNbr, "000");
	}

	// The release immediately older than versionTo within the same minor line (falls back to the
	// next older release overall). This is the lower bound (exclusive) of the changelog range.
	public string function previousRelease(versionTo) {
		var all   = variables.util.getLuceeVersionsDetail();       // order not guaranteed
		var toS    = toSortable(arguments.versionTo);
		var minor  = variables.util.getMinor(arguments.versionTo);
		// newest release strictly older than versionTo, preferring the same minor line
		var bestSameMinor = ""; var bestSameMinorS = "";
		var bestOverall   = ""; var bestOverallS   = "";
		for (var v in all) {
			if (variables.util.getType(v) != "release") continue;
			var vs = toSortable(v);
			if (!len(vs) || vs >= toS) continue;                    // only strictly older releases
			if (vs > bestOverallS) { bestOverallS = vs; bestOverall = v; }
			if (variables.util.getMinor(v) == minor && vs > bestSameMinorS) { bestSameMinorS = vs; bestSameMinor = v; }
		}
		return len(bestSameMinor) ? bestSameMinor : bestOverall;
	}

	// LDEV fixVersion names, cached 60-min stale-while-revalidate.
	public array function projectVersionNames() {
		var key    = "jiraVersions_" & variables.JIRA_PROJECT;
		var cached = variables.util.dlCacheGet(key);
		var data   = cached.data ?: [];
		var age    = structKeyExists(cached, "cachedAt") ? dateDiff("n", cached.cachedAt, now()) : 999;
		if (!arrayIsEmpty(data)) {
			if (age >= 60) {
				thread action="run" name="refresh-jiraversions-#getTickCount()#" ckey=key {
					try {
						local.names = _fetchProjectVersionNames();
						if (!arrayIsEmpty(local.names)) variables.util.dlCachePut(attributes.ckey, { data: local.names, cachedAt: now() });
					} catch(e) { cflog(log:"application", exception:e, type:"error"); }
				}
			}
			return data;
		}
		try {
			data = _fetchProjectVersionNames();
			if (!arrayIsEmpty(data)) variables.util.dlCachePut(key, { data: data, cachedAt: now() });
		} catch(e) { cflog(log:"application", exception:e, type:"error"); }
		return data;
	}

	private array function _fetchProjectVersionNames() {
		var endpoint = "https://" & variables.JIRA_HOST & "/rest/api/3/project/" & variables.JIRA_PROJECT & "/versions";
		cfhttp(method="GET", url=endpoint, result="local.res", throwOnError=false) {
			cfhttpparam(type="header", name="Accept", value="application/json");
		}
		if (local.res.statusCode != "200 OK") throw(type="Jira.HTTP", message=local.res.statusCode);
		var arr   = deserializeJSON(local.res.fileContent);
		var names = [];
		for (var v in arr) if (structKeyExists(v, "name")) arrayAppend(names, v.name);
		return names;
	}

	/**
	 * Changelog for a version: { version, from, tickets:[ {key,summary,type,fixVersions[]} ] }.
	 * The tickets that shipped in a given version never change, so every version is cached once
	 * and then served from cache forever — a specific version is only ever built from Jira once.
	 * The only thing not cached is a result built while the Jira version list was unavailable
	 * (marked incomplete), so a transient outage cannot permanently poison a version with an
	 * empty changelog.
	 */
	public struct function getChangelog(versionTo) {
		var key    = "changelog_" & arguments.versionTo;
		var cached = variables.util.dlCacheGet(key);
		if (!isEmpty(cached) && structKeyExists(cached, "version")) return cached;

		var result = _buildChangelog(arguments.versionTo);
		if (!(result.incomplete ?: false)) {
			result.cachedAt = now();
			variables.util.dlCachePut(key, result);
		}
		return result;
	}

	private struct function _buildChangelog(versionTo) {
		var from  = previousRelease(arguments.versionTo);
		var toS    = toSortable(arguments.versionTo);
		var fromS  = len(from) ? toSortable(from) : "00.000.000.0000.000";
		var out    = { version: arguments.versionTo, from: from, tickets: [], incomplete: false };
		if (!len(toS)) return out;

		// build versions in (from, to] — if the Jira version list is unavailable, flag the
		// result as incomplete so the caller does not cache this (otherwise a transient Jira
		// outage would permanently cache an empty changelog for this version)
		var names = projectVersionNames();
		if (arrayIsEmpty(names)) { out.incomplete = true; return out; }
		var inRange = [];
		for (var n in names) {
			var ns = toSortable(n);
			if (len(ns) && ns > fromS && ns <= toS) arrayAppend(inRange, n);
		}
		if (arrayIsEmpty(inRange)) return out;

		var jql = "project=" & variables.JIRA_PROJECT & " AND status in (" & variables.JIRA_STATUS
				& ") AND fixVersion in (" & arrayToList(arrayMap(inRange, function(n){ return '"' & n & '"'; }), ",") & ")";
		var rangeLookup = {};
		for (var n in inRange) rangeLookup[n] = true;

		var seen = {};
		for (var issue in _searchIssues(jql)) {
			if (structKeyExists(seen, issue.key)) continue;
			seen[issue.key] = true;
			var fvs = [];
			for (var fv in (issue.fields.fixVersions ?: [])) {
				if (structKeyExists(rangeLookup, fv.name ?: "")) arrayAppend(fvs, fv.name);
			}
			arraySort(fvs, function(a,b){ return compare(toSortable(b), toSortable(a)); });
			arrayAppend(out.tickets, {
				key:         issue.key,
				summary:     issue.fields.summary ?: "",
				type:        issue.fields.issuetype.name ?: "",
				fixVersions: fvs
			});
		}
		// newest fix first, then ticket id
		arraySort(out.tickets, function(a,b){
			var av = arrayLen(a.fixVersions) ? toSortable(a.fixVersions[1]) : "";
			var bv = arrayLen(b.fixVersions) ? toSortable(b.fixVersions[1]) : "";
			if (av != bv) return compare(bv, av);
			return compareNoCase(b.key, a.key);
		});
		return out;
	}

	private array function _searchIssues(jql) {
		var endpoint = "https://" & variables.JIRA_HOST & "/rest/api/3/search/jql";
		var all    = [];
		var token  = "";
		var page   = 0;
		do {
			// quoted keys keep their lowercase spelling — Jira's /search/jql rejects the payload
			// if the keys arrive upper-cased (which unquoted struct keys would be)
			var body = { "jql": arguments.jql, "fields": ["summary","issuetype","fixVersions"], "maxResults": 200 };
			if (len(token)) body["nextPageToken"] = token;
			cfhttp(method="POST", url=endpoint, result="local.res", throwOnError=false) {
				cfhttpparam(type="header", name="Accept",       value="application/json");
				cfhttpparam(type="header", name="Content-Type", value="application/json");
				cfhttpparam(type="body",   value=serializeJSON(body));
			}
			if (local.res.statusCode != "200 OK") throw(type="Jira.HTTP", message=local.res.statusCode, detail=local.res.fileContent);
			var data = deserializeJSON(local.res.fileContent);
			if (isArray(data.issues ?: "")) arrayAppend(all, data.issues, true);
			token = data.nextPageToken ?: "";
			page++;
		} while (len(token) && page < 20);
		return all;
	}

}
