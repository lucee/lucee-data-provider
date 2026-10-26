// Helpers that reproduce the CFML built-ins used by apps/maven-bridge, so the
// Worker produces byte-identical bodies and URLs.

/** CFML xmlFormat(): escapes & < > " and ' (as &apos;). */
export function xmlFormat(value: string): string {
	return String(value)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&apos;");
}

/** encodeForHtml() as rendered by the current bridge for the values it handles. */
export function encodeForHtml(value: string): string {
	return String(value)
		.replace(/&/g, "&amp;")
		.replace(/</g, "&lt;")
		.replace(/>/g, "&gt;")
		.replace(/"/g, "&quot;")
		.replace(/'/g, "&#39;");
}

/** CFML urlEncodedFormat(): every byte that is not [A-Za-z0-9] is %XX encoded. */
export function urlEncodedFormat(value: string): string {
	let out = "";
	for (const byte of new TextEncoder().encode(String(value))) {
		const ch = String.fromCharCode(byte);
		out += /[A-Za-z0-9]/.test(ch) ? ch : "%" + byte.toString(16).toUpperCase().padStart(2, "0");
	}
	return out;
}

/** Case-insensitive string compare (CFML compareNoCase / arraySort "textnocase"). */
export function compareNoCase(a: string, b: string): number {
	const x = a.toLowerCase();
	const y = b.toLowerCase();
	return x < y ? -1 : x > y ? 1 : 0;
}

/** Case-sensitive string compare (CFML compare()). */
export function compare(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

export function equalsNoCase(a: string, b: string): boolean {
	return a.toLowerCase() === b.toLowerCase();
}

export function containsNoCase(haystack: string, needle: string): boolean {
	return haystack.toLowerCase().includes(needle.toLowerCase());
}

export function startsWithNoCase(value: string, prefix: string): boolean {
	return value.toLowerCase().startsWith(prefix.toLowerCase());
}

/** CFML isNumeric() for the plain version segments the bridge deals with. */
export function isNumeric(value: string): boolean {
	return /^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*$/.test(value);
}

const pad = (n: number, len = 2) => String(n).padStart(len, "0");

/** dateTimeFormat(dt, "yyyymmddHHnnss") in UTC. */
export function mavenTimestamp(date: Date): string {
	return (
		date.getUTCFullYear() +
		pad(date.getUTCMonth() + 1) +
		pad(date.getUTCDate()) +
		pad(date.getUTCHours()) +
		pad(date.getUTCMinutes()) +
		pad(date.getUTCSeconds())
	);
}

const MONTHS = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
];

/** serializeJSON() rendering of a date: "October, 26 2026 13:41:06 +0000". */
export function cfJsonDate(date: Date): string {
	return (
		`${MONTHS[date.getUTCMonth()]}, ${pad(date.getUTCDate())} ${date.getUTCFullYear()} ` +
		`${pad(date.getUTCHours())}:${pad(date.getUTCMinutes())}:${pad(date.getUTCSeconds())} +0000`
	);
}

/**
 * Struct with case-insensitive keys that keeps the casing of the first insert,
 * like a CFML struct.
 */
export class NoCaseMap<V> {
	private readonly entries = new Map<string, { key: string; value: V }>();

	get size(): number {
		return this.entries.size;
	}

	has(key: string): boolean {
		return this.entries.has(key.toLowerCase());
	}

	get(key: string): V | undefined {
		return this.entries.get(key.toLowerCase())?.value;
	}

	set(key: string, value: V): void {
		const lower = key.toLowerCase();
		const existing = this.entries.get(lower);
		this.entries.set(lower, { key: existing ? existing.key : key, value });
	}

	keys(): string[] {
		return [...this.entries.values()].map((e) => e.key);
	}

	toObject(): Record<string, V> {
		const out: Record<string, V> = {};
		for (const e of this.entries.values()) out[e.key] = e.value;
		return out;
	}

	static fromObject<V>(obj: Record<string, V>): NoCaseMap<V> {
		const map = new NoCaseMap<V>();
		for (const [k, v] of Object.entries(obj)) map.set(k, v);
		return map;
	}
}
