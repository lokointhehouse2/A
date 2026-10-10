/**
 * Output helpers for views. Everything user- or data-derived is encoded at output time.
 */
component {

    public ViewHelper function init( required any csrf, required any config ) {
        variables.csrf = arguments.csrf;
        variables.config = arguments.config;
        variables.assetVersions = {};
        return this;
    }

    public string function e( any value ) {
        if ( isNull( arguments.value ) ) return "";
        return encodeForHTML( toString( arguments.value ) );
    }

    public string function attr( any value ) {
        if ( isNull( arguments.value ) ) return "";
        return encodeForHTMLAttribute( toString( arguments.value ) );
    }

    public string function u( any value ) {
        if ( isNull( arguments.value ) ) return "";
        return encodeForURL( toString( arguments.value ) );
    }

    /** "$52,340" or the fallback when the value is null/unpublished. */
    public string function money( any value, string fallback = "Not published", numeric decimals = 0 ) {
        if ( isNull( arguments.value ) || !isNumeric( arguments.value ) ) return e( arguments.fallback );
        var n = arguments.value;
        var s = arguments.decimals > 0 ? numberFormat( abs( n ), ",." & repeatString( "0", arguments.decimals ) ) : numberFormat( round( abs( n ) ), "," );
        return ( n < 0 ? "-$" : "$" ) & s;
    }

    public string function pct( any value, numeric decimals = 0, string fallback = "Not published" ) {
        if ( isNull( arguments.value ) || !isNumeric( arguments.value ) ) return e( arguments.fallback );
        return numberFormat( arguments.value * 100, arguments.decimals > 0 ? "0." & repeatString( "0", arguments.decimals ) : "0" ) & "%";
    }

    public string function num( any value, string fallback = "—" ) {
        if ( isNull( arguments.value ) || !isNumeric( arguments.value ) ) return e( arguments.fallback );
        return numberFormat( arguments.value, "," );
    }

    public string function csrfField() {
        return variables.csrf.field();
    }

    public string function csrfToken() {
        return variables.csrf.token();
    }

    /** Asset URL with a cache-busting version from the file's modification time. */
    public string function asset( required string path ) {
        if ( !structKeyExists( variables.assetVersions, arguments.path ) || variables.config.isDev ) {
            var full = variables.config.rootPath & "assets/" & arguments.path;
            variables.assetVersions[ arguments.path ] = fileExists( full ) ? left( hash( toString( createObject( "java", "java.io.File" ).init( full ).lastModified() ), "md5" ), 8 ) : "0";
        }
        return "/assets/" & arguments.path & "?v=" & variables.assetVersions[ arguments.path ];
    }

    /** JSON for <script type="application/json"> blocks (not executed, so CSP-safe); "</" is neutralized. */
    public string function jsonData( any value ) {
        return replace( serializeJSON( arguments.value ), "</", "<\/", "all" );
    }

    public any function takeFlash() {
        if ( !structKeyExists( session, "flash" ) ) return javacast( "null", "" );
        var f = session.flash;
        structDelete( session, "flash" );
        return f;
    }

    public string function statusLabel( any status ) {
        switch ( arguments.status ?: "" ) {
            case "available": return "Published";
            case "partial": return "Partly published";
            case "not_published": return "Not published here";
        }
        return "Unknown";
    }

}
