component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function beforeAll (){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());
		application action="update" mappings={
			"/update" : expandPath( dir & "../apps/updateserver/" )
		};
	}

	function run( testResults , testBox ) {
		describe( "check all maven mapping are valid", function() {
			xit(title="check each maven mapping resolves", body=function(){
				var mappings = fileRead("/update/services/legacy/mavenMappings.json");
				expect( isJson( mappings) ).toBeTrue();
				mappings = deserializeJSON( mappings );
				var meta = "";
				var missing = [];
				systemOutput( "", true );
				var mavenMatcher = new update.services.legacy.MavenMatcher();
				for (var mapping in mappings ){
					// systemOutput( "checking #mapping.toJson()#", true );
					try {
						meta = mavenMatcher.getMatch( mapping, "latest" );
						systemOutput( mapping & ": " & meta.toJson(), true );
					} catch( e ) {
						arrayAppend(missing, " #mapping# threw #e.message##chr(10)#, mapping: #mappings[mapping].toJson()# ");
					}
				}
				if ( len( missing ) ){
					systemOutput( "", true );
					systemOutput( "----------- the following maven mappings are invalid ---------------", true );
				}
				for ( err in missing ) {
					systemOutput( chr( 9 ) & err, true );
				}
				expect (len( missing ) ).toBe( 0 );
			});

		});
	}

}
