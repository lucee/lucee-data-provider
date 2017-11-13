<cfscript>
if(isNull(url.type)) url.type="releases";

if(cgi.http_host!="download.lucee.org") location url="http://download.lucee.org" addtoken=false;
  MAX=1000;
	include "functions.cfm";

if(url.type=='ext') extQry=getExtensions('release');
else if(url.type=='extabc') extQry=getExtensions('abc');
else if(url.type=='extsnap') extQry=getExtensions('snapshot');


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
  _5_2_3_30_RC=toVersionSortable("5.2.3.30-RC");



	if(isNull(url.type))url.type="releases";
	else type=url.type;

	intro="The latest {type} is version <b>{version}</b> released at <b>{date}</b>.";
	historyDesc="Older Versions:";
  singular={
  	releases:"Release",snapshots:"Snapshot",abc:'Beta / RC'
  	,ext:"Release",extsnap:"Snapshot",extabc:'Beta / RC'
  };
  multi={releases:"Releases",snapshots:"Snapshots",abc:'Betas / RCs'};

  noVersion="There are currently no downloads available in this category.";


		downloads45=query(
			version:[
				'4.5.5.006'
				,'4.5.4.017'
				,'4.5.3.020'
				,'4.5.2.018'
				,'4.5.1.024'
			]
			,date:[
				createDate(2017,1,26)
				,createDate(2016,10,24)
				,createDate(2016,9,1)
				,createDate(2015,11,9)
				,createDate(2015,10,20)
			]
			,installer:[
				{
					win:"http://cdn.lucee.org/lucee-4.5.5.006-pl0-windows-installer.exe"
					,lin64:"http://cdn.lucee.org/lucee-4.5.5.006-pl0-linux-x64-installer.run"
					,lin32:"http://cdn.lucee.org/lucee-4.5.5.006-pl0-linux-installer.run"
				}
				,{
					win:"http://cdn.lucee.org/lucee-4.5.4.017-pl0-windows-installer.exe"
					,lin64:"http://cdn.lucee.org/lucee-4.5.4.017-pl0-linux-x64-installer.run"
					,lin32:"http://cdn.lucee.org/lucee-4.5.4.017-pl0-linux-installer.run"
				}
				,{
					win:"http://cdn.lucee.org/lucee-4.5.3.020-pl0-windows-installer.exe"
					,lin64:"http://cdn.lucee.org/lucee-4.5.3.020-pl0-linux-x64-installer.run"
					,lin32:"http://cdn.lucee.org/lucee-4.5.3.020-pl0-linux-installer.run"
				}
				,{
					win:"http://cdn.lucee.org/lucee-4.5.2.018-pl0-windows-installer.exe"
					,lin64:"http://cdn.lucee.org/lucee-4.5.2.018-pl0-linux-x64-installer.run"
					,lin32:"http://cdn.lucee.org/lucee-4.5.2.018-pl0-linux-installer.run"
				}
				,{
					win:"http://cdn.lucee.org/lucee-4.5.1.024-pl0-windows-installer.exe"
					,lin64:"http://cdn.lucee.org/lucee-4.5.1.024-pl0-linux-x64-installer.run"
					,lin32:"http://cdn.lucee.org/lucee-4.5.1.024-pl0-linux-installer.run"
				}
			]
			,express:[
				'http://cdn.lucee.org/lucee-4.5.5.006-express.zip'
				,'http://cdn.lucee.org/lucee-4.5.4.017-express.zip'
				,'http://cdn.lucee.org/lucee-4.5.3.020-express.zip'
				,'http://cdn.lucee.org/lucee-4.5.2.018-express.zip'
				,'http://cdn.lucee.org/lucee-4.5.1.024-express.zip'
			]
			,jar:[
				'http://cdn.lucee.org/lucee-4.5.5.006-jars.zip'
				,'http://cdn.lucee.org/lucee-4.5.4.017-jars.zip'
				,'http://cdn.lucee.org/lucee-4.5.3.020-jars.zip'
				,'http://cdn.lucee.org/lucee-4.5.2.018-jars.zip'
				,'http://cdn.lucee.org/lucee-4.5.1.024-jars.zip'
			]
			,war:[
				'http://cdn.lucee.org/lucee-4.5.5.006.war'
				,'http://cdn.lucee.org/lucee-4.5.4.017.war'
				,'http://cdn.lucee.org/lucee-4.5.3.020.war'
				,'http://cdn.lucee.org/lucee-4.5.2.018.war'
				,'http://cdn.lucee.org/lucee-4.5.1.024.war'
			]
			//'https://bitbucket.org/lucee/lucee/downloads/4.5.5.006.lco'
			,core:[
				'http://cdn.lucee.org/4.5.5.006.lco'
				,'http://cdn.lucee.org/4.5.4.017.lco'
				,'http://cdn.lucee.org/4.5.3.020.lco'
				,'http://cdn.lucee.org/4.5.2.018.lco'
				,'http://cdn.lucee.org/4.5.1.024.lco'
			]
			,changelog:[
				{
					"LDEV-96":"ORM cache error when secondary cache is enabled and autoManageSession/flushAtRequestEnd are false"
					,"LDEV-391":"Default timezone for cfquery"
					,"LDEV-613":"ORM NullPointerException caused by <cfquery dbtype=""hql""> in latest stable release"
					,"LDEV-1076":"Exception TagContext template paths have changed from absolute to relative"
					,"LDEV-1083":"xmlParse with big invalid input can produce a out of memor error"
					,"LDEV-1122":"Class files no longer have full path for sourceFile"
					,"LDEV-1124":"datasource timezone ignored for reading incoming date"
					,"LDEV-1172":"SNI support"
				}
				,{
					"LDEV-1036":"callStackGet() function no longer returns full paths to template"
					,"LDEV-1020":"http.setMethod('put') does not send variables set with http.addParam(type='form')"
					,"LDEV-1002":"NPE cfmail with empty html body."
					,"LDEV-995":"Performance Degradation with Unary Increment Operator"
					,"LDEV-969":"JSON-String inside <cfsavecontent> throws error"
					,"LDEV-988":"performance degradation with unary operator in for loops"
					,"LDEV-901":"clustered session/client scope does not merge data"
					,"LDEV-954":"cfhttp blocks for long running calls"
					,"LDEV-914":"sessionInvalidate() causes java.lang.ClassCastException"
					,"LDEV-918":"J2EE Session not maintained in cfhttp requests"
					,"LDEV-947":"cfsavecontent & cfinclude - java.util.ConcurrentModificationException"
					,"LDEV-441":"UDF's mixed into CFC via temp file error when trying to recompile and file is deleted"
					,"LDEV-901":"clustered session/client scope does not merge data"
					,"LDEV-866":"entrySet from a linked struct is loosing the order"
				}
				,{
					"LDEV-992":"JSON Security issue"
					,"LDEV-862":"DateTimeFormat returns wrong value for ISO8601"
					,"LDEV-834":"CollectionMap Causes a Threadleak when parallel=true"
					,"LDEV-840":"webservice complex object invalid case"
					,"LDEV-637":"cfstoredproc fails when calling a procedure with parameters on Oracle with a specified schema"
					,"LDEV-830":"query fails with Can't call commit when autocommit=true"
					,"LDEV-32":"Incompat with val()"
					,"LDEV-775":"Bug with fileExists() with an Application mapping of /"
					,"LDEV-812":"Writelog/cflog's file is not unique per web context"
					,"LDEV-814":"cfadmin action=""stopThread"" does not work"
					,"LDEV-818":"queryAddColumn does not accept a type argument"
					,"LDEV-793":"Fix compatibility - HTML 5 multiple file upload"
					,"LDEV-789":"Web Service CFC soap XML"
					,"LDEV-688":"LDEV-488 Fix Re-Introduces LDEV-78 Bug"
					,"LDEV-777":"connection pool counter is not thread safe"
					,"LDEV-778":"CSV parser used with cfhttp fails with NL at the end"
					,"LDEV-774":"JEE session looses data on onsessionEnd call"
					,"LDEV-761":"CR line breaks when using <cfhttp> on csv files"
					,"LDEV-738":"relative component path fails"
					,"LDEV-714":"onSessionEnd creates WEB-INF/lucee/output/onSessionEnd.out"
					,"LDEV-719":"missing name declaration for property"
					,"LDEV-622":"Cannot use a Map as a struct with null value"
					,"LDEV-684":"CFARGUMENT Can't cast String [] to a boolean"
					,"LDEV-692":"getApplicationSettings() does not return expected results"
					,"LDEV-224":"QueryExecute throws error when specifying list of numerics"
					,"LDEV-297":"DSN screen UX"
					,"LDEV-360":"Add explicit link to ""Overview"" in Admin navigation"
					,"LDEV-371":"cfhttp creates connections that don't expire until the keep-alive timeout"
					,"LDEV-434":"isJSON and deserializeJSON accept invalid JSON"
					,"LDEV-458":"Parsing issue with CFC property containing attribute with no value"
					,"LDEV-467":"?: bug with false"
					,"LDEV-488":"ORM Stack overflow error"
					,"LDEV-490":"Regression - ""ORM not enabled"" error when ORM attributes are used"
					,"LDEV-516":"Debug output doesn't show up if using default-function-output=false"
					,"LDEV-573":"Update links in Lucee web and server admin home page screens"
					,"LDEV-631":"YesNoFormat() empty string response"
					,"LDEV-671":"QueryExecute right context"
					,"LDEV-650":"share application context with modern and classic listener fails"
					,"LDEV-620":"enlargeCapacity blocks the system"
				}
				,{
					"LDEV-599":"inspect template double check leads to missingIncludeException"
					,"LDEV-569":"SSLCertificateInstall fails with some hosts"
					,"LDEV-411":"Debugging displays wrong execution times in specific cases"
					,"LDEV-557":"life and idle timeout for mail server"
					,"LDEV-471":"SQL Error, Negative delay"
					,"LDEV-509":"datasource storage clean open new connection"
					,"LDEV-24":"queryExecute does not support passing arguments scope as param structure"
					,"LDEV-340":"SpoolerEngineImpl$SimpleThread can get in an endless loop"
					,"LDEV-364":"queryParam null=true doesn't work for QueryExecute"
					,"LDEV-370":"cfscript Query doesn't play well with oracle parameters"
					,"LDEV-432":"Better ORM Errors, Include SQL statement"
					,"LDEV-475":"fileSetLastModified() Fails Silently on Non-Existent File"
					,"LDEV-476":"built in function names reserved in cfinterface"
					,"LDEV-492":"XML objects don't cast to string properly"
					,"LDEV-501":"PostgreSQL Driver Queries Fail in 4.5.2.005"
					,"LDEV-503":"Lucee fails to read cookie"
					,"LDEV-504":"controller thread can get blocked"
					,"LDEV-485":"cfhttp (with updated library) timeout issue"
					,"LDEV-479":"improve default query timeout"
					,"LDEV-480":"validate connections in the datasource connection pool"
					,"LDEV-472":"Queries called from event gateways break due to invalid request timeout"
					,"LDEV-457":"HTMLEditFormat handling of carriage returns"
					,"LDEV-470":"Graylog does not work with Lucee"
					,"LDEV-463":"reduce size of of udf properties (getter/setter/ ...)"
					,"LDEV-429":"Unable to access Youtube API using SSL"
					,"LDEV-430":"logging for datasources"
				}
				,{
					"LDEV-78":"ORM doesn't persist data in cftransactions"
					,"LDEV-384":"Hanging requests if debugging is enabled / Locking in ArrayImpl"
					,"LDEV-383":"cfhttp fails"
					,"LDEV-292":"CFHTTP fails over SSL with SNI"
					,"LDEV-376":"writable CGI Scope"
					,"LDEV-372":"make CGI Scope writable"
					,"LDEV-354":"IsEmpty(0) returns true"
					,"LDEV-353":"NPE when using a struct as an exception"
					,"LDEV-348":"Invalid Cookie name causes stacktrace and can bring down lucee/tomcat"
					,"LDEV-322":"If structKeyExists() works on an Exception, so should .keyExists()"
					,"LDEV-47":"Support for (element in list)"
					,"LDEV-327":"add frontend for request Queue"
					,"LDEV-338":"declared inline datasource does not work with ORM"
					,"LDEV-2":"QueryExecute generates wrong entries in the debug information"
					,"LDEV-327":"add frontend for request Queue"
					,"##331":"cached query not disconnect from life query"
					,"##23":"queryExecute does not support passing arguments scope as param structure"
					,"##237":"application.cfc this.tag.function.output=""false"" default attribute value does not work"
					,"##319":"mail sending is synchronized"
					,"##293":"Listener mode modern invokes Application.cfm files"
					,"##292":"duplicate check in duplication get not cleaned"
					,"##277":"Request timeout fails with Java8"
					,"##274":"ThreadQueue size is off"
					,"##210":"Duplicate encoding in soap webservice"
					,"##222":"Setting request timeout to 0 throws exception"
					,"##216":"typo ""succesful"" when verifying smtp server"
					,"##215":"queryExecute allows invalid parameter syntax without erroring"
					,"##207":"Error in memcached cache after migration from Railo"
					,"##204":"Update CFHTTP multipart response handling to support quoted boundaries"
					,"##201":"Make Lucee compatible with Railo extensions"
					,"##189":"Extension license viewer displays white text on white background, thus it never displays"
					,"##178":"Multipart image byte array response doesn't handle quoted boundary"
					,"##188":"cfhttp empty csv fails"
					,"##185":"The Layout CFC based CustomTag still has references to the railo package"
					,"##180":"RequestTimeout cripples 3 party code"
					,"##164":"""!"" in mail message"
					,"##150":"Error executing function tests as embedded Application.cfc was missing TestBox archive"
					,"##78":"Services - Update: Error ""server http://dev.lucee.org failed to return a valid response. The key [APIKEY] does not exist."""
					,"##103":"queryGetRow() function and Query.getRow() method"
					,"##145":"Lucee logo and maximize/minimize button disappear with maximised"
					,"##147":"structKeyExists return true for ""server.railo"""
					,"##118":"toBinary should not throw an error when 1st arg is an empty string"
					,"##136":"Get off of Java 7"
					,"##143":"testcases testbox archive not works"
					,"##139":"Admin page broken - Remote: Security Key"
					,"##126":"actions without text are not processed by cfhtmlhead and cfhtmlbody"
					,"##125":"cfhtmlhead and cfhtmlbody ignore the id attribute"
					,"##3":"dateDiff() method implemented incorrectly"
					,"##79":"Axis info messages shouldn't be logged"
					,"##4":"cfhtmlhead does not work"
					,"##8":"getID() built-in function conflicting with component functions"
					,"##88":"Admin Settings Export: extra equals sign in mappings statements"
					,"##80":"Verify Providers: key [VALIDURLS] doesn't exist (existing keys:ROWS,URLS)"
					,"##76":"ContentBox with Lucee"
					,"##21":"Error when migrating if EHCache is defined"
					,"##15":"Mura/ORM reload error after upgrade from Railo"
					,"##14":"Layout.cfc is looking for railo.core.ajax.AjaxBinder"
					,"##13":"Debugging settings issue"
					,"##11":"missing IEventHandler Interface"
				}
			]

		);

  
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


