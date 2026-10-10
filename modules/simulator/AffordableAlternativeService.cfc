/**
 * "What your current path could support": the smallest set of changes, tried in a fixed order
 * (travel, vehicle cost, housing option, goal timing), that funds every goal on time without an unfunded gap.
 * Never removes children and never adds a second income. Browser mirror: assets/js/projection.js.
 */
component {

    variables.EPS = 0.005;
    variables.tripKinds = [ "local", "usa", "cruise", "world" ];

    public AffordableAlternativeService function init( required any timeline, required any goals ) {
        variables.timeline = arguments.timeline;
        variables.goals = arguments.goals;
        variables.presets = arguments.timeline.presets();
        return this;
    }

    /** Returns null when the requested plan already works. */
    public any function build( required struct s, required struct ref ) {
        var ref = arguments.ref;
        var cand = duplicate( arguments.s );
        cand.plan = variables.timeline.planOf( cand );
        var changes = [];
        if ( quickFeasible( cand, ref ).ok ) return javacast( "null", "" );

        // 1. discretionary travel
        var tr = variables.timeline.tileOf( cand, "travel" );
        if ( !isNull( tr ) ) {
            var levels = [];
            var before = travelSummary( tr );
            if ( !isNull( tr.annual ) ) {
                var halfAnnual = round( tr.annual / 2 );
                arrayAppend( levels, { kind: "travel_annual", value: halfAnnual, requested: before, alternative: travelSummary( { annual: halfAnnual } ), why: "Half the travel budget" } );
            } else if ( isStruct( tr.trips ?: "" ) ) {
                var half = {};
                var same = true;
                for ( var k in variables.tripKinds ) {
                    half[ k ] = int( ( tr.trips[ k ] ?: 0 ) / 2 );
                    if ( half[ k ] != ( tr.trips[ k ] ?: 0 ) ) same = false;
                }
                if ( !same ) arrayAppend( levels, { kind: "travel_trips", value: half, requested: before, alternative: travelSummary( { trips: half } ), why: "Fewer trips each year" } );
                var localOnly = {};
                for ( var k in variables.tripKinds ) {
                    var lc = min( 2, tr.trips.local ?: 0 );
                    localOnly[ k ] = k == "local" ? ( lc == 0 ? 1 : lc ) : 0;
                }
                arrayAppend( levels, { kind: "travel_trips", value: localOnly, requested: before, alternative: travelSummary( { trips: localOnly } ), why: "Local getaways instead of bigger trips" } );
            }
            arrayAppend( levels, { kind: "travel_remove", requested: before, alternative: "No travel budget for now", why: "Travel is the first optional cost to trim" } );
            var res = tryLevels( cand, changes, "travel", levels, ref );
            cand = res.cand;
            if ( res.ok ) return finish( cand, changes, ref );
        }
        // 2. vehicle cost
        var carLevels = [];
        for ( var ct in [ "car", "second_car" ] ) {
            var c = variables.timeline.tileOf( cand, ct );
            if ( !isNull( c ) && isNull( c.price ) && len( c.tier ?: "" ) && c.tier != "compact" && structKeyExists( variables.presets.car ?: {}, "compact" ) ) {
                arrayAppend( carLevels, { ct: ct, from: c.tier } );
            }
        }
        if ( arrayLen( carLevels ) ) {
            var parts = [];
            for ( var cl in carLevels ) arrayAppend( parts, levelLabel( "car", cl.from ) & ( cl.ct == "second_car" ? " second car" : " car" ) );
            var res2 = tryLevels( cand, changes, "vehicle", [ { kind: "cars_compact", value: carLevels, requested: arrayToList( parts, " + " ), alternative: "Compact " & ( arrayLen( carLevels ) > 1 ? "cars" : "car" ), why: "Lower car payment, insurance and gas" } ], ref );
            cand = res2.cand;
            if ( res2.ok ) return finish( cand, changes, ref );
        }
        // 3. housing option (same family size: only the size/finish level of the home changes)
        var h = variables.timeline.tileOf( cand, "house" );
        if ( !isNull( h ) && isNull( h.price ) && structKeyExists( variables.presets, "house" ) ) {
            var tiers = houseTiers();
            var idx = arrayFind( tiers, h.tier ?: "" );
            var hl = [];
            for ( var t = idx - 1; t >= 1; t-- ) {
                arrayAppend( hl, { kind: "house_tier", value: tiers[ t ], requested: levelLabel( "house", h.tier ) & " home", alternative: levelLabel( "house", tiers[ t ] ) & " home", why: "Smaller deposit and monthly cost" } );
            }
            if ( arrayLen( hl ) ) {
                var res3 = tryLevels( cand, changes, "housing", hl, ref );
                cand = res3.cand;
                if ( res3.ok ) return finish( cand, changes, ref );
            }
        }
        // 4. goal timing: move each goal to its calculated age
        var ev = variables.goals.evaluate( cand, ref, false );
        if ( !ev.available ) return { available: false, feasible: false, reason: "Some costs for the alternative are not available.", changes: changes };
        var timing = [];
        var allDated = true;
        for ( var goal in ev.goals ) {
            if ( goal.key == "education" ) continue;
            if ( isNull( goal.projectedAge ) ) { allDated = false; continue; }
            if ( goal.projectedAge > goal.requestedAge ) arrayAppend( timing, goal );
        }
        if ( allDated && arrayLen( timing ) ) {
            var nextCand = duplicate( cand );
            for ( var goal in timing ) nextCand.plan.goals[ goal.key ] = goal.projectedAge;
            var q = quickFeasible( nextCand, ref );
            cand = nextCand;
            for ( var goal in timing ) {
                var gap = arrayLen( goal.gaps.atRequestedAge ) ? goal.gaps.atRequestedAge[ 1 ] : {};
                var gapType = gap.type ?: "";
                var why = ( gapType == "retirement_funding" ? "Retirement funding gap" : ( gapType == "monthly_cash_flow" ? "Monthly cost gap" : "Upfront cash gap" ) );
                if ( ( gap.amount ?: 0 ) != 0 ) why &= " of about " & usd( gap.amount ) & ( gapType == "monthly_cash_flow" ? "/month" : "" );
                why &= "; #goal.yearsDelayed# more year" & ( goal.yearsDelayed == 1 ? "" : "s" );
                arrayAppend( changes, { area: "timing", goal: goal.key, requested: "#goal.label# at #goal.requestedAge#", alternative: "#goal.label# at #goal.projectedAge#", why: why } );
            }
            if ( q.ok ) return finish( cand, changes, ref );
        }
        var last = quickFeasible( cand, ref );
        var reason = "No combination of the allowed changes funds every goal within this timeline.";
        if ( !isNull( last.sim ) && last.sim.maxEssentialGap.amount > variables.EPS ) {
            reason = "Everyday expenses still exceed estimated income by " & usd( last.sim.maxEssentialGap.amount ) & "/month at age #last.sim.maxEssentialGap.age#.";
        } else if ( !isNull( last.sim ) && last.sim.unfunded.training > variables.EPS ) {
            reason = "Training-period costs still need about " & usd( last.sim.unfunded.training ) & " of support.";
        }
        return { available: true, feasible: false, reason: reason, essentialGap: isNull( last.sim ) ? javacast( "null", "" ) : last.sim.maxEssentialGap, changes: changes };
    }

    // ------------------------------------------------------------------ helpers

    private struct function quickFeasible( required struct s, required struct ref ) {
        var ctx = variables.timeline.context( arguments.s, arguments.ref );
        if ( !ctx.available ) return { ok: false, sim: javacast( "null", "" ) };
        var sim = variables.timeline.simulate( ctx, { retireAge: ctx.retireAge, goals: variables.timeline.goalAges( ctx ), record: false } );
        var ok = sim.unfunded.training + sim.unfunded.working + sim.unfunded.retired <= variables.EPS;
        for ( var k in sim.goals ) {
            var gr = sim.goals[ k ];
            if ( isNull( gr.achieved ) || gr.achieved > gr.month ) ok = false;
        }
        if ( !isNull( sim.savingsGoal ) && ( isNull( sim.savingsGoal.achieved ) || sim.savingsGoal.achieved > sim.savingsGoal.month ) ) ok = false;
        return { ok: ok, sim: sim };
    }

    /** Tries each level in order; keeps the first that works, or the last (strongest) level. */
    private struct function tryLevels( required struct cand, required array changes, required string area, required array levels, required struct ref ) {
        var n = arrayLen( arguments.levels );
        for ( var i = 1; i <= n; i++ ) {
            var lv = arguments.levels[ i ];
            var nextCand = duplicate( arguments.cand );
            applyLevel( nextCand, lv );
            var q = quickFeasible( nextCand, arguments.ref );
            if ( q.ok || i == n ) {
                arrayAppend( arguments.changes, { area: arguments.area, requested: lv.requested, alternative: lv.alternative, why: lv.why } );
                return { ok: q.ok, cand: nextCand };
            }
        }
        return { ok: false, cand: arguments.cand };
    }

    private void function applyLevel( required struct s, required struct lv ) {
        var s = arguments.s;
        switch ( arguments.lv.kind ) {
            case "travel_annual":
                var ta = variables.timeline.tileOf( s, "travel" );
                ta.annual = arguments.lv.value;
                break;
            case "travel_trips":
                var tt = variables.timeline.tileOf( s, "travel" );
                tt.trips = duplicate( arguments.lv.value );
                break;
            case "travel_remove":
                var kept = [];
                for ( var t in s.tiles ) if ( t.type != "travel" ) arrayAppend( kept, t );
                s.tiles = kept;
                break;
            case "cars_compact":
                for ( var c in arguments.lv.value ) {
                    var ctile = variables.timeline.tileOf( s, c.ct );
                    ctile.tier = "compact";
                }
                break;
            case "house_tier":
                var hh = variables.timeline.tileOf( s, "house" );
                hh.tier = arguments.lv.value;
                hh.bedrooms = max( variables.presets.house[ arguments.lv.value ].bedrooms, 1 );
                break;
        }
    }

    private struct function finish( required struct cand, required array changes, required struct ref ) {
        var ev = variables.goals.evaluate( arguments.cand, arguments.ref, false );
        return { available: true, feasible: true, reason: "", changes: arguments.changes, scenario: arguments.cand, overallStatus: ev.overallStatus, goals: ev.goals, ageSnapshots: ev.ageSnapshots };
    }

    private string function travelSummary( required struct t ) {
        if ( !isNull( arguments.t.annual ) ) return usd( arguments.t.annual ) & " a year";
        if ( !isStruct( arguments.t.trips ?: "" ) ) return "Default travel budget";
        var parts = [];
        for ( var k in variables.tripKinds ) {
            if ( ( arguments.t.trips[ k ] ?: 0 ) > 0 ) {
                var p = variables.presets.travel[ k ] ?: {};
                arrayAppend( parts, arguments.t.trips[ k ] & " x " & lCase( p.label ?: k ) );
            }
        }
        return arrayLen( parts ) ? arrayToList( parts, ", " ) & " a year" : "No trips";
    }

    private string function usd( required numeric n ) {
        return "$" & numberFormat( round( arguments.n ), "," );
    }

    private string function levelLabel( required string group, required string key ) {
        var g = variables.presets[ arguments.group ] ?: {};
        return structKeyExists( g, arguments.key ) ? g[ arguments.key ].label : arguments.key;
    }

    /** House tiers in assumptions.json order (smallest first). */
    private array function houseTiers() {
        var order = [ "cozy", "standard", "luxurious", "mansion" ];
        var out = [];
        for ( var k in order ) if ( structKeyExists( variables.presets.house, k ) ) arrayAppend( out, k );
        return out;
    }

}
