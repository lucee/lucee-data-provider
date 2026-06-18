component {

	this.name = "LuceeSkill";
	this.sessionManagement = false;
	this.requestTimeout = createTimeSpan(0, 0, 2, 0);

	variables.skillSourceUrl = "https://docs.lucee.org/lucee.skill";
	variables.skillFileName = "main.skill";
	variables.refreshAfterMinutes = 60;

	public function onApplicationStart() {
		syncSkillFile();
		return true;
	}

	public boolean function onRequestStart() {
		syncSkillFile();
		return true;
	}

	private void function syncSkillFile() {
		var webroot = getDirectoryFromPath(getCurrentTemplatePath());
		var targetFile = webroot & variables.skillFileName;

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
}
