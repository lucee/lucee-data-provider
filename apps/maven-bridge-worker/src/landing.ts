// Port of index.cfm (landing page).
import { compareNoCase, encodeForHtml } from "./cfml";
import { renderHtmlDocument } from "./chrome";
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
	return renderHtmlDocument("Lucee Maven Bridge", `<div class="container">

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
`);
}
