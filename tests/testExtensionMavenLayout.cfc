component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		variables.base       = GetTempDirectory() & "ldev6789-" & CreateUUID() & "/";
		variables.flatRoot   = base & "flat/";
		variables.mavenRoot  = base & "maven/org/lucee/";
		variables.cdnUrl     = "https://ext.example.invalid/";
		variables.mavenCdn   = "https://cdn.example.invalid/org/lucee/";
		variables.extId      = "212BA548-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.otherId    = "99999999-F15A-4EBD-8B1EEDF8DD8A844D";

		DirectoryCreate( flatRoot,  true );
		DirectoryCreate( mavenRoot, true );

		// a legacy extension in the flat bucket
		_createLex( flatRoot & "mail-1.1.0.8-RC.lex", extId, "1.1.0.8-RC" );

		// published to the maven layout only
		_createMavenLex( "mail-extension", "1.1.0.17", extId );
		_createMavenLex( "ftp-extension",  "1.0.0.8",  otherId );

		// the same id and version as the flat file, copied over to the maven layout 
		_createMavenLex( "mail-extension", "1.1.0.8-RC", extId );

		// not extensions of their own: a -lite file and a file not named after its artifact and version
		_createLex( mavenRoot & "mail-extension/1.1.0.17/mail-extension-1.1.0.17-lite.lex", extId, "1.1.0.17" );
		_createLex( mavenRoot & "mail-extension/1.1.0.17/something-else.lex", extId, "1.1.0.99" );

		// not an extension artifact
		_createLex( mavenRoot & "other-library/1.0.0/other-library-1.0.0.lex", otherId, "1.0.0" );
	}

	function afterAll() {
		if ( DirectoryExists( variables.base ) ) {
			DirectoryDelete( variables.base, true );
		}
	}

	function run( testResults , testBox ) {
		describe( "LDEV-6789 extensions published to the maven layout only", function() {

			it( title="adds new versions from the maven layout", body=function() {
				var reader = _newReader();
				var all    = reader.list( type="all", all=true );
				var found  = _versions( all );

				expect( found ).toHaveKey( extId & "|1.1.0.17" );
				expect( found ).toHaveKey( otherId & "|1.0.0.8" );
			});

			it( title="keeps the extension of the flat bucket", body=function() {
				var found = _versions( _newReader().list( type="all", all=true ) );

				expect( found ).toHaveKey( extId & "|1.1.0.8-RC" );
			});

			it( title="ignores a maven file with the same id and version as a known extension", body=function() {
				var reader = _newReader();
				var all    = reader.list( type="all", all=true );
				var count  = 0;

				loop query=all {
					if ( all.id == extId && all.version == "1.1.0.8-RC" ) {
						count++;
					}
				}

				expect( count ).toBe( 1 );
				// LDEV-6795: Maven first, the flat file is served from the Maven layout, as the layout has that id and version
				expect( reader.getDownloadUrl( "mail-1.1.0.8-RC.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.8-RC/mail-extension-1.1.0.8-RC.lex" );
				expect( reader.getDownloadUrl( "mail-extension-1.1.0.8-RC.lex", cdnUrl ) ).toBe( cdnUrl & "mail-extension-1.1.0.8-RC.lex" );
			});

			it( title="ignores lite files, misnamed files and artifacts that are not extensions", body=function() {
				var all = _newReader().list( type="all", all=true );

				expect( _versions( all ) ).notToHaveKey( extId & "|1.1.0.99" );
				expect( _versions( all ) ).notToHaveKey( otherId & "|1.0.0" );
				expect( all.recordCount ).toBe( 3 );
			});

			it( title="serves the files of the maven layout from the maven cdn and the others from the extensions cdn", body=function() {
				var reader = _newReader();

				reader.list( type="all", all=true );

				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
				expect( reader.getDownloadUrl( "ftp-extension-1.0.0.8.lex", cdnUrl ) )
					.toBe( mavenCdn & "ftp-extension/1.0.0.8/ftp-extension-1.0.0.8.lex" );
				// LDEV-6795: a flat file that is in the Maven layout too (same id and version, other file name) is served from the layout
				expect( reader.getDownloadUrl( "mail-1.1.0.8-RC.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.8-RC/mail-extension-1.1.0.8-RC.lex" );
			});

			it( title="does not touch the maven layout when it is not configured", body=function() {
				// a flat bucket of its own, the one of the other tests has the cached extension meta of the maven files
				var otherFlat = base & "flat-only/";
				DirectoryCreate( otherFlat, true );
				FileCopy( flatRoot & "mail-1.1.0.8-RC.lex", otherFlat & "mail-1.1.0.8-RC.lex" );

				var reader = new services.ExtensionMetadataReader( s3root=_noTrailingSlash( otherFlat ) );
				reader.loadMeta();
				var found = _versions( reader.list( type="all", all=true ) );

				expect( found ).notToHaveKey( extId & "|1.1.0.17" );
				expect( found ).toHaveKey( extId & "|1.1.0.8-RC" );
			});

		});
	}

	private function _newReader() {
		var reader = new services.ExtensionMetadataReader(
			  s3root      = _noTrailingSlash( flatRoot )
			, mavenRoot   = mavenRoot
			, mavenCdnUrl = mavenCdn
		);
		reader.loadMeta();
		return reader;
	}

	private function _noTrailingSlash( path ) {
		return Left( arguments.path, Len( arguments.path ) - 1 );
	}

	private struct function _versions( extensions ) {
		var found = {};

		loop query=arguments.extensions {
			found[ arguments.extensions.id & "|" & arguments.extensions.version ] = true;
		}

		return found;
	}

	private function _createMavenLex( artifact, version, id ) {
		var file = mavenRoot & arguments.artifact & "/" & arguments.version & "/" & arguments.artifact & "-" & arguments.version & ".lex";

		_createLex( file, arguments.id, arguments.version );
	}

	// an extension file is a zip with a manifest
	private function _createLex( path, id, version ) {
		var src = base & "src-" & CreateUUID() & "/";

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.id & Chr( 13 ) & Chr( 10 )
			& "name: LDEV-6789 test extension" & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.version & Chr( 13 ) & Chr( 10 ) & Chr( 13 ) & Chr( 10 ) );

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
