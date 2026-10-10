/*
 * Browser-engine tests (Node, no dependencies).
 *   node tests/js/engine.test.js              verify engine.js against frozen fixtures + hand-checked cases
 *   node tests/js/engine.test.js --generate   (server running) rebuild fixtures from live reference bundles and
 *                                              assert the JS engine matches the server's CFML calculation
 */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const E = require('../../assets/js/engine.js');

const FIX_DIR = path.join(__dirname, '..', 'fixtures', 'scenarios');
const BASE = process.env.APP_BASE_URL || 'http://127.0.0.1:42005';
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= (tol === undefined ? 0.01 : tol), `${msg}: ${a} vs ${b}`);

const SCENARIOS = {
    orlando_teacher_family: {
        cbsa: '36740', state: 'FL', filingStatus: 'mfj', adults: 2,
        earners: [{ soc: '25-2031', percentile: 'median' }],
        tiles: [{ type: 'house', bedrooms: 3 }, { type: 'car' }, { type: 'second_car' }, { type: 'children', count: 2, ageGroup: 'child_6_8' },
            { type: 'childcare' }, { type: 'savings' }, { type: 'travel' }, { type: 'student_debt' }],
        education: { pathway: 'bachelor', unitid: 132903, cip: '23.01' }, timeline: { mode: 'today' }
    },
    nyc_developer_roommate: {
        cbsa: '35620', state: 'NY', nycResident: true, filingStatus: 'single', adults: 1,
        earners: [{ soc: '15-1252', percentile: 'p25' }],
        tiles: [{ type: 'apartment', bedrooms: 2, benchmark: 'acs' }, { type: 'roommates', count: 1 }, { type: 'travel', annual: 3000 }, { type: 'savings', monthly: 400 }],
        education: { pathway: 'bachelor', years: 4, annualNetPrice: 18000, grantsAnnual: 2000, familyAnnual: 4000 }, timeline: { mode: 'projected' },
        assumptions: { wageGrowthPct: 1.5, inflationPct: 2.5 }
    },
    dc_unmarried_two_earners: {
        cbsa: '47900', state: 'DC', filingStatus: 'hoh', adults: 2,
        earners: [{ soc: '29-1141', percentile: 'median' }, { soc: '47-2031', percentile: 'p25', workFraction: 0.5 }],
        tiles: [{ type: 'apartment', bedrooms: 2, benchmark: 'hud' }, { type: 'car' }, { type: 'children', count: 1, ageGroup: 'child_2_3' }, { type: 'childcare' }],
        education: { pathway: 'associate', years: 2, annualNetPrice: 9000 }, timeline: { mode: 'today' }
    },
    orlando_missing_wage: {
        cbsa: '36740', state: 'FL', filingStatus: 'single', adults: 1,
        earners: [{ soc: '45-3031', percentile: 'median' }],
        tiles: [{ type: 'apartment', bedrooms: 1 }], education: { pathway: 'work' }, timeline: { mode: 'today' }
    },
    va_fastfood_parttime_custom: {
        cbsa: '47900', state: 'VA', filingStatus: 'single', adults: 1,
        earners: [{ soc: '35-3023', percentile: 'median', workFraction: 0.5 }],
        tiles: [{ type: 'apartment', bedrooms: 0, customRent: 1450 }, { type: 'roommates', count: 1 }], education: { pathway: 'ged' }, timeline: { mode: 'today' }
    }
};

function pick(r) {
    const lines = {};
    r.costs.lines.forEach(l => { lines[l.key] = l.monthly; });
    return {
        complete: r.complete,
        grossAnnual: r.income.grossAnnual,
        taxesTotal: r.income.taxes.total,
        federalIncomeTax: r.income.taxes.federalIncomeTax,
        stateIncomeTax: r.income.taxes.stateIncomeTax,
        localIncomeTax: r.income.taxes.localIncomeTax,
        takeHomeMonthly: r.income.takeHomeMonthly,
        monthlyCosts: r.costs.monthlyTotal,
        monthlySurplus: r.monthlySurplus,
        lines: lines,
        borrowed: r.education.borrowed,
        timeline: r.timeline.map(t => ({ age: t.age, wage: t.wage, takeHome: t.takeHome, cumulativeSurplus: t.cumulativeSurplus, debtBalance: t.debtBalance })),
        earnerWages: r.income.earners.map(e => e.annualWage)
    };
}

function compareResults(a, b, label, tol) {
    tol = tol === undefined ? 0.02 : tol;
    assert.strictEqual(a.complete, b.complete, label + ' complete');
    ['grossAnnual', 'taxesTotal', 'federalIncomeTax', 'stateIncomeTax', 'localIncomeTax', 'takeHomeMonthly', 'monthlyCosts', 'monthlySurplus'].forEach(k => near(a[k], b[k], tol, label + ' ' + k));
    assert.deepStrictEqual(Object.keys(a.lines).sort(), Object.keys(b.lines).sort(), label + ' line keys');
    Object.keys(a.lines).forEach(k => {
        if (a.lines[k] === null || b.lines[k] === null) assert.strictEqual(a.lines[k], b.lines[k], label + ' line ' + k + ' null');
        else near(a.lines[k], b.lines[k], tol, label + ' line ' + k);
    });
    assert.deepStrictEqual(a.earnerWages, b.earnerWages, label + ' earner wages (null stays null)');
    if (a.borrowed === null || b.borrowed === null) assert.strictEqual(a.borrowed, b.borrowed); else near(a.borrowed, b.borrowed, tol, label + ' borrowed');
    a.timeline.forEach((t, i) => { near(t.cumulativeSurplus, b.timeline[i].cumulativeSurplus, Math.max(1, tol), label + ' timeline ' + t.age); });
}

