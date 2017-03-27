<cfscript>
	if(isNull(url.major)) url.major='5.0';
	include "functions.cfm";
	
	query=getExtensions(!isNull(url.beta) && url.beta);

	_5_0_0_70=toVersionSortable("5.0.0.70-SNAPSHOT");
	_5_0_0_112=toVersionSortable("5.0.0.112-SNAPSHOT");
	_5_0_0_219=toVersionSortable("5.0.0.219-SNAPSHOT");
	_5_0_0_254=toVersionSortable("5.0.0.254-SNAPSHOT");
	_5_0_0_255=toVersionSortable("5.0.0.255-SNAPSHOT");
	_5_0_0_256=toVersionSortable("5.0.0.256-SNAPSHOT");
	_5_0_0_257=toVersionSortable("5.0.0.257-SNAPSHOT");
	_5_0_0_258=toVersionSortable("5.0.0.258-SNAPSHOT");
	_5_0_0_259=toVersionSortable("5.0.0.259-SNAPSHOT");
	_5_0_0_260=toVersionSortable("5.0.0.260-SNAPSHOT");
	_5_0_0_261=toVersionSortable("5.0.0.261-SNAPSHOT");
	_5_0_0_262=toVersionSortable("5.0.0.262-SNAPSHOT");

	if(isNull(url.type))type="releases";
	else type=url.type;

	intro="The latest {type} is version <b>{version}</b> released at <b>{date}</b>.";
	historyDesc="Get older Versions.";
	singular={releases:"release",snapshots:"snapshot"};
</cfscript>

<!--- output --->
<cfoutput>

