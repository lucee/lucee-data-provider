// Ports of services/VersionUtils.cfc and the version helpers of services/ExtensionMetadataReader.cfc,
// including the way CFML compares simple values, so versions sort and filter exactly the same.

/** CFML ListToArray( value, delimiter ): empty elements are dropped */
export function listToArray(value: string, delimiter: string): string[] {
	return String(value)
		.split(delimiter)
		.filter((part) => part.length > 0);
}

/** CFML isNumeric() for the values versions are made of */
export function isNumeric(value: unknown): boolean {
	if (typeof value === "number") return Number.isFinite(value);
	return /^\s*[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\s*$/.test(String(value));
}

/**
 * How CFML compares two simple values with <, >, ==: as numbers when both are numeric, otherwise as
 * strings, ignoring case.
 */
export function cfCompare(a: unknown, b: unknown): number {
	if (isNumeric(a) && isNumeric(b)) {
		const x = Number(a);
		const y = Number(b);
		return x < y ? -1 : x > y ? 1 : 0;
	}
	return compareNoCase(String(a ?? ""), String(b ?? ""));
}

/** CFML compareNoCase() */
export function compareNoCase(a: string, b: string): number {
	const x = a.toLowerCase();
	const y = b.toLowerCase();
	return x < y ? -1 : x > y ? 1 : 0;
}

/** CFML compare() */
export function compare(a: string, b: string): number {
	return a < b ? -1 : a > b ? 1 : 0;
}

function repStr(str: string, amount: number): string {
	return amount < 1 ? "" : str.repeat(amount);
}

function num(value: string): string {
	return String(Number(value));
}

/**
 * VersionUtils::sortableVersionString(): an OSGi version as a string that sorts like the version,
 * "7.1.2.191-SNAPSHOT" > "07.001.002.0191.000".
 */
export function sortableVersionString(version: string): string {
	const arr = listToArray(version, ".");

	if (arr.length !== 4 || !isNumeric(arr[0]) || !isNumeric(arr[1]) || !isNumeric(arr[2])) {
		// fallback for non-4-part versions (e.g. "13.2.1" or "6.2.1-jre8")
		let rtn = "";
		for (let i = 1; i <= arr.length; i++) {
			let v = arr[i - 1].replace(/[a-zA-Z-]/g, "");
			const paddingLength = i === 1 ? 2 : i === 2 || i === 3 ? 3 : 4;
			v = v.length < paddingLength ? "0".repeat(paddingLength - v.length) + v : v;
			rtn += (i === 1 ? "" : ".") + v;
		}
		if (arr.length <= 3) rtn += ".0000";
		return rtn;
	}

	const major = num(arr[0]);
	const minor = num(arr[1]);
	const micro = num(arr[2]);
	let qualifier = "0";
	let appendixNbr = "100";

	const qArr = listToArray(arr[3], "-");
	if (qArr.length === 1 && isNumeric(qArr[0])) {
		qualifier = num(qArr[0]);
	} else if (qArr.length === 2 && isNumeric(qArr[0])) {
		qualifier = num(qArr[0]);
		const appendix = qArr[1].toUpperCase(); // == in CFML ignores case
		appendixNbr = appendix === "SNAPSHOT" ? "0" : appendix === "BETA" ? "50" : "75";
	} else {
		qualifier = qArr.length && isNumeric(qArr[0]) ? num(qArr[0]) : "0";
		appendixNbr = "75";
	}

	return (
		repStr("0", 2 - major.length) + major +
		"." + repStr("0", 3 - minor.length) + minor +
		"." + repStr("0", 3 - micro.length) + micro +
		"." + repStr("0", 4 - qualifier.length) + qualifier +
		"." + repStr("0", 3 - appendixNbr.length) + appendixNbr
	);
}

/**
 * VersionUtils::checkVersionGTE(): is the given core version (major, minor, patch, build) at least the
 * given (minimum) version?
 */
export function checkVersionGTE(version: string, major: unknown, minor: unknown = "", patch: unknown = "", build: unknown = ""): boolean {
	const v: unknown[] = listToArray(version, ".");
	while (v.length < 4) v.push(0);

	if (cfCompare(v[0], major) > 0) return false;
	if (cfCompare(v[0], major) < 0) return true;
	if (cfCompare(v[1], minor) > 0) return false;
	if (cfCompare(v[1], minor) < 0) return true;
	if (cfCompare(v[2], patch) > 0) return false;
	if (cfCompare(v[2], patch) < 0) return true;
	return cfCompare(v[3], build) <= 0;
}

/**
 * The parts of a core version as the CFML code uses them (ListToArray( coreVersion, "." )). Parts that
 * are missing are empty strings (the CFML code fails on a core version of less than 4 parts, see README).
 */
export function coreVersionParts(coreVersion: string): [string, string, string, string] {
	const v = listToArray(coreVersion, ".");
	return [v[0] ?? "", v[1] ?? "", v[2] ?? "", v[3] ?? ""];
}

/** _fitsCoreVersion(): can a core version (of 4 parts) load an extension with the given min core version? When in doubt: yes */
export function fitsCoreVersion(minCore: string, coreVersion: string): boolean {
	const v = listToArray(coreVersion, ".");
	if (!minCore.length || v.length < 4) return true;
	return checkVersionGTE(minCore, v[0], v[1], v[2], v[3]);
}

function findNoCase(needle: string, haystack: string): boolean {
	return haystack.toLowerCase().includes(needle.toLowerCase());
}

/**
 * _matchesReleaseType(): "snapshot": only snapshots, "abc": only alphas, betas and release candidates,
 * "release": finals only, any other type (including "all"): every version.
 */
export function matchesReleaseType(version: string, type: string): boolean {
	switch (type.toLowerCase()) {
		case "snapshot":
			return findNoCase("-SNAPSHOT", version);
		case "abc":
			return findNoCase("-ALPHA", version) || findNoCase("-BETA", version) || findNoCase("-RC", version);
		case "release":
			return !findNoCase("-ALPHA", version) && !findNoCase("-BETA", version) && !findNoCase("-RC", version) && !findNoCase("-SNAPSHOT", version);
	}
	return true;
}

/** _effectiveMinCore(): the min core version of the manifest, or mavenOnlyMinCore for a Maven packaged extension when that is higher */
export function effectiveMinCore(minCore: string, packaging: string, mavenOnlyMinCore: string): string {
	if (!mavenOnlyMinCore.length || packaging !== "maven") return minCore;
	if (!minCore.length) return mavenOnlyMinCore;
	return compare(sortableVersionString(mavenOnlyMinCore), sortableVersionString(minCore)) > 0 ? mavenOnlyMinCore : minCore;
}
