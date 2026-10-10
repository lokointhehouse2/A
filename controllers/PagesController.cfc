/**
 * Server-rendered pages. Interactive pieces (builder, search) progressively enhance this HTML with assets/js.
 */
component extends="BaseController" {

    variables.homeOccupations = [ "47-2031", "29-1141", "15-1252", "35-3023", "25-2031" ];

    public struct function home( required struct rc ) {
        var cmp = { occupations: [], metros: [] };
        try {
            cmp.metros = variables.b.geography.featured( variables.b.config.featuredMetros );
            var rents = {};
            for ( var m in cmp.metros ) {
                var h = variables.b.housing.forMetro( m.cbsa );
                rents[ m.cbsa ] = { value: h.acs.rents[ "1" ] ?: javacast( "null", "" ), period: h.acs.period };
            }
            for ( var soc in variables.homeOccupations ) {
                try {
                    var occ = variables.b.occupations.get( soc );
                    arrayAppend( cmp.occupations, { soc: soc, title: occ.title, wages: variables.b.wages.compareMetros( soc, variables.b.config.featuredMetros ) } );
                } catch ( NotFound e ) {}
            }
            cmp.rents = rents;
            cmp.year = variables.b.wages.latestYear( "metro" );
        } catch ( any e ) {
            variables.b.logger.error( "Home comparison failed", e );
        }
        return view( "pages/home", { comparison: cmp, title: "Dream big. See what it takes." } );
    }

    public struct function builder( required struct rc ) {
        var start = variables.b.validator.oneOf( arguments.rc.start ?: "", "life,job,school", "life", "start" );
        return view( "pages/builder", {
            title: "Future Builder",
            start: start,
            featured: variables.b.geography.featured( variables.b.config.featuredMetros ),
            sharedId: reFind( "^[0-9a-f\-]{36}$", arguments.rc.s ?: "" ) ? arguments.rc.s : "",
            assumptions: variables.b.simulator.assumptionDefaults()
        } );
    }

    public struct function careers( required struct rc ) {
        var v = variables.b.validator;
        var q = v.searchTerm( arguments.rc.q ?: "" );
        var cbsa = v.cbsa( arguments.rc.cbsa ?: "", false );
        var results = len( q ) ? variables.b.occupations.search( q, 30, cbsa ) : [];
        return view( "pages/careers", { title: "Explore careers", q: q, cbsa: cbsa, results: results,
            metro: len( cbsa ) ? variables.b.geography.get( cbsa ) : javacast( "null", "" ),
            featured: variables.b.geography.featured( variables.b.config.featuredMetros ) } );
    }

    public struct function career( required struct rc ) {
        var v = variables.b.validator;
        var cbsa = v.cbsa( arguments.rc.cbsa ?: variables.b.config.featuredMetros[ 1 ], false );
        var occ = variables.b.occupations.get( arguments.rc.soc );
        return view( "pages/career", {
            title: occ.title, occupation: occ,
            pathways: variables.b.occupations.pathways( arguments.rc.soc ),
            wages: variables.b.wages.forOccupation( arguments.rc.soc, cbsa ),
            metro: len( cbsa ) ? variables.b.geography.get( cbsa ) : javacast( "null", "" ),
            programs: variables.b.careerMapping.programsForSoc( arguments.rc.soc ),
            featured: variables.b.geography.featured( variables.b.config.featuredMetros ),
            comparison: variables.b.wages.compareMetros( arguments.rc.soc, variables.b.config.featuredMetros )
        } );
    }

    public struct function colleges( required struct rc ) {
        var v = variables.b.validator;
        var q = v.searchTerm( arguments.rc.q ?: "" );
        var st = v.stateCode( arguments.rc.state ?: "" );
        return view( "pages/colleges", { title: "Explore colleges", q: q, state: st,
            results: len( q ) || len( st ) ? variables.b.institutions.search( q, st, 40 ) : variables.b.institutions.search( "", "", 40 ) } );
    }

    public struct function college( required struct rc ) {
        var inst = variables.b.institutions.get( arguments.rc.unitid );
        return view( "pages/college", { title: inst.name, institution: inst, programs: variables.b.programs.forInstitution( arguments.rc.unitid ) } );
    }

    public struct function about( required struct rc ) {
        return view( "pages/about", { title: "How FuturePath works" } );
    }

    public struct function sources( required struct rc ) {
        var sources = queryExecute( "SELECT source_key, name, agency, source_url, license_notes, refresh_cadence FROM data_sources ORDER BY name", {}, { datasource: "futurepathDB", returntype: "array" } );
        return view( "pages/sources", { title: "Data sources and assumptions", sources: sources, datasets: variables.b.importRunner.status(), assumptions: variables.b.simulator.assumptionDefaults() } );
    }

    public struct function privacy( required struct rc ) {
        return view( "pages/privacy", { title: "Privacy" } );
    }

    public struct function sharedScenario( required struct rc ) {
        variables.b.scenarios.get( arguments.rc.uuid );
        return redirect( "/builder?s=" & encodeForURL( lCase( arguments.rc.uuid ) ) );
    }

}