<h2>Lucee</h2>
<p>
<a class="linkk" href="?type=releases">Releases</a>
| <a class="linkk" href="?type=abc">Betas/Release Candidates</a>
| <a class="linkk" href="?type=snapshots">Snapshots</a>
</p>


<h2>Extensions</h2>
<p>
<a class="linkk" href="?type=ext">Releases</a>
| <a class="linkk" href="?type=extabc">Betas/Release Candidates</a>
| <a class="linkk" href="?type=extsnap">Snapshots</a>
</p>

<br>
<hr>

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
  if(queryColumnExists(downloads,"changelog")) {
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
  }
//dump(downloads);



</cfscript>
<cfif isNull(latest)>
  <p>#noVersion#</p>
<cfelse>
		<h1>Lucee #singular[type]#</h1>
		<h2>#downloads.version[latest]#</h2>
		<p>#replace(replace(replace(intro,"{date}",lsDateFormat(downloads.jarDate[latest])),"{version}",downloads.version[latest]),"{type}",singular[type])# #lang.desc[type]#</p>

		<!--- installers --->
		<cfif  type == "releases" >
			<cfset installers=getInstaller(downloads.version[latest])>
			<cfif structCount(installers)>
				<h3>Installers (*.exe, *.run)</h3>
				<p>Platform Specific Installers for
				<cfset count=1>
				<cfset str="">
				<cfset l=structCount(installers)>
				<cfloop struct="#installers#" index="k" item="v">
					<cfif count GT 1>
						<cfif count	EQ l>
							<cfset str&=' and '>
						<cfelse>
							<cfset str&=', '>
						</cfif>		
					</cfif>
					<cfset str&='<a href="#toCDN(v)#">#lang.installer[k]#</a>'>
					<cfset count++>
				</cfloop>
				<cfoutput>#str#</cfoutput>
			</cfif>
		</cfif>
		
		<!---  Express--->
		<h3>Express Build (*.zip)</h3>
		<p>#lang.express#<br>
		<cfset uri="#_url[type]#/rest/update/provider/express/#downloads.version[latest]#">
		<a href="#toCDN(uri)#">download</a></p>

		<!--- jar --->
		<h3>Jar file (*.jar)</h3>
		<p><cfif downloads.v[latest] GTE _5_0_0_219>#lang.libNew#<cfelse>#lang.lib#</cfif><br>
		<cfset uri="#_url[type]#/rest/update/provider/#downloads.v[latest] GTE _5_0_0_112?"loader":"libs"#/#downloads.version[latest]#">
		<a href="#toCDN(uri)#">lucee.jar<cfif downloads.v[latest] LT _5_0_0_219> (no dependecies)</cfif></a>
		<cfif downloads.v[latest] GTE _5_0_0_112 and downloads.v[latest] LT _5_0_0_219>
			<cfset uri="#_url[type]#/rest/update/provider/loader-all/#downloads.version[latest]#">
			<br><a href="#toCDN(uri)#">lucee.jar (with dependecies)</a>
		</cfif>
		</p>


		<!--- War --->
		<h3>WAR file (*.war)</h3>
		<p>#lang.war#<br>
		<cfset uri="#_url[type]#/rest/update/provider/war/#downloads.version[latest]#">
		<a href="#toCDN(uri)#">download</a></p>

		<!--- Lucee Core --->
		<h3>Core file (*.lco)</h3>
		<p>#lang.core#<br>
		<cfset uri="#_url[type]#/rest/update/provider/download/#downloads.version[latest]#">
		<a href="#toCDN(uri)#">download</a></p>


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
			<cfif  url.type == "releases"><td align="center"><h3>Installer</h3></td></cfif>	
			<td align="center"><h3>Express</h3></td>
			<td align="center"><h3>Jar</h3></td>
			<td align="center"><h3>Core</h3></td>
			<td align="center"><h3>WAR</h3></td>
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
        downloads.v == _5_2_1_8 ||
        downloads.v == _5_2_3_30_RC 
        
			>
				<cfcontinue>
			</cfif>
			<cfset css="">
			<cfif true><!--- downloads.version!=downloads.version[latest] --->
			<tr>
				<td class="#css#" align="center">#downloads.version#</td>
				<td class="#css#" align="center">#lsDateFormat(downloads.jarDate)#</td>
				<cfif  url.type == "releases">
					<td class="#css#">
					<cfset installers=getInstaller(downloads.version)>
					<cfset count=1>
					<cfset str="">
					<cfset l=structCount(installers)>
					<cfloop struct="#installers#" index="kk" item="vv">
						<cfif count GT 1>
							<cfset str&=', '>
						</cfif>
						<cfset str&='<a href="#toCDN(vv)#">#lang.installer[kk]#</a>'>
						<cfset count++>
					</cfloop>
					<cfoutput>#str#</cfoutput>
					</td>
				</cfif>
				<td class="#css#">
					<cfset uri="#_url[type]#/rest/update/provider/express/#downloads.version#">
					<a href="#toCDN(uri)#">Express</a>
				</td>

				<td class="#css#" >
					<cfif downloads.v GTE _5_0_0_219>
						<cfset uri="#_url[type]#/rest/update/provider/loader/#downloads.version#">
						<a href="#toCDN(uri)#">lucee.jar</a>
					<cfelseif downloads.v GTE _5_0_0_112>
						<cfset uri="#_url[type]#/rest/update/provider/loader-all/#downloads.version#">
						<a href="#toCDN(uri)#">lucee.jar</a></span>
					<cfelse>
						-
					</cfif></td>

				<cfset uri="#_url[type]#/rest/update/provider/download/#downloads.version#">
				<td class="#css#"><a href="#toCDN(uri)#">Core</a></td>
				<cfset uri="#_url[type]#/rest/update/provider/war/#downloads.version#">
				<td class="#css#"><a href="#toCDN(uri)#">WAR</a></td>


			</tr>
			<!--- changelog --->
			<cfif !isNull(downloads.changelog) && isStruct(downloads.changelog) && structCount(downloads.changelog)>
			<tr>
				<td colspan="#(type == "releases")?8:7#" class="grey">
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


		<!--- Lucee 4.5 --->
		<cfif  type == "releases" ><cfloop query=downloads45>
			<cfset css="">
			<tr>
				<td class="#css#" align="center">#downloads45.version#</td>
				<td class="#css#" align="center">#lsDateFormat(downloads45.date)#</td>
				<cfif  type == "releases">
					<td class="#css#">
					<cfset installers=downloads45.installer>
					<cfset count=1>
					<cfset str="">
					<cfset l=structCount(installers)>
					<cfloop struct="#installers#" index="kk" item="vv">
						<cfif count GT 1>
							<cfset str&=', '>
						</cfif>
						<cfset str&='<a href="#toCDN(vv)#">#lang.installer[kk]#</a>'>
						<cfset count++>
					</cfloop>
					<cfoutput>#str#</cfoutput>
					</td>
				</cfif>
				<td class="#css#">
					<cfset uri="#downloads45.express#">
					<a href="#toCDN(uri)#">Express</a>
				</td>

				<td class="#css#" >
					<cfset uri="#downloads45.jar#">
					<a href="#toCDN(uri)#">lucee.jar</a>
				</td>

				<cfset uri="#downloads45.core#">
				<td class="#css#"><cfif len(uri)><a href="#toCDN(uri)#">Core</a></cfif></td>
				<cfset uri="#downloads45.war#">
				<td class="#css#"><a href="#toCDN(uri)#">WAR</a></td>


			</tr>
			<!--- changelog --->
			<cfif !isNull(downloads45.changelog) && isStruct(downloads45.changelog) && structCount(downloads45.changelog)>
			<tr>
				<td colspan="#(type == "releases")?8:7#" class="grey">
                                  <div class="clog-wrapper">
					<h3 class="clog-toggle pointer">Changelog <i class="icon icon-collapse"></i></h3>
					<div class="clog-detail">
						<cfset sct=downloads45.changelog>
						<cfset keys=structKeyArray(sct)>
						<cfset arraySort(keys,function(l,r) {
							return compare(makeComparable(r),makeComparable(l));
							})>
						<cfloop array="#keys#" index="i" item="key">
					<cfif find('LDEV-',key)>
						<a href="http://bugs.lucee.org/browse/#key#">#key#</a>
					<cfelse>
						#key#
					</cfif>
					 #sct[key]#<br>
					</cfloop></div>
                                   </div><!-- .clog-wrapper !-->
				</td>
			</tr>

			</cfif>

		</cfloop></cfif>

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




