component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/releasedateservices" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
		variables.src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
	}

	function run( testResults, testBox ) {

		describe( "getdate/{version}: the release date of a core version, fast and cached", function() {

			it( title="takes the lastModified of LuceeVersionsDetail(), without a request", body=function() {
				var w = _world();
				var rd = _new( w );
				var d = rd.get( "6.2.3.35" );

				expect( IsDate( d ) ).toBeTrue();
				expect( DateTimeFormat( d, "yyyy-mm-dd HH:nn:ss", "UTC" ) ).toBe( "2025-10-31 09:08:04" );
				expect( w.heads ).toBe( [] );
			});

			it( title="a version that is not listed is not found, without asking for its detail or a request", body=function() {
				var w = _world();
				var rd = _new( w );

				expect( rd.get( "6.2.3.34" ) ).toBe( "" );
				expect( rd.get( "garbage" ) ).toBe( "" );
				expect( rd.get( "7.0.0.1-FOO" ) ).toBe( "" );
				expect( w.details ).toBe( [] );
				expect( w.heads ).toBe( [] );
			});

			it( title="without a lastModified, one HEAD to the pom of the detail, the date of a release is kept for good", body=function() {
				var w = _world();
				var rd = _new( w );

				var d = rd.get( "7.1.2.195" );
				expect( IsDate( d ) ).toBeTrue();
				expect( DateTimeFormat( d, "yyyy-mm-dd HH:nn:ss", "UTC" ) ).toBe( "2026-11-20 13:05:08" );
				expect( w.heads ).toBe( [ "https://repo.example.invalid/org/lucee/lucee/7.1.2.195/lucee-7.1.2.195.pom" ] );

				// cached: no detail and no request again
				rd.get( "7.1.2.195" );
				rd.get( "7.1.2.195" );
				expect( ArrayLen( w.heads ) ).toBe( 1 );
				expect( ArrayLen( w.details ) ).toBe( 1 );
			});

			it( title="without any file URL in the detail, the pom of the Lucee repository", body=function() {
				var w = _world();
				var rd = _new( w );

				expect( IsDate( rd.get( "8.0.0.310" ) ) ).toBeTrue();
				expect( w.heads ).toBe( [ "https://mixed.example.invalid/org/lucee/lucee/8.0.0.310/lucee-8.0.0.310.pom" ] );
			});

			it( title="a listed version without a date is a miss that is asked again only after a while", body=function() {
				var w = _world();
				var rd = _new( w, 300 );

				expect( rd.get( "7.0.2.106" ) ).toBe( "" );
				expect( rd.get( "7.0.2.106" ) ).toBe( "" );
				expect( ArrayLen( w.heads ) ).toBe( 1 );

				// with no time to keep a miss it is asked again
				var w2 = _world();
				var rd2 = _new( w2, 0 );
				rd2.get( "7.0.2.106" );
				sleep( 5 );
				rd2.get( "7.0.2.106" );
				expect( ArrayLen( w2.heads ) ).toBe( 2 );
			});

			it( title="a failing HEAD is a miss, not an error", body=function() {
				var w = _world();
				w.throwOnHead = true;
				var rd = _new( w );

				expect( rd.get( "7.1.2.195" ) ).toBe( "" );
			});

			it( title="the date of a snapshot is kept only for a while, it can be published again", body=function() {
				var w = _world();
				var rd = new releasedateservices.CoreReleaseDate( coreVersions=_coreVersions( w ), catalog=_catalog( w ), snapshotSeconds=0, head=_head( w ) );

				expect( IsDate( rd.get( "8.0.0.311-SNAPSHOT" ) ) ).toBeTrue();
				sleep( 5 );
				rd.get( "8.0.0.311-SNAPSHOT" );
				expect( ArrayLen( w.details ) ).toBe( 2 );
			});

			it( title="when the version list cannot be read, the detail is still asked", body=function() {
				var w = _world();
				w.listFails = true;
				var rd = _new( w );

				expect( IsDate( rd.get( "6.2.3.35" ) ) ).toBeTrue();
			});

			it( title="the REST function uses the cached lookup and answers a 404, not the slow legacy MavenRepo", body=function() {
				var fn = Mid( src, Find( "remote function getDate(", src ), 1200 );
				fn = Left( fn, Find( "remote function readGetOnlyForDebugging", fn ) - 1 );

				expect( fn ).toInclude( "coreReleaseDate.get(" );
				expect( fn ).toInclude( 'statuscode="404"' );
				expect( fn ).notToInclude( "MavenRepo" );
			});

		});
	}

	private function _new( required struct w, numeric missSeconds=300 ) {
		return new releasedateservices.CoreReleaseDate(
			  coreVersions = _coreVersions( w )
			, catalog      = _catalog( w )
			, mixedRepo    = "https://mixed.example.invalid"
			, missSeconds  = arguments.missSeconds
			, head         = _head( w )
		);
	}

	private struct function _world() {
		return {
			  heads       : []
			, details     : []
			, throwOnHead : false
			, listFails   : false
			, versions    : [ "6.2.3.34-SNAPSHOT", "6.2.3.35", "7.0.2.106", "7.1.2.195", "8.0.0.310", "8.0.0.311-SNAPSHOT" ]
			, detail      : {
				  "6.2.3.35"           : { jar="https://repo.example.invalid/org/lucee/lucee/6.2.3.35/lucee-6.2.3.35.jar", lastModified="October, 31 2025 09:08:04 +0000" }
				, "7.1.2.195"          : { pom="https://repo.example.invalid/org/lucee/lucee/7.1.2.195/lucee-7.1.2.195.pom", jar="https://repo.example.invalid/org/lucee/lucee/7.1.2.195/lucee-7.1.2.195.jar" }
				, "7.0.2.106"          : { pom="https://repo.example.invalid/org/lucee/lucee/7.0.2.106/lucee-7.0.2.106.pom" }
				, "8.0.0.311-SNAPSHOT" : { jar="https://snap.example.invalid/lucee-8.0.0.311-20261126.235223-1.jar", lastModified=ParseDateTime( "November, 26 2026 23:52:23 +0000" ) }
			}
			, lastModified : {
				  "https://repo.example.invalid/org/lucee/lucee/7.1.2.195/lucee-7.1.2.195.pom"  : "Fri, 20 Nov 2026 13:05:08 GMT"
				, "https://mixed.example.invalid/org/lucee/lucee/8.0.0.310/lucee-8.0.0.310.pom" : "Fri, 20 Nov 2026 14:22:26 GMT"
			}
		};
	}

	private struct function _coreVersions( required struct w ) {
		var real = new releasedateservices.CoreVersions( flatSource="" );
		return {
			  isOffered   : function( version ) { return real.isOffered( version ); }
			, getVersions : function() {
				if ( w.listFails ) throw( message="no list" );
				var res = StructNew( "linked" );
				loop array=w.versions item="local.v" {
					res[ v ] = { version=v };
				}
				return res;
			}
		};
	}

	private struct function _catalog( required struct w ) {
		return {
			getVersionDetail : function( version ) {
				ArrayAppend( w.details, version );
				return Duplicate( w.detail[ version ] ?: {} );
			}
		};
	}

	private function _head( required struct w ) {
		return function( target, timeout ) {
			ArrayAppend( w.heads, target );
			if ( w.throwOnHead ) throw( message="connect timed out" );
			return w.lastModified[ target ] ?: "";
		};
	}

}
