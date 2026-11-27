/**
 * The OSGi bundle jars that were extracted from an extension .lex, kept in a Google Cloud Storage bucket as
 *   <prefix><Bundle-SymbolicName>-<Bundle-Version>.jar
 * (flat, so a jar is easy to find: provider/bundles/org.lucee.axis.extension-1.4.0.27-SNAPSHOT.jar).
 *
 * Talks to the Cloud Storage JSON API with the token of the Cloud Run service account (metadata server), the same
 * account that already mounts the bucket. No key file, no secret.
 *
 * - exists():  one metadata read per object and instance; a found object is remembered for good (a jar of a
 *              bundle version does not change), a missing one for negativeSeconds
 * - put():     an upload with ifGenerationMatch=0, an object that is already there is never overwritten (412)
 * - read():    the bytes of an object, for a bucket that is not public
 * - publicUrl(): the URL of an object when publicBaseUrl is set (a public bucket), "" otherwise
 *
 * Empty bucket: disabled, every method answers "not there" and nothing goes over the network.
 */
component accessors=true {

	property name="bucket"          type="string"  default="";
	property name="prefix"          type="string"  default="provider/bundles/";
	// e.g. https://storage.googleapis.com/<bucket>/ for a bucket with public read access; "" streams through the instance
	property name="publicBaseUrl"   type="string"  default="";
	property name="timeout"         type="numeric" default=20;
	property name="negativeSeconds" type="numeric" default=600;
	// tests: an object with send( method, url, headers, body, binary ) returning { status, body }
	property name="transport"       type="any";

	variables._known   = {};
	variables._missing = {};
	variables._token   = { value="", expires=0 };

	public function init( string bucket="", string prefix="provider/bundles/", string publicBaseUrl="", numeric timeout=20, numeric negativeSeconds=600, any transport ) {
		variables.bucket          = Trim( arguments.bucket );
		variables.prefix          = _normalizePrefix( arguments.prefix );
		variables.publicBaseUrl   = Trim( arguments.publicBaseUrl );
		if ( Len( variables.publicBaseUrl ) && Right( variables.publicBaseUrl, 1 ) != "/" ) {
			variables.publicBaseUrl &= "/";
		}
		variables.timeout         = arguments.timeout;
		variables.negativeSeconds = arguments.negativeSeconds;
		if ( !IsNull( arguments.transport ) ) {
			variables.transport = arguments.transport;
		}
		return this;
	}

	public boolean function isEnabled() {
		return Len( variables.bucket ) > 0;
	}

	/**
	 * <prefix><bundleName>-<bundleVersion>.jar, "" for a name or version that cannot be a key (only letters, digits
	 * and . _ - + are used by OSGi names and versions, anything else is not cached).
	 */
	public string function objectName( required string bundleName, required string bundleVersion ) {
		if ( !_safe( arguments.bundleName ) || !_safe( arguments.bundleVersion ) ) {
			return "";
		}
		return variables.prefix & arguments.bundleName & "-" & arguments.bundleVersion & ".jar";
	}

	public string function publicUrl( required string bundleName, required string bundleVersion ) {
		var name = objectName( arguments.bundleName, arguments.bundleVersion );
		return Len( name ) && Len( variables.publicBaseUrl ) ? variables.publicBaseUrl & name : "";
	}

	/**
	 * Whether the jar is in the bucket. Throws when the bucket cannot be asked (the caller treats that as a miss
	 * without remembering it).
	 */
	public boolean function exists( required string bundleName, required string bundleVersion ) {
		var name = objectName( arguments.bundleName, arguments.bundleVersion );
		if ( !isEnabled() || !Len( name ) ) {
			return false;
		}
		if ( StructKeyExists( variables._known, name ) ) {
			return true;
		}
		var missUntil = variables._missing[ name ] ?: 0;
		if ( missUntil > _nowMs() ) {
			return false;
		}

		var res = _request( "GET", _objectUrl( name ) & "?fields=name,size" );
		if ( res.status == 200 ) {
			_remember( name );
			return true;
		}
		if ( res.status == 404 ) {
			_rememberMissing( name );
			return false;
		}
		throw( type="bundle.cache.error", message="Cloud Storage answered #res.status# for the metadata of [#name#]" );
	}

	/**
	 * Upload a jar, never overwriting an object that is already there (ifGenerationMatch=0). Returns true when the
	 * object is in the bucket afterwards (uploaded now or already there), throws on any other answer.
	 */
	public boolean function put( required string bundleName, required string bundleVersion, required string file ) {
		var name = objectName( arguments.bundleName, arguments.bundleVersion );
		if ( !isEnabled() || !Len( name ) ) {
			return false;
		}
		if ( StructKeyExists( variables._known, name ) ) {
			return true;
		}

		var res = _request(
			  "POST"
			, "https://storage.googleapis.com/upload/storage/v1/b/" & _enc( variables.bucket ) & "/o?uploadType=media&ifGenerationMatch=0&name=" & _enc( name )
			, { "Content-Type": "application/java-archive" }
			, FileReadBinary( arguments.file )
		);
		// 412: there already is an object of that name (another instance was faster), it is the same jar
		if ( res.status == 200 || res.status == 412 ) {
			_remember( name );
			return true;
		}
		throw( type="bundle.cache.error", message="Cloud Storage answered #res.status# to the upload of [#name#]" );
	}

	/**
	 * The bytes of a jar in the bucket (a bucket without public access is streamed through the instance).
	 */
	public binary function read( required string bundleName, required string bundleVersion ) {
		var name = objectName( arguments.bundleName, arguments.bundleVersion );
		if ( !isEnabled() || !Len( name ) ) {
			throw( type="bundle.cache.error", message="no bundle cache bucket" );
		}
		var res = _request( "GET", _objectUrl( name ) & "?alt=media", {}, "", true );
		if ( res.status == 200 && IsBinary( res.body ) ) {
			return res.body;
		}
		if ( res.status == 404 ) {
			StructDelete( variables._known, name );
			_rememberMissing( name );
		}
		throw( type="bundle.cache.error", message="Cloud Storage answered #res.status# for [#name#]" );
	}

// PRIVATE

	private string function _objectUrl( required string name ) {
		return "https://storage.googleapis.com/storage/v1/b/" & _enc( variables.bucket ) & "/o/" & _enc( arguments.name );
	}

	private struct function _request( required string method, required string url, struct headers={}, any body="", boolean binary=false ) {
		var h = StructCopy( arguments.headers );
		h[ "Authorization" ] = "Bearer " & _accessToken();
		return _send( arguments.method, arguments.url, h, arguments.body, arguments.binary );
	}

	private struct function _send( required string method, required string url, struct headers={}, any body="", boolean binary=false, numeric timeout=variables.timeout ) {
		if ( !IsNull( variables.transport ) ) {
			return variables.transport.send( arguments.method, arguments.url, arguments.headers, arguments.body, arguments.binary );
		}
		var res = {};
		http method=arguments.method url=arguments.url timeout=arguments.timeout throwonerror=false getasbinary=( arguments.binary ? "yes" : "auto" ) result="res" {
			loop collection=arguments.headers key="local.k" value="local.v" {
				httpparam type="header" name=k value=v;
			}
			if ( !IsSimpleValue( arguments.body ) || Len( arguments.body ) ) {
				httpparam type="body" value=arguments.body;
			}
		}
		return { status=Val( res.status_code ?: 0 ), body=res.filecontent ?: "" };
	}

	// the token of the service account of the Cloud Run service, kept until a minute before it expires
	private string function _accessToken() {
		if ( Len( variables._token.value ) && variables._token.expires > _nowMs() ) {
			return variables._token.value;
		}
		// no metadata server (a local run): not asked again for a minute
		if ( ( variables._token.failedUntil ?: 0 ) > _nowMs() ) {
			throw( type="bundle.cache.error", message="no access token from the metadata server" );
		}
		lock name="lucee-bundle-cache-token" type="exclusive" timeout=10 {
			if ( Len( variables._token.value ) && variables._token.expires > _nowMs() ) {
				return variables._token.value;
			}
			var res = { status=0, body="" };
			try {
				res = _send(
					  "GET"
					, "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token"
					, { "Metadata-Flavor": "Google" }
					, ""
					, false
					, 5
				);
			} catch ( any e ) {}
			if ( res.status != 200 || !IsJson( res.body ) ) {
				variables._token = { value="", expires=0, failedUntil=_nowMs() + 60000 };
				throw( type="bundle.cache.error", message="no access token from the metadata server (#res.status#)" );
			}
			var t = DeserializeJson( res.body );
			variables._token = {
				  value   = t.access_token ?: ""
				, expires = _nowMs() + ( Max( Val( t.expires_in ?: 0 ) - 60, 0 ) * 1000 )
			};
			return variables._token.value;
		}
	}

	private void function _remember( required string name ) {
		if ( StructCount( variables._known ) >= 20000 ) {
			variables._known = {};
		}
		variables._known[ arguments.name ] = true;
		StructDelete( variables._missing, arguments.name );
	}

	private void function _rememberMissing( required string name ) {
		if ( StructCount( variables._missing ) >= 20000 ) {
			variables._missing = {};
		}
		variables._missing[ arguments.name ] = _nowMs() + ( variables.negativeSeconds * 1000 );
	}

	private boolean function _safe( required string s ) {
		return Len( arguments.s ) && Len( arguments.s ) <= 200 && ReFind( "^[A-Za-z0-9._+-]+$", arguments.s ) && !Find( "..", arguments.s );
	}

	private string function _normalizePrefix( required string prefix ) {
		var p = ReReplace( Trim( arguments.prefix ), "^/+", "" );
		if ( Len( p ) && Right( p, 1 ) != "/" ) {
			p &= "/";
		}
		return p;
	}

	private string function _enc( required string s ) {
		return Replace( CreateObject( "java", "java.net.URLEncoder" ).encode( arguments.s, "UTF-8" ), "+", "%20", "all" );
	}

	private numeric function _nowMs() {
		return GetTickCount();
	}

}
