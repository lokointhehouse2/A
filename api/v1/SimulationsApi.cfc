/**
 * GET  /api/v1/reference/bundle?cbsa=&socs=&state=&nyc=&unitid=   reference data for client-side recalculation
 * POST /api/v1/simulations/calculate        { scenario }                     authoritative budget calculation + result.projection (age timeline)
 * POST /api/v1/simulations/reverse-careers  { scenario, options }            required pay + matching careers
 * POST /api/v1/simulations/compare          { scenarios:[...] } (max 3)       side-by-side results
 * POST /api/v1/scenarios                    { scenario, title }               save config for a share link
 * GET  /api/v1/scenarios/{uuid}                                              load a shared scenario
 */
component extends="controllers.BaseController" {

    public struct function referenceBundle( required struct rc ) {
        var v = variables.b.validator;
        var cbsa = v.cbsa( arguments.rc.cbsa ?: "" );
        var socs = listToArray( v.searchTerm( arguments.rc.socs ?: "", 40 ) );
        for ( var s in socs ) v.soc( s );
        if ( arrayLen( socs ) > 4 ) v.fail( "At most four occupations per request.", { socs: "Too many" } );
        var unitid = v.intInRange( arguments.rc.unitid ?: "", 0, 999999999, 0, "unitid" );
        var bundle = variables.b.reference.bundle( cbsa, socs, v.stateCode( arguments.rc.state ?: "" ), ( arguments.rc.nyc ?: "" ) == "1",
            v.intInRange( arguments.rc.taxYear ?: "", 2020, 2035, 0, "taxYear" ), unitid );
        bundle.assumptions = variables.b.simulator.assumptionDefaults();
        bundle.calculationVersion = variables.b.config.calculationVersion;
        return ok( bundle );
    }

    public struct function calculate( required struct rc ) {
        var scenario = variables.b.simulator.normalize( requireScenario( arguments.rc.body ) );
        var ref = refFor( scenario );
        var result = variables.b.simulator.compute( scenario, ref );
        result.projection = variables.b.goals.evaluate( scenario, ref );
        return ok( { scenario: scenario, result: result } );
    }

    public struct function reverseCareers( required struct rc ) {
        var v = variables.b.validator;
        var scenario = variables.b.simulator.normalize( requireScenario( arguments.rc.body ) );
        var o = isStruct( arguments.rc.body.options ?: "" ) ? arguments.rc.body.options : {};
        var edu = v.searchTerm( o.education ?: "", 200 );
        if ( len( edu ) && !reFind( "^[a-z,]+$", edu ) ) v.fail( "Invalid education filter.", { education: "Invalid" } );
        var options = {
            percentile: v.oneOf( o.percentile ?: "median", "p10,p25,median,p75,p90,mean", "median", "percentile" ),
            maxTrainingYears: v.numberInRange( o.maxTrainingYears ?: 99, 0, 99, 99, "maxTrainingYears" ),
            education: edu,
            sort: v.oneOf( o.sort ?: "jobs", "jobs,margin,training,growth", "jobs", "sort" ),
            limit: v.intInRange( o.limit ?: 25, 5, 100, 25, "limit" )
        };
        return ok( variables.b.reverseSearch.search( scenario, refFor( scenario ), options ) );
    }

    public struct function compare( required struct rc ) {
        var list = arguments.rc.body.scenarios ?: "";
        if ( !isArray( list ) || !arrayLen( list ) ) variables.b.validator.fail( "Send scenarios: [ ... ] (one to three).", { scenarios: "Required" } );
        if ( arrayLen( list ) > 3 ) variables.b.validator.fail( "Compare up to three futures at a time.", { scenarios: "Too many" } );
        var out = [];
        for ( var raw in list ) {
            var s = variables.b.simulator.normalize( isStruct( raw ) ? raw : {} );
            var r = variables.b.simulator.compute( s, refFor( s ) );
            arrayAppend( out, {
                scenario: s, result: r,
                summary: {
                    metro: variables.b.geography.get( s.cbsa ).name,
                    career: arrayLen( r.income.earners ) ? r.income.earners[ 1 ].title : "",
                    takeHomeMonthly: r.income.takeHomeMonthly, monthlyCosts: r.costs.monthlyTotal, monthlySurplus: r.monthlySurplus,
                    educationTotalCost: r.education.totalCost, educationBorrowed: r.education.borrowed, complete: r.complete
                }
            } );
        }
        return ok( { futures: out, differences: differences( out ) } );
    }

    public struct function saveScenario( required struct rc ) {
        var scenario = variables.b.simulator.normalize( requireScenario( arguments.rc.body ) );
        var result = variables.b.simulator.compute( scenario, refFor( scenario ) );
        var id = variables.b.scenarios.save( scenario, variables.b.validator.searchTerm( arguments.rc.body.title ?: "", 120 ), result );
        return created( { uuid: id, url: variables.b.config.baseUrl & "/s/" & id } );
    }

    public struct function getScenario( required struct rc ) {
        var saved = variables.b.scenarios.get( arguments.rc.uuid );
        saved.scenario = variables.b.simulator.normalize( saved.scenario );
        return ok( saved );
    }

    // ------------------------------------------------------------------ helpers

    private struct function requireScenario( any body ) {
        if ( isNull( arguments.body ) || !isStruct( arguments.body.scenario ?: "" ) ) variables.b.validator.fail( "Send { scenario: { ... } }.", { scenario: "Required" } );
        return arguments.body.scenario;
    }

    private struct function refFor( required struct scenario ) {
        var socs = [];
        for ( var e in arguments.scenario.earners ) if ( len( e.soc ) ) arrayAppend( socs, e.soc );
        return variables.b.reference.bundle( arguments.scenario.cbsa, socs, arguments.scenario.state, arguments.scenario.nycResident, arguments.scenario.taxYear, arguments.scenario.education.unitid ?: "" );
    }

    /** Fields that differ between futures, so the UI can highlight only the differences. */
    private array function differences( required array futures ) {
        if ( arrayLen( arguments.futures ) < 2 ) return [];
        var keys = [ "metro", "career", "takeHomeMonthly", "monthlyCosts", "monthlySurplus", "educationTotalCost", "educationBorrowed" ];
        var diff = [];
        for ( var k in keys ) {
            var first = serializeJSON( arguments.futures[ 1 ].summary[ k ] ?: "" );
            for ( var i = 2; i <= arrayLen( arguments.futures ); i++ ) {
                if ( serializeJSON( arguments.futures[ i ].summary[ k ] ?: "" ) != first ) { arrayAppend( diff, k ); break; }
            }
        }
        return diff;
    }

}
