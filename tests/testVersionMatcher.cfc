component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		variables.testVersions = deserializeJson(FileRead("staticArtifacts/testVersionMatcher_versions.json"));
		application action="update" mappings={
			"/update" : expandPath( dir & "../apps/updateserver/" )
		};
	}

	function run( testResults , testBox ) {
		describe( "LDEV-5391 check latest /rest/update/provider/latest/ matches correct version", function() {

			it(title="6.2.1.5 should not match 6.2.1.55", body=function(){
				expect(testLatest("snapshot", "6.2.1.5", "jar") ).toBe( "6.2.1.5-SNAPSHOT" );
				expect(testLatest("snapshot", "6.2.1.55", "jar") ) .toBe( "6.2.1.55-SNAPSHOT" );
				expect(testLatest("snapshot", "6.2.0.32", "jar") ) .toBe( "6.2.0.32-SNAPSHOT" );
			});

			it(title="missing", body=function(){
				expect(testLatest("stable", "6.2.0.32", "jar") ) .toBe("");
				expect(testLatest("", "6.2.0.32", "jar") ) .toBe("");
				expect(testLatest("any", "7", "jar") ) .toBe("");
				expect(testLatest("any", "4.5", "jar") ) .toBe("");
			});

			it(title="stable cacade 5", body=function(){
				expect(testLatest("stable", "5", "jar") ) .toBe(  "5.4.6.9"  );
				expect(testLatest("stable", "5.4", "jar") ) .toBe(  "5.4.6.9"  );
				expect(testLatest("stable", "5.4.6", "jar") ) .toBe(  "5.4.6.9"  );
				expect(testLatest("stable", "5.4.6.9", "jar") ) .toBe(  "5.4.6.9"  );
			});

			it(title="stable cacade 6", body=function(){
				expect(testLatest("stable", "6", "jar") ) .toBe(  "6.2.0.321"  );
				expect(testLatest("stable", "6.2", "jar") ) .toBe(  "6.2.0.321"  );
				expect(testLatest("stable", "6.2.0", "jar") ) .toBe(  "6.2.0.321"  );
			});

			it(title="latest", body=function(){
				expect(testLatest("any", "0", "jar") ) .toBe( "6.2.1.58-SNAPSHOT" );
			});
		});
	}

	private testLatest(type, version, distribution ){

		var matchedVersion = services.VersionUtils::matchVersion( variables.testVersions, 
			arguments.type, arguments.version, arguments.distribution );
		if ( len( matchedVersion ) eq 0 );
			return "";
		return variables.testVersions[ matchedVersion ].version;
	}

}
