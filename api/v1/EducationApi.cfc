/**
 * GET /api/v1/institutions?q=&state=FL&cip=23.01   search colleges
 * GET /api/v1/institutions/{unitid}               costs and completion
 * GET /api/v1/institutions/{unitid}/programs      programs with observed field-of-study outcomes
 * GET /api/v1/programs?q=english                  fields of study (CIP)
 * GET /api/v1/programs/{cip}/careers?cbsa=        possible occupations from the CIP-SOC crosswalk
 * GET /api/v1/pathways                            generic education pathways
 */
component extends="controllers.BaseController" {

    public struct function searchInstitutions( required struct rc ) {
        var v = variables.b.validator;
        var cip = v.searchTerm( arguments.rc.cip ?: "", 7 );
        if ( len( cip ) && !reFind( "^[0-9]{2}(\.[0-9]{2}([0-9]{2})?)?$", cip ) ) v.fail( "CIP codes look like 23.01.", { cip: "Invalid CIP code" } );
        return ok( variables.b.institutions.search( v.searchTerm( arguments.rc.q ?: "" ), v.stateCode( arguments.rc.state ?: "" ), limitParam( arguments.rc, 12, 50 ), cip ) );
    }

    public struct function institution( required struct rc ) {
        return ok( variables.b.institutions.get( arguments.rc.unitid ) );
    }

    public struct function institutionPrograms( required struct rc ) {
        var inst = variables.b.institutions.get( arguments.rc.unitid );
        return ok( {
            unitid: inst.unitid, name: inst.name,
            programs: variables.b.programs.forInstitution( arguments.rc.unitid ),
            caveat: "Observed earnings are medians for former students of this field at this school who received federal aid, measured 1, 4 or 5 years after completing. They are a different measure from BLS occupational wages and are often suppressed for small groups.",
            source: { name: "College Scorecard field-of-study data", url: "https://collegescorecard.ed.gov/data/" }
        } );
    }

    public struct function searchPrograms( required struct rc ) {
        return ok( variables.b.programs.search( variables.b.validator.searchTerm( arguments.rc.q ?: "" ), limitParam( arguments.rc, 15, 50 ) ) );
    }

    public struct function programCareers( required struct rc ) {
        var cbsa = variables.b.validator.cbsa( arguments.rc.cbsa ?: "", false );
        return ok( variables.b.careerMapping.careersForCip( arguments.rc.cip, cbsa ) );
    }

    public struct function pathways( required struct rc ) {
        return ok( variables.b.occupations.allPathways() );
    }

}
