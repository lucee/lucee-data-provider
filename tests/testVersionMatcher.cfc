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

			// this is only testing against a limited sample subset

			it(title="6.2.1.5 should not match 6.2.1.55", body=function(){
				expect( testLatest( "snapshot", "6.2.1.5", "jar" ) ).toBe( "6.2.1.5-SNAPSHOT" );
				expect( testLatest( "snapshot", "6.2.1.55", "jar" ) ).toBe( "6.2.1.55-SNAPSHOT" );
				expect( testLatest( "snapshot", "6.2.0.32", "jar" ) ).toBe( "6.2.0.32-SNAPSHOT" );


				expect( testLatest( "stable", "5.3.1.1", "jar" ) ).toBe( "5.3.1.1" );
				expect( testLatest( "stable", "5.3.1", "jar" ) ).toBe( "5.3.1.1" );
				expect( testLatest( "stable", "5.3.10", "jar" ) ).toBe( "5.3.10.1" );
				expect( testLatest( "stable", "5.3", "jar" ) ).toBe( "5.3.10.1" );

				expect( testLatest( "all", "6.2.1.5", "linux-aarch64" ) ).toBe( "6.2.1.5-SNAPSHOT" );
				expect( testLatest( "snapshot", "6.2.1.5", "jar" ) ).toBe( "6.2.1.5-SNAPSHOT" );
			});

			it(title="missing", body=function(){
				expect( testLatest( "snapshot", "5.3.1.0", "jar" ) ).toBe( "" );
				expect( testLatest( "stable", "6.2.0.32", "jar" ) ).toBe( "" );
				expect( testLatest( "snapshot", "6.2.0.321", "jar" ) ).toBe( "" );
				expect( testLatest( "any", "7", "jar" ) ).toBe( "" );
				expect( testLatest( "any", "4.5", "jar" ) ).toBe( "" );
				expect( testLatest( "stable", "6.1.1", "jar" ) ).toBe( "" );
				expect( testLatest( "stable", "6.2.1", "jar" ) ).toBe( "" );
			});

			it(title="stable cacade 5", body=function(){
				expect( testLatest( "stable", "5", "jar" ) ).toBe( "5.4.6.9"  );
				expect( testLatest( "stable", "5.4", "jar" ) ).toBe( "5.4.6.9"  );
				expect( testLatest( "stable", "5.4.6", "jar" ) ).toBe( "5.4.6.9"  );
				expect( testLatest( "stable", "5.4.6.9", "jar" ) ).toBe( "5.4.6.9"  );
			});

			it(title="stable cascade 6", body=function(){
				expect( testLatest( "stable", "6", "jar" ) ).toBe( "6.2.0.321"  );
				expect( testLatest( "stable", "6.2", "jar" ) ).toBe( "6.2.0.321"  );
				expect( testLatest( "stable", "6.2.0", "jar" ) ).toBe( "6.2.0.321"  );
			});

			it(title="latest", body=function(){
				expect( testLatest( "all", "0", "jar" ) ).toBe( "6.2.1.58-SNAPSHOT" );
			});

			it(title="installer", body=function(){
				expect( testLatest( "all", "0", "linux-aarch64" ) ).toBe( "6.2.1.5-SNAPSHOT" );
				expect( testLatest( "all", "0", "linux-x64" ) ).toBe( "6.2.1.58-SNAPSHOT" );

				expect( testLatest( "stable", "0", "linux-aarch64" ) ).toBe( "" );
				expect( testLatest( "stable", "0", "linux-x64" ) ).toBe( "" );

				expect( testLatest( "all", "6", "linux-aarch64" ) ).toBe( "6.2.1.5-SNAPSHOT" );
				expect( testLatest( "all", "6", "linux-x64" ) ).toBe( "6.2.1.58-SNAPSHOT" );

				expect( testLatest( "all", "5", "linux-aarch64" ) ).toBe( "" );
				expect( testLatest( "all", "5", "linux-x64" ) ).toBe( "" );

				expect( testLatest( "all", "7", "linux-aarch64" ) ).toBe( "" );
				expect( testLatest( "all", "7", "linux-x64" ) ).toBe( "" );
			});

		});
	}

	private function testLatest(type, version, distribution ){

		if ( arguments.type eq "all" )
			arguments.type ="";
		if ( arguments.version eq 0 )
			arguments.version = "";


		var matchedVersion = update.services.VersionUtils::matchVersion( duplicate(variables.testVersions),
			arguments.type, arguments.version, arguments.distribution );
		if ( len( matchedVersion ) eq 0 )
			return "";
		return variables.testVersions[ matchedVersion ].version;
	}

}
