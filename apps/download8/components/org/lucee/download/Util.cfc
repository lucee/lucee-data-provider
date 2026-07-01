component accessors="false" {

	this.CDN = "https://cdn.lucee.org/";

	this.DL_INFO = {
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

	// cache storage lives in the component instance (application scope via application.util)
	variables.cache    = {};
	variables.cacheDir = "";

	// ── Version helpers ───────────────────────────────────────────────────

	function getMinor(ver) {
		local.base  = listFirst(ver, "-");
		local.parts = listToArray(local.base, ".");
		if (arrayLen(local.parts) >= 2) return local.parts[1] & "." & local.parts[2];
		return "";
	}

	function getType(ver) {
		local.v = lCase(ver);
		if (findNoCase("-snapshot", local.v)) return "snapshot";
		if (findNoCase("-beta",     local.v)) return "beta";
		if (findNoCase("-alpha",    local.v)) return "alpha";
		if (findNoCase("-rc",       local.v)) return "rc";
		return "release";
	}

	function formatVersion(ver) {
		return listFirst(ver, "-");
	}

	function parseDate(dateStr) {
		try {
			if (len(trim(dateStr))) return dateFormat(parseDateTime(dateStr), "mmm d, yyyy");
		} catch(e) {}
		return "";
	}

	function artifactDisplayName(artifactId) {
		local.words  = listToArray(artifactId, "-");
		local.result = [];
		for (local.w in local.words) {
			arrayAppend(local.result, uCase(left(local.w, 1)) & lCase(right(local.w, len(local.w)-1)));
		}
		return arrayToList(local.result, " ");
	}

	function versionCompare(v1, v2) {
		local.a   = listToArray(listFirst(v1,"-"), ".");
		local.b   = listToArray(listFirst(v2,"-"), ".");
		local.len = max(arrayLen(local.a), arrayLen(local.b));
		for (local.i = 1; local.i <= local.len; local.i++) {
			local.n1 = val(local.a[local.i] ?: "0");
			local.n2 = val(local.b[local.i] ?: "0");
			if (local.n1 > local.n2) return 1;
			if (local.n1 < local.n2) return -1;
		}
		return 0;
	}

	function cdnLinks(ver) {
		return {
			win64:           this.CDN & "lucee-" & ver & "-windows-x64-installer.exe",
			"linux-x64":     this.CDN & "lucee-" & ver & "-linux-x64-installer.run",
			"linux-aarch64": this.CDN & "lucee-" & ver & "-linux-aarch64-installer.run",
			express:         this.CDN & "lucee-express-" & ver & ".zip",
			jar:             this.CDN & "lucee-" & ver & ".jar",
			light:           this.CDN & "lucee-light-" & ver & ".jar",
			lco:             this.CDN & ver & ".lco",
			war:             this.CDN & "lucee-" & ver & ".war"
		};
	}

	// ── Three-tier cache: component variables → file → fetch ─────────────

	private string function getCacheDirectory() {
		if (len(variables.cacheDir)) return variables.cacheDir;
		local.dir = server.system.environment.CACHE_DIRECTORY ?: "";
		if (!len(local.dir)) {
			// default: /var/cache (alongside /var/www and /var/components)
			local.dir = "/var/cache";
		}
		if (!directoryExists(local.dir)) directoryCreate(local.dir, true, true);
		variables.cacheDir = local.dir;
		return local.dir;
	}

	public string function getCacheFile(sourceTemplate) {
		var dir = getCacheDirectory();
		if(right(dir,1) != server.separator.file) dir &= server.separator.file;
		var filename=sourceTemplate&"_"&cgi.QUERY_STRING;
		var filename=dir&"site"&replace(replace(replace(replace(filename,"=","_","all"),"&","_","all"),".","_","all"),"/","_","all")&".html";
		return filename;
	}

	function dlCacheGet(key) {
		local.t = getTickCount();
		// 1. component variables
		if (structKeyExists(variables.cache, key)) {
			info("reading data from memory [#key#] took #getTickCount()-local.t#ms");
			return variables.cache[key];
		}
		// 2. file
		local.file = getCacheDirectory() & server.separator.file & key & ".json";
		if (fileExists(local.file)) {
			try {
				local.val = deserializeJSON(fileRead(local.file));
				variables.cache[key] = local.val;
				info("reading data from file [#local.file#] took #getTickCount()-local.t#ms");
				return local.val;
			} catch(e) {}
		}
		return {};
	}

	function dlCachePut(key, value) {
		variables.cache[key] = value;
		local.file = getCacheDirectory() & server.separator.file & key & ".json";
		local.json = serializeJSON(value);
		lock name="dlCachePut_#key#" type="exclusive" timeout="5" {
			try {
				fileWrite(local.file, local.json);
			} catch(e) {}
		}
	}

	// ── Lucee versions API (cached) ──────────────────────────────────────

	function getLuceeVersionsDetail(version) {
		if (isNull(arguments.version)) {
			// versions list with stale-while-revalidate (5 min)
			local.cached = dlCacheGet("luceeVersionsList");
			local.data   = local.cached.data ?: [];
			local.age    = structKeyExists(local.cached, "cachedAt") ? dateDiff("n", local.cached.cachedAt, now()) : 999;
			if (!arrayIsEmpty(local.data)) {
				if (local.age >= 5) {
					thread action="run" name="refresh-versions-list-#getTickCount()#" {
						local.t = getTickCount();
						try {
							local.list = LuceeVersionsList();
							info("reading data from function LuceeVersionsList() took #getTickCount()-local.t#ms");
							dlCachePut("luceeVersionsList", { data: local.list, cachedAt: now() });
						} catch(e) {}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try { local.data = LuceeVersionsList(); } catch(e) { local.data = []; }
			info("reading data from function LuceeVersionsList() took #getTickCount()-local.t#ms");
			dlCachePut("luceeVersionsList", { data: local.data, cachedAt: now() });
			return local.data;
		} else {
			// single version detail — version data is immutable, cache indefinitely
			local.key    = "luceeVerDetail_" & arguments.version;
			local.cached = dlCacheGet(local.key);
			if (!isEmpty(local.cached)) return local.cached;
			local.t = getTickCount();
			try {
				local.detail = LuceeVersionsDetail(arguments.version);
				info("reading data from function LuceeVersionsDetail(#arguments.version#) took #getTickCount()-local.t#ms");
				dlCachePut(local.key, local.detail);
				return local.detail;
			} catch(e) { return {}; }
		}
	}

	// ── LuceeExtension API (cached) ─────────────────────────────────────

	function getLuceeExtension(groupId, artifactId, version, download=false) {
		if (isNull(arguments.artifactId)) {
			// artifact list for group — 10-min stale-while-revalidate
			local.key    = "extArtifacts_" & arguments.groupId;
			local.cached = dlCacheGet(local.key);
			local.data   = local.cached.data ?: [];
			local.age    = structKeyExists(local.cached, "cachedAt") ? dateDiff("n", local.cached.cachedAt, now()) : 999;
			if (!arrayIsEmpty(local.data)) {
				if (local.age >= 10) {
					thread action="run" name="refresh-extartifacts-#arguments.groupId#-#getTickCount()#"
						gid=arguments.groupId ckey=local.key {
						local.t = getTickCount();
						try {
							local.list = LuceeExtension(attributes.gid);
							info("reading data from function LuceeExtension(#attributes.gid#) took #getTickCount()-local.t#ms");
							dlCachePut(attributes.ckey, { data: local.list, cachedAt: now() });
						} catch(e) {}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try { local.data = LuceeExtension(arguments.groupId); } catch(e) { local.data = []; }
			info("reading data from function LuceeExtension(#arguments.groupId#) took #getTickCount()-local.t#ms");
			dlCachePut(local.key, { data: local.data, cachedAt: now() });
			return local.data;

		} else if (isNull(arguments.version)) {
			// version list for artifact — 10-min stale-while-revalidate, alpha-filtered and sorted desc
			local.key    = "extVersions_" & arguments.groupId & "_" & arguments.artifactId;
			local.cached = dlCacheGet(local.key);
			local.data   = local.cached.data ?: [];
			local.age    = structKeyExists(local.cached, "cachedAt") ? dateDiff("n", local.cached.cachedAt, now()) : 999;
			if (!arrayIsEmpty(local.data)) {
				if (local.age >= 10) {
					thread action="run" name="refresh-extver-#arguments.groupId#-#arguments.artifactId#-#getTickCount()#"
						gid=arguments.groupId aid=arguments.artifactId ckey=local.key {
						local.t = getTickCount();
						try {
							local.list = LuceeExtension(attributes.gid, attributes.aid);
							info("reading data from function LuceeExtension(#attributes.gid#,#attributes.aid#) took #getTickCount()-local.t#ms");
							local.na = local.list.filter(function(v) { return !findNoCase("-alpha", lCase(v)); });
							if (!arrayIsEmpty(local.na)) local.list = local.na;
							arraySort(local.list, function(a,b) { return versionCompare(b,a); });
							dlCachePut(attributes.ckey, { data: local.list, cachedAt: now() });
						} catch(e) {}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try { local.data = LuceeExtension(arguments.groupId, arguments.artifactId); } catch(e) { local.data = []; }
			info("reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#) took #getTickCount()-local.t#ms");
			local.na = local.data.filter(function(v) { return !findNoCase("-alpha", lCase(v)); });
			if (!arrayIsEmpty(local.na)) local.data = local.na;
			arraySort(local.data, function(a,b) { return versionCompare(b,a); });
			dlCachePut(local.key, { data: local.data, cachedAt: now() });
			return local.data;

		} else {
			// version detail — immutable, cache indefinitely
			local.key    = "extRaw_" & arguments.groupId & "_" & arguments.artifactId & "_" & arguments.version;
			local.cached = dlCacheGet(local.key);
			if (!isEmpty(local.cached)) return local.cached;
			local.t = getTickCount();
			try {
				local.meta = LuceeExtension(arguments.groupId, arguments.artifactId, arguments.version, arguments.download);
				info("reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#,#arguments.version#,#arguments.download#) took #getTickCount()-local.t#ms");
				dlCachePut(local.key, local.meta);
				return local.meta;
			} catch(e) { return {}; }
		}
	}

	// ── Cache warmup ─────────────────────────────────────────────────────

	function warmup() {
		thread action="run" name="cache-warmup" {
			try {
				// Lucee versions list
				try {
					local.versions = getLuceeVersionsDetail();
					info("cache warm: luceeVersionsList (#arrayLen(local.versions)# versions)");
				} catch(e) {
					info("cache warm fail: luceeVersionsList — #e.message#");
				}

				// Extension metadata (name, image, latest version)
				for (local.groupId in ["org.lucee", "io.forgebox"]) {
					try {
						local.artifacts   = getLuceeExtension(local.groupId);
						local.metaMapKey  = "extMetaMap_" & local.groupId;
						local.metaMap     = dlCacheGet(local.metaMapKey);
						if (isEmpty(local.metaMap)) local.metaMap = {};
						local.threadNames = {};

						for (local.artifactId in local.artifacts) {
							if (structKeyExists(local.metaMap, local.artifactId)) continue;
							local.tname = "warm-ext-#local.groupId#-#local.artifactId#";
							local.threadNames[local.artifactId] = local.tname;
							thread action="run"
								name = local.tname
								gid  = local.groupId
								aid  = local.artifactId {
								try {
									local.vers = getLuceeExtension(attributes.gid, attributes.aid);
									if (arrayIsEmpty(local.vers)) return;
									local.pickVer = local.vers[1];
									local.meta    = getLuceeExtension(attributes.gid, attributes.aid, local.pickVer, true);
									thread.entry  = {
										displayName:   local.meta.metadata.name  ?: "",
										image:         local.meta.metadata.image ?: "",
										latestVersion: local.pickVer,
										cachedAt:      now()
									};
									local.verMapKey = "extVerMap_" & attributes.gid & "_" & attributes.aid;
									local.verMap    = dlCacheGet(local.verMapKey);
									if (isEmpty(local.verMap)) local.verMap = {};
									if (!structKeyExists(local.verMap, local.pickVer)) {
										local.verMap[local.pickVer] = {
											version:      local.meta.version      ?: local.pickVer,
											lastModified: local.meta.lastModified ?: "",
											type:         !findNoCase("-", local.pickVer) ? "release" : listLast(lCase(local.pickVer), "-"),
											minCore:      local.meta.metadata.MinCoreVersion ?: ""
										};
										dlCachePut(local.verMapKey, local.verMap);
									}
									info("cache warm: #attributes.gid#:#attributes.aid# (#local.pickVer#)");
								} catch(e) {
									info("cache warm fail: #attributes.gid#:#attributes.aid# — #e.message#");
								}
							}
						}

						// Join all artifact threads and write consolidated map once
						for (local.artifactId in structKeyArray(local.threadNames)) {
							local.tname = local.threadNames[local.artifactId];
							cfthread(action="join", name=local.tname, timeout=120000);
							try {
								if (!isNull(cfthread[local.tname].entry))
									local.metaMap[local.artifactId] = cfthread[local.tname].entry;
							} catch(e) {}
						}
						dlCachePut(local.metaMapKey, local.metaMap);
						info("cache warm: extMetaMap_#local.groupId# (#structCount(local.metaMap)# extensions)");
					} catch(e) {
						info("cache warm fail: group #local.groupId# — #e.message#");
					}
				}
			} catch(e) {
				info("cache warmup failed: #e.message#");
			}
		}
	}

	function info(msg) {
		cflog(log:"application",type:"info",text:msg);
	}
}
