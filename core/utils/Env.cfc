/**
 * Environment configuration loader.
 * Resolution order: OS environment / JVM system property first, then the project .env file.
 * Never logs or exposes values.
 */
component accessors="false" {

    variables.values = {};

    public Env function init( required string rootPath ) {
        variables.values = loadDotEnv( arguments.rootPath & ".env" );
        var system = createObject( "java", "java.lang.System" );
        var osEnv = system.getenv();
        for ( var key in osEnv ) {
            variables.values[ key ] = osEnv[ key ];
        }
        return this;
    }

    public string function get( required string key, string defaultValue = "" ) {
        if ( structKeyExists( variables.values, arguments.key ) && len( variables.values[ arguments.key ] ) ) {
            return variables.values[ arguments.key ];
        }
        return arguments.defaultValue;
    }

    public boolean function bool( required string key, boolean defaultValue = false ) {
        var raw = lCase( trim( get( arguments.key, "" ) ) );
        if ( !len( raw ) ) return arguments.defaultValue;
        return listFindNoCase( "true,1,yes,on", raw ) > 0;
    }

    public numeric function integer( required string key, numeric defaultValue = 0 ) {
        var raw = trim( get( arguments.key, "" ) );
        return isNumeric( raw ) ? int( raw ) : arguments.defaultValue;
    }

    private struct function loadDotEnv( required string path ) {
        var result = {};
        if ( !fileExists( arguments.path ) ) return result;
        var text = fileRead( arguments.path, "utf-8" );
        if ( len( text ) && asc( left( text, 1 ) ) == 65279 ) text = mid( text, 2, len( text ) );
        var lines = listToArray( text, chr( 10 ) );
        for ( var line in lines ) {
            line = trim( replace( line, chr( 13 ), "", "all" ) );
            if ( !len( line ) || left( line, 1 ) == "##" || !find( "=", line ) ) continue;
            var key = trim( listFirst( line, "=" ) );
            var value = trim( mid( line, find( "=", line ) + 1, len( line ) ) );
            if ( len( value ) >= 2 && (
                ( left( value, 1 ) == '"' && right( value, 1 ) == '"' ) ||
                ( left( value, 1 ) == "'" && right( value, 1 ) == "'" )
            ) ) {
                value = mid( value, 2, len( value ) - 2 );
            }
            result[ key ] = value;
        }
        return result;
    }

}
