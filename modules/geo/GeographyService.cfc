/**
 * Metro areas (CBSAs) and their states. Lookups are by published CBSA code; search is only a convenience
 * for finding the code, never a substitute for it.
 */
component {

    variables.dsn = "futurepathDB";

    public GeographyService function init( required any strings ) {
        variables.strings = arguments.strings;
        return this;
    }

    public array function search( string q = "", numeric limit = 10 ) {
        var term = trim( arguments.q );
        var params = { lim: { value: arguments.limit, cfsqltype: "integer" } };
        var where = "m.active_flag = 1";
        if ( reFind( "^[0-9]{5}$", term ) ) {
            where &= " AND m.cbsa_code = :code";
            params.code = { value: term, cfsqltype: "char" };
        } else if ( len( term ) ) {
            var words = listToArray( reReplace( term, "[^A-Za-z0-9 .'\-]", " ", "all" ), " " );
            for ( var i = 1; i <= min( arrayLen( words ), 5 ); i++ ) {
                where &= " AND m.name LIKE :w#i#";
                params[ "w#i#" ] = { value: "%" & variables.strings.likeEscape( words[ i ] ) & "%", cfsqltype: "varchar" };
            }
            params.prefix = { value: variables.strings.likeEscape( term ) & "%", cfsqltype: "varchar" };
        }
        var orderBy = len( term ) && !reFind( "^[0-9]{5}$", term ) ? "CASE WHEN m.name LIKE :prefix THEN 0 ELSE 1 END, total_emp DESC" : "total_emp DESC";
        return queryExecute( "
            SELECT m.cbsa_code, m.name, m.primary_state_code,
                   (SELECT w.employment_count FROM occupational_wages w WHERE w.cbsa_code = m.cbsa_code AND w.soc_code = '00-0000' ORDER BY w.wage_year DESC LIMIT 1) AS total_emp,
                   (SELECT GROUP_CONCAT(s.state_code ORDER BY s.state_code) FROM metro_state_map ms JOIN states s ON s.state_fips = ms.state_fips WHERE ms.cbsa_code = m.cbsa_code) AS state_codes
            FROM metro_areas m
            WHERE #where#
            ORDER BY #orderBy#
            LIMIT :lim", params, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return { cbsa: r.cbsa_code, name: r.name, primaryState: r.primary_state_code, states: listToArray( r.state_codes ?: "" ), totalEmployment: r.total_emp };
            } );
    }

    public struct function get( required string cbsa ) {
        var rows = queryExecute( "SELECT cbsa_code, name, geographic_type, primary_state_code, source_year FROM metro_areas WHERE cbsa_code = :c",
            { c: { value: arguments.cbsa, cfsqltype: "char" } }, { datasource: variables.dsn, returntype: "array" } );
        if ( !arrayLen( rows ) ) throw( type = "NotFound", message = "That metro area isn't in the imported data." );
        var states = queryExecute( "SELECT s.state_code, s.name, s.state_fips FROM metro_state_map ms JOIN states s ON s.state_fips = ms.state_fips WHERE ms.cbsa_code = :c ORDER BY s.state_code",
            { c: { value: arguments.cbsa, cfsqltype: "char" } }, { datasource: variables.dsn, returntype: "array" } );
        var r = rows[ 1 ];
        return {
            cbsa: r.cbsa_code, name: r.name, type: r.geographic_type, primaryState: r.primary_state_code, sourceYear: r.source_year,
            shortName: shortName( r.name ),
            states: states.map( function( s ) { return { code: s.state_code, name: s.name, fips: s.state_fips }; } ),
            // New York City residents pay NYC resident income tax; it applies only inside the five boroughs.
            hasNycOption: r.cbsa_code == "35620"
        };
    }

    public array function featured( required array codes ) {
        var out = [];
        for ( var c in arguments.codes ) {
            try { arrayAppend( out, get( c ) ); } catch ( NotFound e ) {}
        }
        return out;
    }

    /** "Orlando-Kissimmee-Sanford, FL" -> "Orlando" */
    public string function shortName( required string name ) {
        return listFirst( listFirst( arguments.name, "," ), "-" );
    }

}
