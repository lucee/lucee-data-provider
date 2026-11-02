component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		variables.base     = GetTempDirectory() & "ldev6795-" & CreateUUID() & "/";
		variables.cdnUrl   = "https://ext.example.invalid/";
		variables.mavenCdn = "https://cdn.example.invalid/org/lucee/";
		variables.mailId   = "212BA548-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.legacyId = "11111111-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.plainId  = "22222222-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.oldId    = "33333333-F15A-4EBD-8B1EEDF8DD8A844D";
		variables.newId    = "44444444-F15A-4EBD-8B1EEDF8DD8A844D";

		DirectoryCreate( base, true );
	}

	function afterAll() {
		if ( DirectoryExists( variables.base ) ) {
			DirectoryDelete( variables.base, true );
		}
	}

	function run( testResults , testBox ) {

		describe( "LDEV-6795 Maven first, with the flat S3 files as the fallback", function() {

			it( title="serves the flat only extensions as the fallback by default, the others from the Maven layout", body=function() {
				var world  = _newWorld();
				var reader = _newReader( world );
				var found  = _versions( reader.list( type="all", all=true ) );

				expect( found ).toHaveKey( legacyId & "|1.0.0.1" );
				expect( found ).toHaveKey( mailId & "|1.1.0.8" );
				expect( found ).toHaveKey( mailId & "|1.1.0.17" );

				expect( reader.getDownloadUrl( "legacy-1.0.0.1.lex", cdnUrl ) ).toBe( cdnUrl & "legacy-1.0.0.1.lex" );
				// in both, the Maven layout wins
				expect( reader.getDownloadUrl( "mail-1.1.0.8.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.8/mail-extension-1.1.0.8.lex" );
				expect( reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", cdnUrl ) )
					.toBe( mavenCdn & "mail-extension/1.1.0.17/mail-extension-1.1.0.17.lex" );
			});

			it( title="counts the files served by the fallback, and only those", body=function() {
				var reader = _newReader( _newWorld() );

				reader.getDownloadUrl( "legacy-1.0.0.1.lex", cdnUrl );
				reader.getDownloadUrl( "legacy-1.0.0.1.lex", cdnUrl );
				reader.getDownloadUrl( "mail-1.1.0.8.lex", cdnUrl );
				reader.getDownloadUrl( "mail-extension-1.1.0.17.lex", cdnUrl );

				expect( reader.getFlatFallbackHits() ).toBe( { "legacy-1.0.0.1.lex" : 2 } );
			});

			it( title="does not serve what is only in the flat bucket when the fallback is off", body=function() {
				var reader = _newReader( _newWorld(), { flatFallback=false } );
				var found  = _versions( reader.list( type="all", all=true ) );

				expect( found ).notToHaveKey( legacyId & "|1.0.0.1" );
				expect( found ).toHaveKey( mailId & "|1.1.0.8" );
				expect( found ).toHaveKey( mailId & "|1.1.0.17" );

				expect( reader.getExtensionDetail( id=legacyId ) ).toBe( {} );
				expect( reader.getExtensionDetail( id=legacyId, version="1.0.0.1" ) ).toBe( {} );
				expect( reader.getExtensionDetail( id=mailId ).filename ).toBe( "mail-extension-1.1.0.17.lex" );
				expect( reader.getExtensionDetail( id=mailId, version="1.1.0.8" ).filename ).toBe( "mail-1.1.0.8.lex" );
			});

			it( title="switches the fallback off and on again while running", body=function() {
				var reader = _newReader( _newWorld() );

				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( legacyId & "|1.0.0.1" );

				reader.setFlatFallback( false );
				expect( _versions( reader.list( type="all", all=true ) ) ).notToHaveKey( legacyId & "|1.0.0.1" );
				expect( reader.getExtensionDetail( id=legacyId ) ).toBe( {} );

				reader.setFlatFallback( true );
				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( legacyId & "|1.0.0.1" );
				expect( reader.getExtensionDetail( id=legacyId ).filename ).toBe( "legacy-1.0.0.1.lex" );
			});

			it( title="keeps serving the flat files with the fallback off when there is no Maven source at all", body=function() {
				var world  = _newWorld();
				var reader = new services.ExtensionMetadataReader( s3root=_noTrailingSlash( world.flat ), flatFallback=false );

				reader.loadMeta();

				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( legacyId & "|1.0.0.1" );
			});

			it( title="still has everything in the extension meta for the bundles when the fallback is off", body=function() {
				var reader = _newReader( _newWorld(), { flatFallback=false } );

				expect( reader.getExtensionFileMatchingBundle( "legacy", "1.0.0.1" ) ).toBe( "legacy-1.0.0.1.lex" );
			});

		});

		describe( "LDEV-6795 packaging of an extension file", function() {

			it( title="is osgi with jars, maven with a maven folder and unknown with neither", body=function() {
				var reader    = _newReader( _newWorld() );
				var packaging = _packaging( reader );

				expect( packaging[ "legacy-1.0.0.1.lex" ] ).toBe( "osgi" );
				expect( packaging[ "plain-1.0.0.1.lex" ] ).toBe( "unknown" );
				expect( packaging[ "mail-extension-1.1.0.17.lex" ] ).toBe( "maven" );
			});

			it( title="is kept in the state file, which also loads when written before the packaging was recorded", body=function() {
				var world = _newWorld();

				_newReader( world );

				var state = DeserializeJson( FileRead( world.flat & "extensions.json" ), false );
				expect( state ).toHaveKey( "packaging" );

				QueryDeleteColumn( state, "packaging" );
				FileWrite( world.flat & "extensions.json", SerializeJson( state ) );

				// no minimum core version for Maven: nothing is read, it is served as before
				var reader = _newReader( world );

				expect( _packaging( reader )[ "legacy-1.0.0.1.lex" ] ).toBe( "" );
				expect( _versions( reader.list( type="all", all=true ) ) ).toHaveKey( legacyId & "|1.0.0.1" );
			});

			it( title="is read for the files of an old state file when there is a minimum core version for Maven", body=function() {
				var world = _newWorld();

				_newReader( world );
				_removePackagingFromState( world );

				var reader    = _newReader( world, { mavenOnlyMinCore="7.2.0.0" } );
				var packaging = _packaging( reader );

				expect( packaging[ "legacy-1.0.0.1.lex" ] ).toBe( "osgi" );
				expect( packaging[ "plain-1.0.0.1.lex" ] ).toBe( "unknown" );
				expect( packaging[ "mail-extension-1.1.0.17.lex" ] ).toBe( "maven" );

				// and kept
				expect( DeserializeJson( FileRead( world.flat & "extensions.json" ), false ).packaging[ 1 ] ).notToBe( "" );
			});

			it( title="is read for a limited number of files per load", body=function() {
				var world = _newWorld();

				_newReader( world );
				_removePackagingFromState( world );

				var reader = _newReader( world, { mavenOnlyMinCore="7.2.0.0", packagingBackfillMax=2 } );
				var known  = _knownPackagings( reader );

				expect( known ).toBe( 2 );

				reader.loadMeta();
				expect( _knownPackagings( reader ) ).toBe( 4 );

				// 4 files in all
				reader.loadMeta();
				expect( _knownPackagings( reader ) ).toBe( 4 );
			});

		});

		describe( "LDEV-6795 minimum core version for extensions packaged for Maven", function() {

			it( title="changes nothing when it is not set", body=function() {
				var reader = _newReader( _newVersionsWorld() );

				expect( reader.getExtensionDetail( id=oldId, coreVersion="7.1.0.5" ).version ).toBe( "2.0.0.1" );
				expect( _versions( reader.list( type="all", all=true, coreVersion="7.1.0.5" ) ) ).toHaveKey( oldId & "|2.0.0.1" );
			});

			it( title="does not list a Maven packaged extension for a core below it, but the older osgi version", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );
				var found  = _versions( reader.list( type="all", all=true, coreVersion="7.1.0.5" ) );

				expect( found ).toHaveKey( oldId & "|1.0.0.1" );
				expect( found ).notToHaveKey( oldId & "|2.0.0.1" );

				var latest = _row( reader.list( type="all", coreVersion="7.1.0.5" ), oldId );
				expect( latest.version ).toBe( "1.0.0.1" );
				expect( latest.older ).toBe( [] );
			});

			it( title="lists it for a core at or above it, with the minimum core version it needs", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );
				var all    = reader.list( type="all", all=true, coreVersion="7.2.0.1" );
				var found  = _versions( all );

				expect( found ).toHaveKey( oldId & "|1.0.0.1" );
				expect( found ).toHaveKey( oldId & "|2.0.0.1" );

				var latest = _row( reader.list( type="all", coreVersion="7.2.0.0" ), oldId );
				expect( latest.version ).toBe( "2.0.0.1" );
				expect( latest.minCoreVersion ).toBe( "7.2.0.0" );
				// the older versions, with the minimum core version of each
				expect( latest.older ).toBe( [ "1.0.0.1" ] );
				expect( latest.coreVersion ).toBe( [ "5.3.0.0" ] );
			});

			it( title="is the minimum when the manifest has a lower one, the manifest one when that is higher", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );

				expect( _versions( reader.list( type="all", all=true, coreVersion="7.3.0.1" ) ) ).toHaveKey( oldId & "|2.0.0.1" );
				expect( _versions( reader.list( type="all", all=true, coreVersion="7.3.0.1" ) ) ).notToHaveKey( newId & "|1.0.0.1" );
				expect( _versions( reader.list( type="all", all=true, coreVersion="7.5.0.0" ) ) ).toHaveKey( newId & "|1.0.0.1" );
			});

			it( title="gives the latest version that the core can load", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );

				expect( reader.getExtensionDetail( id=oldId, coreVersion="7.1.0.5" ).version ).toBe( "1.0.0.1" );
				expect( reader.getExtensionDetail( id=oldId, coreVersion="7.2.0.1" ).version ).toBe( "2.0.0.1" );
				expect( reader.getExtensionDetail( id=oldId ).version ).toBe( "2.0.0.1" );
			});

			it( title="gives nothing when no version can be loaded by the core", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );

				expect( function() {
					reader.getExtensionDetail( id=newId, coreVersion="7.1.0.5" );
				} ).toThrow( message="No extension version available" );
			});

			it( title="does not serve a version asked for to a core that can't load it, but without a core version", body=function() {
				var reader = _newReader( _newVersionsWorld(), { mavenOnlyMinCore="7.2.0.0" } );

				expect( reader.getExtensionDetail( id=oldId, version="2.0.0.1", coreVersion="7.1.0.5" ) ).toBe( {} );
				expect( reader.getExtensionDetail( id=oldId, version="2.0.0.1", coreVersion="7.2.0.1" ).filename )
					.toBe( "old-extension-2.0.0.1.lex" );
				expect( reader.getExtensionDetail( id=oldId, version="2.0.0.1" ).filename ).toBe( "old-extension-2.0.0.1.lex" );
				expect( reader.getExtensionDetail( id=oldId, version="1.0.0.1", coreVersion="7.1.0.5" ).filename )
					.toBe( "old-1.0.0.1.lex" );
			});

			it( title="does not hold back an extension of which the packaging is not known", body=function() {
				var world  = _newVersionsWorld();
				var reader = _newReader( world, { mavenOnlyMinCore="7.2.0.0" } );

				expect( _versions( reader.list( type="all", all=true, coreVersion="6.2.0.1" ) ) ).toHaveKey( plainId & "|1.0.0.1" );
			});

		});
	}

	private function _newWorld() {
		var world = { root=base & CreateUUID() & "/" };

		world.flat  = world.root & "flat/";
		world.maven = world.root & "maven/org/lucee/";

		DirectoryCreate( world.flat,  true );
		DirectoryCreate( world.maven, true );

		// only in the flat bucket
		_createLex( world.flat & "legacy-1.0.0.1.lex", legacyId, "1.0.0.1", { jars=true } );
		_createLex( world.flat & "plain-1.0.0.1.lex",  plainId,  "1.0.0.1", {} );

		// in the flat bucket and in the Maven layout, under another name
		_createLex( world.flat & "mail-1.1.0.8.lex", mailId, "1.1.0.8", { jars=true } );
		_createMavenLex( world, "mail-extension", "1.1.0.8", mailId );
		_createMavenLex( world, "mail-extension", "1.1.0.17", mailId );

		return world;
	}

	// an osgi extension in the flat bucket, newer versions of it packaged for Maven
	private function _newVersionsWorld() {
		var world = { root=base & CreateUUID() & "/" };

		world.flat  = world.root & "flat/";
		world.maven = world.root & "maven/org/lucee/";

		DirectoryCreate( world.flat,  true );
		DirectoryCreate( world.maven, true );

		_createLex( world.flat & "old-1.0.0.1.lex", oldId, "1.0.0.1", { jars=true, minCore="5.3.0.0" } );
		_createMavenLex( world, "old-extension", "2.0.0.1", oldId, "6.0.0.0" );
		_createMavenLex( world, "new-extension", "1.0.0.1", newId, "7.5.0.0" );
		_createLex( world.flat & "plain-1.0.0.1.lex", plainId, "1.0.0.1", { minCore="5.3.0.0" } );

		return world;
	}

	private function _newReader( required struct world, struct settings={} ) {
		var reader = new services.ExtensionMetadataReader(
			  s3root      = _noTrailingSlash( world.flat )
			, mavenRoot   = world.maven
			, mavenCdnUrl = mavenCdn
			, flatFallback         = arguments.settings.flatFallback         ?: true
			, mavenOnlyMinCore     = arguments.settings.mavenOnlyMinCore     ?: ""
			, packagingBackfillMax = arguments.settings.packagingBackfillMax ?: 200
		);

		reader.loadMeta();

		return reader;
	}

	private function _removePackagingFromState( required struct world ) {
		var state = DeserializeJson( FileRead( world.flat & "extensions.json" ), false );

		QueryDeleteColumn( state, "packaging" );
		FileWrite( world.flat & "extensions.json", SerializeJson( state ) );
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

	// the row of an extension of a query, as a struct
	private struct function _row( extensions, id ) {
		loop query=arguments.extensions {
			if ( arguments.extensions.id == arguments.id ) {
				return QueryRowData( arguments.extensions, arguments.extensions.currentRow );
			}
		}

		return {};
	}

	// file name > packaging
	private struct function _packaging( reader ) {
		var found = {};
		var meta  = arguments.reader.getExtensionMeta();

		loop query=meta {
			found[ meta.filename ] = meta.packaging;
		}

		return found;
	}

	private numeric function _knownPackagings( reader ) {
		var count = 0;

		for ( var value in _packaging( arguments.reader ) ) {
			if ( Len( _packaging( arguments.reader )[ value ] ) ) {
				count++;
			}
		}

		return count;
	}

	private function _createMavenLex( world, artifact, version, id, minCore="" ) {
		var file = world.maven & arguments.artifact & "/" & arguments.version & "/" & arguments.artifact & "-" & arguments.version & ".lex";

		_createLex( file, arguments.id, arguments.version, { maven=true, minCore=arguments.minCore } );
	}

	// an extension file is a zip with a manifest, and jars (osgi) or a maven folder (maven) when asked for
	private function _createLex( path, id, version, struct options ) {
		var src = base & "src-" & CreateUUID() & "/";
		var crlf = Chr( 13 ) & Chr( 10 );

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & crlf
			& "id: " & arguments.id & crlf
			& "name: LDEV-6795 test extension " & arguments.id & crlf
			& "version: " & arguments.version & crlf
			& ( Len( arguments.options.minCore ?: "" ) ? "lucee-core-version: " & arguments.options.minCore & crlf : "" )
			& crlf );

		if ( arguments.options.jars ?: false ) {
			DirectoryCreate( src & "jars", true );
			FileWrite( src & "jars/test.jar", "not really a jar" );
		}
		if ( arguments.options.maven ?: false ) {
			DirectoryCreate( src & "maven/org/lucee/test/1.0", true );
			FileWrite( src & "maven/org/lucee/test/1.0/test-1.0.jar", "not really a jar" );
		}

		DirectoryCreate( GetDirectoryFromPath( arguments.path ), true, true );
		Compress( format="zip", source=src, target=arguments.path, includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
