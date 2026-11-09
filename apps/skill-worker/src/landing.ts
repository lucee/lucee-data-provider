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
	<script>try{var t=localStorage.getItem("lucee-theme");if(t==="light"||t==="dark")document.documentElement.setAttribute("data-theme",t)}catch(e){}</script>
	<link rel="stylesheet" href="/res/lucee-header/theme.css" data-lucee-theme-css>
	<link rel="stylesheet" href="/res/lucee-header/header.css" data-lucee-header-css>
	<script src="/res/lucee-header/header.js" defer></script>
	<link rel="stylesheet" href="/res/skill.css?v=2">
</head>
<body>

<lucee-header home="https://lucee.org/" current="ai">
	<a href="https://lucee.org/" aria-label="Lucee home">Lucee</a><a href="https://download.lucee.org/">Download</a><a href="https://docs.lucee.org/">Docs</a><a href="https://lucee.org/extensions">Extensions</a><a href="https://lucee.org/community">Community</a><a href="https://lucee.org/ai">AI</a><a href="https://lucee.org/support">Support</a>
</lucee-header>

<div class="container">

<div class="page-title">
	<h1>Lucee Skills</h1>
</div>

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
		<a href="https://hub.docker.com/r/lucee/lucee" target="_blank">Docker Hub</a> &middot;
		<a href="https://opencollective.com/lucee" target="_blank">Donate</a>
	</span>
</footer>

</body>
</html>
`;
}
