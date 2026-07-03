<cfscript>
setting showdebugoutput=false;

// ── Locate the downloads directory (same volume-mounted path Application.cfc uses) ──
downloadsDirectory = server.system.environment.DOWNLOADS_DIRECTORY ?: "";
if (!len(downloadsDirectory)) {
	downloadsDirectory = "/downloads";
}

function humanizeSlug(slug) {
	local.words = listToArray(slug, "-_");
	local.out = [];
	for (local.w in local.words) {
		arrayAppend(local.out, uCase(left(local.w, 1)) & mid(local.w, 2, len(local.w)));
	}
	return arrayToList(local.out, " ");
}

function formatBytes(bytes) {
	if (bytes >= 1024*1024) return numberFormat(bytes/1024/1024, "0.0") & " MB";
	if (bytes >= 1024) return numberFormat(bytes/1024, "0") & " KB";
	return bytes & " B";
}

// ── Load skill metadata straight from the .skill file's YAML frontmatter ──
function loadSkill(filename) {
	local.result = { available: false, filename: arguments.filename };
	local.path = downloadsDirectory & server.separator.file & arguments.filename;
	if (!fileExists(local.path)) return local.result;

	local.info = getFileInfo(local.path);
	local.result.available    = true;
	local.result.size         = local.info.size;
	local.result.lastModified = local.info.lastModified;

	local.content     = fileRead(local.path);
	local.frontmatter = "";
	local.fm = reFind("(?s)^---[\r\n]+(.*?)[\r\n]+---", local.content, 1, true);
	if (arrayLen(local.fm.pos) >= 2 && local.fm.pos[2] > 0) {
		local.frontmatter = mid(local.content, local.fm.pos[2], local.fm.len[2]);
	}

	local.name        = listFirst(arguments.filename, ".");
	local.description = "";
	local.inDesc       = false;
	for (local.line in listToArray(local.frontmatter, chr(10), true)) {
		local.trimmed = trim(local.line);
		if (left(local.trimmed, 5) == "name:") {
			local.name = trim(mid(local.trimmed, 6, len(local.trimmed)));
			local.inDesc = false;
		} else if (left(local.trimmed, 12) == "description:") {
			local.inDesc = true;
			local.rest = trim(mid(local.trimmed, 13, len(local.trimmed)));
			if (len(local.rest) && local.rest != ">" && local.rest != "|") local.description = local.rest;
		} else if (local.inDesc && (left(local.line, 1) == " " || left(local.line, 1) == chr(9))) {
			local.description = len(local.description) ? local.description & " " & local.trimmed : local.trimmed;
		} else {
			local.inDesc = false;
		}
	}

	local.result.name        = local.name;
	local.result.displayName = humanizeSlug(local.name);
	local.result.description = trim(reReplace(local.description, "\s+", " ", "all"));
	return local.result;
}

// ── Skills we currently publish ──
skills = [ loadSkill("main.skill") ];
</cfscript>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Lucee Skills</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/skill.css?v=1">
</head>
<body>
<cfoutput>

<!--- ── Header ── --->
<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Skills</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org"     target="_blank">Docs</a>
		<a href="https://dev.lucee.org"      target="_blank">Forum</a>
		<a href="https://github.com/lucee"   target="_blank">GitHub</a>
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
		<a href="https://buymeacoffee.com/luceeorg" target="_blank" class="bmc-link">
			<img src="/res/byme2.png" class="bmc-icon" alt="Buy me a coffee">
			<img src="/res/byme.png"  class="bmc-full" alt="Buy me a coffee">
		</a>
		<a href="https://opencollective.com/lucee" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>
			Donate
		</a>
		<a href="https://mcp.lucee-services.com/" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"/><path d="M12 1v4M12 19v4M4.22 4.22l2.83 2.83M16.95 16.95l2.83 2.83M1 12h4M19 12h4M4.22 19.78l2.83-2.83M16.95 7.05l2.83-2.83"/></svg>
			MCP Server
		</a>
		<a href="https://download.lucee.org/" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12m0 0l-4-4m4 4l4-4"/><path d="M4 17v2a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-2"/></svg>
			Downloads
		</a>
	</nav>
</header>

<div class="container">

<!--- ── What is a Skill ── --->
<section>
	<h2 class="section-title">What is a Skill?</h2>
	<p class="section-intro">
		A <strong>skill</strong> is a small, structured text file that gives an AI assistant on-demand access to accurate,
		up-to-date reference material instead of relying on what it memorized during training. Each Lucee skill bundles an
		index of recipes, guides, and technical specs with instructions for the assistant on when and how to fetch the
		relevant page before answering — so you get working CFML code and correct API details instead of confident guesses.
	</p>
</section>

<!--- ── Using Skills with AI Assistants ── --->
<section>
	<h2 class="section-title">Using Skills with Your AI Assistant</h2>
	<p class="section-intro">Skill files are plain text, so any assistant that lets you attach reference material can use one. A few common setups:</p>
	<div class="assistant-grid">
		<article class="assistant-card">
			<h3>Claude</h3>
			<p>
				Claude supports Agent Skills natively. Download the file into your project's
				<code>.claude/skills/</code> directory, or add it under a Claude.ai Project's Skills settings —
				Claude loads it automatically whenever a Lucee or CFML question comes up.
			</p>
		</article>
		<article class="assistant-card">
			<h3>ChatGPT</h3>
			<p>
				Attach the file to a Project or upload it to a Custom GPT's Knowledge files. ChatGPT will pull from
				it as reference material whenever your prompt touches Lucee or CFML.
			</p>
		</article>
		<article class="assistant-card">
			<h3>Gemini</h3>
			<p>
				Add the file as a knowledge source on a Gemini Gem, or paste its contents into your system
				instructions so Gemini has the same Lucee-specific context to work from.
			</p>
		</article>
	</div>
</section>

<hr class="section-divider">

<!--- ── Available Skills ── --->
<section>
	<h2 class="section-title">Available Skills</h2>
	<div class="skill-grid">
		<cfloop array="#skills#" item="skill">
		<cfif skill.available>
			<article class="skill-card">
				<div class="skill-card-header">
					<div class="skill-card-icon">
						<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 15h6M9 11h2"/></svg>
					</div>
					<div>
						<h3>#encodeForHTML(skill.displayName)#</h3>
						<div class="skill-card-name">#encodeForHTML(skill.name)#</div>
					</div>
				</div>
				<div class="skill-card-body">
					<p>#encodeForHTML(skill.description)#</p>
					<div class="skill-card-meta">
						<span class="skill-meta-chip">#formatBytes(skill.size)#</span>
						<span class="skill-meta-chip">Updated #dateFormat(skill.lastModified, "mmm d, yyyy")#</span>
						<span class="skill-meta-chip">Refreshed hourly from docs.lucee.org</span>
					</div>
				</div>
				<div class="skill-card-footer">
					<a class="skill-url" href="/#encodeForURL(skill.filename)#">#encodeForHTML("https://" & cgi.http_host & "/" & skill.filename)#</a>
				</div>
			</article>
		</cfif>
		</cfloop>
	</div>
</section>

</div><!--- .container --->

<!--- ── Footer ── --->
<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a> &middot;
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
	</span>
</footer>

</cfoutput>
</body>
</html>
