component {
	
	variables.ResourceUtil=createObject('java','lucee.commons.io.res.util.ResourceUtil');
	variables.Pack200=createObject('java','java.util.jar.Pack200');
	variables.GZIPInputStream=createObject('java','java.util.zip.GZIPInputStream');
	variables.GZIPOutputStream=createObject('java','java.util.zip.GZIPOutputStream');
	variables.JarInputStream=createObject('java','java.util.jar.JarInputStream');
	variables.JarOutputStream=createObject('java','java.util.jar.JarOutputStream');
	variables.System=createObject('java','java.lang.System');
	variables.DevNullOutputStream=createObject('java','lucee.commons.io.DevNullOutputStream');
	variables.PrintStream=createObject('java','java.io.PrintStream');
	
	public void function pack2Jar(string p200FilePath,string jarFilePath) localmode=true {
		p200=ResourceUtil.toResourceNotExisting(getPageContext(), p200FilePath);
		jar=ResourceUtil.toResourceNotExisting(getPageContext(), jarFilePath);

		if(!jar.exists())jar.createFile(false);
		_pack2Jar(p200.getInputStream(), jar.getOutputStream());
	}
	
	public void function jar2pack(string jarFilePath, string p200FilePath) localmode=true {
		jar=ResourceUtil.toResourceNotExisting(getPageContext(), jarFilePath);
		p200=ResourceUtil.toResourceNotExisting(getPageContext(), p200FilePath);
		if(!p200.exists())p200.createFile(false);
		_jar2pack(jar.getInputStream(), p200.getOutputStream());
	}

	private void function _pack2Jar(is,os) localmode=true {
		
		unpacker = Pack200.newUnpacker();
		p = unpacker.properties();
		p.put(unpacker.DEFLATE_HINT, unpacker.TRUE);
		
		is=GZIPInputStream.init(is);
		try{
			jos = JarOutputStream.init(os);
			unpacker.unpack(is, jos);
			jos.finish();
		}
		finally{
			is.close();
			jos.close();
		}
	}
	
	private void function _jar2pack(is,os, boolean closeIS, boolean closeOS) localmode=true {
		// Create the Packer object
		packer = Pack200.newPacker();

		// Initialize the state by setting the desired properties
		p = packer.properties();
		// take more time choosing codings for better compression
		p.put(packer.EFFORT, "7");  // default is "5"
		// use largest-possible archive segments (>10% better compression).
		p.put(packer.SEGMENT_LIMIT, "-1");
		// reorder files for better compression.
		p.put(packer.KEEP_FILE_ORDER, packer.FALSE);
		// smear modification times to a single value.
		p.put(packer.MODIFICATION_TIME, packer.LATEST);
		// ignore all JAR deflation requests,
		// transmitting a single request to use "store" mode.
		p.put(packer.DEFLATE_HINT, packer.FALSE);
		// discard debug attributes
		p.put(packer.CODE_ATTRIBUTE_PFX&"LineNumberTable", packer.STRIP);
		// throw an error if an attribute is unrecognized
		p.put(packer.UNKNOWN_ATTRIBUTE, packer.ERROR);
		
		
		
		os=GZIPOutputStream.init(os);
		
		err = System.err;
		try{
			System.setErr(PrintStream.init(DevNullOutputStream.DEV_NULL_OUTPUT_STREAM));
			jis = JarInputStream.init(is);
			packer.pack(jis, os);
		}
		finally{
			System.setErr(err);
			jis.close();
			os.close();
		}
	}
	
}