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
		} 
		catch(e) {
			cflog(log:"application",exception:e,type:"error");
		}
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

	// ── Extension images ─────────────────────────────────────────────────

	// Resolve a rate-limited raw.githubusercontent.com logo URL to Lucee's own artifact
	// CDN. Keyed by maven coordinates (repo/branch-agnostic); anything else is returned
	// unchanged. Called both when caching metadata and defensively at render time, so a
	// stale github URL cached before the CDN migration never reaches the browser.
	public string function githubRawToCdn(groupId, artifactId, image) {
		if (findNoCase("raw.githubusercontent.com/", arguments.image ?: ""))
			return this.CDN & "artifacts/" & replace(arguments.groupId, ".", "-", "all") & "-" & replace(arguments.artifactId, ".", "-", "all") & ".png";
		return arguments.image ?: "";
	}

	// A pom <image> may be a relative "./<artifactId>-<version>-logo.png" pointing at a logo
	// deployed as a maven artifact next to the .lex. Resolve it against the .lex's maven
	// directory so it is host-agnostic (follows whatever mirror serves the extension). If
	// there is no usable base URL, fall back to the artifact CDN. Non-relative values pass
	// through unchanged.
	public string function resolveRelativeImage(groupId, artifactId, image, base) {
		if (left(arguments.image ?: "", 2) != "./") return arguments.image ?: "";
		if (left(arguments.base ?: "", 4) == "http")
			return mid(arguments.base, 1, len(arguments.base) - len(listLast(arguments.base, "/"))) & listLast(arguments.image, "/");
		return this.CDN & "artifacts/" & replace(arguments.groupId, ".", "-", "all") & "-" & replace(arguments.artifactId, ".", "-", "all") & ".png";
	}

	// Converts a raw image value to a web-accessible URL.
	// If already a URL, returns it unchanged.
	// If base64, writes to /downloads/ (persistent) and copies to webroot, returns the path.
	public string function toImageReference(groupId, artifactId, image) {
		if (!len(arguments.image)) return "";
		arguments.image = githubRawToCdn(arguments.groupId, arguments.artifactId, arguments.image);
		if (left(arguments.image, 1) == "/" || left(arguments.image, 4) == "http") return arguments.image;

		var filename    = "logo-" & replace(arguments.groupId, ".", "-", "all") & "-" & replace(arguments.artifactId, ".", "-", "all") & ".png";
		var storagePath = getCacheDirectory()& "/" & filename;
		var webrootPath = "/var/www/" & filename;
		lock name="imgwrite-#filename#" type="exclusive" timeout="30" {
			if (!fileExists(storagePath)) {
				var b64 = arguments.image;
				if (find(",", b64)) b64 = listLast(b64, ",");
				var img     = ImageReadBase64(b64);
				var maxSize = 128;
				var info    = ImageInfo(img);
				if (info.width > maxSize || info.height > maxSize) {
					if (info.width >= info.height)
						ImageResize(img, maxSize, "");
					else
						ImageResize(img, "", maxSize);
				}
				ImageWrite(img, storagePath, 1, true);
			}
			if (!fileExists(webrootPath)) fileCopy(storagePath, webrootPath);
		}

		return "/" & filename;
	}

	// ── Three-tier cache: component variables → file → fetch ─────────────

	public string function getCacheDirectory() {
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

	public string function getCacheFile(sourceTemplate, queryString="") {
		var dir = getCacheDirectory();
		if(right(dir,1) != server.separator.file) dir &= server.separator.file;
		var filename=sourceTemplate&"_"&arguments.queryString;
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
			} catch(e) {
				cflog(log:"application",exception:e,type:"error");
			}
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
			} catch(e) {
				cflog(log:"application",exception:e,type:"error");
			}
		}
	}

	// ── Lucee versions API (cached) ──────────────────────────────────────

	// If any download URL in the detail is a Sonatype snapshot with a build timestamp
	// (…-YYYYMMDD.HHMMSS-N.<ext>), return the epoch ms at which Sonatype purges it — the
	// timestamp date + 89 days (90-day retention, minus a day of safety margin). Returns
	// null when there is no such timestamp (e.g. a release from the permanent CDN), meaning
	// "cache forever".
	private function snapshotUrlExpiry(detail) {
		for (var k in arguments.detail) {
			if (!isSimpleValue(arguments.detail[k])) continue;
			var m = reFind("-([0-9]{8})\.[0-9]{6}-[0-9]+\.", arguments.detail[k], 1, true);
			if (arrayLen(m.pos) >= 2 && m.pos[2] > 0) {
				var ymd = mid(arguments.detail[k], m.pos[2], m.len[2]);
				var d   = createDate(val(mid(ymd, 1, 4)), val(mid(ymd, 5, 2)), val(mid(ymd, 7, 2)));
				return dateAdd("d", 89, d).getTime();
			}
		}
		// no timestamp found → permanent (returns null)
	}

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
						} catch(e) {
							cflog(log:"application",exception:e,type:"error");
						}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try {
				local.data = LuceeVersionsList();
				info("reading data from function LuceeVersionsList() took #getTickCount()-local.t#ms");
				dlCachePut("luceeVersionsList", { data: local.data, cachedAt: now() });
			} catch(e) {
				local.data = [];
				cflog(log:"application",exception:e,type:"error");
			}
			return local.data;
		} else {
			// single version detail. Releases are immutable → cache forever. A snapshot resolves
			// to a Sonatype timestamped URL (lucee-<ver>-YYYYMMDD.HHMMSS-N.<ext>) that Sonatype
			// purges ~90 days after that timestamp, so cache only until (timestamp + 89 days) and
			// re-resolve after that rather than serving a URL that is about to 404.
			local.key    = "luceeVerDetail_" & arguments.version;
			local.cached = dlCacheGet(local.key);
			if (!isEmpty(local.cached) && structKeyExists(local.cached, "data")
				&& (!structKeyExists(local.cached, "expiresAt") || now().getTime() < local.cached.expiresAt))
				return local.cached.data;
			local.t = getTickCount();
			try {
				local.detail = LuceeVersionsDetail(arguments.version);
				info("reading data from function LuceeVersionsDetail(#arguments.version#) took #getTickCount()-local.t#ms");
				local.entry = { data: local.detail };
				local.exp   = snapshotUrlExpiry(local.detail);
				if (!isNull(local.exp)) local.entry.expiresAt = local.exp;
				dlCachePut(local.key, local.entry);
				return local.detail;
			} catch(e) {
				cflog(log:"application",exception:e,type:"error");
				return {};
			}
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
							// never cache an empty result: 0 artifacts means the scan failed, not that the group is empty
							if (!arrayIsEmpty(local.list)) dlCachePut(attributes.ckey, { data: local.list, cachedAt: now() });
						} catch(e) {
							cflog(log:"application",exception:e,type:"error");
						}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try {
				local.data = LuceeExtension(arguments.groupId);
				info("reading data from function LuceeExtension(#arguments.groupId#) took #getTickCount()-local.t#ms");
				// never cache an empty result: 0 artifacts means the scan failed, not that the group is empty
				if (!arrayIsEmpty(local.data)) dlCachePut(local.key, { data: local.data, cachedAt: now() });
			} catch(e) {
				local.data = [];
				cflog(log:"application",exception:e,type:"error");
			}
			return local.data;

		} else if (isNull(arguments.version)) {
			// version list for artifact — 10-min stale-while-revalidate, alpha-filtered and sorted desc
			local.key    = "extver_" & arguments.groupId & "_" & arguments.artifactId;
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
							// never cache an empty result: 0 versions means the scan failed, not that the extension has none
							if (!arrayIsEmpty(local.list)) dlCachePut(attributes.ckey, { data: local.list, cachedAt: now() });
						} catch(e) {
							cflog(log:"application",exception:e,type:"error");
						}
					}
				}
				return local.data;
			}
			local.t = getTickCount();
			try {
				local.data = LuceeExtension(arguments.groupId, arguments.artifactId);
				info("reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#) took #getTickCount()-local.t#ms");
				local.na = local.data.filter(function(v) { return !findNoCase("-alpha", lCase(v)); });
				if (!arrayIsEmpty(local.na)) local.data = local.na;
				arraySort(local.data, function(a,b) { return versionCompare(b,a); });
				// never cache an empty result: 0 versions means the scan failed, not that the extension has none
				if (!arrayIsEmpty(local.data)) dlCachePut(local.key, { data: local.data, cachedAt: now() });
			} catch(e) {
				local.data = [];
				cflog(log:"application",exception:e,type:"error");
			}
			return local.data;

		} else {
			// version detail — immutable, cache indefinitely
			local.key    = "extdata_" & arguments.groupId & "_" & arguments.artifactId & "_" & arguments.version;
			local.cached = dlCacheGet(local.key);
			if (!isEmpty(local.cached)) return local.cached;
			local.t = getTickCount();
			try {
				local.meta = LuceeExtension(arguments.groupId, arguments.artifactId, arguments.version, arguments.download);
				info("reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#,#arguments.version#,#arguments.download#) took #getTickCount()-local.t#ms");
				if (structKeyExists(local.meta, "metadata") && len(local.meta.metadata.image ?: "")) {
					// resolve a relative "./...-logo.png" (maven logo artifact) against the .lex dir first
					local.meta.metadata.image = resolveRelativeImage(arguments.groupId, arguments.artifactId, local.meta.metadata.image, local.meta.lex ?: (local.meta.pom ?: ""));
					local.meta.metadata.image = toImageReference(arguments.groupId, arguments.artifactId, local.meta.metadata.image);
				}
				dlCachePut(local.key, local.meta);
				return local.meta;
			} catch(e) {cflog(log:"application",exception:e,type:"error"); return {}; }
		}
	}

	// ── Cache warmup ─────────────────────────────────────────────────────

	function warmup() {
		thread action="run" name="cache-warmup" {
			try {
				// Restore extension logos to the webroot; the webroot is wiped on redeploy,
				// but cached metadata keeps referencing /logo-*.png (only the cache dir persists)
				try {
					local.restored = 0;
					for (local.png in directoryList(getCacheDirectory(), false, "path", "logo-*.png")) {
						local.target = "/var/www/" & getFileFromPath(local.png);
						if (!fileExists(local.target)) {
							fileCopy(local.png, local.target);
							local.restored++;
						}
					}
					if (local.restored) info("cache warm: restored #local.restored# extension logo(s) to webroot");
				} catch(e) {
					info("cache warm fail: logo restore — #e.message#");
				}

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
						local.artifacts  = getLuceeExtension(local.groupId);
						local.metaMapKey = "extMetaMap_" & local.groupId;
						local.metaMap    = dlCacheGet(local.metaMapKey);
						if (isEmpty(local.metaMap)) local.metaMap = {};

						arrayEach(local.artifacts, function(artifactId) {
							if (structKeyExists(metaMap, artifactId)) return;
							try {
								local.vers = getLuceeExtension(groupId, artifactId);
								if (arrayIsEmpty(local.vers)) return;
								local.pickVer = local.vers[1];
								local.meta    = getLuceeExtension(groupId, artifactId, local.pickVer, true);
								local.entry   = {
									displayName:   local.meta.metadata.name  ?: "",
									image:         local.meta.metadata.image ?: "",
									latestVersion: local.pickVer,
									cachedAt:      now()
								};
								local.verMapKey = "extVerMap_" & groupId & "_" & artifactId;
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
								lock name="extMetaMap_#groupId#" type="exclusive" timeout="10" {
									metaMap[artifactId] = local.entry;
								}
								info("cache warm: #groupId#:#artifactId# (#local.pickVer#)");
							} catch(e) {
								info("cache warm fail: #groupId#:#artifactId# — #e.message#");
							}
						}, false); // serial on purpose: each LuceeExtension() call scans 4 mirrors
						            // concurrently and downloads the version .pom/.lex. Fanning these out
						            // in parallel saturates Lucee's in-JVM HTTP client (the mirrors
						            // themselves don't rate-limit), so scans time out and the BIF returns —
						            // and internally caches — an empty version list. Serial keeps
						            // client-side concurrency bounded so a cold warmup resolves cleanly.

						dlCachePut(metaMapKey, metaMap);
						info("cache warm: extMetaMap_#groupId# (#structCount(metaMap)# extensions)");
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
