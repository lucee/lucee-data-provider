<cfscript>
	include "functions.cfm";
	query=getExtensions();

if(!isNull(form.submit)){
	config.addBundles=!isNull(form.bundles) && form.bundles;
	config.extension=isNull(form.extension)?[]:form.extension;
	dump(config);
}

</cfscript>

<cfparam name="url.version">

<!--- output --->
<cfoutput>
<h2>Custom build for version #url.version#</h2>
<p>Create a build of the lucee.jar that exactly contains what you want.</p>
<table border="1">
<form method="post" action="custom.cfm?version=#url.version#">
<tr>
	<td>
		<h2>Bundles (3th party jars)</h2>
		<p>
		<input type="checkbox" name="bundles" value="true" checked>
		Bundle dependencies (3th party jars) with the lucee.jar. This makes the Lucee jar a lot bigger but you now longer have to take care that the 3th party bundles (jars) are at /lucee-server/bundles and Lucee no longer has to download them.</p>
	</td>
</tr>

<tr>
	<td>
		<h2>Extensions</h2>
		Bundle Lucee Extensions with your Lucee.jar.
<cfloop query="#query#">
		<p><input type="checkbox" name="extension[]" value="#query.id#"> <b>#query.name#</b><br>
		#query.description#</p>
</cfloop>
	</td>
</tr>

<tr>
	<td>
		<input type="submit" name="submit" value="create lucee.jar">
	</td>
</tr>
</form>
</table>
</cfoutput>	

