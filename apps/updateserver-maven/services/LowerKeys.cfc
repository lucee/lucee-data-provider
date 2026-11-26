/**
 * Copies of structs with lower case keys (recursive, also in arrays), so the JSON of an answer has the same
 * keys as the legacy update provider. serializeJSON keeps the case of keys set with brackets.
 */
component {

	public static any function copy( any data ) {
		if ( IsStruct( arguments.data ) ) {
			var rtn = StructNew( "linked" );
			loop collection=arguments.data key="local.k" value="local.v" {
				rtn[ LCase( k ) ] = IsNull( v ) ? "" : copy( v );
			}
			return rtn;
		}
		if ( IsArray( arguments.data ) ) {
			var arr = [];
			loop array=arguments.data item="local.item" {
				ArrayAppend( arr, IsNull( item ) ? "" : copy( item ) );
			}
			return arr;
		}
		return arguments.data;
	}

}
