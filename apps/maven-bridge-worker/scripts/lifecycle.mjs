// R2 lifecycle settings shared by the worker (src/config.ts) and scripts/provision.mjs.
// SNAPSHOT files are stored under their own key prefix, because lifecycle rules only
// match by key prefix and SNAPSHOT and release files share their Maven folders.

export const DEFAULT_SNAPSHOT_PREFIX = "snapshots/";
export const DEFAULT_SNAPSHOT_RETENTION_DAYS = 90;
export const SNAPSHOT_RULE_ID = "lucee-maven-bridge-snapshot-expiry";

/** R2_SNAPSHOT_PREFIX: blank = default, no leading slash, always ends with a slash. */
export function normalizeSnapshotPrefix(value) {
	const raw = String(value ?? "").trim().replace(/^\/+/, "");
	if (!raw.length) return DEFAULT_SNAPSHOT_PREFIX;
	return raw.endsWith("/") ? raw : raw + "/";
}

/** R2_SNAPSHOT_RETENTION_DAYS: blank = default, 0 = keep SNAPSHOT files forever (no rule). */
export function parseRetentionDays(value) {
	const raw = String(value ?? "").trim();
	if (!raw.length) return DEFAULT_SNAPSHOT_RETENTION_DAYS;
	if (!/^\d+$/.test(raw)) throw new Error(`Invalid R2_SNAPSHOT_RETENTION_DAYS [${value}]`);
	return Number(raw);
}

/** Value of a plain string entry (NAME = "value") in wrangler.toml, undefined when missing. */
export function readTomlVar(toml, name) {
	const match = new RegExp(`^\\s*${name}\\s*=\\s*"([^"]*)"`, "m").exec(toml);
	return match ? match[1] : undefined;
}

/** Lifecycle rule deleting SNAPSHOT objects `days` after they were stored, null for 0 days. */
export function snapshotExpiryRule(prefix, days) {
	if (!days) return null;
	if (!prefix.length) throw new Error("A SNAPSHOT expiry rule needs a key prefix, an empty prefix would match every object");
	return {
		id: SNAPSHOT_RULE_ID,
		enabled: true,
		conditions: { prefix },
		deleteObjectsTransition: { condition: { type: "Age", maxAge: days * 86400 } }
	};
}

function sameRule(a, b) {
	return (
		a.enabled === b.enabled &&
		(a.conditions?.prefix ?? "") === b.conditions.prefix &&
		a.deleteObjectsTransition?.condition?.type === b.deleteObjectsTransition.condition.type &&
		a.deleteObjectsTransition?.condition?.maxAge === b.deleteObjectsTransition.condition.maxAge &&
		!a.abortMultipartUploadsTransition &&
		!(a.storageClassTransitions ?? []).length
	);
}

/**
 * The bucket's rules with the SNAPSHOT rule set (or removed when `rule` is null). Every other
 * rule is kept as it is, because the lifecycle PUT replaces all rules of the bucket.
 * `changed` is false when the bucket already has exactly this state.
 */
export function mergeLifecycleRules(existing, rule) {
	const current = Array.isArray(existing) ? existing : [];
	const ours = current.filter((r) => r?.id === SNAPSHOT_RULE_ID);
	const others = current.filter((r) => r?.id !== SNAPSHOT_RULE_ID);
	if (!rule) return { rules: others, changed: ours.length > 0 };
	const changed = ours.length !== 1 || !sameRule(ours[0], rule);
	return { rules: [...others, rule], changed };
}
