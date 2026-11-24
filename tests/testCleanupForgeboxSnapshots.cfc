component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver/services" )
		};
	}

	function run( testResults, testBox ) {

		describe( "cleanupForgeboxSnapshots", function() {

			it( title="lists and deletes only forgebox*-SNAPSHOT.zip at the bucket root", body=function() {
				var work = GetTempDirectory() & "cleanup-fb-snapshots-" & CreateUniqueId() & "/";
				DirectoryCreate( work, true );
				DirectoryCreate( work & "subdir", true );

				var keep = [
					"forgebox-6.2.1.122.zip",
					"forgebox-6.2.1.122-RC.zip",
					"forgebox-6.2.1.122-BETA.zip",
					"lucee-6.2.1.122-SNAPSHOT.zip",
					"lucee-6.2.1.122.jar",
					"6.2.1.122.lco",
					"subdir/forgebox-1.0.0.1-SNAPSHOT.zip"
				];
				var remove = [
					"forgebox-6.2.1.122-SNAPSHOT.zip",
					"forgebox-light-6.2.1.122-SNAPSHOT.zip",
					"FORGEBOX-7.0.0.1-snapshot.ZIP"
				];
				loop array=keep item="local.name" {
					FileWrite( work & name, "keep" );
				}
				loop array=remove item="local.name" {
					FileWrite( work & name, "remove" );
				}

				var savedVersions = StructKeyExists( application, "s3VersionData" ) ? Duplicate( application.s3VersionData ) : javacast( "null", "" );
				var cacheFile = ExpandPath( variables.dir & "../apps/updateserver/services/legacy/cache/versions.json" );
				var cacheBackup = FileExists( cacheFile ) ? FileRead( cacheFile ) : "";
				var cacheExisted = FileExists( cacheFile );

				try {
					var s3 = new services.legacy.S3( work );
					var preview = s3.cleanupForgeboxSnapshots( true );

					expect( preview.dryRun ).toBeTrue();
					expect( preview.count ).toBe( 3 );
					expect( preview.errors ).toBe( [] );
					loop array=remove item="local.name" {
						expect( preview.deleted ).toInclude( name );
						expect( FileExists( work & name ) ).toBeTrue();
					}
					loop array=keep item="local.name" {
						expect( preview.deleted ).notToInclude( ListLast( name, "/" ) );
						expect( FileExists( work & name ) ).toBeTrue();
					}

					var result = s3.cleanupForgeboxSnapshots( false );
					expect( result.dryRun ).toBeFalse();
					expect( result.count ).toBe( 3 );
					expect( result.errors ).toBe( [] );
					loop array=remove item="local.name" {
						expect( result.deleted ).toInclude( name );
						expect( FileExists( work & name ) ).toBeFalse();
					}
					loop array=keep item="local.name" {
						expect( FileExists( work & name ) ).toBeTrue();
					}

					var again = s3.cleanupForgeboxSnapshots( true );
					expect( again.count ).toBe( 0 );
					expect( again.deleted ).toBe( [] );
				}
				finally {
					if ( !IsNull( savedVersions ) ) {
						application.s3VersionData = savedVersions;
					}
					else {
						StructDelete( application, "s3VersionData", false );
					}
					if ( cacheExisted ) {
						FileWrite( cacheFile, cacheBackup );
					}
					else if ( FileExists( cacheFile ) ) {
						FileDelete( cacheFile );
					}
					if ( DirectoryExists( work ) ) {
						DirectoryDelete( work, true );
					}
				}
			});

		});
	}

}
