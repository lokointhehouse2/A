/**
 * Age-projection checks against frozen fixtures (no live downloads).
 */
component extends="testbox.system.BaseSpec" {

    function beforeAll() {
        variables.b = application.beans;
        variables.fixtureDir = expandPath( "/tests/fixtures/scenarios/" );
    }

    function run() {
        describe( "Age projection", function() {
            it( "marks a missing wage as more information needed, never $0 success or failure", function() {
                var p = project( "orlando_missing_wage" );
                expect( p.available ).toBeFalse();
                expect( p.overallStatus.code ).toBe( "info" );
                expect( arrayLen( p.ageSnapshots ) ).toBe( 0 );
                var keys = [];
                for ( var m in p.overallStatus.missing ) arrayAppend( keys, m.key );
                expect( arrayFind( keys, "career" ) ).toBeGT( 0 );
            } );

            it( "returns ages 20-70 and typed goal statuses for a complete family scenario", function() {
                var p = project( "orlando_teacher_family" );
                expect( p.available ).toBeTrue();
                for ( var a in [ 20, 30, 40, 50, 60, 70 ] ) expect( snap( p, a ).age ).toBe( a );
                expect( arrayLen( p.goals ) ).toBeGT( 0 );
                for ( var g in p.goals ) {
                    expect( listFind( "on_track,later,not_achievable,info", g.status ) ).toBeGT( 0 );
                    expect( isArray( g.gaps.atRequestedAge ) ).toBeTrue();
                    if ( g.status == "later" ) expect( g.projectedAge ).toBeGT( g.requestedAge );
                    if ( g.status == "not_achievable" && g.key != "education" ) expect( isNull( g.projectedAge ) ).toBeTrue();
                    for ( var gap in g.gaps.atRequestedAge ) expect( listFind( "upfront_cash,monthly_cash_flow,retirement_funding", gap.type ) ).toBeGT( 0 );
                }
                expect( p.horizon.retirementPlanningAge ).toBeGTE( 70 );
                expect( p.provenance.assumptions.surplusRule ).toInclude( "cash" );
            } );

            it( "does not invent children or a second income from age alone", function() {
                var p = project( "va_fastfood_parttime_custom" );
                expect( p.available ).toBeTrue();
                expect( snap( p, 35 ).kidsHome ).toBe( 0 );
            } );

            it( "changes cash when starting savings change", function() {
                var fx = deserializeJSON( fileRead( variables.fixtureDir & "orlando_teacher_family.json", "utf-8" ) );
                var poor = variables.b.simulator.normalize( fx.scenario );
                var rich = duplicate( poor );
                rich.plan.startingCash = 200000;
                var a = variables.b.goals.evaluate( poor, fx.reference, false );
                var b = variables.b.goals.evaluate( rich, fx.reference, false );
                expect( snap( b, 20 ).balances.cash ).toBeGT( snap( a, 20 ).balances.cash );
            } );
        } );
    }

    private struct function project( required string name ) {
        var fx = deserializeJSON( fileRead( variables.fixtureDir & arguments.name & ".json", "utf-8" ) );
        return variables.b.goals.evaluate( variables.b.simulator.normalize( fx.scenario ), fx.reference, false );
    }

    private struct function snap( required struct p, required numeric age ) {
        for ( var s in arguments.p.ageSnapshots ) if ( s.age == arguments.age ) return s;
        throw( message = "No snapshot for age #arguments.age#" );
    }

}
