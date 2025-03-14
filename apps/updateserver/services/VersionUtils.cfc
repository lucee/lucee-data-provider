component {


	/**
	 * Takes an OSGi compatible version string and returns as a "sortable"
	 * string with padded version numbers.
	 *
	 * n.b. Taken from original and not reformatted/refactored yet.
	 */
	public static function sortableVersionString( required string version ) cachedWithin=1 {
		local.arr = ListToArray( arguments.version, '.' );

		// OSGi compatible version
		if( arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			return version;
		}
		local.sct = {major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if(qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()==2 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[2];
			if(sct.qualifier_appendix=="SNAPSHOT")sct.qualifier_appendix_nbr=0;
			else if(sct.qualifier_appendix=="BETA")sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else {
			sct.qualifier=isNumeric(qArr[1])?qArr[1]+0:0;
			sct.qualifier_appendix_nbr=75;
		}

		return repStr("0",2-len(sct.major))&sct.major
					&"."&repStr("0",3-len(sct.minor))&sct.minor
					&"."&repStr("0",3-len(sct.micro))&sct.micro
					&"."&repStr("0",4-len(sct.qualifier))&sct.qualifier
					&"."&repStr("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}

	public static function repStr(str,amount) {
		if(amount<1) return "";
		return repeatString(str,amount);
	}

	public static function toVersionSortable(string version) cachedWithin=1 {
		local.arr=listToArray(arguments.version,'.');

		if(arr.len()!=4 || !isNumeric(arr[1]) || !isNumeric(arr[2]) || !isNumeric(arr[3])) {
			throw "version number ["&arguments.version&"] is invalid";
		}
		local.sct={major:arr[1]+0,minor:arr[2]+0,micro:arr[3]+0,qualifier_appendix:"",qualifier_appendix_nbr:100};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		local.qArr=listToArray(arr[4],'-');
		if (qArr.len()==1 && isNumeric(qArr[1])) local.sct.qualifier=qArr[1]+0;
		else if(qArr.len()==2 && isNumeric(qArr[1])) {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix=qArr[2];
			if (sct.qualifier_appendix=="SNAPSHOT") sct.qualifier_appendix_nbr=0;
			else if (sct.qualifier_appendix=="BETA") sct.qualifier_appendix_nbr=50;
			else sct.qualifier_appendix_nbr=75; // every other appendix is better than SNAPSHOT
		}
		else {
			sct.qualifier=qArr[1]+0;
			sct.qualifier_appendix_nbr=75;
		}

		return	repeatString("0",2-len(sct.major))&sct.major
			&"."&repeatString("0",3-len(sct.minor))&sct.minor
			&"."&repeatString("0",3-len(sct.micro))&sct.micro
			&"."&repeatString("0",4-len(sct.qualifier))&sct.qualifier
			&"."&repeatString("0",3-len(sct.qualifier_appendix_nbr))&sct.qualifier_appendix_nbr;
	}

	/*
	lucee-6.2.1.58-SNAPSHOT-linux-aarch64-installer.run
	lucee-6.2.1.58-SNAPSHOT-linux-x64-installer.run
	lucee-6.2.1.58-SNAPSHOT-windows-x64-installer.exe
	*/

	public static function parseInstallerFilename( filename ){
		var ext = listLast( arguments.filename, '.' );
		var _version = listToArray( arguments.filename, "-" );
		var type = "";
		var version = "";
		switch ( ext ){
			case "run":
				type = findNoCase('-x64-', arguments.filename ) ? 'linux-x64' : 'linux-aarch64';
				var pos = ArrayFind( _version, 'linux' );
				version = _version[ 2 ];
				if (pos == 4)
					 version &= "-" & _version[ 3 ]; // i.e. snapshot
				break;
			case "exe":
				type="win64";
				var pos = ArrayFind( _version, 'windows' );
				version = _version[ 2 ];
				if (pos == 4)
					 version &= "-" & _version[ 3 ]; // i.e. snapshot
				break;
			default:
				break;
		}
		return {
			version,
			type
		};
	}

	public static function matchVersion( versions, type, version, distribution ){
		//systemOutput(versions.toJson(), true);
		//systemOutput("", true);
		//systemOutput("-------[#type#][#version#][#distribution#]------------", true);
		var arrVersions = structKeyArray( arguments.versions ).reverse();

		loop array="#arrVersions#" index="local.i" value="local.v" {
			var _version = versions[ local.v ].version;
			var _type = listToArray( _version, "-" ); // [ "6.2.0.317", "RC" ]
			//systemOutput({_version, _type}, true);
			if ( arrayLen( _type ) eq 2 && arguments.type eq "stable" ){
				// version has a suffix, i.e. 6.2.1.55-SNAPSHOT, stable versions have no suffix
				//systemOutput("version has a suffix, not stable", true);
				continue;
			} else if ( len( arguments.type ) gt 0 && arguments.type neq "stable" ){
				if ( arrayLen( _type ) eq 1
						|| ( _type[ 2 ] neq arguments.type) ){
					//systemOutput("wrong type", true);
					continue;
				}
			}

			if ( len( arguments.version ) eq 0
					&& structKeyExists( versions[ local.v ], arguments.distribution ) ){
				//systemOutput("match for the first version for the requested distribution", true);
				return v;
			}
			var versionMatches = findNoCase( arguments.version, _version );
			if ( versionMatches neq 1 ) {
				//systemOutput("requested version prefix does not match this version", true);
				continue;
			}
			// at this point, the versions prefix match
			if ( versionMatches eq 1 && len( _type[ 1 ] ) eq len( arguments.version ) ) {
				//systemOutput("exact version match", true);
				if ( structKeyExists( versions[ local.v ], arguments.distribution ) ){
					//systemOutput("exact version match", true);
					return v;
				} else {
					//systemOutput("exact version match, no distribution", true);
					return "";
				}
			} else {
				// avoid 6.2.1.55 matching 6.2.1.5
				if ( ( len( arguments.version ) lt len( _type[ 1 ] )
						&& mid( _type[ 1 ], len( arguments.version ) + 1, 1 ) neq "." )) {
					//systemOutput("avoid partial match", true);
					continue;
				}
			}
			if ( structKeyExists( versions[ local.v ], arguments.distribution ) ){
				return v; // match on version and distribution
			} else {
				//systemOutput("match but missing distribution", true);
				continue; //
			}
		}
		return "";
	}
}