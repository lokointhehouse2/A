/**
 * Goal dates and statuses on top of TimelineProjectionService (browser mirror: assets/js/projection.js).
 * A goal is "on track" when funded at the requested age, "later" when funded at a later age within the timeline,
 * and "not achievable within this timeline under the current assumptions" otherwise. Unavailable data returns an
 * informational status with the missing inputs instead of a verdict.
 */
component {

    variables.VERSION = "projection-2026.1";
    variables.EPS = 0.005;
    variables.STATUS_TEXT = { on_track: "On track", later: "Later than planned", not_achievable: "Not achievable within this timeline under the current assumptions", info: "More information needed" };
    variables.OMISSIONS = [
        "Social Security, pensions and other retirement income are counted only when you enter them.",
        "Taxes on retirement-account withdrawals are not modeled.",
        "Retirement-account money is treated as available only from your retirement age.",
        "A car payment continues for life as a replacement cycle (a new car when the loan ends).",
        "Home values and rents stay at today's level (no appreciation).",
        "Tax rules are held at the current year; projected mode assumes brackets keep pace with inflation.",
        "Interest that builds up on student loans while in school is not included.",
        "Living costs while in training use one shared-housing assumption, not your lifestyle cards."
    ];

    public GoalFeasibilityService function init( required any timeline ) {
        variables.timeline = arguments.timeline;
        return this;
    }

    public void function setAlternative( required any alternative ) {
        variables.alternative = arguments.alternative;
    }

    public string function version() { return variables.VERSION; }

    public struct function evaluate( required struct s, required struct ref, boolean withAlternative = true ) {
        var s = arguments.s;
        var ctx = variables.timeline.context( s, arguments.ref );
        var horizon = {
            startAge: ctx.startAge, endAge: ctx.endAge, retirementPlanningAge: ctx.planningAge, careerStartAge: ctx.careerStartMonth / 12,
            dollarBasis: "today's dollars", mode: ( s.timeline.mode ?: "today" ) == "projected" ? "projected" : "today"
        };
        var provenance = {
            dataYears: ctx.base.dataYears, citations: ctx.base.citations,
            assumptions: {
                investmentReturnPct: ctx.A.investmentReturnPct, emergencyReserveMonths: ctx.A.emergencyReserveMonths, trainingLivingMonthly: ctx.A.trainingLivingMonthly,
                wageGrowthPct: horizon.mode == "projected" ? ctx.A.wageGrowthPct : 0, retirementIncomeMonthly: ctx.plan.retirementIncomeMonthly,
                surplusRule: "Money left over after planned savings goes to cash; shortfalls use cash first (and savings, then retirement money once retired)."
            },
            omissions: variables.OMISSIONS, unavailable: ctx.missing
        };
        if ( !ctx.available ) {
            var noCareer = false;
            for ( var miss in ctx.missing ) if ( miss.key == "career" || miss.key == "housing" ) noCareer = true;
            return {
                projectionVersion: variables.VERSION, available: false, horizon: horizon, ageSnapshots: [], goals: [], events: [],
                overallStatus: { code: "info", message: noCareer ? "Choose a career and housing to see your future." : "Some data is missing, so this future is incomplete.", missing: ctx.missing },
                alternative: javacast( "null", "" ), provenance: provenance
            };
        }
        var main = variables.timeline.simulate( ctx, { retireAge: ctx.retireAge, goals: variables.timeline.goalAges( ctx ), record: true } );
        var goals = buildGoals( ctx, main );
        var ov = overall( goals, main, ctx.endAge );
        var events = [];
        for ( var e in main.events ) if ( e.month < ctx.endAge * 12 + 12 ) arrayAppend( events, { age: int( e.month / 12 ), kind: e.kind, label: e.label } );
        var result = {
            projectionVersion: variables.VERSION, available: true, horizon: horizon, ageSnapshots: main.snapshots, goals: goals,
            events: events, unfunded: main.unfunded, overallStatus: ov, alternative: javacast( "null", "" ), provenance: provenance
        };
        if ( arguments.withAlternative && ov.code != "achievable" && structKeyExists( variables, "alternative" ) ) {
            result.alternative = variables.alternative.build( s, arguments.ref );
        }
        return result;
    }

    // ------------------------------------------------------------------ helpers

    private array function buildGoals( required struct ctx, required struct main ) {
        var ctx = arguments.ctx;
        var main = arguments.main;
        var g = ctx.plan.goals;
        var out = [];
        var careerAge = int( ctx.careerStartMonth / 12 );
        if ( ctx.degree ) {
            var finish = ceiling( ctx.careerStartMonth / 12 );
            var trainingGap = main.unfunded.training;
            var ok = trainingGap <= variables.EPS;
            arrayAppend( out, {
                key: "education", label: "Finish school or training", requestedAge: finish, projectedAge: finish, status: ok ? "on_track" : "not_achievable",
                statusText: ok ? variables.STATUS_TEXT.on_track : "Training costs not fully funded", yearsDelayed: 0,
                required: { monthlyCost: ctx.A.trainingLivingMonthly + ctx.tuitionCashMonthly },
                available: { monthlyIncome: ctx.plan.studyIncomeMonthly + ctx.plan.trainingSupportMonthly, cash: ctx.plan.startingCash },
                gaps: { atRequestedAge: ok ? [] : [ { type: "upfront_cash", amount: trainingGap } ], atEndAge: [] },
                reason: ok ? "Living costs while training are covered." : "Living costs while training need about #usd( trainingGap )# more in total. Add family support, work while studying or starting savings.",
                conditional: false
            } );
        }
        if ( structKeyExists( main.goals, "house" ) ) arrayAppend( out, purchaseGoal( main, "house", "Buy a home", clampAge( ctx, g.house ?: javacast( "null", "" ), 30 ) ) );
        if ( structKeyExists( main.goals, "car" ) ) arrayAppend( out, purchaseGoal( main, "car", isNull( ctx.car2 ) ? "Buy a car" : "Buy your cars", clampAge( ctx, g.car ?: javacast( "null", "" ), careerAge ) ) );
        if ( structKeyExists( main.goals, "travel" ) ) {
            var tg = purchaseGoal( main, "travel", "Travel budget", clampAge( ctx, g.travel ?: javacast( "null", "" ), careerAge ) );
            if ( tg.status == "on_track" ) tg.reason = "Your trips fit the monthly budget.";
            arrayAppend( out, tg );
        }
        if ( !isNull( main.savingsGoal ) ) {
            var sg = main.savingsGoal;
            var req = clampAge( ctx, g.savings ?: javacast( "null", "" ), 30 );
            var proj = !isNull( sg.achieved ) && sg.achieved <= ctx.endAge * 12 ? int( sg.achieved / 12 ) : javacast( "null", "" );
            var sst = statusOf( req, proj ?: javacast( "null", "" ) );
            var bal = isNull( sg.atRequested ) ? 0 : sg.atRequested.balance;
            arrayAppend( out, {
                key: "savings", label: "Save #usd( sg.target )#", requestedAge: req, projectedAge: proj ?: javacast( "null", "" ),
                status: sst, statusText: variables.STATUS_TEXT[ sst ],
                yearsDelayed: !isNull( proj ) && proj > req ? proj - req : 0,
                required: { target: sg.target }, available: { balanceAtRequestedAge: bal },
                gaps: { atRequestedAge: sst == "on_track" ? [] : [ { type: "upfront_cash", amount: max( 0, sg.target - bal ) } ], atEndAge: [] },
                reason: sst == "on_track" ? "Your monthly savings reach the target in time." : "Your savings account is short of the target at that age.",
                conditional: !isNull( proj ) && !isNull( main.firstUnfundedMonth ) && sg.achieved > main.firstUnfundedMonth
            } );
        }
        var R = ctx.retireAge;
        var gapAtR = main.unfunded.retired;
        var projected = gapAtR <= variables.EPS ? R : javacast( "null", "" );
        var gapAtEnd = gapAtR;
        if ( isNull( projected ) ) {
            for ( var a = R + 1; a <= ctx.endAge; a++ ) {
                var run = variables.timeline.simulate( ctx, { retireAge: a, goals: variables.timeline.goalAges( ctx ), record: false } );
                gapAtEnd = run.unfunded.retired;
                if ( gapAtEnd <= variables.EPS ) { projected = a; break; }
            }
        }
        var rst = statusOf( R, projected ?: javacast( "null", "" ) );
        arrayAppend( out, {
            key: "retirement", label: "Retire", requestedAge: R, projectedAge: projected ?: javacast( "null", "" ), status: rst, statusText: variables.STATUS_TEXT[ rst ],
            yearsDelayed: !isNull( projected ) && projected > R ? projected - R : 0,
            required: { planningAge: ctx.planningAge }, available: { retirementIncomeMonthly: ctx.plan.retirementIncomeMonthly },
            gaps: {
                atRequestedAge: gapAtR > variables.EPS ? [ { type: "retirement_funding", amount: gapAtR } ] : [],
                atEndAge: isNull( projected ) && gapAtEnd > variables.EPS ? [ { type: "retirement_funding", amount: gapAtEnd } ] : []
            },
            reason: rst == "on_track" ? "Savings and the retirement income you entered last to age #ctx.planningAge#." : "Savings run out before age #ctx.planningAge# if you retire at #R#.",
            conditional: main.unfunded.training + main.unfunded.working > variables.EPS
        } );
        return out;
    }

    private struct function overall( required array goals, required struct sim, required numeric endAge ) {
        var anyNo = false;
        var anyLate = false;
        for ( var g in arguments.goals ) {
            if ( g.status == "not_achievable" ) anyNo = true;
            if ( g.status == "later" ) anyLate = true;
        }
        var gap = arguments.sim.unfunded.training + arguments.sim.unfunded.working + arguments.sim.unfunded.retired;
        if ( anyNo ) return { code: "not_funded", message: "Your current path does not fund every goal by age #arguments.endAge#." };
        if ( anyLate || gap > variables.EPS ) return { code: "adjust", message: "Your future needs a few adjustments." };
        return { code: "achievable", message: "Your plan looks achievable under these assumptions." };
    }

    private struct function purchaseGoal( required struct sim, required string key, required string label, required numeric requestedAge ) {
        var gr = arguments.sim.goals[ arguments.key ];
        var projected = isNull( gr.achieved ) ? javacast( "null", "" ) : int( gr.achieved / 12 );
        var st = statusOf( arguments.requestedAge, projected ?: javacast( "null", "" ) );
        var at = gr.atRequested ?: javacast( "null", "" );
        return {
            key: arguments.key, label: arguments.label, requestedAge: arguments.requestedAge, projectedAge: projected ?: javacast( "null", "" ),
            status: st, statusText: variables.STATUS_TEXT[ st ],
            yearsDelayed: !isNull( projected ) && projected > arguments.requestedAge ? projected - arguments.requestedAge : 0,
            required: isNull( at ) ? javacast( "null", "" ) : { upfrontCash: at.requiredCash, monthlyCost: at.monthlyCost },
            available: isNull( at ) ? javacast( "null", "" ) : { cash: at.availableCash, monthlyLeftOver: at.monthlyLeft },
            gaps: { atRequestedAge: typedGaps( at ?: javacast( "null", "" ) ), atEndAge: isNull( projected ) ? typedGaps( gr.atEnd ?: javacast( "null", "" ) ) : [] },
            reason: st == "on_track" ? "Funded at the age you picked." : blocker( at ?: javacast( "null", "" ) ),
            conditional: !isNull( projected ) && !isNull( arguments.sim.firstUnfundedMonth ) && gr.achieved > arguments.sim.firstUnfundedMonth
        };
    }

    private string function statusOf( required numeric requested, any projected ) {
        if ( isNull( arguments.projected ) ) return "not_achievable";
        return arguments.projected <= arguments.requested ? "on_track" : "later";
    }

    private array function typedGaps( any at ) {
        if ( isNull( arguments.at ) ) return [];
        var out = [];
        if ( arguments.at.upfrontGap > variables.EPS ) arrayAppend( out, { type: "upfront_cash", amount: arguments.at.upfrontGap } );
        if ( arguments.at.monthlyGap > variables.EPS ) arrayAppend( out, { type: "monthly_cash_flow", amount: arguments.at.monthlyGap } );
        return out;
    }

    private string function blocker( any at ) {
        if ( isNull( arguments.at ) ) return "";
        if ( arguments.at.phase != "working" ) return arguments.at.phase == "training" ? "You are still in training at this age." : "You are retired at this age.";
        var d = arguments.at.upfrontGap > variables.EPS;
        var mo = arguments.at.monthlyGap > variables.EPS;
        if ( d && mo ) return "Both the upfront cash and the monthly cost are short.";
        if ( d ) return "The upfront cash (deposit plus reserve) is short.";
        if ( mo ) return "The monthly cost does not fit the budget yet.";
        return "";
    }

    public string function usd( required numeric n ) {
        return "$" & numberFormat( round( arguments.n ), "," );
    }

    private numeric function clampAge( required struct ctx, any age, required numeric fallback ) {
        return max( arguments.ctx.startAge, isNull( arguments.age ) ? arguments.fallback : arguments.age );
    }

}
