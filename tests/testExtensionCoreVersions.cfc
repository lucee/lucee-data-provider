component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		variables.testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions.json"), false);

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
		variables.extMetaReader = new services.ExtensionMetadataReader();
		variables.extMetaReader.loadMeta( variables.testVersions );

		variables.compressExt = "8D7FB0DF-08BB-1589-FE3975678F07DB17";
		variables.imageExt   = "B737ABC4-D43F-4D91-8E8E973E37C40D1B";
	}

	function run( testResults , testBox ) {
		describe( "test extension listing by core version", function() {

			it (title="test no coreVersion", body=function(){
				var ext = testExtList( coreVersion="" );
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext[ imageExt ].version ).toBe ( "3.0.0.0-SNAPSHOT" );
			});

			it (title="test coreVersion 5.4.6.9", body=function(){
				var ext = testExtList( coreVersion="5.4.6.9" );
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "1.0.0.15" );
				expect ( ext[ imageExt ].version ).toBe ( "2.0.0.29" );
			});

			it (title="test coreVersion 6.2.1.5", body=function(){
				var ext = testExtList( coreVersion="6.2.1.5" );
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "1.0.0.15" );
				expect ( ext[ variables.imageExt ].version ).toBe ( "2.0.0.29" );
			});

			it (title="test coreVersion 7.0.0.109", body=function(){
				var ext = testExtList( coreVersion="7.0.0.109" );
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "1.0.0.15" );
				expect ( ext[ variables.imageExt ].version ).toBe ( "2.0.0.29" );
			});

			it (title="test coreVersion 7.0.0.219", body=function(){
				var ext = testExtList( coreVersion="8.0.0.0");
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext[ variables.imageExt ].version ).toBe ( "3.0.0.0-SNAPSHOT" );
			});

			it (title="test coreVersion 8.0.0.0", body=function(){
				var ext = testExtList( coreVersion="8.0.0.0");
				expect ( ext ).toHaveLength( 2 );
				expect ( ext[ variables.compressExt ].version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext[ variables.imageExt ].version ).toBe ( "3.0.0.0-SNAPSHOT" );
			});

		});

		describe( "test extension full by specific version, core version is ignored unless empty or latest", function() {

			it (title="test no coreVersion", body=function(){
				var ext = testExtFull( coreVersion="", id=variables.compressExt, version="2.0.0.1-SNAPSHOT");
				expect ( ext.version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 7.0.0.118", body=function(){
				var ext = testExtFull( coreVersion="7.0.0.119", id=variables.compressExt, version="1.0.0.15");
				expect ( ext.version ).toBe ( "1.0.0.15" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 7.0.0.118", body=function(){
				var ext = testExtFull( coreVersion="7.0.0.119", id=variables.compressExt, version="2.0.0.1-SNAPSHOT");
				expect ( ext.version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});
		});

		describe( "test extension full by core version", function() {

			it (title="test no coreVersion", body=function(){
				var ext = testExtFull( coreVersion="", id=variables.compressExt );
				expect ( ext.version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 5.4.6.9", body=function(){
				var ext = testExtFull( coreVersion="5.4.6.9", id=variables.compressExt );
				expect ( ext.version ).toBe ( "1.0.0.15" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 6.2.1.5", body=function(){
				var ext = testExtFull( coreVersion="6.2.1.5", id=variables.compressExt );
				expect ( ext.version ).toBe ( "1.0.0.15" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 7.0.0.109", body=function(){
				var ext = testExtFull( coreVersion="7.0.0.109", id=variables.compressExt );
				expect ( ext.version ).toBe ( "1.0.0.15" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 7.0.0.219", body=function(){
				var ext = testExtFull( coreVersion="8.0.0.0", id=variables.compressExt );
				expect ( ext.version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

			it (title="test coreVersion 8.0.0.0", body=function(){
				var ext = testExtFull( coreVersion="8.0.0.0", id=variables.compressExt );
				expect ( ext.version ).toBe ( "2.0.0.1-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.compressExt );
			});

		});
	}

	private function testExtFull( id, version="", coreVersion="" ){
		var ext = variables.extMetaReader.getExtensionDetail(
			  id            = arguments.id
			, version       = arguments.version
			, coreVersion   = arguments.coreVersion
			, withLogo      = false
		);

		return ext;
	}

	private function testExtList( type="all", version="", coreVersion="" ){
		var ext = variables.extMetaReader.list(
			  type          = arguments.type
			, coreVersion   = arguments.coreVersion
			, withLogo      = false
		);

		return QueryToStruct( ext, "id" );
	}
}
