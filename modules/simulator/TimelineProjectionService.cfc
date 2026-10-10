/**
 * Monthly age projection. The browser runs the same algorithm (assets/js/projection.js); both are checked against
 * tests/fixtures/projection.
 *
 * Simulates every month from the scenario starting age to the retirement planning age. Each month's income and
 * spending come from LifestyleSimulatorService.compute() for the life stage at that month (same taxes, housing,
 * cars, childcare and food rules as the budget). Balances stay separate: liquid cash, savings account,
 * retirement account (pre-tax contributions), debts and home equity. Amounts are today's dollars.
 */
component {

    variables.EPS = 0.005;
    variables.schoolPaths = "certificate,associate,bachelor,master,doctoral,professional,medicine";
    variables.tripKinds = [ "local", "usa", "cruise", "world" ];
    variables.fallbacks = { emergencyReserveMonths: 3, investmentReturnPct: 0, trainingLivingMonthly: 1100 };

    public TimelineProjectionService function init( required any simulator, required any loans ) {
        variables.simulator = arguments.simulator;
        variables.loans = arguments.loans;
        variables.presets = arguments.simulator.assumptionDefaults().presets ?: {};
        return this;
    }

    public struct function planDefaults() {
        return {
            endAge: 70, planningAge: 95,
            startingCash: 0, startingInvestments: 0, startingDebt: 0, startingDebtRatePct: 7,
            trainingSupportMonthly: 0, studyIncomeMonthly: 0, retirementIncomeMonthly: 0,
            firstChildAge: 30, childSpacingYears: 2, childcareYears: 5, secondEarnerAge: javacast( "null", "" ),
            goals: { house: 30, car: javacast( "null", "" ), travel: javacast( "null", "" ), savings: 30, savingsTarget: 10000, retirement: 67 }
        };
    }

    public struct function planOf( required struct s ) {
        var p = planDefaults();
        var raw = isStruct( arguments.s.plan ?: "" ) ? arguments.s.plan : {};
        for ( var k in p ) {
            if ( k == "goals" ) continue;
            if ( structKeyExists( raw, k ) ) p[ k ] = raw[ k ] ?: javacast( "null", "" );
        }
        var rg = isStruct( raw.goals ?: "" ) ? raw.goals : {};
        for ( var g in p.goals ) if ( structKeyExists( rg, g ) ) p.goals[ g ] = rg[ g ] ?: javacast( "null", "" );
        return p;
    }

    public struct function context( required struct s, required struct ref ) {
        var s = arguments.s;
        var ref = arguments.ref;
        var base = variables.simulator.compute( s, ref, false );
        var A = duplicate( base.assumptionsUsed );
        for ( var k in variables.fallbacks ) if ( !isNumeric( A[ k ] ?: "" ) ) A[ k ] = variables.fallbacks[ k ];
        var p = planOf( s );
        var startAge = isNumeric( s.timeline.startAge ?: "" ) ? s.timeline.startAge : 18;
        var endAge = max( p.endAge, startAge + 10 );
        var planningAge = max( p.planningAge, endAge );
        var eduYears = base.education.years ?: 0;
        var careerStartMonth = startAge * 12 + round( eduYears * 12 );
        var house = tileOf( s, "house" );
        var apt = tileOf( s, "apartment" );
        var hv = isStruct( ref.housing.homeValue ?: "" ) ? ref.housing.homeValue.value : javacast( "null", "" );
        var housePrice = javacast( "null", "" );
        if ( !isNull( house ) ) {
            var level = presetFor( "house", house.tier ?: "" );
            if ( !isNull( house.price ) ) housePrice = house.price;
            else if ( !isNull( hv ) ) housePrice = hv * ( isNull( level ) ? 1 : level.priceMultiplier );
        }
        var rental = javacast( "null", "" );
        if ( !isNull( apt ) ) rental = duplicate( apt );
        else if ( !isNull( house ) ) rental = { type: "apartment", bedrooms: min( 3, house.bedrooms ?: 2 ), benchmark: "acs", customRent: javacast( "null", "" ) };
        var debtTile = tileOf( s, "student_debt" );
        var borrowed = base.education.borrowed ?: 0;
        var loan = ref.loans[ s.education.loanKey ] ?: { rate: 0, months: 120 };
        var studentPrincipal = isNull( debtTile ) ? 0 : ( debtTile.principal ?: borrowed );
        var car = tileOf( s, "car" );
        var car2 = tileOf( s, "second_car" );
        var savingsTile = tileOf( s, "savings" );
        var e1 = arrayLen( base.income.earners ) ? base.income.earners[ 1 ] : javacast( "null", "" );
        var e2 = arrayLen( base.income.earners ) > 1 ? base.income.earners[ 2 ] : javacast( "null", "" );

        var missing = [];
        if ( isNull( e1 ) || isNull( e1.annualWage ) ) arrayAppend( missing, { key: "career", text: !isNull( e1 ) && len( e1.soc ?: "" ) ? "A published local wage for your career (try another pay level or career)" : "A career choice" } );
        if ( arrayLen( s.earners ) > 1 && ( isNull( e2 ) || isNull( e2.annualWage ) ) ) arrayAppend( missing, { key: "career2", text: "The second earner's career pay" } );
        if ( isNull( house ) && isNull( apt ) ) arrayAppend( missing, { key: "housing", text: "A place to live (Apartment or House)" } );
        if ( !isNull( house ) && isNull( housePrice ) ) arrayAppend( missing, { key: "home_value", text: "A home value for this metro" } );
        if ( !isNull( rental ) ) {
            var rentKey = toString( rental.bedrooms );
            var published = !isNull( rental.customRent )
                || isNumeric( ref.housing.acs.rents[ rentKey ] ?: "" )
                || ( arrayLen( ref.housing.hud.areas ?: [] ) && isNumeric( ref.housing.hud.areas[ 1 ].rents[ rentKey ] ?: "" ) );
            if ( !published ) arrayAppend( missing, { key: "rent", text: "A published rent for this metro" } );
        }
        var retireAge = min( max( max( startAge, p.goals.retirement ?: 67 ), ceiling( careerStartMonth / 12 ) + 1 ), endAge );
        return {
            s: s, ref: ref, base: base, A: A, plan: p, cache: {},
            startAge: startAge, endAge: endAge, planningAge: planningAge, eduYears: eduYears, retireAge: retireAge,
            startMonth: startAge * 12, careerStartMonth: careerStartMonth,
            degree: listFind( variables.schoolPaths, s.education.pathway ) > 0 && eduYears > 0,
            house: house ?: javacast( "null", "" ), apt: apt ?: javacast( "null", "" ), rental: rental ?: javacast( "null", "" ), housePrice: housePrice ?: javacast( "null", "" ),
            studentPrincipal: studentPrincipal, loan: loan,
            tuitionCashMonthly: isNull( debtTile ) && eduYears > 0 ? borrowed / eduYears / 12 : 0,
            car: car ?: javacast( "null", "" ), car2: car2 ?: javacast( "null", "" ),
            carDown: ( carPrice( car ?: javacast( "null", "" ), A ) + carPrice( car2 ?: javacast( "null", "" ), A ) ) * A.carDownPaymentPct / 100,
            savingsMonthly: isNull( savingsTile ) ? 0 : ( savingsTile.monthly ?: A.emergencySavingsMonthly ),
            wage1: isNull( e1 ) ? javacast( "null", "" ) : ( e1.annualWage ?: javacast( "null", "" ) ),
            wage2: isNull( e2 ) ? javacast( "null", "" ) : ( e2.annualWage ?: javacast( "null", "" ) ),
            missing: missing, available: arrayLen( missing ) == 0
        };
    }

    /** opts: { retireAge, goals: { house, car, travel, savings, savingsTarget }, record } */
    public struct function simulate( required struct ctx, required struct opts ) {
        var ctx = arguments.ctx;
        var p = ctx.plan;
        var A = ctx.A;
        var s = ctx.s;
        var g = arguments.opts.goals;
        var record = arguments.opts.record ?: false;
        var retireMonth = max( ctx.careerStartMonth, arguments.opts.retireAge * 12 );
        var endMonth = ctx.planningAge * 12;
        var horizonMonth = ctx.endAge * 12;
        var monthlyGrowth = A.investmentReturnPct == 0 ? 1 : ( 1 + A.investmentReturnPct / 100 ) ^ ( 1 / 12 );
        var projected = ( s.timeline.mode ?: "today" ) == "projected";
        var kids = tileOf( s, "children" );
        var care = tileOf( s, "childcare" );

        var cash = p.startingCash;
        var savings = p.startingInvestments;
        var retire = 0;
        var student = 0;
        var studentPay = payment( ctx.studentPrincipal, ctx.loan.rate, ctx.loan.months );
        var other = p.startingDebt;
        var otherPay = payment( p.startingDebt, p.startingDebtRatePct, 120 );
        var owned = false;
        var mortgage = 0;
        var mortgageMonths = 0;
        var mortgagePaid = false;
        var mortgageRate = A.mortgageRatePct;
        var mortgageTerm = A.mortgageTermYears * 12;
        var mortgagePay = 0;
        var cars = 0;
        var travelOn = false;
        var unfunded = { training: 0, working: 0, retired: 0 };
        var firstUnfundedMonth = javacast( "null", "" );
        var cashOutMonth = javacast( "null", "" );
        var events = [];
        var snapshots = [];
        var maxEssentialGap = { amount: 0, age: javacast( "null", "" ) };

        var goals = {};
        if ( !isNull( ctx.house ) ) goals.house = newGoal( goalMonth( ctx, g.house ?: javacast( "null", "" ), 360 ) );
        if ( !isNull( ctx.car ) ) goals.car = newGoal( goalMonth( ctx, g.car ?: javacast( "null", "" ), ctx.careerStartMonth ) );
        if ( !isNull( tileOf( s, "travel" ) ) ) goals.travel = newGoal( goalMonth( ctx, g.travel ?: javacast( "null", "" ), ctx.careerStartMonth ) );
        var savingsGoal = javacast( "null", "" );
        if ( !isNull( tileOf( s, "savings" ) ) && ( g.savingsTarget ?: 0 ) > 0 ) {
            savingsGoal = { month: goalMonth( ctx, g.savings ?: javacast( "null", "" ), 360 ), target: g.savingsTarget, achieved: javacast( "null", "" ), atRequested: javacast( "null", "" ) };
            if ( savings >= savingsGoal.target ) savingsGoal.achieved = ctx.startMonth;
        }
        var priority = [ "house", "car", "travel" ];
        var order = structKeyArray( goals );
        arraySort( order, function( a, b ) {
            var d = goals[ a ].month - goals[ b ].month;
            if ( d != 0 ) return d < 0 ? -1 : 1;
            return arrayFind( priority, a ) - arrayFind( priority, b );
        } );

        var year = resetYear();
        var lastStage = "";

        for ( var m = ctx.startMonth; m < endMonth; m++ ) {
            var age = int( m / 12 );
            if ( m == ctx.careerStartMonth ) student = ctx.studentPrincipal;
            var phase = m < ctx.careerStartMonth ? "training" : ( m >= retireMonth ? "retired" : "working" );
            if ( phase != lastStage ) {
                if ( phase == "working" && m > ctx.startMonth ) arrayAppend( events, { month: m, kind: "career", label: "Career starts" } );
                if ( phase == "retired" ) arrayAppend( events, { month: m, kind: "retire", label: "Retirement begins" } );
                lastStage = phase;
            }
            var kidsHome = 0;
            var kidsCare = 0;
            if ( !isNull( kids ) ) {
                for ( var i = 0; i < kids.count; i++ ) {
                    var born = p.firstChildAge * 12 + i * p.childSpacingYears * 12;
                    var ageM = m - born;
                    if ( ageM == 0 ) arrayAppend( events, { month: m, kind: "child", label: kids.count > 1 ? "Child #i + 1# arrives" : "Child arrives" } );
                    if ( ageM >= 0 && ageM < 216 ) {
                        kidsHome++;
                        if ( !isNull( care ) && ageM < p.childcareYears * 12 ) kidsCare++;
                    }
                }
                if ( !isNull( care ) && !isNull( care.children ) ) kidsCare = min( kidsCare, care.children );
            }
            var earner2 = arrayLen( s.earners ) > 1 && age >= ( p.secondEarnerAge ?: int( ctx.careerStartMonth / 12 ) );
            var growth = projected && phase == "working" ? ( 1 + A.wageGrowthPct / 100 ) ^ int( ( m - ctx.careerStartMonth ) / 12 ) : 1;
            var st = { phase: phase, owned: owned, cars: cars, kidsHome: kidsHome, kidsCare: kidsCare, travel: travelOn, earner2: earner2, growth: growth, mortgagePaid: mortgagePaid };

            var iS = ctx.loan.rate / 1200;
            var iO = p.startingDebtRatePct / 1200;
            var payS = m >= ctx.careerStartMonth && student > variables.EPS ? min( studentPay, student * ( 1 + iS ) ) : 0;
            var payO = other > variables.EPS ? min( otherPay, other * ( 1 + iO ) ) : 0;
            var debtPay = payS + payO;
            var planned = phase == "working" ? ctx.savingsMonthly : 0;

            for ( var key in order ) {
                var gr = goals[ key ];
                if ( !isNull( gr.achieved ) || m < gr.month || m >= horizonMonth ) continue;
                var nxt = duplicate( st );
                var need = 0;
                if ( key == "house" ) { nxt.owned = true; nxt.mortgagePaid = false; need = ctx.housePrice * ( A.downPaymentPct + A.closingCostPct ) / 100; }
                if ( key == "car" ) { nxt.cars = isNull( ctx.car2 ) ? 1 : 2; need = ctx.carDown; }
                if ( key == "travel" ) nxt.travel = true;
                var fNext = flows( ctx, nxt );
                var reserve = key == "travel" ? 0 : A.emergencyReserveMonths * ( fNext.living + debtPay );
                var upfrontGap = key == "travel" ? 0 : max( 0, need + reserve - cash );
                var monthlyLeft = fNext.income - fNext.living - debtPay - planned;
                var monthlyGap = max( 0, -monthlyLeft );
                var attempt = { age: age, phase: phase, requiredCash: need + reserve, availableCash: cash, upfrontGap: upfrontGap, monthlyCost: fNext.living, monthlyLeft: monthlyLeft, monthlyGap: monthlyGap, reserve: reserve };
                if ( isNull( gr.atRequested ) ) gr.atRequested = attempt;
                gr.atEnd = attempt;
                if ( phase == "working" && upfrontGap <= variables.EPS && monthlyGap <= variables.EPS ) {
                    gr.achieved = m;
                    cash -= need;
                    st = nxt;
                    if ( key == "house" ) {
                        owned = true;
                        mortgage = ctx.housePrice * ( 1 - A.downPaymentPct / 100 );
                        mortgageMonths = 0;
                        mortgagePaid = false;
                        mortgagePay = payment( mortgage, mortgageRate, mortgageTerm );
                        arrayAppend( events, { month: m, kind: "house", label: "Buy a home" } );
                    }
                    if ( key == "car" ) { cars = nxt.cars; arrayAppend( events, { month: m, kind: "car", label: isNull( ctx.car2 ) ? "Buy a car" : "Buy two cars" } ); }
                    if ( key == "travel" ) { travelOn = true; arrayAppend( events, { month: m, kind: "travel", label: "Start traveling" } ); }
                }
            }

            var f = flows( ctx, st );
            var essential = f.income - f.living - debtPay;
            var alloc = min( planned, max( 0, essential ) );
            var left = essential - alloc;
            if ( phase == "working" && essential < 0 && -essential > maxEssentialGap.amount ) maxEssentialGap = { amount: -essential, age: age };
            var gap = 0;
            if ( left >= 0 ) {
                cash += left;
            } else {
                var needCash = -left;
                var take = min( cash, needCash ); cash -= take; needCash -= take;
                if ( phase == "retired" ) {
                    take = min( savings, needCash ); savings -= take; needCash -= take;
                    take = min( retire, needCash ); retire -= take; needCash -= take;
                }
                if ( needCash > variables.EPS ) {
                    gap = needCash;
                    unfunded[ phase ] += needCash;
                    if ( isNull( firstUnfundedMonth ) ) { firstUnfundedMonth = m; arrayAppend( events, { month: m, kind: "gap", label: "Money runs short" } ); }
                }
                if ( cash <= variables.EPS && isNull( cashOutMonth ) && phase != "retired" ) cashOutMonth = m;
            }
            savings = ( savings + alloc ) * monthlyGrowth;
            retire = ( retire + f.pretax ) * monthlyGrowth;
            if ( !isNull( savingsGoal ) && isNull( savingsGoal.achieved ) && m + 1 >= savingsGoal.month && isNull( savingsGoal.atRequested ) ) savingsGoal.atRequested = { age: int( savingsGoal.month / 12 ), balance: savings };
            if ( !isNull( savingsGoal ) && isNull( savingsGoal.achieved ) && savings >= savingsGoal.target - variables.EPS ) {
                savingsGoal.achieved = m + 1;
                arrayAppend( events, { month: m + 1, kind: "savings", label: "Savings goal reached" } );
            }
            if ( payS > 0 ) {
                student = student * ( 1 + iS ) - payS;
                if ( student <= variables.EPS ) { student = 0; arrayAppend( events, { month: m, kind: "debt", label: "Student loans paid off" } ); }
            }
            if ( payO > 0 ) { other = other * ( 1 + iO ) - payO; if ( other <= variables.EPS ) other = 0; }
            if ( owned && !mortgagePaid ) {
                var iM = mortgageRate / 1200;
                mortgage = mortgage * ( 1 + iM ) - min( mortgagePay, mortgage * ( 1 + iM ) );
                mortgageMonths++;
                if ( mortgageMonths >= mortgageTerm || mortgage <= variables.EPS ) { mortgage = 0; mortgagePaid = true; arrayAppend( events, { month: m, kind: "mortgage", label: "Mortgage paid off" } ); }
            }

            if ( record && age <= ctx.endAge ) {
                year.income += f.income; year.living += f.living; year.debt += debtPay; year.alloc += alloc; year.planned += planned;
                year.gross += f.gross; year.taxes += f.taxes; year.pretax += f.pretax; year.unfunded += gap;
                if ( m mod 12 == 11 ) {
                    var labels = [];
                    for ( var ev in events ) if ( int( ev.month / 12 ) == age ) arrayAppend( labels, ev.label );
                    arrayAppend( snapshots, {
                        age: age, stage: phase,
                        takeHomeMonthly: year.income / 12, livingMonthly: year.living / 12, debtMonthly: year.debt / 12,
                        savingsPlannedMonthly: year.planned / 12, savingsAllocatedMonthly: year.alloc / 12,
                        plannedSpendingMonthly: ( year.living + year.debt + year.planned ) / 12,
                        leftoverMonthly: ( year.income - year.living - year.debt - year.planned ) / 12,
                        grossMonthly: year.gross / 12, taxesMonthly: year.taxes / 12, pretaxRetirementMonthly: year.pretax / 12,
                        unfundedThisYear: year.unfunded, cumulativeUnfunded: unfunded.training + unfunded.working + unfunded.retired,
                        balances: { cash: cash, savings: savings, retirement: retire, studentDebt: student, otherDebt: other, mortgage: mortgage, homeEquity: owned ? ctx.housePrice - mortgage : 0 },
                        housing: owned ? "own" : ( isNull( ctx.rental ) ? "none" : "rent" ), cars: cars, kidsHome: kidsHome, kidsInCare: kidsCare, travel: travelOn,
                        events: labels
                    } );
                    year = resetYear();
                }
            }
        }
        return {
            snapshots: snapshots, events: events, goals: goals, savingsGoal: savingsGoal ?: javacast( "null", "" ), unfunded: unfunded,
            firstUnfundedMonth: firstUnfundedMonth ?: javacast( "null", "" ), cashOutMonth: cashOutMonth ?: javacast( "null", "" ),
            maxEssentialGap: maxEssentialGap, retireMonth: retireMonth
        };
    }

    public struct function goalAges( required struct ctx ) {
        var g = arguments.ctx.plan.goals;
        return { house: g.house ?: javacast( "null", "" ), car: g.car ?: javacast( "null", "" ), travel: g.travel ?: javacast( "null", "" ),
            savings: g.savings ?: javacast( "null", "" ), savingsTarget: g.savingsTarget ?: 0, retirement: g.retirement ?: 67 };
    }

    public any function tileOf( required struct s, required string type ) {
        for ( var t in arguments.s.tiles ) if ( t.type == arguments.type ) return t;
        return javacast( "null", "" );
    }

    public any function presetFor( required string group, required string key ) {
        if ( !len( arguments.key ) ) return javacast( "null", "" );
        var g = variables.presets[ arguments.group ] ?: {};
        return g[ arguments.key ] ?: javacast( "null", "" );
    }

    public struct function presets() { return variables.presets; }

    // ------------------------------------------------------------------ helpers

    /** Monthly income and spending for one life stage, cached per stage signature. */
    private struct function flows( required struct ctx, required struct st ) {
        var ctx = arguments.ctx;
        var st = arguments.st;
        var key = "#st.phase#|#st.owned ? 1 : 0#|#st.cars#|#st.kidsHome#|#st.kidsCare#|#st.travel ? 1 : 0#|#st.earner2 ? 1 : 0#|#numberFormat( st.growth, '0.000000' )#|#st.mortgagePaid ? 1 : 0#";
        if ( structKeyExists( ctx.cache, key ) ) return ctx.cache[ key ];
        var out = {};
        if ( st.phase == "training" ) {
            out = { income: ctx.plan.studyIncomeMonthly + ctx.plan.trainingSupportMonthly, living: ctx.A.trainingLivingMonthly + ctx.tuitionCashMonthly, pretax: 0, gross: 0, taxes: 0, complete: true };
        } else {
            var s = ctx.s;
            var as = duplicate( s );
            as.earners = [];
            if ( st.phase == "working" ) {
                arrayAppend( as.earners, { soc: s.earners[ 1 ].soc, percentile: s.earners[ 1 ].percentile, workFraction: s.earners[ 1 ].workFraction, customWage: ctx.wage1 * st.growth } );
                if ( st.earner2 && arrayLen( s.earners ) > 1 ) arrayAppend( as.earners, { soc: s.earners[ 2 ].soc, percentile: s.earners[ 2 ].percentile, workFraction: s.earners[ 2 ].workFraction, customWage: ctx.wage2 * st.growth } );
            }
            var tiles = [];
            if ( st.owned ) {
                var h = duplicate( ctx.house );
                h.price = ctx.housePrice;
                arrayAppend( tiles, h );
            } else if ( !isNull( ctx.rental ) ) {
                arrayAppend( tiles, duplicate( ctx.rental ) );
                var rm = tileOf( s, "roommates" );
                if ( !isNull( rm ) ) arrayAppend( tiles, duplicate( rm ) );
            }
            if ( st.cars >= 1 && !isNull( ctx.car ) ) arrayAppend( tiles, duplicate( ctx.car ) );
            if ( st.cars >= 2 && !isNull( ctx.car2 ) ) arrayAppend( tiles, duplicate( ctx.car2 ) );
            var kids = tileOf( s, "children" );
            var care = tileOf( s, "childcare" );
            if ( st.kidsHome > 0 && !isNull( kids ) ) arrayAppend( tiles, { type: "children", count: st.kidsHome, ageGroup: kids.ageGroup } );
            if ( st.kidsCare > 0 && !isNull( care ) ) arrayAppend( tiles, { type: "childcare", children: st.kidsCare, tier: care.tier ?: "middle" } );
            if ( st.travel ) {
                var tr = tileOf( s, "travel" );
                if ( !isNull( tr ) ) arrayAppend( tiles, duplicate( tr ) );
            }
            as.tiles = tiles;
            var r = variables.simulator.compute( as, ctx.ref, false );
            var living = r.costs.monthlyTotal;
            var complete = true;
            for ( var l in r.costs.lines ) {
                if ( isNull( l.monthly ) ) { complete = false; continue; }
                if ( st.mortgagePaid && ( l.key == "mortgage" || l.key == "pmi" ) ) living -= l.monthly;
            }
            if ( st.phase == "working" ) {
                out = { income: r.income.takeHomeMonthly, living: living, pretax: r.income.pretaxRetirementAnnual / 12, gross: r.income.grossAnnual / 12, taxes: r.income.taxes.total / 12, complete: complete };
            } else {
                out = { income: ctx.plan.retirementIncomeMonthly, living: living, pretax: 0, gross: 0, taxes: 0, complete: complete };
            }
        }
        ctx.cache[ key ] = out;
        return out;
    }

    private numeric function payment( required numeric principal, required numeric rate, required numeric months ) {
        return arguments.principal > 0 ? variables.loans.amortize( arguments.principal, arguments.rate, arguments.months ).payment : 0;
    }

    private numeric function goalMonth( required struct ctx, any age, required numeric fallbackMonth ) {
        return max( arguments.ctx.startMonth, isNull( arguments.age ) ? arguments.fallbackMonth : arguments.age * 12 );
    }

    private struct function newGoal( required numeric month ) {
        return { month: arguments.month, achieved: javacast( "null", "" ), atRequested: javacast( "null", "" ), atEnd: javacast( "null", "" ) };
    }

    private struct function resetYear() {
        return { income: 0, living: 0, debt: 0, alloc: 0, planned: 0, gross: 0, taxes: 0, pretax: 0, unfunded: 0 };
    }

    private numeric function carPrice( any t, required struct A ) {
        if ( isNull( arguments.t ) ) return 0;
        if ( !isNull( arguments.t.price ) ) return arguments.t.price;
        var lv = presetFor( "car", arguments.t.tier ?: "" );
        return arguments.A.carPrice * ( isNull( lv ) ? 1 : lv.priceMultiplier );
    }

}