<cfif !isNull(extQry)>

<!--- output --->
<cfoutput>
<h1>Extension #singular[url.type]#</h1>
<p>Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.</p>

<cfif url.type=="extabc">
<p>To install this Extensions from within your Lucee Administrator, you need to add "http://beta.lucee.org" under "Extension/Provider" as a new Provider, after that you can install this Extensions under "Extension/Application" in the Administartor.</p>
<cfelseif url.type=="ext">
<p>You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>
<cfelseif url.type=="extsnap">
</cfif>


<table border="1">
<cfloop query="#extQry#">
<tr>
	<td><img src="data:image/png;base64,#extQry.image#"></td>
	<td>
		<h2>#extQry.name#</h2>
		<p>
			ID:#extQry.id#<br>
			Latest Version:#extQry.version#<br>
			Category:#extQry.category#<br>
			Birth Date:#extQry.created#<br>
			Trial:#yesNoFormat(extQry.trial)#
		</p>
		<p>#extQry.description#</p>
		<p><a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',extQry.trial?"trial":"full"),'{id}',extQry.id)#?version=#extQry.version#">
		download#extQry.trial?" trial":""# version (#extQry.version#)  </a></p>
		<cfif !isNull(extQry.older) && isArray(extQry.older) && arrayLen(extQry.older)>
		<cftry><cfset arraySort(extQry.older,function(l,r) {return compare(toVersionSortable(l),toVersionSortable(r)); })><cfcatch></cfcatch></cftry>
		<p>Older Versions:
		<ul>
		<cfloop array="#extQry.older#" item="_older">
			<li><a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',extQry.trial?"trial":"full"),'{id}',extQry.id)#?version=#_older#">
		download#extQry.trial?" trial":""# version (#_older#)  </a></li>
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
