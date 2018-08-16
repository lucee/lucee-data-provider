
<cfoutput>
<cfscript>
	cdnURL="https://cdn.lucee.org/";

	if(isNull(url.type)) url.type="releases";

	// if(cgi.http_host!="download.lucee.org") location url="http://download.lucee.org" addtoken=false;

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
	_5_2_8_52=toVersionSortable("5.2.8.52-SNAPSHOT");

	// 5.2.8.52-SNAPSHOT/
	if(isNull(url.type))url.type="releases";
	else type=url.type;

	intro="The latest {type} is version <b>{version}</b> released at <b>{date}</b>.";
	historyDesc="Older Versions:";
	singular={
		releases:"Release",snapshots:"Snapshot",abc:'RC / Beta',beta:'Beta',rc:'RC'
		,ext:"Release",extsnap:"Snapshot",extabc:'RC / Beta'
	};
	multi={
		release:"Releases",
		snapshot:"Snapshots",
		abc:'RCs / Betas',
		beta:'Betas',
		rc:'Release Candidates'
	};
	appendix={
		releases:"Release",
		snapshots:"",
		abc:'',
		beta:'',
		rc:''
	};

	noVersion="There are currently no downloads available in this category.";

	downloads45=query(
		version:[
			'4.5.5.015'
			,'4.5.5.006'
			,'4.5.4.017'
			,'4.5.3.020'
			,'4.5.2.018'
			,'4.5.1.024'
		]
		,date:[
			createDate(2018,4,9)
			,createDate(2017,1,26)
			,createDate(2016,10,24)
			,createDate(2016,9,1)
			,createDate(2015,11,9)
			,createDate(2015,10,20)
		]
		,installer:[
			{
			}
			,{
				win:cdnURL&"lucee-4.5.5.006-pl0-windows-installer.exe"
				,lin64:cdnURL&"lucee-4.5.5.006-pl0-linux-x64-installer.run"
				,lin32:cdnURL&"lucee-4.5.5.006-pl0-linux-installer.run"
			}
			,{
				win:cdnURL&"lucee-4.5.4.017-pl0-windows-installer.exe"
				,lin64:cdnURL&"lucee-4.5.4.017-pl0-linux-x64-installer.run"
				,lin32:cdnURL&"lucee-4.5.4.017-pl0-linux-installer.run"
			}
			,{
				win:cdnURL&"lucee-4.5.3.020-pl0-windows-installer.exe"
				,lin64:cdnURL&"lucee-4.5.3.020-pl0-linux-x64-installer.run"
				,lin32:cdnURL&"lucee-4.5.3.020-pl0-linux-installer.run"
			}
			,{
				win:cdnURL&"lucee-4.5.2.018-pl0-windows-installer.exe"
				,lin64:cdnURL&"lucee-4.5.2.018-pl0-linux-x64-installer.run"
				,lin32:cdnURL&"lucee-4.5.2.018-pl0-linux-installer.run"
			}
			,{
				win:cdnURL&"lucee-4.5.1.024-pl0-windows-installer.exe"
				,lin64:cdnURL&"lucee-4.5.1.024-pl0-linux-x64-installer.run"
				,lin32:cdnURL&"lucee-4.5.1.024-pl0-linux-installer.run"
			}
		]
		,express:[
			cdnURL&'lucee-4.5.5.015-express.zip'
			,cdnURL&'lucee-4.5.5.006-express.zip'
			,cdnURL&'lucee-4.5.4.017-express.zip'
			,cdnURL&'lucee-4.5.3.020-express.zip'
			,cdnURL&'lucee-4.5.2.018-express.zip'
			,cdnURL&'lucee-4.5.1.024-express.zip'
		]
		,jar:[
			cdnURL&'lucee-4.5.5.015-jars.zip'
			,cdnURL&'lucee-4.5.5.006-jars.zip'
			,cdnURL&'lucee-4.5.4.017-jars.zip'
			,cdnURL&'lucee-4.5.3.020-jars.zip'
			,cdnURL&'lucee-4.5.2.018-jars.zip'
			,cdnURL&'lucee-4.5.1.024-jars.zip'
		]
		,war:[
			cdnURL&'lucee-4.5.5.015.war'
			,cdnURL&'lucee-4.5.5.006.war'
			,cdnURL&'lucee-4.5.4.017.war'
			,cdnURL&'lucee-4.5.3.020.war'
			,cdnURL&'lucee-4.5.2.018.war'
			,cdnURL&'lucee-4.5.1.024.war'
		]
		//'https://bitbucket.org/lucee/lucee/downloads/4.5.5.006.lco'
		,core:[
			cdnURL&'4.5.5.015.lco'
			,cdnURL&'4.5.5.006.lco'
			,cdnURL&'4.5.4.017.lco'
			,cdnURL&'4.5.3.020.lco'
			,cdnURL&'4.5.2.018.lco'
			,cdnURL&'4.5.1.024.lco'
		]
		,changelog:[
			{
				"LDEV-1462":"expandPath fails with contextpath that are start the same way as other contextpath"
			}
			,{
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
	<script crossorigin="anonymous" integrity="sha384-KJ3o2DKtIkvYIK3UENzmM7KCkRr/rE9/Qpg6aAZGJwFDMVNA/GpGFF93hXpG5KkN" src="https://code.jquery.com/jquery-3.2.1.slim.min.js"></script>
	<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">
	<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
	<link href="/res/download.css" rel="stylesheet">
</cfhtmlhead>
<cfhtmlbody>
<script src="/res/download.js"></script>
</cfhtmlbody>
<style rel="stylesheet">
.data-content{ background-color: ##01798a; color: white; min-width: 100%; font-size: 14px; line-height: 15px;}

.triggerIcon{color :##01798A !important;}
.pointer {cursor: pointer;}
.jumboStyle {padding: 0rem 0rem !important; border-radius : 0px !important; text-align: center !important;}
.fontSize{font-size: 20px !important;}

.BoxWidth { padding: 1rem 1rem 2rem 1rem; border-radius: 1%; padding-left: 6%;}
.col-md-3{ padding-right: 8px !important; padding-left: 8px !important; }
.desc{ padding: 8px; vertical-align: top; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol"; font-size: 1.5rem; font-weight: 600; line-height: 1.5; color: ##212529; text-align: left;}
.descDiv{min-height: 130px;}
.installerDiv{min-height: 75px;}
.jarDiv{min-height: 60px;}
.divHeight{min-height: 36px;}
.fontStyle { font-size: 16px !important; font-weight: normal !important;}
.row_even { background-color: ##EBEBEB; padding: 1% 0 0 4%; }
.row_odd { background-color: ##DADADA; padding: 1% 0 0 4%; }
.borderInfo { border: 1px ridge ##C7C7C7 !important; padding-left: 0px !important; padding-right: 0px !important;background-color:##EBEBEB; }
.well{background-color: white !important;}
.popover-content{ padding: 0.5px 0px !important; }
.popover.bottom .arrow:after { border-bottom-color: ##01798A !important; }
.popover{ border: 2px solid ##01798a !important;}
.popover-title{ padding: 4px 8px !important; }
.row_alterEven{ background-color: ##EBEBEB; padding: 0% 0 0 4%; } 
.row_alterOdd{ background-color: ##DADADA; padding: 0% 0 0 4%; }

/*.TextStyle{ padding: 1%; font-family: "Segoe UI"; font-size: 1.25rem; font-weight: 600;}*/
.TextStyle{ padding: 1%; font-family:  -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol" !important; font-size:1.5rem !important;font-weight: normal !important;}
.head1{font-family: "Times New Roman", Times, serif; font-size: 2.5rem; font-weight: 503;}
h2.fontSize{margin-bottom:-1.80rem !important;}
.title{font-family:  -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol" !important;font-size: 28px !important;}
.textWrap{text-align:center;overflow:hidden;white-space:nowrap;}
@media only screen and (max-width: 1200px){
.textWrap{text-align:center !important;overflow:auto !important;white-space:normal !important;}
}
@media only screen and (min-width: 1500px){
.textWrap{text-align:center !important;overflow:auto !important;white-space:normal !important;}
}

</style>



<!DOCTYPE html>
<html>
	<head>
		<meta charset="utf-8">
		<meta content="ie=edge" http-equiv="x-ua-compatible">
		<meta content="initial-scale=1, shrink-to-fit=no, width=device-width" name="viewport">
		<title>Download Lucee</title>
		<link rel="shortcut icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="72x72" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="114x114" href="/res/images/logo.png">
		<cfhtmlhead action="flush">
	</head>
	<body class="container py-3">

		<!--- output --->
			<div class="bg-primary jumbotron text-white">
				<h1 class="display-3">Downloads</h1>
				<p>Lucee core and extension downloads.</p>
			</div>

			<cfif type EQ "releases" or type EQ"snapshots" or type EQ "abc" or type EQ "beta" or type EQ "rc">
				<cfscript>
					adownloads=getDownloads();
				</cfscript>

				<cfif true>
					<!--- <cfif structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5>
						<div class="alert alert-danger">
						   <strong>Warning: </strong> <span style="font-size: 14px;"> Lucee 4.5 has reached it end of life, it will no longer get any security updates or hot fix </span>
					  	</div>
					</cfif>	 --->
					<h2>Lucee Core</h2>
					<p style="font-size: 1.7rem;">Get releases, release candidates, beta or snapshots from Lucee.</p>
					<script type="text/javascript">
						$(document).ready(function () {
							isSafari = !!navigator.userAgent.match(/Version\/[\d\.]+.*Safari/)
							var isTouch = ('ontouchstart' in document.documentElement);
							if(isTouch) var mthd = 'click';
							else var mthd = 'mouseenter';
							$('.triggerIcon').attr('class','pop').attr("popover-placement", "auto");
							$(".pop").popover({
								trigger: "hover",
								placement: 'bottom',
								position: 'relative',
								html: true,
								animation:false
							})
							.on(mthd, function () {
								var _this = this;
								if (isSafari) {
									$('.popover').attr('style', 'max-width: 200px !important');
									$('.popover-title').attr('style', 'max-width: 100px !important');
								}
								$(this).popover("show");
							})
							.on("mouseleave touchmove", function () {
								var _this = this;
								setTimeout(function () {
									if (!$(".popover:hover").length) {
									  $(_this).popover("hide");
									}
								})
							});
						});
						function hideData (a) {
						  $('.'+a).removeClass('show');
						  $('##'+a+'_id').show();
						}
						function hideToggle (a) {
						  $('##'+a).hide();
						}
						function change(type,field,id) {
						  window.location="?"+type+"="+field.value+"##"+id;
						}
					</script>
					<cfscript>
						rows={};
					</cfscript>
					<div class="panel" id="core">
						<cfset types="releases,snapshots,rc,beta">
						<div class="panel-body">
							<cfloop list="releases,snapshots,rc,beta" item="_type">
								<div class="col-md-3 col-sm-3 col-xs-3">
									<!--- dropDown --->
									<div class="bg-primary BoxWidth text-white">
										<cfif !structKeyEXists(url,_type)>
											<cfloop query="#adownloads#"><cfif adownloads.t==_type><cfset url[_type]=adownloads.id><cfset rows[_type]=adownloads.currentrow><cfbreak></cfif></cfloop>
										</cfif>
										<b><h2>#singular[_type]#</h2> <!--- #ldownloads[type].versionNoAppendix#</b> (#lsDateFormat(ldownloads[type].jarDate)#) --->
										<select onchange="change('#_type#',this, 'core')" style="color:7f8c8d;font-style:normal;" id="lCore" class="form-control" <!--- class="custom-select" --->>
											<cfloop query="#adownloads#"><cfif adownloads.t==_type><option <cfif url[_type]==adownloads.id><cfset rows[_type]=adownloads.currentrow> selected="selected"</cfif> value="#adownloads.id#"><!---

												--->#adownloads.versionNoAppendix# (#lsDateFormat(adownloads.jarDate)#)</option></cfif></cfloop>

											<cfif _type EQ "releases">
											<cfloop query="#downloads45#">
												<option <cfif ListLast(url[_type], "_")==downloads45.version><cfset rows['releases']=downloads45.currentrow> selected="selected"</cfif> value="4.5_#downloads45.version#"><!---
												--->#downloads45.version# (#lsDateFormat(downloads45.date)#)</option>
											</cfloop>
											</cfif>
										</select>
									</div>
									<!--- desc --->
									<div class="desc descDiv row_even">#lang.desc[_type]#</div>
									<!--- Express --->
									<div class="row_odd divHeight">
										<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
											<cfset dw=querySlice(downloads45,rows['releases'],1)>
											<cfset uri=toCDN(dw.express)>
										<cfelse>
											<cfset dw=querySlice(adownloads,rows[_type],1)>
											<cfif dw.s3Express>
												<cfset uri="#cdnURL#lucee-express-#dw.version#.zip">
											<cfelse>
												<cfset uri="#_url[type]#/rest/update/provider/express/#dw.version#">
											</cfif>
										</cfif>
										<div class="fontStyle">
											<a href="#(uri)#">Express</a>
											<span  class="triggerIcon pointer" style="color :##01798A" title="#lang.express#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</div>
									</div>
									<!--- Installer --->
									<div class="row_even installerDiv">
										<cfif _type == "releases">
											<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
												<cfset dw=querySlice(downloads45,rows['releases'],1)>
												<cfset installers=dw.installer>
											<cfelse>
												<cfset dw=querySlice(adownloads,rows[_type],1)>
												<cfset installers=getInstaller(dw.version)>
											</cfif>
											<cfif structIsEmpty(installers) && (listFirst(dw.version,".") GTE 5)>
												<div class="fontStyle">
													<span class="text-primary">Coming Soon!</span>
													<span  class="triggerIcon pointer" style="color :##01798A" title="Installers will available on soon">
														<span class="glyphicon glyphicon-info-sign"></span>
													</span>
												</div>
											<cfelse>
												<cfset count=1>
												<cfset str="">
												<cfset l=structCount(installers)>
												<cfloop struct="#installers#" index="kk" item="vv">
													<cfif count GT 1>
														<cfset str&='<br>'>
													</cfif>
													<cfset str&='<a href="#toCDN(vv)#">#lang.installer[kk]# Installer</a> <span  class="triggerIcon pointer" style="color :##01798A" title="#lang.installer[kk]# Installer">
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>'>
													<cfset count++>
												</cfloop>
												<div class="fontStyle">#str#</div>
											</cfif>
										</cfif>
									</div>
									<!--- jar --->
									<div class="row_odd jarDiv">
										<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
											<cfset dw=querySlice(downloads45,rows['releases'],1)>
											<div class="fontStyle"><a href="#toCDN(dw.jar)#">lucee.jar</a><span  class="triggerIcon pointer" style="color :##01798A" title="#lang.jar#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>
										<cfelse>
											<cfset dw=querySlice(adownloads,rows[_type],1)>
											<cfset uri="#_url[_type]#/rest/update/provider/loader/#dw.version#">
											<div class="fontStyle"><a href="#(uri)#">lucee.jar</a><span  class="triggerIcon pointer" style="color :##01798A" title="#lang.jar#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>

											<cfif dw.s3Light>
												<cfset uri="#cdnURL#lucee-light-#dw.version#.jar">
											<cfelse>
												<cfset uri="#_url[_type]#/rest/update/provider/light/#dw.version#">
											</cfif>
											<div class="fontStyle"><a href="#(uri)#">lucee.jar(without Extension)</a><span  class="triggerIcon pointer" style="color :##01798A" title="Lucee Jar file without Extension bundled">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>

										</cfif>
									</div>
									<!--- core --->
									<div class="row_even divHeight">
										<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
										<cfset dw=querySlice(downloads45,rows['releases'],1)>
										<cfset uri=toCDN(dw.core)>
										<cfelse>
											<cfset dw=querySlice(adownloads,rows[_type],1)>
											<cfif dw.s3Core>
												<cfset uri="#cdnURL##dw.version#.lco">
											<cfelse>
												<cfset uri="#_url[_type]#/rest/update/provider/core/#dw.version#">
											</cfif>
										</cfif>
										<div class="fontStyle"><a href="#(uri)#" >Core</a><span class="triggerIcon pointer" style="color :##01798A" title='#lang.core#'>
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>
									</div>
									<!--- WAR --->
									<div class="row_odd divHeight">
										<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
										<cfset dw=querySlice(downloads45,rows['releases'],1)>
										<cfset uri=toCDN(dw.war)>
										<cfelse>
											<cfset dw=querySlice(adownloads,rows[_type],1)>
											<cfif dw.s3War>
												<cfset uri="#cdnURL#lucee-#dw.version#.war">
											<cfelse>
												<cfset uri="#_url[_type]#/rest/update/provider/war/#dw.version#">
											</cfif>
										</cfif>
										<div class="fontStyle"><a href="#(uri)#" title="#lang.war#">WAR</a><span class="triggerIcon pointer" style="color :##01798A" title="#lang.war#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>
									</div>
									<!--- logs --->
									<div class="row_even divHeight">
										<cfif _type=="releases" && structKeyExists(URL, "releases") && ListFirst(URL.releases, "_") EQ 4.5 >
											<cfset dw=querySlice(downloads45,rows['releases'],1)>
											<cfset res.version = dw.version>
											<cfset res.changelog = dw.changelog>
										<cfelse>
											<cfset downloads=getDownloadFor(_type)>
											<cfset dw=querySlice(adownloads,rows[_type],1)>
											<cfquery name="res" dbtype="query">
												select * from downloads where ID = '#dw.id#'
											</cfquery>
										</cfif>
										<cfif isstruct(res.changelog) && structCount(res.changelog) GT 0>
											<div class="fontStyle">
												<p class="collapsed mb-0" data-toggle="modal" data-target="##myModal#_type#">Changelog<small class="align-middle h6 mb-0 ml-1"><i class="icon icon-collapse collapsed"></i></small></p>
											</div>
											<div class="modal fade" id="myModal#_type#" role="dialog">
												<div class="modal-dialog modal-lg">
													<div class="modal-content">
														<div class="modal-header">
															<button type="button" class="close" data-dismiss="modal">&times;</button>
															<h4 class="modal-title"><b>Version-#res.version# Changelogs</b></h4>
														</div>
														<div class="modal-body desc">
															<cfloop struct="#res.changelog#" index="id" item="subject">
																<a href="http://bugs.lucee.org/browse/#id#" target="blank">#id#</a>- #subject#
																<br>
															</cfloop>
														</div>
														<div class="modal-footer">
															<button type="button" class="btn btn-default btn-lg" data-dismiss="modal">Close</button>
														</div>
												  	</div>
												</div>
											</div>
										<cfelse>
											<div class="fontStyle"></div>
										</cfif>
									</div>
									<div><hr></div>
								</div>
							</cfloop>
						</div>
					</div>

					<div id="ext">
						<h2>Extensions</h2>
						<p style="font-size: 1.7rem;font-weight:normal;">Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.
						You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>
						<cfset types_ = "release,abc,snapshot">
						<cfset rows_ = {}>
						<cfset extQry_ = {}>
						<cfloop list="#types_#" item="type">
							<cfset extQry_[type]=getExtensions(type)>
						</cfloop>
						<cfset ListID = "">
						<div id="ext">
							<cfloop list="#types_#" item="type">
								<cfloop query=extQry_[type]>
									<cfif listFindNoCase(ListID, extQry_[type].id) GT 0>
										<cfcontinue>
									</cfif>
									<cfset ListID = listAppend(ListID, extQry_[type].id)>
									<div class="container">
										<cfset extVersions = {}>
										<cfset extVersions[type]= extQry_[type].older>
										<cfif arrayLen(ArrayFindAllNoCase( extVersions[type], extQry_[type].version ) )  EQ 0>
											<cfset arrayPrepend(extVersions[type], extQry_[type].version)>
										</cfif>
										<cfsavecontent variable="details1">
											Latest Version: <i>#extQry_[type].version#</i><br>
											Birth Date: <i>#dateFormat(extQry_[type].created,'mmmm, dd/yyyy')#</i><br>
											Trial: <i>#yesnoformat(extQry_[type].trial)#</i>
										</cfsavecontent>
										<cfset extVersions['_'&type] = details1>

										<cfloop list="#types_#" item="extType">
											<cfif extType EQ type>
												<cfcontinue>
											</cfif>
											<cfset table = extQry_[extType]>
											<cfquery dbtype="query" name="_res">
												select * from table where id = '#extQry_[type].id#'
											</cfquery>
											<cfif _res.recordcount>
												<cfsavecontent variable="details2">
													Latest Version : <i>#_res.version#</i><br>
													Birth Date : <i>#dateFormat(_res.created,'mmmm, dd/yyyy')#</i><br>
													Trial : <i>#yesnoformat(_res.trial)#</i>
												</cfsavecontent>
												<cfset extVersions[extType] = _res.older>
												<cfset extVersions['_'&extType] = details2>
												<cfif arrayLen(ArrayFindAllNoCase( extVersions[extType], _res.version ) ) EQ 0 >
													<cfset arrayPrepend(extVersions[extType], _res.version)>
												</cfif>
											</cfif>
										</cfloop>
										<cfset extQry = extQry_[type]>
										<div class="col-ms-12 col-xs-12 well well-sm">
												<span class="head1 title">#extQry.name#</span>
												<hr>
											<div class='col-xs-2 col-md-2'>
												<div>
													<cfif len(extQry.image)>
														<img style="max-width: 100%;" src="data:image/png;base64,#extQry.image#">
													</cfif>
												</div>
											</div>
											<div class='col-md-10 col-xs-10'>
												<div class="container bg-white mb-2" style="margin-left:-1.7%;">
													<div class="head1 textStyle" style="font-size:2rem !important;"> ID: #extQry.id# </div>
													<p class="fontStyle ml-2">#extQry.description#</p>
												</div>
												<cfif !isNull(extQry.older) && isArray(extQry.older) && arrayLen(extQry.older)>
													<div class="row">
														<cfloop list="#types_#" item="_extType">
															<cfif !structKeyExists(extVersions, _extType)>
																<cfcontinue>
															</cfif>
																<cftry><cfset arraySort(extVersions[_extType],"textnocase", "desc")><cfcatch></cfcatch></cftry>
																<div class="mb-0 mt-1 col-xs-4 col-md-4 borderInfo">
																	<div class="bg-primary jumbotron text-white jumboStyle">
																		<span class="btn-primary">
																			<h2 class="fontSize">#multi[_extType]#</h2>
																		</span>
																	</div>
																	<cfset len = 1>
																	<cfloop array="#extVersions[_extType]#" item="_older">
																		<cfif len LTE 5>
																			<div <cfif len MOD 2 eq 0>class="row_alterEven textStyle textWrap"<cfelse>class="row_alterOdd textStyle textWrap"</cfif>>
																				<a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',extQry.trial?"trial":"full"),'{id}',extQry.id)#?version=#_older#">download#extQry.trial?" trial":""# version (#_older#)</a>
																				<span  class="triggerIcon pointer" style="color :##01798A" title="#extVersions['_'&_extType]#">
																					<span class="glyphicon glyphicon-info-sign"></span>
																				</span>
																			</div>
																		<cfelseif len EQ 6>
																			<cfset ext_Version = extQry.id&'_'&_extType>
																			<div style="text-align:center;background-color:##BCBCBC;color:2C3A47;" id="#ext_Version#_id" class="collapse-toggle collapsed textStyle" onclick="return hideToggle('#ext_Version#_id');"  data-toggle="collapse">
																				<b><i>Show more..</i></b>
																				<small class="align-middle h6 mb-0">
																					<i class="icon icon-open"></i>
																				</small>
																			</div>
																			<div  class="clog-detail collapse #ext_Version# row_alter" style="text-align:center;">
																				<div <cfif len MOD 2 eq 0>class="row_alterEven textStyle textWrap"<cfelse>class="row_alterOdd textStyle textWrap"</cfif>>
																					<a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',extQry.trial?"trial":"full"),'{id}',extQry.id)#?version=#_older#">
																						download#extQry.trial?" trial":""# version (#_older#)
																					</a>
																					<span  class="triggerIcon pointer" style="color :##01798A" title="#extVersions['_'&_extType]#">
																						<span class="glyphicon glyphicon-info-sign"></span>
																					</span>
																				</div>
																		<cfelseif len GT 5>
																				<div <cfif len MOD 2 eq 0>class="row_alterEven textStyle textWrap"<cfelse>class="row_alterOdd textStyle textWrap"</cfif>>
																					<a href="#replace(replace(EXTENSION_DOWNLOAD,'{type}',extQry.trial?"trial":"full"),'{id}',extQry.id)#?version=#_older#">
																						download#extQry.trial?" trial":""# version (#_older#)
																					</a>
																					<span  class="triggerIcon pointer" style="color :##01798A" title="#extVersions['_'&_extType]#">
																						<span class="glyphicon glyphicon-info-sign">
																						</span>
																					</span>
																				</div>
																		</cfif>
																		<cfif len GT 5 && len eq arrayLen(extVersions[_extType])>
																			<div class="showLess pointer textStyle" style="text-align:center;background-color:##BCBCBC;" onclick="return hideData('#ext_Version#');">
																				<b><i>Show less</i></b>
																				<small class="align-middle h6 mb-0  hideClick">
																					<i class="icon icon-collapse"></i>
																				</small>
																			</div>
																			</div>
																		</cfif>
																		<cfset len++>
																	</cfloop>
																</div>
														</cfloop>
													</div>
												</cfif>
											</div>
										</div>
									</div>
								</cfloop>
							</cfloop>
						</div>
					</div>
				</cfif>
			</cfif>
		<cfhtmlbody action="flush">
	</body>
</html>
</cfoutput>