
<cfoutput>
<cfscript>
	param name="request.changelogs" default="false";
if(isNull(url.type)) url.type="releases";
doS3={
	express:true
	,jar:true
	,lco:true
	,light:true
	,war:true
};

listURL="https://release.lucee.org/rest/update/provider/list/";


extcacheLiveSpanInMinutes=1000;

EXTENSION_PROVIDER="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=all";
EXTENSION_PROVIDER_REL="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=release&flush=1";
EXTENSION_PROVIDER_ABC="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=abc&flush=1";
EXTENSION_PROVIDER_SNAPSHOT="http://extension.lucee.org/rest/extension/provider/info?withLogo=true&type=snapshot&flush=1";
EXTENSION_DOWNLOAD="https://extension.lucee.org/rest/extension/provider/{type}/{id}";


function getExtensions(flush=false) localmode=true {
	if(arguments.flush || isNull(application.extInfo)) {
		http url=EXTENSION_PROVIDER&"&flush="&arguments.flush result="http";
		if(isNull(http.status_code) || http.status_code!=200) throw "could not connect to extension provider (#ep#)";
		data=deSerializeJson(http.fileContent,false);
		application.extInfo = data.extensions;
	}
	return application.extInfo;
}

function extractVersions(qry, type) localmode=true {
	// first we get the current version
	var data=structNew("linked");
	if(variables.is(arguments.type,arguments.qry.version)) {
		data[arguments.qry.version]={'filename':arguments.qry.fileName,'date':arguments.qry.created};
	}

	// now all the older
	var _older=arguments.qry.older;
	var _olderName=arguments.qry.olderName;
	var _olderDate=arguments.qry.olderDate;
	loop array=_older index="local.i" item="local.version" {
		if (variables.is(arguments.type,version)) {
			data[version]={'filename':_olderName[i],'date':_olderDate[i]};
		}
	}
	return data;
}
function is(type, val) {
	if (arguments.type=="all" || arguments.type=="") 
		return true;
	if (arguments.type=="snapshot") 
		return findNoCase('-SNAPSHOT', arguments.val);
	else if (arguments.type=="abc") {
		if(findNoCase('-ALPHA', arguments.val) 
			|| findNoCase('-BETA', arguments.val)
			|| findNoCase('-RC', arguments.val)
		) 
			return true;
		return false;
	}
	else if(arguments.type=="release") 
		return !findNoCase('-', arguments.val);
}

function getVersions(flush) {
	if(!structKeyExists(application,"extVer") || arguments.flush) {
		http url=listURL&"?extended=true"&(arguments.flush?"&flush=true":"") result="local.res";
		application.extVer= deserializeJson(res.fileContent);
	}
	return application.extVer;
}
function getDate(version,flush=false) {
	if(arguments.flush || isNull(application.mavenDates[arguments.version])) {
		local.res="";
		try{
			http url="https://release.lucee.org/rest/update/provider/getdate/"&arguments.version result="local.res";
			var res= trim(deserializeJson(res.fileContent));
			application.mavenDates[version]= lsDateFormat(parseDateTime(res));
		}
		catch(e) {}
		if(len(res)==0) return "";
		
	}
	return application.mavenDates[arguments.version]?:"";
}

function getInfo(version,flush=false) {
	if(arguments.flush || isNull(application.mavenInfo[version])) {
		local.res="";
		try{
			http url="https://release.lucee.org/rest/update/provider/info/"&version result="local.res";
			var res= deserializeJson(res.fileContent);
			application.mavenInfo[version]= res;
		}
		catch(e) {}
		if(len(res)==0) return "";
		
	}
	return application.mavenInfo[version]?:"";
}

function getChangelog(versionFrom,versionTo,flush=false) {
	var id=arguments.versionFrom&"-"&arguments.versionTo;
	if (arguments.flush || isNull(application.mavenChangeLog[id])) {
		local.res="";
		//try{
			http url="https://release.lucee.org/rest/update/provider/changelog/"&arguments.versionFrom&"/"&arguments.versionTo result="local.res";
			var res= deserializeJson(res.fileContent);
			application.mavenChangeLog[id]= res;
		//}catch(e) {}
		if(len(res)==0) return "";
		
	}
	return application.mavenChangeLog[id]?:"";
}


