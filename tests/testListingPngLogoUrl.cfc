component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "png-logo-url-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );

		// 1x1 PNG, used only when the embedded logo should be read
		variables.pngBytes = ToBinary( "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	private boolean function noImageFunctions() {
		return !StructKeyExists( GetFunctionList(), "ImageRead" ) || !StructKeyExists( GetFunctionList(), "ImageWrite" );
	}

	function run( testResults, testBox ) {

		describe( "listing logos: a manifest image that is already a .png URL is passed through", function() {

			it( title="puts an http(s) URL ending in .png into the image column as it is, and does not read META-INF/logo.png", body=function() {
				var url    = "https://cdn.example.invalid/logos/demo.png";
				var reader = _reader([
					_spec( "url-extension-1.0.0.1.lex", "11111111-1111-1111-1111-111111111111", "1.0.0.1", url, "not a png" )
				]);
				var listed = reader.list( type="all", withLogo=true );
				var detail = reader.getExtensionDetail( id="11111111-1111-1111-1111-111111111111", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( listed.image[ 1 ] ).toBe( url );
				expect( detail[ "image" ] ).toBe( url );
			});

			it( title="ignores the query string and is case-insensitive when checking for .png", body=function() {
				var url    = "https://cdn.example.invalid/logos/DEMO.PNG?v=2&cache=bust";
				var reader = _reader([
					_spec( "case-extension-1.0.0.1.lex", "22222222-2222-2222-2222-222222222222", "1.0.0.1", url, "not a png" )
				]);
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.image[ 1 ] ).toBe( url );
			});

			it( title="leaves a URL that does not end in .png to the embedded logo, as before", skip=noImageFunctions(), body=function() {
				var reader = _reader([
					_spec( "gif-extension-1.0.0.1.lex", "33333333-3333-3333-3333-333333333333", "1.0.0.1", "https://cdn.example.invalid/logos/demo.gif", variables.pngBytes )
				]);
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( Len( listed.image[ 1 ] ) ).toBeGT( 0 );
				expect( ReFindNoCase( "^https?://", listed.image[ 1 ] ) ).toBe( 0 );
			});

			it( title="still embeds META-INF/logo.png as base64 when the manifest has no image URL", skip=noImageFunctions(), body=function() {
				var reader = _reader([
					_spec( "embed-extension-1.0.0.1.lex", "44444444-4444-4444-4444-444444444444", "1.0.0.1", "", variables.pngBytes )
				]);
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( Len( listed.image[ 1 ] ) ).toBeGT( 0 );
				expect( ReFindNoCase( "^https?://", listed.image[ 1 ] ) ).toBe( 0 );
			});

			it( title="withLogo=false still strips a passed-through logo URL", body=function() {
				var reader = _reader([
					_spec( "strip-extension-1.0.0.1.lex", "55555555-5555-5555-5555-555555555555", "1.0.0.1", "https://cdn.example.invalid/logo.png", "not a png" )
				]);
				var listed = reader.list( type="all", withLogo=false );
				var detail = reader.getExtensionDetail( id="55555555-5555-5555-5555-555555555555", withLogo=false );

				expect( listed.image[ 1 ] ).toBe( "" );
				expect( detail[ "image" ] ).toBe( "" );
			});

			it( title="LISTING_LOGO_MAX_SIZE leaves a passed-through .png URL as it is", body=function() {
				var url    = "https://cdn.example.invalid/logos/demo.png";
				var reader = _reader([
					_spec( "thumb-extension-1.0.0.1.lex", "66666666-6666-6666-6666-666666666666", "1.0.0.1", url, "not a png" )
				], "260x100");
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.image[ 1 ] ).toBe( url );
			});

		});
	}

	private struct function _spec( required string fileName, required string id, required string version, required string imageUrl, required any logoBytes ) {
		var spec = {
			  fileName  = arguments.fileName
			, id        = arguments.id
			, version   = arguments.version
			, logoBytes = arguments.logoBytes
		};
		spec[ "imageUrl" ] = arguments.imageUrl;

		return spec;
	}

	private function _reader( required array specs, string maxSize="" ) {
		var root = variables.work & "root-" & CreateUniqueId() & "/";
		DirectoryCreate( root, true );

		for ( var spec in arguments.specs ) {
			_createLex( root & spec.fileName, spec );
		}

		var reader = new services.ExtensionMetadataReader( s3root=root, listingLogoMaxSize=arguments.maxSize );
		reader.loadMeta();

		return reader;
	}

	private void function _createLex( required string path, required struct spec ) {
		var src = variables.work & "src-" & CreateUniqueId() & "/";
		DirectoryCreate( src & "META-INF", true );

		var manifest = "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.spec.id & Chr( 13 ) & Chr( 10 )
			& "name: Logo URL test" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.spec.version & Chr( 13 ) & Chr( 10 );
		if ( Len( arguments.spec[ "imageUrl" ] ) ) {
			manifest &= "image: " & arguments.spec[ "imageUrl" ] & Chr( 13 ) & Chr( 10 );
		}
		manifest &= Chr( 13 ) & Chr( 10 );
		FileWrite( src & "META-INF/MANIFEST.MF", manifest );

		if ( StructKeyExists( arguments.spec, "logoBytes" ) ) {
			FileWrite( src & "META-INF/logo.png", arguments.spec.logoBytes );
		}

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
