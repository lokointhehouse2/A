/**
 * Session-bound CSRF tokens. Verified centrally by the front controller for every POST.
 * Forms send "_csrf"; AJAX sends the "X-CSRF-Token" header.
 */
component {

    public CSRFService function init( required any strings ) {
        variables.strings = arguments.strings;
        return this;
    }

    public string function token() {
        if ( !structKeyExists( session, "csrfToken" ) || !len( session.csrfToken ) ) {
            session.csrfToken = variables.strings.randomToken( 32 );
        }
        return session.csrfToken;
    }

    public boolean function verify( string candidate = "" ) {
        if ( !len( arguments.candidate ) || !structKeyExists( session, "csrfToken" ) ) return false;
        var md = createObject( "java", "java.security.MessageDigest" );
        return md.isEqual( charsetDecode( session.csrfToken, "utf-8" ), charsetDecode( arguments.candidate, "utf-8" ) );
    }

    public string function field() {
        return '<input type="hidden" name="_csrf" value="' & encodeForHTMLAttribute( token() ) & '">';
    }

}
