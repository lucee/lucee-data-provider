// Port of index.cfm (landing page).
import { compareNoCase, encodeForHtml } from "./cfml";
import type { BridgeRegistry } from "./registry";
import { select, childText } from "./xml";

interface LandingArtifact {
	artifactId: string;
	release?: string;
	versionCount?: number;
}

interface LandingGroup {
	groupId: string;
	groupPath: string;
	upstream: string;
	artifacts: LandingArtifact[];
	errorMessage: string;
}

/** ESAPI encodeForURL (java.net.URLEncoder): keeps a-z A-Z 0-9 . - * _ and encodes space as + */
export function encodeForUrl(value: string): string {
	return encodeURIComponent(value)
		.replace(/[!'()~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase())
		.replace(/%20/g, "+")
		.replace(/%2A/g, "*");
}

export async function collectGroups(registry: BridgeRegistry): Promise<LandingGroup[]> {
	const groups: LandingGroup[] = [];
	for (const support of registry.getProviders()) {
		const groupPath = support.groupPath;
		let artifacts: LandingArtifact[] = [];
		let errorMessage = "";
		try {
			if (support.hasUpstream()) {
				// upstream mirror: the group maven-metadata.xml is the source of truth
				const content = await support.io.getUpstreamContent(support, `${groupPath}/maven-metadata.xml`);
				for (const node of select(content.body, ["metadata", "artifacts", "artifact"])) {
					const artifactId = childText(node, "artifactId");
					if (artifactId === undefined) throw new Error("Element ARTIFACTID is undefined in artifact");
					artifacts.push({ artifactId, release: childText(node, "release") ?? childText(node, "latest") ?? "" });
				}
				artifacts.push({ artifactId: "lucee" });
				artifacts.sort((a, b) => compareNoCase(a.artifactId, b.artifactId));
			} else {
				const index = await support.getIndex();
				artifacts = index.artifacts
					.keys()
					.sort(compareNoCase)
					.map((id) => ({ artifactId: id, versionCount: index.artifacts.get(id)!.versions.size }));
			}
		} catch (e) {
			artifacts = [];
			errorMessage = e instanceof Error ? e.message : String(e);
		}
		groups.push({ groupId: support.groupId, groupPath, upstream: support.upstreamUrl, artifacts, errorMessage });
	}
	return groups;
}

function renderGroup(group: LandingGroup): string {
	const chips: string[] = [];
	if (group.upstream.length) chips.push('<span class="group-meta-chip upstream">upstream mirror</span>');
	if (group.artifacts.length) chips.push(`<span class="group-meta-chip">${group.artifacts.length} artifacts</span>`);

	let body: string;
	if (group.errorMessage.length) {
		body = `<p class="group-error">Artifact list unavailable right now (${encodeForHtml(group.errorMessage)}). The group and version endpoints under <a href="/${group.groupPath}/">/${encodeForHtml(group.groupPath)}/</a> still work.</p>`;
	} else if (!group.artifacts.length) {
		body = '<p class="group-error">No artifacts found for this group yet.</p>';
	} else {
		const pills = group.artifacts.map((a) => {
			let count = "";
			if (a.versionCount !== undefined) count = `<span class="version-count">${a.versionCount}</span>`;
			else if (a.release) count = `<span class="version-count">${encodeForHtml(a.release)}</span>`;
			return `<a class="artifact-pill" href="/${group.groupPath}/${encodeForUrl(a.artifactId)}/">${encodeForHtml(a.artifactId)}${count}</a>`;
		});
		body = `<div class="artifact-pill-grid">\n${pills.join("\n")}\n</div>`;
	}

	return `<article class="group-card">
	<div class="group-card-header">
		<h3><a href="/${group.groupPath}/">${encodeForHtml(group.groupId)}</a></h3>
		${chips.join("\n\t\t")}
	</div>
	<div class="group-card-body">
		${body}
	</div>
</article>`;
}

export async function landingPage(registry: BridgeRegistry): Promise<string> {
	const groups = await collectGroups(registry);
	return `<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Lucee Maven Bridge</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/maven-bridge.css?v=1">
</head>
<body>
<header class="site-header">
	<a href="/" class="logo">
		<img src="/res/lucee-logo.svg" alt="Lucee" height="36">
		<span class="logo-subtitle">Maven</span>
	</a>
	<nav>
		<a href="https://docs.lucee.org" target="_blank">Docs</a>
		<a href="https://dev.lucee.org" target="_blank">Forum</a>
		<a href="https://github.com/lucee" target="_blank">GitHub</a>
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
		<a href="https://buymeacoffee.com/luceeorg" target="_blank" class="bmc-link">
			<img src="/res/byme2.png" class="bmc-icon" alt="Buy me a coffee">
			<img src="/res/byme.png" class="bmc-full" alt="Buy me a coffee">
		</a>
		<a href="https://opencollective.com/lucee" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="currentColor" stroke="none"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>
			Donate
		</a>
		<a href="https://skill.lucee-services.com/" target="_blank" class="nav-highlight">
			<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>
			Skills
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

<section>
	<h2 class="section-title">What is the Maven Bridge?</h2>
	<p class="section-intro">
		Lucee 7+ discovers extensions from a Maven-style repository layout: a group index, per-artifact
		<code>maven-metadata.xml</code>, and versioned <code>.lex</code> downloads. This bridge translates that layout on
		the fly from legacy REST extension providers — ForgeBox and extension.lucee.org — so Lucee 7+ can point its
		<code>maven.repository</code> setting straight at it without either provider changing.
	</p>
</section>

<section>
	<h2 class="section-title">Group IDs</h2>
	<div class="group-grid">
${groups.map(renderGroup).join("\n")}
	</div>
</section>

</div>

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
