<cfscript>
util = application.util;

ver = trim(url.version ?: "");
if (!len(ver)) location("/versions.cfm", false);

changelog = new org.lucee.download.Changelog(util);
data      = changelog.getChangelog(ver);

verBase   = util.formatVersion(ver);
verType   = util.getType(ver);
typeLabels = { release:"Release", beta:"Beta", rc:"Release Candidate", snapshot:"Snapshot", alpha:"Alpha" };

// A plain-Markdown rendering of the changelog, for pasting into / feeding an AI session.
// Built server-side and stashed in a hidden element; the Copy / Download buttons use it as-is.
aiLines = ["## Lucee " & verBase & " changelog"];
if (len(data.from ?: "")) arrayAppend(aiLines, "Changes since " & util.formatVersion(data.from) & ".");
arrayAppend(aiLines, "Source: Lucee issue tracker (LDEV) — https://luceeserver.atlassian.net/projects/LDEV");
arrayAppend(aiLines, "");
for (aiT in data.tickets) {
	aiFix  = arrayLen(aiT.fixVersions) ? aiT.fixVersions[1] : "";
	aiMeta = aiT.type & (len(aiFix) ? ", fixed in " & aiFix : "");
	arrayAppend(aiLines, "- " & aiT.key & " (" & aiMeta & "): " & aiT.summary & " — " & changelog.browseUrl(aiT.key));
}
aiMd = arrayToList(aiLines, chr(10));
</cfscript>
<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<cfoutput><title>Changelog #encodeForHTML(verBase)# — Lucee Downloads</title></cfoutput>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/download.css?v=9">
</head>
<body>
<cfoutput>

<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Downloads</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org"   target="_blank">Docs</a>
		<a href="https://dev.lucee.org"    target="_blank">Forum</a>
		<a href="https://github.com/lucee" target="_blank">GitHub</a>
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
	</nav>
</header>

<div class="container">
	<div class="page-header">
		<div class="breadcrumb"><a href="/">Downloads</a> › <a href="/versions.cfm">Lucee Server</a> › Changelog</div>
		<h1>
			Changelog #encodeForHTML(verBase)#
			<span class="version-type-badge #verType#" style="vertical-align:middle;">#encodeForHTML(typeLabels[verType] ?: verType)#</span>
		</h1>
		<cfif len(data.from ?: "")>
		<p class="text-muted text-small">Changes since #encodeForHTML(util.formatVersion(data.from))#.</p>
		</cfif>
	</div>

	<cfif arrayIsEmpty(data.tickets)>
		<p class="text-muted">No changelog entries found for this version.</p>
	<cfelse>
		<div class="version-group">
			<div class="version-group-title">
				#arrayLen(data.tickets)# change#(arrayLen(data.tickets) == 1 ? "" : "s")#
			</div>
			<div class="ai-actions">
					<span class="text-muted text-small">Feed this changelog to an AI:</span>
					<button type="button" class="btn-ai" id="ai-copy">Copy</button>
					<button type="button" class="btn-ai" id="ai-download" data-file="lucee-#encodeForHTMLAttribute(verBase)#-changelog.md">Download .md</button>
				</div>
				<pre id="ai-md" hidden>#encodeForHTML(aiMd)#</pre>
				<table class="versions-table">
				<thead>
					<tr>
						<th>Ticket</th>
						<th>Type</th>
						<th>Summary</th>
						<th class="nowrap">Fixed in</th>
					</tr>
				</thead>
				<tbody>
				<cfloop array="#data.tickets#" item="t">
					<tr>
						<td class="nowrap"><a href="#encodeForHTMLAttribute(changelog.browseUrl(t.key))#" target="_blank" rel="noopener"><strong>#encodeForHTML(t.key)#</strong></a></td>
						<td class="text-muted">#encodeForHTML(t.type)#</td>
						<td>#encodeForHTML(t.summary)#</td>
						<td class="text-muted text-small nowrap">#encodeForHTML(arrayLen(t.fixVersions) ? t.fixVersions[1] : "—")#</td>
					</tr>
				</cfloop>
				</tbody>
			</table>
		</div>
	</cfif>

	<p class="text-muted text-small mt-4">
		Sourced from the <a href="https://luceeserver.atlassian.net/projects/LDEV" target="_blank">Lucee issue tracker (LDEV)</a>.
	</p>
	<p class="text-muted text-small" style="margin-top:8px;">
		<a href="/versions.cfm">← Back to versions</a>
	</p>
</div>

<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a>
	</span>
</footer>

</cfoutput>
<script>
(function() {
	var md = document.getElementById('ai-md');
	if (!md) return;
	var text = md.textContent;
	var copy = document.getElementById('ai-copy');
	var dl   = document.getElementById('ai-download');
	function copyText() {
		if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(text);
		return new Promise(function(resolve, reject) {
			try {
				var ta = document.createElement('textarea');
				ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
				document.body.appendChild(ta); ta.focus(); ta.select();
				var ok = document.execCommand('copy');
				document.body.removeChild(ta);
				ok ? resolve() : reject();
			} catch (e) { reject(e); }
		});
	}
	if (copy) copy.addEventListener('click', function() {
		copyText().then(function() {
			copy.textContent = 'Copied!'; copy.classList.add('copied');
			setTimeout(function() { copy.textContent = 'Copy'; copy.classList.remove('copied'); }, 2000);
		}).catch(function() {
			copy.textContent = 'Press Ctrl+C';
			setTimeout(function() { copy.textContent = 'Copy'; }, 2000);
		});
	});
	if (dl) dl.addEventListener('click', function() {
		var blob = new Blob([text], { type: 'text/markdown' });
		var url  = URL.createObjectURL(blob);
		var a    = document.createElement('a');
		a.href = url; a.download = dl.dataset.file || 'changelog.md';
		document.body.appendChild(a); a.click();
		document.body.removeChild(a); URL.revokeObjectURL(url);
	});
})();
</script>
</body>
</html>