baseURL="https://release.lucee.org/rest/update/provider/";


jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
lang.desc={
	abc:"Beta and Release Candidates are a preview for upcoming versions and not ready for production environments."
	,beta:"Beta are a preview for upcoming versions and not ready for production environments."
	,rc:"Release Candidates are candidates to get ready for production environments."
	,releases:"Releases are ready for production environments."
	,snapshots:"Snapshots are generated automatically with every push to the repository. 
	Snapshots can be unstable are NOT recommended for production environments."
};

lang.express="The Express version is an easy to setup version which does not need to be installed. Just extract the zip file onto your computer and without further installation you can start by executing the corresponding start file. This is especially useful if you would like to get to know Lucee or want to test your applications under Lucee. It is also useful for use as a development environment.";
lang.war='Java Servlet engine Web ARchive';
lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
lang.jar='Lucee jar file without dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath). If dependecy bundles are not in place Lucee will download them.';
lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';

lang.lib="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).";
lang.libNew="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary. You can have this Jar in 2 flavors, a version containing all Core Extension (like Hibernate, Lucene or Axis) and a version with no Extension bundled.";

lang.installer.win="Windows";
lang.installer.lin64="Linux (64b)";
lang.installer.lin32="Linux (32b)";



	cdnURL="https://cdn.lucee.org/";
	cdnURLExt="https://ext.lucee.org/";
	MAX=1000;

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

	noVersion="There are currently no downloads available in this category.";

	versions=getVersions(structKeyExists(url,"reset"));
	
	keys=structKeyArray(versions);
	tmp=structNew('linked');
	for(i=arrayLen(keys);i>0;i--) {
		k=keys[i];
		tmp[k]=versions[k];
	}
	versions=tmp;


	// add types
	//releases,snapshots,rc,beta
	loop struct=versions index="vs" item="data" {
		if(findNoCase("-snapshot",data.version)) data['type']="snapshots";
		else if(findNoCase("-rc",data.version)) data['type']="rc";
		else if(findNoCase("-beta",data.version)) data['type']="beta";
		else if(findNoCase("-alpha",data.version)) data['type']="alpha";
		else  data['type']="releases";

		data['versionNoAppendix']=data.version;
	}


	//dump(versions);abort;

</cfscript>

<cfhtmlhead>
	<script crossorigin="anonymous" integrity="sha384-KJ3o2DKtIkvYIK3UENzmM7KCkRr/rE9/Qpg6aAZGJwFDMVNA/GpGFF93hXpG5KkN" src="https://code.jquery.com/jquery-3.2.1.slim.min.js"></script>
	<link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/css/bootstrap.min.css" integrity="sha384-BVYiiSIFeK1dGmJRAkycuHAHRg32OmUcww7on3RYdg4Va+PmSTsz/K68vbdEjh4u" crossorigin="anonymous">
	<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.7/js/bootstrap.min.js" integrity="sha384-Tc5IQib027qvyjSMfHjOMaLkfuWVxZxUPnCJA7l2mCWNIpG9mGCD8wGNIcPD7Txa" crossorigin="anonymous"></script>
	<link href="../res/download.css" rel="stylesheet">
