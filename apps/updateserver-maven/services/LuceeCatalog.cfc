/**
 * Cached access to Lucee 8's LuceeVersionsList / LuceeVersionsDetail /
 * LuceeExtension, using the same keys, value shapes, stale-while-revalidate
 * windows and never-cache-empty rules as apps/download8 Util.cfc.
 *
 * When the built-ins are not available (tests on an older Lucee), the
 * extension artifact list can still be filled from the group-level
 * maven-metadata.xml of the mixed Lucee repository (org.lucee and io.forgebox).
 */
component {

	property name="cache"           type="any";
	property name="groups"          type="array";
	property name="mixedRepo"       type="string";
	property name="timeout"         type="numeric";
	property name="versionsListTtl" type="numeric"; // minutes, download8 uses 5
	property name="extensionTtl"    type="numeric"; // minutes, download8 uses 10

	function init(
		  any     cache
		, array   groups          = [ "org.lucee", "io.forgebox" ]
		, string  mixedRepo       = "https://maven.lucee-services.com/"
		, numeric timeout         = 20
		, numeric versionsListTtl = 5
		, numeric extensionTtl    = 10
		, any     listVersions
		, any     versionDetail
		, any     listExtensions
		, any     listExtensionVersions
		, any     extensionDetail
		, any     httpClient
	) {
		variables.cache           = arguments.cache ?: new services.SharedDownloadCache();
		variables.groups          = arguments.groups;
		variables.mixedRepo       = Right( arguments.mixedRepo, 1 ) == "/" ? arguments.mixedRepo : arguments.mixedRepo & "/";
		variables.timeout         = arguments.timeout;
		variables.versionsListTtl = arguments.versionsListTtl;
		variables.extensionTtl    = arguments.extensionTtl;
		variables.listVersions    = arguments.listVersions    ?: "";
		variables.versionDetail   = arguments.versionDetail   ?: "";
		variables.listExtensions  = arguments.listExtensions  ?: "";
		variables.listExtensionVersions = arguments.listExtensionVersions ?: "";
		variables.extensionDetail = arguments.extensionDetail ?: "";
		variables.httpClient      = arguments.httpClient      ?: "";

		return this;
	}

	// ── Core versions (LuceeVersionsList / LuceeVersionsDetail) ──────────

	public array function getVersionList( boolean flush=false ) {
		var key    = "luceeVersionsList";
		var cached = arguments.flush ? {} : variables.cache.dlCacheGet( key );
		var data   = cached.data ?: [];
		var age    = StructKeyExists( cached, "cachedAt" ) ? DateDiff( "n", cached.cachedAt, Now() ) : 999;

		if ( !ArrayIsEmpty( data ) ) {
			if ( age >= variables.versionsListTtl ) {
				thread action="run" name="refresh-versions-list-#GetTickCount()#" {
					_putVersionList();
				}
			}
			return data;
		}

		return _putVersionList();
	}

	public struct function getVersionDetail( required string version ) {
		var key    = "luceeVerDetail_" & arguments.version;
		var cached = variables.cache.dlCacheGet( key );
		if ( !StructIsEmpty( cached ) && StructKeyExists( cached, "data" )
			&& ( !StructKeyExists( cached, "expiresAt" ) || Now().getTime() < cached.expiresAt )
		) {
			return cached.data;
		}

		var t = GetTickCount();
		try {
			var detail = _callVersionDetail( arguments.version );
			SystemOutput( "reading data from function LuceeVersionsDetail(#arguments.version#) took #GetTickCount()-t#ms", true );
			if ( StructIsEmpty( detail ) ) {
				return {};
			}
			var entry = { data=detail };
			var exp   = _snapshotUrlExpiry( detail );
			if ( !IsNull( exp ) ) {
				entry.expiresAt = exp;
			}
			variables.cache.dlCachePut( key, entry );
			return detail;
		} catch ( any e ) {
			SystemOutput( "LuceeVersionsDetail(#arguments.version#) failed: #e.message#", true );
			return {};
		}
	}

	// ── Extensions (LuceeExtension, or group-level maven-metadata.xml) ───

	public array function getExtensionArtifacts( required string groupId, boolean flush=false ) {
		var key    = "extArtifacts_" & arguments.groupId;
		var cached = arguments.flush ? {} : variables.cache.dlCacheGet( key );
		var data   = cached.data ?: [];
		var age    = StructKeyExists( cached, "cachedAt" ) ? DateDiff( "n", cached.cachedAt, Now() ) : 999;

		if ( !ArrayIsEmpty( data ) ) {
			if ( age >= variables.extensionTtl ) {
				thread action="run" name="refresh-extartifacts-#arguments.groupId#-#GetTickCount()#" gid=arguments.groupId ckey=key {
					_putExtensionArtifacts( attributes.gid, attributes.ckey );
				}
			}
			return data;
		}

		return _putExtensionArtifacts( arguments.groupId, key );
	}

	public array function getExtensionVersions( required string groupId, required string artifactId, boolean flush=false ) {
		var key    = "extver_" & arguments.groupId & "_" & arguments.artifactId;
		var cached = arguments.flush ? {} : variables.cache.dlCacheGet( key );
		var data   = cached.data ?: [];
		var age    = StructKeyExists( cached, "cachedAt" ) ? DateDiff( "n", cached.cachedAt, Now() ) : 999;

		if ( !ArrayIsEmpty( data ) ) {
			if ( age >= variables.extensionTtl ) {
				thread action="run" name="refresh-extver-#arguments.groupId#-#arguments.artifactId#-#GetTickCount()#"
					gid=arguments.groupId aid=arguments.artifactId ckey=key {
					_putExtensionVersions( attributes.gid, attributes.aid, attributes.ckey );
				}
			}
			return data;
		}

		return _putExtensionVersions( arguments.groupId, arguments.artifactId, key );
	}

	public struct function getExtensionDetail(
		  required string  groupId
		, required string  artifactId
		, required string  version
		,          boolean download = false
	) {
		var key    = "extdata_" & arguments.groupId & "_" & arguments.artifactId & "_" & arguments.version;
		var cached = variables.cache.dlCacheGet( key );
		// download8 stores the meta struct itself, not { data, cachedAt }
		if ( !StructIsEmpty( cached ) ) {
			return cached;
		}

		var t = GetTickCount();
		try {
			var meta = _callExtensionDetail( arguments.groupId, arguments.artifactId, arguments.version, arguments.download );
			SystemOutput( "reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#,#arguments.version#,#arguments.download#) took #GetTickCount()-t#ms", true );
			if ( StructIsEmpty( meta ) ) {
				return {};
			}
			variables.cache.dlCachePut( key, meta );
			return meta;
		} catch ( any e ) {
			SystemOutput( "LuceeExtension(#arguments.groupId#,#arguments.artifactId#,#arguments.version#) failed: #e.message#", true );
			return {};
		}
	}

	/**
	 * All extension artifacts of the configured groups, each as
	 * { group, artifact, latest, release }. latest/release come from the
	 * group-level maven-metadata.xml when it can be read (those fields are
	 * not on LuceeExtension(groupId), which only returns artifact ids).
	 */
	public array function listCatalog( boolean flush=false ) {
		var catalog = [];

		for ( var groupId in variables.groups ) {
			var fromXml = _readGroupMetadata( groupId );
			var names   = ArrayLen( fromXml ) ? [] : getExtensionArtifacts( groupId, arguments.flush );

			if ( ArrayLen( fromXml ) ) {
				// still publish the artifact id list under the shared extArtifacts_ key
				var ids = [];
				for ( var row in fromXml ) {
					ArrayAppend( ids, row.artifact );
					ArrayAppend( catalog, row );
				}
				_cacheArtifactIds( groupId, ids );
			} else {
				for ( var name in names ) {
					ArrayAppend( catalog, { group=groupId, artifact=name, latest="", release="" } );
				}
			}
		}

		return catalog;
	}

	public array function getGroups() {
		return variables.groups;
	}

	// ── Internals ────────────────────────────────────────────────────────

	private array function _putVersionList() {
		var t = GetTickCount();
		try {
			var list = _callVersionList();
			SystemOutput( "reading data from function LuceeVersionsList() took #GetTickCount()-t#ms", true );
			if ( !ArrayIsEmpty( list ) ) {
				variables.cache.dlCachePut( "luceeVersionsList", { data=list, cachedAt=Now() } );
			}
			return list;
		} catch ( any e ) {
			SystemOutput( "LuceeVersionsList() failed: #e.message#", true );
			return [];
		}
	}

	private array function _putExtensionArtifacts( required string groupId, required string key ) {
		var t = GetTickCount();
		try {
			var list = _callExtensionArtifacts( arguments.groupId );
			SystemOutput( "reading data from function LuceeExtension(#arguments.groupId#) took #GetTickCount()-t#ms", true );
			if ( ArrayIsEmpty( list ) ) {
				// never cache an empty result: 0 artifacts means the scan failed, not that the group is empty
				list = _artifactIdsFromGroupMetadata( arguments.groupId );
			}
			if ( !ArrayIsEmpty( list ) ) {
				variables.cache.dlCachePut( arguments.key, { data=list, cachedAt=Now() } );
			}
			return list;
		} catch ( any e ) {
			SystemOutput( "LuceeExtension(#arguments.groupId#) failed: #e.message#", true );
			var fallback = _artifactIdsFromGroupMetadata( arguments.groupId );
			if ( !ArrayIsEmpty( fallback ) ) {
				variables.cache.dlCachePut( arguments.key, { data=fallback, cachedAt=Now() } );
			}
			return fallback;
		}
	}

	private array function _putExtensionVersions( required string groupId, required string artifactId, required string key ) {
		var t = GetTickCount();
		try {
			var list = _callExtensionVersions( arguments.groupId, arguments.artifactId );
			SystemOutput( "reading data from function LuceeExtension(#arguments.groupId#,#arguments.artifactId#) took #GetTickCount()-t#ms", true );
			var na = [];
			for ( var v in list ) {
				if ( !FindNoCase( "-alpha", LCase( v ) ) ) {
					ArrayAppend( na, v );
				}
			}
			if ( !ArrayIsEmpty( na ) ) {
				list = na;
			}
			ArraySort( list, function( a, b ) {
				return variables.cache.versionCompare( b, a );
			} );
			if ( !ArrayIsEmpty( list ) ) {
				variables.cache.dlCachePut( arguments.key, { data=list, cachedAt=Now() } );
			}
			return list;
		} catch ( any e ) {
			SystemOutput( "LuceeExtension(#arguments.groupId#,#arguments.artifactId#) failed: #e.message#", true );
			return [];
		}
	}

	private void function _cacheArtifactIds( required string groupId, required array ids ) {
		if ( ArrayIsEmpty( arguments.ids ) ) {
			return;
		}
		variables.cache.dlCachePut( "extArtifacts_" & arguments.groupId, { data=arguments.ids, cachedAt=Now() } );
	}

	private array function _callVersionList() {
		if ( IsCustomFunction( variables.listVersions ) ) {
			return variables.listVersions();
		}
		if ( _hasBif( "LuceeVersionsList" ) ) {
			return LuceeVersionsList();
		}
		return [];
	}

	private struct function _callVersionDetail( required string version ) {
		if ( IsCustomFunction( variables.versionDetail ) ) {
			return variables.versionDetail( arguments.version );
		}
		if ( _hasBif( "LuceeVersionsDetail" ) ) {
			return LuceeVersionsDetail( arguments.version );
		}
		return {};
	}

	private array function _callExtensionArtifacts( required string groupId ) {
		if ( IsCustomFunction( variables.listExtensions ) ) {
			return variables.listExtensions( arguments.groupId );
		}
		if ( _hasBif( "LuceeExtension" ) ) {
			return LuceeExtension( arguments.groupId );
		}
		return [];
	}

	private array function _callExtensionVersions( required string groupId, required string artifactId ) {
		if ( IsCustomFunction( variables.listExtensionVersions ) ) {
			return variables.listExtensionVersions( arguments.groupId, arguments.artifactId );
		}
		if ( _hasBif( "LuceeExtension" ) ) {
			return LuceeExtension( arguments.groupId, arguments.artifactId );
		}
		return [];
	}

	private struct function _callExtensionDetail( required string groupId, required string artifactId, required string version, required boolean download ) {
		if ( IsCustomFunction( variables.extensionDetail ) ) {
			return variables.extensionDetail( arguments.groupId, arguments.artifactId, arguments.version, arguments.download );
		}
		if ( _hasBif( "LuceeExtension" ) ) {
			return LuceeExtension( arguments.groupId, arguments.artifactId, arguments.version, arguments.download );
		}
		return {};
	}

	private boolean function _hasBif( required string name ) {
		try {
			GetFunctionData( arguments.name );
			return true;
		} catch ( any e ) {
			return false;
		}
	}

	private any function _snapshotUrlExpiry( required struct detail ) {
		for ( var k in arguments.detail ) {
			if ( !IsSimpleValue( arguments.detail[ k ] ) ) {
				continue;
			}
			var m = ReFind( "-([0-9]{8})\.[0-9]{6}-[0-9]+\.", arguments.detail[ k ], 1, true );
			if ( ArrayLen( m.pos ) >= 2 && m.pos[ 2 ] > 0 ) {
				var ymd = Mid( arguments.detail[ k ], m.pos[ 2 ], m.len[ 2 ] );
				var d   = CreateDate( Val( Mid( ymd, 1, 4 ) ), Val( Mid( ymd, 5, 2 ) ), Val( Mid( ymd, 7, 2 ) ) );
				return DateAdd( "d", 89, d ).getTime();
			}
		}
	}

	private array function _artifactIdsFromGroupMetadata( required string groupId ) {
		var rows = _readGroupMetadata( arguments.groupId );
		var ids  = [];

		for ( var row in rows ) {
			ArrayAppend( ids, row.artifact );
		}

		return ids;
	}

	/**
	 * The group-level maven-metadata.xml of the mixed Lucee repository:
	 *   {repo}{group/path}/maven-metadata.xml
	 * with <artifacts><artifact><artifactId/><latest/><release/>.
	 * Only artifactIds ending in -extension are kept.
	 */
	public array function _readGroupMetadata( required string groupId ) {
		var metaUrl = variables.mixedRepo & Replace( arguments.groupId, ".", "/", "all" ) & "/maven-metadata.xml";
		var page = _get( metaUrl );

		if ( ( page.status ?: 0 ) != 200 || !Len( Trim( page.content ?: "" ) ) ) {
			if ( Len( page.error ?: "" ) ) {
				SystemOutput( "Group maven-metadata.xml [#metaUrl#] could not be read: #page.status# #page.error#", true );
			}
			return [];
		}

		try {
			return parseGroupMetadata( page.content, arguments.groupId );
		} catch ( any e ) {
			SystemOutput( "Group maven-metadata.xml [#metaUrl#] is not valid: #e.message#", true );
			return [];
		}
	}

	public array function parseGroupMetadata( required string xml, required string groupId ) {
		var doc  = XmlParse( Trim( arguments.xml ) );
		var rows = [];

		for ( var node in XmlSearch( doc, "/metadata/artifacts/artifact" ) ) {
			var artifact = _childText( node, "artifactId" );
			if ( !Len( artifact ) || !artifact.endsWith( "-extension" ) ) {
				continue;
			}
			ArrayAppend( rows, {
				  group    = arguments.groupId
				, artifact = artifact
				, latest   = _childText( node, "latest" )
				, release  = _childText( node, "release" )
			} );
		}

		return rows;
	}

	private string function _childText( required xml node, required string name ) {
		if ( !StructKeyExists( arguments.node, "xmlChildren" ) ) {
			return "";
		}
		for ( var child in arguments.node.xmlChildren ) {
			if ( child.xmlName == arguments.name ) {
				return Trim( child.xmlText );
			}
		}
		return "";
	}

	private struct function _get( required string address ) {
		if ( IsStruct( variables.httpClient ) || IsObject( variables.httpClient ) ) {
			return variables.httpClient.get( arguments.address, variables.timeout );
		}
		http url=arguments.address method="get" timeout=variables.timeout redirect=true getAsBinary="no" result="local.res" {}
		return {
			  status  = Val( ListFirst( local.res.statusCode ?: "0" ) )
			, content = ToString( local.res.fileContent ?: "" )
			, error   = local.res.errorDetail ?: ""
		};
	}

}
