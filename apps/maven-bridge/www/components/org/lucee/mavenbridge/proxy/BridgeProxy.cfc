component {

	public struct function invoke(required string path) {
		// Tomcat maps /org/* to CFML; treat missing path as group index
		if (arguments.path == "/index.cfm") {
			arguments.path = "/";
		}
		return invokePath(arguments.path);
	}

	private struct function invokePath(required string path) {
		var registry = getRegistry();
		var cleanPath = normalizePath(arguments.path);

		if (cleanPath == "/health" || cleanPath == "/healthcheck") {
			return healthResponse(registry);
		}

		if (cleanPath == "/") {
			return textResponse(200, "text/plain; charset=utf-8", registry.describe());
		}

		var resolved = registry.resolve(cleanPath);
		if (resolved.parsed.type == "unknown") {
			return textResponse(404, "text/plain; charset=utf-8", "Not found");
		}

		var support = resolved.support;
		var parsed = resolved.parsed;

		try {
			switch (parsed.type) {
				case "group-index":
					return htmlResponse(200, support.buildGroupIndexHtml());
				case "group-metadata":
					return xmlResponse(200, support.buildGroupMetadata());
				case "artifact-metadata":
					return xmlResponse(200, support.buildArtifactMetadata(parsed.artifactId));
				case "version-metadata":
					return xmlResponse(200, support.buildVersionMetadata(parsed.artifactId, parsed.version));
				case "artifact-file":
					return artifactFileResponse(support, parsed.artifactId, parsed.version, parsed.extension);
				default:
					return textResponse(404, "text/plain; charset=utf-8", "Not found");
			}
		} catch (any e) {
			return textResponse(404, "text/plain; charset=utf-8", e.message ?: "Not found");
		}
	}

	public void function render(required struct response) {
		cfcontent(reset=true, type=arguments.response.contentType);
		if (structKeyExists(arguments.response, "statusCode")) {
			cfheader(statuscode=arguments.response.statusCode);
		}
		if (len(arguments.response.location ?: "")) {
			header name="Location" value=arguments.response.location;
		}
		writeOutput(arguments.response.body ?: "");
	}

	private function getRegistry() {
		return application.bridgeRegistry;
	}

	private struct function artifactFileResponse(required any support, required string artifactId, required string version, required string extension) {
		if (arguments.extension == "pom") {
			return xmlResponse(200, support.buildMinimalPom(arguments.artifactId, arguments.version));
		}

		var downloadUrl = support.getDownloadUrl(arguments.artifactId, arguments.version);
		if (!len(downloadUrl)) {
			return textResponse(404, "text/plain; charset=utf-8", "No [#arguments.extension#] artifact for [#support.getGroupId()#:#arguments.artifactId#:#arguments.version#]");
		}

		return {
			"statusCode": 302,
			"contentType": "text/plain; charset=utf-8",
			"location": downloadUrl,
			"body": ""
		};
	}

	private struct function healthResponse(required any registry) {
		var providers = [];
		var artifactCount = 0;
		for (var support in registry.getSupports()) {
			var index = support.getIndex();
			artifactCount += structCount(index.artifacts);
			arrayAppend(providers, {
				"provider": support.getProviderUrl(),
				"groupId": support.getGroupId(),
				"artifactCount": structCount(index.artifacts),
				"cachedAt": index.cachedAt
			});
		}

		var body = {
			"status": "ok",
			"providers": providers,
			"artifactCount": artifactCount
		};
		if (structKeyExists(url, "flush")) {
			var flush = url.flush;
			if ((isBoolean(flush) && flush) || listFindNoCase("1,true,yes,force", trim(toString(flush))) > 0) {
				body["flushed"] = true;
			}
		}
		return {
			"statusCode": 200,
			"contentType": "application/json; charset=utf-8",
			"body": serializeJSON(body)
		};
	}

	private struct function textResponse(required numeric statusCode, required string contentType, required string body) {
		return { "statusCode": arguments.statusCode, "contentType": arguments.contentType, "body": arguments.body };
	}

	private struct function xmlResponse(required numeric statusCode, required string body) {
		return textResponse(arguments.statusCode, "application/xml; charset=utf-8", arguments.body);
	}

	private struct function htmlResponse(required numeric statusCode, required string body) {
		return textResponse(arguments.statusCode, "text/html; charset=utf-8", arguments.body);
	}

	private string function normalizePath(required string path) {
		var p = replace(arguments.path, "\", "/", "all");
		while (find("//", p)) {
			p = replace(p, "//", "/", "all");
		}
		if (right(p, 10) == "/index.cfm") {
			p = left(p, len(p) - 9);
		}
		if (len(p) > 1 && right(p, 1) == "/") {
			p = left(p, len(p) - 1);
		}
		return len(p) ? p : "/";
	}
}
