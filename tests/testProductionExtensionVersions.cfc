component extends="org.lucee.cfml.test.LuceeTestCase" labels="data-provider-integration" skip=true {

	function beforeAll(){
		variables.dir = getDirectoryFromPath(getCurrentTemplatePath());

		// Fetch production extension list
		cfhttp( url="https://extension.lucee.org/rest/extension/provider/info/?withLogo=false", result="local.prod" );

		if ( prod.status_code != 200 ) {
			throw "Failed to fetch production data: " & prod.status_code;
		}

		var response = deserializeJson( prod.fileContent );

		// Handle response - struct with EXTENSIONS key containing query data
		if ( structKeyExists( response, "EXTENSIONS" ) ) {
			var extensions = response.EXTENSIONS;
			var cols = extensions.COLUMNS;
			var data = extensions.DATA;

			// Convert to array of structs
			variables.prodData = [];
			for ( var rowData in data ) {
				var row = {};
				for ( var i = 1; i <= arrayLen( cols ); i++ ) {
					row[ cols[ i ] ] = rowData[ i ];
				}
				arrayAppend( variables.prodData, row );
			}
		} else {
			systemOutput( response, true);
			throw "Unexpected production response structure";
		}

		systemOutput( "Fetched #arrayLen( variables.prodData )# extensions from production", true );

		// Get unique extension IDs and collect all versions
		variables.extensionIDs = {};
		for ( var ext in variables.prodData ) {
			if ( !structKeyExists( variables.extensionIDs, ext.id ) ) {
				variables.extensionIDs[ ext.id ] = {
					name: ext.name ?: "",
					versions: []
				};
			}

			// Add current version
			arrayAppend( variables.extensionIDs[ ext.id ].versions, ext.version );

			// Add older versions if they exist
			if ( structKeyExists( ext, "older" ) && isArray( ext.older ) ) {
				for ( var olderVer in ext.older ) {
					arrayAppend( variables.extensionIDs[ ext.id ].versions, olderVer );
				}
			}
		}

		systemOutput( "Found #structCount( variables.extensionIDs )# unique extension IDs", true );

		// Test core version that triggers the bug
		variables.testCoreVersion = "6.2.4.24";
	}

	function run( testResults , testBox ) {

		describe( "validate production extension API returns correct versions", function() {

			it (title="test production has extensions", body=function(){
				expect( structCount( variables.extensionIDs ) ).toBeGT( 0 );
			});

			it (title="test each extension returns correct version for coreVersion 6.2.4.24", body=function(){
				var failed = [];
				var tested = 0;
				var skipped = 0;

				for ( var extID in variables.extensionIDs ) {
					var extInfo = variables.extensionIDs[ extID ];

					// Call production API for this extension (redirect=false to get headers)
					cfhttp(
						url="https://extension.lucee.org/rest/extension/provider/full/#extID#?coreVersion=#variables.testCoreVersion#",
						result="local.response",
						redirect=false,
						timeout=10
					);

					if ( response.status_code == 404 ) {
						skipped++;
						continue;
					}

					if ( response.status_code != 302 ) {
						arrayAppend( failed, "#extInfo.name# (#extID#): Expected 302 redirect, got #response.status_code#" );
						continue;
					}

					// Get Location header
					var location = "";
					if ( structKeyExists( response.responseHeader, "Location" ) ) {
						location = response.responseHeader.Location;
					}

					if ( !len( location ) ) {
						arrayAppend( failed, "#extInfo.name# (#extID#): No Location header in redirect" );
						continue;
					}

					// Extract filename from location (last part of URL)
					var filename = listLast( location, "/" );

					// Extract version from filename using regex
					var versionMatch = reMatch( "(\d+\.)(\d+\.){1,2}\d+[^.]*", filename );
					if ( arrayLen( versionMatch ) > 0 ) {
						var redirectVersion = versionMatch[ 1 ];

						// Extract major version number
						var redirectMajor = val( listFirst( redirectVersion, "." ) );

						// Check if redirect has old major version (< 10) and newer versions (>= 10) exist
						if ( redirectMajor < 10 ) {
							var hasNewer = false;
							for ( var v in extInfo.versions ) {
								var vMajor = val( listFirst( v, "." ) );
								if ( vMajor >= 10 ) {
									hasNewer = true;
									break;
								}
							}

							if ( hasNewer ) {
								arrayAppend( failed, "#extInfo.name# (#extID#): redirects to #redirectVersion# but has versions >= 10.x available" );
							}
						}
					}

					tested++;
				}

				systemOutput( "Tested: #tested#, Skipped: #skipped#, Failed: #arrayLen( failed )#", true );

				if ( arrayLen( failed ) > 0 ) {
					systemOutput( "Failures:", true );
					for ( var f in failed ) {
						systemOutput( "  - #f#", true );
					}
				}

				expect( arrayLen( failed ) ).toBe( 0, "All extensions should return correct version" );
			});

		});
	}

}
