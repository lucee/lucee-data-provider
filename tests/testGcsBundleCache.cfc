/**
 * services.GcsBundleCache: the object names (<prefix><Bundle-SymbolicName>-<Bundle-Version>.jar), the requests
 * to the Cloud Storage JSON API (no overwrite: ifGenerationMatch=0) and what it keeps in memory.
 */
component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			  "/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
			, "/ldev6953" : dir
		};
	}

	private function _cache( transport, string prefix="provider/bundles/", string publicBaseUrl="" ) {
		return new services.GcsBundleCache( bucket="lucee_downloads", prefix=arguments.prefix, publicBaseUrl=arguments.publicBaseUrl, transport=arguments.transport );
	}

	function run( testResults, testBox ) {
		describe( "GcsBundleCache", function() {

			it( title="object names are flat <prefix><name>-<version>.jar", body=function() {
				var c = _cache( new ldev6953.GcsTransportStub() );
				expect( c.objectName( "org.lucee.axis.extension", "1.4.0.27-SNAPSHOT" ) ).toBe( "provider/bundles/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar" );
				expect( c.objectName( "mssqljdbc4", "4.0.2206.100" ) ).toBe( "provider/bundles/mssqljdbc4-4.0.2206.100.jar" );
				expect( _cache( new ldev6953.GcsTransportStub(), "/jars" ).objectName( "a", "1" ) ).toBe( "jars/a-1.jar" );
				expect( _cache( new ldev6953.GcsTransportStub(), "" ).objectName( "a", "1" ) ).toBe( "a-1.jar" );
				// not a bundle name or version: not cached
				expect( c.objectName( "../etc", "1" ) ).toBe( "" );
				expect( c.objectName( "a/b", "1" ) ).toBe( "" );
				expect( c.objectName( "a", "1 2" ) ).toBe( "" );
			});

			it( title="publicUrl only with a public base URL", body=function() {
				expect( _cache( new ldev6953.GcsTransportStub() ).publicUrl( "a", "1" ) ).toBe( "" );
				expect( _cache( new ldev6953.GcsTransportStub(), "provider/bundles/", "https://storage.googleapis.com/lucee-bundles" ).publicUrl( "a", "1" ) )
					.toBe( "https://storage.googleapis.com/lucee-bundles/provider/bundles/a-1.jar" );
			});

			it( title="exists asks the metadata once, a found object is remembered, a miss for a while", body=function() {
				var t = new ldev6953.GcsTransportStub( [ { match="^GET .*/o/provider%2Fbundles%2Fa-1\.jar\?fields", status=200, body="{}" } ] );
				var c = _cache( t );
				expect( c.exists( "a", "1" ) ).toBeTrue();
				expect( c.exists( "a", "1" ) ).toBeTrue();
				expect( t.count( "/o/provider%2Fbundles%2Fa-1\.jar" ) ).toBe( 1 );

				expect( c.exists( "b", "2" ) ).toBeFalse();
				expect( c.exists( "b", "2" ) ).toBeFalse();
				expect( t.count( "/o/provider%2Fbundles%2Fb-2\.jar" ) ).toBe( 1 );

				// one token for all requests, sent as a bearer token
				expect( t.count( "metadata\.google\.internal" ) ).toBe( 1 );
				expect( t.requests[ 2 ].headers.Authorization ).toBe( "Bearer tok" );
			});

			it( title="exists throws on an error answer, without remembering it", body=function() {
				var t = new ldev6953.GcsTransportStub( [ { match="fields", status=403 } ] );
				var c = _cache( t );
				expect( function() { c.exists( "a", "1" ); } ).toThrow();
				expect( function() { c.exists( "a", "1" ); } ).toThrow();
			});

			it( title="put uploads with ifGenerationMatch=0, 412 (already there) counts as there", body=function() {
				var file = GetTempFile( GetTempDirectory(), "gcsput" );
				FileWrite( file, "jar" );
				try {
					var t = new ldev6953.GcsTransportStub( [
						  { match="^POST .*name=provider%2Fbundles%2Fa-1\.jar", status=200, body="{}" }
						, { match="^POST .*name=provider%2Fbundles%2Fb-2\.jar", status=412 }
						, { match="^POST .*name=provider%2Fbundles%2Fc-3\.jar", status=403 }
					] );
					var c = _cache( t );
					expect( c.put( "a", "1", file ) ).toBeTrue();
					expect( c.put( "b", "2", file ) ).toBeTrue();
					expect( function() { c.put( "c", "3", file ); } ).toThrow();

					var uploads = t.requests.filter( function( r ) { return r.method == "POST"; } );
					expect( uploads[ 1 ].url ).toInclude( "https://storage.googleapis.com/upload/storage/v1/b/lucee_downloads/o?uploadType=media" );
					expect( uploads[ 1 ].url ).toInclude( "ifGenerationMatch=0" );

					// known now: no metadata request and no second upload
					expect( c.exists( "a", "1" ) ).toBeTrue();
					expect( c.exists( "b", "2" ) ).toBeTrue();
					expect( c.put( "a", "1", file ) ).toBeTrue();
					expect( t.count( "fields" ) ).toBe( 0 );
					expect( t.count( "^POST .*a-1\.jar" ) ).toBe( 1 );
				} finally {
					FileDelete( file );
				}
			});

			it( title="no bucket: disabled, no requests", body=function() {
				var t = new ldev6953.GcsTransportStub();
				var c = new services.GcsBundleCache( bucket="", transport=t );
				expect( c.isEnabled() ).toBeFalse();
				expect( c.exists( "a", "1" ) ).toBeFalse();
				expect( ArrayLen( t.requests ) ).toBe( 0 );
			});

		});

		describe( "MavenMatcher .lex candidates of a bundle", function() {

			it( title="org.lucee.axis.extension 1.4.0.27-SNAPSHOT is in org.lucee:axis-extension", body=function() {
				var paths = new services.legacy.MavenMatcher().lexSearchPaths( "org.lucee.axis.extension", "1.4.0.27-SNAPSHOT" );
				expect( paths[ 1 ] ).toBe( "/org/lucee/axis-extension/1.4.0.27-SNAPSHOT/axis-extension-1.4.0.27-SNAPSHOT.lex" );
				expect( paths ).toInclude( "/org/lucee/axis.extension/1.4.0.27-SNAPSHOT/axis.extension-1.4.0.27-SNAPSHOT.lex" );
			});

			it( title="mssqljdbc4 4.0.2206.100 is in org.lucee:mssql-jdbc-extension (lexBundles.json)", body=function() {
				var paths = new services.legacy.MavenMatcher().lexSearchPaths( "mssqljdbc4", "4.0.2206.100" );
				expect( paths[ 1 ] ).toBe( "/org/lucee/mssql-jdbc-extension/4.0.2206.100/mssql-jdbc-extension-4.0.2206.100.lex" );
			});

			it( title="redis.extension 2.9.0.3-BETA is in org.lucee:redis-extension", body=function() {
				expect( new services.legacy.MavenMatcher().lexSearchPaths( "redis.extension", "2.9.0.3-BETA" ) )
					.toInclude( "/org/lucee/redis-extension/2.9.0.3-BETA/redis-extension-2.9.0.3-BETA.lex" );
			});

			it( title="no .lex lookup for latest", body=function() {
				expect( new services.legacy.MavenMatcher().findLexUrls( "org.lucee.axis.extension", "latest" ) ).toBe( [] );
			});

		});
	}

}
