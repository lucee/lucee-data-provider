component {

	public function init(required array providers, required struct sharedConfig) {
		variables.supports = {};
		for (var entry in arguments.providers) {
			var config = duplicate(arguments.sharedConfig);
			config.provider = trim(entry.provider);
			config.groupId = trim(entry.groupId);
			config.upstream = trim(entry.upstream ?: "");
			if (!len(config.provider) || !len(config.groupId)) {
				continue;
			}
			variables.supports[config.groupId] = new org.lucee.mavenbridge.BridgeSupport(config);
		}
		if (!structCount(variables.supports)) {
			throw(message="No extension providers configured", type="bridge.config");
		}
		return this;
	}

	public struct function resolve(required string path) {
		for (var support in getSupportsByPathLength()) {
			var parsed = support.parseMavenPath(arguments.path);
			if (parsed.type != "unknown") {
				return { "support": support, "parsed": parsed };
			}
		}
		return { "parsed": { "type": "unknown" } };
	}

	public array function getProviders() {
		var providers = [];
		for (var groupId in structKeyArray(variables.supports)) {
			var support = variables.supports[groupId];
			arrayAppend(providers, {
				"provider": support.getProviderUrl(),
				"groupId": support.getGroupId(),
				"upstream": support.hasUpstream() ? support.getUpstreamUrl() : ""
			});
		}
		arraySort(providers, function(a, b) {
			return compareNoCase(a.groupId, b.groupId);
		});
		return providers;
	}

	public any function getSupport(required string groupId) {
		return variables.supports[arguments.groupId];
	}

	public array function getSupports() {
		return getSupportsByPathLength();
	}

	public string function describe() {
		var lines = [
			"Lucee extension provider Maven bridge",
			"Providers: #arrayLen(getProviders())#",
			""
		];
		for (var support in getSupportsByPathLength()) {
			arrayAppend(lines, support.describe());
			arrayAppend(lines, "");
		}
		return arrayToList(lines, chr(10));
	}

	public void function syncAll(required string webroot) {
		for (var groupId in structKeyArray(variables.supports)) {
			variables.supports[groupId].syncRepository(arguments.webroot);
		}
	}

	public void function flushAll(required string webroot) {
		for (var groupId in structKeyArray(variables.supports)) {
			variables.supports[groupId].flushCache(arguments.webroot);
		}
	}

	public static array function parseProviders(required string env) {
		var raw = trim(arguments.env);
		if (!len(raw)) {
			return [];
		}
		if (left(raw, 1) == "[") {
			return normalizeProviderEntries(deserializeJSON(raw));
		}
		return normalizeProviderEntries(listToArray(raw));
	}

	public static array function defaultProviders() {
		return [
			{ "provider": "https://www.forgebox.io", "groupId": "io.forgebox" },
			{ "provider": "https://extension.lucee.org", "groupId": "org.lucee", "upstream": "https://cdn.lucee.org/" }
		];
	}

	private static array function normalizeProviderEntries(required array entries) {
		var providers = [];
		for (var entry in arguments.entries) {
			if (isStruct(entry)) {
				if (len(trim(entry.provider ?: "")) && len(trim(entry.groupId ?: ""))) {
					var providerEntry = {
						"provider": trim(entry.provider),
						"groupId": trim(entry.groupId)
					};
					if (len(trim(entry.upstream ?: ""))) {
						providerEntry["upstream"] = trim(entry.upstream);
					}
					arrayAppend(providers, providerEntry);
				}
				continue;
			}
			var pair = trim(toString(entry));
			if (!len(pair)) {
				continue;
			}
			var segments = listToArray(pair, "|");
			if (arrayLen(segments) < 2) {
				continue;
			}
			var providerEntry = {
				"provider": trim(segments[1]),
				"groupId": trim(segments[2])
			};
			if (arrayLen(segments) >= 3 && len(trim(segments[3]))) {
				providerEntry["upstream"] = trim(segments[3]);
			}
			arrayAppend(providers, providerEntry);
		}
		return providers;
	}

	private array function getSupportsByPathLength() {
		var supports = [];
		for (var groupId in structKeyArray(variables.supports)) {
			arrayAppend(supports, variables.supports[groupId]);
		}
		arraySort(supports, function(a, b) {
			return compare(len(replace(b.getGroupId(), ".", "/", "all")), len(replace(a.getGroupId(), ".", "/", "all")));
		});
		return supports;
	}
}
