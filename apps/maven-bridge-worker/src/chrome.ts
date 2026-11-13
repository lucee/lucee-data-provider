// Shared HTML chrome: the vendored <lucee-header> from apps/website/shared/.

/** No-JS fallback links, same markup as the skill Worker and the hub site. */
export const LUCEE_HEADER_FALLBACK_NAV =
	'<a href="https://lucee.org/" aria-label="Lucee home">Lucee</a><a href="https://download.lucee.org/">Download</a><a href="https://docs.lucee.org/">Docs</a><a href="https://lucee.org/extensions">Extensions</a><a href="https://lucee.org/community">Community</a><a href="https://lucee.org/ai">AI</a><a href="https://lucee.org/support">Support</a>';

/**
 * Wrap a page body in the shared header, footer and stylesheets.
 * `title` must already be HTML-escaped.
 */
export function renderHtmlDocument(title: string, body: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>${title}</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/lucee-header/theme.css?v=2" data-lucee-theme-css>
	<link rel="stylesheet" href="/res/lucee-header/header.css?v=2" data-lucee-header-css>
	<script src="/res/lucee-header/header.js?v=2" defer></script>
	<link rel="stylesheet" href="/res/maven-bridge.css?v=2">
</head>
<body>

<lucee-header home="https://lucee.org/" current="extensions">
	${LUCEE_HEADER_FALLBACK_NAV}
</lucee-header>

${body}

<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org" target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org" target="_blank">Docs</a> &middot;
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
	</span>
</footer>
</body>
</html>
`;
}

/**
 * Maven-style directory listing (h1 + pre of links) inside the shared chrome.
 * `title` and `heading` must already be HTML-escaped. `preLines` are the
 * entries inside <pre>, each usually ending with a newline, joined with
 * newlines the same way the previous bare listings did.
 */
export function renderListingPage(title: string, heading: string, preLines: string[]): string {
	return renderHtmlDocument(
		title,
		`<div class="container">
	<h1 class="listing-title">${heading}</h1>
	<pre>
${preLines.join("\n")}</pre>
</div>`
	);
}
