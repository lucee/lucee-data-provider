<cfscript>
	download=CreateObject("component", "download");
	if(isNull(url.type)) 
		url.type="releases";
	else if(url.type != "releases" || url.type != "snapshots" || url.type != "rc" || url.type != "beta" || url.type != "abc") 
		url.type="releases";
	doS3={
		express:true
		,jar:true
		,lco:true
		,light:true
		,zero:true
		,war:true
	};
	dockerURL="https://docs.lucee.org/recipes/docker.html";
	baseURL="https://release.lucee.org/rest/update/provider/";

	jarInfo='(Java ARchive, read more about <a target="_blank" href="https://en.wikipedia.org/wiki/JAR_(file_format)">here</a>)';
	lang = {};
	lang.desc={
		abc:"Beta versions and Release Candidates offer a glimpse into upcoming releases but are not designed for production environments."
		,beta:"Beta versions preview upcoming releases but are not suitable for production environments."
		,rc:"Release Candidates are poised for production readiness."
		,releases:"Releases are production-ready."
		,snapshots:"Snapshots are auto-generated with each repository update. They may be unstable and are NOT suited for production use."
	};

	lang.express="The Express version offers a straightforward setup without installation requirements. Simply unzip the file on your computer and start using it by running the start file. Ideal for those new to Lucee, testing applications, or as a development environment.";
	lang.war="A WAR file, or Web ARchive, packages web applications for deployment on Java Servlet engines.";
	lang.docker="A Docker image packages Lucee and all its dependencies, enabling quick and consistent deployment in any environment using Docker containers.";

	lang.core='The Lucee Core file, you can simply copy this to the "patches" folder of your existing Lucee installation.';
	lang.jar='The Lucee jar #jarInfo#, simply copy that file to the lib (classpath) folder of your servlet engine.';
	lang.dependencies='Dependencies (3 party bundles) Lucee needs for this release, simply copy this to "/lucee-server/bundles" of your installation (If this files are not present Lucee will download them).';
	lang.jar='Lucee jar file without dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath). If dependency bundles are not in place Lucee will download them.';
	lang.luceeAll='Lucee jar file that contains all dependencies Lucee needs to run. Simply copy this file to your servlet engine lib folder (classpath)';

	lang.lib="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes in 2 favors, the ""lucee.jar"" that only contains Lucee itself and no dependecies (Lucee will download dependencies if necessary) or the lucee-all.jar with all dependencies Lucee needs bundled (not availble for versions before 5.0.0.112).";
	lang.libNew="The Lucee Jar file, you can simply copy to your existing installation to update to Lucee 5. This file comes with all necessary dependencies Lucee needs build in, so no addional jars necessary. You can have this Jar in 2 flavors, a version containing all Core Extension (like Hibernate, Lucene or Axis) and a version with no Extension bundled.";

	lang.installer.win64="Windows";
	lang.installer['linux-x64']="Linux (x64)";
	lang.installer['linux-aarch64']="Linux (aarch64)";

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
	versions = download.getVersions( structKeyExists( url, "reset" ) );
	if ( structKeyExists( url, "reset" ) ){
		download.reset();
	}
	keys=structKeyArray(versions);
	tmp=structNew('linked');
	for(i=arrayLen(keys);i>0;i--) {
		k=keys[i];
		//if(left(k,6)=="06.001" && right(k,4)==".000") continue; // .000=SNAPSHOT
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
		else data['type']="releases";
		data['versionNoAppendix']=data.version;
	}

	// latest
	edgeMajor="7";
	stableMajor="6"
	ltsMajor="5";
	latest={"edge":{},"lts":{},stable:{}};
	alias = {};
	alias[ltsMajor]="lts";
	alias[edgeMajor]="edge";
	alias[stableMajor]="stable";
	loop struct=variables.VERSIONS index="key" item="val" {
		l=int(listFirst(key,'.'));
		if (!structKeyExists(alias, l)) continue;
		mv=alias[l];

		if (!structKeyExists(latest[mv], val.type) || key>latest[mv][val.type].versionSorted) {
			latest[mv][val.type]=val;
			latest[mv][val.type].versionSorted=key;
		}
	}
