/**
 * Consistent JSON envelope for every API response.
 *   success: { success:true, data:{}, message:"", meta:{} }
 *   error:   { success:false, data:null, message:"", error:{ code:"", fields:{} } }
 */
component {

    public struct function ok( any data = {}, string message = "", struct meta = {} ) {
        var out = { "success": true, "data": arguments.data, "message": arguments.message };
        if ( !structIsEmpty( arguments.meta ) ) out[ "meta" ] = arguments.meta;
        return out;
    }

    /** code: typed machine-readable error (validation_failed, not_found, rate_limited, ...). */
    public struct function fail( string message = "Something went wrong.", struct fields = {}, string code = "bad_request" ) {
        return { "success": false, "data": javacast( "null", "" ), "message": arguments.message, "error": { "code": arguments.code, "fields": arguments.fields } };
    }

    public string function toJson( required struct payload ) {
        return serializeJSON( arguments.payload );
    }

    /** Writes the envelope and aborts the request. */
    public void function send( required struct payload, numeric status = 200 ) {
        getPageContext().getResponse().setStatus( arguments.status );
        cfheader( name = "Cache-Control", value = "no-store" );
        cfcontent( type = "application/json; charset=utf-8", reset = true );
        writeOutput( toJson( arguments.payload ) );
        abort;
    }

}
