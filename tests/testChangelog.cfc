component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );
		application action="update" mappings={
			"/download" : expandPath( dir & "../apps/download" )
		};
		variables.changelog = new download.changelog( new download.download() );
	}

	function run( testResults, testBox ) {
		describe( "changelog version filtering", function() {

			it( "should include RC versions in major", function() {
				var versions = {
					"07.000.000.0392.075": {
						"version": "7.0.0.392-RC",
						"war": "lucee-7.0.0.392-RC.war"
					}
				};

				var result = changelog.processVersions( versions );

				expect( result.major ).toHaveKey( "07.000.000.0392.075" );
				expect( result.major[ "07.000.000.0392.075" ].type ).toBe( "rc" );
			});

			it( "should include latest snapshot per major version in major", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"war": "lucee-7.0.1.44-SNAPSHOT.war"
					},
					"07.000.001.0043.000": {
						"version": "7.0.1.43-SNAPSHOT",
						"war": "lucee-7.0.1.43-SNAPSHOT.war"
					}
				};

				var result = changelog.processVersions( versions );

				// Only the latest snapshot (7.0.1.44) should be in major
				expect( result.major ).toHaveKey( "07.000.001.0044.000" );
				expect( result.major ).notToHaveKey( "07.000.001.0043.000" );
				expect( result.major[ "07.000.001.0044.000" ].type ).toBe( "snapshots" );
			});

			it( "should show 7.0.1.44-SNAPSHOT as lead version with 7.0.0.392-RC also showing", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"war": "lucee-7.0.1.44-SNAPSHOT.war"
					},
					"07.000.000.0392.075": {
						"version": "7.0.0.392-RC",
						"war": "lucee-7.0.0.392-RC.war"
					}
				};

				var result = changelog.processVersions( versions );

				// Both should be in major - snapshot is newer so it's the lead version
				expect( result.major ).toHaveKey( "07.000.001.0044.000" );
				expect( result.major ).toHaveKey( "07.000.000.0392.075" );
				expect( result.major[ "07.000.001.0044.000" ].type ).toBe( "snapshots" );
				expect( result.major[ "07.000.000.0392.075" ].type ).toBe( "rc" );
			});

			it( "should filter out snapshots when a release exists for same version", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"versionSorted": "07.000.001.0044.000",
						"war": "lucee-7.0.1.44-SNAPSHOT.war"
					},
					"07.000.001.0044.100": {
						"version": "7.0.1.44",
						"war": "lucee-7.0.1.44.war"
					}
				};

				var result = changelog.processVersions( versions );

				// snapshot should be removed from major because release exists
				expect( result.major ).toHaveKey( "07.000.001.0044.100" );
				expect( result.major ).notToHaveKey( "07.000.001.0044.000" );
			});

			it( "should sort versions newest first", function() {
				var major = {
					"07.000.000.0392.075": { "version": "7.0.0.392-RC" },
					"07.000.001.0044.000": { "version": "7.0.1.44-SNAPSHOT" },
					"07.000.000.0388.075": { "version": "7.0.0.388-RC" }
				};

				var sorted = changelog.getSortedVersions( major );

				expect( sorted[ 1 ] ).toBe( "07.000.001.0044.000" );
				expect( sorted[ 2 ] ).toBe( "07.000.000.0392.075" );
				expect( sorted[ 3 ] ).toBe( "07.000.000.0388.075" );
			});

		});

		describe( "buildChangelogData method", function() {

			it( "should build changelog data array with correct structure", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"type": "snapshots"
					},
					"07.000.000.0392.075": {
						"version": "7.0.0.392-RC",
						"type": "rc"
					}
				};

				var arrVersions = [ "07.000.001.0044.000", "07.000.000.0392.075" ];

				var result = changelog.buildChangelogData( versions, arrVersions, "7.0" );

				expect( result ).toBeArray();
				expect( arrayLen( result ) ).toBe( 2 );

				// Check first version (latest snapshot)
				expect( result[ 1 ].version ).toBe( "7.0.1.44-SNAPSHOT" );
				expect( result[ 1 ].type ).toBe( "snapshots" );
				expect( result[ 1 ]._version ).toBe( "07.000.001.0044.000" );
				expect( result[ 1 ].prevVersion ).toBe( "7.0.0.392-RC" );
				expect( result[ 1 ].header ).toBe( "h4" );

				// Check second version (RC)
				expect( result[ 2 ].version ).toBe( "7.0.0.392-RC" );
				expect( result[ 2 ].type ).toBe( "rc" );
			});

			it( "should set h2 header for releases", function() {
				var versions = {
					"07.000.001.0044.100": {
						"version": "7.0.1.44",
						"type": "releases"
					}
				};

				var arrVersions = [ "07.000.001.0044.100" ];

				var result = changelog.buildChangelogData( versions, arrVersions, "7.0" );

				expect( result[ 1 ].header ).toBe( "h2" );
				expect( result[ 1 ].versionTitle ).toBe( "7.0.1.44 Stable" );
			});

			it( "should only fetch changelog for matching major version", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"type": "snapshots"
					},
					"06.002.000.0030.100": {
						"version": "6.2.0.30",
						"type": "releases"
					}
				};

				var arrVersions = [ "07.000.001.0044.000", "06.002.000.0030.100" ];

				var result = changelog.buildChangelogData( versions, arrVersions, "7.0" );

				// 7.0 version should have changelog fetched (non-empty)
				// 6.2 version should have empty changelog struct
				expect( result[ 1 ].version ).toBe( "7.0.1.44-SNAPSHOT" );
				expect( result[ 2 ].version ).toBe( "6.2.0.30" );
				expect( structCount( result[ 2 ].changelog ) ).toBe( 0 );
			});

			it( "should determine prevVersion correctly for last item", function() {
				var versions = {
					"07.000.001.0044.000": {
						"version": "7.0.1.44-SNAPSHOT",
						"type": "snapshots"
					},
					"07.000.000.0392.075": {
						"version": "7.0.0.392-RC",
						"type": "rc"
					},
					"07.000.000.0388.075": {
						"version": "7.0.0.388-RC",
						"type": "rc"
					}
				};

				var arrVersions = [ "07.000.001.0044.000", "07.000.000.0392.075", "07.000.000.0388.075" ];

				var result = changelog.buildChangelogData( versions, arrVersions, "7.0" );

				// Last item should use the oldest version as prevVersion
				expect( result[ 3 ].version ).toBe( "7.0.0.388-RC" );
				expect( result[ 3 ].prevVersion ).toBe( "7.0.0.388-RC" );
			});

		});
	}

}
