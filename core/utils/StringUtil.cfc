/**
 * Reusable string helpers.
 */
component {

    public string function slugify( required string input, numeric maxLength = 120 ) {
        var s = lCase( trim( arguments.input ) );
        s = replace( s, "&", " and ", "all" );
        s = reReplace( s, "[^a-z0-9]+", "-", "all" );
        s = reReplace( s, "^-+|-+$", "", "all" );
        if ( len( s ) > arguments.maxLength ) s = reReplace( left( s, arguments.maxLength ), "-+$", "" );
        return len( s ) ? s : "item";
    }

    /** lowercase, strip spaces/underscores/punctuation: "Book_Name " -> "bookname" */
    public string function normalizeKey( required string input ) {
        return reReplace( lCase( trim( arguments.input ) ), "[^a-z0-9]", "", "all" );
    }

    /** Escape LIKE wildcards; MariaDB uses backslash as the default LIKE escape. */
    public string function likeEscape( required string input ) {
        var s = replace( arguments.input, "\", "\\", "all" );
        s = replace( s, "%", "\%", "all" );
        s = replace( s, "_", "\_", "all" );
        return s;
    }

    public string function truncate( required string input, required numeric maxLength ) {
        if ( len( arguments.input ) <= arguments.maxLength ) return arguments.input;
        return left( arguments.input, arguments.maxLength - 1 ) & "…";
    }

    public string function randomToken( numeric bytes = 32 ) {
        var secureRandom = createObject( "java", "java.security.SecureRandom" ).init();
        var buffer = createObject( "java", "java.nio.ByteBuffer" ).allocate( arguments.bytes ).array();
        secureRandom.nextBytes( buffer );
        return lCase( binaryEncode( buffer, "hex" ) );
    }

    /** Collapses internal whitespace and trims. */
    public string function clean( any input ) {
        if ( isNull( arguments.input ) || !isSimpleValue( arguments.input ) ) return "";
        return trim( reReplace( toString( arguments.input ), "[\s\x{00A0}]+", " ", "all" ) );
    }

}
