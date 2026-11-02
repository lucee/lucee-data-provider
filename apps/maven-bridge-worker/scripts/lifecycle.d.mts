export interface LifecycleRule {
	id: string;
	enabled: boolean;
	conditions: { prefix: string };
	deleteObjectsTransition?: { condition: { type: string; maxAge?: number; date?: string } };
	abortMultipartUploadsTransition?: { condition: { type: string; maxAge?: number } };
	storageClassTransitions?: unknown[];
}

export const DEFAULT_SNAPSHOT_PREFIX: string;
export const DEFAULT_SNAPSHOT_RETENTION_DAYS: number;
export const SNAPSHOT_RULE_ID: string;
export function normalizeSnapshotPrefix(value: unknown): string;
export function parseRetentionDays(value: unknown): number;
export function readTomlVar(toml: string, name: string): string | undefined;
export function snapshotExpiryRule(prefix: string, days: number): LifecycleRule | null;
export function mergeLifecycleRules(existing: unknown, rule: LifecycleRule | null): { rules: LifecycleRule[]; changed: boolean };
