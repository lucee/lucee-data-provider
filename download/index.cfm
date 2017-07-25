<cfscript>
if(cgi.http_host!="download.lucee.org") location url="http://download.lucee.org" addtoken=false;
  MAX=1000;
	include "functions.cfm";
  isBeta=!isNull(url.beta) && url.beta;
	query=getExtensions(isBeta);

	_5_0_0_70=toVersionSortable("5.0.0.70-SNAPSHOT");
	_5_0_0_112=toVersionSortable("5.0.0.112-SNAPSHOT");
	_5_0_0_219=toVersionSortable("5.0.0.219-SNAPSHOT");
	_5_0_0_255=toVersionSortable("5.0.0.255-SNAPSHOT");
	_5_0_0_256=toVersionSortable("5.0.0.256-SNAPSHOT");
	_5_0_0_257=toVersionSortable("5.0.0.257-SNAPSHOT");
	_5_0_0_258=toVersionSortable("5.0.0.258-SNAPSHOT");
	_5_0_0_259=toVersionSortable("5.0.0.259-SNAPSHOT");
	_5_0_0_260=toVersionSortable("5.0.0.260-SNAPSHOT");
	_5_0_0_261=toVersionSortable("5.0.0.261-SNAPSHOT");
	_5_0_0_262=toVersionSortable("5.0.0.262-SNAPSHOT");
	_5_1_0_31=toVersionSortable("5.1.0.31");
  _5_1_0_008=toVersionSortable("5.1.0.008-SNAPSHOT");
  _5_2_1_7=toVersionSortable("5.2.1.7");
  _5_2_1_8=toVersionSortable("5.2.1.8");



	if(isNull(url.type))url.type="releases";
	else type=url.type;

	intro="The latest {type} is version <b>{version}</b> released at <b>{date}</b>.";
	historyDesc="Get older Versions.";
  singular={releases:"Release",snapshots:"Snapshot",abc:'Alpha / Beta / RC'};
  multi={releases:"Releases",snapshots:"Snapshots",abc:'Alphas / Betas / RCs'};

  noVersion="There are currently no downloads available in this category.";


</cfscript>

<cfhtmlhead>

  <link rel="stylesheet" href="/res/download.css">

</cfhtmlhead>


<cfhtmlbody>

  <script src="/res/jquery-3.2.1.min.js"></script>

  <script>

    $(function(){

      $(".clog-toggle, .clog-toggle-first").click(function(){

        var $parent = $(this).parent(".clog-wrapper");

        $parent.find(".clog-detail")
          .slideToggle( function(){
            $parent.find(".icon-collapse")
              .toggleClass("collapsed");
          } );
      });

      $(".clog-toggle-all").click(function(){

        $(".clog-toggle").trigger("click");
        $(this).find(".icon-collapse")
            .toggleClass("collapsed");
      });

      $(".clog-toggle").click();
    }); // jquery ready
  </script>

</cfhtmlbody>



<html>
  <head>
    <title></title>

    <cfhtmlhead action="flush">
  </head>
  <body>

<!--- output --->
<cfoutput>



<h1>Downloads</h1>

<p>
<a class="linkk" href="?type=releases">Releases</a>
| <a class="linkk" href="?type=snapshots">Snapshots</a>
| <a class="linkk" href="?type=abc">Alphas/Betas/Release Candidates</a>
</p>


<p>
<a class="linkk" href="?type=extensions">Extensions</a>
| <a class="linkk" href="?type=extensions&beta=true">Extensions (Alpha/Beta)</a>
</p>



