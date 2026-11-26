/**
 * Smaller logos for the extension listing (opt-in, LISTING_LOGO_MAX_SIZE, for example "260x100").
 *
 * The logos are base64 images, many of them far larger than the Lucee Administrator shows them (it scales them
 * down to 130x50 itself). A logo larger than the maximum is scaled to fit it and served as a PNG, when that is
 * smaller than the original. The original is kept when the image can't be read, or the image functions are not
 * there. Results are remembered by the hash of the original, so a logo is scaled once per process.
 */
component {

	public function init( string maxSize="" ) {
		variables.maxWidth  = 0;
		variables.maxHeight = 0;

		var size = LCase( Trim( arguments.maxSize ) );
		if ( ReFind( "^[0-9]+x[0-9]+$", size ) ) {
			variables.maxWidth  = Int( ListFirst( size, "x" ) );
			variables.maxHeight = Int( ListLast( size, "x" ) );
		}
		variables.memo = StructNew( "synchronized" );

		return this;
	}

	public boolean function isEnabled() {
		return variables.maxWidth > 0 && variables.maxHeight > 0;
	}

	/**
	 * The logo (base64) scaled to fit the maximum size, or the logo as it is.
	 */
	public string function shrink( string logo="" ) {
		var src = Trim( arguments.logo );
		if ( !isEnabled() || !Len( src ) || ReFindNoCase( "^https?://", src ) ) {
			return arguments.logo;
		}

		var key = Hash( src, "MD5" );
		if ( StructKeyExists( variables.memo, key ) ) {
			return variables.memo[ key ];
		}

		var result = arguments.logo;
		var tmp    = "";
		try {
			var img = ImageRead( ToBinary( src ) );
			if ( ImageGetWidth( img ) > variables.maxWidth || ImageGetHeight( img ) > variables.maxHeight ) {
				ImageScaleToFit( img, variables.maxWidth, variables.maxHeight, "highQuality" );
				tmp = GetTempDirectory() & "logo-" & CreateUUID() & ".png";
				ImageWrite( img, tmp, true );
				var scaled = ToBase64( FileReadBinary( tmp ) );
				if ( Len( scaled ) < Len( src ) ) {
					result = scaled;
				}
			}
		} catch ( any e ) {
			result = arguments.logo;
		} finally {
			if ( Len( tmp ) && FileExists( tmp ) ) {
				try { FileDelete( tmp ); } catch ( any ignore ) {}
			}
		}

		if ( StructCount( variables.memo ) < 2000 ) {
			variables.memo[ key ] = result;
		}

		return result;
	}

	/**
	 * Shrinks the logos of a listing (query with an image column) in place.
	 */
	public void function shrinkAll( required query extensions ) {
		if ( !isEnabled() || !ListFindNoCase( arguments.extensions.columnList, "image" ) ) {
			return;
		}
		for ( var i=1; i<=QueryRecordCount( arguments.extensions ); i++ ) {
			arguments.extensions.image[ i ] = shrink( arguments.extensions.image[ i ] );
		}
	}

}
