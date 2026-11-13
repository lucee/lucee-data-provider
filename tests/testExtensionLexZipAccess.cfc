component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services"   : ExpandPath( dir & "../apps/updateserver-maven/services" ),
			"/lexzipstub" : dir
		};

		variables.work = GetTempDirectory() & "lex-zip-access-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );
		variables.extId = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
		variables.jarSize = 1500000;
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "Maven-only lex metadata does not extract the archive to temp/compress", function() {

			it( title="records osgi packaging and does not unpack bundled jars into Lucee's compress temp", body=function() {
				var marker = "big-" & CreateUniqueId() & ".jar";
				var lexFile = _createLex(
					  fileName = "dummy-extension-1.0.0.1.lex"
					, id       = variables.extId
					, version  = "1.0.0.1"
					, layout   = "osgi"
					, jarName  = marker
				);

				var compressBefore = _compressPaths();
				var reader = _newReader( lexFile, "dummy-extension", "1.0.0.1" );
				var all    = reader.list( type="all", all=true );

				expect( all.recordCount ).toBe( 1 );
				expect( all.packaging[ 1 ] ).toBe( "osgi" );
				expect( all.id[ 1 ] ).toBe( variables.extId );
				expect( _newMarkerPaths( compressBefore, marker ) ).toBe( [] );
			});

			it( title="records maven packaging from a maven/ folder without extracting the archive", body=function() {
				var marker = "artifact-" & CreateUniqueId() & ".jar";
				var lexFile = _createLex(
					  fileName = "coords-extension-2.0.0.1.lex"
					, id       = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
					, version  = "2.0.0.1"
					, layout   = "maven"
					, jarName  = marker
				);

				var compressBefore = _compressPaths();
				var reader = _newReader( lexFile, "coords-extension", "2.0.0.1" );
				var all    = reader.list( type="all", all=true );

				expect( all.recordCount ).toBe( 1 );
				expect( all.packaging[ 1 ] ).toBe( "maven" );
				expect( _newMarkerPaths( compressBefore, marker ) ).toBe( [] );
			});

		});
	}

	private function _newReader( required string lexFile, required string artifact, required string version ) {
		var cache = variables.work & "cache-" & CreateUniqueId() & "/";
		DirectoryCreate( cache, true );
		var stub = new lexzipstub.LexZipAccessMavenStub( arguments.lexFile, arguments.artifact, arguments.version );

		return new services.ExtensionMetadataReader(
			  s3root       = cache
			, mavenSource  = stub
			, mavenOnly    = true
			, flatFallback = false
		);
	}

	private array function _compressPaths() {
		var dir = GetTempDirectory();
		if ( Right( dir, 1 ) != "/" && Right( dir, 1 ) != "\" ) {
			dir &= "/";
		}
		dir &= "compress";
		if ( !DirectoryExists( dir ) ) {
			return [];
		}

		return DirectoryList( dir, true, "path" );
	}

	private array function _newMarkerPaths( required array before, required string marker ) {
		var leftover = [];

		for ( var path in _compressPaths() ) {
			if ( !ArrayFind( arguments.before, path ) && FindNoCase( arguments.marker, path ) ) {
				ArrayAppend( leftover, path );
			}
		}

		return leftover;
	}

	private string function _createLex(
		  required string fileName
		, required string id
		, required string version
		, required string layout
		, required string jarName
	) {
		var src = variables.work & "src-" & CreateUniqueId() & "/";
		DirectoryCreate( src & "META-INF", true );

		var manifest = "Manifest-Version: 1.0" & Chr( 13 ) & Chr( 10 )
			& "id: " & arguments.id & Chr( 13 ) & Chr( 10 )
			& "version: " & arguments.version & Chr( 13 ) & Chr( 10 )
			& "name: Dummy" & Chr( 13 ) & Chr( 10 )
			& "description: test" & Chr( 13 ) & Chr( 10 );

		FileWrite( src & "META-INF/MANIFEST.MF", manifest );

		if ( arguments.layout == "osgi" ) {
			DirectoryCreate( src & "jars", true );
			FileWrite( src & "jars/" & arguments.jarName, RepeatString( "x", variables.jarSize ) );
		} else {
			DirectoryCreate( src & "maven/org/example", true );
			FileWrite( src & "maven/org/example/" & arguments.jarName, RepeatString( "x", variables.jarSize ) );
		}

		var lexFile = variables.work & arguments.fileName;
		_zipDirectory( src, lexFile );
		DirectoryDelete( src, true );

		return lexFile;
	}

	private void function _zipDirectory( required string src, required string target ) {
		var base = Replace( arguments.src, "\\", "/", "all" );
		if ( Right( base, 1 ) != "/" ) {
			base &= "/";
		}
		var zos = CreateObject( "java", "java.util.zip.ZipOutputStream" ).init(
			CreateObject( "java", "java.io.FileOutputStream" ).init( arguments.target )
		);
		try {
			for ( var path in DirectoryList( arguments.src, true, "path" ) ) {
				if ( DirectoryExists( path ) ) {
					continue;
				}
				var name = Mid( Replace( path, "\\", "/", "all" ), Len( base ) + 1, 9999 );
				zos.putNextEntry( CreateObject( "java", "java.util.zip.ZipEntry" ).init( name ) );
				var instream = CreateObject( "java", "java.io.FileInputStream" ).init( path );
				try {
					var buf  = CreateObject( "java", "java.lang.reflect.Array" ).newInstance(
						CreateObject( "java", "java.lang.Byte" ).TYPE,
						8192
					);
					var read = instream.read( buf );
					while ( read >= 0 ) {
						if ( read > 0 ) {
							zos.write( buf, 0, read );
						}
						read = instream.read( buf );
					}
				} finally {
					instream.close();
				}
				zos.closeEntry();
			}
		} finally {
			zos.close();
		}
	}

}
