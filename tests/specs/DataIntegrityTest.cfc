/**
 * Imported data integrity (runs against the development database after the bootstrap imports).
 */
component extends="testbox.system.BaseSpec" {

    function q( required string sql, struct params = {} ) {
        return queryExecute( arguments.sql, arguments.params, { datasource: "futurepathDB", returntype: "array" } );
    }

    function run() {
        describe( "Codes keep their exact formatting", function() {
            it( "stores SOC codes as NN-NNNN and CIP codes as dotted text with leading zeros", function() {
                expect( q( "SELECT COUNT(*) n FROM occupations WHERE soc_code NOT REGEXP '^[0-9]{2}-[0-9]{4}$'" )[ 1 ].n ).toBe( 0 );
                expect( q( "SELECT COUNT(*) n FROM cip_programs WHERE cip_code = '01.0000'" )[ 1 ].n ).toBe( 1 );
                expect( q( "SELECT COUNT(*) n FROM cip_programs WHERE cip_code = '1.0000' OR cip_code = '1'" )[ 1 ].n ).toBe( 0 );
            } );
            it( "normalizes numeric-looking CIP cells back to NN.NNNN", function() {
                var imp = new modules.imports.CipSocImporter( application.beans.importRunner, application.beans.logger );
                expect( imp.normalizeCip( "1.0101" ) ).toBe( "01.0101" );
                expect( imp.normalizeCip( "23.01" ) ).toBe( "23.0100" );
                expect( imp.normalizeCip( "23.0101" ) ).toBe( "23.0101" );
                expect( imp.normalizeCip( "abc" ) ).toBe( "" );
            } );
        } );

        describe( "CIP-SOC crosswalk is many-to-many", function() {
            it( "maps one program to several occupations and one occupation from several programs", function() {
                expect( q( "SELECT COUNT(*) n FROM cip_soc_crosswalk WHERE cip_code = '11.0701'" )[ 1 ].n ).toBeGT( 1 );
                expect( q( "SELECT COUNT(*) n FROM cip_soc_crosswalk WHERE soc_code = '15-1252'" )[ 1 ].n ).toBeGT( 1 );
            } );
            it( "returns English-related careers for a 4-digit Scorecard program (23.01)", function() {
                var res = application.beans.careerMapping.careersForCip( "23.01", "36740" );
                var socs = res.careers.map( function( c ) { return c.soc; } );
                expect( arrayFind( socs, "25-1123" ) ).toBeGT( 0 );
                expect( res.caveat ).toInclude( "not a record of where graduates work" );
            } );
        } );

        describe( "Suppressed values are never zero", function() {
            it( "stores suppressed or top-coded wages as NULL with a code", function() {
                expect( q( "SELECT COUNT(*) n FROM occupational_wages WHERE annual_median = 0 OR annual_mean = 0" )[ 1 ].n ).toBe( 0 );
                expect( q( "SELECT COUNT(*) n FROM occupational_wages WHERE suppression_code LIKE '%A_MEDIAN:*%' AND annual_median IS NOT NULL" )[ 1 ].n ).toBe( 0 );
                expect( q( "SELECT COUNT(*) n FROM occupational_wages WHERE topcoded_fields LIKE '%A_PCT90%' AND annual_p90 IS NOT NULL" )[ 1 ].n ).toBe( 0 );
                expect( q( "SELECT COUNT(*) n FROM occupational_wages WHERE topcoded_fields IS NOT NULL" )[ 1 ].n ).toBeGT( 0 );
            } );
            it( "parses published codes as missing", function() {
                var imp = new modules.imports.BaseImporter( application.beans.importRunner, application.beans.logger );
                expect( isNull( imp.num( "*" ) ) ).toBeTrue();
                expect( isNull( imp.num( "##" ) ) ).toBeTrue();
                expect( isNull( imp.num( "**" ) ) ).toBeTrue();
                expect( isNull( imp.num( "" ) ) ).toBeTrue();
                expect( imp.num( "132,350" ) ).toBe( 132350 );
            } );
            it( "keeps suppressed program earnings NULL", function() {
                expect( q( "SELECT COUNT(*) n FROM program_outcomes WHERE earnings_median = 0" )[ 1 ].n ).toBe( 0 );
                expect( q( "SELECT COUNT(*) n FROM program_outcomes WHERE suppressed_flag = 1 AND earnings_median IS NOT NULL" )[ 1 ].n ).toBe( 0 );
            } );
        } );

        describe( "Geography", function() {
            it( "resolves metros by CBSA code, not by city name", function() {
                expect( application.beans.geography.get( "36740" ).name ).toBe( "Orlando-Kissimmee-Sanford, FL" );
                expect( application.beans.geography.get( "35620" ).name ).toInclude( "New York" );
                expect( application.beans.geography.get( "47900" ).name ).toInclude( "Washington" );
                expect( function() { application.beans.geography.get( "99999" ); } ).toThrow( "NotFound" );
            } );
            it( "flags HUD areas that only cover part of a metro", function() {
                var nyc = q( "SELECT mapping_quality FROM geo_source_mappings WHERE geo_system = 'HUD_FMR_AREA' AND external_geo_code = 'METRO35620MM5600'" );
                expect( nyc[ 1 ].mapping_quality ).toBe( "partial" );
                var orl = q( "SELECT mapping_quality FROM geo_source_mappings WHERE geo_system = 'HUD_FMR_AREA' AND external_geo_code = 'METRO36740M36740'" );
                expect( orl[ 1 ].mapping_quality ).toBe( "exact" );
            } );
            it( "reports a not-published wage explicitly for a metro without an estimate", function() {
                var w = application.beans.wages.forOccupation( "45-3031", "36740" );
                expect( w.local.status ).toBe( "not_published" );
                expect( isNull( w.local.annual ) ).toBeTrue();
            } );
        } );

        describe( "Education costs are separate measures", function() {
            it( "keeps tuition, cost of attendance and net price in separate columns", function() {
                var inst = application.beans.institutions.get( 132903 );
                expect( inst.costs ).toHaveKey( "averageNetPrice" );
                expect( inst.costs ).toHaveKey( "costOfAttendance" );
                expect( inst.costs.note ).toInclude( "do not add them together" );
            } );
        } );
    }

}
