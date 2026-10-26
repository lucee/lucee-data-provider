// Minimal XML reading for maven-metadata.xml files: enough to replace the
// xmlSearch() calls of the CFML bridge without pulling in a parser.

function decodeEntities(text: string): string {
	return text.replace(/&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g, (_m, ent: string) => {
		switch (ent) {
			case "amp": return "&";
			case "lt": return "<";
			case "gt": return ">";
			case "quot": return '"';
			case "apos": return "'";
		}
		const code = ent[1] === "x" ? parseInt(ent.slice(2), 16) : parseInt(ent.slice(1), 10);
		return String.fromCodePoint(code);
	});
}

function stripNoise(xml: string): string {
	return xml
		.replace(/<\?[\s\S]*?\?>/g, "")
		.replace(/<!--[\s\S]*?-->/g, "")
		.replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, (_m, text: string) =>
			text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
		);
}

/** Inner content of every <name> element (no nesting of the same name). */
export function elements(xml: string, name: string): string[] {
	const out: string[] = [];
	const re = new RegExp(`<${name}(?:\\s[^>]*)?(?:/>|>([\\s\\S]*?)</${name}\\s*>)`, "g");
	for (const m of stripNoise(xml).matchAll(re)) out.push(m[1] ?? "");
	return out;
}

/** Inner content of the first <name> element, or undefined. */
export function element(xml: string, name: string): string | undefined {
	return elements(xml, name)[0];
}

/** Decoded text of the first <name> child, or undefined when absent. */
export function childText(xml: string, name: string): string | undefined {
	const inner = element(xml, name);
	return inner === undefined ? undefined : decodeEntities(inner.replace(/<[^>]+>/g, "")).trim();
}

/** Follows a path of element names, e.g. ["metadata", "versioning", "versions", "version"]. */
export function select(xml: string, path: string[]): string[] {
	let current = [xml];
	for (const name of path) {
		current = current.flatMap((c) => elements(c, name));
	}
	return current;
}

export function textOf(inner: string): string {
	return decodeEntities(inner.replace(/<[^>]+>/g, "")).trim();
}
