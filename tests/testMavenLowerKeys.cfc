component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );

		application action="update" mappings={
			"/lowerkeysservices" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
		variables.src = FileRead( ExpandPath( dir & "../apps/updateserver-maven/rest/UpdateProvider.cfc" ) );
	}

	function run( testResults, testBox ) {

		describe( "Maven UpdateProvider list?extended=true and get/{version} keys", function() {

			it( title="the JSON has lower case keys, also nested", body=function() {
				var entry = { VERSION="7.0.6.10", JAR="lucee-7.0.6.10.jar", LIGHT="lucee-light-7.0.6.10.jar", SOURCES={ POM={ SRC="x.pom" } }, LIST=[ { A=1 } ] };
				var data  = StructNew( "linked" );
				data[ "07.000.006.0010.100" ] = entry;

				var json = SerializeJSON( lowerkeysservices.LowerKeys::copy( data ) );

				expect( json ).toInclude( '"version":"7.0.6.10"' );
				expect( json ).toInclude( '"jar":"lucee-7.0.6.10.jar"' );
				expect( json ).toInclude( '"sources":{"pom":{"src":"x.pom"}}' );
				expect( json ).toInclude( '"list":[{"a":1}]' );
				expect( json ).notToInclude( '"VERSION"' );
				// the version key stays as it is
				expect( json ).toInclude( '"07.000.006.0010.100"' );
			});

			it( title="CFML readers such as the ForgeBox publisher read the lower case keys", body=function() {
				var data = DeserializeJSON( SerializeJSON( lowerkeysservices.LowerKeys::copy( { "1"={ VERSION="7.0.6.10", JAR="a.jar", LIGHT="b.jar" } } ) ) );
				var v    = data[ "1" ];

				// as task.cfc of forgebox-cfengine-publisher reads it
				expect( v.version ).toBe( "7.0.6.10" );
				expect( v.jar ?: "" ).toBe( "a.jar" );
				expect( v.light ?: "" ).toBe( "b.jar" );
			});

			it( title="the original is not changed", body=function() {
				var entry = { VERSION="1" };
				lowerkeysservices.LowerKeys::copy( entry );
				expect( SerializeJSON( entry ) ).toInclude( '"VERSION"' );
			});

			it( title="list?extended=true and get/{version} use it", body=function() {
				expect( variables.src ).toInclude( "if ( extended ) return services.LowerKeys::copy( versions );" );
				expect( variables.src ).toInclude( "return services.LowerKeys::copy( mr.get(arguments.version,arguments.extended) );" );
			});

		});
	}

}
