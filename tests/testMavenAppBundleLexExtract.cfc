/**
 * A bundle that is on no Maven repository is looked up inside the extension .lex files: the .lex is unpacked once,
 * every OSGi jar of it goes into the bundle cache (Cloud Storage) as <prefix><Bundle-SymbolicName>-<Bundle-Version>.jar
 * (never overwriting), and the download is served from there.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/ldev6953" : dir
		};
		variables.lexFile = GetTempDirectory() & "bundle-lex-" & CreateUniqueId() & ".lex";
		_writeLex( variables.lexFile, [
			  { path="jars/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar", manifest={ "Bundle-SymbolicName"="org.lucee.test.extension;singleton:=true", "Bundle-Version"="1.2.3.4-SNAPSHOT" } }
			, { path="jars/other.bundle-2.0.0.jar", manifest={ "Bundle-SymbolicName"="other.bundle", "Bundle-Version"="2.0.0" } }
			, { path="jars/plain.jar", manifest={ "Implementation-Title"="not a bundle" } }
		] );
	}

	function afterAll() {
		if ( FileExists( variables.lexFile ) ) FileDelete( variables.lexFile );
	}

	private function _svc( cache, matcher, boolean lexFallback=true ) {
		var args = {
			  extensionsCdnUrl    = ""
			, bundleS3Root        = ""
			, bundleCdnUrl        = ""
			, extensionMetaReader = new ldev6953.LDEV6953MetaStub()
			, mavenMatcher        = arguments.matcher
			, lexFallback         = arguments.lexFallback
		};
		if ( !IsNull( arguments.cache ) ) {
			args.bundleCache = arguments.cache;
		}
		return new services.BundleDownloadService( argumentCollection=args );
	}

	private function _matcher() {
		return new ldev6953.BundleLexMatcherStub( variables.lexFile, [ "org.lucee.test.extension" ] );
	}

	function run( testResults, testBox ) {
		describe( "the .lex fallback with the bundle cache", function() {

			it( title="unpacks the lex, caches every OSGi jar under <name>-<version>.jar and answers the cache object", body=function() {
				var cache = new ldev6953.BundleCacheMemoryStub();
				var svc   = _svc( cache, _matcher() );

				var b = svc.findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				expect( b.url ).toBe( "" );
				expect( b.cacheObject ).toBe( "provider/bundles/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar" );
				expect( StructKeyList( cache.objects ) ).toInclude( "provider/bundles/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar" );
				expect( StructKeyList( cache.objects ) ).toInclude( "provider/bundles/other.bundle-2.0.0.jar" );
				expect( StructCount( cache.objects ) ).toBe( 2 ); // plain.jar is no OSGi bundle
				// the requested bundle is uploaded first
				expect( cache.puts[ 1 ] ).toBe( "provider/bundles/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar" );

				var bytes = svc.readCachedBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				expect( IsBinary( bytes ) ).toBeTrue();
				expect( Len( bytes ) ).toBeGT( 0 );
			});

			it( title="a lex is unpacked once per instance, repeated requests are answered from memory", body=function() {
				var cache   = new ldev6953.BundleCacheMemoryStub();
				var matcher = _matcher();
				var svc     = _svc( cache, matcher );

				svc.findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				var puts = ArrayLen( cache.puts );
				var again = svc.findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				expect( again.cacheObject ).toBe( "provider/bundles/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar" );
				expect( ArrayLen( cache.puts ) ).toBe( puts );
				expect( matcher.lexLookups ).toBe( 1 );
			});

			it( title="another instance finds the jars of the lex in the bucket, without unpacking", body=function() {
				var cache = new ldev6953.BundleCacheMemoryStub();
				_svc( cache, _matcher() ).findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				var puts = ArrayLen( cache.puts );

				var matcher = _matcher();
				var other   = _svc( cache, matcher ).findBundle( "other.bundle", "2.0.0" );
				expect( other.cacheObject ).toBe( "provider/bundles/other.bundle-2.0.0.jar" );
				expect( matcher.lexLookups ).toBe( 0 );
				expect( ArrayLen( cache.puts ) ).toBe( puts );
			});

			it( title="a jar that is already in the bucket is never overwritten", body=function() {
				var cache = new ldev6953.BundleCacheMemoryStub();
				var name  = "provider/bundles/other.bundle-2.0.0.jar";
				cache.objects[ name ] = CharsetDecode( "already there", "UTF-8" );

				_svc( cache, _matcher() ).findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				expect( CharsetEncode( cache.objects[ name ], "UTF-8" ) ).toBe( "already there" );
			});

			it( title="a public bucket URL is answered as the url (a 302)", body=function() {
				var cache = new ldev6953.BundleCacheMemoryStub( publicBaseUrl="https://storage.googleapis.com/lucee-bundles/" );
				var b = _svc( cache, _matcher() ).findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" );
				expect( b.url ).toBe( "https://storage.googleapis.com/lucee-bundles/provider/bundles/org.lucee.test.extension-1.2.3.4-SNAPSHOT.jar" );
			});

			it( title="a bundle that is not in the lex is a 404, cached for a while", body=function() {
				var cache   = new ldev6953.BundleCacheMemoryStub();
				var matcher = new ldev6953.BundleLexMatcherStub( variables.lexFile, [ "missing.bundle" ] );
				var svc     = _svc( cache, matcher );

				var b = svc.findBundle( "missing.bundle", "1.0.0" );
				expect( b.url ).toBe( "" );
				expect( b.cacheObject ).toBe( "" );
				expect( IsDate( b.cacheExpires ) ).toBeTrue();
				svc.findBundle( "missing.bundle", "1.0.0" );
				expect( matcher.lexLookups ).toBe( 1 );
			});

			it( title="no lex lookup for latest, without a bundle cache or with the fallback off", body=function() {
				var matcher = _matcher();
				expect( _svc( new ldev6953.BundleCacheMemoryStub(), matcher ).findBundle( "org.lucee.test.extension", "latest" ).cacheObject ?: "" ).toBe( "" );
				expect( _svc( NullValue(), matcher ).findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" ).cacheObject ?: "" ).toBe( "" );
				expect( _svc( new ldev6953.BundleCacheMemoryStub(), matcher, false ).findBundle( "org.lucee.test.extension", "1.2.3.4-SNAPSHOT" ).cacheObject ?: "" ).toBe( "" );
				expect( matcher.lexLookups ).toBe( 0 );
			});

		});
	}

	// a .lex (zip) with jars that have the given manifest headers
	private void function _writeLex( required string file, required array jars ) {
		var out = CreateObject( "java", "java.util.zip.ZipOutputStream" ).init( CreateObject( "java", "java.io.FileOutputStream" ).init( arguments.file ) );
		try {
			out.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( "META-INF/MANIFEST.MF" ) );
			out.write( CharsetDecode( "Manifest-Version: 1.0#Chr(13)##Chr(10)#name: test#Chr(13)##Chr(10)##Chr(13)##Chr(10)#", "UTF-8" ) );
			out.closeEntry();
			for ( var jar in arguments.jars ) {
				out.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( jar.path ) );
				out.write( _jarBytes( jar.manifest ) );
				out.closeEntry();
			}
		} finally {
			out.close();
		}
	}

	private binary function _jarBytes( required struct headers ) {
		var mf = "Manifest-Version: 1.0#Chr(13)##Chr(10)#";
		for ( var k in arguments.headers ) {
			mf &= k & ": " & arguments.headers[ k ] & Chr(13) & Chr(10);
		}
		mf &= Chr(13) & Chr(10);
		var bos = CreateObject( "java", "java.io.ByteArrayOutputStream" ).init();
		var zos = CreateObject( "java", "java.util.zip.ZipOutputStream" ).init( bos );
		zos.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( "META-INF/MANIFEST.MF" ) );
		zos.write( CharsetDecode( mf, "UTF-8" ) );
		zos.closeEntry();
		zos.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( "readme.txt" ) );
		zos.write( CharsetDecode( "test", "UTF-8" ) );
		zos.closeEntry();
		zos.close();
		return bos.toByteArray();
	}

}