<style type="text/css">
  *,
  *::after,
  *::before {
    -webkit-box-sizing: inherit;
            box-sizing: inherit;
  }

  @-ms-viewport {
    width: device-width;
  }

  body {
    background-color: white;
    color: ##212121;
    font-family: Roboto, -apple-system, BlinkMacSystemFont, "Segoe UI", "Helvetica Neue", Arial, sans-serif;
    font-size: 0.875rem;
    font-weight: 400;
    line-height: 1.428572;
    margin: 0;
  }

  html {
    -webkit-box-sizing: border-box;
            box-sizing: border-box;
    font-family: sans-serif;
    line-height: 1.15;
    -ms-overflow-style: scrollbar;
    -webkit-tap-highlight-color: transparent;
    -webkit-text-size-adjust: 100%;
            text-size-adjust: 100%;
  }

  [tabindex="-1"]:focus {
    outline: 0 !important;
  }

  a {
    background-color: transparent;
    color: ##01798a;
    text-decoration: none;
    -webkit-text-decoration-skip: objects;
    -ms-touch-action: manipulation;
        touch-action: manipulation;
  }
  a:active, a:focus, a:hover {
    color: ##3f51b5;
    text-decoration: none;
  }

  b,
  strong {
    font-weight: bolder;
  }

  h1,
  h2,
  h3,
  h4,
  h5,
  h6 {
    color: inherit;
    font-family: inherit;
    margin-top: 0;
    margin-bottom: .5rem;
  }

  h1 {
    font-size: 2.8125rem;
    font-weight: 400;
    letter-spacing: 0;
    line-height: 3rem;
  }
  @media (min-width: 768px) {
    h1 {
      font-size: 7rem;
      font-weight: 300;
      letter-spacing: -.04em;
      line-height: 7rem;
    }
  }

  h2 {
    font-size: 2.125rem;
    font-weight: 400;
    letter-spacing: 0;
    line-height: 2.5rem;
  }

  h3 {
    font-size: 1.5rem;
    font-weight: 400;
    letter-spacing: 0;
    line-height: 2rem;
  }

  h4 {
    font-size: 1.25rem;
    font-weight: 700;
    letter-spacing: 0.02em;
    line-height: 1.75rem;
  }

  h5 {
    font-size: 1rem;
    font-weight: 400;
    letter-spacing: 0.04em;
    line-height: 1.5rem;
  }

  h6 {
    font-size: 0.875rem;
    font-weight: 700;
    letter-spacing: 0;
    line-height: 1.25rem;
  }

  img {
    border-style: none;
    height: auto;
    max-width: 100px;
    vertical-align: middle;
  }

  p {
    margin-top: 0;
    margin-bottom: 1rem;
  }

  small {
    font-size: 80%;
    font-weight: 400;
  }

  table {
    background-color: ##ffffff;
    border: 0;
    border-collapse: collapse;
    -webkit-box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
            box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
    margin-bottom: 1rem;
    max-width: 100%;
    width: 100%;
  }

  table td,
  table th {
    padding-right: 1rem;
    padding-left: 1rem;
    text-align: left;
    text-align: start;
    vertical-align: top;
  }

  table td > :last-child,
  table th > :last-child {
    margin-bottom: 0;
  }

  table tbody td,
  table tbody th {
    border-top: 1px solid ##e1e1e1;
    color: ##212121;
    font-size: 0.8125rem;
    font-weight: 400;
    height: 3rem;
    padding-top: 0.919643rem;
    padding-bottom: 0.919643rem;
  }

  table tbody tr:hover {
    background-color: ##eeeeee;
  }

  table tbody tr td.grey {
    background-color: ##f5f5f5;
  }

  table tbody tr td.grey strong {
    display: inline-block;
    margin-bottom: .5rem;
  }

  table thead td,
  table thead th {
    color: ##9e9e9e;
    font-size: 0.75rem;
    font-weight: 700;
    height: 3.5rem;
    padding-top: 1.214286rem;
    padding-bottom: 1.214286rem;
  }

  table thead {
    background-color: ##ffffff;
    position: sticky;
    top: 0;
  }

  table[title="Extensions"] br + strong {
    display: inline-block;
    margin-top: .25rem;
  }

  table[title="Extensions"] strong + ul {
    margin-top: .25rem;
  }

  ul {
    margin-top: 0;
    margin-bottom: 1rem;
    padding-left: 1rem;
  }

  .btn {
    border-radius: 2px;
    -webkit-transition-duration: 0.3s;
         -o-transition-duration: 0.3s;
            transition-duration: 0.3s;
    -webkit-transition-property: background-color, color, -webkit-box-shadow;
            transition-property: background-color, color, -webkit-box-shadow;
         -o-transition-property: background-color, box-shadow, color;
            transition-property: background-color, box-shadow, color;
            transition-property: background-color, box-shadow, color, -webkit-box-shadow;
    -webkit-transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
         -o-transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
            transition-timing-function: cubic-bezier(0.4, 0, 0.2, 1);
    background-color: ##f5f5f5;
    background-image: none;
    border: 0;
    -webkit-box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
            box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
    color: ##212121;
    display: inline-block;
    font-size: 0.875rem;
    font-weight: 700;
    line-height: 1;
    margin: 0 0 .5rem;
    max-width: 100%;
    min-width: 5.5rem;
    padding: 0.6875rem 1rem;
    position: relative;
    text-align: center;
    text-transform: uppercase;
    -webkit-user-select: none;
       -moz-user-select: none;
        -ms-user-select: none;
            user-select: none;
    vertical-align: middle;
    white-space: nowrap;
  }
  .btn:active, .btn:focus, .btn:hover {
    background-color: ##eeeeee;
    color: ##212121;
    text-decoration: none;
  }
  .btn:active {
    -webkit-box-shadow: 0 8px 10px 1px rgba(0, 0, 0, 0.14), 0 3px 14px 2px rgba(0, 0, 0, 0.12), 0 5px 5px -3px rgba(0, 0, 0, 0.4);
            box-shadow: 0 8px 10px 1px rgba(0, 0, 0, 0.14), 0 3px 14px 2px rgba(0, 0, 0, 0.12), 0 5px 5px -3px rgba(0, 0, 0, 0.4);
  }

  .container {
    margin-right: auto;
    margin-left: auto;
    max-width: 100%;
    padding-right: 16px;
    padding-left: 16px;
    width: 960px;
  }

  .card {
    border-radius: 2px;
    background-color: ##ffffff;
    -webkit-box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
            box-shadow: 0 2px 2px 0 rgba(0, 0, 0, 0.14), 0 1px 5px 0 rgba(0, 0, 0, 0.12), 0 3px 1px -2px rgba(0, 0, 0, 0.4);
    margin-bottom: 3rem;
    position: relative;
  }

  .card-block {
    padding: 1rem;
  }

  .card-block > :last-child {
    margin-bottom: 0;
  }

  .page-body {
    margin-bottom: 3rem;
  }

  .page-header {
    background-color: ##01798a;
    color: ##ffffff;
    margin-bottom: 3rem;
    padding-top: 3rem;
    padding-bottom: 2.5rem;
  }
