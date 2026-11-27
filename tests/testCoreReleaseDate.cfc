component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "CoreReleaseDate: fast getdate lookup", function() {

			it( title="an unlisted version such as 6.2.3.34 throws NotFound and makes no catalog detail or HTTP request", body=function() {
				var calls = { detail=0, head=0 };
				var svc = _new(
					  list   = [ "6.2.3.35", "6.2.3.34-SNAPSHOT", "8.0.0.310" ]
					, detail = function( version ) { calls.detail++; return { lastModified=Now() }; }
					, head   = function( required string fileUrl, required numeric timeout ) { calls.head++; return { status=200, lastModified=Now() }; }
				);

				expect( function() { svc.get( "6.2.3.34" ); } )
					.toThrow( message="", type="CoreReleaseDate.NotFound" );
				expect( calls.detail ).toBe( 0 );
				expect( calls.head ).toBe( 0 );
			});

			it( title="uses lastModified from the catalog and does not make an HTTP request", body=function() {
				var calls = { head=0 };
				var date = CreateDateTime( 2025, 10, 31, 9, 8, 4 );
				var svc = _new(
					  list   = [ "8.0.0.310" ]
					, detail = function( version ) { return { lastModified=date, jar="https://example.test/lucee-8.0.0.310.jar" }; }
					, head   = function( required string fileUrl, required numeric timeout ) { calls.head++; return { status=200, lastModified=Now() }; }
				);

				var result = svc.get( "8.0.0.310" );
				expect( IsDate( result ) ).toBeTrue();
				expect( DateCompare( result, date ) ).toBe( 0 );
				expect( calls.head ).toBe( 0 );
				// download.cfc reads deserializeJson of this payload
				var json = SerializeJson( result );
				expect( Left( json, 1 ) ).toBe( '"' );
				expect( IsDate( DeserializeJson( json ) ) ).toBeTrue();
				expect( DateCompare( ParseDateTime( DeserializeJson( json ) ), date ) ).toBe( 0 );
			});

			it( title="falls back to one HEAD request with the configured timeout when the catalog has no lastModified", body=function() {
				var calls = { head=0, timeout=0, fileUrl="" };
				var date = CreateDateTime( 2025, 10, 31, 9, 8, 4 );
				var svc = _new(
					  list    = [ "6.2.3.35" ]
					, detail  = function( version ) { return { jar="https://example.test/org/lucee/lucee/6.2.3.35/lucee-6.2.3.35.jar" }; }
					, head    = function( required string fileUrl, required numeric timeout ) {
						calls.head++;
						calls.timeout = arguments.timeout;
						calls.fileUrl = arguments.fileUrl;
						return { status=200, lastModified=date };
					}
					, timeout = 5
				);

				var result = svc.get( "6.2.3.35" );
				expect( DateCompare( result, date ) ).toBe( 0 );
				expect( calls.head ).toBe( 1 );
				expect( calls.timeout ).toBe( 5 );
				expect( calls.fileUrl ).toBe( "https://example.test/org/lucee/lucee/6.2.3.35/lucee-6.2.3.35.jar" );
			});

			it( title="HEADs the Maven layout pom when the catalog detail has no file URL", body=function() {
				var calls = { fileUrl="" };
				var date = CreateDateTime( 2024, 1, 2, 3, 4, 5 );
				var svc = _new(
					  list      = [ "7.1.2.195" ]
					, detail    = function( version ) { return {}; }
					, head      = function( required string fileUrl, required numeric timeout ) { calls.fileUrl = arguments.fileUrl; return { status=200, lastModified=date }; }
					, mixedRepo = "https://maven.lucee-services.com/"
				);

				expect( DateCompare( svc.get( "7.1.2.195" ), date ) ).toBe( 0 );
				expect( calls.fileUrl ).toBe( "https://maven.lucee-services.com/org/lucee/lucee/7.1.2.195/lucee-7.1.2.195.pom" );
			});

			it( title="caches a release date indefinitely, a SNAPSHOT for an hour, and a listed miss for 5 minutes", body=function() {
				var clock = { now=CreateDateTime( 2026, 11, 27, 12, 0, 0 ) };
				var heads = { "8.0.0.310"=0, "8.0.1.107-SNAPSHOT"=0, "7.0.0.395"=0 };
				var svc = _new(
					  list  = [ "8.0.0.310", "8.0.1.107-SNAPSHOT", "7.0.0.395" ]
					, detail = function( version ) { return {}; }
					, head   = function( required string fileUrl, required numeric timeout ) {
						if ( Find( "8.0.0.310", arguments.fileUrl ) ) {
							heads[ "8.0.0.310" ]++;
							return { status=200, lastModified=CreateDateTime( 2026, 1, 1, 0, 0, 0 ) };
						}
						if ( Find( "8.0.1.107-SNAPSHOT", arguments.fileUrl ) ) {
							heads[ "8.0.1.107-SNAPSHOT" ]++;
							return { status=200, lastModified=CreateDateTime( 2026, 2, 2, 0, 0, 0 ) };
						}
						heads[ "7.0.0.395" ]++;
						return { status=404, lastModified="" };
					}
					, nowFn = function() { return clock.now; }
				);

				svc.get( "8.0.0.310" );
				svc.get( "8.0.1.107-SNAPSHOT" );
				expect( svc.get( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 1 );
				expect( heads[ "7.0.0.395" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 4, clock.now );
				svc.get( "8.0.0.310" );
				svc.get( "8.0.1.107-SNAPSHOT" );
				expect( svc.get( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 1 );
				expect( heads[ "7.0.0.395" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 2, clock.now ); // 6 minutes from the start: listed miss expires
				expect( svc.get( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "7.0.0.395" ] ).toBe( 2 );
				svc.get( "8.0.0.310" );
				svc.get( "8.0.1.107-SNAPSHOT" );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 55, clock.now ); // 61 minutes from the start: SNAPSHOT expires, release does not
				svc.get( "8.0.0.310" );
				svc.get( "8.0.1.107-SNAPSHOT" );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 2 );
			});

			it( title="a failed or header-less HEAD is a listed miss, not a 404, and is retried after 5 minutes", body=function() {
				var clock = { now=CreateDateTime( 2026, 11, 27, 12, 0, 0 ) };
				var heads = { n=0 };
				var svc = _new(
					  list   = [ "8.0.0.310" ]
					, detail = function( version ) { return {}; }
					, head   = function( required string fileUrl, required numeric timeout ) {
						heads.n++;
						return { status=0, lastModified="" };
					}
					, nowFn  = function() { return clock.now; }
				);

				expect( svc.get( "8.0.0.310" ) ).toBe( "" );
				expect( heads.n ).toBe( 1 );
				clock.now = DateAdd( "s", 299, clock.now );
				expect( svc.get( "8.0.0.310" ) ).toBe( "" );
				expect( heads.n ).toBe( 1 );
				clock.now = DateAdd( "s", 1, clock.now ); // 300 seconds: the miss expires
				expect( svc.get( "8.0.0.310" ) ).toBe( "" );
				expect( heads.n ).toBe( 2 );
			});

		});
	}

	private function _new(
		  array   list
		, any     detail
		, any     head
		, numeric timeout   = 5
		, string  mixedRepo = "https://maven.lucee-services.com/"
		, any     nowFn
	) {
		var versions = arguments.list;
		var catalog = {
			  getVersionList   = function() { return versions; }
			, getVersionDetail = arguments.detail
		};

		return new services.CoreReleaseDate(
			  catalog    = catalog
			, httpClient = { head=arguments.head }
			, mixedRepo  = arguments.mixedRepo
			, timeout    = arguments.timeout
			, nowFn      = arguments.nowFn ?: function() { return Now(); }
		);
	}

}
