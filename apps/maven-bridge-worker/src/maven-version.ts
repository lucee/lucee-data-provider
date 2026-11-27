// Maven ComparableVersion ordering (org.apache.maven.artifact.versioning.ComparableVersion), the same rules as
// lucee/Lucee .github/scripts/maven-group-metadata.js: numeric segments compare numerically, a qualifier sorts
// before the plain release of the same number and the known qualifiers are ordered
// alpha < beta < milestone < rc < snapshot < (release) < sp, unknown qualifiers after sp (lexically).
// So 5.0.0.60-BETA < 5.0.0.252, 8.0.0.304-RC < 8.0.0.304 and 7.1.3.0-SNAPSHOT < 7.1.3.0.

const QUALIFIERS = ["alpha", "beta", "milestone", "rc", "snapshot", "", "sp"];
const QUALIFIER_ALIASES: Record<string, string> = { ga: "", final: "", release: "", cr: "rc" };
const RELEASE_INDEX = String(QUALIFIERS.indexOf(""));

type Item = { type: "int"; value: bigint } | { type: "string"; value: string } | { type: "list"; items: Item[] };
type ListItem = { type: "list"; items: Item[] };

function comparableQualifier(q: string): string {
	const i = QUALIFIERS.indexOf(q);
	return i === -1 ? `${QUALIFIERS.length}-${q}` : String(i);
}

function stringItem(value: string, followedByDigit: boolean): Item {
	if (followedByDigit && value.length === 1) value = ({ a: "alpha", b: "beta", m: "milestone" } as Record<string, string>)[value] ?? value;
	return { type: "string", value: QUALIFIER_ALIASES[value] ?? value };
}

function parseItem(isDigit: boolean, buf: string): Item {
	return isDigit ? { type: "int", value: BigInt(buf) } : stringItem(buf, false);
}

function isNullItem(item: Item): boolean {
	if (item.type === "int") return item.value === 0n;
	if (item.type === "string") return comparableQualifier(item.value) === RELEASE_INDEX;
	return item.items.length === 0;
}

function normalize(list: ListItem): void {
	for (let i = list.items.length - 1; i >= 0; i--) {
		const item = list.items[i];
		if (isNullItem(item)) list.items.splice(i, 1);
		else if (item.type !== "list") break;
	}
}

function parse(version: string): ListItem {
	const v = version.trim().toLowerCase();
	const root: ListItem = { type: "list", items: [] };
	let list = root;
	const stack: ListItem[] = [root];
	let isDigit = false;
	let start = 0;
	const push = () => {
		const sub: ListItem = { type: "list", items: [] };
		list.items.push(sub);
		list = sub;
		stack.push(sub);
	};
	for (let i = 0; i < v.length; i++) {
		const c = v[i];
		if (c === "." || c === "-") {
			list.items.push(i === start ? { type: "int", value: 0n } : parseItem(isDigit, v.slice(start, i)));
			start = i + 1;
			if (c === "-") push();
		} else if (c >= "0" && c <= "9") {
			if (!isDigit && i > start) {
				list.items.push(stringItem(v.slice(start, i), true));
				start = i;
				push();
			}
			isDigit = true;
		} else {
			if (isDigit && i > start) {
				list.items.push(parseItem(true, v.slice(start, i)));
				start = i;
				push();
			}
			isDigit = false;
		}
	}
	if (v.length > start) list.items.push(parseItem(isDigit, v.slice(start)));
	while (stack.length) normalize(stack.pop()!);
	return root;
}

function cmp(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

function compareItems(a: Item, b?: Item): number {
	if (b === undefined) {
		if (a.type === "int") return a.value === 0n ? 0 : 1;
		if (a.type === "string") return cmp(comparableQualifier(a.value), RELEASE_INDEX);
		return a.items.length ? compareItems(a.items[0]) : 0;
	}
	if (a.type === "int") {
		if (b.type !== "int") return 1;
		return a.value < b.value ? -1 : a.value > b.value ? 1 : 0;
	}
	if (a.type === "string") {
		if (b.type !== "string") return -1;
		return cmp(comparableQualifier(a.value), comparableQualifier(b.value));
	}
	if (b.type === "int") return -1;
	if (b.type === "string") return 1;
	const n = Math.max(a.items.length, b.items.length);
	for (let i = 0; i < n; i++) {
		const l = a.items[i];
		const r = b.items[i];
		const result = l === undefined ? (r === undefined ? 0 : -compareItems(r)) : compareItems(l, r);
		if (result !== 0) return result;
	}
	return 0;
}

/** Compares two Maven versions, <0, 0 or >0 (ComparableVersion semantics, case-insensitive). */
export function compareVersions(a: string, b: string): number {
	return compareItems(parse(a), parse(b));
}

/** Maven version order, oldest first; ties (e.g. 1.0 and 1.0.0) keep a deterministic order. */
export function sortVersions(versions: Iterable<string>): string[] {
	const parsed = new Map<string, ListItem>();
	const key = (v: string) => {
		let p = parsed.get(v);
		if (!p) parsed.set(v, (p = parse(v)));
		return p;
	};
	return [...versions].sort((a, b) => compareItems(key(a), key(b)) || cmp(a, b));
}

/** true when the version string contains -SNAPSHOT (Maven metadata <release> excludes these). */
export function isSnapshotVersion(version: string): boolean {
	return version.toUpperCase().includes("-SNAPSHOT");
}

/**
 * Highest non-SNAPSHOT version in a list already sorted oldest-first.
 * RC, BETA and ALPHA count as a release, matching the files written for cdn.lucee.org.
 */
export function findLatestRelease(sortedVersions: readonly string[]): string {
	for (let i = sortedVersions.length - 1; i >= 0; i--) {
		if (!isSnapshotVersion(sortedVersions[i])) return sortedVersions[i];
	}
	return "";
}