</style>

<h1>Downloads</h1>
<p>
<a class="linkk" href="?type=releases">Releases</a> 
| <a class="linkk" href="?type=snapshots">Snapshots</a>
</p>
<p>
<a class="linkk" href="?type=releases&major=5.1">Releases (Beta)</a> 
| <a class="linkk" href="?type=snapshots&major=5.1">Snapshots (Beta)</a> 
</p>
<p>
<a class="linkk" href="?type=extensions">Extensions</a>
| <a class="linkk" href="?type=extensions&beta=true">Extensions (Beta)</a>
</p>



<cfif type=="releases" || type=="snapshots">
<cfscript>
	tmpDownloads=getDownloads();

	// filter out not matching major version
	downloads=queryNew(tmpDownloads.columnlist);
	loop query=tmpDownloads {
		if(left(tmpDownloads.version,len(url.major))==url.major) {
			row=downloads.addRow();
			loop array=tmpDownloads.columnArray() item="col" {
				downloads.setCell(col,tmpDownloads[col],row);
			}
		}
	}

	loop query=downloads {
		if(downloads.type==variables.type) {
			latest=downloads.currentrow;
			break;
		}
	}
</cfscript>
	



		<h2>Latest 	#UCFirst(type)# (#downloads.version[latest]#)</h2>
		<p>#replace(replace(replace(intro,"{date}",lsDateFormat(downloads.jarDate[latest])),"{version}",downloads.version[latest]),"{type}",singular[type])# #lang.desc[type]#</p>

		<!--- jar --->
		<h3>Lucee library (.jar file)</h3>
		<p><cfif downloads.v[latest] GTE _5_0_0_219>#lang.libNew#<cfelse>#lang.lib#</cfif><br>
		<a href="#_url[type]#/rest/update/provider/#downloads.v[latest] GTE _5_0_0_112?"loader":"libs"#/#downloads.version[latest]#">lucee.jar<cfif downloads.v[latest] LT _5_0_0_219> (no dependecies)</cfif></a>
		<cfif downloads.v[latest] GTE _5_0_0_112 and downloads.v[latest] LT _5_0_0_219>
			<br><a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version[latest]#">lucee-all.jar (with dependecies)</a>
		</cfif>
		</p>


		<!---  Express--->
		<h3>Express</h3>
		<p>#lang.express#<br>
		<a href="#_url[type]#/rest/update/provider/express/#downloads.version[latest]#">download</a></p>
		
		<!--- War --->
		<h3>Lucee WAR file (lucee.war)</h3>
		<p>#lang.war#<br>
		<a href="#_url[type]#/rest/update/provider/war/#downloads.version[latest]#">download</a></p>
		
		<!--- Lucee Core --->
		<h3>Lucee core file (#downloads.version[latest]#.lco)</h3>
		<p>#lang.core#<br>
		<a href="#_url[type]#/rest/update/provider/download/#downloads.version[latest]#">download</a></p>
		

		<!--- changelog --->
		<cfif !isnull(downloads.changelog[latest]) && isStruct(downloads.changelog[latest]) && structCount(downloads.changelog[latest])>
			<h3>Changelog</h3>
			<p><cfloop struct="#downloads.changelog[latest]#" index="id" item="subject">
				<a href="http://bugs.lucee.org/browse/#id#">#id#</a> #subject#<br>
			</cfloop></p>
		</cfif>

		<cfif downloads.recordcount GT 1>
		
		<cfsilent>
		<cfloop query=downloads>
			<cfif downloads.type==variables.type && downloads.version!=downloads.version[latest]>
				<cfif isNull(last)>
					<cfset last=downloads.version>
				</cfif>
				<cfset first=downloads.version>
			</cfif>
		</cfloop>
		</cfsilent>
		<cfif !isNUll(first)>
		<h2>#UCFirst(type)# History (#first# - #last#)</h2>
		<p>#historyDesc#</p>




		<table border="1" width="100%">
		<tr>
			<td align="center"><h3>Version</h3></td>
			<td align="center"><h3>Date</h3></td>
			
			<td align="center"><h3>Express</h3></td>
			<td align="center"><h3>Lucee library</h3><span class="comment"> with dependencies</span></td>
			<td align="center"><h3>Lucee library</h3><span class="comment"> without dependencies</span></td>
			<td align="center"><h3>Lucee core file</h3></td>
			<td align="center"><h3>Lucee WAR file</h3></td>
		</tr>	
		<cfloop query=downloads>

			<cfif 
				downloads.v == _5_0_0_255 ||
				downloads.v == _5_0_0_256 ||
				downloads.v == _5_0_0_257 ||
				downloads.v == _5_0_0_258 ||
				downloads.v == _5_0_0_259 ||
				downloads.v == _5_0_0_260 ||
				downloads.v == _5_0_0_261 ||
				downloads.v == _5_0_0_262

			>
				<cfcontinue>
			</cfif>
			<cfset css="">
			<cfif downloads.type==variables.type && downloads.version!=downloads.version[latest]>
			<tr>
				<td class="#css#" align="center">#downloads.version#</td>
				<td class="#css#" align="center">#lsDateFormat(downloads.jarDate)#</td>
				
				<td class="#css#"><a href="#_url[type]#/rest/update/provider/express/#downloads.version#">Express</a></td>

				<td class="#css#" >
					<cfif downloads.v GTE _5_0_0_219>
						<a href="#_url[type]#/rest/update/provider/loader/#downloads.version#">lucee.jar</a>
					<cfelseif downloads.v GTE _5_0_0_112>
						<a href="#_url[type]#/rest/update/provider/loader-all/#downloads.version#">lucee-all.jar</a></span>
					<cfelse>
						-
					</cfif></td>

				<td class="#css#">
					<cfif downloads.v LT _5_0_0_219>
					<a href="#_url[type]#/rest/update/provider/#downloads.v GTE _5_0_0_112?"loader":"libs"#/#downloads.version#">lucee.jar</a>
					</cfif>
				</td>

				<td class="#css#"><a href="#_url[type]#/rest/update/provider/download/#downloads.version#">Core</a></td>

				<td class="#css#"><a href="#_url[type]#/rest/update/provider/war/#downloads.version#">WAR</a></td>
				

			</tr>
			<!--- changelog --->
			<cfif !isNull(downloads.changelog) && isStruct(downloads.changelog) && structCount(downloads.changelog)>
			<tr>
				<td colspan="7" class="grey">
					<h3>Changelog</h3>
					<p><cfloop struct="#downloads.changelog#" index="id" item="subject">
					<a href="http://bugs.lucee.org/browse/#id#">#id#</a> #subject#<br>
					</cfloop></p>
				</td>
			</tr>

			</cfif>
			</cfif>

		</cfloop>
</cfif>

</cfif>



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
<h2>#UCFirst(type)#</h2>
<p>Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.</p>
<table border="1">
<cfloop query="#query#">
<tr>
	<td><img src="data:image/png;base64,#query.image#"></td>
	<td>
		<h2>#query.name#</h2>
		<p>
			ID:#query.id#<br>
			Latest Version:#query.version#<br>
			Category:#query.category#<br>
			Birth Date:#query.created#<br>
			Trial:#yesNoFormat(query.trial)#
		</p>
		<p>#query.description#</p>
		<p><a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',query.trial?"trial":"full"),'{id}',query.id)#?version=#query.version#">
		download#query.trial?" trial":""# version (#query.version#)  </a></p>
		<cfif !isNull(query.older) && isArray(query.older) && arrayLen(query.older)>
		<p>Older Versions:
		<ul>
		<cfloop array="#query.older#" item="_older">
			<li><a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',query.trial?"trial":"full"),'{id}',query.id)#?version=#_older#">
		download#query.trial?" trial":""# version (#_older#)  </a></li>
		</cfloop>
	</ul>
		</p>
		</cfif>
	</td>

</tr>
</cfloop>
</table>
</cfoutput>	

</cfif>


