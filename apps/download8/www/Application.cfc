component {
	this.name = "lucee-downloads";
	variables.maxAge=60*60; // 1 hour
	// variables.maxAge=10; // 10 seconds
	this.componentMappings = [
      {
         "physical": "/var/components/",
         "archive": "",
         "primary": "physical"
      }
   ];

	function onRequestStart() {
		// note: ?flush no longer re-inits util — a page flush must not wipe the shared
		// in-memory data caches. Component code changes are picked up on redeploy/restart.
		if(isNull(application.util)) {
			application.util = new org.lucee.download.Util();
		}
	}

	// only these params affect page content — everything else is ignored in the cache key
	variables.cacheParams = {
		"/index.cfm":        [],
		"/extension.cfm":    ["groupId", "artifactId"],
		"/changelog.cfm":    ["version"],
		"/versions.cfm":     ["track", "type", "minor"],
		"/versionlinks.cfm": ["version"],
		"/download.cfm":     ["version", "type"]
	};

	function onRequest(template) {
var allowedParams = variables.cacheParams[arguments.template] ?: [];
		var cacheQS = "";
		for (var p in allowedParams) {
			if (!isNull(url[p])) cacheQS &= (len(cacheQS) ? "&" : "") & p & "=" & url[p];
		}
		var filename=application.util.getCacheFile(arguments.template, cacheQS);
		// ?flush=true flushes ONLY the current page's cached HTML — not the whole site,
		// and not the shared data caches. The page then re-renders from the existing
		// metadata caches (github logos are resolved to the CDN at render time).
		var flush=url.flush ?: false;
		if (flush && fileExists(filename)) {
			fileDelete(filename);
		}
		if(fileExists(filename)) {
			echo(fileRead(filename));
			var expired=getTickCount()>(fileInfo(filename).dateLastModified.getTime()+((variables.maxAge-1)*1000));
			if(expired) {
				lock name="cache-#filename#" type="exclusive" timeout="0" throwOnTimeout=false {
					thread action="run" name="cache-regen-#filename#-#getTickCount()#" template=template filename=filename {
						load(attributes.template, attributes.filename);
					}
				}
			}
		}
		else {
			echo(load(arguments.template,filename));
		}
		
	}

	private function load(template,filename) {
		saveContent variable="local.content" {
			include template;
			echo("<!-- cached at #now()# -->");
		}
		if (!isNull(request.skipHtmlCache) && request.skipHtmlCache) return local.content;
		fileWrite(filename,local.content);
		return local.content;
	}
}
