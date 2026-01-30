component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll(){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		variables.testVersions = deserializeJson(FileRead("staticArtifacts/testExtensionCoreVersions-MSSQL.json"), false);

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		// Reprocess versionSortable with fixed sortableVersionString function
		for ( var i = 1; i <= variables.testVersions.recordCount; i++ ) {
			if ( len( variables.testVersions.version[ i ] ) ) {
				variables.testVersions.versionSortable[ i ] = services.VersionUtils::sortableVersionString( variables.testVersions.version[ i ] );
			}
		}

		// Sort by id asc, versionSortable desc (same as loadMeta does)
		QuerySort( variables.testVersions, "id,versionSortable", "asc,desc" );

		variables.extMetaReader = new services.ExtensionMetadataReader();
		variables.extMetaReader.loadMeta( variables.testVersions );

		variables.mssqlExt = "99A4EF8D-F2FD-40C8-8FB8C2E67A4EEEB6";
	}

	function run( testResults , testBox ) {

		describe( "test MSSQL extension latest full by core version", function() {

			it (title="test no coreVersion", body=function(){
				var ext = testExtFull( coreVersion="", id=variables.mssqlExt );
				expect ( ext.version ).toBe ( "13.2.1" );
				expect ( ext.id ).toBe ( variables.mssqlExt );
			});

			it (title="test coreVersion 5.4.6.9", body=function(){
				var ext = testExtFull( coreVersion="5.4.6.9", id=variables.mssqlExt );
				// 5.4.6.9 > 5.3.2.63-SNAPSHOT, so should get latest version
				expect ( ext.version ).toBe ( "13.2.1" );
				expect ( ext.id ).toBe ( variables.mssqlExt );
			});

			it (title="test coreVersion 6.2.4.24 (bug scenario)", body=function(){
				var ext = testExtFull( coreVersion="6.2.4.24", id=variables.mssqlExt );
				// 6.2.4.24 > 5.3.2.63-SNAPSHOT, so should get latest version
				// This is the bug: returns old 6.2.1-jre8 instead of newer compatible version
				expect ( ext.version ).toBe ( "13.2.1" );
				expect ( ext.id ).toBe ( variables.mssqlExt );
			});

			it (title="test coreVersion 7.0.0.109", body=function(){
				var ext = testExtFull( coreVersion="7.0.0.109", id=variables.mssqlExt );
				// 7.0.0.109 > 5.3.2.63-SNAPSHOT, so should get latest version
				expect ( ext.version ).toBe ( "13.2.1" );
				expect ( ext.id ).toBe ( variables.mssqlExt );
			});

			it (title="test specific version 12.6.3.jre11", body=function(){
				var ext = testExtFull( coreVersion="", id=variables.mssqlExt, version="12.6.3.jre11" );
				expect ( ext.version ).toBe ( "12.6.3.jre11" );
				expect ( ext.id ).toBe ( variables.mssqlExt );
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
