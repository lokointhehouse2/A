/**
 * Programs (CIP fields of study) and observed field-of-study outcomes from College Scorecard.
 * Observed program earnings are a different measure from BLS occupational wages and are labeled as such.
 */
component {

    variables.dsn = "futurepathDB";
    variables.credentialNames = { "1": "Undergraduate certificate", "2": "Associate degree", "3": "Bachelor's degree", "4": "Post-baccalaureate certificate",
        "5": "Master's degree", "6": "Doctoral degree", "7": "First professional degree", "8": "Graduate certificate" };
    variables.credentialPathway = { "1": "certificate", "2": "associate", "3": "bachelor", "4": "bachelor", "5": "master", "6": "doctoral", "7": "professional", "8": "master" };

    public ProgramService function init( required any strings ) {
        variables.strings = arguments.strings;
        return this;
    }

    public array function forInstitution( required numeric unitid ) {
        var rows = queryExecute( "
            SELECT ip.cip_code, ip.credential_level_code, ip.credential_title, ip.program_label, ip.reported_awards,
                   po.earnings_horizon, po.earnings_median, po.earnings_count, po.debt_median, po.debt_measure, po.suppressed_flag
            FROM institution_programs ip
            LEFT JOIN program_outcomes po ON po.unitid = ip.unitid AND po.cip_code = ip.cip_code AND po.credential_level_code = ip.credential_level_code AND po.report_year = ip.reporting_year
            WHERE ip.unitid = :id
            ORDER BY ip.program_label, ip.credential_level_code, po.earnings_horizon", { id: { value: arguments.unitid, cfsqltype: "integer" } }, { datasource: variables.dsn, returntype: "array" } );
        var programs = [];
        var index = {};
        for ( var r in rows ) {
            var key = r.cip_code & "|" & r.credential_level_code;
            if ( !structKeyExists( index, key ) ) {
                var p = {
                    cip: r.cip_code, credentialLevel: r.credential_level_code,
                    credential: r.credential_title ?: ( variables.credentialNames[ toString( r.credential_level_code ) ] ?: "Credential" ),
                    pathway: variables.credentialPathway[ toString( r.credential_level_code ) ] ?: "certificate",
                    title: r.program_label, awards: r.reported_awards,
                    observedEarnings: {}, debtMedian: r.debt_median, debtMeasure: r.debt_measure, earningsAvailable: false
                };
                arrayAppend( programs, p );
                index[ key ] = arrayLen( programs );
            }
            var prog = programs[ index[ key ] ];
            if ( !isNull( r.earnings_horizon ) ) {
                prog.observedEarnings[ r.earnings_horizon ] = { median: r.earnings_median, count: r.earnings_count };
                if ( !isNull( r.earnings_median ) ) prog.earningsAvailable = true;
            }
        }
        return programs;
    }

    /** Fields of study (CIP) by title, with how many imported colleges offer each. */
    public array function search( string q = "", numeric limit = 15 ) {
        var params = { lim: { value: arguments.limit, cfsqltype: "integer" } };
        var where = "c.cip_level IN (4, 6)";
        var term = trim( arguments.q );
        if ( reFind( "^[0-9]{2}(\.[0-9]{2}([0-9]{2})?)?$", term ) ) {
            where &= " AND c.cip_code LIKE :code";
            params.code = { value: term & "%", cfsqltype: "varchar" };
        } else {
            var words = listToArray( reReplace( term, "[^A-Za-z0-9 \-]", " ", "all" ), " " );
            for ( var i = 1; i <= min( arrayLen( words ), 5 ); i++ ) {
                where &= " AND c.title LIKE :w#i#";
                params[ "w#i#" ] = { value: "%" & variables.strings.likeEscape( words[ i ] ) & "%", cfsqltype: "varchar" };
            }
        }
        return queryExecute( "
            SELECT c.cip_code, c.title, c.cip_level,
                   (SELECT COUNT(DISTINCT ip.unitid) FROM institution_programs ip WHERE ip.cip_code = c.cip_code) AS colleges,
                   (SELECT COUNT(DISTINCT x.soc_code) FROM cip_soc_crosswalk x WHERE x.cip_code LIKE CONCAT(c.cip_code, '%')) AS mapped_careers
            FROM cip_programs c
            WHERE #where#
            ORDER BY c.cip_level ASC, colleges DESC, c.title
            LIMIT :lim", params, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return { cip: r.cip_code, title: r.title, level: r.cip_level, colleges: r.colleges, mappedCareers: r.mapped_careers };
            } );
    }

    public struct function credentialNames() {
        return duplicate( variables.credentialNames );
    }

}
