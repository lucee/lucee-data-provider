/** a row of the extension meta, keyed by the column names */
export type Row = Record<string, unknown>;

/** a CFML query as serializeJSON() writes it (and deserializeJSON( json, false ) reads it back as a query) */
export interface CfQuery {
	COLUMNS: string[];
	DATA: unknown[][];
}

/** where a file of the extension meta can be had from a Maven source (LDEV-6795: Maven first) */
export type Location =
	| { source: "bucket"; path: string }
	| { source: "repo"; artifact: string; version: string; repos: string[] };

/** what the CFML provider and the discovery found out about the Maven files (extensions-maven.json) */
export interface MavenState {
	/** maven files found to be known already (same id and version) */
	skipped: Record<string, boolean>;
	/** artifact > extension id */
	artifactIds: Record<string, string>;
}

export interface ExtensionIndex {
	/** epoch ms */
	builtAt: number;
	columns: string[];
	/** the extension meta without the logos (image is ""), sorted by id asc, versionSortable desc */
	rows: unknown[][];
	/** file name > Maven location */
	locations: Record<string, Location>;
	stats: {
		rows: number;
		fromMeta: number;
		discovered: number;
		mavenFiles: number;
		bucketComplete: boolean;
		reposComplete: boolean;
		discoveryRead: number;
		discoveryErrors: number;
		packagingRead: number;
	};
}

/** file name > base64 logo */
export type Logos = Record<string, string>;
