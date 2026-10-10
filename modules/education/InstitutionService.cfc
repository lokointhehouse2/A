/**
 * Colleges (College Scorecard institutions by UNITID): search, costs and completion outcomes.
 * Tuition, cost of attendance and average net price are different measures and are always reported separately.
 */
component {

    variables.dsn = "futurepathDB";

    public InstitutionService function init( required any strings ) {
        variables.strings = arguments.strings;
        return this;
    }

    public array function search( string q = "", string state = "", numeric limit = 12, string cip = "" ) {
        var params = { lim: { value: arguments.limit, cfsqltype: "integer" } };
        var where = "i.active_flag = 1";
        var words = listToArray( reReplace( trim( arguments.q ), "[^A-Za-z0-9 &.'\-]", " ", "all" ), " " );
        for ( var i = 1; i <= min( arrayLen( words ), 5 ); i++ ) {
            where &= " AND i.name LIKE :w#i#";
            params[ "w#i#" ] = { value: "%" & variables.strings.likeEscape( words[ i ] ) & "%", cfsqltype: "varchar" };
        }
        if ( len( arguments.state ) ) {
            where &= " AND i.state_code = :st";
            params.st = { value: arguments.state, cfsqltype: "char" };
        }
        if ( len( arguments.cip ) ) {
            where &= " AND EXISTS (SELECT 1 FROM institution_programs ip WHERE ip.unitid = i.unitid AND ip.cip_code LIKE :cip)";
            params.cip = { value: variables.strings.likeEscape( arguments.cip ) & "%", cfsqltype: "varchar" };
        }
        return queryExecute( "
            SELECT i.unitid, i.name, i.city, i.state_code, i.control_type, i.predominant_degree, i.student_size,
                   c.in_state_tuition, c.out_state_tuition, c.average_net_price, c.total_cost_of_attendance,
                   (SELECT COUNT(*) FROM institution_programs ip WHERE ip.unitid = i.unitid) AS program_count
            FROM institutions i
            LEFT JOIN institution_costs c ON c.unitid = i.unitid AND c.academic_year = 'latest'
            WHERE #where#
            ORDER BY i.student_size DESC, i.name
            LIMIT :lim", params, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return {
                    unitid: r.unitid, name: r.name, city: r.city, state: r.state_code, control: r.control_type,
                    predominantDegree: r.predominant_degree, studentSize: r.student_size, programCount: r.program_count,
                    costs: { inStateTuition: r.in_state_tuition, outOfStateTuition: r.out_state_tuition, averageNetPrice: r.average_net_price, costOfAttendance: r.total_cost_of_attendance }
                };
            } );
    }

    public struct function get( required numeric unitid ) {
        var rows = queryExecute( "
            SELECT i.*, c.academic_year, c.in_state_tuition, c.out_state_tuition, c.total_cost_of_attendance, c.average_net_price, c.reporting_population,
                   o.completion_rate, o.retention_rate, o.median_debt, o.published_definitions_json, s.name AS source_name, s.source_url
            FROM institutions i
            LEFT JOIN institution_costs c ON c.unitid = i.unitid AND c.academic_year = 'latest'
            LEFT JOIN institution_outcomes o ON o.unitid = i.unitid AND o.report_year = 'latest'
            LEFT JOIN data_sources s ON s.id = i.source_id
            WHERE i.unitid = :id", { id: { value: arguments.unitid, cfsqltype: "integer" } }, { datasource: variables.dsn, returntype: "array" } );
        if ( !arrayLen( rows ) ) throw( type = "NotFound", message = "That college isn't in the imported data." );
        var r = rows[ 1 ];
        return {
            unitid: r.unitid, name: r.name, city: r.city, state: r.state_code, website: r.website_url,
            control: r.control_type, predominantDegree: r.predominant_degree, studentSize: r.student_size,
            costs: {
                period: r.academic_year, inStateTuition: r.in_state_tuition, outOfStateTuition: r.out_state_tuition,
                costOfAttendance: r.total_cost_of_attendance, averageNetPrice: r.average_net_price, population: r.reporting_population,
                note: "Tuition, cost of attendance and average net price are separate measures. Net price already subtracts average grants and scholarships for aid recipients; do not add them together."
            },
            outcomes: {
                completionRate: r.completion_rate, retentionRate: r.retention_rate, medianDebt: r.median_debt,
                definitions: isJSON( r.published_definitions_json ?: "" ) ? deserializeJSON( r.published_definitions_json ) : {}
            },
            source: { name: r.source_name ?: "College Scorecard", url: r.source_url ?: "https://collegescorecard.ed.gov/data/", vintage: r.source_year }
        };
    }

}