</cfhtmlhead>
<cfhtmlbody>
<script src="../res/download.js"></script>
</cfhtmlbody>
<style rel="stylesheet">
.data-content{ background-color: ##01798a; color: white; min-width: 100%; font-size: 14px; line-height: 15px;}

.triggerIcon{color :##01798A !important;}
.pointer {cursor: pointer;}
.jumboStyle {padding: 0rem 0rem !important; border-radius : 0px !important; text-align: center !important;}
.fontSize{font-size: 20px !important;}

.BoxWidth { padding: 1rem 1rem 2rem 1rem; border-radius: 1%; padding-left: 6%;}
.col-md-3{ padding-right: 8px !important; padding-left: 8px !important; }
.desc{ padding: 8px; vertical-align: top; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji","Segoe UI Symbol"; font-size: 1.5rem; font-weight: 400; line-height: 1.5; color: ##212529; text-align: left;}
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
.bugLink {
	padding-right: 20px;
}
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
		<cfif request.changelogs>
			<title>Lucee Changelogs - #Ucase(url.type)#</title>
		<cfelse>
			<title>Download Lucee</title>
		</cfif>

		<link rel="shortcut icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="72x72" href="/res/images/logo.png">
		<link rel="apple-touch-icon" sizes="114x114" href="/res/images/logo.png">
		<cfhtmlhead action="flush">
	</head>
	<body class="container py-3">
		<cfif request.changelogs>
			<div class="bg-primary jumbotron text-white">
				<h1 class="display-3">Lucee Changelogs - #ucase(type)#</h1>
			</div>
			<div class="btn-group" role="group">
			<cfloop list="releases,snapshots,rc,beta" item="_type">
				<a href="?type=#_type#" class="btn  btn-lg <cfif url.type eq _type>btn-primary<cfelse>btn-default</cfif>" href="?type=#type#">					
					#ucase(_type)#
				</a>
			</cfloop>
			</div>		
			<br><br>
			<cfscript>
				_versions={};
				rows = [:];
			</cfscript>
			<cfloop list="releases,snapshots,rc,beta" item="_type">			
				<cfscript>	
					if (url.type neq _type)
						continue;
					_versions[_type] = [];
					rows[_type] = [:];				

					//dump (var=versions, top=1);
					loop struct="#versions#" index="vs" item="data"{						
						if (data.type == _type){
							StructAppend(data, {"vs":vs});
							ArrayAppend(_versions[_type], data);
						}
					}
					prevVersion = "0.0.0.0";
				</cfscript>

				<cfloop array="#_versions[_type]#" item="vv" index="i">
					<cfscript>
						changelog = false;						
						if (i neq ArrayLen(_versions[_type]))
							prevVersion = _versions[_type][i+1].version;
							
						changelog=getChangelog(prevVersion, vv.version);
						if(isStruct(changelog))
							structDelete(changelog,prevVersion);
						//changelog=false;	
					</cfscript>

					<cfif isstruct(changelog) && structCount(changelog) GT 0>
						<h4 id="#vv.version#"><a href="index.cfm?#_type#=#vv.vs###Core">Lucee #vv.version#</a></h4>
						<div class="changelogs desc">
							<cfloop struct="#changelog#" index="ver" item="tickets">
								<cfloop struct="#tickets#" index="id" item="subject">
									<a class="bugLink" href="http://bugs.lucee.org/browse/#id#" target="blank">#id#</a> #htmleditFormat(subject)#
									<br>
								</cfloop>
							</cfloop>
							<br>
						</div>
					</cfif>
					<cfflush>
				</cfloop>
			</cfloop>
			<cfabort>
		<cfelse>
		
		<!--- output --->
			<div class="bg-primary jumbotron text-white">
				<h1 class="display-3">Downloads</h1>
				<p>Lucee core and extension downloads.</p>
			</div>

			<cfif type EQ "releases" or type EQ "snapshots" or type EQ "abc" or type EQ "beta" or type EQ "rc">
				
				<cfif true>
					
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
							<cfset _versions={}>
							<cfloop list="releases,snapshots,rc,beta" item="_type">
								<cfset _versions[_type]=[]>
								<div class="col-md-3 col-sm-3 col-xs-3">
									<!--- dropDown --->
									<div class="bg-primary BoxWidth text-white">
										<cfif !structKeyEXists(url,_type)>
											<cfloop struct="#versions#" index="vs" item="data"><cfif data.type==_type><cfset url[_type]=vs><cfset rows[_type]=vs><cfbreak></cfif></cfloop>
										</cfif>
										<b><h2>#singular[_type]#</h2> <!--- #ldownloads[type].versionNoAppendix#</b> (#lsDateFormat(ldownloads[type].jarDate)#) --->
										<select onchange="change('#_type#',this, 'core')" style="color:7f8c8d;font-style:normal;" id="lCore" class="form-control" <!--- class="custom-select" --->>
											<cfloop struct="#versions#" index="vs" item="data"><cfif data.type==_type><option <cfif url[_type]==vs><cfset rows[_type]=vs> selected="selected"</cfif> value="#vs#"><!---

												---><cfset arrayAppend(_versions[_type],data.version)>#data.versionNoAppendix#</option></cfif></cfloop>

										</select>										
									</div>
									<cfset dw=versions[rows[_type]]>
									<!--- desc --->
									<div class="desc descDiv row_even">
										<cfset res=getDate(dw.version)>
										<span style="font-weight:600">#dw.version#</span><cfif len(res)>
	
 <span style="font-size:12px">(#res#)</span></cfif><br><br>

									 #lang.desc[_type]#</div>
									
									<!--- Express --->
									<cfif structKeyExists(dw,"express")><div class="row_odd divHeight">
										<cfif doS3.express>
											<cfset uri="#cdnURL##dw.express#">
										<cfelse>
											<cfset uri="#baseURL#express/#dw.version#">
										</cfif>
										<div class="fontStyle">
											<a href="#uri#">Express</a>
											<span  class="triggerIcon pointer" style="color :##01798A" title="#lang.express#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</div>
									</div></cfif>
									<!--- Installer --->
									<div class="row_even installerDiv">
										<cfif _type == "releases">
											
											<cfif !structKeyExists(dw,"win") and !structKeyExists(dw,"lin32") and !structKeyExists(dw,"lin64")>
												<cfif left(dw.version,1) GT 4>
													<div class="fontStyle">
													<span class="text-primary">Coming Soon!</span>
													<span  class="triggerIcon pointer" style="color :##01798A" title="Installers will available on soon">
														<span class="glyphicon glyphicon-info-sign"></span>
													</span>
												</div></cfif>
											<cfelse>
												<cfset count=1>
												<cfset str="">
												<cfloop list="win,lin64,lin32" item="kk">
													<cfif !structKeyExists(dw,kk)><cfcontinue></cfif>
													<cfset uri="#cdnURL##dw[kk]#">
													<cfif count GT 1>
														<cfset str&='<br>'>
													</cfif>
													<cfset str&='<a href="#uri#">#lang.installer[kk]# Installer</a> <span  class="triggerIcon pointer" style="color :##01798A" title="#lang.installer[kk]# Installer">
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
											<cfif structKeyExists(dw,"jar")>
											<cfif doS3.jar>
												<cfset uri="#cdnURL##dw.jar#">
											<cfelse>
												<cfset uri="#baseURL#loader/#dw.version#">
											</cfif>
										
											<div class="fontStyle"><a href="#(uri)#">lucee.jar</a><span  class="triggerIcon pointer" style="color :##01798A" title="#lang.jar#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div></cfif>
											<cfif structKeyExists(dw,"light")>
											<cfif doS3.light>
												<cfset uri="#cdnURL##dw.light#">
											<cfelse>
												<cfset uri="#baseURL#light/#dw.version#">
											</cfif>
											
											<div class="fontStyle"><a href="#(uri)#">lucee.jar(without Extension)</a><span  class="triggerIcon pointer" style="color :##01798A" title="Lucee Jar file without Extension bundled">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div></cfif>

									</div>
									<!--- core --->
									<cfif structKeyExists(dw,"lco")><div class="row_even divHeight">
										<cfif doS3.lco>
											<cfset uri="#cdnURL##dw.lco#">
										<cfelse>
											<cfset uri="#baseURL#core/#dw.version#">
										</cfif>
											
										<div class="fontStyle"><a href="#(uri)#" >Core</a><span class="triggerIcon pointer" style="color :##01798A" title='#lang.core#'>
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>
									</div></cfif>
									<!--- WAR --->
									<cfif structKeyExists(dw,"war")><div class="row_odd divHeight">
										<cfif doS3.war>
											<cfset uri="#cdnURL##dw.war#">
										<cfelse>
											<cfset uri="#baseURL#war/#dw.version#">
										</cfif>
										
										<div class="fontStyle"><a href="#(uri)#" title="#lang.war#">WAR</a><span class="triggerIcon pointer" style="color :##01798A" title="#lang.war#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></div>
									</div></cfif>
									<!--- logs --->
									<div class="row_even divHeight">
											<cfscript>
											loop array=_versions[_type] item="vv" index="i"{
												if(vv==dw.version ) {
													prevVersion=arrayIndexExists(_versions[_type],i+1)?_versions[_type][i+1]:"0.0.0.0";
												}
											}
											changelog=getChangelog(prevVersion,dw.version);
											if(isStruct(changelog))structDelete(changelog,prevVersion);
											//dump(prevVersion);
											//dump(dw.version);
											//dump(changelog);
											
											</cfscript>											

										<cfif isstruct(changelog) && structCount(changelog) GT 0>
											<div class="fontStyle">
												<a href="changelogs.cfm?type=#_type####dw.version#">Changelogs</a>
											</div>											
										<cfelse>
											<div class="fontStyle">
												<a href="changelogs.cfm?type=#_type#">Changelogs</a>
											</div>
										</cfif>
									</div>
									<div><hr></div><!--- --->
								</div>
							</cfloop>
						</div>
					</div>
<cfscript>
	
	extQry=getExtensions(structKeyExists(url,"reset"));
</cfscript>
<div id="ext">
	<h2>Extensions</h2>
						
	<p style="font-size: 1.7rem;font-weight:normal;">Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.
	You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>

	<cfloop query=extQry>
	<div class="container">
		<div class="col-ms-12 col-xs-12 well well-sm">
			<!--- title --->
			<span class="head1 title">#extQry.name#</span>
			<hr>
			<!--- image --->
			<div class='col-xs-2 col-md-2'>
				<div>
				<cfif len(extQry.image)>
					<img style="max-width: 100%;" src="data:image/png;base64,#extQry.image#">
				</cfif>
				</div>
			</div>
			<!--- description --->
			<div class='col-md-10 col-xs-10'>
				<div class="container bg-white mb-2" style="margin-left:-1.7%;">
					<div class="head1 textStyle" style="font-size:2rem !important;"> 
						ID: #extQry.id# 
						<p class="fontStyle ml-2">#extQry.description#</p>
					</div>
				
			<!--- downloads --->
			<div class="row">
			<cfloop list="release,abc,snapshot" item="type">
				<cfset exts=extractVersions(extQry,type)>
				<cfif structCount(exts)>
				<div class="mb-0 mt-1 col-xs-4 col-md-4 borderInfo">
					<div class="bg-primary jumbotron text-white jumboStyle">
						<span class="btn-primary">
							<h2 class="fontSize">#multi[type]#</h2>
						</span>
					</div>
					<cfset ind=0>
					<cfset uid="">
					<cfset cnt=structCount(exts)>
					<cfloop struct="#exts#" index="ver" item="el">
					<cfset ind++>

					<!--- show more --->
					<cfif ind EQ 5 and cnt GT 6>
						<cfset uid=createUniqueId()>
						<div style="text-align:center;background-color:##BCBCBC;color:2C3A47;" id="#uid#_release_id" class="collapse-toggle collapsed textStyle" onclick="return hideToggle('#uid#_release_id');"  data-toggle="collapse">
						<b><i>Show more..</i></b>
						<small class="align-middle h6 mb-0">
							<i class="icon icon-open"></i>
						</small>
						</div>
						<div  class="clog-detail collapse #uid#_release row_alter" style="text-align:center;">
					</cfif>


					<div <cfif ind MOD 2 eq 0>class="row_alterEven textStyle textWrap"<cfelse>class="row_alterOdd textStyle textWrap"</cfif>>
						
						<a href="#cdnURLExt##el.filename#">#ver# (#lsDateFormat(el.date)#)</a>
						<!--- <span  class="triggerIcon pointer" 
						style="color :##01798A" title="">
						<span class="glyphicon glyphicon-info-sign"></span>
						</span>--->

					</div>

					<!--- show less --->
					<cfif cnt EQ ind and len(uid)>
						<div class="showLess pointer textStyle" 
						style="text-align:center;background-color:##BCBCBC;" onclick="return hideData('#uid#_release');">
							<b><i>Show less</i></b>
							<small class="align-middle h6 mb-0  hideClick">
								<i class="icon icon-collapse"></i>
							</small>
						</div>
					</div>
					</cfif>
					</cfloop>





				</div>
				</cfif>
			</cfloop>
			</div>


		</div>
	</div>
	</div>
	</div>	
	</cfloop>
</div>


				</cfif>
			</cfif>
		</cfif>
		<cfhtmlbody action="flush">
	</body>
</html>
</cfoutput>
