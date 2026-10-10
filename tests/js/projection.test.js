/*
 * Age-projection checks (Node). Uses frozen scenario fixtures, not live downloads.
 *   node tests/js/projection.test.js
 *   node tests/js/projection.test.js --parity   (server on :42005) JS vs CFML
 */
'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert');
const P = require('../../assets/js/projection.js');

const FIX_DIR = path.join(__dirname, '..', 'fixtures', 'scenarios');
const BASE = process.env.APP_BASE_URL || 'http://127.0.0.1:42005';
const near = (a, b, tol, msg) => assert.ok(Math.abs(a - b) <= (tol === undefined ? 0.5 : tol), `${msg}: ${a} vs ${b}`);
const load = (name) => JSON.parse(fs.readFileSync(path.join(FIX_DIR, name + '.json'), 'utf8'));

function evalFx(name, extra) {
    const fx = load(name);
    const s = Object.assign({}, fx.scenario, extra || {});
    return { fx, s, p: P.evaluate(s, fx.reference, fx.reference.assumptions, { alternative: false }) };
}

function snap(p, age) { return p.ageSnapshots.filter((s) => s.age === age)[0]; }
function goal(p, key) { return p.goals.filter((g) => g.key === key)[0]; }

function handChecked() {
    const missing = evalFx('orlando_missing_wage');
    assert.strictEqual(missing.p.available, false, 'missing wage is incomplete');
    assert.strictEqual(missing.p.overallStatus.code, 'info');
    assert.ok(missing.p.overallStatus.missing.some((m) => m.key === 'career'));
    assert.strictEqual(missing.p.ageSnapshots.length, 0);
    assert.ok(missing.p.goals.every((g) => !g || g.status === 'info') || missing.p.goals.length === 0);

    const rent = evalFx('va_fastfood_parttime_custom');
    assert.strictEqual(rent.p.available, true, 'custom rent + career is complete');
    [20, 30, 40, 50, 60, 70].forEach((a) => assert.ok(snap(rent.p, a), 'snapshot ' + a));
    assert.ok(snap(rent.p, 20).stage === 'working' || snap(rent.p, 20).stage === 'training');

    const family = evalFx('orlando_teacher_family');
    assert.strictEqual(family.p.available, true);
    [20, 30, 40, 50, 60, 70].forEach((a) => assert.ok(snap(family.p, a), 'family snapshot ' + a));
    family.p.goals.forEach((g) => {
        assert.ok(['on_track', 'later', 'not_achievable', 'info'].indexOf(g.status) >= 0, g.key + ' status');
        assert.ok(g.requestedAge > 0);
        assert.ok(g.gaps && Array.isArray(g.gaps.atRequestedAge) && Array.isArray(g.gaps.atEndAge));
        g.gaps.atRequestedAge.forEach((x) => assert.ok(['upfront_cash', 'monthly_cash_flow', 'retirement_funding'].indexOf(x.type) >= 0, x.type));
        if (g.status === 'later') assert.ok(g.projectedAge !== null && g.projectedAge > g.requestedAge, g.key + ' delay');
        if (g.status === 'not_achievable' && g.key !== 'education') assert.strictEqual(g.projectedAge, null, g.key + ' unmet age');
    });

    const house = goal(family.p, 'house');
    if (house && house.projectedAge !== null) {
        assert.ok(house.projectedAge !== 50 || house.requestedAge === 50 || house.yearsDelayed !== undefined);
        const buy = family.p.events.filter((e) => e.kind === 'house')[0];
        if (buy) assert.strictEqual(buy.age, house.projectedAge);
    }

    const richer = evalFx('orlando_teacher_family', { plan: Object.assign({}, P.PLAN_DEFAULTS, { startingCash: 200000, startingInvestments: 50000 }) });
    const poorer = evalFx('orlando_teacher_family', { plan: Object.assign({}, P.PLAN_DEFAULTS, { startingCash: 0, startingInvestments: 0 }) });
    const cashRich = snap(richer.p, 20).balances.cash;
    const cashPoor = snap(poorer.p, 20).balances.cash;
    assert.ok(cashRich > cashPoor, 'starting cash changes the trajectory');

    const noKids = JSON.parse(JSON.stringify(family.s));
    noKids.tiles = noKids.tiles.filter((t) => t.type !== 'children' && t.type !== 'childcare');
    const withoutKids = P.evaluate(noKids, family.fx.reference, family.fx.reference.assumptions, { alternative: false });
    const withKids = snap(family.p, 35);
    const sansKids = snap(withoutKids, 35);
    if (withKids && sansKids) assert.ok(withKids.kidsHome >= 0 && sansKids.kidsHome === 0, 'children only from explicit tiles');

    const nyc = evalFx('nyc_developer_roommate');
    assert.strictEqual(nyc.p.available, true);
    const s30 = snap(nyc.p, 30);
    const allocated = nyc.p.ageSnapshots.reduce((n, row) => n + row.savingsAllocatedMonthly * 12, 0);
    assert.ok(allocated >= 0, 'savings allocations are non-negative');
    assert.ok(s30.balances.homeEquity === 0 || s30.housing === 'own', 'home equity only after purchase');

    const original = JSON.stringify(family.s);
    const withAlt = P.evaluate(family.s, family.fx.reference, family.fx.reference.assumptions);
    assert.strictEqual(JSON.stringify(family.s), original, 'evaluate does not mutate the requested scenario');
    if (withAlt.alternative && withAlt.alternative.scenario) {
        assert.notStrictEqual(JSON.stringify(withAlt.alternative.scenario), original);
        assert.strictEqual(withAlt.alternative.scenario.cbsa, family.s.cbsa);
        assert.strictEqual(withAlt.alternative.scenario.earners[0].soc, family.s.earners[0].soc);
        const kidsBefore = (family.s.tiles || []).some((t) => t.type === 'children');
        const kidsAfter = (withAlt.alternative.scenario.tiles || []).some((t) => t.type === 'children');
        assert.strictEqual(kidsAfter, kidsBefore, 'alternative never removes children');
    }

    const noHouse = JSON.parse(JSON.stringify(rent.s));
    noHouse.tiles = noHouse.tiles.filter((t) => t.type !== 'apartment' && t.type !== 'house');
    const incomplete = P.evaluate(noHouse, rent.fx.reference, rent.fx.reference.assumptions, { alternative: false });
    assert.strictEqual(incomplete.available, false);
    assert.ok(incomplete.overallStatus.missing.some((m) => m.key === 'housing'));
    assert.ok(!/never/i.test(incomplete.overallStatus.message));

    console.log('ok projection hand-checked cases');
}

