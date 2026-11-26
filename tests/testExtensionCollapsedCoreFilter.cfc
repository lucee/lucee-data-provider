component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider" {

	function beforeAll() {
		variables.dir = GetDirectoryFromPath( GetCurrentTemplatePath() );
		application action="update" mappings={
			"/services" : ExpandPath( dir & "../apps/updateserver-maven/services" )
		};
	}

	function run( testResults, testBox ) {
		describe( "LDEV-6953 collapsed listing filter keeps older versions that fit", function() {

			it( title="promotes Chart 2.0.0.1 when latest 3.0.0.5 needs 7.1 and the core is 7.0", body=function() {
				var reader = new services.ExtensionMetadataReader();
				var q = _chartRow(
					  currentVersion = "3.0.0.5"
					, currentMinCore = "7.1.0.2"
					, older          = [ "2.0.0.3", "2.0.0.1" ]
					, olderNames     = [ "chart-extension-2.0.0.3.lex", "chart-extension-2.0.0.1.lex" ]
					, olderCores     = [ "6.2.5.38", "7.0.0.110" ]
				);

				var filtered = reader.filterCollapsedByCoreVersion( q, "7.0.5.41" );

				expect( filtered.recordCount ).toBe( 1 );
				expect( filtered.version[ 1 ] ).toBe( "2.0.0.3" );
				expect( filtered.filename[ 1 ] ).toBe( "chart-extension-2.0.0.3.lex" );
				expect( filtered.minCoreVersion[ 1 ] ).toBe( "6.2.5.38" );
				expect( filtered.older[ 1 ] ).toBe( [ "2.0.0.1" ] );
				expect( filtered.olderName[ 1 ] ).toBe( [ "chart-extension-2.0.0.1.lex" ] );
			});

			it( title="keeps latest 3.0.0.5 on 7.1 and leaves older 2.0.0.1 in place", body=function() {
				var reader = new services.ExtensionMetadataReader();
				var q = _chartRow(
					  currentVersion = "3.0.0.5"
					, currentMinCore = "7.1.0.2"
					, older          = [ "2.0.0.1" ]
					, olderNames     = [ "chart-extension-2.0.0.1.lex" ]
					, olderCores     = [ "7.0.0.110" ]
				);

				var filtered = reader.filterCollapsedByCoreVersion( q, "7.1.2.191" );

				expect( filtered.recordCount ).toBe( 1 );
				expect( filtered.version[ 1 ] ).toBe( "3.0.0.5" );
				expect( filtered.older[ 1 ] ).toBe( [ "2.0.0.1" ] );
			});

			it( title="drops the row when no version fits the core", body=function() {
				var reader = new services.ExtensionMetadataReader();
				var q = _chartRow(
					  currentVersion = "3.0.0.5"
					, currentMinCore = "7.1.0.2"
					, older          = [ "3.0.0.4-RC" ]
					, olderNames     = [ "chart-extension-3.0.0.4-RC.lex" ]
					, olderCores     = [ "7.1.0.2" ]
				);

				var filtered = reader.filterCollapsedByCoreVersion( q, "6.2.1.5" );

				expect( filtered.recordCount ).toBe( 0 );
			});

		});
	}

	private query function _chartRow( currentVersion, currentMinCore, older, olderNames, olderCores ) {
		var q = QueryNew( "id,name,version,filename,minCoreVersion,created,versionSortable,older,olderName,olderDate,coreVersion" );
		QueryAddRow( q, 1 );
		q.id             [ 1 ] = "D46B46A9-A0E3-44E1-D972A04AC3A8DC10";
		q.name           [ 1 ] = "Chart Extension";
		q.version        [ 1 ] = arguments.currentVersion;
		q.filename       [ 1 ] = "chart-extension-" & arguments.currentVersion & ".lex";
		q.minCoreVersion [ 1 ] = arguments.currentMinCore;
		q.created        [ 1 ] = "2026-11-10";
		q.versionSortable[ 1 ] = arguments.currentVersion;
		q.older          [ 1 ] = arguments.older;
		q.olderName      [ 1 ] = arguments.olderNames;
		q.olderDate      [ 1 ] = [ "", "" ];
		q.coreVersion    [ 1 ] = arguments.olderCores;
		return q;
	}

}
