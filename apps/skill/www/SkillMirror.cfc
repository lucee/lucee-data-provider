/**
 * Mirrors the Lucee skill from docs.lucee.org into the downloads directory (LDEV-6552):
 * the router as main.skill, skills.json, and every topic file skills.json lists as skill/<id>.md.
 * Each file is checked against the sha256 in skills.json; a file that does not match (or a
 * manifest that is not valid) never replaces the last good copy.
 */
component {

	variables.TOPIC_ID = "^[a-z0-9][a-z0-9-]*$";
	variables.MANIFEST_FILE = "skills.json";

	public function init(
		required string downloadsDirectory,
		string skillSourceUrl = "https://docs.lucee.org/lucee.skill",
		string skillFileName = "main.skill",
		string manifestUrl = "https://docs.lucee.org/skill/skills.json",
		numeric timeout = 60
	) {
		variables.dir = arguments.downloadsDirectory;
		variables.skillSourceUrl = arguments.skillSourceUrl;
		variables.skillFileName = arguments.skillFileName;
		variables.manifestUrl = arguments.manifestUrl;
		variables.timeout = arguments.timeout;
		if (!directoryExists(variables.dir)) directoryCreate(variables.dir, true, true);
		return this;
	}

	public string function path(required string relativePath) {
		return variables.dir & "/" & arguments.relativePath;
	}

	public string function topicPath(required string id) {
		return path("skill/" & arguments.id & ".md");
	}

	/** the mirrored manifest, or an empty struct when there is none */
	public struct function readManifest() {
		var file = path(variables.MANIFEST_FILE);
		if (!len(variables.manifestUrl) || !fileExists(file)) return {};
		try {
			return parseManifest(fileRead(file, "utf-8"));
		} catch (any e) {
			log type="error" text="mirrored #variables.MANIFEST_FILE# is not usable: #e.message#";
			return {};
		}
	}

	/** topic ids are lower case; true when the manifest lists it */
	public boolean function isTopic(required string id) {
		if (!reFind(variables.TOPIC_ID, arguments.id)) return false;
		var manifest = readManifest();
		if (!structKeyExists(manifest, "topics")) return false;
		for (var topic in manifest.topics) {
			if (topic.id == arguments.id) return true;
		}
		return false;
	}

	/**
	 * Checks and normalizes skills.json: topic ids, unique ids, topic urls on the manifest's own
	 * origin, sha256 as hex. Throws on anything unexpected.
	 */
	public struct function parseManifest(required string json) {
		if (!isJSON(arguments.json)) throw(message="#variables.MANIFEST_FILE# is not valid JSON");
		var data = deserializeJSON(arguments.json);
		if (!isStruct(data) || !structKeyExists(data, "topics") || !isArray(data.topics)) {
			throw(message="#variables.MANIFEST_FILE# has no topics array");
		}
		var origin = originOf(variables.manifestUrl);
		var result = { name: toStr(data.name ?: ""), router: {}, topics: [] };
		var seen = {};
		for (var item in data.topics) {
			if (!isStruct(item)) throw(message="#variables.MANIFEST_FILE#: a topic is not an object");
			var id = toStr(item.id ?: "");
			// case-sensitive: ids are lower case
			if (!reFind(variables.TOPIC_ID, id)) throw(message="#variables.MANIFEST_FILE#: invalid topic id ""#id#""");
			if (structKeyExists(seen, id)) throw(message="#variables.MANIFEST_FILE#: topic ""#id#"" is listed twice");
			seen[id] = true;
			var href = toStr(item.url ?: "");
			if (!len(href)) href = toStr(item.path ?: "");
			if (!len(href)) throw(message="#variables.MANIFEST_FILE#: topic ""#id#"" has no url");
			var topicUrl = resolveUrl(href, variables.manifestUrl);
			if (originOf(topicUrl) != origin) throw(message="#variables.MANIFEST_FILE#: topic ""#id#"" is not on #origin#");
			arrayAppend(result.topics, {
				id: id,
				title: len(toStr(item.title ?: "")) ? toStr(item.title) : id,
				description: toStr(item.description ?: ""),
				url: topicUrl,
				entries: toCount(item.entries ?: 0),
				sha256: toSha(item.sha256 ?: "", "topic ""#id#"""),
				approxTokens: toCount(item.approxTokens ?: 0)
			});
		}
		if (isStruct(data.router ?: "") && len(toStr(data.router.url ?: ""))) {
			result.router = {
				url: resolveUrl(toStr(data.router.url), variables.manifestUrl),
				sha256: toSha(data.router.sha256 ?: "", "router"),
				approxTokens: toCount(data.router.approxTokens ?: 0)
			};
		}
		return result;
	}

	/**
	 * Mirrors the manifest, the router and every topic. One failing file does not stop the others.
	 * Returns the errors (empty when everything worked).
	 */
	public array function sync() {
		var errors = [];
		var manifest = {};
		var manifestBody = "";

		if (len(variables.manifestUrl)) {
			try {
				manifestBody = download(variables.manifestUrl);
				manifest = parseManifest(toString(manifestBody, "utf-8"));
			} catch (any e) {
				arrayAppend(errors, "#variables.MANIFEST_FILE#: #e.message#");
				manifestBody = "";
				// the last good copy still drives the topic refresh
				manifest = readManifest();
			}
		}

		// router (main.skill), checked against the manifest when it is the manifest's router
		try {
			var expected = "";
			if (structKeyExists(manifest, "router") && structKeyExists(manifest.router, "url") && manifest.router.url == variables.skillSourceUrl) {
				expected = manifest.router.sha256;
			}
			store(variables.skillFileName, download(variables.skillSourceUrl), expected);
		} catch (any e) {
			arrayAppend(errors, "#variables.skillFileName#: #e.message#");
		}

		for (var topic in manifest.topics ?: []) {
			try {
				var file = "skill/" & topic.id & ".md";
				// unchanged files are not downloaded again
				if (len(topic.sha256) && fileExists(path(file)) && sha256(fileReadBinary(path(file))) == topic.sha256) continue;
				store(file, download(topic.url), topic.sha256);
			} catch (any e) {
				arrayAppend(errors, "skill/#topic.id#.md: #e.message#");
			}
		}

		// the manifest last, so it never lists a topic that was not mirrored before
		if (len(manifestBody)) store(variables.MANIFEST_FILE, manifestBody, "");

		for (var err in errors) {
			log type="error" text="skill mirror: #err# (cached copy kept)";
		}
		return errors;
	}

	private binary function download(required string address) {
		cfhttp(url=arguments.address, method="GET", result="local.result", throwOnError=false, timeout=variables.timeout, getAsBinary="yes", userAgent="lucee-skill") {}
		if (left(local.result.statusCode, 3) != "200") throw(message="#arguments.address# answered #local.result.statusCode#");
		var body = local.result.fileContent;
		if (!isBinary(body)) body = charsetDecode(toString(body), "utf-8");
		if (!len(trim(toString(body, "utf-8")))) throw(message="#arguments.address# answered with an empty body");
		return body;
	}

	/** writes atomically, after checking the sha256 when one is expected */
	private void function store(required string file, required binary body, required string expectedSha) {
		if (len(arguments.expectedSha)) {
			var actual = sha256(arguments.body);
			if (actual != arguments.expectedSha) throw(message="does not match the sha256 in #variables.MANIFEST_FILE# (got #actual#)");
		}
		var target = path(arguments.file);
		var parent = getDirectoryFromPath(target);
		if (!directoryExists(parent)) directoryCreate(parent, true, true);
		var temp = target & "." & createUUID() & ".tmp";
		fileWrite(temp, arguments.body);
		fileMove(temp, target);
	}

	private string function sha256(required binary body) {
		return lCase(hash(arguments.body, "SHA-256"));
	}

	private string function toStr(any value) {
		return isSimpleValue(arguments.value) ? trim(arguments.value) : "";
	}

	private numeric function toCount(any value) {
		return isNumeric(arguments.value) && arguments.value >= 0 ? round(arguments.value) : 0;
	}

	private string function toSha(any value, required string what) {
		var s = lCase(toStr(arguments.value));
		if (len(s) && !reFind("^[0-9a-f]{64}$", s)) throw(message="#variables.MANIFEST_FILE#: #arguments.what#: sha256 is not a SHA-256 hex digest");
		return s;
	}

	private string function resolveUrl(required string href, required string base) {
		if (reFindNoCase("^https?://", arguments.href)) return arguments.href;
		var origin = originOf(arguments.base);
		if (left(arguments.href, 1) == "/") return origin & arguments.href;
		var basePath = mid(arguments.base, len(origin) + 1, len(arguments.base));
		basePath = reReplace(basePath, "[^/]*$", "");
		return origin & basePath & arguments.href;
	}

	private string function originOf(required string address) {
		var m = reFindNoCase("^(https?://[^/?##]+)", arguments.address, 1, true);
		if (arrayLen(m.pos) < 2 || m.pos[2] == 0) throw(message="not an http(s) url: #arguments.address#");
		return lCase(mid(arguments.address, m.pos[2], m.len[2]));
	}
}
