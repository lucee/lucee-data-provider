<cfscript>
	links = [
		["Lucee.org", "https://www.lucee.org/"],
		["Developer Forum", "https://dev.lucee.org/"],
		["Download", "/"],
		["Changelogs", "/changelog"],
		["Docker", "https://hub.docker.com/r/lucee/lucee/"],
		["Documentation", "https://docs.lucee.org/"],
		["Github", "https://github.com/lucee"],
		["Bug Tracker", "https://luceeserver.atlassian.net/projects/LDEV/summary"],
		["Support Lucee Development <span class='glyphicon glyphicon-heart support-lucee ml-1'></span>", "https://opencollective.com/lucee"]
	];
</cfscript>
<cfoutput>
	<div class="link-bar">
		<cfloop array=#links# item="link">
			<a href="#link[2]#">#link[1]#</a>
		</cfloop>
	</div>
</cfoutput>