<cfif type=="releases" || type=="snapshots" || type=="abc">
<cfscript>
  function toKeySortable(key) {
      var arr=listToArray(key,'-');
      while(len(arr[2])<5) {
          arr[2]="0"&arr[2];
      }
      return arr[1]&"-"&arr[2];
  }
	tmpDownloads=getDownloads();
  if(!queryColumnExists(tmpDownloads,"state"))queryAddColumn(tmpDownloads,"state");
  loop query=tmpDownloads {
    if(findNoCase("alpha",tmpDownloads.version)) tmpDownloads.state[tmpDownloads.currentrow]="alpha";
    else if(findNoCase("beta",tmpDownloads.version)) tmpDownloads.state[tmpDownloads.currentrow]="beta";
    else if(findNoCase("rc",tmpDownloads.version)) tmpDownloads.state[tmpDownloads.currentrow]="rc";
    else if(findNoCase("ReleaseCandidate",tmpDownloads.version)) tmpDownloads.state[tmpDownloads.currentrow]="rc";
  }

  // filter out not matching major version
	downloads=queryNew("test,"&tmpDownloads.columnlist);
  arrColumns=tmpDownloads.columnArray();
	loop query=tmpDownloads {
		if(
      ( url.type==tmpDownloads.type && tmpDownloads.state=="" )
      ||
      ( url.type=="abc" && tmpDownloads.state!="" ) // has -ALPAH for example
      ) {
			row=downloads.addRow();
			loop array=arrColumns item="col" {
        if(col=="changelog") {
          _changelog=tmpDownloads[col];
          if(!isStruct(_changelog))_changelog={};
          else _changelog=duplicate(_changelog);
          downloads.setCell(col,_changelog,row);
        }
				else downloads.setCell(col,tmpDownloads[col],row);
			}
      downloads.setCell('test',listLen(tmpDownloads.version,'-'),row);

      if(downloads.recordcount>=MAX) break;
		}
    else if(!isNull(_changelog) && isStruct(tmpDownloads.changelog)) {
      loop struct=tmpDownloads.changelog index="key" item="ver" {
        _changelog[key]=ver;
      }
    }
	}
  if(downloads.recordcount) latest=1;

  // sort changelog
  loop query=downloads {
    cl=downloads.changelog;
    if(isStruct(cl) && structCount(cl)>1) {
      q=queryNew('k,ks,v');
      loop struct=cl index="key" item="val" {
        r=queryAddRow(q);
        querySetCell(q,"k",key,r);
        querySetCell(q,"ks",toKeySortable(key),r);
        querySetCell(q,"v",val,r);
      }
      querySort(q,"ks","desc");
      sct=structNew("linked");
      loop query=q {
        sct[q.k]=q.v;
      }
      downloads.changelog=sct;
    }


  }
//dump(downloads);



</cfscript>
<cfif isNull(latest)>
  <p>#noVersion#</p>
<cfelse>
		<h2>Latest 	#singular[type]# (#downloads.version[latest]#)</h2>
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
                  <div class="clog-wrapper">
			<h3 class="clog-toggle-first">Changelog <i class="icon icon-collapse"></i></h3>
			<div class="clog-detail"><cfloop struct="#downloads.changelog[latest]#" index="id" item="subject">
				<a href="http://bugs.lucee.org/browse/#id#">#id#</a> #subject#<br>
			     </cfloop>
                        </div>
                  </div><!-- .clog-wrapper !-->
		</cfif>

		<cfif downloads.recordcount GT 1>

		<cfsilent>
		<cfloop query=downloads>
			<cfif true> <!--- downloads.version!=downloads.version[latest] --->
				<cfif isNull(last)>
					<cfset last=downloads.version>
				</cfif>
				<cfset first=downloads.version>
			</cfif>
		</cfloop>
		</cfsilent>
		<cfif !isNUll(first)>
		<h2>
			#singular[type]# History (#last# - #first#)
			<span class="clog-toggle-all">Changelogs <i class="icon icon-collapse collapsed"></i></span>
		</h2>
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
				downloads.v == _5_0_0_262 ||
				downloads.v == _5_1_0_31  ||
        downloads.v == _5_1_0_008 ||
        downloads.v == _5_2_1_7 ||
        downloads.v == _5_2_1_8

			>
				<cfcontinue>
			</cfif>
			<cfset css="">
			<cfif true><!--- downloads.version!=downloads.version[latest] --->
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
                                  <div class="clog-wrapper">
					<h3 class="clog-toggle">Changelog <i class="icon icon-collapse"></i></h3>
					<div class="clog-detail"><cfloop struct="#downloads.changelog#" index="id" item="subject">
					<a href="http://bugs.lucee.org/browse/#id#">#id#</a> #subject#<br>
					</cfloop></div>
                                   </div><!-- .clog-wrapper !-->
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
</cfif>


</cfoutput>




<cfif type=="extensions">

<!--- output --->
<cfoutput>
<h2>#UCFirst(type)#</h2>
<p>Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.</p>

<cfif isBeta>
<p>To install this Extensions from within your Lucee Administrator, you need to add "http://beta.lucee.org" under "Extension/Provider" as a new Provider, after that you can install this Extensions under "Extension/Application" in the Administartor.</p>
<cfelse>
<p>You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>
</cfif>


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

    <cfhtmlbody action="flush">
  </body>
</html>
