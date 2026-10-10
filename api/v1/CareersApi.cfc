/**
 * GET /api/v1/occupations?q=carpenter&cbsa=36740      search SOC occupations (with local availability)
 * GET /api/v1/occupations/{soc}                       occupation profile
 * GET /api/v1/occupations/{soc}/wages?cbsa=&year=     local + national wages with provenance
 * GET /api/v1/occupations/{soc}/pathways              training / education routes
 * GET /api/v1/occupations/{soc}/programs              programs (CIP) mapped to this occupation
 */
component extends="controllers.BaseController" {

    public struct function search( required struct rc ) {
        var v = variables.b.validator;
        var q = v.searchTerm( arguments.rc.q ?: "" );
        var cbsa = v.cbsa( arguments.rc.cbsa ?: "", false );
        return ok( variables.b.occupations.search( q, limitParam( arguments.rc, 12, 50 ), cbsa, v.searchTerm( arguments.rc.education ?: "", 80 ) ), { query: q, cbsa: cbsa } );
    }

    public struct function detail( required struct rc ) {
        var o = variables.b.occupations.get( arguments.rc.soc );
        o.pathways = variables.b.occupations.pathways( arguments.rc.soc );
        return ok( o );
    }

    public struct function wages( required struct rc ) {
        var v = variables.b.validator;
        var cbsa = v.cbsa( arguments.rc.cbsa ?: "", false );
        var year = v.intInRange( arguments.rc.year ?: "", 1997, 2100, 0, "year" );
        var occ = variables.b.occupations.get( arguments.rc.soc );
        var w = variables.b.wages.forOccupation( arguments.rc.soc, cbsa, year );
        w.title = occ.title;
        if ( len( cbsa ) ) w.metro = variables.b.geography.get( cbsa );
        return ok( w );
    }

    public struct function pathways( required struct rc ) {
        variables.b.occupations.get( arguments.rc.soc );
        return ok( {
            soc: arguments.rc.soc,
            pathways: variables.b.occupations.pathways( arguments.rc.soc ),
            caveat: "Based on the BLS typical entry-level education for this occupation. Requirements differ by employer and state; some jobs need a license."
        } );
    }

    public struct function programs( required struct rc ) {
        variables.b.occupations.get( arguments.rc.soc );
        return ok( { soc: arguments.rc.soc, programs: variables.b.careerMapping.programsForSoc( arguments.rc.soc ),
            caveat: "Programs that can prepare people for this occupation (NCES CIP-SOC crosswalk). Other routes exist." } );
    }

}
