component {

	this.name = "LuceeSkill";
	this.sessionManagement = false;
	this.requestTimeout = createTimeSpan(0, 0, 2, 0);

	variables.skillSourceUrl = "https://docs.lucee.org/lucee.skill";
	variables.skillFileName = "main.skill";
	// LDEV-6552: every topic file listed in skills.json is mirrored and served as /skill/<id>.md
	variables.manifestUrl = "https://docs.lucee.org/skill/skills.json";
	variables.refreshAfterMinutes = 60;
	variables.downloadsDirectory = "";

	public function onApplicationStart() {
		syncSkillFile();
		return true;
	}

	public boolean function onRequestStart(required string targetPage) {
		syncSkillFile();

		var ext = getRequestExtension(arguments.targetPage);
		if (!len(ext)) {
			return true;
		}

		if (ext == "skill") {
			serveSkillFile(arguments.targetPage);
			return false;
		}

		// *.md and *.json are routed through Lucee (Dockerfile) for the topic files and the manifest
		if (ext == "md" || ext == "json") {
			serveMirroredFile(arguments.targetPage, ext);
			return false;
		}

		// SkillMirror.cfc is not meant to be called over HTTP
		if (ext == "cfc") {
			notFound();
		}

		var contentType = getContentTypeForExtension(ext);
		if (len(contentType)) {
			header name="Content-Type" value=contentType;
		}

		return true;
	}

	private string function getDownloadsDirectory() {
		if (len(variables.downloadsDirectory)) return variables.downloadsDirectory;
		var dir = server.system.environment.DOWNLOADS_DIRECTORY ?: "";
		if (!len(dir)) {
			// default: /downloads (mounted volume, survives container restarts)
			dir = "/downloads";
		}
		if (!directoryExists(dir)) directoryCreate(dir, true, true);
		variables.downloadsDirectory = dir;
		return dir;
	}

	private function getMirror() {
		return new SkillMirror(
			downloadsDirectory = getDownloadsDirectory(),
			skillSourceUrl = variables.skillSourceUrl,
			skillFileName = variables.skillFileName,
			manifestUrl = variables.manifestUrl
		);
	}

	/** mirrors the router, skills.json and the topic files at most once per refreshAfterMinutes */
	private void function syncSkillFile() {
		var targetFile = getDownloadsDirectory() & server.separator.file & variables.skillFileName;

		if (isSkillFileFresh(targetFile)) {
			return;
		}

		lock name="lucee-skill-sync" timeout="120" throwOnTimeout=false {
			if (isSkillFileFresh(targetFile)) {
				return;
			}
			// errors are logged by the mirror; the last good copies stay in place
			getMirror().sync();
		}
	}

	private boolean function isSkillFileFresh(required string targetFile) {
		if (!fileExists(arguments.targetFile)) {
			return false;
		}

		return dateDiff("n", getFileInfo(arguments.targetFile).lastModified, now()) < variables.refreshAfterMinutes;
	}

	private string function getRequestExtension(required string targetPage) {
		var path = listLast(arguments.targetPage, "/\");
		if (!len(path) || !find(".", path)) {
			return "";
		}
		return lcase(listLast(path, "."));
	}

	private string function getContentTypeForExtension(required string ext) {
		switch (lcase(arguments.ext)) {
			case "json":
				return "application/json; charset=utf-8";
			case "md":
				return "text/markdown; charset=utf-8";
			case "txt":
			case "skill":
				return "text/plain; charset=utf-8";
			default:
				return "";
		}
	}

	private void function notFound() {
		header statuscode="404" statustext="Not Found";
		writeOutput("Not Found");
		abort;
	}

	/** /skills.json and /skill/<id>.md from the mirror; other .md/.json files from the webroot */
	private void function serveMirroredFile(required string targetPage, required string ext) {
		var page = lCase(arguments.targetPage);
		var file = "";
		if (page == "/skills.json") {
			file = getDownloadsDirectory() & "/skills.json";
		} else {
			var m = reFind("^/skill/([a-z0-9][a-z0-9-]*)\.md$", page, 1, true);
			if (arrayLen(m.pos) >= 2 && m.pos[2] > 0) {
				var id = mid(page, m.pos[2], m.len[2]);
				// only topics the mirrored manifest lists
				if (getMirror().isTopic(id)) file = getMirror().topicPath(id);
			} else if (fileExists(expandPath(arguments.targetPage))) {
				// e.g. /res/lucee-header/README.md, served as it was before *.md went through Lucee
				file = expandPath(arguments.targetPage);
			}
		}
		if (!len(file) || !fileExists(file)) notFound();
		content type=getContentTypeForExtension(arguments.ext) file=file deletefile="no";
	}

	private void function serveSkillFile(required string targetPage) {
		var filename = listLast(arguments.targetPage, "/\");
		if (lcase(listLast(filename, ".")) != "skill") {
			header statuscode="404" statustext="Not Found";
			writeOutput("Not Found");
			abort;
		}

		var targetFile = getDownloadsDirectory() & server.separator.file & filename;
		if (!fileExists(targetFile)) {
			header statuscode="404" statustext="Not Found";
			writeOutput("Not Found");
			abort;
		}

		var mimeType = "text/plain; charset=utf-8";
		content type=mimeType file=targetFile deletefile="no";
	}
}
