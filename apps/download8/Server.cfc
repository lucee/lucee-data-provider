component {

	private void function cachePut(string key, any value) {
		application[arguments.key] = arguments.value;
		local.dir = application["__cacheDir"] ?: "";
		if (!len(local.dir)) return;
		try {
			fileWrite(local.dir & server.separator.file & arguments.key & ".json", serializeJSON(arguments.value));
		} catch(e) {}
	}

	private any function cacheGet(string key) {
		local.val = application[arguments.key] ?: {};
		if (!isEmpty(local.val)) return local.val;
		local.dir  = application["__cacheDir"] ?: "";
		if (!len(local.dir)) return {};
		local.file = local.dir & server.separator.file & arguments.key & ".json";
		if (fileExists(local.file)) {
			try {
				local.val = deserializeJSON(fileRead(local.file));
				application[arguments.key] = local.val;
				return local.val;
			} catch(e) {}
		}
		return {};
	}

	remote function onServerStart( boolean reload = false ) {
		systemOutput("onServerStart: warming caches", true, true);

		// resolve cache directory — must match what index.cfm computes
		local.cacheDir = server.system.environment.CACHE_DIRECTORY ?: "";
		if (!len(local.cacheDir)) {
			// default: parent of www/ = apps/download8/
			local.cacheDir = getDirectoryFromPath(getCurrentTemplatePath());
		}
		if (right(local.cacheDir, 1) == server.separator.file)
			local.cacheDir = left(local.cacheDir, len(local.cacheDir) - 1);
		application["__cacheDir"] = local.cacheDir;
		if (!directoryExists(local.cacheDir)) directoryCreate(local.cacheDir, true, true);

		thread action="run" name="cache-warmup" {
			try {
				// ── Lucee versions list ──────────────────────────────────────
				try {
					local.versions = LuceeVersionsList();
					cachePut("luceeVersionsList", { data: local.versions, cachedAt: now() });
					systemOutput("cache warm: luceeVersionsList (#arrayLen(local.versions)# versions)", true);
				} catch(e) {
					systemOutput("cache warm fail: luceeVersionsList — #e.message#", true);
					local.versions = [];
				}

				// ── Extension metadata (name, image, latest version) ─────────
				for (local.groupId in ["org.lucee", "io.forgebox"]) {
					try {
						local.artifacts = LuceeExtension(local.groupId);
						for (local.artifactId in local.artifacts) {
							thread action="run"
								name = "warm-ext-#local.groupId#-#local.artifactId#"
								gid  = local.groupId
								aid  = local.artifactId {
								try {
									local.cacheKey = "extMeta_" & attributes.gid & "_" & attributes.aid;
									if (!isEmpty(cacheGet(local.cacheKey))) return;
									local.vers = LuceeExtension(attributes.gid, attributes.aid);
									local.vers = local.vers.filter(function(v) {
										return !findNoCase("-alpha", lCase(v));
									});
									if (arrayIsEmpty(local.vers)) return;
									arraySort(local.vers, function(a, b) {
										local.a = listToArray(listFirst(a,"-"), ".");
										local.b = listToArray(listFirst(b,"-"), ".");
										local.len = max(arrayLen(local.a), arrayLen(local.b));
										for (local.i = 1; local.i <= local.len; local.i++) {
											local.n1 = val(local.a[local.i] ?: "0");
											local.n2 = val(local.b[local.i] ?: "0");
											if (local.n1 > local.n2) return -1;
											if (local.n1 < local.n2) return 1;
										}
										return 0;
									});
									local.pickVer = local.vers[1];
									local.meta    = LuceeExtension(attributes.gid, attributes.aid, local.pickVer, true);
									cachePut(local.cacheKey, {
										displayName:   local.meta.metadata.name  ?: "",
										image:         local.meta.metadata.image ?: "",
										latestVersion: local.pickVer,
										cachedAt:      now()
									});
									local.verKey = "extVer_" & attributes.gid & "_" & attributes.aid & "_" & local.pickVer;
									if (isEmpty(cacheGet(local.verKey))) {
										cachePut(local.verKey, {
											version:      local.meta.version      ?: local.pickVer,
											lastModified: local.meta.lastModified ?: "",
											type:         !findNoCase("-", local.pickVer) ? "release" : listLast(lCase(local.pickVer), "-"),
											minCore:      local.meta.metadata.MinCoreVersion ?: ""
										});
									}
									systemOutput("cache warm: #attributes.gid#:#attributes.aid# (#local.pickVer#)", true);
								} catch(e) {
									systemOutput("cache warm fail: #attributes.gid#:#attributes.aid# — #e.message#", true);
								}
							}
						}
					} catch(e) {
						systemOutput("cache warm fail: group #local.groupId# — #e.message#", true);
					}
				}
			} catch(e) {
				systemOutput("cache warmup failed: #e.message#", true);
			}
		}
	}

}
