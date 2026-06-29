<cfinclude template="../functions.cfm">
<cfscript>
cacheSetDirectory(server.system.environment.CACHE_DIRECTORY ?: getDirectoryFromPath(getDirectoryFromPath(getCurrentTemplatePath())));

ver = url.version ?: "";
if (!len(ver)) {
	cfheader(statusCode=400, statusText="Bad Request");
	writeOutput("{}");
	abort;
}

function buildLinks(ver) {
	local.cacheKey = "luceeVerDetail_" & ver;
	local.detail   = cacheGet(local.cacheKey);
	if (isEmpty(local.detail)) {
		try {
			local.detail = LuceeVersionsDetail(ver);
			cachePut(local.cacheKey, local.detail);
		} catch(e) { local.detail = {}; }
	}
	local.isRelease = (getType(ver) == "release");
	local.links = local.isRelease ? cdnLinks(formatVersion(ver)) : {};
	for (local.k in local.detail) {
		if (local.k != "lastModified" && local.k != "pom" && len(local.detail[local.k])) {
			local.links[local.k] = local.detail[local.k];
		}
	}
	return local.links;
}

DL_INFO = {
	"win64":         "Windows x64 installer — guided setup wizard, installs Lucee as a Windows service with Tomcat included.",
	"linux-x64":     "Linux x64 installer — shell installer for 64-bit Linux, sets up Lucee as a system service with Tomcat.",
	"linux-aarch64": "Linux aarch64 installer — same as the x64 installer but for ARM64 (Apple Silicon, Ampere, AWS Graviton).",
	"express":       "Express ZIP — no installation needed. Unzip and run the start script. Ideal for local development or quick evaluation.",
	"jar":           "lucee.jar — drop into your servlet engine's lib/classpath folder. Lucee will download any missing dependency bundles on first start.",
	"light":         "lucee-light.jar — minimal Lucee jar with no bundled extensions. Smaller footprint; extensions are fetched on demand.",
	"lco":           "Core (.lco) — Lucee Core update file. Copy to the patches/ folder of an existing installation to update the core without reinstalling.",
	"war":           "WAR — Web ARchive for deployment on any Java Servlet container (Tomcat, Jetty, WildFly, etc.).",
	"zero":          "lucee-zero.jar — Lucee with zero bundled extensions. The smallest possible footprint; every extension is loaded on demand.",
	"docker":        "Docker Images — pre-built Lucee + Tomcat images on Docker Hub. Best for containerised and cloud deployments."
};

lnk = buildLinks(ver);
cfheader(name="Content-Type", value="text/html; charset=utf-8");
</cfscript>
<cfoutput>
<div class="dl-links">
	<cfif structKeyExists(lnk,"win64")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=win64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['win64'])#">Windows</a>
	</cfif>
	<cfif structKeyExists(lnk,"linux-x64")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-x64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-x64'])#">Linux x64</a>
	</cfif>
	<cfif structKeyExists(lnk,"linux-aarch64")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=linux-aarch64" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['linux-aarch64'])#">Linux arm64</a>
	</cfif>
	<cfif structKeyExists(lnk,"express")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=express" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['express'])#">Express</a>
	</cfif>
	<cfif structKeyExists(lnk,"jar")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=jar" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['jar'])#">lucee.jar</a>
	</cfif>
	<cfif structKeyExists(lnk,"light")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=light" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['light'])#">lucee-light.jar</a>
	</cfif>
	<cfif structKeyExists(lnk,"zero")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=zero" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['zero'])#">lucee-zero.jar</a>
	</cfif>
	<cfif structKeyExists(lnk,"lco")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=lco" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['lco'])#">Core (.lco)</a>
	</cfif>
	<cfif structKeyExists(lnk,"war")>
	<a href="/download.cfm?version=#encodeForURL(ver)#&type=war" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['war'])#">WAR</a>
	</cfif>
	<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#encodeForURL(listFirst(ver,'-'))#" target="_blank" class="has-tooltip" data-tooltip="#encodeForHTMLAttribute(DL_INFO['docker'])#">Docker</a>
</div>
</cfoutput>
