component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services"   : ExpandPath( dir & "../apps/updateserver-maven/services" ),
			"/logourlstub": dir
		};

		variables.work = GetTempDirectory() & "artifact-logo-url-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );

		// 1x1 PNG, used only when the embedded logo should be read
		variables.pngBytes = ToBinary( "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" );
		variables.defaultLogoUrl = "https://cdn.lucee.org/artifacts/org-lucee-demo-extension.png";
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

		describe( "listing logos: the public artifact logo URL is used when that file is there", function() {

			it( title="puts the artifact logo URL into the image column and does not read META-INF/logo.png", body=function() {
				var probe = _probe({ "#variables.defaultLogoUrl#": true });
				var reader = _reader([
					_spec( "demo-extension-1.0.0.1.lex", "11111111-1111-1111-1111-111111111111", "1.0.0.1", "org.lucee", "demo-extension", "", "not a png" )
				], { artifactLogoProbe=probe });
				var listed = reader.list( type="all", withLogo=true );
				var detail = reader.getExtensionDetail( id="11111111-1111-1111-1111-111111111111", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( listed.image[ 1 ] ).toBe( variables.defaultLogoUrl );
				expect( detail[ "image" ] ).toBe( variables.defaultLogoUrl );
				expect( ArrayLen( probe.getCalls() ) ).toBeGT( 0 );
			});

			it( title="builds the URL like Lucee 8: dots in the group and artifact become dashes, no version in the path", body=function() {
				var logoSrc = "https://cdn.lucee.org/artifacts/com-example-foo-bar-baz-extension.png";
				var reader = _reader([
					_spec( "bar.baz-extension-2.0.0.1.lex", "22222222-2222-2222-2222-222222222222", "2.0.0.1", "com.example.foo", "bar.baz-extension", "", "" )
				], { artifactLogoProbe={ "#logoSrc#": true } });

				expect( reader.list( type="all", withLogo=true ).image[ 1 ] ).toBe( logoSrc );
			});

			it( title="falls back to the embedded logo when the artifact logo is not there", skip=noImageFunctions(), body=function() {
				var reader = _reader([
					_spec( "missing-extension-1.0.0.1.lex", "33333333-3333-3333-3333-333333333333", "1.0.0.1", "org.lucee", "missing-extension", "", variables.pngBytes )
				], { artifactLogoProbe={ "https://cdn.lucee.org/artifacts/org-lucee-missing-extension.png": false } });
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( Len( listed.image[ 1 ] ) ).toBeGT( 0 );
				expect( ReFindNoCase( "^https?://", listed.image[ 1 ] ) ).toBe( 0 );
			});

			it( title="still embeds META-INF/logo.png as base64 when there are no maven coordinates", skip=noImageFunctions(), body=function() {
				var probe = _probe({});
				var reader = _reader([
					_spec( "plain-extension-1.0.0.1.lex", "44444444-4444-4444-4444-444444444444", "1.0.0.1", "", "", "", variables.pngBytes )
				], { artifactLogoProbe=probe });
				var listed = reader.list( type="all", withLogo=true );

				expect( listed.recordCount ).toBe( 1 );
				expect( Len( listed.image[ 1 ] ) ).toBeGT( 0 );
				expect( ReFindNoCase( "^https?://", listed.image[ 1 ] ) ).toBe( 0 );
				expect( ArrayLen( probe.getCalls() ) ).toBe( 0 );
			});

			it( title="keeps a custom manifest .png URL as it is, even when an artifact logo is also there", body=function() {
				var custom = "https://example.invalid/custom-logo.png";
				var reader = _reader([
					_spec( "custom-extension-1.0.0.1.lex", "55555555-5555-5555-5555-555555555555", "1.0.0.1", "org.lucee", "custom-extension", custom, "not a png" )
				], { artifactLogoProbe={ "#variables.defaultLogoUrl#": true, "https://cdn.lucee.org/artifacts/org-lucee-custom-extension.png": true } });

				expect( reader.list( type="all", withLogo=true ).image[ 1 ] ).toBe( custom );
			});

			it( title="replaces a GitHub raw manifest logo with the artifact logo URL when that file is there", body=function() {
				var raw = "https://raw.githubusercontent.com/lucee/demo/master/source/images/logo.png";
				var hosted = "https://cdn.lucee.org/artifacts/org-lucee-github-extension.png";
				var reader = _reader([
					_spec( "github-extension-1.0.0.1.lex", "66666666-6666-6666-6666-666666666666", "1.0.0.1", "org.lucee", "github-extension", raw, "not a png" )
				], { artifactLogoProbe={ "#hosted#": true } });

				expect( reader.list( type="all", withLogo=true ).image[ 1 ] ).toBe( hosted );
			});

			it( title="keeps a GitHub raw manifest logo when the artifact logo is not there", body=function() {
				var raw = "https://raw.githubusercontent.com/lucee/demo/master/source/images/logo.png";
				var reader = _reader([
					_spec( "githubmiss-extension-1.0.0.1.lex", "77777777-7777-7777-7777-777777777777", "1.0.0.1", "org.lucee", "githubmiss-extension", raw, "not a png" )
				], { artifactLogoProbe={ "https://cdn.lucee.org/artifacts/org-lucee-githubmiss-extension.png": false } });

				expect( reader.list( type="all", withLogo=true ).image[ 1 ] ).toBe( raw );
			});

			it( title="withLogo=false still strips an artifact logo URL", body=function() {
				var reader = _reader([
					_spec( "strip-extension-1.0.0.1.lex", "88888888-8888-8888-8888-888888888888", "1.0.0.1", "org.lucee", "strip-extension", "", "not a png" )
				], { artifactLogoProbe={ "https://cdn.lucee.org/artifacts/org-lucee-strip-extension.png": true } });
				var listed = reader.list( type="all", withLogo=false );
				var detail = reader.getExtensionDetail( id="88888888-8888-8888-8888-888888888888", withLogo=false );

				expect( listed.image[ 1 ] ).toBe( "" );
				expect( detail[ "image" ] ).toBe( "" );
			});

			it( title="LISTING_LOGO_MAX_SIZE leaves an artifact logo URL as it is", body=function() {
				var reader = _reader([
					_spec( "thumb-extension-1.0.0.1.lex", "99999999-9999-9999-9999-999999999999", "1.0.0.1", "org.lucee", "thumb-extension", "", "not a png" )
				], { artifactLogoProbe={ "https://cdn.lucee.org/artifacts/org-lucee-thumb-extension.png": true }, listingLogoMaxSize="260x100" });

				expect( reader.list( type="all", withLogo=true ).image[ 1 ] ).toBe( "https://cdn.lucee.org/artifacts/org-lucee-thumb-extension.png" );
			});

			it( title="listing and detail requests do not check whether the logo URL is there", body=function() {
				var probe = _probe({ "#variables.defaultLogoUrl#": true });
				var reader = _reader([
					_spec( "demo-extension-1.0.0.1.lex", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "1.0.0.1", "org.lucee", "demo-extension", "", "not a png" )
				], { artifactLogoProbe=probe });
				var afterLoad = ArrayLen( probe.getCalls() );

				reader.list( type="all", withLogo=true );
				reader.list( type="all", withLogo=true );
				reader.getExtensionDetail( id="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", withLogo=true );

				expect( afterLoad ).toBeGT( 0 );
				expect( ArrayLen( probe.getCalls() ) ).toBe( afterLoad );
			});

			it( title="a later load replaces a stored base64 logo with the artifact URL without reading the lex again", skip=noImageFunctions(), body=function() {
				var spec = _spec( "rebuild-extension-1.0.0.1.lex", "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "1.0.0.1", "org.lucee", "rebuild-extension", "", variables.pngBytes );
				var root = variables.work & "root-" & CreateUniqueId() & "/";
				DirectoryCreate( root, true );
				_createLex( root & spec.fileName, spec );

				var first = new services.ExtensionMetadataReader(
					  s3root            = root
					, artifactLogoProbe = { "https://cdn.lucee.org/artifacts/org-lucee-rebuild-extension.png": false }
				);
				first.loadMeta();
				var firstImage = first.list( type="all", withLogo=true ).image[ 1 ];
				expect( ReFindNoCase( "^https?://", firstImage ) ).toBe( 0 );
				expect( Len( firstImage ) ).toBeGT( 0 );

				// the lex is no longer needed: the second load serves the persisted meta
				FileDelete( root & spec.fileName );

				var second = new services.ExtensionMetadataReader(
					  s3root            = root
					, mavenSource       = new logourlstub.ListingArtifactLogoMavenStub( spec.fileName, spec.artifactId, spec.version, spec.groupId )
					, artifactLogoProbe = { "https://cdn.lucee.org/artifacts/org-lucee-rebuild-extension.png": true }
				);
				second.loadMeta();

				expect( second.list( type="all", withLogo=true ).image[ 1 ] ).toBe( "https://cdn.lucee.org/artifacts/org-lucee-rebuild-extension.png" );
			});

		});
	}

	private struct function _spec( required string fileName, required string id, required string version, required string groupId, required string artifactId, required string imageUrl, required any logoBytes ) {
		var spec = {
			  fileName   = arguments.fileName
			, id         = arguments.id
			, version    = arguments.version
			, groupId    = arguments.groupId
			, artifactId = arguments.artifactId
			, logoBytes  = arguments.logoBytes
		};
		spec[ "imageUrl" ] = arguments.imageUrl;

		return spec;
	}

	private function _probe( required struct map ) {
		var calls = [];
		var data  = arguments.map;

		return {
			  exists   = function( required string logoUrl ) {
				ArrayAppend( calls, arguments.logoUrl );
				return IsBoolean( data[ arguments.logoUrl ] ?: false ) && data[ arguments.logoUrl ];
			}
			, getCalls = function() { return calls; }
		};
	}

	private function _reader( required array specs, struct args={} ) {
		var root = variables.work & "root-" & CreateUniqueId() & "/";
		DirectoryCreate( root, true );

		for ( var spec in arguments.specs ) {
			_createLex( root & spec.fileName, spec );
		}

		var initArgs = { s3root=root };
		StructAppend( initArgs, arguments.args, true );
		var reader = new services.ExtensionMetadataReader( argumentCollection=initArgs );
		reader.loadMeta();

		return reader;
	}

	private void function _createLex( required string path, required struct spec ) {
		var src = variables.work & "src-" & CreateUniqueId() & "/";
		DirectoryCreate( src & "META-INF", true );

		var manifest = "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.spec.id & Chr( 13 ) & Chr( 10 )
			& "name: Artifact logo URL test" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.spec.version & Chr( 13 ) & Chr( 10 );
		if ( Len( arguments.spec.groupId ) ) {
			manifest &= "groupId: " & arguments.spec.groupId & Chr( 13 ) & Chr( 10 );
		}
		if ( Len( arguments.spec.artifactId ) ) {
			manifest &= "artifactId: " & arguments.spec.artifactId & Chr( 13 ) & Chr( 10 );
		}
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
