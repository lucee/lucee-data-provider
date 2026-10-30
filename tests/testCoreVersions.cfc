component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = getDirectoryFromPath( getCurrentTemplatePath() );

		application action="update" mappings={
			  "/services"       : expandPath( dir & "../apps/updateserver/services" )
			, "/updateprovider" : expandPath( dir & "../apps/updateserver/rest" )
		};

		variables.releases  = "https://releases.example.invalid/maven2/";
		variables.snapshots = "https://snapshots.example.invalid/maven-snapshots/";
		variables.mixed     = "https://mixed.example.invalid/";
		variables.cdnUrl    = "https://cdn.example.invalid/";
	}

	function run( testResults , testBox ) {

		describe( "LDEV-6796 the core versions: Maven first, with the flat S3 files as the fallback", function() {

			it( title="lists the versions of the core of all the repositories, a repository only has what it is meant to have", body=function() {
				var found = _newMaven( _newWorld() ).listVersions();

				expect( found.complete ).toBeTrue();
				expect( found.versions ).toHaveKey( "6.2.0.321" );
				expect( found.versions ).toHaveKey( "7.1.0.5-RC" );
				expect( found.versions ).toHaveKey( "8.0.0.1-ALPHA" );
				expect( found.versions ).toHaveKey( "6.2.1.7-SNAPSHOT" );
				// a snapshot in the releases and a release in the snapshots repository is not taken
				expect( found.versions ).notToHaveKey( "6.2.1.5-SNAPSHOT" );
				expect( found.versions ).notToHaveKey( "6.2.0.99" );
				// the repositories of the kind of the version first, then the mixed one
				expect( found.versions[ "6.2.0.321" ] ).toBe( [ releases, mixed ] );
				expect( found.versions[ "6.2.1.7-SNAPSHOT" ] ).toBe( [ snapshots, mixed ] );
			});

			it( title="merges the Maven versions with the flat ones, only the versions the update provider offers, sorted", body=function() {
				var versions = _newVersions( _newWorld() ).getVersions();
				var all      = _versionList( versions );

				// only in the flat files, only in Maven, and in both
				expect( all ).toInclude( "5.3.10.120" );
				expect( all ).toInclude( "6.2.0.300" );
				expect( all ).toInclude( "7.1.1.2-SNAPSHOT" );
				expect( all ).toInclude( "6.2.0.321" );
				// what is not a version, and 7.0.0.202
				expect( all ).notToInclude( "garbage" );
				expect( all ).notToInclude( "7.0.0.202" );
				expect( all ).notToInclude( "7.0.0.1-FOO" );

				// sorted
				var sorted = Duplicate( all );
				ArraySort( sorted, function( a, b ) { return Compare( services.VersionUtils::toVersionSortable( a ), services.VersionUtils::toVersionSortable( b ) ); } );
				expect( all ).toBe( sorted );

				// the key is the sortable version, as it is for the flat files
				expect( versions ).toHaveKey( services.VersionUtils::toVersionSortable( "6.2.0.321" ) );
			});

			it( title="gives the types of a version that is only in Maven the names of the flat files, and keeps the ones of the flat files", body=function() {
				var versions = _newVersions( _newWorld() ).getVersions();
				var maven    = versions[ services.VersionUtils::toVersionSortable( "7.1.1.2-SNAPSHOT" ) ];
				var both     = versions[ services.VersionUtils::toVersionSortable( "6.2.0.321" ) ];
				var flat     = versions[ services.VersionUtils::toVersionSortable( "5.3.10.120" ) ];

				expect( maven.jar ).toBe( "lucee-7.1.1.2-SNAPSHOT.jar" );
				expect( maven.light ).toBe( "lucee-light-7.1.1.2-SNAPSHOT.jar" );
				expect( maven.zero ).toBe( "lucee-zero-7.1.1.2-SNAPSHOT.jar" );
				expect( maven.lco ).toBe( "7.1.1.2-SNAPSHOT.lco" );
				expect( maven.war ).toBe( "lucee-7.1.1.2-SNAPSHOT.war" );
				expect( maven.express ).toBe( "lucee-express-7.1.1.2-SNAPSHOT.zip" );

				// the flat types that are not in Maven stay
				expect( both ).toHaveKey( "win64" );
				expect( flat.forgebox ).toBe( "forgebox-5.3.10.120.zip" );
			});

			it( title="does not change what the flat source returned", body=function() {
				var world = _newWorld();
				var flat  = _flatFiles();
				var core  = _newVersions( world, { flat=flat } );

				core.getVersions();

				expect( flat[ services.VersionUtils::toVersionSortable( "6.2.0.321" ) ] ).notToHaveKey( "war" );
			});

			it( title="drops the versions that are only in the flat files when the fallback is off, and does not read them", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { flatFallback=false } );
				var all   = _versionList( core.getVersions() );

				expect( all ).toInclude( "6.2.0.321" );
				expect( all ).toInclude( "7.1.1.2-SNAPSHOT" );
				expect( all ).notToInclude( "5.3.10.120" );
				expect( all ).notToInclude( "6.2.0.300" );
				expect( world.flatReads ).toBe( 0 );
			});

			it( title="serves the flat files when there is no Maven source, even with the fallback off", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { maven="", flatFallback=false } );

				expect( _versionList( core.getVersions() ) ).toBe( [ "5.3.10.120", "6.2.0.300", "6.2.0.321", "7.0.0.1" ] );
				expect( core.resolveFile( "jar", "6.2.0.300" ).url ).toBe( cdnUrl & "lucee-6.2.0.300.jar" );
			});

			it( title="serves the flat files when the Maven layout has no version, even with the fallback off", body=function() {
				var world = _newWorld();

				for ( var repo in [ releases, snapshots, mixed ] ) {
					world.status[ repo & "org/lucee/lucee/maven-metadata.xml" ] = 503;
				}

				var core = _newVersions( world, { flatFallback=false } );

				expect( _versionList( core.getVersions() ) ).toBe( [ "5.3.10.120", "6.2.0.300", "6.2.0.321", "7.0.0.1" ] );
				expect( core.resolveFile( "lco", "6.2.0.300" ).url ).toBe( cdnUrl & "6.2.0.300.lco" );
			});

			it( title="does not fail when the flat files can't be read, the Maven versions are enough", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { flatBroken=true } );

				expect( _versionList( core.getVersions() ) ).toInclude( "6.2.0.321" );
				expect( _versionList( core.getVersions() ) ).notToInclude( "6.2.0.300" );
			});

			it( title="fails when no version can be found at all", body=function() {
				var world = _newWorld();

				for ( var repo in [ releases, snapshots, mixed ] ) {
					world.status[ repo & "org/lucee/lucee/maven-metadata.xml" ] = 503;
				}

				var core = _newVersions( world, { flatBroken=true } );

				expect( function() { core.getVersions(); } ).toThrow();
			});

			it( title="keeps the versions it has when they can't be read again", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { cacheSeconds=0 } );

				expect( _versionList( core.getVersions() ) ).toInclude( "7.1.1.2-SNAPSHOT" );

				for ( var repo in [ releases, snapshots, mixed ] ) {
					world.status[ repo & "org/lucee/lucee/maven-metadata.xml" ] = 503;
				}
				world.flatFails = true;

				expect( _versionList( core.getVersions() ) ).toInclude( "7.1.1.2-SNAPSHOT" );
				expect( _versionList( core.getVersions() ) ).toInclude( "6.2.0.321" );
			});

			it( title="reads the repositories once while the versions are fresh, and again after a reset", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world );

				core.getVersions();
				var requests = ArrayLen( world.requests );
				core.getVersions();
				expect( ArrayLen( world.requests ) ).toBe( requests );

				core.reset();
				core.getVersions();
				expect( ArrayLen( world.requests ) ).toBeGT( requests );

				requests = ArrayLen( world.requests );
				core.getVersions( flush=true );
				expect( ArrayLen( world.requests ) ).toBeGT( requests );
			});

			it( title="offers the versions the update provider offers, as the flat files do", body=function() {
				var core = _newVersions( _newWorld() );

				expect( core.isOffered( "6.2.0.321" ) ).toBeTrue();
				expect( core.isOffered( "6.2.0.321-SNAPSHOT" ) ).toBeTrue();
				expect( core.isOffered( "7.1.0.5-RC" ) ).toBeTrue();
				expect( core.isOffered( "7.1.0.5-BETA" ) ).toBeTrue();
				expect( core.isOffered( "8.0.0.1-ALPHA" ) ).toBeTrue();
				expect( core.isOffered( "7.0.0.202" ) ).toBeFalse();
				expect( core.isOffered( "7.0.0.202-SNAPSHOT" ) ).toBeTrue();
				expect( core.isOffered( "7.0.0.1-FOO" ) ).toBeFalse();
				expect( core.isOffered( "7.0.0" ) ).toBeFalse();
				expect( core.isOffered( "7.0.0.x" ) ).toBeFalse();
				expect( core.isOffered( "a.0.0.1" ) ).toBeFalse();
				expect( core.isOffered( "6.2.0.1-SNAPSHOT-X" ) ).toBeFalse();
			});

		});

		describe( "LDEV-6796 the files of the core", function() {

			it( title="points to the file in the Maven layout, the mixed repository first, nothing is counted as the fallback", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world );

				expect( core.resolveFile( "jar", "6.2.0.321" ) ).toBe( { url=mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar", source="maven", present=true } );
				expect( core.resolveFile( "light", "6.2.0.321" ).url ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar" );
				expect( core.resolveFile( "zero", "6.2.0.321" ).url ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-zero.jar" );
				expect( core.resolveFile( "lco", "6.2.0.321" ).url ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" );
				expect( core.resolveFile( "war", "6.2.0.321" ).url ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.war" );
				expect( core.resolveFile( "express", "6.2.0.321" ).url ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-express.zip" );

				expect( core.getFlatFallbackHits() ).toBe( {} );
			});

			it( title="asks the next repository when the first has no file, and does not point to a repository that fails", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world );

				// the bridge doesn't know the file, the releases do
				world.missing[ mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar" ] = true;
				expect( core.resolveFile( "jar", "6.2.0.321" ).url ).toBe( releases & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar" );

				// the bridge fails: not pointed to (fallback off, so that nothing else is served)
				var failing = _newVersions( world, { flatFallback=false } );
				world.status[ mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.war" ] = 503;
				world.status[ releases & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.war" ] = 503;
				expect( failing.resolveFile( "war", "6.2.0.321" ) ).toBe( {} );
			});

			it( title="asks a repository once if it has a file", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world );
				var fileUrl = mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar";

				core.resolveFile( "jar", "6.2.0.321" );
				core.resolveFile( "jar", "6.2.0.321" );
				expect( _heads( world, fileUrl ) ).toBe( 1 );
			});

			it( title="uses the timestamped file of a snapshot when the repository has one", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { maven=_newMaven( world, { mixedRepos=[], releaseRepos=[], snapshotRepos=[ snapshots ] } ) } );

				expect( core.resolveFile( "jar", "6.2.1.7-SNAPSHOT" ).url )
					.toBe( snapshots & "org/lucee/lucee/6.2.1.7-SNAPSHOT/lucee-6.2.1.7-20261022.163826-3.jar" );
				expect( core.resolveFile( "light", "6.2.1.7-SNAPSHOT" ).url )
					.toBe( snapshots & "org/lucee/lucee/6.2.1.7-SNAPSHOT/lucee-6.2.1.7-20261022.163826-2-light.jar" );
				// not in the metadata: the plain name
				expect( core.resolveFile( "war", "6.2.1.7-SNAPSHOT" ).url )
					.toBe( snapshots & "org/lucee/lucee/6.2.1.7-SNAPSHOT/lucee-6.2.1.7-SNAPSHOT.war" );
			});

			it( title="serves the file from the flat files, logs and counts it, when it is not in the Maven layout (the fallback is on)", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world );

				// a version only in the flat files
				expect( core.resolveFile( "jar", "6.2.0.300" ) ).toBe( { url=cdnUrl & "lucee-6.2.0.300.jar", source="flat", present=true } );
				// the file is not in Maven, but in the flat files (for the types of the flat files the names are the ones of the flat files)
				world.missing[ mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" ] = true;
				world.missing[ releases & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" ] = true;
				expect( core.resolveFile( "lco", "6.2.0.321" ) ).toBe( { url=cdnUrl & "6.2.0.321.lco", source="flat", present=true } );
				// the flat files don't have it either, it is up to the caller to have it built
				expect( core.resolveFile( "war", "6.2.0.300" ) ).toBe( { url=cdnUrl & "lucee-6.2.0.300.war", source="flat", present=false } );
				// a type that is not known
				expect( core.resolveFile( "nope", "6.2.0.300" ) ).toBe( {} );

				expect( core.getFlatFallbackHits() ).toBe( {
					  "lucee-6.2.0.300.jar" : 1
					, "6.2.0.321.lco"       : 1
					, "lucee-6.2.0.300.war" : 1
				} );

				core.resolveFile( "jar", "6.2.0.300" );
				expect( core.getFlatFallbackHits()[ "lucee-6.2.0.300.jar" ] ).toBe( 2 );
			});

			it( title="does not serve what is only in the flat files when the fallback is off", body=function() {
				var world = _newWorld();
				var core  = _newVersions( world, { flatFallback=false } );

				expect( core.resolveFile( "jar", "6.2.0.300" ) ).toBe( {} );
				expect( core.resolveFile( "jar", "6.2.0.321" ).source ).toBe( "maven" );

				world.missing[ mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" ] = true;
				world.missing[ releases & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" ] = true;
				expect( core.resolveFile( "lco", "6.2.0.321" ) ).toBe( {} );

				expect( core.getFlatFallbackHits() ).toBe( {} );
			});

			it( title="does not know a file of a version nobody has", body=function() {
				var core = _newVersions( _newWorld() );

				expect( core.resolveFile( "jar", "1.2.3.4" ).source ).toBe( "flat" ); // the fallback has a name for it, the caller has it built or not
				expect( _newVersions( _newWorld(), { flatFallback=false } ).resolveFile( "jar", "1.2.3.4" ) ).toBe( {} );
			});

			it( title="has no flat file when there is no url for them", body=function() {
				var core = _newVersions( _newWorld(), { flatUrl="" } );

				expect( core.resolveFile( "jar", "6.2.0.300" ) ).toBe( {} );
			});

		});

		describe( "LDEV-6796 the versions a calling Lucee can load", function() {

			it( title="shows the versions of the major of the caller by default", body=function() {
				var core     = _newVersions( _newWorld() );
				var versions = core.getVersions();

				expect( core.getVersionFilter() ).toBe( "major" );
				expect( _versionList( core.filterForCaller( versions, "6.2.0.1" ) ) ).toBe( [ "6.2.0.1", "6.2.0.300", "6.2.0.321", "6.2.1.7-SNAPSHOT" ] );
				expect( _versionList( core.filterForCaller( versions, { major=7 } ) ) ).toBe( [ "7.0.0.1", "7.1.0.5-RC", "7.1.1.2-SNAPSHOT" ] );
				expect( _versionList( core.filterForCaller( versions, "5.3.9.1" ) ) ).toBe( [ "5.3.10.120" ] );
				// nothing for a major that has no version
				expect( core.filterForCaller( versions, "4.0.0.1" ) ).toBe( {} );
				// not changed
				expect( _versionList( versions ) ).toInclude( "7.1.0.5-RC" );
			});

			it( title="keeps the order of the versions", body=function() {
				var core     = _newVersions( _newWorld() );
				var filtered = core.filterForCaller( core.getVersions(), "6.2.0.1" );
				var sorted   = StructKeyArray( filtered );

				ArraySort( sorted, "textnocase" );
				expect( StructKeyArray( filtered ) ).toBe( sorted );
			});

			it( title="shows all the versions with the filter none, as it was", body=function() {
				var core     = _newVersions( _newWorld(), { versionFilter="none" } );
				var versions = core.getVersions();

				expect( core.getVersionFilter() ).toBe( "none" );
				expect( _versionList( core.filterForCaller( versions, "6.2.0.1" ) ) ).toBe( _versionList( versions ) );
				expect( _versionList( _newVersions( _newWorld(), { versionFilter="off" } ).filterForCaller( versions, "6.2.0.1" ) ) ).toBe( _versionList( versions ) );
			});

			it( title="shows the majors of a rule, the major of the caller when it has no rule", body=function() {
				var core     = _newVersions( _newWorld(), { versionFilter="6:6-7, 5:5" } );
				var versions = core.getVersions();

				expect( _versionList( core.filterForCaller( versions, "6.2.0.1" ) ) ).toBe( [ "6.2.0.1", "6.2.0.300", "6.2.0.321", "6.2.1.7-SNAPSHOT", "7.0.0.1", "7.1.0.5-RC", "7.1.1.2-SNAPSHOT" ] );
				expect( _versionList( core.filterForCaller( versions, "5.3.9.1" ) ) ).toBe( [ "5.3.10.120" ] );
				expect( _versionList( core.filterForCaller( versions, "7.0.0.1" ) ) ).toBe( [ "7.0.0.1", "7.1.0.5-RC", "7.1.1.2-SNAPSHOT" ] );
				expect( core.getVersionFilter() ).toBe( "6:6-7, 5:5" );
			});

			it( title="uses the default for a filter that is not valid, and says so", body=function() {
				for ( var spec in [ "everything", "6:", "6:7-6", "6:6,x" ] ) {
					var core = _newVersions( _newWorld(), { versionFilter=spec } );

					expect( core.getVersionFilter() ).toBe( "major", spec );
					expect( _versionList( core.filterForCaller( core.getVersions(), "6.2.0.1" ) ) ).toBe( [ "6.2.0.1", "6.2.0.300", "6.2.0.321", "6.2.1.7-SNAPSHOT" ] );
				}
			});

			it( title="uses the default for an empty filter", body=function() {
				expect( _newVersions( _newWorld(), { versionFilter="" } ).getVersionFilter() ).toBe( "major" );
			});

		});

		describe( "LDEV-6796 the update provider", function() {

			beforeEach( function() {
				// the update provider reads what it needs from the application
				variables.saved = {};
				for ( var key in [ "bundleDownloadService", "coreS3Root", "coreCdnUrl", "jiraChangelogService", "coreVersions" ] ) {
					variables.saved[ key ] = application[ key ] ?: javacast( "null", 0 );
				}
			});

			afterEach( function() {
				for ( var key in [ "bundleDownloadService", "coreS3Root", "coreCdnUrl", "jiraChangelogService", "coreVersions" ] ) {
					if ( IsNull( variables.saved[ key ] ) ) {
						StructDelete( application, key );
					} else {
						application[ key ] = variables.saved[ key ];
					}
				}
			});

			it( title="offers a calling Lucee only the versions it can load, and the newest of those", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );

				var six = provider.getInfo( "6.1.0.1" );
				expect( six.type ).toBe( "info" );
				expect( six.available ).toBe( "6.2.1.7-SNAPSHOT" );
				expect( six.otherVersions ).toBe( [ "6.2.0.1", "6.2.0.300", "6.2.0.321", "6.2.1.7-SNAPSHOT" ] );

				var seven = provider.getInfo( "7.0.0.1" );
				expect( seven.available ).toBe( "7.1.1.2-SNAPSHOT" );
				expect( seven.otherVersions ).toBe( [ "7.0.0.1", "7.1.0.5-RC", "7.1.1.2-SNAPSHOT" ] );

				expect( provider.getInfoSimple( "6.1.0.1" ) ).toBe( "6.2.1.7-SNAPSHOT" );
			});

			it( title="says there is no update when the newest version of the major is the one of the caller", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );
				var info     = provider.getInfo( "6.2.1.7-SNAPSHOT" );

				expect( info.type ).toBe( "info" );
				expect( info.message ).toInclude( "no update" );
				expect( info.message ).toInclude( "Latest version is [6.2.1.7-SNAPSHOT]" );
				expect( info.otherVersions ).toBe( [ "6.2.0.1", "6.2.0.300", "6.2.0.321", "6.2.1.7-SNAPSHOT" ] );
			});

			it( title="says there is no update when there is no version of the major of the caller", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );
				var info     = provider.getInfo( "9.0.0.1" );

				expect( info.type ).toBe( "info" );
				expect( info.message ).toInclude( "no update" );
				expect( info.otherVersions ).toBe( [] );
			});

			it( title="offers the newest of all versions as before with the filter none", body=function() {
				var provider = _newProvider( _newVersions( _newWorld(), { versionFilter="none" } ) );
				var info     = provider.getInfo( "6.1.0.1" );

				expect( info.available ).toBe( "8.0.0.1-ALPHA" );
				expect( info.otherVersions ).toInclude( "5.3.10.120" );
				expect( info.otherVersions ).toInclude( "7.0.0.1" );
			});

			it( title="does not filter the versions for the version of all versions", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );
				var info     = provider.getInfo( "0.0.0.0" );

				expect( info.type ).toBe( "info" );
				expect( info.available ).toBe( "8.0.0.1-ALPHA" );
			});

			it( title="redirects the downloads to the files in the Maven layout", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );
				var response = getPageContext().getResponse();

				provider.downLoader( "6.2.0.321" );
				expect( _locations( response ) ).toInclude( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar" );
				provider.downLight( "6.2.0.321" );
				expect( _locations( response ) ).toInclude( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-light.jar" );
				provider.downloadCore( "6.2.0.321" );
				expect( _locations( response ) ).toInclude( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.lco" );
				provider.downloadWar( "6.2.0.321" );
				expect( _locations( response ) ).toInclude( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.war" );
				provider.downloadExpress( "6.2.0.321" );
				expect( _locations( response ) ).toInclude( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321-express.zip" );
			});

			it( title="gets the latest version from the Maven layout, and the file of the version the flat files have", body=function() {
				var provider = _newProvider( _newVersions( _newWorld() ) );

				// a version the filter would hide for a 6 is still the latest of "all"
				expect( provider.getLatest( 0, "all", "jar", "string" ) ).toBe( "8.0.0.1-ALPHA" );
				expect( provider.getLatest( 6, "snapshot", "jar", "string" ) ).toBe( "6.2.1.7-SNAPSHOT" );
				expect( provider.getLatest( "6.2.0", "stable", "jar", "string" ) ).toBe( "6.2.0.321" );

				// the url is the one of the Maven layout, or the flat one for a version only the flat files have
				expect( provider.getLatest( "6.2.0.321", "all", "jar", "url" ) ).toBe( mixed & "org/lucee/lucee/6.2.0.321/lucee-6.2.0.321.jar" );
				expect( provider.getLatest( "6.2.0.300", "all", "jar", "url" ) ).toBe( cdnUrl & "lucee-6.2.0.300.jar" );
				expect( provider.getLatest( "6.2.0.300", "all", "jar", "filename" ) ).toBe( "lucee-6.2.0.300.jar" );
			});

			it( title="gets the latest version that has the file", body=function() {
				var world = _newWorld();

				// the two newest versions have no war, anywhere
				for ( var version in [ "7.1.1.2-SNAPSHOT", "8.0.0.1-ALPHA" ] ) {
					world.missing[ mixed & "org/lucee/lucee/#version#/lucee-#version#.war" ] = true;
				}

				var provider = _newProvider( _newVersions( world, { flatFallback=false } ) );

				expect( provider.getLatest( 0, "all", "war", "string" ) ).toBe( "7.1.0.5-RC" );
			});

		});

	}

