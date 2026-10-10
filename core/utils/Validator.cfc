/**
 * Small input-validation helpers. Each throws type "Validation" (rendered as HTTP 422 with field errors).
 */
component {

    public void function fail( required string message, struct fields = {} ) {
        throw( type = "Validation", message = arguments.message, extendedInfo = serializeJSON( arguments.fields ) );
    }

    public string function searchTerm( any value, numeric maxLength = 80 ) {
        if ( isNull( arguments.value ) || !isSimpleValue( arguments.value ) ) return "";
        var s = trim( reReplace( toString( arguments.value ), "[\x00-\x1F]", "", "all" ) );
        return left( s, arguments.maxLength );
    }

    public string function soc( required string value ) {
        if ( !reFind( "^[0-9]{2}-[0-9]{4}$", arguments.value ) ) fail( "Occupation codes look like 15-1252.", { soc: "Invalid SOC code" } );
        return arguments.value;
    }

    public string function cbsa( any value, boolean required = true ) {
        var v = isNull( arguments.value ) ? "" : trim( toString( arguments.value ) );
        if ( !len( v ) && !arguments.required ) return "";
        if ( !reFind( "^[0-9]{5}$", v ) ) fail( "Metro area codes are 5-digit CBSA codes.", { cbsa: "Invalid CBSA code" } );
        return v;
    }

    public string function stateCode( any value, boolean required = false ) {
        var v = isNull( arguments.value ) ? "" : uCase( trim( toString( arguments.value ) ) );
        if ( !len( v ) && !arguments.required ) return "";
        if ( !reFind( "^[A-Z]{2}$", v ) ) fail( "State codes are two letters, like FL.", { state: "Invalid state code" } );
        return v;
    }

    public numeric function intInRange( any value, required numeric minValue, required numeric maxValue, required numeric defaultValue, string field = "value" ) {
        if ( isNull( arguments.value ) || ( isSimpleValue( arguments.value ) && !len( trim( toString( arguments.value ) ) ) ) ) return arguments.defaultValue;
        if ( !isNumeric( arguments.value ) ) fail( "#arguments.field# must be a number.", { "#arguments.field#": "Not a number" } );
        var n = int( arguments.value );
        if ( n < arguments.minValue || n > arguments.maxValue ) fail( "#arguments.field# must be between #arguments.minValue# and #arguments.maxValue#.", { "#arguments.field#": "Out of range" } );
        return n;
    }

    public numeric function numberInRange( any value, required numeric minValue, required numeric maxValue, required numeric defaultValue, string field = "value" ) {
        if ( isNull( arguments.value ) || ( isSimpleValue( arguments.value ) && !len( trim( toString( arguments.value ) ) ) ) ) return arguments.defaultValue;
        if ( !isNumeric( arguments.value ) ) fail( "#arguments.field# must be a number.", { "#arguments.field#": "Not a number" } );
        var n = val( arguments.value );
        if ( n < arguments.minValue || n > arguments.maxValue ) fail( "#arguments.field# must be between #arguments.minValue# and #arguments.maxValue#.", { "#arguments.field#": "Out of range" } );
        return n;
    }

    public string function oneOf( any value, required string allowedList, required string defaultValue, string field = "value" ) {
        var v = isNull( arguments.value ) ? "" : trim( toString( arguments.value ) );
        if ( !len( v ) ) return arguments.defaultValue;
        if ( !listFindNoCase( arguments.allowedList, v ) ) fail( "#arguments.field# must be one of: #arguments.allowedList#.", { "#arguments.field#": "Not allowed" } );
        return lCase( v );
    }

}
