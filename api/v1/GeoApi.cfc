/**
 * GET /api/v1/geographies?q=orlando        search imported metro areas (CBSA)
 * GET /api/v1/geographies/{cbsa}           metro detail with states and housing benchmarks
 */
component extends="controllers.BaseController" {

    public struct function search( required struct rc ) {
        var q = variables.b.validator.searchTerm( arguments.rc.q ?: "" );
        return ok( variables.b.geography.search( q, limitParam( arguments.rc, 10, 30 ) ), { query: q } );
    }

    public struct function detail( required struct rc ) {
        var metro = variables.b.geography.get( arguments.rc.cbsa );
        metro.housing = variables.b.housing.forMetro( arguments.rc.cbsa );
        return ok( metro );
    }

}