</cfscript>
<cfoutput>
	<!DOCTYPE html>
	<html>
	<head>
		<title>Download Lucee</title>
		<cfinclude template="_header.cfm">
	</head>
	<body class="container py-3">
		<!--- output --->
		<div class="bg-primary jumbotron text-white">
			<cfinclude template="_linkbar.cfm">
			<h1 class="display-3">Lucee Downloads</h1>
			<p>Lucee Server and Extensions</p>
		</div>

				<cfif type EQ "releases" or type EQ "snapshots" or type EQ "abc" or type EQ "beta" or type EQ "rc">

				   <cfif true>


					  <cfset subjects={
						 releases:"Release",
						 rc:"Release Candidate",
						 beta:"Beta",
						 snapshots:"Snapshot"
					  }>
					  <cfset mainsubjects={
						 edge:"Bleeding Edge",
						 stable: "Stable",
						 lts:"LTS (Long Term Support)"
					  }>

					  <table  border=0 cellpadding="25" cellspacing="5" width="100%">
						 <tr>
							<cfset lists={stable="releases,rc,beta,snapshots",edge:"rc,beta,snapshots",lts:"releases,rc,snapshots"}>
							<cfloop list="stable,edge,lts" item="mainType">
							<td valign="top"><div class="panel-body">
								<div class="bg-primary BoxWidth text-white"><h2>#mainsubjects[mainType]#</h2></div>
								<div class="desc descDiv row_even">
								<cfset count_shown=0>
								<cfloop list="#lists[mainType]#" item="type">
									<cfif len( latest[maintype][type] ?: {} ) eq 0>
										<cfcontinue>
									</cfif>
									<div class="panel-body">
									<cfset dw=latest[maintype][type]>
									<cfset dateFormatted=download.getReleaseDate(dw.version)>
									<h2>#subjects[type]# #dw.version#<cfif len(dateFormatted)> (#dateFormatted#)</cfif></h2>
									<p>#lang.desc[type]#</p>
								<ul>
									<!--- Express --->
									<div class="fontStyle">
									<cfif structKeyExists(dw,"express")>
										<cfif doS3.express>
											<cfset uri="#cdnURL##dw.express#">
										<cfelse>
											<cfset uri="#baseURL#express/#dw.version#">
										</cfif>
										<li><a href="#uri#">Express</a>
											<span  class="triggerIcon pointer" style="color :##01798A" title="#lang.express#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</li>
									</cfif>

									<!--- Installer --->
									<cfset str="">
									<cfloop list="win64,linux-x64,linux-aarch64" item="kk">
										<cfif !structKeyExists(dw,kk)><cfcontinue></cfif>
										<cfset uri="#cdnURL##dw[kk]#">
										<cfset str&='<li><a href="#uri#">#lang.installer[kk]# Installer</a> <span  class="triggerIcon pointer" style="color :##01798A" title="#lang.installer[kk]# Installer">
										<span class="glyphicon glyphicon-info-sign"></span>
									</span></li>'>
									</cfloop>
									#str#

									<!--- jar --->
									<cfif structKeyExists(dw,"jar")>
										<cfif doS3.jar>
											<cfset uri="#cdnURL##dw.jar#">
										<cfelse>
											<cfset uri="#baseURL#loader/#dw.version#">
										</cfif>

										<li><a href="#(uri)#">lucee.jar</a>
											<span  class="triggerIcon pointer" style="color :##01798A" title="#lang.jar#">
												<span class="glyphicon glyphicon-info-sign"></span></li>
											</span>
									</cfif>
									<cfif structKeyExists(dw,"light")>
										<cfif doS3.light>
											<cfset uri="#cdnURL##dw.light#">
										<cfelse>
											<cfset uri="#baseURL#light/#dw.version#">
										</cfif>

										<li><a href="#(uri)#">lucee-light.jar</a><span  class="triggerIcon pointer" style="color :##01798A" title='Lucee Jar file without any Extensions bundled, "Lucee light"'>
										   <span class="glyphicon glyphicon-info-sign"></span>
										</span></li>
									 </cfif>
									 <cfif structKeyExists(dw,"zero")>
										<cfif doS3.zero>
										   <cfset uri="#cdnURL##dw.zero#">
										<cfelse>
										   <cfset uri="#baseURL#zero/#dw.version#">
										</cfif>

										<li><a href="#(uri)#">lucee-zero.jar</a><span  class="triggerIcon pointer" style="color :##01798A" title='Lucee Jar file without any Extensions bundled or doc and admin bundles, "Lucee zero"'>
										   <span class="glyphicon glyphicon-info-sign"></span>
										</span></li>
									 </cfif>

									 <!--- core --->
									 <cfif structKeyExists(dw,"lco")>
										<cfif doS3.lco>
											<cfset uri="#cdnURL##dw.lco#">
										<cfelse>
											<cfset uri="#baseURL#core/#dw.version#">
										</cfif>

										<li><a href="#(uri)#" >Core</a>
											<span class="triggerIcon pointer" style="color :##01798A" title='#lang.core#'>
												<span class="glyphicon glyphicon-info-sign"></span>
											</span></li>
									 </cfif>
									 <!--- WAR --->
									 <cfif structKeyExists(dw,"war")>
										<cfif doS3.war>
											<cfset uri="#cdnURL##dw.war#">
										<cfelse>
											<cfset uri="#baseURL#war/#dw.version#">
										</cfif>

										<li>
											<a href="#(uri)#" title="#lang.war#">WAR</a>
											<span class="triggerIcon pointer" style="color :##01798A" title="#lang.war#">
												<span class="glyphicon glyphicon-info-sign"></span>
											</span>
										</li>
									 </cfif>
									 <!--- Docker --->
									 <li>
										<!--- Docker --->
										<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#dw.version#">Docker Images</a>
										<span class="triggerIcon pointer" style="color :##01798A" title="#lang.docker#">
											<a href="#dockerURL#"><span class="glyphicon glyphicon-info-sign"></span></a>
										</span>
									</li>
									</ul>
									<cfif count_shown eq 0>
										<a href="/changelog/?version=#left(dw.version,3)#">Version Changelogs</a>
									</cfif>
									<cfset count_shown++>
								</div>
							   </cfloop>
							</div></div></td>
							</cfloop>
						 </tr>
					  </table>

					  <h1 id="history">History</h1>

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
							$(`.${a}`).toggleClass('collapse');
							$('##'+a).show();
						 }
						 function hideToggle (a) {
        					$(`.${a}`).toggleClass('collapse');
							$('##'+a).hide();
							$('.'+a).removeClass('show');
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
										<cfscript>
											if (!structKeyExists(url,_type) || !structKeyExists(versions, url[_type])){ // handle beta=true, ignore
												vs = download.getLatestVersionForType( versions, _type );
												url[_type]=vs;
												rows[_type]=vs;
											}
										</cfscript>
										<b><h2>#singular[_type]#</h2> <!--- #ldownloads[type].versionNoAppendix#</b> (#lsDateFormat(ldownloads[type].jarDate)#) --->
										<select onchange="change('#_type#',this, 'core')" style="color:7f8c8d;font-style:normal;" id="lCore" class="form-control" <!--- class="custom-select" --->>
											<cfloop struct="#versions#" index="vs" item="data">
												<cfif vs=="05.003.007.0044.100"><cfcontinue></cfif><cfif data.type==_type><option <cfif url[_type]==vs><cfset rows[_type]=vs> selected="selected"</cfif> value="#vs#"><cfset arrayAppend(_versions[_type],data.version)>#data.versionNoAppendix#</option></cfif>
											</cfloop>
										</select>
									</div>
									<cfscript>
										if ( !structKeyExists( rows,_type ) ){ 
											// requested version doesn't exist, fallback on latest
											vs = download.getLatestVersionForType( versions, _type );
											url[_type]=vs;
											rows[_type]=vs;
										}
									</cfscript>
								<cfset dw=versions[rows[_type]] ?: {}>
								<!--- desc --->
								<cfif len(dw) eq 0>
									</div>
									<cfcontinue>
								</cfif>
								<div class="desc descDiv row_even">
									<cfset res=download.getReleaseDate(dw.version)>
									<span style="font-weight:600">#dw.version#</span><cfif len(res)>
									<span style="font-size:12px">(#res#)</span></cfif><br><br>
									#lang.desc[_type]#</div>

									<!--- Express --->
									<cfif structKeyExists(dw,"express")>
										<div class="row_odd divHeight">
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
										</div>
									</cfif>
									<!--- Installer --->
									<div class="row_even installerDiv">
										<cfset count=0>
										<cfset str="">
										<cfloop list="win64,linux-x64,linux-aarch64" item="kk">
											<cfif !structKeyExists(dw,kk)><cfcontinue></cfif>
												<cfset count++>
												<cfset uri="#cdnURL##dw[kk]#">
												<cfif count GT 1>
													<cfset str&='<br>'>
												</cfif>
												<cfset str&='<a href="#uri#">#lang.installer[kk]# Installer</a> <span  class="triggerIcon pointer" style="color :##01798A" title="#lang.installer[kk]# Installer">
											<span class="glyphicon glyphicon-info-sign"></span>
										</span>'>
										</cfloop>
										<cfif _type == "releases" && count eq 0>
											<div class="fontStyle">
												<span class="text-primary">Coming Soon!</span>
													<span  class="triggerIcon pointer" style="color :##01798A" title="Installers will available on soon">
														<span class="glyphicon glyphicon-info-sign"></span>
													</span>
											</div>
										<cfelseif count gt 0>
											<div class="fontStyle">#str#</div>
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

											<div class="fontStyle"><a href="#(uri)#">lucee.jar</a>
												<span  class="triggerIcon pointer" style="color :##01798A" title="#lang.jar#">
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</cfif>
										<cfif structKeyExists(dw,"light")>
											<cfif doS3.light>
												<cfset uri="#cdnURL##dw.light#">
											<cfelse>
												<cfset uri="#baseURL#light/#dw.version#">
											</cfif>

											<div class="fontStyle"><a href="#(uri)#">lucee-light.jar</a>
												<span  class="triggerIcon pointer" style="color :##01798A" title='Lucee Jar file without any Extensions bundled, "Lucee light"'>
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</cfif>
										<cfif structKeyExists(dw,"zero")>
											<cfif doS3.zero>
												<cfset uri="#cdnURL##dw.zero#">
											<cfelse>
												<cfset uri="#baseURL#zero/#dw.version#">
											</cfif>

											<div class="fontStyle"><a href="#(uri)#">lucee-zero.jar</a>
												<span  class="triggerIcon pointer" style="color :##01798A" title='Lucee Jar file without any Extensions bundled or doc and admin bundles, "Lucee zero"'>
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</cfif>
									</div>
									<!--- core --->
									<cfif structKeyExists(dw,"lco")>
										<div class="row_even divHeight">
											<cfif doS3.lco>
												<cfset uri="#cdnURL##dw.lco#">
											<cfelse>
												<cfset uri="#baseURL#core/#dw.version#">
											</cfif>
											<div class="fontStyle"><a href="#(uri)#" >Core</a>
												<span class="triggerIcon pointer" style="color :##01798A" title='#lang.core#'>
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</div>
									</cfif>
									<!--- WAR --->
									<cfif structKeyExists(dw,"war")>
										<div class="row_odd divHeight">
											<cfif doS3.war>
												<cfset uri="#cdnURL##dw.war#">
											<cfelse>
												<cfset uri="#baseURL#war/#dw.version#">
											</cfif>

											<div class="fontStyle"><a href="#(uri)#" title="#lang.war#">WAR</a>
												<span class="triggerIcon pointer" style="color :##01798A" title="#lang.war#">
													<span class="glyphicon glyphicon-info-sign"></span>
												</span>
											</div>
										</div>
									</cfif>

									<!--- Docker --->
									<div class="row_even divHeight">
										<div class="fontStyle">
											<a href="https://hub.docker.com/r/lucee/lucee/tags?name=#dw.version#">Docker Images</a>
											<span class="triggerIcon pointer" style="color :##01798A" title="#lang.docker#">
												<a href="#dockerURL#"><span class="glyphicon glyphicon-info-sign"></span></a>
											</span>
										</div>
									</div>

								<!--- logs --->
								<div class="row_odd divHeight">
									<cfscript>
										loop array=_versions[_type] item="vv" index="i"{
											if(vv==dw.version ) {
												prevVersion=arrayIndexExists(_versions[_type],i+1)?_versions[_type][i+1]:"0.0.0.0";
											}
										}
										changelog=download.getChangelog(prevVersion,dw.version);
										if(isStruct(changelog))structDelete(changelog,prevVersion);
										//dump(prevVersion);
										//dump(dw.version);
										//dump(changelog);

										</cfscript>

									 <cfif isstruct(changelog) && structCount(changelog) GT 0>
										<div class="fontStyle">
										   <p class="collapsed mb-0" data-toggle="modal" data-target="##myModal#_type#">Changelog<small class="align-middle h6 mb-0 ml-1"><i class="icon icon-collapse collapsed"></i></small></p>
										</div>
										<div class="modal fade" id="myModal#_type#" role="dialog">
											<div class="modal-dialog modal-lg">
												<div class="modal-content">
													<div class="modal-header">
														<button type="button" class="close" data-dismiss="modal">&times;</button>
														<h4 class="modal-title"><b>Version-#dw.version# Changelogs</b></h4>
													</div>
													<div class="modal-body desc">
														<cfset changelogTicketList = "">
														<cfloop struct="#changelog#" index="ver" item="tickets">
															<cfloop struct="#tickets#" index="id" item="subject">
																<cfif !listFindNoCase(changelogTicketList, id)>
																	<a href="https://bugs.lucee.org/browse/#id#" target="blank">#id#</a>- #subject#
																	<br>
																	<cfset changelogTicketList = listAppend(changelogTicketList, id)>
																</cfif>
															</cfloop>
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
								<div><hr></div><!--- --->
							</div>
						</cfloop>
						</div>
					</div>

	<cfscript>
		extQry=download.getExtensions(structKeyExists(url,"reset"));
	</cfscript>
	<div id="ext">
		<h1>Extensions</h1>

		  <p style="font-size: 1.7rem;font-weight:normal;">Lucee Extensions, simply copy them to /lucee-server/deploy, of a running Lucee installation, to install them.
		  You can also install this Extensions from within your Lucee Administrator under "Extension/Application".</p>

		  <cfloop query=extQry>
			 <cfif extQry.id=="1E12B23C-5B38-4764-8FF41B7FD9428468">
				<cfcontinue>
			 </cfif>
		  <div class="container">
			 <div class="col-ms-12 col-xs-12 well well-sm">
				<!--- title --->
				<div class="permalinkHover"  id="#extQry.id#" >
					<span class="head1 title">#extQry.name# 
						<span data-id="#extQry.id#" class="permalink">
							<span class="glyphicon glyphicon glyphicon-link"></span>
						</span>
					</span>
				</div>
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
					  
					  <cfif structKeyExists(application.extensionMeta, extQry.id)>
						<div class="head1 textStyle" style="font-size:1.5rem;">
							<cfset extMeta = application.extensionMeta[extQry.id]>
							<cfif structKeyExists(extMeta, "docs")>
								<span class="glyphicon glyphicon-info-sign"></span>
								<a href="#extMeta.docs#">Documentation</a>&nbsp;
							</cfif>
							<cfif structKeyExists(extMeta, "src")>
								<span class="glyphicon glyphicon-info-sign"></span>
								<a href="#extMeta.src#">Source</a>&nbsp;
							</cfif>
							<cfif structKeyExists(extMeta, "labels")>
								<span class="glyphicon glyphicon-info-sign"></span>
								<a href="https://luceeserver.atlassian.net/issues/?jql=labels%20%3D%20%22#extMeta.labels#%22">Issues</a>
							</cfif>
						 </div>
					  </cfif>
				<!--- downloads --->
				<div class="row">
				<!--- call extractVersions function once per extension rather than three times --->
				<cfset exts=download.extractVersions(extQry)>
				<cfloop list="release,abc,snapshot" item="type">
					<cfif structCount(exts[type])>
						<div class="mb-0 mt-1 col-xs-4 col-md-4 borderInfo">
							<div class="bg-primary jumbotron text-white jumboStyle">
								<span class="btn-primary">
									<h2 class="fontSize">#multi[type]#</h2>
								</span>
							</div>
							<cfset ind=0>
							<cfset uid="">
							<cfset cnt=structCount(exts[type])>
							<cfloop struct="#exts[type]#" index="ver" item="el">
								<cfset ind++>
								<!--- show more --->
								<cfif ind EQ 5 and cnt GT 6>
									<cfset uid=createUniqueId()>
									<div style="text-align:center;background-color:##BCBCBC;color:2C3A47;" id="#uid#_release_id" class="collapse-toggle collapsed textStyle" onclick="return hideToggle('#uid#_release_id');"  data-toggle="toggle">
										<b><i>Show more..</i></b>
										<small class="align-middle h6 mb-0">
											<i class="icon icon-open"></i>
										</small>
										</div>
										<div  class="clog-detail collapse #uid#_release_id row_alter" style="text-align:center;">
								</cfif>
								<div <cfif ind MOD 2 eq 0>class="row_alterEven textStyle textWrap"<cfelse>class="row_alterOdd textStyle textWrap"</cfif>>
									<a href="#cdnURLExt##el.filename#"
										<cfif !isEmpty(el.meta.mincoreversion)>
											title="Requires Lucee #encodeForHTMLAttribute(el.meta.mincoreversion)#" 
										</cfif>
										>#ver# (#lsDateFormat(el.date)#)</a>
									<!--- <span  class="triggerIcon pointer"
									style="color :##01798A" title="">
									<span class="glyphicon glyphicon-info-sign"></span>
									</span>--->
								</div>
								<!--- show less --->
								<cfif cnt EQ ind and len(uid)>
									<div class="showLess pointer textStyle"
											style="text-align:center;background-color:##BCBCBC;" 
											onclick="return hideData('#uid#_release_id');">
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
			 <cfhtmlbody action="flush">
			 <script>
				$('.permalink').each(function() {
				   var anchor = document.createElement('a')
				   anchor.href = '##' + $(this).attr('data-id')
				   $(this).wrapInner(anchor)
				});
				$('span.permalink').hide();
				$('div.permalinkHover').hover(
				   function() { $(this).find('span.permalink').show(); },
				   function() { $(this).find('span.permalink').hide(); }
				);
			 </script>

	   <p style="font-size: 1.6rem;">Lucee Release Announcements, including changelogs are available via <a href="https://dev.lucee.org/c/news/release/8">Releases Category</a></p>
	   <p style="font-size: 1.6rem;">Extension updates and changelogs are posted under the <a href="https://dev.lucee.org/c/hacking/extensions/5">Extensions Category</a></p>
	   <p style="font-size: 1.6rem;">Official Lucee Docker images are available via <a href="https://hub.docker.com/r/lucee/lucee">Docker Hub</a></p>
	   <p style="font-size: 1.6rem;">Commandbox Lucee engines/releases are listed at <a href="https://www.forgebox.io/view/lucee">Forgebox</a></p>
	<script>
		function copyToClipboard(elementId, button) {
			const el = document.createElement('textarea');
			el.value = document.getElementById(elementId).innerText;
			document.body.appendChild(el);
			el.select();
			document.execCommand('copy');
			document.body.removeChild(el);
			const originalText = button.innerText;
			button.innerText = 'copied';
			setTimeout(() => {
				button.innerText = originalText;
			}, 5000);
		}
	</script>
	</body>
	</html>
</cfoutput>
