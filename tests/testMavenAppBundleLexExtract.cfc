component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/ldev6953" : dir
		};
		variables.work = GetTempDirectory() & "ldev6953-lex-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {
		describe( "LDEV-6953 extract OSGi jars from an extension lex", function() {

			it( title="findBundle serves the jar whose Bundle-SymbolicName matches, and indexes the others", body=function() {
				var lexFile = _createLexWithBundles();
				var matcher = new ldev6953.LDEV6953MatcherStub( lexFile );
				var reader  = new ldev6953.LDEV6953MetaStub();
				var svc = new services.BundleDownloadService(
					  extensionsCdnUrl    = ""
					, bundleS3Root        = ""
					, bundleCdnUrl        = ""
					, extensionMetaReader = reader
					, mavenMatcher        = matcher
				);

				var chart = svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				expect( chart ).toHaveKey( "file" );
				expect( Len( chart.file ) ).toBeGT( 0 );
				expect( FileExists( chart.file ) ).toBeTrue();
				expect( ListLast( chart.file, "/\\" ) ).toBe( "org.lucee.chart.extension-2.0.0.1.jar" );
				expect( ListLast( chart.url ?: "", "." ) ).notToBe( "lex" );

				var manifest = _bundleManifest( chart.file );
				expect( manifest.bundleName ).toBe( "org.lucee.chart.extension" );
				expect( manifest.bundleVersion ).toBe( "2.0.0.1" );

				var jfree = svc.findBundle( "org.jfree.chart", "1.0.19.0001L" );
				expect( FileExists( jfree.file ?: "" ) ).toBeTrue();
				var jfreeMf = _bundleManifest( jfree.file );
				expect( jfreeMf.bundleName ).toBe( "org.jfree.chart" );
				expect( jfreeMf.bundleVersion ).toBe( "1.0.19.0001L" );
			});

		});
	}

	private string function _createLexWithBundles() {
		var src = variables.work & "src/";
		DirectoryCreate( src & "META-INF", true );
		DirectoryCreate( src & "jars", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0#Chr(10)#id: D46B46A9-A0E3-44E1-D972A04AC3A8DC10#Chr(10)#version: 2.0.0.1#Chr(10)#" );
		_writeOsgiJar( src & "jars/chart-extension-2.0.0.1.jar", "org.lucee.chart.extension", "2.0.0.1" );
		_writeOsgiJar( src & "jars/org-jfree-chart-1-0-19-0001L.jar", "org.jfree.chart", "1.0.19.0001L" );
		var lexFile = variables.work & "chart-extension-2.0.0.1.lex";
		_zipDirectory( src, lexFile );
		return lexFile;
	}

	private void function _writeOsgiJar( required string path, required string symbolicName, required string version ) {
		var jarSrc = variables.work & "jar-" & CreateUniqueId() & "/";
		DirectoryCreate( jarSrc & "META-INF", true );
		var mf = "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "Bundle-ManifestVersion: 2" & Chr( 13 ) & Chr( 10 )
			& "Bundle-SymbolicName: " & arguments.symbolicName & Chr( 13 ) & Chr( 10 )
			& "Bundle-Version: " & arguments.version & Chr( 13 ) & Chr( 10 );
		FileWrite( jarSrc & "META-INF/MANIFEST.MF", mf );
		FileWrite( jarSrc & "placeholder.txt", arguments.symbolicName );
		_zipDirectory( jarSrc, arguments.path );
		DirectoryDelete( jarSrc, true );
	}

	private struct function _bundleManifest( required string jarFile ) {
		var zipFile = CreateObject( "java", "java.util.zip.ZipFile" ).init( arguments.jarFile );
		try {
			var entry = zipFile.getEntry( "META-INF/MANIFEST.MF" );
			var stream = zipFile.getInputStream( entry );
			try {
				var text = ToString( stream.readAllBytes(), "UTF-8" );
			} finally {
				stream.close();
			}
		} finally {
			zipFile.close();
		}
		var headers = {};
		for ( var raw in ListToArray( Replace( text, Chr( 13 ), "", "all" ), Chr( 10 ), true ) ) {
			var colon = Find( ":", raw );
			if ( colon >= 2 ) {
				headers[ Trim( Left( raw, colon - 1 ) ) ] = Trim( Mid( raw, colon + 1 ) );
			}
		}
		return {
			  bundleName    = headers[ "Bundle-SymbolicName" ] ?: ""
			, bundleVersion = headers[ "Bundle-Version" ] ?: ""
		};
	}

	private void function _zipDirectory( required string src, required string target ) {
		var base = Replace( arguments.src, "\\", "/", "all" );
		if ( Right( base, 1 ) != "/" ) {
			base &= "/";
		}
		var zos = CreateObject( "java", "java.util.zip.ZipOutputStream" ).init(
			CreateObject( "java", "java.io.FileOutputStream" ).init( arguments.target )
		);
		try {
			for ( var path in DirectoryList( arguments.src, true, "path" ) ) {
				if ( DirectoryExists( path ) ) {
					continue;
				}
				var name = Mid( Replace( path, "\\", "/", "all" ), Len( base ) + 1, 9999 );
				zos.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( name ) );
				var instream = CreateObject( "java", "java.io.FileInputStream" ).init( path );
				try {
					var buf = CreateObject( "java", "java.lang.reflect.Array" ).newInstance(
						CreateObject( "java", "java.lang.Byte" ).TYPE,
						8192
					);
					var read = instream.read( buf );
					while ( read >= 0 ) {
						if ( read > 0 ) {
							zos.write( buf, 0, read );
						}
						read = instream.read( buf );
					}
				} finally {
					instream.close();
				}
				zos.closeEntry();
			}
		} finally {
			zos.close();
		}
	}

}
