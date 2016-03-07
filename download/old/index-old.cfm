<cfscript>
	include "functions.cfm";
	downloads=getDownloads();
	query=getExtensions();


	_5_0_0_70=toVersionSortable("5.0.0.70-SNAPSHOT");
	_5_0_0_112=toVersionSortable("5.0.0.112-SNAPSHOT");
</cfscript>

<!--- output --->
<cfoutput>

<style>
td {
	font-family: Arial;
	font-size:13px;
}
.comment {
	font-size:11px;
}
.grey {
	background-color:##ccc;
}
</style>


<cfloop list="releases,snapshots" item="type">
		<h2>#UCFirst(type)#</h2>
		<p>#lang.desc[type]#</p>
		<cfif cookie["showAll_"&type]>
			<a href="?showAll=false&type=#type#">Show latest</a>
		<cfelse>
			<a href="?showAll=true&type=#type#">Show all</a>
		</cfif>
		<table border="1" width="100%">
		<tr>
			<td width="200" align="center"><h2>Version</h2></td>
			<td width="200" align="center"><h2>Birth Date</h2></td>
			<td colspan="2" width="80%" align="center"><h2>Downloads</h2></td>
			
			<!---<td><h2>Express</h2><p>#lang.express#</p></td>
			<td><h2>WAR</h2><p>#lang.war#</p></td>
			<td><h2>Core</h2><p>#lang.core#</p></td>
			<td><h2>Jar</h2><p>#lang.jar#</p></td>
			<td><h2>Jar-All</h2><p>#lang.LuceeAll#</p></td>
			<td><h2>Dependencies</h2><p>#lang.dependencies#</p></td>--->
		</tr>	
		<cfloop query=downloads>
			<cfset css=((downloads.currentrow%2)==0)?"grey":"">
			<cfif downloads.type==variables.type>
			<tr>
				<td class="#css#" align="center" rowspan="3">#downloads.version#</td>
				<td class="#css#" align="center" rowspan="3">#lsDateFormat(downloads.jarDate)#</td>
				
				<td class="#css#" width="40%"><a href="#_url[type]#/rest/update/provider/download/#downloads.version#">Lucee core file (#downloads.version#.lco)</a>
				<br><span class="comment">#lang.core#</span></td>
				<td class="#css#" width="40%"><cfif downloads.v GTE _5_0_0_112><a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version#">Lucee library (lucee-all.jar) with dependencies</a>
				<br><span class="comment">#lang.LuceeAll#</span><cfelse>no Lucee library (lucee-all.jar) with dependencies</cfif></td>

			</tr>
			<tr>
				<td class="#css#"><a href="#_url[type]#/rest/update/provider/#downloads.v GTE _5_0_0_112?"loader":"libs"#/#downloads.version#">Lucee library (lucee.jar) without dependencies</a>
				<br><span class="comment">#lang.jar#</span></td>
				<td class="#css#"><a href="#_url[type]#/rest/update/provider/dependencies/#downloads.version#">Bundles/Dependencies</a>
				<br><span class="comment">#lang.dependencies#</span></td>
			</tr>
			<tr>
				<td class="#css#"><a href="#_url[type]#/rest/update/provider/express/#downloads.version#">Lucee Express Build</a>
				<br><span class="comment">#lang.express#</span></td>
				<td class="#css#"><cfif downloads.v GTE _5_0_0_70><a href="#_url[type]#/rest/update/provider/war/#downloads.version#">Lucee WAR file (lucee.war)</a>
				<br><span class="comment">#lang.war#</span><cfelse>no WAR file</cfif></td>
			</tr>
				<cfif !cookie["showAll_"&type]>
					<cfbreak>
				</cfif>
			</cfif>

		</cfloop>
		</table>
</cfloop>




<!--- 
<cfloop list="releases,snapshots" item="type">
		<h2>#UCFirst(type)#</h2>
		<p>#lang.desc[type]#</p>
		<cfif cookie["showAll_"&type]>
			<a href="?showAll=false&type=#type#">Show latest</a>
		<cfelse>
			<a href="?showAll=true&type=#type#">Show all</a>
		</cfif>
		<table border="1">
		<tr>
			<td><h2>Birth Date</h2></td>
			<td><h2>Express</h2><p>#lang.express#</p></td>
			<td><h2>WAR</h2><p>#lang.war#</p></td>
			<td><h2>Core</h2><p>#lang.core#</p></td>
			<td><h2>Jar</h2><p>#lang.jar#</p></td>
			<td><h2>Jar-All</h2><p>#lang.LuceeAll#</p></td>
			<td><h2>Dependencies</h2><p>#lang.dependencies#</p></td>
		</tr>	
		<cfloop query=downloads>
			<cfif downloads.type==variables.type>
			<tr>
			<td>#lsDateFormat(downloads.jarDate)#</td>
			<td><a href="#_url[type]#/rest/update/provider/express/#downloads.version#">Express #downloads.version#</a></td>
			<td><cfif downloads.v GTE _5_0_0_70><a href="#_url[type]#/rest/update/provider/war/#downloads.version#">WAR #downloads.version#</a><cfelse> - </cfif></td>
			<td><a href="#_url[type]#/rest/update/provider/download/#downloads.version#">Core #downloads.version#</a></td>
			<td><a href="#_url[type]#/rest/update/provider/#downloads.v GTE _5_0_0_112?"loader":"libs"#/#downloads.version#">JAR #downloads.version#</a></td>
			<td><cfif downloads.v GTE _5_0_0_112><a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version#">JAR-all #downloads.version#</a><cfelse> - </cfif></td>
			<td><a href="#_url[type]#/rest/update/provider/dependencies/#downloads.version#">dep #downloads.version#</a></td>
			</tr>
				<cfif !cookie["showAll_"&type]>
					<cfbreak>
				</cfif>
			</cfif>

		</cfloop>
		</table>
</cfloop>--->
</cfoutput>	


<!--- output --->
<cfoutput>
<h2>Extensions</h2>
<p>Lucee Extensions, simply copy them to /lucee-server/context/deploy, of a running Lucee installation, to install them.</p>
<table border="1">
<cfloop query="#query#">
<tr>
	<td><img src="data:image/png;base64,#query.image#"></td>
	<td>
		<h2>#query.name#</h2>
		<p>
			ID:#query.id#<br>
			Version:#query.version#<br>
			Category:#query.category#<br>
			Birth Date:#query.created#<br>
			Trial:#yesNoFormat(query.trial)#
		</p>
		<p>#query.description#</p>
		<p><a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',query.trial?"trial":"full"),'{id}',query.id)#">download (#query.trial?"trial":"full"# version)</a></p>

	</td>

</tr>
</cfloop>
</table>
</cfoutput>	
