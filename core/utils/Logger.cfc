/**
 * Concise application log (Lucee log file "futurepath").
 * Never pass passwords, hashes, API keys or session tokens to this logger.
 */
component {

    public void function info( required string message ) {
        write( "information", arguments.message );
    }

    public void function warn( required string message ) {
        write( "warning", arguments.message );
    }

    public void function error( required string message, any exception ) {
        var text = arguments.message;
        if ( !isNull( arguments.exception ) && isStruct( arguments.exception ) ) {
            text &= " | " & ( arguments.exception.type ?: "" ) & ": " & ( arguments.exception.message ?: "" );
            if ( len( arguments.exception.detail ?: "" ) ) text &= " | " & left( arguments.exception.detail, 500 );
            if ( isArray( arguments.exception.tagContext ?: "" ) && arrayLen( arguments.exception.tagContext ) ) {
                var ctx = arguments.exception.tagContext[ 1 ];
                text &= " @ " & ( ctx.template ?: "" ) & ":" & ( ctx.line ?: "" );
            }
        }
        write( "error", text );
    }

    private void function write( required string type, required string text ) {
        try {
            cflog( file = "futurepath", type = arguments.type, text = left( arguments.text, 2000 ) );
        } catch ( any e ) {
            // logging must never break a request
        }
    }

}
