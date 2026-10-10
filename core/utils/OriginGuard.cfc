/**
 * Same-origin check for state-changing JSON requests (browser CSRF defence for the public API).
 * Requests without Origin/Referer (curl, server-to-server) are allowed; browsers always send Origin on POST.
 */
component {

    public OriginGuard function init( required string baseUrl ) {
        variables.allowed = [ lCase( arguments.baseUrl ) ];
        return this;
    }

    public boolean function isSameOrigin( required struct headers ) {
        var origin = lCase( arguments.headers[ "Origin" ] ?: "" );
        if ( !len( origin ) ) {
            var referer = lCase( arguments.headers[ "Referer" ] ?: "" );
            if ( !len( referer ) ) return true;
            var m = reFind( "^(https?://[^/]+)", referer, 1, true );
            origin = m.pos[ 1 ] ? mid( referer, m.pos[ 2 ], m.len[ 2 ] ) : "";
        }
        if ( origin == "null" ) return false;
        var host = lCase( arguments.headers[ "Host" ] ?: "" );
        if ( len( host ) && ( origin == "http://" & host || origin == "https://" & host ) ) return true;
        return arrayFind( variables.allowed, origin ) > 0;
    }

}
