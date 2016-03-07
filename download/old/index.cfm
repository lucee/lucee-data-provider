<cfscript>
	include "functions.cfm";
	
	query=getExtensions();


	_5_0_0_70=toVersionSortable("5.0.0.70-SNAPSHOT");
	_5_0_0_112=toVersionSortable("5.0.0.112-SNAPSHOT");

	if(isNull(url.type))type="releases";
	else type=url.type;

	intro="The latest {type} is version <b>{version}</b> released at <b>{date}</b>.";
	historyDesc="Get older Versions.";
	singular={releases:"release",snapshots:"snapshot"};
</cfscript>

<!--- output --->
<cfoutput>

<style>
td,p {
	font-family: Arial;
	font-size:12px;
}

h1 {
	font-family: Arial;
	font-size:22px;
}
h2 {
	font-family: Arial;
	font-size:18px;
}
h3 {
	font-family: Arial;
	font-size:15px;
}



.comment {
	font-size:12px;
}
.grey {
	background-color:##ccc;
}
</style>

<h1>Downloads</h1>
<p>
<a href="?type=releases">Releases</a> | <a href="?type=snapshots">Snapshots</a> | <a href="?type=extensions">Extensions</a>
</p>



<cfif type=="releases" || type=="snapshots">
<cfscript>
	downloads=getDownloads();
	loop query=downloads {
		if(downloads.type==variables.type) {
			latest=downloads.currentrow;
			break;
		}
	}
</cfscript>
	



		<h2>Latest 	#UCFirst(type)#</h2>
		<p>#replace(replace(replace(intro,"{date}",lsDateFormat(downloads.jarDate[latest])),"{version}",downloads.version[latest]),"{type}",singular[type])# #lang.desc[type]#</p>


		<table border="1" width="100%">
		<tr>
			<td width="50%"><h3>Express</h3>
		<p>#lang.express#<br>
		<a href="#_url[type]#/rest/update/provider/express/#downloads.version[latest]#">download</a></p></td>
			<td width="50%"><cfif downloads.v[latest] GTE _5_0_0_112>
		<h3>Lucee library (lucee-all.jar) with dependencies</h3>
		<p>#lang.LuceeAll#<br>
		<a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version[latest]#">download</a></p>
		</cfif></td>
		</tr>
		<tr>
			<td width="50%"><h3>Lucee library (lucee.jar) without dependencies</h3>
		<p>#lang.jar#<br>
		<a href="#_url[type]#/rest/update/provider/#downloads.v[latest] GTE _5_0_0_112?"loader":"libs"#/#downloads.version[latest]#">download</a></p></td>
			<td width="50%"><h3>Lucee core file (#downloads.version[latest]#.lco)</h3>
		<p>#lang.core#<br>
		<a href="#_url[type]#/rest/update/provider/download/#downloads.version[latest]#">download</a></p></td>
		</tr>
		<tr>
			<td width="50%"><h3>Lucee WAR file (lucee.war)</h3>
		<p>#lang.war#<br>
		<a href="#_url[type]#/rest/update/provider/war/#downloads.version[latest]#">download</a></p></td>
			<td width="50%"></td>
		</tr>
		
		</table>


		
		<h2>History </h2>
		<p>#historyDesc#</p>




		<table border="1" width="100%">
		<tr>
			<td align="center"><h2>Version</h2></td>
			<td align="center"><h2>Birth Date</h2></td>
			
			<td align="center"><h2>Express</h2></td>
			<td align="center"><h2>Lucee library</h2><span class="comment"> with dependencies</span></td>
			<td align="center"><h2>Lucee library</h2><span class="comment"> without dependencies</span></td>
			<td align="center"><h2>Lucee core file</h2></td>
			<td align="center"><h2>Lucee WAR file</h2></td>
		</tr>	
		<cfloop query=downloads>
			<cfset css=((downloads.currentrow%2)==0)?"grey":"">
			<cfif downloads.type==variables.type && downloads.version!=downloads.version[latest]>
			<tr>
				<td class="#css#" align="center">#downloads.version#</td>
				<td class="#css#" align="center">#lsDateFormat(downloads.jarDate)#</td>
				
				<td class="#css#"><a href="#_url[type]#/rest/update/provider/express/#downloads.version#">Express</a></td>

				<td class="#css#" ><cfif downloads.v GTE _5_0_0_112><a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version#">lucee-all.jar</a></span><cfelse>-</cfif></td>

				<td class="#css#"><a href="#_url[type]#/rest/update/provider/#downloads.v GTE _5_0_0_112?"loader":"libs"#/#downloads.version#">lucee.jar</a></td>

				<td class="#css#"><a href="#_url[type]#/rest/update/provider/download/#downloads.version#">Core</a></td>

				<td class="#css#"><a href="#_url[type]#/rest/update/provider/war/#downloads.version#">WAR</a></td>
				

			</tr>
			</cfif>

		</cfloop>





<!--- <a href="#_url[type]#/rest/update/provider/dependencies/#downloads.version#">Bundles/Dependencies</a>
				<br><span class="comment">#lang.dependencies#</span> --->

		<!---<cfif cookie["showAll_"&type]>
			<a href="?showAll=false&type=#type#">Show latest</a>
		<cfelse>
			<a href="?showAll=true&type=#type#">Show all</a>
		</cfif>--->
		

</cfif>



</cfoutput>	




<cfif type=="extensions">

<!--- output --->
<cfoutput>
<h2>Extensions	#UCFirst(type)#</h2>
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

</cfif>
