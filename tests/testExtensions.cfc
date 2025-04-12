component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" {

	function run( testResults , testBox ) {
		describe( "validate extension info json", function() {

			it(title="latest", body=function(){
				var extInfoPath = expandPath( dir & "../apps/download/extensionMeta.json" );
				expect( fileExists( extInfoPath ) ).toBeTrue();
				expect( isJson( fileRead( extInfoPath ) ) ).toBeTrue();
				var json = deserializeJSON( fileRead( extInfoPath ) );
				expect( isStruct( json ) ).toBeTrue();
			});

		});
	}
}
