component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "HttpCaching: ETags and conditional requests", function() {

			it( title="builds a weak ETag that changes with the seed", body=function() {
				var a = services.HttpCaching::weakEtag( "one" );
				var b = services.HttpCaching::weakEtag( "two" );

				expect( a ).toMatch( '^W/"[0-9a-f]{32}"$' );
				expect( a ).toBe( services.HttpCaching::weakEtag( "one" ) );
				expect( a ).notToBe( b );
			});

			it( title="matches If-None-Match weakly, in a list and for *", body=function() {
				var etag = services.HttpCaching::weakEtag( "x" );
				var opaque = Mid( etag, 3 );

				expect( services.HttpCaching::matchesIfNoneMatch( etag, etag ) ).toBeTrue();
				expect( services.HttpCaching::matchesIfNoneMatch( opaque, etag ) ).toBeTrue();
				expect( services.HttpCaching::matchesIfNoneMatch( '"other", ' & etag, etag ) ).toBeTrue();
				expect( services.HttpCaching::matchesIfNoneMatch( "*", etag ) ).toBeTrue();
				expect( services.HttpCaching::matchesIfNoneMatch( '"other"', etag ) ).toBeFalse();
				expect( services.HttpCaching::matchesIfNoneMatch( "", etag ) ).toBeFalse();
			});

			it( title="If-None-Match decides over If-Modified-Since", body=function() {
				var etag  = services.HttpCaching::weakEtag( "x" );
				var built = DateAdd( "h", -1, Now() );
				var later = services.HttpCaching::httpDate( Now() );

				expect( services.HttpCaching::isNotModified( ifNoneMatch='"other"', ifModifiedSince=later, etag=etag, lastModified=built ) ).toBeFalse();
				expect( services.HttpCaching::isNotModified( ifNoneMatch=etag, etag=etag, lastModified=built ) ).toBeTrue();
			});

			it( title="If-Modified-Since: not modified when the response is not newer, to the second", body=function() {
				var etag  = services.HttpCaching::weakEtag( "x" );
				var built = DateAdd( "h", -1, Now() );

				expect( services.HttpCaching::isNotModified( ifModifiedSince=services.HttpCaching::httpDate( Now() ), etag=etag, lastModified=built ) ).toBeTrue();
				expect( services.HttpCaching::isNotModified( ifModifiedSince=services.HttpCaching::httpDate( built ), etag=etag, lastModified=built ) ).toBeTrue();
				expect( services.HttpCaching::isNotModified( ifModifiedSince=services.HttpCaching::httpDate( DateAdd( "h", -2, Now() ) ), etag=etag, lastModified=built ) ).toBeFalse();
				expect( services.HttpCaching::isNotModified( ifModifiedSince="not a date", etag=etag, lastModified=built ) ).toBeFalse();
				expect( services.HttpCaching::isNotModified( etag=etag, lastModified=built ) ).toBeFalse();
			});

			it( title="Cache-Control is public with the configured max-age", body=function() {
				expect( services.HttpCaching::cacheControl() ).toBe( "public, max-age=" & services.HttpCaching::maxAge() );
				expect( services.HttpCaching::maxAge() ).toBeGTE( 0 );
			});

		});
	}

}
