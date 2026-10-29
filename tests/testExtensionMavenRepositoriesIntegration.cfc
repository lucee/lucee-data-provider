component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		// the repositories Lucee core uses by default, the same as the defaults of the extension provider
		variables.releases  = "https://repo1.maven.org/maven2/";
		variables.snapshots = "https://central.sonatype.com/repository/maven-snapshots/";
		variables.mixed     = "https://maven.lucee-services.com/";
		variables.tmp       = GetTempDirectory() & "ldev6789-live-" & CreateUUID() & "/";

		DirectoryCreate( tmp, true );

		variables.source = new services.MavenExtensionSource(
			  releaseRepos  = [ releases ]
			, snapshotRepos = [ snapshots ]
			, mixedRepos    = [ mixed ]
		);
		variables.found = source.listExtensions();
	}

	function afterAll() {
		if ( DirectoryExists( variables.tmp ) ) {
			DirectoryDelete( variables.tmp, true );
		}
	}

	function run( testResults, testBox ) {
		describe( "LDEV-6789 extensions from the live Maven repositories", function() {

			it( title="lists every repository", body=function() {
				expect( found.complete ).toBeTrue();
				expect( found.files.len() ).toBeGT( 100 );
			});

			it( title="lists Mail 1.1.0.17 and FTP 1.0.0.8, the versions reported as 404 in LDEV-6789", body=function() {
				var mail = _find( "mail-extension-1.1.0.17.lex" );
				var ftp  = _find( "ftp-extension-1.0.0.8.lex" );

				expect( mail.artifact ).toBe( "mail-extension" );
				expect( ftp.version ).toBe( "1.0.0.8" );
				expect( mail.repos ).toInclude( releases );
				expect( ftp.repos ).toInclude( releases );
			});

			it( title="serves Mail 1.1.0.17 and FTP 1.0.0.8", body=function() {
				for ( var name in [ "mail-extension-1.1.0.17.lex", "ftp-extension-1.0.0.8.lex" ] ) {
					var file   = _find( name );
					var target = tmp & name;
					var fileUrl = source.getFileUrl( file.artifact, file.version, file.repos );

					expect( fileUrl ).notToBe( "" );

					source.download( file.artifact, file.version, file.repos, target );

					expect( FileExists( target ) ).toBeTrue();
					expect( IsZipFile( target ) ).toBeTrue( name & " is no zip file" );
				}
			});

			it( title="resolves the snapshots that are listed to a file", body=function() {
				var snaps = found.files.filter( function( f ) {
					return Right( f.version, 9 ) == "-SNAPSHOT" && f.repos.find( snapshots ) > 0;
				});

				// the timestamped files of the snapshot repository, tested for a few of them
				for ( var file in snaps.slice( 1, Min( 3, snaps.len() ) ) ) {
					var fileUrl = source.getFileUrl( file.artifact, file.version, [ snapshots ] );

					expect( fileUrl ).toMatch( "^" & snapshots );
					expect( fileUrl ).toMatch( "-[0-9]{8}\.[0-9]{6}-[0-9]+\.lex$" );

					http url=fileUrl method="head" timeout=30 result="local.res" redirect=true;
					expect( Val( local.res.statusCode ) ).toBe( 200, fileUrl );
				}
			});

			it( title="has no release in the lists of snapshot versions and no snapshot at a release", body=function() {
				for ( var file in found.files ) {
					if ( Right( file.version, 9 ) == "-SNAPSHOT" ) {
						expect( file.repos ).notToInclude( releases );
					}
					else {
						expect( file.repos ).notToInclude( snapshots );
					}
				}
			});

		});
	}

	private struct function _find( name ) {
		for ( var file in found.files ) {
			if ( file.name == arguments.name ) {
				return file;
			}
		}

		throw( message="[#arguments.name#] not found in the live repositories" );
	}

}
