// Port of BridgeRegistry.cfc
import { compare, compareNoCase, NoCaseMap } from "./cfml";
import type { BridgeConfig } from "./config";
import { BridgeError } from "./errors";
import { BridgeSupport, type ParsedPath, type SupportIo } from "./support";

export class BridgeRegistry {
	private readonly supports = new NoCaseMap<BridgeSupport>();

	constructor(config: BridgeConfig, io: SupportIo) {
		for (const entry of config.providers) {
			const provider = entry.provider.trim();
			const groupId = entry.groupId.trim();
			if (!provider.length || !groupId.length) continue;
			const support = new BridgeSupport({
				provider,
				groupId,
				upstream: (entry.upstream ?? "").trim(),
				cacheTtlMinutes: config.cacheTtlMinutes,
				timeout: config.timeout,
				githubReleasesUrl: config.githubReleasesUrl
			});
			support.io = io;
			this.supports.set(groupId, support);
		}
		if (!this.supports.size) throw new BridgeError("No extension providers configured", "bridge.config");
	}

	/**
	 * Supports ordered like getSupportsByPathLength(); the CFML comparator compares
	 * the path lengths as strings, which is kept so the health output stays identical.
	 */
	getSupports(): BridgeSupport[] {
		const list = this.supports.keys().map((k) => this.supports.get(k)!);
		return list.sort((a, b) => compare(String(b.groupPath.length), String(a.groupPath.length)));
	}

	getSupport(groupId: string): BridgeSupport | undefined {
		return this.supports.get(groupId);
	}

	/** Providers sorted by groupId (used by the landing page). */
	getProviders(): BridgeSupport[] {
		return this.supports.keys().map((k) => this.supports.get(k)!).sort((a, b) => compareNoCase(a.groupId, b.groupId));
	}

	resolve(path: string): { support?: BridgeSupport; parsed: ParsedPath } {
		for (const support of this.getSupports()) {
			const parsed = support.parseMavenPath(path);
			if (parsed.type !== "unknown") return { support, parsed };
		}
		return { parsed: { type: "unknown" } };
	}
}
