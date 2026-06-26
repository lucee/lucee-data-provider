/**
 * Server startup listener.
 * Pre-warms extension metadata cache so the first request to /extension.cfm
 * doesn't have to block while Lucee downloads and inspects each .lex file.
 * Each extension is fetched in its own thread so startup is not delayed.
 */
component {

	remote function onServerStart( boolean reload = false ) {
		systemOutput("on server start",1,1);
		thread action="run" name="ext-metadata-prefetch" {
			try {
				for ( local.groupId in ["org.lucee", "io.forgebox"] ) {
					local.artifacts = LuceeExtension( local.groupId );

					for ( local.artifactId in local.artifacts ) {
						local.aid = local.artifactId;

						thread action="run"
							name  = "ext-prefetch-#local.groupId#-#local.aid#"
							gid   = local.groupId
							aid   = local.aid {

							try {
								local.versions = LuceeExtension( attributes.gid, attributes.aid );
								for ( local.ver in local.versions ) {
									try {
										LuceeExtension( attributes.gid, attributes.aid, local.ver, true );
									} catch ( any verErr ) {
										systemOutput( "ext prefetch fail version #local.ver#: #verErr.message#", true );
									}
								}
								if ( !arrayIsEmpty( local.versions ) ) {
									systemOutput( "ext prefetch ok (#arrayLen(local.versions)# versions): #attributes.gid#:#attributes.aid#", true );
								}
							} catch ( any e ) {
								systemOutput( "ext prefetch fail: #attributes.gid#:#attributes.aid# — #e.message#", true );
							}
						}
					}
				}

			} catch ( any e ) {
				systemOutput( "ext prefetch init failed: #e.message#", true );
			}
		}
	}

}
