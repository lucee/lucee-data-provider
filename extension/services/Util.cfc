component {


	/**
	 * Takes an OSGi compatible version string and returns as a "sortable"
	 * string with padded version numbers.
	 *
	 * n.b. Taken from original and not reformatted/refactored yet.
	 */
	public static function sortableVersionString( required string version ){
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
}