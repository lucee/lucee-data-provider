/*
	Express templates are subset of the normal lucee installers, just the tomcat part
	built using https://github.com/lucee/lucee-installer/actions/workflows/express-template.yml

	see https://luceeserver.atlassian.net/browse/LDEV-5367
*/
component {

	public struct function getExpressTemplates( s3Root ) cachedWithin="request" {
		lock name="build-getExpressTemplates" timeout="10" {
			return _getExpressTemplates( s3Root );
		}
	}

	private struct function _getExpressTemplates( s3Root ){
		var expressSrc = s3Root & "express-templates/";
		var expressLocal = getDirectoryFromPath( getCurrentTemplatePath() ) & "build/servers/";
		var s3_templates = directoryList( path=expressSrc, listInfo="query" );
		var local_templates = directoryList( path=expressLocal, listInfo="query" );
		// figure out the latest templates for Tomcat 9 and 10
		var express_templates = {};
		var express_versions = "lucee-tomcat-9.0.,lucee-tomcat-10.1.,lucee-tomcat-11.0.";
		var versions = [];
		// https://cdn.lucee.org/express-templates/lucee-tomcat-9.0.100-template.zip
		// https://cdn.lucee.org/express-templates/lucee-tomcat-10.1.36-template.zip
		loop list="#express_versions#" item="local.tomcat_major" {
			versions = [];
			loop query="#s3_templates#" {
				if ( s3_templates.name contains tomcat_major
						&& listLen( s3_templates.name, "-" ) eq 4
						&& listLen( s3_templates.name, ".") eq 4
						&& listLast( s3_templates.name, "." ) eq "zip" ){
					arrayAppend( versions, ListLast( ListGetAt( s3_templates.name, 3, "-" ), "." ) );
				}
			}
			if ( arrayLen( versions ) eq 0 ){
				systemOutput("express templates dir was empty? [#expressSrc#]", true);
				throw "getExpressTemplates() No express templates found for: [#tomcat_major#]";
			}
			ArraySort( versions, "numeric", "desc" );
			// tomcat-9 = lucee-tomcat-9.0.100-template.zip
			express_templates[ ListFirst( listRest( tomcat_major, "-" ), "." ) ]
				= "#tomcat_major##versions[ 1 ]#-template.zip" ;
		}

		var st_s3 = QueryToStruct(s3_templates, "name" );
		var st_local = QueryToStruct(local_templates, "name" );

		//systemOutput( express_templates, true );

		loop collection="#express_templates#" key="local.major" value="local.name"{
			if ( !structKeyExists(st_local, name ) ){
				systemOutput( "getExpressTemplates() New Express Template [#name#]", true);
				_fetchExpressTemplateFromS3( name, expressSrc, expressLocal );
			} else if ( st_s3[ name ].size != st_local[ name ].size ) {
				systemOutput( "getExpressTemplates() Express Templates updated on remote [#name#]", true);
				_fetchExpressTemplateFromS3( name, expressSrc, expressLocal );
			}
		}

		if ( structCount( express_templates ) neq listLen( express_versions ) )
			throw "Expected #listLen(express_versions)# express templates: [#express_templates.toJson()#], i.e. [#express_versions#]";
		return express_templates;
	}

	private function _fetchExpressTemplateFromS3( name, src, dest ){
		if ( !directoryExists( dest ) )
			directoryCreate( dest );
		var _dest = getTempDirectory( true ) & name;
		var _src = src & name;
		fileCopy( _src, _dest );
		if ( isZipFile( _dest ) ){
			fileCopy( _dest, dest & name);
			fileDelete( _dest );
			return true;
		} else {
			fileDelete( _dest );
		}
		throw "getExpressTemplates() [#_dest#] isn't a valid zip file, src [#_src#], args [#arguments.toJson()#]";
	}

}