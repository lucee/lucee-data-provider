
component hint="luceeVersionsListS3 but with a local directory, for local development" {

	function listVersions( dir ){
		var qry=directoryList( path=arguments.dir, recurse= true, listInfo="query", filter=function (path){
			var ext=listLast(path,'.');
			var name=listLast(path,'\/');

			if(ext=='lco') return true;
			if(ext=='war' && left(name,6)=='lucee-') return true;
			if(ext=='exe' && left(name,6)=='lucee-') return true; // lucee-4.5.3.020-pl0-windows-installer.exe
			if(ext=='run' && left(name,6)=='lucee-') return true; // lucee-4.5.3.020-pl0-windows-installer.exe
			if(ext=='jar' && left(name,6)=='lucee-') return true;
			if(ext=='zip' && (left(name,6)=='lucee-' || left(name,9)=='forgebox-')) return true;
			/*
			if(ext=='jar' && left(name,6)=='lucee-' || left(name,12)!='lucee-light-') {
				return true;
			}*/
			// systemOutput(" skipped file:" & path, true);
			return false;
		});

		var data=structNew("linked");

		// maven files have a different format, type is the suffix, was the prefix before

		var patterns=structNew('linked');
		patterns['express'] = { suffix: 'express', ext: "zip" };
		patterns['light']   = { suffix: 'light', ext: "jar" };
		patterns['zero']    = { suffix: 'zero', ext: "jar" };
		patterns['forgebox-light']     = { suffix: 'forgebox-light', ext: "zip" };
		patterns['forgebox']      = { suffix: 'forgebox', ext: "zip" };
		// patterns['jar']     = { suffix: '', ext: "jar" };

		loop query=qry {
			var type = "";
			var ext=listLast(qry.name,'.');
			var version="";
			// core (.lco)
			var name=qry.name;
			var _name = mid( listDeleteAt( name, listLen( name, "." ), "." ), 7 ); // strip off the file extension [.zip] and [lucee-] prefix
			//systemOutput( "b4:" & qry.directory & "/" & name & " [#_name#]", true);
			if ( ext=='lco' ) {
				var version = _name;
				var type="lco";
			} else if ( ext=='exe' ) {
				var _installer = services.VersionUtils::parseInstallerFilename( qry.name );
				var version = _installer.version;
				var type =  _installer.type;
			} else if ( ext=='run' ) {
				var _installer = services.VersionUtils::parseInstallerFilename( qry.name );
				var version = _installer.version;
				var type =  _installer.type;
			} else if ( ext=='war' ) {
				var version = _name ;
				var type="war";
			}
			// all others
			else {
				loop struct=patterns key="local.t" value="local.pattern" {
					if ( pattern.ext != ext ) continue;
					var s = len( pattern.suffix );
					//systemOutput( "----- suffix " & pattern.suffix & " #s# [" & right( _name, s ) & "] " & _name, true);
					if (right( _name, s ) == pattern.suffix ) {
						var version = mid( _name, 1, len( _name )-s); // ignore the leading -
						var type=t;
						if(type=="jars") type="jar";
						break;
					}
				}
				// hard to match no suffix
				if ( len( type ) eq 0 and ext eq "jar" ) {
					version = _name;
					type = "jar";
				}
			}

			//systemOutput( "mid:" & qry.directory & "/" & name & " - " & version & " - " & type, true);

			// check version
			var arrVersion=listToArray(version,'.');
			if ( arrayLen(arrVersion)!=4 ||
				!isNumeric(arrVersion[1]) ||
				!isNumeric(arrVersion[2]) ||
				!isNumeric(arrVersion[3])) continue;

			// hide 7.0.0.202 stable
			if (arrVersion[1] == 7
				&& arrVersion[2] == 0
				&& arrVersion[3] == 0
				&& arrVersion[4] == 202) continue;

				var arrPatch=listToArray(arrVersion[4],'-');
			if ( arrayLen(arrPatch)>2 ||
				arrayLen(arrPatch)==0 ||
				!isNumeric(arrPatch[1])) continue;

			if (arrayLen(arrPatch)==2 &&
				arrPatch[2]!="SNAPSHOT" &&
				arrPatch[2]!="BETA" &&
				arrPatch[2]!="RC" &&
				arrPatch[2]!="ALPHA") continue;

			var vs=services.VersionUtils::toVersionSortable(version);
			//if(isNull(data[version])) data[version]={};
			if ( !structKeyExists( data, vs ) ) {
				data[vs]= {};
				data[vs]['version']=version;
			}
			data[vs][type]=qry.directory & "/" & name;
			if ( type=="jar" ){
				data[vs]['lastModified']=qry.dateLastModified;
				data[vs]['size']=qry.size;
			}
			// systemOutput( "after" & qry.directory & "/" & name & " - " & type, true);
		}

		// now convert back to the format returned by luceeVersionsListS3
		var versions=[];
		structEach( data, function( k,v ) {
			arrayAppend( versions, v );
		});
		// systemOutput(serializeJson(var=data, compact=false), true);

		return versions;
	}

}