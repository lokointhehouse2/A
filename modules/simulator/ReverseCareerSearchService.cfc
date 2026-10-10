/**
 * Dream-life reverse search: solve for the gross pay the lifestyle needs (bisection over the tax engine),
 * then compare it with local BLS wage evidence for every occupation published in the metro.
 * Careers below the target are still listed ("close") so lower-paying paths stay visible for exploration.
 * Ranking uses only sourced fields: wage margin, typical training years (BLS entry education) and BLS projections.
 */
component {

    variables.dsn = "futurepathDB";

    public ReverseCareerSearchService function init( required any simulator, required any wages ) {
        variables.simulator = arguments.simulator;
        variables.wages = arguments.wages;
        return this;
    }

    /**
     * options: { percentile, maxTrainingYears, education (list of pathway types), sort: jobs|margin|training|growth, limit }
     */
    public struct function search( required struct scenario, required struct ref, struct options = {} ) {
        var percentile = arguments.options.percentile ?: "median";
        var limit = min( 100, max( 5, arguments.options.limit ?: 25 ) );
        var sort = arguments.options.sort ?: "jobs";
        var maxYears = arguments.options.maxTrainingYears ?: 99;
        var eduFilter = arguments.options.education ?: "";
        var need = variables.simulator.requiredGross( arguments.scenario, arguments.ref );
        var training = trainingYears();
        var workFraction = arrayLen( arguments.scenario.earners ) ? arguments.scenario.earners[ 1 ].workFraction : 1;
        var affordable = [];
        var close = [];
        var noData = 0;
        for ( var w in variables.wages.forMetro( arguments.scenario.cbsa ) ) {
            var wage = w.annual[ percentile ] ?: javacast( "null", "" );
            if ( isNull( wage ) ) { noData++; continue; }
            var tr = training[ w.soc ] ?: { years: javacast( "null", "" ), pathway: "", pathwayName: "" };
            if ( !isNull( tr.years ) && tr.years > maxYears ) continue;
            if ( len( eduFilter ) && !listFindNoCase( eduFilter, tr.pathway ) ) continue;
            var item = {
                soc: w.soc, title: w.title, wage: wage, percentile: percentile, employment: w.employment,
                entryEducation: w.entryEducation, trainingYears: tr.years, pathway: tr.pathway, pathwayName: tr.pathwayName,
                outlookPercent: w.outlookPercent, outlookPeriod: w.outlookPeriod,
                margin: isNull( need ) ? javacast( "null", "" ) : wage * workFraction - need.earner1Gross
            };
            if ( !isNull( need ) && item.margin >= 0 ) arrayAppend( affordable, item ); else arrayAppend( close, item );
        }
        sortItems( affordable, sort );
        arraySort( close, function( a, b ) { return sgn( ( b.margin ?: 0 ) - ( a.margin ?: 0 ) ); } );
        return {
            required: need,
            percentile: percentile,
            affordableCount: arrayLen( affordable ),
            affordable: arraySlice( affordable, 1, min( limit, arrayLen( affordable ) ) ),
            close: arraySlice( close, 1, min( limit, arrayLen( close ) ) ),
            occupationsWithoutPublishedWage: noData,
            explanation: "Required pay is what earner 1 would need before taxes so that take-home pay covers this budget (using the same tax rules). Careers are compared using local BLS #percentile# wages; that's evidence about current workers, not a job offer.",
            source: variables.wages.source( variables.wages.latestYear( "metro" ) )
        };
    }

    private void function sortItems( required array items, required string sort ) {
        if ( arguments.sort == "training" ) {
            arraySort( arguments.items, function( a, b ) {
                var ya = a.trainingYears ?: 99; var yb = b.trainingYears ?: 99;
                if ( ya != yb ) return ya < yb ? -1 : 1;
                return sgn( ( b.margin ?: 0 ) - ( a.margin ?: 0 ) );
            } );
        } else if ( arguments.sort == "growth" ) {
            arraySort( arguments.items, function( a, b ) {
                var ga = a.outlookPercent ?: -999; var gb = b.outlookPercent ?: -999;
                if ( ga != gb ) return ga > gb ? -1 : 1;
                return sgn( ( b.margin ?: 0 ) - ( a.margin ?: 0 ) );
            } );
        } else if ( arguments.sort == "margin" ) {
            arraySort( arguments.items, function( a, b ) { return sgn( ( b.margin ?: 0 ) - ( a.margin ?: 0 ) ); } );
        } else {
            // jobs: careers with the most local jobs first
            arraySort( arguments.items, function( a, b ) { return sgn( ( b.employment ?: 0 ) - ( a.employment ?: 0 ) ); } );
        }
    }

    /** Shortest "common" pathway per occupation (typical years from education_pathways). */
    private struct function trainingYears() {
        var out = {};
        for ( var r in queryExecute( "
            SELECT op.soc_code, ep.pathway_key, ep.type, ep.name, ep.typical_years
            FROM occupation_pathways op JOIN education_pathways ep ON ep.id = op.pathway_id
            WHERE op.requirement_status IN ('common','required')
            ORDER BY op.soc_code, ep.typical_years", {}, { datasource: variables.dsn, returntype: "array" } ) ) {
            if ( !structKeyExists( out, r.soc_code ) ) out[ r.soc_code ] = { years: r.typical_years, pathway: r.type, pathwayName: r.name };
        }
        return out;
    }

}
