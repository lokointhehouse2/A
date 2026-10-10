/**
 * Program (CIP) <-> occupation (SOC) possibilities from the official NCES CIP 2020 - SOC 2018 crosswalk.
 * A mapping means a program can prepare people for an occupation. It is NOT a record of where graduates
 * work and never guarantees a job. Many-to-many in both directions.
 *
 * CIP levels: "23" (2-digit family), "23.01" (4-digit, used by College Scorecard), "23.0101" (6-digit, crosswalk).
 * Broader codes are expanded to every 6-digit program inside them.
 */
component {

    variables.dsn = "futurepathDB";

    public struct function careersForCip( required string cip, string cbsa = "" ) {
        if ( !reFind( "^[0-9]{2}(\.[0-9]{2}([0-9]{2})?)?$", arguments.cip ) ) throw( type = "Validation", message = "CIP codes look like 23, 23.01 or 23.0101." );
        var program = queryExecute( "SELECT cip_code, title, cip_level FROM cip_programs WHERE cip_code = :c", { c: { value: arguments.cip, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );
        var params = { prefix: { value: len( arguments.cip ) == 7 ? arguments.cip : arguments.cip & ( len( arguments.cip ) == 2 ? ".%" : "%" ), cfsqltype: "varchar" } };
        var match = len( arguments.cip ) == 7 ? "x.cip_code = :prefix" : "x.cip_code LIKE :prefix";
        var localCols = ", NULL AS local_median, NULL AS local_status";
        var localJoin = "";
        if ( reFind( "^[0-9]{5}$", arguments.cbsa ) ) {
            localJoin = "LEFT JOIN occupational_wages lw ON lw.soc_code = x.soc_code AND lw.area_level = 'metro' AND lw.area_code = :cbsa
                         AND lw.wage_year = (SELECT MAX(wage_year) FROM occupational_wages WHERE area_level = 'metro')";
            localCols = ", lw.annual_median AS local_median, CASE WHEN lw.id IS NULL THEN 'not_published' WHEN lw.annual_median IS NULL THEN 'partial' ELSE 'available' END AS local_status";
            params.cbsa = { value: arguments.cbsa, cfsqltype: "varchar" };
        }
        var rows = queryExecute( "
            SELECT x.soc_code, COALESCE(o.title, MAX(x.soc_title)) AS title, o.education_category,
                   GROUP_CONCAT(DISTINCT x.cip_code ORDER BY x.cip_code) AS via_cips,
                   nw.annual_median AS national_median #localCols#
            FROM cip_soc_crosswalk x
            LEFT JOIN occupations o ON o.soc_code = x.soc_code
            LEFT JOIN occupational_wages nw ON nw.soc_code = x.soc_code AND nw.area_level = 'national'
                 AND nw.wage_year = (SELECT MAX(wage_year) FROM occupational_wages WHERE area_level = 'national')
            #localJoin#
            WHERE #match#
            GROUP BY x.soc_code, o.title, o.education_category, nw.annual_median #len( localJoin ) ? ', lw.annual_median, lw.id' : ''#
            ORDER BY title", params, { datasource: variables.dsn, returntype: "array" } );
        return {
            cip: arguments.cip,
            title: arrayLen( program ) ? program[ 1 ].title : javacast( "null", "" ),
            careers: rows.map( function( r ) {
                return {
                    soc: r.soc_code, title: r.title, entryEducation: r.education_category, viaCips: listToArray( r.via_cips ?: "" ),
                    nationalMedian: r.national_median, localMedian: r.local_median, localStatus: r.local_status,
                    hasWageData: !isNull( r.national_median ) || !isNull( r.local_median )
                };
            } ),
            caveat: "These are occupations this field of study can prepare you for, from the official NCES CIP-SOC crosswalk. It is not a record of where graduates work, and some of these jobs need more education, a license or experience.",
            source: { name: "NCES CIP 2020 to SOC 2018 Crosswalk", url: "https://nces.ed.gov/ipeds/cipcode/resources.aspx" }
        };
    }

    public array function programsForSoc( required string soc ) {
        return queryExecute( "
            SELECT x.cip_code, c.title,
                   (SELECT COUNT(DISTINCT ip.unitid) FROM institution_programs ip WHERE ip.cip_code = LEFT(x.cip_code, 5)) AS colleges
            FROM cip_soc_crosswalk x JOIN cip_programs c ON c.cip_code = x.cip_code
            WHERE x.soc_code = :soc ORDER BY c.title", { soc: { value: arguments.soc, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return { cip: r.cip_code, family: left( r.cip_code, 5 ), title: r.title, collegesImported: r.colleges };
            } );
    }

}
