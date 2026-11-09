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
	<script>try{var t=localStorage.getItem("lucee-theme");if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}</script>
	<link rel="stylesheet" href="/res/lucee-header/theme.css" data-lucee-theme-css>
	<link rel="stylesheet" href="/res/lucee-header/header.css" data-lucee-header-css>
	<script src="/res/lucee-header/header.js" defer></script>
	<link rel="stylesheet" href="/res/skill.css?v=2">
</head>
<body>
<cfoutput>

<!--- ── Header ── --->
<lucee-header home="https://lucee.org/" current="ai">
	<a href="https://lucee.org/" aria-label="Lucee home">Lucee</a><a href="https://download.lucee.org/">Download</a><a href="https://docs.lucee.org/">Docs</a><a href="https://lucee.org/extensions">Extensions</a><a href="https://lucee.org/community">Community</a><a href="https://lucee.org/ai">AI</a><a href="https://lucee.org/support">Support</a>
</lucee-header>

<div class="container">

<!--- ── Page title ── --->
<div class="page-title">
	<h1>Lucee Skills</h1>
</div>

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

<hr class="section-divider">

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

</div><!--- .container --->

<!--- ── Footer ── --->
<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a> &middot;
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a> &middot;
		<a href="https://opencollective.com/lucee" target="_blank">Donate</a>
	</span>
</footer>

</cfoutput>
</body>
</html>
