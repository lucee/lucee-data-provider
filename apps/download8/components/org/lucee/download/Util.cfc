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

	function dlCacheGet(key) {
		// 1. component variables
		if (structKeyExists(variables.cache, key)) return variables.cache[key];
		// 2. file
		local.file = getCacheDirectory() & server.separator.file & key & ".json";
		if (fileExists(local.file)) {
			try {
				local.val = deserializeJSON(fileRead(local.file));
				variables.cache[key] = local.val;
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

}
