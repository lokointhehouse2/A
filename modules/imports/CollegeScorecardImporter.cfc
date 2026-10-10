/**
 * College Scorecard importer. Reads API result pages saved as JSON (storage/imports/raw/scorecard/*.json),
 * written by the allowlisted Scorecard connector or uploaded by an admin.
 *
 * Field names used (verified against live API responses):
 *   institution: school.name, school.city, school.state, school.school_url, school.ownership,
 *                school.degrees_awarded.predominant, location.lat/lon, latest.student.size
 *   costs:       latest.cost.tuition.in_state / out_of_state, latest.cost.attendance.academic_year,
 *                latest.cost.avg_net_price.overall      (kept separate: never summed)
 *   outcomes:    latest.completion.rate_suppressed.overall, latest.student.retention_rate.four_year.full_time,
 *                latest.aid.median_debt.completers.overall
 *   programs:    latest.programs.cip_4_digit[] (code, title, credential.level, counts.ipeds_awards2,
 *                earnings.{1_yr,4_yr,5_yr}.overall_median_earnings, debt.staff_grad_plus.all.{eval_inst,all_inst}.median)
 * Program earnings are observed outcomes of former students in a field at an institution; they are kept apart
 * from BLS occupational wages everywhere in the app.
 */
component extends="BaseImporter" {

    variables.ownership = { "1": "Public", "2": "Private nonprofit", "3": "Private for-profit" };
    variables.predominant = { "0": "Not classified", "1": "Certificate", "2": "Associate", "3": "Bachelor's", "4": "Graduate" };

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var dir = directoryExists( arguments.path ) ? arguments.path : getDirectoryFromPath( arguments.path );
        var files = directoryExists( arguments.path ) ? directoryList( dir, false, "path", "*.json", "name asc" ) : [ arguments.path ];
        var ctx = arguments.ctx;
        var label = "College Scorecard latest release (fetched " & dateFormat( getFileInfo( files[ 1 ] ).lastModified, "yyyy-mm-dd" ) & ")";
        var reportYear = "latest";
        var instRows = [];
        var costRows = [];
        var outcomeRows = [];
        var cipRows = {};
        var progRows = [];
        var progOutcomeRows = [];
        for ( var f in files ) {
            var doc = deserializeJSON( fileRead( f, "utf-8" ) );
            if ( !isStruct( doc ) || !isArray( doc.results ?: "" ) ) { warn( ctx, "#getFileFromPath( f )# is not a Scorecard results page" ); continue; }
            for ( var s in doc.results ) {
                ctx.seen++;
                var unitid = s[ "id" ] ?: 0;
                if ( !isNumeric( unitid ) || unitid <= 0 ) { ctx.skipped++; continue; }
                arrayAppend( instRows, [
                    unitid, s[ "school.name" ] ?: "Unknown", s[ "school.city" ] ?: javacast( "null", "" ), s[ "school.state" ] ?: javacast( "null", "" ),
                    normalizeUrl( s[ "school.school_url" ] ?: "" ),
                    variables.ownership[ toString( s[ "school.ownership" ] ?: "" ) ] ?: javacast( "null", "" ),
                    variables.predominant[ toString( s[ "school.degrees_awarded.predominant" ] ?: "" ) ] ?: javacast( "null", "" ),
                    s[ "latest.student.size" ] ?: javacast( "null", "" ),
                    s[ "location.lat" ] ?: javacast( "null", "" ), s[ "location.lon" ] ?: javacast( "null", "" ),
                    reportYear, ctx.sourceId
                ] );
                arrayAppend( costRows, [
                    unitid, reportYear,
                    s[ "latest.cost.tuition.in_state" ] ?: javacast( "null", "" ),
                    s[ "latest.cost.tuition.out_of_state" ] ?: javacast( "null", "" ),
                    s[ "latest.cost.attendance.academic_year" ] ?: javacast( "null", "" ),
                    s[ "latest.cost.avg_net_price.overall" ] ?: javacast( "null", "" ),
                    "Average net price: Title IV aid recipients (in-state for public institutions). Cost of attendance: academic-year programs.",
                    ctx.sourceId
                ] );
                arrayAppend( outcomeRows, [
                    unitid, reportYear,
                    s[ "latest.completion.rate_suppressed.overall" ] ?: javacast( "null", "" ),
                    s[ "latest.student.retention_rate.four_year.full_time" ] ?: javacast( "null", "" ),
                    s[ "latest.aid.median_debt.completers.overall" ] ?: javacast( "null", "" ),
                    serializeJSON( {
                        "completion_rate": "Share of first-time, full-time students completing within 150% of normal time (suppressed for small cohorts)",
                        "retention_rate": "Share of first-time, full-time students returning for a second year (four-year institutions)",
                        "median_debt": "Median federal loan debt of students who completed"
                    } ),
                    ctx.sourceId
                ] );
                for ( var p in ( s[ "latest.programs.cip_4_digit" ] ?: [] ) ) {
                    var raw = toString( p.code ?: "" );
                    if ( !reFind( "^[0-9]{4}$", raw ) ) continue;
                    var cip = left( raw, 2 ) & "." & right( raw, 2 );
                    var title = reReplace( trim( p.title ?: "" ), "\.$", "" );
                    if ( !structKeyExists( cipRows, cip ) && len( title ) ) cipRows[ cip ] = [ cip, title, 4, 2020 ];
                    var level = val( p.credential.level ?: 0 );
                    if ( level <= 0 ) continue;
                    arrayAppend( progRows, [ unitid, cip, level, p.credential.title ?: javacast( "null", "" ), title, p.counts.ipeds_awards2 ?: javacast( "null", "" ), reportYear ] );
                    var debt = debtMedian( p );
                    for ( var horizon in [ "1_yr", "4_yr", "5_yr" ] ) {
                        var e = p.earnings[ horizon ] ?: {};
                        var median = isStruct( e ) ? ( e.overall_median_earnings ?: javacast( "null", "" ) ) : javacast( "null", "" );
                        var count = isStruct( e ) && isStruct( e.working_not_enrolled ?: "" ) ? ( e.working_not_enrolled.overall_count ?: javacast( "null", "" ) ) : javacast( "null", "" );
                        arrayAppend( progOutcomeRows, [
                            unitid, cip, level, reportYear, horizon, median,
                            "Median earnings of former students working and not enrolled, #replace( horizon, '_yr', '' )# year(s) after completion",
                            count, debt.value, debt.measure,
                            serializeJSON( { "horizon": horizon, "credential": p.credential.title ?: "" } ),
                            isNull( median ) ? 1 : 0, ctx.sourceId
                        ] );
                    }
                }
            }
        }
        var counts = { seen: 0, inserted: 0, updated: 0, skipped: 0 };
        upsert( "institutions", [ "unitid", "name", "city", "state_code", "website_url", "control_type", "predominant_degree", "student_size", "latitude", "longitude", "source_year", "source_id" ],
            [ "integer", "varchar", "varchar", "char", "varchar", "varchar", "varchar", "integer", "decimal", "decimal", "varchar", "integer" ],
            instRows, [ "name", "city", "state_code", "website_url", "control_type", "predominant_degree", "student_size", "latitude", "longitude", "source_year", "source_id" ], ctx );
        upsert( "institution_costs", [ "unitid", "academic_year", "in_state_tuition", "out_state_tuition", "total_cost_of_attendance", "average_net_price", "reporting_population", "source_id" ],
            [ "integer", "varchar", "decimal", "decimal", "decimal", "decimal", "varchar", "integer" ], costRows,
            [ "in_state_tuition", "out_state_tuition", "total_cost_of_attendance", "average_net_price", "reporting_population", "source_id" ], counts );
        upsert( "institution_outcomes", [ "unitid", "report_year", "completion_rate", "retention_rate", "median_debt", "published_definitions_json", "source_id" ],
            [ "integer", "varchar", "decimal", "decimal", "decimal", "longvarchar", "integer" ], outcomeRows,
            [ "completion_rate", "retention_rate", "median_debt", "published_definitions_json", "source_id" ], counts );
        var cipList = [];
        for ( var k in cipRows ) arrayAppend( cipList, cipRows[ k ] );
        // 4-digit CIP families come from Scorecard titles; existing titles are kept.
        upsert( "cip_programs", [ "cip_code", "title", "cip_level", "taxonomy_year" ], [ "varchar", "varchar", "tinyint", "smallint" ], cipList, [ "cip_level" ], counts );
        upsert( "institution_programs", [ "unitid", "cip_code", "credential_level_code", "credential_title", "program_label", "reported_awards", "reporting_year" ],
            [ "integer", "varchar", "tinyint", "varchar", "varchar", "integer", "varchar" ], progRows,
            [ "credential_title", "program_label", "reported_awards" ], counts );
        upsert( "program_outcomes", [ "unitid", "cip_code", "credential_level_code", "report_year", "earnings_horizon", "earnings_median", "earnings_measure",
                "earnings_count", "debt_median", "debt_measure", "cohort_info_json", "suppressed_flag", "source_id" ],
            [ "integer", "varchar", "tinyint", "varchar", "varchar", "decimal", "varchar", "integer", "decimal", "varchar", "varchar", "tinyint", "integer" ],
            progOutcomeRows, [ "earnings_median", "earnings_measure", "earnings_count", "debt_median", "debt_measure", "cohort_info_json", "suppressed_flag", "source_id" ], counts );
        progress( ctx, "#arrayLen( instRows )# institutions, #arrayLen( progRows )# programs" );
        return { vintageYear: javacast( "null", "" ), vintageLabel: label };
    }

    /** Median federal (Stafford + Grad PLUS) debt of completers: this institution first, then all institutions. */
    private struct function debtMedian( required struct program ) {
        var d = arguments.program.debt.staff_grad_plus.all ?: {};
        if ( isStruct( d ) ) {
            var own = d.eval_inst.median ?: javacast( "null", "" );
            if ( !isNull( own ) ) return { value: own, measure: "Median Stafford + Grad PLUS debt of completers (borrowed at this institution)" };
            var all = d.all_inst.median ?: javacast( "null", "" );
            if ( !isNull( all ) ) return { value: all, measure: "Median Stafford + Grad PLUS debt of completers (all institutions attended)" };
        }
        return { value: javacast( "null", "" ), measure: javacast( "null", "" ) };
    }

    private any function normalizeUrl( required string raw ) {
        var u = trim( arguments.raw );
        if ( !len( u ) ) return javacast( "null", "" );
        if ( !reFindNoCase( "^https?://", u ) ) u = "https://" & u;
        return reFindNoCase( "^https?://[a-z0-9.\-]+(/[^\s""'<>]*)?$", u ) ? left( u, 255 ) : javacast( "null", "" );
    }

}
