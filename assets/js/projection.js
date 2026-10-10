/*
 * FuturePath age projection (browser + Node). Mirrors the CFML services TimelineProjectionService,
 * GoalFeasibilityService and AffordableAlternativeService; both are checked against tests/fixtures/projection.
 *
 * A monthly simulation from the scenario starting age to the retirement planning age. Each month's income and
 * spending come from the existing budget engine (FPEngine.compute) for the life stage at that month, so taxes,
 * rent/mortgage, cars, childcare and food use exactly the same rules as the budget. Balances are kept apart:
 * liquid cash, a savings account (Savings card), a retirement account (pre-tax contributions), debts and home equity.
 * All amounts are today's dollars. Pure functions only: no DOM, no network.
 */
(function (root, factory) {
    if (typeof module === 'object' && module.exports) module.exports = factory(require('./engine.js'));
    else root.FPProjection = factory(root.FPEngine);
}(typeof self !== 'undefined' ? self : this, function (E) {
    'use strict';

    var VERSION = 'projection-2026.1';
    var EPS = 0.005;
    var isNum = function (v) { return typeof v === 'number' && isFinite(v); };
    var nz = function (v, d) { return v === null || v === undefined ? d : v; };
    var clone = function (o) { return JSON.parse(JSON.stringify(o)); };
    var usd = function (n) { return '$' + Math.round(n).toLocaleString('en-US'); };
    var SCHOOL_PATHS = ['certificate', 'associate', 'bachelor', 'master', 'doctoral', 'professional', 'medicine'];

    var PLAN_DEFAULTS = {
        endAge: 70, planningAge: 95,
        startingCash: 0, startingInvestments: 0, startingDebt: 0, startingDebtRatePct: 7,
        trainingSupportMonthly: 0, studyIncomeMonthly: 0, retirementIncomeMonthly: 0,
        firstChildAge: 30, childSpacingYears: 2, childcareYears: 5, secondEarnerAge: null,
        goals: { house: 30, car: null, travel: null, savings: 30, savingsTarget: 10000, retirement: 67 }
    };
    var ASSUMPTION_FALLBACKS = { emergencyReserveMonths: 3, investmentReturnPct: 0, trainingLivingMonthly: 1100 };
    var OMISSIONS = [
        'Social Security, pensions and other retirement income are counted only when you enter them.',
        'Taxes on retirement-account withdrawals are not modeled.',
        'Retirement-account money is treated as available only from your retirement age.',
        'A car payment continues for life as a replacement cycle (a new car when the loan ends).',
        'Home values and rents stay at today\'s level (no appreciation).',
        'Tax rules are held at the current year; projected mode assumes brackets keep pace with inflation.',
        'Interest that builds up on student loans while in school is not included.',
        'Living costs while in training use one shared-housing assumption, not your lifestyle cards.'
    ];

    function plan(s) {
        var p = clone(PLAN_DEFAULTS);
        var raw = s.plan || {};
        Object.keys(PLAN_DEFAULTS).forEach(function (k) { if (k !== 'goals' && raw[k] !== undefined) p[k] = raw[k]; });
        Object.keys(PLAN_DEFAULTS.goals).forEach(function (k) { if (raw.goals && raw.goals[k] !== undefined) p.goals[k] = raw.goals[k]; });
        return p;
    }
    function tileOf(s, type) { return (s.tiles || []).filter(function (t) { return t.type === type; })[0] || null; }

    // ------------------------------------------------------------------ context
    function context(s, ref, defaults) {
        var base = E.compute(s, ref, defaults, { includeTimeline: false });
        var A = {};
        Object.keys(base.assumptionsUsed).forEach(function (k) { A[k] = base.assumptionsUsed[k]; });
        Object.keys(ASSUMPTION_FALLBACKS).forEach(function (k) { if (!isNum(A[k])) A[k] = ASSUMPTION_FALLBACKS[k]; });
        var p = plan(s);
        var startAge = s.timeline && isNum(s.timeline.startAge) ? s.timeline.startAge : 18;
        var endAge = Math.max(p.endAge, startAge + 10);
        var planningAge = Math.max(p.planningAge, endAge);
        var eduYears = nz(base.education.years, 0);
        var careerStartMonth = startAge * 12 + Math.round(eduYears * 12);
        var house = tileOf(s, 'house'), apt = tileOf(s, 'apartment');
        var hv = ref.housing && ref.housing.homeValue ? ref.housing.homeValue.value : null;
        var level = house && defaults.presets && defaults.presets.house ? defaults.presets.house[house.tier] : null;
        var housePrice = house ? (isNum(house.price) ? house.price : (isNum(hv) ? hv * (level ? level.priceMultiplier : 1) : null)) : null;
        var rental = apt ? clone(apt) : (house ? { type: 'apartment', bedrooms: Math.min(3, house.bedrooms || 2), benchmark: 'acs', customRent: null } : null);
        var debtTile = tileOf(s, 'student_debt');
        var borrowed = nz(base.education.borrowed, 0);
        var loan = (ref.loans || {})[s.education.loanKey] || { rate: 0, months: 120 };
        var studentPrincipal = debtTile ? nz(debtTile.principal, borrowed) : 0;
        var car = tileOf(s, 'car'), car2 = tileOf(s, 'second_car');
        var carPrice = function (t) {
            if (!t) return 0;
            var lv = defaults.presets && defaults.presets.car ? defaults.presets.car[t.tier] : null;
            return isNum(t.price) ? t.price : A.carPrice * (lv ? lv.priceMultiplier : 1);
        };
        var savingsTile = tileOf(s, 'savings');
        var e1 = base.income.earners[0] || null;
        var e2 = base.income.earners[1] || null;

        var missing = [];
        if (!e1 || e1.annualWage === null) missing.push({ key: 'career', text: e1 && e1.soc ? 'A published local wage for your career (try another pay level or career)' : 'A career choice' });
        if (s.earners.length > 1 && (!e2 || e2.annualWage === null)) missing.push({ key: 'career2', text: "The second earner's career pay" });
        if (!house && !apt) missing.push({ key: 'housing', text: 'A place to live (Apartment or House)' });
        if (house && housePrice === null) missing.push({ key: 'home_value', text: 'A home value for this metro' });
        if (rental) {
            var rentKey = String(rental.bedrooms);
            var rentPublished = isNum(rental.customRent) || (ref.housing && ref.housing.acs && ref.housing.acs.rents && isNum(ref.housing.acs.rents[rentKey])) ||
                (ref.housing && ref.housing.hud && ref.housing.hud.areas && ref.housing.hud.areas.length && isNum(ref.housing.hud.areas[0].rents[rentKey]));
            if (!rentPublished) missing.push({ key: 'rent', text: 'A published rent for this metro' });
        }

        var retireAge = Math.min(Math.max(Math.max(startAge, nz(p.goals.retirement, 67)), Math.ceil(careerStartMonth / 12) + 1), endAge);
        return {
            s: s, ref: ref, defaults: defaults, base: base, A: A, plan: p, cache: {},
            startAge: startAge, endAge: endAge, planningAge: planningAge, eduYears: eduYears, retireAge: retireAge,
            startMonth: startAge * 12, careerStartMonth: careerStartMonth,
            degree: SCHOOL_PATHS.indexOf(s.education.pathway) >= 0 && eduYears > 0,
            house: house, apt: apt, rental: rental, housePrice: housePrice,
            studentPrincipal: studentPrincipal, loan: loan,
            tuitionCashMonthly: !debtTile && eduYears > 0 ? borrowed / eduYears / 12 : 0,
            car: car, car2: car2, carDown: (carPrice(car) + carPrice(car2)) * A.carDownPaymentPct / 100,
            savingsMonthly: savingsTile ? nz(savingsTile.monthly, A.emergencySavingsMonthly) : 0,
            wage1: e1 ? e1.annualWage : null, wage2: e2 ? e2.annualWage : null,
            missing: missing, available: missing.length === 0
        };
    }

    // ------------------------------------------------------------------ monthly cash flows for a life stage
    function flows(ctx, st) {
        var key = [st.phase, st.owned ? 1 : 0, st.cars, st.kidsHome, st.kidsCare, st.travel ? 1 : 0, st.earner2 ? 1 : 0, st.growth.toFixed(6), st.mortgagePaid ? 1 : 0].join('|');
        if (ctx.cache[key]) return ctx.cache[key];
        var out;
        if (st.phase === 'training') {
            out = { income: ctx.plan.studyIncomeMonthly + ctx.plan.trainingSupportMonthly, living: ctx.A.trainingLivingMonthly + ctx.tuitionCashMonthly,
                pretax: 0, gross: 0, taxes: 0, categories: null, complete: true };
        } else {
            var as = clone(ctx.s);
            var s = ctx.s;
            as.earners = [];
            if (st.phase === 'working') {
                as.earners.push({ soc: s.earners[0].soc, percentile: s.earners[0].percentile, workFraction: s.earners[0].workFraction, customWage: ctx.wage1 * st.growth });
                if (st.earner2 && s.earners[1]) as.earners.push({ soc: s.earners[1].soc, percentile: s.earners[1].percentile, workFraction: s.earners[1].workFraction, customWage: ctx.wage2 * st.growth });
            }
            var tiles = [];
            if (st.owned) { var h = clone(ctx.house); h.price = ctx.housePrice; tiles.push(h); }
            else if (ctx.rental) {
                tiles.push(clone(ctx.rental));
                var rm = tileOf(s, 'roommates'); if (rm) tiles.push(clone(rm));
            }
            if (st.cars >= 1 && ctx.car) tiles.push(clone(ctx.car));
            if (st.cars >= 2 && ctx.car2) tiles.push(clone(ctx.car2));
            var kids = tileOf(s, 'children'), care = tileOf(s, 'childcare');
            if (st.kidsHome > 0 && kids) tiles.push({ type: 'children', count: st.kidsHome, ageGroup: kids.ageGroup });
            if (st.kidsCare > 0 && care) tiles.push({ type: 'childcare', children: st.kidsCare, tier: care.tier });
            if (st.travel) { var tr = tileOf(s, 'travel'); if (tr) tiles.push(clone(tr)); }
            as.tiles = tiles;
            var r = E.compute(as, ctx.ref, ctx.defaults, { includeTimeline: false });
            var living = r.costs.monthlyTotal;
            if (st.mortgagePaid) r.costs.lines.forEach(function (l) { if ((l.key === 'mortgage' || l.key === 'pmi') && l.monthly !== null) living -= l.monthly; });
            var complete = r.costs.lines.every(function (l) { return l.monthly !== null; });
            out = st.phase === 'working'
                ? { income: r.income.takeHomeMonthly, living: living, pretax: r.income.pretaxRetirementAnnual / 12, gross: r.income.grossAnnual / 12, taxes: r.income.taxes.total / 12, categories: r.costs.categories, complete: complete }
                : { income: ctx.plan.retirementIncomeMonthly, living: living, pretax: 0, gross: 0, taxes: 0, categories: r.costs.categories, complete: complete };
        }
        ctx.cache[key] = out;
        return out;
    }

    // ------------------------------------------------------------------ simulation
    function amortPayment(principal, rate, months) { return principal > 0 ? E.amortize(principal, rate, months).payment : 0; }

    function goalMonth(ctx, age, fallbackMonth) { return Math.max(ctx.startMonth, isNum(age) ? age * 12 : fallbackMonth); }

    /** opts: { retireAge, goals: {house, car, travel, savings, savingsTarget}, record } */
    function simulate(ctx, opts) {
        var p = ctx.plan, A = ctx.A, s = ctx.s;
        var g = opts.goals;
        var retireMonth = Math.max(ctx.careerStartMonth, opts.retireAge * 12);
        var endMonth = ctx.planningAge * 12;
        var horizonMonth = ctx.endAge * 12;
        var monthlyGrowth = A.investmentReturnPct === 0 ? 1 : Math.pow(1 + A.investmentReturnPct / 100, 1 / 12);
        var projected = s.timeline && s.timeline.mode === 'projected';
        var kids = tileOf(s, 'children'), care = tileOf(s, 'childcare');

        var cash = p.startingCash, savings = p.startingInvestments, retire = 0;
        var student = 0, studentPay = amortPayment(ctx.studentPrincipal, ctx.loan.rate, ctx.loan.months);
        var other = p.startingDebt, otherPay = amortPayment(p.startingDebt, p.startingDebtRatePct, 120);
        var owned = false, mortgage = 0, mortgageMonths = 0, mortgagePaid = false;
        var mortgageRate = A.mortgageRatePct, mortgageTerm = A.mortgageTermYears * 12;
        var mortgagePay = 0, cars = 0, travelOn = false;
        var unfunded = { training: 0, working: 0, retired: 0 };
        var firstUnfundedMonth = null, cashOutMonth = null;
        var events = [];
        var snapshots = [];
        var maxEssentialGap = { amount: 0, age: null };

        var goals = {};
        if (ctx.house) goals.house = { month: goalMonth(ctx, g.house, 360), achieved: null, atRequested: null, atEnd: null };
        if (ctx.car) goals.car = { month: goalMonth(ctx, g.car, ctx.careerStartMonth), achieved: null, atRequested: null, atEnd: null };
        if (tileOf(s, 'travel')) goals.travel = { month: goalMonth(ctx, g.travel, ctx.careerStartMonth), achieved: null, atRequested: null, atEnd: null };
        var savingsGoal = tileOf(s, 'savings') && g.savingsTarget > 0 ? { month: goalMonth(ctx, g.savings, 360), target: g.savingsTarget, achieved: null, atRequested: null } : null;
        if (savingsGoal && savings >= savingsGoal.target) savingsGoal.achieved = ctx.startMonth;
        var order = Object.keys(goals).sort(function (a, b) { return goals[a].month - goals[b].month || ['house', 'car', 'travel'].indexOf(a) - ['house', 'car', 'travel'].indexOf(b); });

        var year = null;
        var resetYear = function () { return { income: 0, living: 0, debt: 0, alloc: 0, planned: 0, gross: 0, taxes: 0, pretax: 0, unfunded: 0 }; };
        year = resetYear();
        var lastStage = null;

        for (var m = ctx.startMonth; m < endMonth; m++) {
            var age = Math.floor(m / 12);
            if (m === ctx.careerStartMonth) student = ctx.studentPrincipal;
            var phase = m < ctx.careerStartMonth ? 'training' : (m >= retireMonth ? 'retired' : 'working');
            if (phase !== lastStage) {
                if (phase === 'working' && m > ctx.startMonth) events.push({ month: m, kind: 'career', label: 'Career starts' });
                if (phase === 'retired') events.push({ month: m, kind: 'retire', label: 'Retirement begins' });
                lastStage = phase;
            }
            var kidsHome = 0, kidsCare = 0;
            if (kids) {
                for (var i = 0; i < kids.count; i++) {
                    var born = p.firstChildAge * 12 + i * p.childSpacingYears * 12;
                    var ageM = m - born;
                    if (ageM === 0) events.push({ month: m, kind: 'child', label: kids.count > 1 ? 'Child ' + (i + 1) + ' arrives' : 'Child arrives' });
                    if (ageM >= 0 && ageM < 216) { kidsHome++; if (care && ageM < p.childcareYears * 12) kidsCare++; }
                }
                if (care && isNum(care.children)) kidsCare = Math.min(kidsCare, care.children);
            }
            var earner2 = s.earners.length > 1 && age >= nz(p.secondEarnerAge, Math.floor(ctx.careerStartMonth / 12));
            var growth = projected && phase === 'working' ? Math.pow(1 + A.wageGrowthPct / 100, Math.floor((m - ctx.careerStartMonth) / 12)) : 1;
            var st = { phase: phase, owned: owned, cars: cars, kidsHome: kidsHome, kidsCare: kidsCare, travel: travelOn, earner2: earner2, growth: growth, mortgagePaid: mortgagePaid };

            var iS = ctx.loan.rate / 1200, iO = p.startingDebtRatePct / 1200;
            var payS = m >= ctx.careerStartMonth && student > EPS ? Math.min(studentPay, student * (1 + iS)) : 0;
            var payO = other > EPS ? Math.min(otherPay, other * (1 + iO)) : 0;
            var debtPay = payS + payO;
            var planned = phase === 'working' ? ctx.savingsMonthly : 0;

            // goals attempted in order of requested date; each purchase spends real cash, so goals cannot share it
            for (var gi = 0; gi < order.length; gi++) {
                var key = order[gi], gr = goals[key];
                if (gr.achieved !== null || m < gr.month || m >= horizonMonth) continue;
                var next = Object.assign({}, st);
                var need = 0;
                if (key === 'house') { next.owned = true; next.mortgagePaid = false; need = ctx.housePrice * (A.downPaymentPct + A.closingCostPct) / 100; }
                if (key === 'car') { next.cars = ctx.car2 ? 2 : 1; need = ctx.carDown; }
                if (key === 'travel') next.travel = true;
                var fNext = flows(ctx, next);
                var reserve = key === 'travel' ? 0 : A.emergencyReserveMonths * (fNext.living + debtPay);
                var upfrontGap = key === 'travel' ? 0 : Math.max(0, need + reserve - cash);
                var monthlyLeft = fNext.income - fNext.living - debtPay - planned;
                var monthlyGap = Math.max(0, -monthlyLeft);
                var attempt = { age: age, phase: phase, requiredCash: need + reserve, availableCash: cash, upfrontGap: upfrontGap, monthlyCost: fNext.living, monthlyLeft: monthlyLeft, monthlyGap: monthlyGap, reserve: reserve };
                if (gr.atRequested === null) gr.atRequested = attempt;
                gr.atEnd = attempt;
                if (phase === 'working' && upfrontGap <= EPS && monthlyGap <= EPS) {
                    gr.achieved = m;
                    cash -= need;
                    st = next;
                    if (key === 'house') {
                        owned = true; mortgage = ctx.housePrice * (1 - A.downPaymentPct / 100); mortgageMonths = 0; mortgagePaid = false;
                        mortgagePay = amortPayment(mortgage, mortgageRate, mortgageTerm);
                        events.push({ month: m, kind: 'house', label: 'Buy a home' });
                    }
                    if (key === 'car') { cars = next.cars; events.push({ month: m, kind: 'car', label: ctx.car2 ? 'Buy two cars' : 'Buy a car' }); }
                    if (key === 'travel') { travelOn = true; events.push({ month: m, kind: 'travel', label: 'Start traveling' }); }
                }
            }

            var f = flows(ctx, st);
            var available = f.income - f.living - debtPay;
            var alloc = Math.min(planned, Math.max(0, available));
            var left = available - alloc;
            if (phase === 'working' && f.income - f.living - debtPay < 0 && -(f.income - f.living - debtPay) > maxEssentialGap.amount) maxEssentialGap = { amount: -(f.income - f.living - debtPay), age: age };
            var gap = 0;
            if (left >= 0) cash += left;
            else {
                var needCash = -left;
                var take = Math.min(cash, needCash); cash -= take; needCash -= take;
                if (phase === 'retired') {
                    take = Math.min(savings, needCash); savings -= take; needCash -= take;
                    take = Math.min(retire, needCash); retire -= take; needCash -= take;
                }
                if (needCash > EPS) {
                    gap = needCash;
                    unfunded[phase] += needCash;
                    if (firstUnfundedMonth === null) { firstUnfundedMonth = m; events.push({ month: m, kind: 'gap', label: 'Money runs short' }); }
                }
                if (cash <= EPS && cashOutMonth === null && phase !== 'retired') cashOutMonth = m;
            }
            savings = (savings + alloc) * monthlyGrowth;
            retire = (retire + f.pretax) * monthlyGrowth;
            if (savingsGoal && savingsGoal.achieved === null && m + 1 >= savingsGoal.month && savingsGoal.atRequested === null) savingsGoal.atRequested = { age: Math.floor(savingsGoal.month / 12), balance: savings };
            if (savingsGoal && savingsGoal.achieved === null && savings >= savingsGoal.target - EPS) {
                savingsGoal.achieved = m + 1;
                events.push({ month: m + 1, kind: 'savings', label: 'Savings goal reached' });
            }
            if (payS > 0) { student = student * (1 + iS) - payS; if (student <= EPS) { student = 0; events.push({ month: m, kind: 'debt', label: 'Student loans paid off' }); } }
            if (payO > 0) { other = other * (1 + iO) - payO; if (other <= EPS) other = 0; }
            if (owned && !mortgagePaid) {
                var iM = mortgageRate / 1200;
                mortgage = mortgage * (1 + iM) - Math.min(mortgagePay, mortgage * (1 + iM));
                mortgageMonths++;
                if (mortgageMonths >= mortgageTerm || mortgage <= EPS) { mortgage = 0; mortgagePaid = true; events.push({ month: m, kind: 'mortgage', label: 'Mortgage paid off' }); }
            }

            if (opts.record && age <= ctx.endAge) {
                year.income += f.income; year.living += f.living; year.debt += debtPay; year.alloc += alloc; year.planned += planned;
                year.gross += f.gross; year.taxes += f.taxes; year.pretax += f.pretax; year.unfunded += gap;
                if (m % 12 === 11) {
                    snapshots.push({
                        age: age, stage: phase,
                        takeHomeMonthly: year.income / 12, livingMonthly: year.living / 12, debtMonthly: year.debt / 12,
                        savingsPlannedMonthly: year.planned / 12, savingsAllocatedMonthly: year.alloc / 12,
                        plannedSpendingMonthly: (year.living + year.debt + year.planned) / 12,
                        leftoverMonthly: (year.income - year.living - year.debt - year.planned) / 12,
                        grossMonthly: year.gross / 12, taxesMonthly: year.taxes / 12, pretaxRetirementMonthly: year.pretax / 12,
                        unfundedThisYear: year.unfunded, cumulativeUnfunded: unfunded.training + unfunded.working + unfunded.retired,
                        balances: { cash: cash, savings: savings, retirement: retire, studentDebt: student, otherDebt: other, mortgage: mortgage, homeEquity: owned ? ctx.housePrice - mortgage : 0 },
                        housing: owned ? 'own' : (ctx.rental ? 'rent' : 'none'), cars: cars, kidsHome: kidsHome, kidsInCare: kidsCare, travel: travelOn,
                        events: events.filter(function (e) { return Math.floor(e.month / 12) === age; }).map(function (e) { return e.label; })
                    });
                    year = resetYear();
                }
            }
        }
        return {
            snapshots: snapshots, events: events, goals: goals, savingsGoal: savingsGoal, unfunded: unfunded,
            firstUnfundedMonth: firstUnfundedMonth, cashOutMonth: cashOutMonth, maxEssentialGap: maxEssentialGap, retireMonth: retireMonth
        };
    }

    function goalAges(ctx) {
        var g = ctx.plan.goals;
        return { house: g.house, car: g.car, travel: g.travel, savings: g.savings, savingsTarget: g.savingsTarget, retirement: g.retirement };
    }

    // ------------------------------------------------------------------ goals
    var STATUS_TEXT = { on_track: 'On track', later: 'Later than planned', not_achievable: 'Not achievable within this timeline under the current assumptions', info: 'More information needed' };

    function status(requested, projected) {
        if (projected === null) return 'not_achievable';
        return projected <= requested ? 'on_track' : 'later';
    }
    function typedGaps(at) {
        if (!at) return [];
        var out = [];
        if (at.upfrontGap > EPS) out.push({ type: 'upfront_cash', amount: at.upfrontGap });
        if (at.monthlyGap > EPS) out.push({ type: 'monthly_cash_flow', amount: at.monthlyGap });
        return out;
    }
    function blocker(at) {
        if (!at) return '';
        if (at.phase !== 'working') return at.phase === 'training' ? 'You are still in training at this age.' : 'You are retired at this age.';
        var d = at.upfrontGap > EPS, mo = at.monthlyGap > EPS;
        return d && mo ? 'Both the upfront cash and the monthly cost are short.' : (d ? 'The upfront cash (deposit plus reserve) is short.' : (mo ? 'The monthly cost does not fit the budget yet.' : ''));
    }

    function purchaseGoal(ctx, sim, key, label, requestedAge) {
        var gr = sim.goals[key];
        var projected = gr.achieved !== null ? Math.floor(gr.achieved / 12) : null;
        var st = status(requestedAge, projected);
        var at = gr.atRequested;
        return {
            key: key, label: label, requestedAge: requestedAge, projectedAge: projected, status: st, statusText: STATUS_TEXT[st],
            yearsDelayed: projected !== null && projected > requestedAge ? projected - requestedAge : 0,
            required: at ? { upfrontCash: at.requiredCash, monthlyCost: at.monthlyCost } : null,
            available: at ? { cash: at.availableCash, monthlyLeftOver: at.monthlyLeft } : null,
            gaps: { atRequestedAge: typedGaps(at), atEndAge: projected === null ? typedGaps(gr.atEnd) : [] },
            reason: st === 'on_track' ? 'Funded at the age you picked.' : blocker(at),
            conditional: projected !== null && sim.firstUnfundedMonth !== null && gr.achieved > sim.firstUnfundedMonth
        };
    }

    function retirementRun(ctx, age) { return simulate(ctx, { retireAge: age, goals: goalAges(ctx), record: false }); }

    function buildGoals(ctx, main) {
        var g = ctx.plan.goals, out = [];
        var startAge = ctx.startAge;
        var clampAge = function (a, fallback) { return Math.max(startAge, isNum(a) ? a : fallback); };
        if (ctx.degree) {
            var finish = Math.ceil(ctx.careerStartMonth / 12);
            var trainingGap = main.unfunded.training;
            var ok = trainingGap <= EPS;
            out.push({
                key: 'education', label: 'Finish school or training', requestedAge: finish, projectedAge: finish, status: ok ? 'on_track' : 'not_achievable',
                statusText: ok ? STATUS_TEXT.on_track : 'Training costs not fully funded', yearsDelayed: 0,
                required: { monthlyCost: ctx.A.trainingLivingMonthly + ctx.tuitionCashMonthly }, available: { monthlyIncome: ctx.plan.studyIncomeMonthly + ctx.plan.trainingSupportMonthly, cash: ctx.plan.startingCash },
                gaps: { atRequestedAge: ok ? [] : [{ type: 'upfront_cash', amount: trainingGap }], atEndAge: [] },
                reason: ok ? 'Living costs while training are covered.' : 'Living costs while training need about ' + usd(trainingGap) + ' more in total. Add family support, work while studying or starting savings.',
                conditional: false
            });
        }
        if (main.goals.house) out.push(purchaseGoal(ctx, main, 'house', 'Buy a home', clampAge(g.house, 30)));
        if (main.goals.car) out.push(purchaseGoal(ctx, main, 'car', ctx.car2 ? 'Buy your cars' : 'Buy a car', clampAge(g.car, Math.floor(ctx.careerStartMonth / 12))));
        if (main.goals.travel) {
            var tg = purchaseGoal(ctx, main, 'travel', 'Travel budget', clampAge(g.travel, Math.floor(ctx.careerStartMonth / 12)));
            if (tg.status === 'on_track') tg.reason = 'Your trips fit the monthly budget.';
            out.push(tg);
        }
        if (main.savingsGoal) {
            var sg = main.savingsGoal, req = clampAge(g.savings, 30);
            var proj = sg.achieved !== null && sg.achieved <= ctx.endAge * 12 ? Math.floor(sg.achieved / 12) : null;
            var sst = status(req, proj);
            var bal = sg.atRequested ? sg.atRequested.balance : 0;
            out.push({
                key: 'savings', label: 'Save ' + usd(sg.target), requestedAge: req, projectedAge: proj, status: sst, statusText: STATUS_TEXT[sst],
                yearsDelayed: proj !== null && proj > req ? proj - req : 0,
                required: { target: sg.target }, available: { balanceAtRequestedAge: bal },
                gaps: { atRequestedAge: sst === 'on_track' ? [] : [{ type: 'upfront_cash', amount: Math.max(0, sg.target - bal) }], atEndAge: [] },
                reason: sst === 'on_track' ? 'Your monthly savings reach the target in time.' : 'Your savings account is short of the target at that age.',
                conditional: proj !== null && main.firstUnfundedMonth !== null && sg.achieved > main.firstUnfundedMonth
            });
        }
        // retirement: fund every month from the retirement age to the planning age without an unfunded gap
        var R = ctx.retireAge;
        var gapAtR = main.unfunded.retired, projected = gapAtR <= EPS ? R : null, gapAtEnd = gapAtR;
        if (projected === null) {
            for (var a = R + 1; a <= ctx.endAge; a++) {
                var run = retirementRun(ctx, a);
                gapAtEnd = run.unfunded.retired;
                if (gapAtEnd <= EPS) { projected = a; break; }
            }
        }
        var rst = status(R, projected);
        out.push({
            key: 'retirement', label: 'Retire', requestedAge: R, projectedAge: projected, status: rst, statusText: STATUS_TEXT[rst],
            yearsDelayed: projected !== null && projected > R ? projected - R : 0,
            required: { planningAge: ctx.planningAge }, available: { retirementIncomeMonthly: ctx.plan.retirementIncomeMonthly },
            gaps: { atRequestedAge: gapAtR > EPS ? [{ type: 'retirement_funding', amount: gapAtR }] : [], atEndAge: projected === null && gapAtEnd > EPS ? [{ type: 'retirement_funding', amount: gapAtEnd }] : [] },
            reason: rst === 'on_track' ? 'Savings and the retirement income you entered last to age ' + ctx.planningAge + '.' : 'Savings run out before age ' + ctx.planningAge + ' if you retire at ' + R + '.',
            conditional: main.unfunded.training + main.unfunded.working > EPS
        });
        return out;
    }

    function overall(goals, sim, endAge) {
        var anyNo = goals.some(function (g) { return g.status === 'not_achievable'; });
        var anyLate = goals.some(function (g) { return g.status === 'later'; });
        var gap = sim.unfunded.training + sim.unfunded.working + sim.unfunded.retired;
        if (anyNo) return { code: 'not_funded', message: 'Your current path does not fund every goal by age ' + endAge + '.' };
        if (anyLate || gap > EPS) return { code: 'adjust', message: 'Your future needs a few adjustments.' };
        return { code: 'achievable', message: 'Your plan looks achievable under these assumptions.' };
    }

    // ------------------------------------------------------------------ affordable alternative
    function quickFeasible(s, ref, defaults) {
        var ctx = context(s, ref, defaults);
        if (!ctx.available) return { ok: false, ctx: ctx, sim: null };
        var sim = simulate(ctx, { retireAge: ctx.retireAge, goals: goalAges(ctx), record: false });
        var ok = sim.unfunded.training + sim.unfunded.working + sim.unfunded.retired <= EPS;
        Object.keys(sim.goals).forEach(function (k) {
            var gr = sim.goals[k];
            if (gr.achieved === null || gr.achieved > gr.month) ok = false;
        });
        if (sim.savingsGoal && (sim.savingsGoal.achieved === null || sim.savingsGoal.achieved > sim.savingsGoal.month)) ok = false;
        return { ok: ok, ctx: ctx, sim: sim };
    }

    function travelSummary(t, defaults) {
        if (!t) return 'No travel';
        if (isNum(t.annual)) return usd(t.annual) + ' a year';
        if (!t.trips) return 'Default travel budget';
        var parts = (E.TRIP_KINDS || []).filter(function (k) { return t.trips && t.trips[k] > 0; }).map(function (k) {
            var p = defaults.presets && defaults.presets.travel ? defaults.presets.travel[k] : null;
            return t.trips[k] + ' x ' + (p ? p.label.toLowerCase() : k);
        });
        return parts.length ? parts.join(', ') + ' a year' : 'No trips';
    }
    function levelLabel(defaults, group, key) { var g = defaults.presets ? defaults.presets[group] : null; return g && g[key] ? g[key].label : key; }

    function alternative(s, ref, defaults) {
        var cand = clone(s);
        cand.plan = plan(cand);
        var changes = [];
        var tryLevels = function (area, levels) {
            for (var i = 0; i < levels.length; i++) {
                var next = clone(cand);
                levels[i].apply(next);
                var q = quickFeasible(next, ref, defaults);
                if (q.ok || i === levels.length - 1) {
                    cand = next;
                    changes.push({ area: area, requested: levels[i].requested, alternative: levels[i].alternative, why: levels[i].why });
                    return q.ok;
                }
            }
            return false;
        };
        if (quickFeasible(cand, ref, defaults).ok) return null;

        // 1. discretionary travel
        var tr = tileOf(cand, 'travel');
        if (tr) {
            var levels = [];
            var before = travelSummary(tr, defaults);
            if (isNum(tr.annual)) {
                levels.push({ apply: function (x) { tileOf(x, 'travel').annual = Math.round(tr.annual / 2); }, requested: before, alternative: travelSummary({ annual: Math.round(tr.annual / 2) }, defaults), why: 'Half the travel budget' });
            } else if (tr.trips) {
                var half = {}; (E.TRIP_KINDS || []).forEach(function (k) { half[k] = Math.floor((tr.trips[k] || 0) / 2); });
                if (JSON.stringify(half) !== JSON.stringify(tr.trips)) levels.push({ apply: function (x) { tileOf(x, 'travel').trips = clone(half); }, requested: before, alternative: travelSummary({ trips: half }, defaults), why: 'Fewer trips each year' });
                var localOnly = {}; (E.TRIP_KINDS || []).forEach(function (k) { localOnly[k] = k === 'local' ? Math.min(2, tr.trips.local || 0) || 1 : 0; });
                levels.push({ apply: function (x) { tileOf(x, 'travel').trips = clone(localOnly); }, requested: before, alternative: travelSummary({ trips: localOnly }, defaults), why: 'Local getaways instead of bigger trips' });
            }
            levels.push({ apply: function (x) { x.tiles = x.tiles.filter(function (t) { return t.type !== 'travel'; }); }, requested: before, alternative: 'No travel budget for now', why: 'Travel is the first optional cost to trim' });
            if (tryLevels('travel', levels)) return finishAlternative(s, cand, changes, ref, defaults);
        }
        // 2. vehicle cost
        var carLevels = [];
        ['car', 'second_car'].forEach(function (ct) {
            var c = tileOf(cand, ct);
            if (c && !isNum(c.price) && c.tier && c.tier !== 'compact' && defaults.presets && defaults.presets.car && defaults.presets.car.compact) {
                carLevels.push({ ct: ct, from: c.tier });
            }
        });
        if (carLevels.length) {
            var desc = carLevels.map(function (c) { return levelLabel(defaults, 'car', c.from) + (c.ct === 'second_car' ? ' second car' : ' car'); }).join(' + ');
            if (tryLevels('vehicle', [{ apply: function (x) { carLevels.forEach(function (c) { tileOf(x, c.ct).tier = 'compact'; }); }, requested: desc, alternative: 'Compact ' + (carLevels.length > 1 ? 'cars' : 'car'), why: 'Lower car payment, insurance and gas' }])) return finishAlternative(s, cand, changes, ref, defaults);
        }
        // 3. housing option (same family size: only the size/finish level of the home changes)
        var h = tileOf(cand, 'house');
        if (h && !isNum(h.price) && defaults.presets && defaults.presets.house) {
            var tiers = Object.keys(defaults.presets.house);
            var idx = tiers.indexOf(h.tier);
            var hl = [];
            for (var t = idx - 1; t >= 0; t--) {
                (function (tier) {
                    hl.push({ apply: function (x) { var hh = tileOf(x, 'house'); hh.tier = tier; hh.bedrooms = Math.max(defaults.presets.house[tier].bedrooms, 1); }, requested: levelLabel(defaults, 'house', h.tier) + ' home', alternative: levelLabel(defaults, 'house', tier) + ' home', why: 'Smaller deposit and monthly cost' });
                }(tiers[t]));
            }
            if (hl.length && tryLevels('housing', hl)) return finishAlternative(s, cand, changes, ref, defaults);
        }
        // 4. goal timing: move each goal to its calculated age
        var ev = evaluate(cand, ref, defaults, { alternative: false });
        if (!ev.available) return { available: false, feasible: false, reason: 'Some costs for the alternative are not available.', changes: changes };
        var timing = [];
        var allDated = true;
        ev.goals.forEach(function (goal) {
            if (goal.key === 'education') return;
            if (goal.projectedAge === null) { allDated = false; return; }
            if (goal.projectedAge > goal.requestedAge) timing.push(goal);
        });
        if (allDated && timing.length) {
            var next = clone(cand);
            timing.forEach(function (goal) { next.plan.goals[goal.key] = goal.projectedAge; });
            var q = quickFeasible(next, ref, defaults);
            cand = next;
            timing.forEach(function (goal) {
                var gap = (goal.gaps.atRequestedAge[0] || {});
                changes.push({ area: 'timing', goal: goal.key, requested: goal.label + ' at ' + goal.requestedAge, alternative: goal.label + ' at ' + goal.projectedAge,
                    why: (gap.type === 'retirement_funding' ? 'Retirement funding gap' : gap.type === 'monthly_cash_flow' ? 'Monthly cost gap' : 'Upfront cash gap') + (gap.amount ? ' of about ' + usd(gap.amount) + (gap.type === 'monthly_cash_flow' ? '/month' : '') : '') + '; ' + goal.yearsDelayed + ' more year' + (goal.yearsDelayed === 1 ? '' : 's') });
            });
            if (q.ok) return finishAlternative(s, cand, changes, ref, defaults);
        }
        var last = quickFeasible(cand, ref, defaults);
        var reason;
        if (last.sim && last.sim.maxEssentialGap.amount > EPS) reason = 'Everyday expenses still exceed estimated income by ' + usd(last.sim.maxEssentialGap.amount) + '/month at age ' + last.sim.maxEssentialGap.age + '.';
        else if (last.sim && last.sim.unfunded.training > EPS) reason = 'Training-period costs still need about ' + usd(last.sim.unfunded.training) + ' of support.';
        else reason = 'No combination of the allowed changes funds every goal within this timeline.';
        return { available: true, feasible: false, reason: reason, essentialGap: last.sim ? last.sim.maxEssentialGap : null, changes: changes };
    }

    function finishAlternative(original, cand, changes, ref, defaults) {
        var ev = evaluate(cand, ref, defaults, { alternative: false });
        return { available: true, feasible: true, reason: '', changes: changes, scenario: cand, overallStatus: ev.overallStatus, goals: ev.goals, ageSnapshots: ev.ageSnapshots };
    }

    // ------------------------------------------------------------------ main
    function evaluate(s, ref, defaults, options) {
        options = options || {};
        var ctx = context(s, ref, defaults);
        var horizon = { startAge: ctx.startAge, endAge: ctx.endAge, retirementPlanningAge: ctx.planningAge, careerStartAge: ctx.careerStartMonth / 12,
            dollarBasis: "today's dollars", mode: s.timeline && s.timeline.mode === 'projected' ? 'projected' : 'today' };
        var provenance = {
            dataYears: ctx.base.dataYears, citations: ctx.base.citations,
            assumptions: { investmentReturnPct: ctx.A.investmentReturnPct, emergencyReserveMonths: ctx.A.emergencyReserveMonths, trainingLivingMonthly: ctx.A.trainingLivingMonthly,
                wageGrowthPct: horizon.mode === 'projected' ? ctx.A.wageGrowthPct : 0, retirementIncomeMonthly: ctx.plan.retirementIncomeMonthly,
                surplusRule: 'Money left over after planned savings goes to cash; shortfalls use cash first (and savings, then retirement money once retired).' },
            omissions: OMISSIONS, unavailable: ctx.missing
        };
        if (!ctx.available) {
            var noCareer = ctx.missing.some(function (m) { return m.key === 'career' || m.key === 'housing'; });
            return { projectionVersion: VERSION, available: false, horizon: horizon, ageSnapshots: [], goals: [], events: [],
                overallStatus: { code: 'info', message: noCareer ? 'Choose a career and housing to see your future.' : 'Some data is missing, so this future is incomplete.', missing: ctx.missing },
                alternative: null, provenance: provenance };
        }
        var main = simulate(ctx, { retireAge: ctx.retireAge, goals: goalAges(ctx), record: true });
        var goals = buildGoals(ctx, main);
        var ov = overall(goals, main, ctx.endAge);
        var result = {
            projectionVersion: VERSION, available: true, horizon: horizon, ageSnapshots: main.snapshots, goals: goals,
            events: main.events.filter(function (e) { return e.month < ctx.endAge * 12 + 12; }).map(function (e) { return { age: Math.floor(e.month / 12), kind: e.kind, label: e.label }; }),
            unfunded: main.unfunded, overallStatus: ov, alternative: null, provenance: provenance
        };
        if (options.alternative !== false && ov.code !== 'achievable') result.alternative = alternative(s, ref, defaults);
        return result;
    }

    return { evaluate: evaluate, plan: plan, PLAN_DEFAULTS: PLAN_DEFAULTS, VERSION: VERSION, STATUS_TEXT: STATUS_TEXT };
}));
