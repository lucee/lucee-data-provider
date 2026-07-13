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
			var prefixHtml = buildGroupPrefixIndexHtml(registry, cleanPath);
			if (len(prefixHtml)) {
				return htmlResponse(200, prefixHtml);
			}
			return textResponse(404, "text/plain; charset=utf-8", "Not found");
		}

		var support = resolved.support;
		var parsed = resolved.parsed;

		try {
			if (support.hasUpstream() && isUpstreamContentType(parsed.type)) {
				return upstreamContentResponse(support, parsed);
			}

			switch (parsed.type) {
				case "group-index":
					return htmlResponse(200, support.buildGroupIndexHtml());
				case "group-metadata":
					return xmlResponse(200, support.buildGroupMetadata());
				case "artifact-index":
					return htmlResponse(200, support.buildArtifactIndexHtml(parsed.artifactId));
				case "artifact-metadata":
					return xmlResponse(200, support.buildArtifactMetadata(parsed.artifactId));
				case "version-index":
					return htmlResponse(200, support.buildVersionIndexHtml(parsed.artifactId, parsed.version));
				case "version-metadata":
					return xmlResponse(200, support.buildVersionMetadata(parsed.artifactId, parsed.version));
				case "artifact-file":
					return artifactFileResponse(support, parsed);
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
		return server.bridgeRegistry;
	}

	private struct function artifactFileResponse(required any support, required struct parsed) {
		// upstream mirrors serve files from the upstream repo only, never from the REST provider
		if (support.hasUpstream()) {
			// core "lucee" files are canonical at the upstream root (legacy layout)
			var legacyPath = support.toUpstreamLegacyCorePath(arguments.parsed);
			if (len(legacyPath)) {
				if (support.upstreamResourceExists(legacyPath)) {
					return redirectResponse(support.getUpstreamUrl() & legacyPath);
				}
				return textResponse(404, "text/plain; charset=utf-8", "Not found");
			}
			var upstreamPath = support.toUpstreamRelativePath(arguments.parsed);
			if (support.upstreamResourceExists(upstreamPath)) {
				return redirectResponse(support.getUpstreamUrl() & upstreamPath);
			}
			return textResponse(404, "text/plain; charset=utf-8", "Not found");
		}

		if (arguments.parsed.extension == "pom") {
			return xmlResponse(200, support.buildMinimalPom(arguments.parsed.artifactId, arguments.parsed.version));
		}

		var downloadUrl = support.getDownloadUrl(arguments.parsed.artifactId, arguments.parsed.version);
		if (!len(downloadUrl)) {
			return textResponse(404, "text/plain; charset=utf-8", "No [#arguments.parsed.extension#] artifact for [#support.getGroupId()#:#arguments.parsed.artifactId#:#arguments.parsed.version#]");
		}

		return redirectResponse(downloadUrl);
	}

	private boolean function isUpstreamContentType(required string type) {
		return listFindNoCase(
			"group-index,group-metadata,artifact-index,artifact-metadata,version-index,version-metadata",
			arguments.type
		) > 0;
	}

	private struct function upstreamContentResponse(required any support, required struct parsed) {
		// upstream mirrors are pass-through: what the upstream has is what we serve,
		// a 404 upstream stays a 404 (no synthesis from the REST provider)
		var relativePath = support.toUpstreamRelativePath(arguments.parsed);
		try {
			var content = support.getCachedUpstreamContent(server.bridgeWebroot, relativePath);
			return textResponse(200, content.contentType, content.body);
		} catch (any e) {
			if (e.type != "bridge.upstream.notfound") {
				rethrow;
			}
		}
		return upstreamSynthesizedResponse(arguments.support, arguments.parsed);
	}

	// the upstream repo only publishes browsable indexes at group level; artifact and
	// version pages are built from the upstream maven-metadata.xml (never the REST provider)
	private struct function upstreamSynthesizedResponse(required any support, required struct parsed) {
		switch (arguments.parsed.type) {
			case "artifact-index":
				return htmlResponse(200, support.buildArtifactIndexHtml(
					parsed.artifactId,
					support.listUpstreamVersions(server.bridgeWebroot, parsed.artifactId)
				));
			case "version-index":
				if (!arrayFindNoCase(support.listUpstreamVersions(server.bridgeWebroot, parsed.artifactId), parsed.version)) {
					return textResponse(404, "text/plain; charset=utf-8", "Not found");
				}
				return htmlResponse(200, support.buildUpstreamVersionIndexHtml(server.bridgeWebroot, parsed.artifactId, parsed.version));
			case "version-metadata":
				// only snapshots have version-level metadata; built from the version string alone
				if (findNoCase("-SNAPSHOT", parsed.version)
					&& arrayFindNoCase(support.listUpstreamVersions(server.bridgeWebroot, parsed.artifactId), parsed.version)) {
					return xmlResponse(200, support.buildVersionMetadata(parsed.artifactId, parsed.version));
				}
				return textResponse(404, "text/plain; charset=utf-8", "Not found");
			default:
				return textResponse(404, "text/plain; charset=utf-8", "Not found");
		}
	}

	// index for path segments above the group level (/org, /io): lists the next
	// segment of every configured group under that prefix
	private string function buildGroupPrefixIndexHtml(required any registry, required string path) {
		var children = {};
		for (var support in registry.getSupports()) {
			var groupPath = "/" & replace(support.getGroupId(), ".", "/", "all");
			if (left(groupPath, len(arguments.path) + 1) == arguments.path & "/") {
				var remainder = mid(groupPath, len(arguments.path) + 2);
				children[listFirst(remainder, "/")] = true;
			}
		}
		if (!structCount(children)) {
			return "";
		}
		var names = structKeyArray(children);
		arraySort(names, "textnocase");
		var title = mid(arguments.path, 2);
		var html = [
			"<!DOCTYPE html>",
			"<html><head><title>#encodeForHtml(title)#</title></head><body>",
			"<h1>#encodeForHtml(title)#</h1>",
			"<pre>"
		];
		for (var name in names) {
			arrayAppend(html, '<a href="#encodeForHtml(arguments.path)#/#encodeForHtml(name)#/">#encodeForHtml(name)#/</a>' & chr(10));
		}
		arrayAppend(html, "</pre></body></html>");
		return arrayToList(html, chr(10));
	}

	private struct function redirectResponse(required string location) {
		return {
			"statusCode": 302,
			"contentType": "text/plain; charset=utf-8",
			"location": arguments.location,
			"body": ""
		};
	}

	private struct function healthResponse(required any registry) {
		var providers = [];
		var artifactCount = 0;
		for (var support in registry.getSupports()) {
			var provider = {
				"provider": support.getProviderUrl(),
				"groupId": support.getGroupId()
			};
			if (support.hasUpstream()) {
				provider["upstream"] = support.getUpstreamUrl();
				provider["mode"] = "upstream-mirror";
			} else {
				var index = support.getIndex();
				artifactCount += structCount(index.artifacts);
				provider["artifactCount"] = structCount(index.artifacts);
				provider["cachedAt"] = index.cachedAt;
				provider["mode"] = "rest-provider";
			}
			arrayAppend(providers, provider);
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
