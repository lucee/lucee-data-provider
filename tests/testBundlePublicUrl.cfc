/**
 * A jar that was extracted from a lex is redirected to (302) when the same bundle has a public URL, the URL lookup
 * runs once per bundle and its answer is cached, see BundleDownloadService._preferPublicUrl().
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services"  : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/bundleurl" : dir
		};
		variables.work = GetTempDirectory() & "bundle-public-url-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {
		describe( "jars extracted from a lex prefer a public URL", function() {

			it( title="a jar of the lex with a public URL gets that URL (and keeps the file), the lookup is cached", body=function() {
				var jfreeUrl = "https://repo1.maven.org/maven2/org/lucee/org.jfree.chart/1.0.19.0001L/org.jfree.chart-1.0.19.0001L.jar";
				var matcher  = new bundleurl.BundlePublicUrlMatcherStub( _createLex(), { "org.jfree.chart:1.0.19.0001L": jfreeUrl } );
				var svc      = _service( matcher );

				// the requested bundle: no public jar, served from the disk of this instance
				var chart = svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				expect( FileExists( chart.file ?: "" ) ).toBeTrue();
				expect( chart.url ).toBe( "" );
				expect( IsDate( chart.urlCheckAfter ) ).toBeTrue();
				expect( chart.urlCheckAfter > Now() ).toBeTrue();

				// a jar that was indexed with it: not served from the disk when Maven has it
				matcher.resetCalls();
				var jfree = svc.findBundle( "org.jfree.chart", "1.0.19.0001L" );
				expect( jfree.url ).toBe( jfreeUrl );
				expect( FileExists( jfree.file ?: "" ) ).toBeTrue();
				expect( ArrayLen( matcher.getCalls() ) ).toBeGT( 0 );

				// answered from the cache: no lookup at all, for the found URL and for the miss
				matcher.resetCalls();
				expect( svc.findBundle( "org.jfree.chart", "1.0.19.0001L" ).url ).toBe( jfreeUrl );
				expect( svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" ).url ).toBe( "" );
				expect( matcher.getCalls() ).toBe( [] );
			});

			it( title="the URL lookup only asks for jars, a lex is never a public URL of a jar", body=function() {
				var matcher = new bundleurl.BundlePublicUrlMatcherStub( _createLex() );
				var svc     = _service( matcher );

				svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				var jarsOnly = matcher.getCalls().filter( function( c ) { return c.jarsOnly; } );
				expect( ArrayLen( jarsOnly ) ).toBe( 1 );
				expect( jarsOnly[ 1 ].rawSearch ).toBeTrue();
				expect( jarsOnly[ 1 ].bundleName ).toBe( "org.lucee.chart.extension" );
			});

			it( title="a failed URL lookup still serves the file and is retried within the hour", body=function() {
				var matcher = new bundleurl.BundlePublicUrlMatcherStub( lexFile=_createLex(), failJarsOnly=true );
				var svc     = _service( matcher );

				var chart = svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				expect( FileExists( chart.file ?: "" ) ).toBeTrue();
				expect( chart.url ).toBe( "" );
				expect( chart.urlCheckAfter <= DateAdd( "n", 61, Now() ) ).toBeTrue();
			});

			it( title="a known URL is kept when the extracted jar is gone from the temp folder, no new lookup", body=function() {
				var jfreeUrl = "https://maven.lucee-services.com/org/lucee/org.jfree.chart/1.0.19.0001L/org.jfree.chart-1.0.19.0001L.jar";
				var matcher  = new bundleurl.BundlePublicUrlMatcherStub( _createLex(), { "org.jfree.chart:1.0.19.0001L": jfreeUrl } );
				var svc      = _service( matcher );

				svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				var jfree = svc.findBundle( "org.jfree.chart", "1.0.19.0001L" );
				expect( jfree.url ).toBe( jfreeUrl );
				// the temp folder is shared with the other bundle tests: put the jar back afterwards
				var keep = variables.work & "keep-" & CreateUniqueId() & ".jar";
				FileCopy( jfree.file, keep );
				FileDelete( jfree.file );
				try {
					matcher.resetCalls();
					var again = svc.findBundle( "org.jfree.chart", "1.0.19.0001L" );
					expect( again.url ).toBe( jfreeUrl );
					expect( again.file ).toBe( "" );
					expect( matcher.getCalls() ).toBe( [] );
				} finally {
					FileCopy( keep, jfree.file );
				}
			});

			it( title="'latest' is not given the URL of another version", body=function() {
				var matcher = new bundleurl.BundlePublicUrlMatcherStub( _createLex() );
				var svc     = _service( matcher );

				svc.findBundle( "org.lucee.chart.extension", "2.0.0.1" );
				matcher.resetCalls();
				var latest = svc.findBundle( "org.jfree.chart", "latest" );
				expect( matcher.getCalls().filter( function( c ) { return c.jarsOnly; } ) ).toBe( [] );
			});

		});

		describe( "MavenMatcher raw search with jarsOnly", function() {

			it( title="finds the lex without jarsOnly, nothing with it, and a jar with it", body=function() {
				var repo = variables.work & "repo-" & CreateUniqueId() & "/";
				var lexPath = repo & "org/lucee/x-ext/1.0.0/x-ext-1.0.0.lex";
				DirectoryCreate( GetDirectoryFromPath( lexPath ), true );
				FileWrite( lexPath, "lex" );

				var matcher = new bundleurl.LocalRepoMavenMatcherStub( repo );
				expect( matcher.findBundleUrl( bundleName="x.ext", bundleVersion="1.0.0", rawSearch=true ) ).toInclude( "x-ext-1.0.0.lex" );
				expect( matcher.findBundleUrl( bundleName="x.ext", bundleVersion="1.0.0", rawSearch=true, jarsOnly=true ) ).toBe( "" );

				// uploaded as org.lucee:<Bundle-SymbolicName>:<version> ("Upload Maven jar" workflow)
				var jarPath = repo & "org/lucee/x.ext/1.0.0/x.ext-1.0.0.jar";
				DirectoryCreate( GetDirectoryFromPath( jarPath ), true );
				FileWrite( jarPath, "jar" );
				expect( matcher.findBundleUrl( bundleName="x.ext", bundleVersion="1.0.0", rawSearch=true, jarsOnly=true ) ).toInclude( "x.ext-1.0.0.jar" );
			});

			it( title="an org.lucee.* bundle with jarsOnly does not answer the dashed lex", body=function() {
				var repo = variables.work & "repo-" & CreateUniqueId() & "/";
				var lexPath = repo & "org/lucee/y-extension/2.0.0/y-extension-2.0.0.lex";
				DirectoryCreate( GetDirectoryFromPath( lexPath ), true );
				FileWrite( lexPath, "lex" );

				var matcher = new bundleurl.LocalRepoMavenMatcherStub( repo );
				expect( matcher.findBundleUrl( bundleName="org.lucee.y.extension", bundleVersion="2.0.0", rawSearch=true ) ).toInclude( ".lex" );
				expect( matcher.findBundleUrl( bundleName="org.lucee.y.extension", bundleVersion="2.0.0", rawSearch=true, jarsOnly=true ) ).toBe( "" );
			});

		});
	}

	private any function _service( required any matcher ) {
		return new services.BundleDownloadService(
			  extensionsCdnUrl    = ""
			, bundleS3Root        = ""
			, bundleCdnUrl        = ""
			, extensionMetaReader = new bundleurl.LDEV6953MetaStub()
			, mavenMatcher        = arguments.matcher
		);
	}

	// a lex with org.lucee.chart.extension 2.0.0.1 and org.jfree.chart 1.0.19.0001L (the same as the LDEV-6953 test)
	private string function _createLex() {
		return _createLexWithBundles();
	}

	private string function _createLexWithBundles() {
		var id  = CreateUniqueId();
		var src = variables.work & "src-" & id & "/";
		DirectoryCreate( src & "META-INF", true );
		DirectoryCreate( src & "jars", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0#Chr(10)#id: D46B46A9-A0E3-44E1-D972A04AC3A8DC10#Chr(10)#version: 2.0.0.1#Chr(10)#" );
		_writeOsgiJar( src & "jars/chart-extension-2.0.0.1.jar", "org.lucee.chart.extension", "2.0.0.1" );
		_writeOsgiJar( src & "jars/org-jfree-chart-1-0-19-0001L.jar", "org.jfree.chart", "1.0.19.0001L" );
		var lexFile = variables.work & "chart-extension-2.0.0.1-" & id & ".lex";
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