async function parity() {
    const names = ['orlando_teacher_family', 'nyc_developer_roommate', 'orlando_missing_wage', 'va_fastfood_parttime_custom'];
    for (const name of names) {
        const { s, p, fx } = evalFx(name);
        const res = await fetch(BASE + '/api/v1/simulations/calculate', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ scenario: s }) });
        const json = await res.json();
        if (!json.success) throw new Error(name + ': ' + json.message);
        const srv = json.data.result.projection;
        assert.strictEqual(p.available, srv.available, name + ' available');
        assert.strictEqual(p.overallStatus.code, srv.overallStatus.code, name + ' overall');
        if (!p.available) continue;
        assert.strictEqual(p.ageSnapshots.length, srv.ageSnapshots.length, name + ' snapshot count');
        [20, 30, 40, 50, 60, 70].forEach((a) => {
            const aJ = snap(p, a), aS = snap(srv, a);
            near(aJ.takeHomeMonthly, aS.takeHomeMonthly, 0.05, name + ' take-home ' + a);
            near(aJ.plannedSpendingMonthly, aS.plannedSpendingMonthly, 0.05, name + ' spend ' + a);
            near(aJ.balances.cash, aS.balances.cash, 1, name + ' cash ' + a);
        });
        assert.strictEqual(p.goals.length, srv.goals.length, name + ' goal count');
        p.goals.forEach((g, i) => {
            assert.strictEqual(g.key, srv.goals[i].key);
            assert.strictEqual(g.status, srv.goals[i].status, name + ' ' + g.key + ' status');
            assert.strictEqual(g.projectedAge, srv.goals[i].projectedAge, name + ' ' + g.key + ' age');
        });
        console.log('ok JS/CFML parity', name);
        void fx;
    }
}

(async () => {
    try {
        handChecked();
        if (process.argv.includes('--parity')) await parity();
        console.log('ALL PROJECTION TESTS PASSED');
    } catch (e) {
        console.error('FAILED:', e.message);
        process.exit(1);
    }
})();
