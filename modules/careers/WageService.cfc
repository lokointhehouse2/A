/**
 * BLS OEWS wage lookups with explicit availability status and provenance.
 *
 * status:
 *   available      annual median published
 *   partial        the row exists but the annual median is suppressed (*) or top-coded (#); other figures may exist
 *   not_published  BLS publishes no estimate for this occupation in this area (too few workers or confidentiality)
 * Percentiles describe the spread of current wages in the occupation; they are NOT years of experience.
 */
component {

    variables.dsn = "futurepathDB";
    variables.topCode = { annual: 239200, hourly: 115, year: 2025 };

    public numeric function latestYear( string areaLevel = "metro" ) {
        var q = queryExecute( "SELECT MAX(wage_year) AS y FROM occupational_wages WHERE area_level = :l", { l: { value: arguments.areaLevel, cfsqltype: "varchar" } }, { datasource: variables.dsn } );
        return val( q.y ?: 0 );
    }

    /** Local (metro) and national wages for one occupation, with definitions and source. */
    public struct function forOccupation( required string soc, string cbsa = "", numeric year = 0 ) {
        var metroYear = arguments.year > 0 ? arguments.year : latestYear( "metro" );
        var nationalYear = latestYear( "national" );
        var localWage = javacast( "null", "" );
        if ( reFind( "^[0-9]{5}$", arguments.cbsa ) ) {
            localWage = normalize( fetchRow( arguments.soc, "metro", arguments.cbsa, metroYear ), "metro", arguments.cbsa, metroYear );
        }
        var national = normalize( fetchRow( arguments.soc, "national", "99", nationalYear ), "national", "99", nationalYear );
        return { soc: arguments.soc, "local": localWage, national: national, definitions: definitions(), source: source( metroYear ) };
    }

    /** Same occupation across several metros (landing-page comparison). */
    public array function compareMetros( required string soc, required array cbsaCodes ) {
        var y = latestYear( "metro" );
        var out = [];
        for ( var c in arguments.cbsaCodes ) arrayAppend( out, normalize( fetchRow( arguments.soc, "metro", c, y ), "metro", c, y ) );
        return out;
    }

    /** All detailed occupations with a published wage in a metro (reverse search). */
    public array function forMetro( required string cbsa ) {
        var y = latestYear( "metro" );
        var cbsa = arguments.cbsa;
        return queryExecute( "
            SELECT w.*, o.title, o.education_category, p.outlook_percent, p.outlook_period
            FROM occupational_wages w
            JOIN occupations o ON o.soc_code = w.soc_code AND o.occupation_group = 'detailed'
            LEFT JOIN occupation_profiles p ON p.soc_code = w.soc_code
            WHERE w.area_level = 'metro' AND w.area_code = :c AND w.wage_year = :y",
            { c: { value: arguments.cbsa, cfsqltype: "varchar" }, y: { value: y, cfsqltype: "smallint" } },
            { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                var n = normalize( r, "metro", cbsa, y );
                n.soc = r.soc_code;
                n.title = r.title;
                n.entryEducation = r.education_category;
                n.outlookPercent = r.outlook_percent;
                n.outlookPeriod = r.outlook_period;
                return n;
            } );
    }

    /** Wage for a percentile key (p10, p25, median, p75, p90, mean), or null when not published. */
    public any function annualFor( required struct wage, required string percentile ) {
        if ( !isStruct( arguments.wage.annual ?: "" ) ) return javacast( "null", "" );
        return arguments.wage.annual[ arguments.percentile ] ?: javacast( "null", "" );
    }

    public struct function definitions() {
        return {
            "mean": "Average (mean) annual wage of all workers in the occupation in this area.",
            "median": "Half of workers earn more than this and half earn less.",
            "p10": "10% of workers earn less than this (90% earn more).",
            "p25": "25% of workers earn less than this.",
            "p75": "75% of workers earn less than this.",
            "p90": "90% of workers earn less than this.",
            "percentileCaveat": "Percentiles show how pay is spread across current workers. They are not a career ladder or a measure of years of experience.",
            "topCode": "Wages at or above $#numberFormat( variables.topCode.annual, ',' )# per year ($#variables.topCode.hourly#/hour) are not published as exact figures (shown as '#chr( 8805 )# $#numberFormat( variables.topCode.annual, ',' )#').",
            "annualOnly": "Only annual wages are published for this occupation (for example, teachers who work a school year).",
            "hourlyOnly": "Only hourly wages are published for this occupation, so no annual figure is available."
        };
    }

    public struct function source( required numeric year ) {
        return {
            name: "BLS Occupational Employment and Wage Statistics (OEWS), May #arguments.year#",
            agency: "U.S. Bureau of Labor Statistics",
            url: "https://www.bls.gov/oes/tables.htm",
            year: arguments.year,
            note: "An occupational wage describes current workers in a labor market. It is not a job offer or a starting salary."
        };
    }

    // ------------------------------------------------------------------ internals

    private any function fetchRow( required string soc, required string level, required string code, required numeric year ) {
        var rows = queryExecute( "SELECT * FROM occupational_wages WHERE soc_code = :s AND area_level = :l AND area_code = :c AND wage_year = :y", {
            s: { value: arguments.soc, cfsqltype: "varchar" }, l: { value: arguments.level, cfsqltype: "varchar" },
            c: { value: arguments.code, cfsqltype: "varchar" }, y: { value: arguments.year, cfsqltype: "smallint" }
        }, { datasource: variables.dsn, returntype: "array" } );
        return arrayLen( rows ) ? rows[ 1 ] : javacast( "null", "" );
    }

    public struct function normalize( any row, required string level, required string code, required numeric year ) {
        if ( isNull( arguments.row ) ) {
            return {
                status: "not_published", areaLevel: arguments.level, areaCode: arguments.code, year: arguments.year,
                annual: javacast( "null", "" ), hourly: javacast( "null", "" ), employment: javacast( "null", "" ),
                flags: { annualOnly: false, hourlyOnly: false, suppressed: [], topcoded: [] },
                message: arguments.level == "metro"
                    ? "BLS does not publish a wage estimate for this occupation in this metro area (often because too few people do this job there)."
                    : "BLS does not publish a national wage estimate for this occupation."
            };
        }
        var r = arguments.row;
        var suppressed = listToArray( r.suppression_code ?: "", ";" );
        var topcoded = listToArray( r.topcoded_fields ?: "", "," );
        var status = isNull( r.annual_median ) ? "partial" : "available";
        var message = "";
        if ( status == "partial" ) {
            if ( arrayFindNoCase( topcoded, "A_MEDIAN" ) ) message = "The median wage is at or above $#numberFormat( variables.topCode.annual, ',' )#, so BLS does not publish an exact figure.";
            else if ( r.hourly_only ) message = "BLS publishes only hourly wages for this occupation, so no annual median is available.";
            else message = "BLS did not publish the median wage for this occupation here (estimate not available).";
        }
        return {
            status: status, areaLevel: arguments.level, areaCode: arguments.code, year: r.wage_year,
            annual: { mean: r.annual_mean, p10: r.annual_p10, p25: r.annual_p25, median: r.annual_median, p75: r.annual_p75, p90: r.annual_p90 },
            hourly: { mean: r.hourly_mean, median: r.hourly_median },
            employment: r.employment_count,
            precision: { employmentPrse: r.employment_prse, meanPrse: r.mean_prse },
            flags: { annualOnly: r.annual_only == 1, hourlyOnly: r.hourly_only == 1, suppressed: suppressed, topcoded: topcoded },
            message: message
        };
    }

}
