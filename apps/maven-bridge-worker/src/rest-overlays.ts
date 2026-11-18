// Extra REST-provider versions that the upstream /info index does not list.
// The maven-bridge otherwise only mirrors ForgeBox, so S3-only releases such as
// cfspreadsheet 3.0.4 and 3.0.5 would be missing from io.forgebox. Provider
// entries always win when both list the same version.
import { NoCaseMap } from "./cfml";
import type { RestIndex } from "./rest-index";

export interface RestVersionOverlay {
	groupId: string;
	artifactId: string;
	id: string;
	name: string;
	description?: string;
	/** version -> download URL (usually the org.lucee CDN copy). */
	versions: Record<string, string>;
}

export const REST_VERSION_OVERLAYS: RestVersionOverlay[] = [
	{
		groupId: "io.forgebox",
		artifactId: "cfspreadsheet-extension",
		id: "037A27FF-0B80-4CBA-B954BEBD790B460E",
		name: "cfspreadsheet",
		description: "A spreadsheet extension for Lucee 5",
		versions: {
			"3.0.4": "https://cdn.lucee.org/org/lucee/spreadsheet-extension/3.0.4/spreadsheet-extension-3.0.4.lex",
			"3.0.5": "https://cdn.lucee.org/org/lucee/spreadsheet-extension/3.0.5/spreadsheet-extension-3.0.5.lex"
		}
	}
];

export function applyRestVersionOverlays(index: RestIndex): RestIndex {
	for (const overlay of REST_VERSION_OVERLAYS) {
		if (overlay.groupId.toLowerCase() !== index.groupId.toLowerCase()) continue;
		let artifact = index.artifacts.get(overlay.artifactId);
		if (!artifact) {
			artifact = { id: overlay.id, name: overlay.name, versions: new NoCaseMap() };
			index.artifacts.set(overlay.artifactId, artifact);
		}
		for (const [version, downloadUrl] of Object.entries(overlay.versions)) {
			if (artifact.versions.has(version)) continue;
			artifact.versions.set(version, {
				id: overlay.id,
				name: overlay.name,
				description: overlay.description ?? "",
				filename: "",
				created: "",
				downloadUrl
			});
		}
	}
	return index;
}
