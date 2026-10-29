component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			  "/services" : expandPath( dir & "../apps/updateserver/services" )
			, "/rest"     : expandPath( dir & "../apps/updateserver/rest" )
		};

		variables.base   = GetTempDirectory() & "ldev6789-type-" & CreateUUID() & "/";
		variables.flat   = base & "flat/";
		variables.cdnUrl = "https://ext.example.invalid/";

		// ftp like: finals, a release candidate and a snapshot that is newer than all of them
		variables.ftpId   = "11111111-F15A-4EBD-8B1EEDF8DD8A844D";
		// only snapshots
		variables.snapId  = "22222222-F15A-4EBD-8B1EEDF8DD8A844D";
		// only finals
		variables.finalId = "33333333-F15A-4EBD-8B1EEDF8DD8A844D";
		// versions that need different core versions, the newest ones are not for every core
		variables.coreId  = "44444444-F15A-4EBD-8B1EEDF8DD8A844D";

		DirectoryCreate( flat, true );

		_createLex( ftpId, "ftp", "1.0.0.8" );
		_createLex( ftpId, "ftp", "1.0.0.9" );
		_createLex( ftpId, "ftp", "1.0.0.10-RC" );
		_createLex( ftpId, "ftp", "1.0.0.11-SNAPSHOT" );

		_createLex( snapId, "snap", "1.0.0.1-SNAPSHOT" );
		_createLex( snapId, "snap", "1.0.0.2-SNAPSHOT" );

		_createLex( finalId, "final", "2.0.0.1" );
		_createLex( finalId, "final", "2.0.0.2" );

		_createLex( coreId, "core", "1.0.0.1", "5.0.0.0" );
		_createLex( coreId, "core", "2.0.0.1", "7.0.0.0" );
		_createLex( coreId, "core", "2.1.0.0-SNAPSHOT", "7.0.0.0" );

		variables.reader = new services.ExtensionMetadataReader( s3root=Left( flat, Len( flat ) - 1 ) );
		variables.reader.loadMeta();

		// the rest service gets what it needs from the application
		variables.hadReader = StructKeyExists( application, "extMetaReader" );
		variables.hadCdn    = StructKeyExists( application, "extensionsCdnUrl" );
		variables.oldReader = application.extMetaReader     ?: "";
		variables.oldCdn    = application.extensionsCdnUrl  ?: "";
		application.extMetaReader    = variables.reader;
		application.extensionsCdnUrl = cdnUrl;
	}

	function afterAll() {
		if ( variables.hadReader ) {
			application.extMetaReader = variables.oldReader;
		} else {
			StructDelete( application, "extMetaReader" );
		}

		if ( variables.hadCdn ) {
			application.extensionsCdnUrl = variables.oldCdn;
		} else {
			StructDelete( application, "extensionsCdnUrl" );
		}

		if ( DirectoryExists( variables.base ) ) {
			DirectoryDelete( variables.base, true );
		}
	}

	function run( testResults , testBox ) {
		describe( "LDEV-6789 the latest version of an extension is the latest one of the requested type", function() {

			it( title="lists the newest final of an extension that has a newer snapshot for the type release", body=function() {
				var ext = _byId( reader.list( type="release", withLogo=false ) );

				expect( ext ).toHaveKey( ftpId );
				expect( ext[ ftpId ].version ).toBe( "1.0.0.9" );
				expect( ext[ ftpId ].filename ).toBe( "ftp-extension-1.0.0.9.lex" );
				expect( ext[ finalId ].version ).toBe( "2.0.0.2" );
			});

			it( title="only has versions of the same type in the older versions", body=function() {
				var ext = _byId( reader.list( type="release", withLogo=false ) );

				expect( ext[ ftpId ].older ).toBe( [ "1.0.0.8" ] );
				expect( ext[ ftpId ].olderName ).toBe( [ "ftp-extension-1.0.0.8.lex" ] );
				expect( ext[ ftpId ].older ).notToInclude( "1.0.0.11-SNAPSHOT" );
				expect( ext[ ftpId ].older ).notToInclude( "1.0.0.10-RC" );
				expect( ext[ finalId ].older ).toBe( [ "2.0.0.1" ] );
			});

			it( title="lists the newest version, the snapshot, for the type all", body=function() {
				var ext = _byId( reader.list( type="all", withLogo=false ) );

				expect( ext[ ftpId ].version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( ext[ ftpId ].older ).toBe( [ "1.0.0.10-RC", "1.0.0.9", "1.0.0.8" ] );
			});

			it( title="lists the newest snapshot for the type snapshot, and the newest of the alphas, betas and release candidates for the type abc", body=function() {
				var snapshots = _byId( reader.list( type="snapshot", withLogo=false ) );
				var abc       = _byId( reader.list( type="abc", withLogo=false ) );

				expect( snapshots[ ftpId ].version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( snapshots[ ftpId ].older ).toBe( [] );
				expect( snapshots ).notToHaveKey( finalId );

				expect( abc ).toHaveKey( ftpId );
				expect( abc[ ftpId ].version ).toBe( "1.0.0.10-RC" );
				expect( abc[ ftpId ].older ).toBe( [] );
				expect( abc ).notToHaveKey( snapId );
				expect( abc ).notToHaveKey( finalId );
			});

			it( title="has no extension that only has snapshots for the type release, but for all and snapshot", body=function() {
				var release   = _byId( reader.list( type="release", withLogo=false ) );
				var all       = _byId( reader.list( type="all", withLogo=false ) );
				var snapshots = _byId( reader.list( type="snapshot", withLogo=false ) );

				expect( release ).notToHaveKey( snapId );
				expect( all ).toHaveKey( snapId );
				expect( all[ snapId ].version ).toBe( "1.0.0.2-SNAPSHOT" );
				expect( all[ snapId ].older ).toBe( [ "1.0.0.1-SNAPSHOT" ] );
				expect( snapshots ).toHaveKey( snapId );
				expect( snapshots[ snapId ].version ).toBe( "1.0.0.2-SNAPSHOT" );
			});

			it( title="lists every version with all=true, filtered by the type", body=function() {
				var versions = function( type ) {
					var found = [];
					var q     = reader.list( type=arguments.type, all=true, withLogo=false );
					loop query=q {
						if ( q.id == ftpId ) {
							ArrayAppend( found, q.version );
						}
					}
					return found;
				};

				expect( versions( "release" ) ).toBe( [ "1.0.0.9", "1.0.0.8" ] );
				expect( versions( "all" ) ).toBe( [ "1.0.0.11-SNAPSHOT", "1.0.0.10-RC", "1.0.0.9", "1.0.0.8" ] );
			});

			it( title="takes the core version into account as well as the type", body=function() {
				var old     = _byId( reader.list( type="release", coreVersion="6.2.1.5", withLogo=false ) );
				var current = _byId( reader.list( type="release", coreVersion="7.0.0.100", withLogo=false ) );
				var all     = _byId( reader.list( type="all", coreVersion="7.0.0.100", withLogo=false ) );

				expect( old[ coreId ].version ).toBe( "1.0.0.1" );
				expect( current[ coreId ].version ).toBe( "2.0.0.1" );
				expect( current[ coreId ].older ).toBe( [ "1.0.0.1" ] );
				expect( all[ coreId ].version ).toBe( "2.1.0.0-SNAPSHOT" );
			});

			it( title="lists the newest version of every extension when no type is given, as before", body=function() {
				var all = _byId( reader.list( withLogo=false ) );

				expect( all ).toHaveLength( 4 );
				expect( all[ ftpId ].version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( all[ snapId ].version ).toBe( "1.0.0.2-SNAPSHOT" );
				expect( all[ finalId ].version ).toBe( "2.0.0.2" );
			});

		});

		describe( "LDEV-6789 an extension without a version is the latest one of the requested type", function() {

			it( title="is the newest final for the type release, not the snapshot", body=function() {
				var ext = reader.getExtensionDetail( id=ftpId, type="release" );

				expect( ext.version ).toBe( "1.0.0.9" );
				expect( ext.filename ).toBe( "ftp-extension-1.0.0.9.lex" );
				expect( reader.getDownloadUrl( ext.filename, cdnUrl ) ).toBe( cdnUrl & "ftp-extension-1.0.0.9.lex" );
			});

			it( title="is the newest of the type for the other types", body=function() {
				expect( reader.getExtensionDetail( id=ftpId, type="all" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( reader.getExtensionDetail( id=ftpId, type="snapshot" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( reader.getExtensionDetail( id=ftpId, type="abc" ).version ).toBe( "1.0.0.10-RC" );
			});

			it( title="stays the newest version without a type, as before", body=function() {
				expect( reader.getExtensionDetail( id=ftpId ).version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( reader.getExtensionDetail( id=ftpId, version="latest" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
			});

			it( title="is not changed by the type when the version is given", body=function() {
				expect( reader.getExtensionDetail( id=ftpId, version="1.0.0.11-SNAPSHOT", type="release" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( reader.getExtensionDetail( id=ftpId, version="1.0.0.8", type="snapshot" ).version ).toBe( "1.0.0.8" );
			});

			it( title="is nothing for the type release when there is only a snapshot", body=function() {
				expect( reader.getExtensionDetail( id=snapId, type="release" ) ).toBeEmpty();
				expect( reader.getExtensionDetail( id=snapId, type="all" ).version ).toBe( "1.0.0.2-SNAPSHOT" );
				expect( reader.getExtensionDetail( id=snapId, type="snapshot" ).version ).toBe( "1.0.0.2-SNAPSHOT" );
			});

			it( title="is the newest of the type that fits the core version", body=function() {
				expect( reader.getExtensionDetail( id=coreId, type="release", coreVersion="6.2.1.5" ).version ).toBe( "1.0.0.1" );
				expect( reader.getExtensionDetail( id=coreId, type="release", coreVersion="7.0.0.100" ).version ).toBe( "2.0.0.1" );
				expect( reader.getExtensionDetail( id=coreId, type="all", coreVersion="7.0.0.100" ).version ).toBe( "2.1.0.0-SNAPSHOT" );
			});

			it( title="fails as before when no version of the type fits the core version", body=function() {
				expect( function() {
					reader.getExtensionDetail( id=coreId, type="release", coreVersion="4.0.0.0" );
				} ).toThrow( regex="No extension version available for \[4\.0\.0\.0\]" );
			});

		});

		describe( "LDEV-6789 the rest service answers with the release versions by default", function() {

			it( title="lists the extensions with a final, with the newest final, when no type is given", body=function() {
				var provider = _newProvider();
				var result   = provider.getInfo( coreVersion="" );
				var ext      = _byId( result.extensions );

				expect( ext ).toHaveKey( ftpId );
				expect( ext[ ftpId ].version ).toBe( "1.0.0.9" );
				expect( ext ).toHaveKey( finalId );
				expect( ext ).notToHaveKey( snapId );
			});

			it( title="lists the snapshots when the type all is requested", body=function() {
				var ext = _byId( _newProvider().getInfo( type="all", coreVersion="" ).extensions );

				expect( ext[ ftpId ].version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( ext ).toHaveKey( snapId );
			});

			it( title="provides the newest final of an extension requested without a version", body=function() {
				var ext = _newProvider().getInfoDetail( id=ftpId );

				expect( ext.version ).toBe( "1.0.0.9" );
				expect( _newProvider().getInfoDetail( id=ftpId, type="all" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
				expect( _newProvider().getInfoDetail( id=ftpId, version="1.0.0.11-SNAPSHOT" ).version ).toBe( "1.0.0.11-SNAPSHOT" );
			});

			it( title="redirects the download of an extension requested without a version to the newest final", body=function() {
				var provider = _newProvider();

				_expectRedirect( provider, ftpId, {}, cdnUrl & "ftp-extension-1.0.0.9.lex" );
				_expectRedirect( provider, ftpId, { type="all" }, cdnUrl & "ftp-extension-1.0.0.11-SNAPSHOT.lex" );
				_expectRedirect( provider, ftpId, { version="1.0.0.8" }, cdnUrl & "ftp-extension-1.0.0.8.lex" );
			});

		});
	}

	private struct function _byId( required query extensions ) {
		var found = {};

		loop query=arguments.extensions {
			found[ arguments.extensions.id ] = {
				  version   = arguments.extensions.version
				, filename  = arguments.extensions.filename
				, older     = arguments.extensions.older
				, olderName = arguments.extensions.olderName
			};
		}

		return found;
	}

	private function _newProvider() {
		return new rest.ExtensionProvider();
	}

	// the download is a redirect, the Location header of this call is the one that is new in the response
	private function _expectRedirect( provider, id, args, expected ) {
		var named    = Duplicate( arguments.args );
		var response = getPageContext().getResponse();
		var before   = _locations( response );

		named.id = arguments.id;

		try {
			arguments.provider.getFull( argumentCollection=named );

			var added = _locations( response ).filter( function( location ) {
				return !ArrayFind( before, location );
			} );

			expect( response.getStatus() ).toBe( 302 );
			expect( added ).toBe( [ arguments.expected ] );
		}
		finally {
			// the response of the test run must not stay a redirect
			response.setStatus( 200 );
		}
	}

	// the values of the Location headers of a response, there are none before the first one is set
	private array function _locations( response ) {
		var headers = arguments.response.getHeaders( "Location" );

		var values  = [];

		if ( !IsNull( headers ) ) {
			for ( var value in headers.toArray() ) {
				ArrayAppend( values, value );
			}
		}

		return values;
	}

	// an extension file is a zip with a manifest
	private function _createLex( id, artifact, version, minCoreVersion="" ) {
		var src = base & "src-" & CreateUUID() & "/";
		var eol = Chr( 13 ) & Chr( 10 );

		DirectoryCreate( src & "META-INF", true );
		FileWrite( src & "META-INF/MANIFEST.MF", "Manifest-Version: 1.0" & eol
			& "id: " & arguments.id & eol
			& "name: LDEV-6789 " & arguments.artifact & " extension" & eol
			& "version: " & arguments.version & eol
			& ( Len( arguments.minCoreVersion ) ? "lucee-core-version: " & arguments.minCoreVersion & eol : "" )
			& eol );

		Compress( format="zip", source=src, target=flat & arguments.artifact & "-extension-" & arguments.version & ".lex", includeBaseFolder=false );
		DirectoryDelete( src, true );
	}

}
