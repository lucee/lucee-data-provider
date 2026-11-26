component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};

		variables.work = GetTempDirectory() & "maven-dep-pom-tests-" & CreateUniqueId() & "/";
		DirectoryCreate( variables.work, true );

		variables.slim = variables.work & "slim.pom";
		variables.full = variables.work & "full.pom";
		FileWrite( variables.slim, '<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.lucee</groupId>
  <artifactId>lucee</artifactId>
  <version>7.1.2.195</version>
  <packaging>pom</packaging>
</project>
' );
		FileWrite( variables.full, '<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.lucee</groupId>
  <artifactId>lucee</artifactId>
  <version>7.1.2.195</version>
  <dependencies>
    <dependency>
      <groupId>org.lucee</groupId>
      <artifactId>commons-io</artifactId>
      <version>2.16.1</version>
    </dependency>
  </dependencies>
</project>
' );
	}

	function afterAll() {
		if ( StructKeyExists( variables, "work" ) && DirectoryExists( variables.work ) ) {
			DirectoryDelete( variables.work, true );
		}
	}

	function run( testResults, testBox ) {

		describe( "MavenRepo picks a POM that lists dependencies", function() {

			it( title="skips a slim Central POM and uses the loader POM with <dependencies>", body=function() {
				var repo = new services.legacy.MavenRepo();
				expect( repo.pomHasDependencies( variables.slim ) ).toBeFalse();
				expect( repo.pomHasDependencies( variables.full ) ).toBeTrue();
				expect( repo.resolveDependencyPom( "7.1.2.195", {}, [ variables.slim, variables.full ] ) ).toBe( variables.full );
			});

			it( title="throws a clear error when no candidate POM has <dependencies>", body=function() {
				var repo = new services.legacy.MavenRepo();
				var err = "";
				try {
					repo.resolveDependencyPom( "5.4.7.3", {}, [ variables.slim ] );
				}
				catch ( any e ) {
					err = e.message;
				}
				expect( err ).toInclude( "5.4.7.3" );
				expect( err ).toInclude( "<dependencies>" );
			});

			it( title="readDependenciesFromPOM throws a clear error for a slim POM", body=function() {
				var repo = new services.legacy.MavenRepo();
				var err = "";
				try {
					repo.readDependenciesFromPOM( variables.slim );
				}
				catch ( any e ) {
					err = e.message;
				}
				expect( err ).toInclude( "<dependencies>" );
			});

			it( title="getOSGiDependencies resolves the POM through resolveDependencyPom", body=function() {
				var src = FileRead( ExpandPath( variables.dir & "../apps/updateserver-maven/services/legacy/MavenRepo.cfc" ) );
				expect( src ).toInclude( "resolveDependencyPom(" );
				expect( src ).toInclude( "maven.lucee-services.com" );
			});

		});
	}

}
