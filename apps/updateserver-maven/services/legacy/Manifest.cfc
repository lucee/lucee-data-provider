component {
	
	variables.ResourceUtil=createObject('java','lucee.commons.io.res.util.ResourceUtil');
	variables.ZipFile=createObject('java','java.util.zip.ZipFile');
	variables.File=createObject('java','java.io.File');
	variables.Manifest=createObject('java','java.util.jar.Manifest');
	variables.StringUtil=createObject('java','lucee.commons.lang.StringUtil');
	

	public Struct function extractBundleInfo(required string path) localMode=true {
		sct=extractManifest(path);
		var rtn={"name":sct.main['Bundle-SymbolicName'],"version":sct.main['Bundle-Version']};
		return rtn;
	}
	public Struct function extractManifest(required string path) localMode=true {

		res = File.init(path);
		zip = ZipFile.init(res);
		
		// read the manifest from the file
		try {
			ze = zip.getEntry("META-INF/MANIFEST.MF");
			if(isNull(ze)) throw "zip file ["&str&"] has no entry with name [META-INF/MANIFEST.MF]";
			
			is = zip.getInputStream(ze);
			manifest=Manifest.init(is);
			
		}
		finally {
			is.close();
			zip.close();
		}
		
		// convert manifest to a struct
		sct={};
		// set the main attributes
		fillData(sct,"main",manifest.getMainAttributes());
		
		// all the others
		set = manifest.getEntries().entrySet();
		if(set.size()>0) {
			it = set.iterator();
			sec={};
			sct["sections"]=sec;
			while(it.hasNext()){
				e = it.next();
				fillData(sec,e.getKey(),e.getValue());
			}
		}
		return sct;
	}

	private void function fillData(Struct parent, String key, attrs) localMode=true {
		sct={};
		parent[key]=sct;
		
		it = attrs.entrySet().iterator();
		while(it.hasNext()){
			e = it.next();
			sct[toString(e.getKey())]=unwrap(toString(e.getValue()))
		}
	}

	private String function unwrap(String str) localmode=true {
	    str = str.trim();
	
	    if(left(str,1) == '"' && right(str,1)=='"')
		   	str=mid(str,2,str.len()-2);
	    if(left(str,1)== "'" && right(str,1)=="'")
			str=mid(str,2,str.len()-2);
		return str;
	}
}