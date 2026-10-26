// Port of apps/skill/www/index.cfm (landing page).
import { lastModifiedOf, type CachedSkill } from "./store";

export interface SkillInfo {
	file: string;
	name: string;
	displayName: string;
	description: string;
	size: number;
	/** Last-Modified of the source, or when the body last changed when the source sends none */
	updated: Date;
	sourceHost: string;
}

export function encodeForHtml(value: string): string {
	return String(value)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&#39;");
}

/** ESAPI encodeForURL (java.net.URLEncoder): keeps a-z A-Z 0-9 . - * _ and encodes space as + */
export function encodeForUrl(value: string): string {
	return encodeURIComponent(value)
		.replace(/[!'()~]/g, (c) => "%" + c.charCodeAt(0).toString(16).toUpperCase())
		.replace(/%20/g, "+")
		.replace(/%2A/g, "*");
}

export function humanizeSlug(slug: string): string {
	return slug
		.split(/[-_]/)
		.filter(Boolean)
		.map((w) => w.charAt(0).toUpperCase() + w.slice(1))
		.join(" ");
}

export function formatBytes(bytes: number): string {
	if (bytes >= 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MB";
	if (bytes >= 1024) return Math.round(bytes / 1024) + " KB";
	return bytes + " B";
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** dateFormat(date, "mmm d, yyyy") in UTC */
export function formatDate(date: Date): string {
	return `${MONTHS[date.getUTCMonth()]} ${date.getUTCDate()}, ${date.getUTCFullYear()}`;
}

/** name and description from the YAML frontmatter, same rules as index.cfm */
export function parseFrontmatter(content: string, fallbackName: string): { name: string; description: string } {
	const match = /^---[\r\n]+([\s\S]*?)[\r\n]+---/.exec(content);
	const frontmatter = match ? match[1] : "";
	let name = fallbackName;
	let description = "";
	let inDesc = false;
	for (const line of frontmatter.split("\n")) {
		const trimmed = line.trim();
		if (trimmed.startsWith("name:")) {
			name = trimmed.slice(5).trim();
			inDesc = false;
		} else if (trimmed.startsWith("description:")) {
			inDesc = true;
			const rest = trimmed.slice(12).trim();
			if (rest && rest !== ">" && rest !== "|") description = rest;
		} else if (inDesc && (line.startsWith(" ") || line.startsWith("\t"))) {
			description = description ? `${description} ${trimmed}` : trimmed;
		} else {
			inDesc = false;
		}
	}
	return { name, description: description.replace(/\s+/g, " ").trim() };
}

export function skillInfo(file: string, cached: CachedSkill): SkillInfo {
	const { name, description } = parseFrontmatter(cached.body, file.split(".")[0]);
	const lastModified = new Date(lastModifiedOf(cached));
	return {
		file,
		name,
		displayName: humanizeSlug(name),
		description,
		size: new TextEncoder().encode(cached.body).byteLength,
		updated: Number.isNaN(lastModified.getTime()) ? new Date(cached.modifiedAt ?? cached.fetchedAt) : lastModified,
		sourceHost: new URL(cached.source).host
	};
}

function skillCard(skill: SkillInfo, host: string): string {
	return `
			<article class="skill-card">
				<div class="skill-card-header">
					<div class="skill-card-icon">
						<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M9 15h6M9 11h2"/></svg>
					</div>
					<div>
						<h3>${encodeForHtml(skill.displayName)}</h3>
						<div class="skill-card-name">${encodeForHtml(skill.name)}</div>
					</div>
				</div>
				<div class="skill-card-body">
					<p>${encodeForHtml(skill.description)}</p>
					<div class="skill-card-meta">
						<span class="skill-meta-chip">${formatBytes(skill.size)}</span>
						<span class="skill-meta-chip">Updated ${formatDate(skill.updated)}</span>
						<span class="skill-meta-chip">Refreshed hourly from ${encodeForHtml(skill.sourceHost)}</span>
					</div>
				</div>
				<div class="skill-card-footer">
					<a class="skill-url" href="/${encodeForUrl(skill.file)}">${encodeForHtml("https://" + host + "/" + skill.file)}</a>
				</div>
			</article>`;
}

export function renderLanding(skills: SkillInfo[], host: string): string {
	return `<!DOCTYPE html>
<html lang="en">
<head>
	<meta charset="UTF-8">
	<meta name="viewport" content="width=device-width, initial-scale=1">
	<title>Lucee Skills</title>
	<link rel="icon" type="image/png" href="/res/favicon.png">
	<link rel="stylesheet" href="/res/skill.css?v=1">
</head>
<body>

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

<section>
	<h2 class="section-title">What is a Skill?</h2>
	<p class="section-intro">
		A <strong>skill</strong> is a small, structured text file that gives an AI assistant on-demand access to accurate,
		up-to-date reference material instead of relying on what it memorized during training. Each Lucee skill bundles an
		index of recipes, guides, and technical specs with instructions for the assistant on when and how to fetch the
		relevant page before answering — so you get working CFML code and correct API details instead of confident guesses.
	</p>
</section>

<section>
	<h2 class="section-title">Available Skills</h2>
	<div class="skill-grid">${skills.map((s) => skillCard(s, host)).join("")}
	</div>
</section>

<hr class="section-divider">

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

</div>

<footer class="site-footer">
	<span>&copy; Lucee Association Switzerland</span>
	<span>
		<a href="https://github.com/lucee" target="_blank">GitHub</a> &middot;
		<a href="https://dev.lucee.org"    target="_blank">Forum</a> &middot;
		<a href="https://docs.lucee.org"   target="_blank">Docs</a> &middot;
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a>
	</span>
</footer>

</body>
</html>
`;
}