async function api(url, body) {
    const res = await fetch(BASE + url, body ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {});
    const json = await res.json();
    if (!json.success) throw new Error(url + ': ' + json.message);
    return json.data;
}

async function generate() {
    fs.mkdirSync(FIX_DIR, { recursive: true });
    for (const name of Object.keys(SCENARIOS)) {
        const calc = await api('/api/v1/simulations/calculate', { scenario: SCENARIOS[name] });
        const s = calc.scenario;
        const socs = s.earners.map(e => e.soc).filter(Boolean).join(',');
        const ref = await api(`/api/v1/reference/bundle?cbsa=${s.cbsa}&state=${s.state}&nyc=${s.nycResident ? 1 : 0}&socs=${socs}` + (s.education.unitid ? '&unitid=' + s.education.unitid : ''));
        const defaults = ref.assumptions;
        const jsResult = E.compute(s, ref, defaults);
        compareResults(pick(jsResult), pick(calc.result), name + ' (JS vs server CFML)');
        const req = E.requiredGross(s, ref, defaults);
        const serverReq = await api('/api/v1/simulations/reverse-careers', { scenario: s, options: { limit: 5 } });
        if (req === null) assert.strictEqual(serverReq.required, null);
        else near(req.earner1Gross, serverReq.required.earner1Gross, 2, name + ' requiredGross JS vs server');
        fs.writeFileSync(path.join(FIX_DIR, name + '.json'), JSON.stringify({
            name, note: 'Frozen reference data snapshot. Regenerate with: node tests/js/engine.test.js --generate',
            scenario: s, reference: ref, expected: Object.assign(pick(jsResult), { requiredEarner1Gross: req ? req.earner1Gross : null })
        }, null, 1));
        console.log('fixture written + JS/CFML parity ok:', name);
    }
}

function handChecked() {
    // Progressive brackets: 2026 single, $60,000 wages, no pretax. Taxable 60,000 - 16,100 = 43,900.
    // 10% x 12,400 + 12% x (43,900 - 12,400) = 1,240 + 3,780 = 5,020.
    const brackets = [{ lower: 0, upper: 12400, rate: 0.10 }, { lower: 12400, upper: 50400, rate: 0.12 }, { lower: 50400, upper: 105700, rate: 0.22 }];
    near(E.bracketTax(43900, brackets), 5020, 0.001, 'single bracket tax');
    near(E.bracketTax(0, brackets), 0, 0, 'zero income');
    near(E.bracketTax(60000, brackets), 1240 + 4560 + 0.22 * 9600, 0.001, 'crosses third bracket');
    // Loans: zero interest, positive interest, invalid term.
    near(E.amortize(12000, 0, 120).payment, 100, 1e-9, 'zero-rate loan');
    near(E.amortize(10000, 6, 120).payment, 111.0205, 0.001, '6% 10-year loan');
    assert.throws(() => E.amortize(1000, 5, 0), /whole number of months/);
    assert.strictEqual(E.amortize(0, 5, 60).payment, 0);
    near(E.balanceAfter(10000, 6, 120, 120), 0, 0.01, 'paid off');
}

function verifyFixtures() {
    const files = fs.existsSync(FIX_DIR) ? fs.readdirSync(FIX_DIR).filter(f => f.endsWith('.json')) : [];
    assert.ok(files.length > 0, 'no fixtures; run with --generate first');
    files.forEach(f => {
        const fx = JSON.parse(fs.readFileSync(path.join(FIX_DIR, f), 'utf8'));
        const r = E.compute(fx.scenario, fx.reference, fx.reference.assumptions);
        compareResults(pick(r), fx.expected, fx.name, 0.005);
        const req = E.requiredGross(fx.scenario, fx.reference, fx.reference.assumptions);
        assert.strictEqual(req ? req.earner1Gross : null, fx.expected.requiredEarner1Gross, fx.name + ' required gross');
        // Rent and mortgage are mutually exclusive.
        const keys = Object.keys(fx.expected.lines);
        assert.ok(!(keys.includes('rent') && keys.includes('mortgage')), fx.name + ' rent+mortgage');
        // Suppressed / unpublished wages are never turned into numbers.
        r.income.earners.forEach(e => { if (e.status !== 'sourced' && e.status !== 'custom') assert.strictEqual(e.annualWage, null); });
        console.log('ok', fx.name);
    });
}

(async () => {
    try {
        handChecked();
        console.log('ok hand-checked tax and loan cases');
        if (process.argv.includes('--generate')) await generate();
        verifyFixtures();
        console.log('ALL JS ENGINE TESTS PASSED');
    } catch (e) {
        console.error('FAILED:', e.message);
        process.exit(1);
    }
})();
