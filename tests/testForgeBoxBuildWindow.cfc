component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : expandPath( dir & "../apps/updateserver/services" )
		};

		variables.s3 = new services.legacy.S3( getTempDirectory() );
	}

	function run( testResults, testBox ) {

		describe( "Artifacts: finals always, otherwise only a jar not older than 24 hours", function() {

			it( title="a final is always built, even when the jar is older than 24 hours or has no date", body=function() {
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.0.321", "date-jar"=dateAdd( "h", -48, now() ) } ) ).toBeTrue();
				expect( variables.s3.shouldBuildArtifacts( { version="5.4.6.9" } ) ).toBeTrue();
			});

			it( title="a non-final under 24 hours is built (SNAPSHOT, RC, BETA, ALPHA)", body=function() {
				var recent = dateAdd( "n", -23 * 60, now() );
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT", "date-jar"=recent } ) ).toBeTrue();
				expect( variables.s3.shouldBuildArtifacts( { version="7.1.0.5-RC", "date-jar"=recent } ) ).toBeTrue();
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.0.1-BETA", "date-jar"=recent } ) ).toBeTrue();
				expect( variables.s3.shouldBuildArtifacts( { version="8.0.0.1-ALPHA", "date-jar"=recent } ) ).toBeTrue();
			});

			it( title="a non-final over 24 hours is skipped for all types", body=function() {
				var old = dateAdd( "h", -24, now() );
				old = dateAdd( "n", -1, old );
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT", "date-jar"=old } ) ).toBeFalse();
				expect( variables.s3.shouldBuildArtifacts( { version="7.1.0.5-RC", "date-jar"=old } ) ).toBeFalse();
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.0.1-BETA", "date-jar"=old } ) ).toBeFalse();
				expect( variables.s3.shouldBuildArtifacts( { version="8.0.0.1-ALPHA", "date-jar"=old } ) ).toBeFalse();
			});

			it( title="a non-final with a missing or unusable date-jar is skipped", body=function() {
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT" } ) ).toBeFalse();
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT", "date-jar"="" } ) ).toBeFalse();
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT", "date-jar"="not-a-date" } ) ).toBeFalse();
			});

			it( title="a non-final is built at the 24 hour boundary", body=function() {
				expect( variables.s3.shouldBuildArtifacts( { version="6.2.1.7-SNAPSHOT", "date-jar"=dateAdd( "h", -24, now() ) } ) ).toBeTrue();
			});

			it( title="shouldBuildForgeBox remains a wrapper for shouldBuildArtifacts", body=function() {
				var recent = dateAdd( "n", -23 * 60, now() );
				var old = dateAdd( "n", -1, dateAdd( "h", -24, now() ) );
				expect( variables.s3.shouldBuildForgeBox( { version="6.2.0.321", "date-jar"=old } ) ).toBeTrue();
				expect( variables.s3.shouldBuildForgeBox( { version="6.2.1.7-SNAPSHOT", "date-jar"=recent } ) ).toBeTrue();
				expect( variables.s3.shouldBuildForgeBox( { version="6.2.1.7-SNAPSHOT", "date-jar"=old } ) ).toBeFalse();
				expect( variables.s3.shouldBuildForgeBox( { version="6.2.1.7-SNAPSHOT" } ) ).toBeFalse();
			});

		});
	}

}
