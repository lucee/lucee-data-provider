component {

	remote function onServerStart( boolean reload = false ) {
		systemOutput("onServerStart: warming caches", true, true);
		thread action="run" name="cache-warmup" {
			try {
				// ── Lucee versions list ──────────────────────────────────────
				try {
					local.versions = LuceeVersionsList();
					application["luceeVersionsList"] = { data: local.versions, cachedAt: now() };
					systemOutput("cache warm: luceeVersionsList (#arrayLen(local.versions)# versions)", true);
				} catch(e) {
					systemOutput("cache warm fail: luceeVersionsList — #e.message#", true);
					local.versions = [];
				}

				// ── Extension metadata (name, image, latest version) ─────────
				// One thread per extension, fetch only the latest version with download=true
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
									// skip if already cached from a previous warm or request
									if (!isEmpty(application[local.cacheKey] ?: {})) {
										return;
									}
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
									application[local.cacheKey] = {
										displayName:   local.meta.metadata.name  ?: "",
										image:         local.meta.metadata.image ?: "",
										latestVersion: local.pickVer,
										cachedAt:      now()
									};
									// also warm the per-version detail cache for the latest
									local.verKey = "extVer_" & attributes.gid & "_" & attributes.aid & "_" & local.pickVer;
									if (isEmpty(application[local.verKey] ?: {})) {
										local.verMinCore = local.meta.metadata.MinCoreVersion ?: "";
										application[local.verKey] = {
											version:      local.meta.version      ?: local.pickVer,
											lastModified: local.meta.lastModified ?: "",
											type:         !findNoCase("-", local.pickVer) ? "release" : listLast(lCase(local.pickVer), "-"),
											minCore:      local.verMinCore
										};
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
