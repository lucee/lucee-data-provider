component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/download" : ExpandPath( dir & "../apps/download" )
		};
	}

	function afterEach() {
		if ( !IsNull( application.mavenDates ) ) {
			StructClear( application.mavenDates );
		}
	}

	function run( testResults, testBox ) {

		describe( "download.getReleaseDate: Last-Modified from a jar HEAD, not getdate", function() {

			it( title="HEADs the Maven jar and returns LsDateFormat of Last-Modified, with a 5 second timeout", body=function() {
				var calls = { n=0, url="", timeout=0 };
				var lastMod = "Fri, 31 Oct 2025 09:08:04 GMT";
				var dl = _new( function( url, timeout ) {
					calls.n++;
					calls.url = url;
					calls.timeout = timeout;
					return { status=200, lastModified=lastMod };
				} );

				var result = dl.getReleaseDate( "8.0.0.310" );
				expect( result ).toBe( LsDateFormat( ParseDateTime( lastMod ) ) );
				expect( calls.n ).toBe( 1 );
				expect( calls.timeout ).toBe( 5 );
				expect( calls.url ).toBe( "https://maven.lucee-services.com/org/lucee/lucee/8.0.0.310/lucee-8.0.0.310.jar" );
			});

			it( title="does not call the update provider getdate endpoint", body=function() {
				var urls = [];
				var dl = _new( function( url, timeout ) {
					ArrayAppend( urls, url );
					return { status=200, lastModified="Fri, 31 Oct 2025 09:08:04 GMT" };
				} );

				dl.getReleaseDate( "6.2.3.35" );
				expect( ArrayLen( urls ) ).toBe( 1 );
				expect( urls[ 1 ] ).notToInclude( "getdate" );
				expect( urls[ 1 ] ).notToInclude( "update.lucee.org" );
			});

			it( title="fails soft to an empty date when the HEAD fails or has no Last-Modified", body=function() {
				var dl = _new( function( url, timeout ) {
					return { status=404, lastModified="" };
				} );
				expect( dl.getReleaseDate( "9.9.9.9" ) ).toBe( "" );

				dl = _new( function( url, timeout ) {
					throw( message="connection timed out" );
				} );
				expect( dl.getReleaseDate( "8.0.0.310" ) ).toBe( "" );
			});

			it( title="caches a release date indefinitely, a SNAPSHOT for an hour, and a miss for 5 minutes", body=function() {
				var clock = { now=CreateDateTime( 2026, 11, 27, 12, 0, 0 ) };
				var heads = { "8.0.0.310"=0, "8.0.1.107-SNAPSHOT"=0, "7.0.0.395"=0 };
				var lastMod = "Fri, 31 Oct 2025 09:08:04 GMT";
				var dl = _new(
					head = function( url, timeout ) {
						if ( Find( "8.0.0.310", url ) ) {
							heads[ "8.0.0.310" ]++;
							return { status=200, lastModified=lastMod };
						}
						if ( Find( "8.0.1.107-SNAPSHOT", url ) ) {
							heads[ "8.0.1.107-SNAPSHOT" ]++;
							return { status=200, lastModified=lastMod };
						}
						heads[ "7.0.0.395" ]++;
						return { status=0, lastModified="" };
					}
					, nowFn = function() { return clock.now; }
				);

				var releaseDate = LsDateFormat( ParseDateTime( lastMod ) );
				expect( dl.getReleaseDate( "8.0.0.310" ) ).toBe( releaseDate );
				expect( dl.getReleaseDate( "8.0.1.107-SNAPSHOT" ) ).toBe( releaseDate );
				expect( dl.getReleaseDate( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 1 );
				expect( heads[ "7.0.0.395" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 4, clock.now );
				expect( dl.getReleaseDate( "8.0.0.310" ) ).toBe( releaseDate );
				expect( dl.getReleaseDate( "8.0.1.107-SNAPSHOT" ) ).toBe( releaseDate );
				expect( dl.getReleaseDate( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "7.0.0.395" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 2, clock.now ); // 6 minutes: miss expires
				expect( dl.getReleaseDate( "7.0.0.395" ) ).toBe( "" );
				expect( heads[ "7.0.0.395" ] ).toBe( 2 );
				expect( dl.getReleaseDate( "8.0.1.107-SNAPSHOT" ) ).toBe( releaseDate );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 1 );

				clock.now = DateAdd( "n", 55, clock.now ); // 61 minutes: SNAPSHOT expires, release does not
				expect( dl.getReleaseDate( "8.0.0.310" ) ).toBe( releaseDate );
				expect( heads[ "8.0.0.310" ] ).toBe( 1 );
				expect( dl.getReleaseDate( "8.0.1.107-SNAPSHOT" ) ).toBe( releaseDate );
				expect( heads[ "8.0.1.107-SNAPSHOT" ] ).toBe( 2 );
			});

		});
	}

	private function _new( required any head, any nowFn ) {
		var dl = new download.download();
		dl.httpClient = { head=arguments.head };
		if ( !IsNull( arguments.nowFn ) ) {
			dl.nowFn = arguments.nowFn;
		}
		return dl;
	}

}
