/**
 * Calculation engine: frozen fixtures (shared with the browser engine) plus hand-checked tax and loan cases.
 */
component extends="testbox.system.BaseSpec" {

    function beforeAll() {
        variables.cfg = application.config;
        variables.taxes = new modules.finance.TaxEstimatorService();
        variables.loans = new modules.finance.LoanCalculatorService();
        variables.sim = new modules.simulator.LifestyleSimulatorService( variables.cfg, variables.taxes, variables.loans );
        variables.fixtureDir = expandPath( "/tests/fixtures/scenarios/" );
    }

    function run() {
        describe( "Fixtures shared with the browser engine", function() {
            it( "reproduces every fixture result exactly (CFML = JS)", function() {
                var files = directoryList( variables.fixtureDir, false, "path", "*.json" );
                expect( arrayLen( files ) ).toBeGT( 0 );
                for ( var f in files ) {
                    var fx = deserializeJSON( fileRead( f, "utf-8" ) );
                    var r = variables.sim.compute( variables.sim.normalize( fx.scenario ), fx.reference );
                    var x = fx.expected;
                    expect( r.complete ).toBe( x.complete, fx.name & " complete" );
                    assertNear( r.income.grossAnnual, x.grossAnnual, fx.name & " gross" );
                    assertNear( r.income.taxes.total, x.taxesTotal, fx.name & " taxes" );
                    assertNear( r.income.takeHomeMonthly, x.takeHomeMonthly, fx.name & " take-home" );
                    assertNear( r.costs.monthlyTotal, x.monthlyCosts, fx.name & " costs" );
                    assertNear( r.monthlySurplus, x.monthlySurplus, fx.name & " surplus" );
                    for ( var l in r.costs.lines ) {
                        expect( structKeyExists( x.lines, l.key ) ).toBeTrue( fx.name & " unexpected line " & l.key );
                        if ( isNull( l.monthly ) ) expect( isNull( x.lines[ l.key ] ) ).toBeTrue( fx.name & " " & l.key & " should be null" );
                        else assertNear( l.monthly, x.lines[ l.key ], fx.name & " " & l.key );
                    }
                    for ( var i = 1; i <= arrayLen( r.timeline ); i++ ) assertNear( r.timeline[ i ].cumulativeSurplus, x.timeline[ i ].cumulativeSurplus, fx.name & " timeline", 1 );
                    var req = variables.sim.requiredGross( variables.sim.normalize( fx.scenario ), fx.reference );
                    if ( isNull( x.requiredEarner1Gross ) ) expect( isNull( req ) ).toBeTrue();
                    else assertNear( req.earner1Gross, x.requiredEarner1Gross, fx.name & " required gross", 2 );
                }
            } );

            it( "never turns an unpublished wage into $0 income", function() {
                var fx = deserializeJSON( fileRead( variables.fixtureDir & "orlando_missing_wage.json", "utf-8" ) );
                var r = variables.sim.compute( variables.sim.normalize( fx.scenario ), fx.reference );
                expect( r.complete ).toBeFalse();
                expect( isNull( r.income.earners[ 1 ].annualWage ) ).toBeTrue();
                expect( r.income.earners[ 1 ].status ).toBe( "missing" );
                expect( arrayLen( r.warnings ) ).toBeGT( 0 );
            } );

            it( "reports the data vintage and assumptions used", function() {
                var fx = deserializeJSON( fileRead( variables.fixtureDir & "orlando_teacher_family.json", "utf-8" ) );
                var r = variables.sim.compute( variables.sim.normalize( fx.scenario ), fx.reference );
                expect( r.dataYears.wages ).toBe( fx.reference.dataYears.wages );
                expect( r.assumptionsUsed ).toHaveKey( "mortgageRatePct" );
                expect( arrayLen( r.citations ) ).toBeGT( 2 );
            } );
        } );

        describe( "Taxes", function() {
            it( "applies 2026 federal brackets progressively", function() {
                var b = [ { lower: 0, upper: 12400, rate: 0.10 }, { lower: 12400, upper: 50400, rate: 0.12 }, { lower: 50400, upper: javacast( "null", "" ), rate: 0.22 } ];
                assertNear( variables.taxes.bracketTax( 43900, b ), 5020, "single 60k" );
                assertNear( variables.taxes.bracketTax( 60000, b ), 1240 + 4560 + 0.22 * 9600, "third bracket" );
                expect( variables.taxes.bracketTax( 0, b ) ).toBe( 0 );
            } );

            it( "does not double-count two earners filing jointly", function() {
                var fed = variables.taxes.pack( "US", 2026 );
                var joint = variables.taxes.estimate( { wages: [ 50000, 50000 ], pretax: [ 0, 0 ], filingStatus: "mfj", children: 0, stateCode: "FL", packs: { federal: fed, state: variables.taxes.pack( "FL", 2026 ) } } );
                // AGI 100,000 - 32,200 = 67,800 taxable: 2,480 + 12% x 43,000 = 7,640; FICA 7.65% x 100,000 = 7,650.
                assertNear( joint.federalIncomeTax, 7640, "joint federal" );
                assertNear( joint.socialSecurity + joint.medicare, 7650, "FICA" );
                assertNear( joint.total, 15290, "joint total" );
                var separate = variables.taxes.estimate( { wages: [ 50000, 50000 ], pretax: [ 0, 0 ], filingStatus: "single", children: 0, stateCode: "FL", packs: { federal: fed, state: variables.taxes.pack( "FL", 2026 ) } } );
                expect( separate.filing ).toBe( "separate" );
                // Each: 50,000 - 16,100 = 33,900 -> 1,240 + 12% x 21,500 = 3,820; two returns = 7,640.
                assertNear( separate.federalIncomeTax, 7640, "separate federal" );
            } );

            it( "caps Social Security at the 2026 wage base per earner", function() {
                var fed = variables.taxes.pack( "US", 2026 );
                expect( fed.socialSecurity.wageBase ).toBe( 184500 );
                var t = variables.taxes.estimate( { wages: [ 300000 ], pretax: [ 0 ], filingStatus: "single", children: 0, stateCode: "", packs: { federal: fed } } );
                assertNear( t.socialSecurity, 184500 * 0.062, "SS cap" );
                assertNear( t.additionalMedicare, 100000 * 0.009, "additional Medicare" );
            } );

            it( "warns instead of guessing when a state is not modeled", function() {
                var fed = variables.taxes.pack( "US", 2026 );
                var t = variables.taxes.estimate( { wages: [ 60000 ], pretax: [ 0 ], filingStatus: "single", children: 0, stateCode: "NJ", packs: { federal: fed } } );
                expect( t.stateModeled ).toBeFalse();
                expect( t.stateIncomeTax ).toBe( 0 );
                expect( arrayToList( t.warnings ) ).toInclude( "not modeled" );
            } );

            it( "uses the latest published year when the requested year is missing (DC)", function() {
                var dc = variables.taxes.pack( "DC", 2026 );
                expect( dc.taxYear ).toBe( 2025 );
                expect( dc.requestedYear ).toBe( 2026 );
            } );
        } );

        describe( "Loans", function() {
            it( "handles zero interest, positive interest and invalid terms", function() {
                assertNear( variables.loans.amortize( 12000, 0, 120 ).payment, 100, "zero rate" );
                assertNear( variables.loans.amortize( 10000, 6, 120 ).payment, 111.0205, "6% 10 yr", 0.001 );
                expect( variables.loans.amortize( 0, 6, 120 ).payment ).toBe( 0 );
                expect( function() { variables.loans.amortize( 1000, 5, 0 ); } ).toThrow( "Validation" );
                expect( function() { variables.loans.amortize( 1000, 5, 12.5 ); } ).toThrow( "Validation" );
            } );
        } );

        describe( "Housing rules", function() {
            it( "never charges rent and a mortgage together", function() {
                var fx = deserializeJSON( fileRead( variables.fixtureDir & "orlando_teacher_family.json", "utf-8" ) );
                var s = variables.sim.normalize( fx.scenario );
                arrayAppend( s.tiles, { type: "apartment", bedrooms: 2, benchmark: "acs", customRent: javacast( "null", "" ) } );
                var r = variables.sim.compute( s, fx.reference );
                var keys = r.costs.lines.map( function( l ) { return l.key; } );
                expect( arrayFind( keys, "mortgage" ) ).toBeGT( 0 );
                expect( arrayFind( keys, "rent" ) ).toBe( 0 );
                expect( arrayToList( r.warnings, "|" ) ).toInclude( "Only the house is counted" );
            } );
        } );

        describe( "Scenario validation", function() {
            it( "rejects malformed input with a Validation error", function() {
                expect( function() { variables.sim.normalize( { cbsa: "abc" } ); } ).toThrow( "Validation" );
                expect( function() { variables.sim.normalize( { cbsa: "36740", earners: [ { soc: "151252" } ] } ); } ).toThrow( "Validation" );
                expect( function() { variables.sim.normalize( { cbsa: "36740", assumptions: { mortgageRatePct: 99 } } ); } ).toThrow( "Validation" );
            } );
            it( "ignores unknown tiles and duplicate tiles", function() {
                var s = variables.sim.normalize( { cbsa: "36740", tiles: [ { type: "yacht" }, { type: "car" }, { type: "car" } ] } );
                expect( arrayLen( s.tiles ) ).toBe( 1 );
            } );
        } );
    }

    private void function assertNear( required numeric actual, required numeric expected, string label = "", numeric tolerance = 0.02 ) {
        expect( abs( arguments.actual - arguments.expected ) <= arguments.tolerance ).toBeTrue( "#arguments.label#: #arguments.actual# vs #arguments.expected#" );
    }

}
