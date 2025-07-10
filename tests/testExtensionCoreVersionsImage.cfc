component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		variables.testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions-Image.json"), false);

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};
		variables.extMetaReader = new services.ExtensionMetadataReader();
		variables.extMetaReader.loadMeta( variables.testVersions );

		variables.imageExt   = "B737ABC4-D43F-4D91-8E8E973E37C40D1B";
	}

	function run( testResults , testBox ) {
		
		describe( "test image extension latest full by core version", function() {

			it (title="test no coreVersion", body=function(){
				var ext = testExtFull( coreVersion="", id=variables.imageExt );
				expect ( ext.version ).toBe ( "3.0.0.2-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
			});

			it (title="test coreVersion 5.4.6.9", body=function(){
				var ext = testExtFull( coreVersion="5.4.6.9", id=variables.imageExt );
				expect ( ext.version ).toBe ( "2.0.0.30-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
			});

			it (title="test coreVersion 6.2.1.5", body=function(){
				var ext = testExtFull( coreVersion="6.2.1.5", id=variables.imageExt );
				expect ( ext.version ).toBe ( "2.0.0.30-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
			});

			it (title="test coreVersion 7.0.0.109", body=function(){
				var ext = testExtFull( coreVersion="7.0.0.109", id=variables.imageExt );
				expect ( ext.version ).toBe ( "2.0.0.30-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
			});

			it (title="test coreVersion 7.0.0.219", body=function(){
				var ext = testExtFull( coreVersion="8.0.0.0", id=variables.imageExt );
				expect ( ext.version ).toBe ( "3.0.0.2-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
			});

			it (title="test coreVersion 8.0.0.0", body=function(){
				var ext = testExtFull( coreVersion="8.0.0.0", id=variables.imageExt );
				expect ( ext.version ).toBe ( "3.0.0.2-SNAPSHOT" );
				expect ( ext.id ).toBe ( variables.imageExt );
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

}