// the world

	// the repositories: what they have, and what they answer
	private struct function _newWorld() {
		var world = {
			  pages     = {}
			, missing   = {}
			, status    = {}
			, requests  = ArrayNew( 1, true )
			, heads     = ArrayNew( 1, true )
			, flatReads = 0
			, flatFails = false
		};
		var core = "org/lucee/lucee/";

		_setMetadata( world, releases , [ "6.2.0.1", "6.2.0.321", "7.0.0.1", "7.0.0.202", "7.1.0.5-RC", "7.0.0.1-FOO", "garbage", "6.2.1.5-SNAPSHOT" ] );
		_setMetadata( world, snapshots, [ "6.2.1.7-SNAPSHOT", "6.2.0.99" ] );
		_setMetadata( world, mixed    , [ "6.2.0.321", "7.1.0.5-RC", "7.1.1.2-SNAPSHOT", "8.0.0.1-ALPHA", "6.2.1.7-SNAPSHOT" ] );

		// the timestamped files of a snapshot in the snapshots repository
		world.pages[ snapshots & core & "6.2.1.7-SNAPSHOT/maven-metadata.xml" ] =
			"<?xml version=""1.0"" encoding=""UTF-8""?><metadata><groupId>org.lucee</groupId><artifactId>lucee</artifactId><version>6.2.1.7-SNAPSHOT</version><versioning>"
			& "<snapshot><timestamp>20261022.163826</timestamp><buildNumber>3</buildNumber></snapshot><lastUpdated>20261022163826</lastUpdated><snapshotVersions>"
			& "<snapshotVersion><classifier>light</classifier><extension>jar</extension><value>6.2.1.7-20261022.163826-2</value><updated>20261022163826</updated></snapshotVersion>"
			& "<snapshotVersion><extension>pom</extension><value>6.2.1.7-20261022.163826-3</value><updated>20261022163826</updated></snapshotVersion>"
			& "<snapshotVersion><extension>jar</extension><value>6.2.1.7-20261022.163826-3</value><updated>20261022163826</updated></snapshotVersion>"
			& "</snapshotVersions></versioning></metadata>";

		return world;
	}

	private function _setMetadata( world, repo, versions ) {
		var xml = "<?xml version=""1.0"" encoding=""UTF-8""?><metadata><groupId>org.lucee</groupId><artifactId>lucee</artifactId><versioning><versions>";

		for ( var version in arguments.versions ) {
			xml &= "<version>#version#</version>";
		}

		arguments.world.pages[ arguments.repo & "org/lucee/lucee/maven-metadata.xml" ] = xml & "</versions></versioning></metadata>";
	}

	// the flat files of S3 as the S3 component returns them
	private struct function _flatFiles() {
		var flat = StructNew( "linked" );

		flat[ services.VersionUtils::toVersionSortable( "5.3.10.120" ) ] = {
			  version="5.3.10.120", jar="lucee-5.3.10.120.jar", light="lucee-light-5.3.10.120.jar", lco="5.3.10.120.lco"
			, war="lucee-5.3.10.120.war", express="lucee-express-5.3.10.120.zip", forgebox="forgebox-5.3.10.120.zip"
		};
		flat[ services.VersionUtils::toVersionSortable( "6.2.0.300" ) ] = {
			  version="6.2.0.300", jar="lucee-6.2.0.300.jar", light="lucee-light-6.2.0.300.jar", lco="6.2.0.300.lco"
		};
		flat[ services.VersionUtils::toVersionSortable( "6.2.0.321" ) ] = {
			  version="6.2.0.321", jar="lucee-6.2.0.321.jar", light="lucee-light-6.2.0.321.jar", lco="6.2.0.321.lco", win64="lucee-6.2.0.321-pl0-windows-x64-installer.exe"
		};
		flat[ services.VersionUtils::toVersionSortable( "7.0.0.1" ) ] = {
			  version="7.0.0.1", jar="lucee-7.0.0.1.jar", lco="7.0.0.1.lco"
		};

		return flat;
	}

	// the flat source (the S3 component), answers from the flat files
	private struct function _newFlatSource( world, flat ) {
		var world = arguments.world;
		var flat  = arguments.flat;

		return {
			getVersions = function( boolean flush=false ) {
				world.flatReads++;

				if ( world.flatFails ) {
					throw( type="test", message="the flat files can't be read" );
				}

				return flat;
			}
		};
	}

	private any function _newMaven( world, struct args={} ) {
		var settings = {
			  releaseRepos  = [ releases ]
			, snapshotRepos = [ snapshots ]
			, mixedRepos    = [ mixed ]
			, retryDelay    = 0
			, httpClient    = _newClient( arguments.world )
		};

		StructAppend( settings, arguments.args, true );

		return new services.MavenCoreSource( argumentCollection=settings );
	}

	// the versions with all that is needed, args: maven, flat, flatFallback, flatUrl, versionFilter, cacheSeconds
	private any function _newVersions( world, struct args={} ) {
		var settings = {
			  flatSource    = ""
			, mavenSource   = StructKeyExists( arguments.args, "maven" ) ? arguments.args.maven : _newMaven( arguments.world )
			, flatUrl       = StructKeyExists( arguments.args, "flatUrl" ) ? arguments.args.flatUrl : cdnUrl
			, flatFallback  = arguments.args.flatFallback  ?: true
			, versionFilter = arguments.args.versionFilter ?: "major"
			, cacheSeconds  = arguments.args.cacheSeconds  ?: 300
		};

		if ( arguments.args.flatBroken ?: false ) {
			settings.flatSource = { getVersions=function() { throw( type="test", message="the flat files can't be read" ); } };
		} else {
			settings.flatSource = _newFlatSource( arguments.world, arguments.args.flat ?: _flatFiles() );
		}

		return new services.CoreVersions( argumentCollection=settings );
	}

	private any function _newProvider( versions ) {
		application.bundleDownloadService = "";
		application.coreS3Root            = "s3:///example-bucket/";
		application.coreCdnUrl            = cdnUrl;
		application.jiraChangelogService  = { getChangeLog=function() { return {}; } };
		application.coreVersions          = arguments.versions;

		return new updateprovider.UpdateProvider();
	}

	private array function _versionList( versions ) {
		var list = [];

		for ( var key in arguments.versions ) {
			ArrayAppend( list, arguments.versions[ key ].version );
		}

		return list;
	}

	// each redirect adds a Location header to the response of the test, every url redirected to must be one of them
	private array function _locations( response ) {
		return arguments.response.getHeaders( "Location" ).toArray();
	}

	private numeric function _heads( world, fileUrl ) {
		var count = 0;

		for ( var requested in arguments.world.heads ) {
			if ( requested == arguments.fileUrl ) {
				count++;
			}
		}

		return count;
	}

	// the http client of the sources, answers from the world
	private struct function _newClient( world ) {
		var world = arguments.world;

		return {
			get = function( required string url, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );

				if ( StructKeyExists( world.status, arguments.url ) ) {
					return { status=world.status[ arguments.url ], error="forced", content="" };
				}
				if ( StructKeyExists( world.pages, arguments.url ) ) {
					return { status=200, error="", content=world.pages[ arguments.url ] };
				}
				return { status=404, error="not found", content="" };
			},
			// the files are all there, unless the world says they are not (a repository that redirects does what a head says)
			head = function( required string url, required numeric timeout ) {
				ArrayAppend( world.requests, arguments.url );
				ArrayAppend( world.heads, arguments.url );

				if ( StructKeyExists( world.status, arguments.url ) ) {
					return { status=world.status[ arguments.url ], error="forced" };
				}
				if ( StructKeyExists( world.missing, arguments.url ) ) {
					return { status=404, error="not found" };
				}
				// the releases repository has the jars and nothing else
				if ( Left( arguments.url, Len( releases ) ) == releases && !ReFind( "\.jar$", arguments.url ) ) {
					return { status=404, error="not found" };
				}
				// the snapshots repository has the snapshots
				if ( Left( arguments.url, Len( snapshots ) ) == snapshots && !FindNoCase( "SNAPSHOT", arguments.url ) ) {
					return { status=404, error="not found" };
				}
				return { status=302, error="" };
			},
			download = function( required string url, required string file, required numeric timeout ) {
				throw( type="test", message="nothing is downloaded: #arguments.url#" );
			}
		};
	}

}
