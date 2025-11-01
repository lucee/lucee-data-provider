component {

	function init( required download ) {
		variables.download = arguments.download;
		return this;
	}

	/**
	 * Process raw versions from the update provider and filter them for the changelog
	 * @versions The raw versions struct from download.getVersions()
	 * @returns Struct with { major: {}, latestSnapshots: {} }
	 */
	function processVersions( required struct versions ) localmode=true {
		var major = {};
		var snapshots = {};

		// add types to each version
		loop struct=arguments.versions index="local.vs" item="local.data" {
			if ( findNoCase( "-snapshot", data.version ) ) {
				data['type'] = "snapshots";
			} else if ( findNoCase( "-rc", data.version ) ) {
				data['type'] = "rc";
			} else if ( findNoCase( "-beta", data.version ) ) {
				data['type'] = "beta";
			} else if ( findNoCase( "-alpha", data.version ) ) {
				data['type'] = "alpha";
			} else {
				data['type'] = "releases";
			}
			data['versionNoAppendix'] = data.version;

			if ( data.type != "snapshots" ) {
				major[ vs ] = data;
			} else {
				// Track all snapshots - key (vs) is already the sorted version
				// Extract major version from key: "07" from "07.000.001.0044.000"
				var majorVersion = listFirst( vs, "." );

				// Keep only the latest snapshot per major version (highest key)
				if ( !structKeyExists( snapshots, majorVersion ) || vs > snapshots[ majorVersion ].key ) {
					snapshots[ majorVersion ] = {
						key: vs,
						data: data
					};
				}
			}
		}

		// Promote the latest snapshot per major version to major
		// BUT only if there isn't already an RC/Beta/Release with the same version
		structEach( snapshots, function( majorVer, snapshot ) {
			var snapshotKey = snapshot.key;
			var snapshotData = snapshot.data;

			// Extract version prefix (first 4 parts) to check for duplicates
			// e.g., "07.000.001.0044" from "07.000.001.0044.000"
			var versionPrefix = listDeleteAt( snapshotKey, listLen( snapshotKey, "." ), "." );

			// Check if there's already an RC/Beta/Release with same version
			var hasDuplicate = false;
			loop list=".050,.075,.100" index="local.qualifier" {
				if ( structKeyExists( major, versionPrefix & qualifier ) ) {
					hasDuplicate = true;
					break;
				}
			}

			// If no duplicate, promote this snapshot to major
			if ( !hasDuplicate ) {
				major[ snapshotKey ] = snapshotData;
			}
		});

		return {
			major: major,
			latestSnapshots: snapshots
		};
	}

	/**
	 * Get sorted array of version keys for display
	 * @major The major versions struct
	 * @returns Array of version keys, sorted newest first
	 */
	function getSortedVersions( required struct major ) localmode=true {
		return structKeyArray( arguments.major ).reverse().sort( "text", "desc" );
	}

	/**
	 * Sort changelog struct keys by version, filtering to only include versions matching the major version filter
	 * @changelog The changelog struct from download.getChangelog() - keys are fix versions, values are ticket structs
	 * @majorVersionFilter The major version to filter by (e.g., "7.0")
	 * @returns Array of version keys, sorted newest first, filtered to only include matching major versions
	 */
	function getSortedChangelogVersions( required struct changelog, required string majorVersionFilter ) localmode=true {
		var versions = structKeyArray( arguments.changelog );

		// Filter to only include versions that start with the major version filter
		var filtered = [];
		loop array=versions index="local.i" item="local.ver" {
			if ( left( ver, len( arguments.majorVersionFilter ) ) eq arguments.majorVersionFilter ) {
				arrayAppend( filtered, ver );
			}
		}

		// Sort using proper version sorting (convert to sortable format first)
		// Use callback to compare using toVersionSortable format
		arraySort( filtered, function( v1, v2 ) {
			try {
				var sorted1 = toVersionSortable( arguments.v1 );
				var sorted2 = toVersionSortable( arguments.v2 );
				// Descending order (newest first)
				return compare( sorted2, sorted1 );
			} catch ( any e ) {
				// Fallback to text comparison if version parsing fails
				return compareNoCase( arguments.v2, arguments.v1 );
			}
		});

		return filtered;
	}

	/**
	 * Build the changelog data array for a specific major version
	 * @versions The processed versions struct (from processVersions)
	 * @arrVersions Array of sorted version keys (from getSortedVersions)
	 * @majorVersionFilter Major version to filter by (e.g., "7.0")
	 * @returns Array of structs with version metadata and changelog data
	 */
	function buildChangelogData( required struct versions, required array arrVersions, required string majorVersionFilter ) localmode=true {
		var arrChangeLogs = [];

		loop array=arguments.arrVersions index="local.idx" item="local._version" {
			var version = arguments.versions[ _version ].version;
			var prevVersion = "";

			// Determine previous version for changelog range
			if ( idx lt arrayLen( arguments.arrVersions ) ) {
				prevVersion = arguments.versions[ arguments.arrVersions[ idx + 1 ] ].version;

				// If current version is a stable release, check if there's an RC/Beta/Alpha with same base version
				if ( arguments.versions[ _version ].type eq "releases" ) {
					var baseVersion = listFirst( version, "-" );
					//systemOutput( "Stable release #version#: looking for RC/Beta/Alpha with base version #baseVersion#, current prevVersion=#prevVersion#", true );
					// Look through all versions to find RC/Beta/Alpha with matching base
					loop array=arguments.arrVersions index="local.checkIdx" item="local.checkKey" {
						var checkVersion = arguments.versions[ checkKey ].version;
						var checkType = arguments.versions[ checkKey ].type;
						var checkBase = listFirst( checkVersion, "-" );
						// If we find an RC/Beta/Alpha with the same base version, use it as prevVersion
						if ( ( checkType eq "rc" || checkType eq "beta" || checkType eq "alpha" )
							&& checkBase eq baseVersion ) {
							//systemOutput( "Found match: #checkVersion# (type=#checkType#, base=#checkBase#), setting as prevVersion", true );
							prevVersion = checkVersion;
							break;
						}
					}
					//systemOutput( "Final prevVersion for stable #version# is #prevVersion#", true );
				}
			} else {
				// Last version - use the oldest version from the sorted array (last item)
				var lastKey = arguments.arrVersions[ arrayLen( arguments.arrVersions ) ];
				prevVersion = arguments.versions[ lastKey ].version;
			}

			// Determine header type and title
			var versionTitle = version;
			var header = "h4";
			switch( arguments.versions[ _version ].type ) {
				case "releases":
					header = "h2";
					versionTitle &= " Stable";
					break;
			}

			// Fetch changelog only if version matches the major version filter
			var changelog = {};
			var versionReleaseDate = "";
			if ( left( version, len( arguments.majorVersionFilter ) ) eq arguments.majorVersionFilter ) {
				// For RC/Beta/Alpha, use the base version (without suffix) as upper bound to include tickets tagged without suffix
				var changelogVersion = version;
				if ( arguments.versions[ _version ].type eq "rc" || arguments.versions[ _version ].type eq "beta" || arguments.versions[ _version ].type eq "alpha" ) {
					changelogVersion = listFirst( version, "-" );
				}
				changelog = variables.download.getChangelog( prevVersion, changelogVersion, false, true );
				versionReleaseDate = variables.download.getReleaseDate( version );
			}

			if ( !isStruct( changelog ) ) {
				changelog = {};
			}

			arrayAppend( arrChangeLogs, {
				version: version,
				_version: _version,
				type: arguments.versions[ _version ].type,
				prevVersion: prevVersion,
				versionReleaseDate: versionReleaseDate,
				changelog: changelog,
				header: header,
				versionTitle: versionTitle
			});
		}

		return arrChangeLogs;
	}

	/**
	 * Remove duplicate tickets from stable releases that also appear in their RC/Beta/Alpha
	 * Handles two cases:
	 * 1. Same base version (e.g., 6.2.3.35 stable and 6.2.3.35-RC)
	 * 2. Different base version where stable's prevVersion is RC/Beta/Alpha (e.g., 6.2.2.91 stable with prevVersion 6.2.2.90-RC)
	 * @arrChangeLogs The changelog data array from buildChangelogData
	 * @returns The deduplicated changelog data array
	 */
	function deduplicateStableReleaseTickets( required array arrChangeLogs ) localmode=true {
		// Build a lookup map by version for quick access
		versionLookup = {};
		loop array=arguments.arrChangeLogs index="changelog" {
			versionLookup[ changelog.version ] = changelog;
		}

		// Process each stable release
		loop array=arguments.arrChangeLogs index="changelog" {
			if ( changelog.type eq "releases" && structCount( changelog.changelog ) > 0 ) {
				stableRelease = changelog;
				prevVersion = stableRelease.prevVersion;

				// Check if prevVersion is an RC/Beta/Alpha
				isPrevRC = ( findNoCase( "-rc", prevVersion ) || findNoCase( "-beta", prevVersion ) || findNoCase( "-alpha", prevVersion ) );

				// If prevVersion is RC/Beta/Alpha and exists in our data, deduplicate
				if ( isPrevRC && structKeyExists( versionLookup, prevVersion ) ) {
					rcRelease = versionLookup[ prevVersion ];

					if ( structCount( rcRelease.changelog ) > 0 ) {
						// Build a list of all ticket IDs in the RC changelog
						rcTicketIds = {};
						loop collection=rcRelease.changelog index="ver" item="tickets" {
							loop collection=tickets index="ticketId" item="ticketData" {
								rcTicketIds[ ticketId ] = true;
							}
						}

						// Remove those tickets from the stable changelog
						loop collection=stableRelease.changelog index="ver" item="tickets" {
							ticketsToKeep = {};
							loop collection=tickets index="ticketId" item="ticketData" {
								if ( !structKeyExists( rcTicketIds, ticketId ) ) {
									ticketsToKeep[ ticketId ] = ticketData;
								}
							}
							stableRelease.changelog[ ver ] = ticketsToKeep;
						}
					}
				}
			}
		}

		return arguments.arrChangeLogs;
	}

	/**
	 * Convert a version string to sortable format (from VersionUtils.cfc logic)
	 * @version Version string like "7.0.1.44-SNAPSHOT"
	 * @returns Sortable version string like "07.000.001.0044.000"
	 */
	private function toVersionSortable( required string version ) localmode=true {
		var arr = listToArray( arguments.version, '.' );

		if ( arr.len() != 4 || !isNumeric( arr[ 1 ] ) || !isNumeric( arr[ 2 ] ) || !isNumeric( arr[ 3 ] ) ) {
			throw "version number [" & arguments.version & "] is invalid";
		}

		var sct = {
			major: arr[ 1 ] + 0,
			minor: arr[ 2 ] + 0,
			micro: arr[ 3 ] + 0,
			qualifier_appendix: "",
			qualifier_appendix_nbr: 100
		};

		// qualifier has an appendix? (BETA,SNAPSHOT)
		var qArr = listToArray( arr[ 4 ], '-' );
		if ( qArr.len() == 1 && isNumeric( qArr[ 1 ] ) ) {
			sct.qualifier = qArr[ 1 ] + 0;
		} else if ( qArr.len() == 2 && isNumeric( qArr[ 1 ] ) ) {
			sct.qualifier = qArr[ 1 ] + 0;
			sct.qualifier_appendix = qArr[ 2 ];
			if ( sct.qualifier_appendix == "SNAPSHOT" ) {
				sct.qualifier_appendix_nbr = 0;
			} else if ( sct.qualifier_appendix == "BETA" ) {
				sct.qualifier_appendix_nbr = 50;
			} else {
				sct.qualifier_appendix_nbr = 75; // every other appendix is better than SNAPSHOT
			}
		} else {
			sct.qualifier = qArr[ 1 ] + 0;
			sct.qualifier_appendix_nbr = 75;
		}

		return repeatString( "0", 2 - len( sct.major ) ) & sct.major
			& "." & repeatString( "0", 3 - len( sct.minor ) ) & sct.minor
			& "." & repeatString( "0", 3 - len( sct.micro ) ) & sct.micro
			& "." & repeatString( "0", 4 - len( sct.qualifier ) ) & sct.qualifier
			& "." & repeatString( "0", 3 - len( sct.qualifier_appendix_nbr ) ) & sct.qualifier_appendix_nbr;
	}

}
