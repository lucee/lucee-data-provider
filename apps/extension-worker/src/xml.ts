// The little XML the provider reads (maven-metadata.xml), without a DOM parser.

function decode(value: string): string {
	return value
		.replace(/&lt;/g, "<")
		.replace(/&gt;/g, ">")
		.replace(/&quot;/g, '"')
		.replace(/&apos;/g, "'")
		.replace(/&amp;/g, "&");
}

/** the text of every <tag> element in the given xml */
export function elementTexts(xml: string, tag: string): string[] {
	const re = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`, "g");
	return [...xml.matchAll(re)].map((m) => decode(m[1]).trim());
}

/** the first <tag> element in the given xml, undefined when there is none */
export function firstElement(xml: string, tag: string): string | undefined {
	const re = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)</${tag}>`);
	const m = re.exec(xml);
	return m ? m[1] : undefined;
}

/** /metadata/versioning/versions/version, throws when the xml is not maven metadata */
export function metadataVersions(xml: string): string[] {
	if (!/<metadata[\s>]/.test(xml)) throw new Error("not maven metadata");
	const versioning = firstElement(xml, "versioning") ?? "";
	const versions = firstElement(versioning, "versions") ?? "";
	return elementTexts(versions, "version");
}

/** /metadata/artifacts/artifact/artifactId of a group maven-metadata.xml */
export function groupArtifacts(xml: string): string[] {
	if (!/<metadata[\s>]/.test(xml)) throw new Error("not maven metadata");
	return elementTexts(xml, "artifactId");
}

export interface SnapshotVersion {
	classifier?: string;
	extension: string;
	value: string;
}

/** /metadata/versioning/snapshotVersions/snapshotVersion of the maven-metadata.xml of a snapshot version */
export function snapshotVersions(xml: string): SnapshotVersion[] {
	if (!/<metadata[\s>]/.test(xml)) throw new Error("not maven metadata");
	return elementTexts(xml, "snapshotVersion").map((node) => ({
		classifier: firstElement(node, "classifier")?.trim(),
		extension: (firstElement(node, "extension") ?? "").trim(),
		value: (firstElement(node, "value") ?? "").trim()
	}));
}
