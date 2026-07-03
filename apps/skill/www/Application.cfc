component {

	this.name = "LuceeSkill";
	this.sessionManagement = false;
	this.requestTimeout = createTimeSpan(0, 0, 2, 0);

	variables.skillSourceUrl = "https://docs.lucee.org/lucee.skill";
	variables.skillFileName = "main.skill";
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

	private void function syncSkillFile() {
		var targetFile = getDownloadsDirectory() & server.separator.file & variables.skillFileName;

		if (isSkillFileFresh(targetFile)) {
			return;
		}

		lock name="lucee-skill-sync" timeout="120" throwOnTimeout=false {
			if (isSkillFileFresh(targetFile)) {
				return;
			}

			cfhttp(
				url=variables.skillSourceUrl,
				method="GET",
				result="local.result",
				throwOnError=false,
				timeout=60
			) {}

			if (left(local.result.statusCode, 3) != "200") {
				log type="error" text="Failed to download skill file from #variables.skillSourceUrl#: #local.result.statusCode#";
				return;
			}

			fileWrite(targetFile, local.result.fileContent, "utf-8");
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
			case "txt":
			case "md":
			case "skill":
				return "text/plain; charset=utf-8";
			default:
				return "";
		}
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
