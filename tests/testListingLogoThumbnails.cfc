component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work    = GetTempDirectory() & "listing-logos-" & CreateUniqueId() & "/";
		variables.fixture = DeserializeJSON( FileRead( dir & "staticArtifacts/testExtensionCoreVersions.json" ), false );
		DirectoryCreate( variables.work, true );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	private boolean function noImageFunctions() {
		return !StructKeyExists( GetFunctionList(), "ImageRead" ) || !StructKeyExists( GetFunctionList(), "ImageScaleToFit" );
	}

	function run( testResults, testBox ) {

		describe( "listing logos: scaled down only when LISTING_LOGO_MAX_SIZE is set", function() {

			it( title="without a maximum size the logos are served as they are", body=function() {
				var plain  = _reader( "" ).list( type="all", withLogo=true );
				var images = _images( variables.fixture );

				for ( var i=1; i<=QueryRecordCount( plain ); i++ ) {
					expect( ArrayFind( images, plain.image[ i ] ) ).toBeGT( 0 );
				}
			});

			it( title="with a maximum size the larger logos are scaled to fit it and get smaller", skip=noImageFunctions(), body=function() {
				var plain  = _reader( "" ).list( type="all", withLogo=true );
				var shrunk = _reader( "260x100" ).list( type="all", withLogo=true );

				expect( QueryRecordCount( shrunk ) ).toBe( QueryRecordCount( plain ) );
				var smaller = 0;
				for ( var i=1; i<=QueryRecordCount( shrunk ); i++ ) {
					expect( Len( shrunk.image[ i ] ) ).toBeLTE( Len( plain.image[ i ] ) );
					if ( Len( shrunk.image[ i ] ) && shrunk.image[ i ] != plain.image[ i ] ) {
						var img = ImageRead( ToBinary( shrunk.image[ i ] ) );
						expect( ImageGetWidth( img ) ).toBeLTE( 260 );
						expect( ImageGetHeight( img ) ).toBeLTE( 100 );
						smaller++;
					}
				}
				expect( smaller ).toBeGT( 0 );
			});

			it( title="the listing can be built more than once on the same reader (with and without a maximum size)", body=function() {
				for ( var size in [ "", "260x100" ] ) {
					var reader = _reader( size );
					var first  = reader.list( type="all", withLogo=true );
					var second = reader.list( type="all", withLogo=true );
					var third  = reader.list( type="release", withLogo=true );
					expect( QueryRecordCount( second ) ).toBe( QueryRecordCount( first ) );
					expect( QueryRecordCount( third ) ).toBeGT( 0 );
				}
			});

			it( title="withLogo=false still strips the logos", body=function() {
				var none = _reader( "260x100" ).list( type="all", withLogo=false );
				for ( var i=1; i<=QueryRecordCount( none ); i++ ) {
					expect( none.image[ i ] ).toBe( "" );
				}
			});

			it( title="a logo that can't be read is kept as it is", body=function() {
				var thumbs = new services.LogoThumbnails( "260x100" );
				expect( thumbs.shrink( "not an image" ) ).toBe( "not an image" );
				expect( thumbs.shrink( "https://example.invalid/logo.png" ) ).toBe( "https://example.invalid/logo.png" );
				expect( new services.LogoThumbnails( "" ).isEnabled() ).toBeFalse();
				expect( new services.LogoThumbnails( "big" ).isEnabled() ).toBeFalse();
			});

		});
	}

	private function _reader( required string maxSize ) {
		var reader = new services.ExtensionMetadataReader( s3root=variables.work & CreateUniqueId(), listingLogoMaxSize=arguments.maxSize );
		reader.loadMeta( Duplicate( variables.fixture ) );

		return reader;
	}

	private array function _images( required query q ) {
		var images = [];
		for ( var i=1; i<=QueryRecordCount( arguments.q ); i++ ) {
			ArrayAppend( images, arguments.q.image[ i ] );
		}

		return images;
	}

}
