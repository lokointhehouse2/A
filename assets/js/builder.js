/*
 * FuturePath Future Builder.
 * One normalized `state` (the scenario) drives everything. Every change goes through commit(), which records undo
 * history and re-renders. Reference data (wages, rents, taxes...) comes in cached "bundles" from
 * /api/v1/reference/bundle; budgets are recalculated instantly in the browser with FPEngine.compute().
 * Responses that arrive after a newer request are ignored, so fast changes never show stale numbers.
 * Every drag-and-drop action has a button alternative (Add, Remove, Move up/down, Use).
 */
(function (window, document) {
    'use strict';
    var FP = window.FP, E = window.FPEngine, P = window.FPProjection;
    var bootEl = document.getElementById('fp-boot');
    if (!bootEl || !FP || !E || !P) return;
    var BOOT = JSON.parse(bootEl.textContent);
    var DEF = BOOT.assumptions;
    var $ = function (id) { return document.getElementById(id); };
    var el = FP.el;

    // ------------------------------------------------------------------ tiles
    var TILES = {
        apartment: { icon: '\u{1F3E0}', label: 'Apartment', desc: 'Rent a place (Census median rent)' },
        house: { icon: '\u{1F3E1}', label: 'House', desc: 'Buy a home: cozy to mansion' },
        roommates: { icon: '\u{1F465}', label: 'Roommates', desc: 'Split the rent' },
        car: { icon: '\u{1F697}', label: 'Car', desc: 'Compact, standard or luxury' },
        second_car: { icon: '\u{1F699}', label: 'Second car', desc: 'Another vehicle' },
        children: { icon: '\u{1F476}', label: 'Children', desc: 'How many kids?' },
        childcare: { icon: '\u{1F9F8}', label: 'Daycare', desc: 'Low-end to high-end care' },
        travel: { icon: '✈️', label: 'Travel', desc: 'Getaways, cruises, world trips' },
        savings: { icon: '\u{1F437}', label: 'Savings', desc: 'Money set aside each month' },
        student_debt: { icon: '\u{1F393}', label: 'Student debt', desc: 'Shows up when you pick a degree' }
    };
    var TILE_ORDER = ['apartment', 'house', 'roommates', 'car', 'second_car', 'children', 'childcare', 'travel', 'savings', 'student_debt'];
    var PALETTE_ORDER = TILE_ORDER.filter(function (t) { return t !== 'student_debt'; });
    var SCHOOL_PATHS = ['certificate', 'associate', 'bachelor', 'master', 'doctoral', 'professional', 'medicine'];
    var GRAD_PATHS = ['master', 'doctoral', 'professional', 'medicine'];
    var PRESETS = DEF.presets || { house: {}, car: {}, childcare: {}, travel: {} };
    var LEVEL_ICONS = {
        house: { cozy: '\u{1F3E0}', standard: '\u{1F3E1}', luxurious: '\u{1F3D8}️', mansion: '\u{1F3F0}' },
        car: { compact: '\u{1F697}', standard: '\u{1F699}', luxury: '\u{1F3CE}️' },
        childcare: { low: '\u{1F475}', middle: '\u{1F3EB}', high: '⭐' },
        travel: { local: '\u{1F3D5}️', usa: '\u{1F5FD}', cruise: '\u{1F6F3}️', world: '\u{1F30D}' }
    };
    var MAX_TRIPS = 12;

    function defaultTile(type) {
        switch (type) {
            case 'apartment': return { type: type, bedrooms: 1, benchmark: 'acs', customRent: null };
            case 'house': return { type: type, bedrooms: 3, price: null, tier: 'cozy' };
            case 'roommates': return { type: type, count: 1 };
            case 'car': case 'second_car': return { type: type, price: null, tier: 'standard' };
            case 'children': return { type: type, count: 1, ageGroup: 'child_6_8' };
            case 'childcare': return { type: type, children: null, tier: 'middle' };
            case 'travel': return { type: type, annual: null, trips: { local: 2, usa: 0, cruise: 0, world: 0 } };
            case 'savings': return { type: type, monthly: null };
            case 'student_debt': return { type: type, principal: null };
        }
        return { type: type };
    }

    function defaultScenario() {
        var m = BOOT.featured[0] || { cbsa: '36740', states: ['FL'] };
        return {
            v: 1, cbsa: m.cbsa, state: m.states[0] || '', nycResident: false, taxYear: 2026, filingStatus: 'single', adults: 1,
            earners: [{ soc: '', percentile: 'median', workFraction: 1, customWage: null }],
            tiles: [defaultTile('apartment')],
            education: { pathway: '', years: 0, unitid: null, cip: '', annualNetPrice: null, grantsAnnual: 0, familyAnnual: 0, loanKey: 'direct_undergrad' },
            assumptions: {},
            timeline: { startAge: 18, mode: 'today', ages: [18, 22, 25, 30, 40] },
            plan: JSON.parse(JSON.stringify(P.PLAN_DEFAULTS))
        };
    }

    function num(v, lo, hi, def) { return typeof v === 'number' && isFinite(v) && v >= lo && v <= hi ? v : def; }
    function wholeNum(v, lo, hi, def) { var n = num(v, lo, hi, def); return n === null ? null : Math.round(n); }

    /** Timeline plan from a link, storage or an older saved scenario; missing fields get the documented defaults. */
    function sanitizePlan(raw) {
        var p = JSON.parse(JSON.stringify(P.PLAN_DEFAULTS));
        if (!raw || typeof raw !== 'object') return p;
        p.endAge = wholeNum(raw.endAge, 60, 90, 70);
        p.planningAge = wholeNum(raw.planningAge, p.endAge, 105, Math.max(95, p.endAge));
        ['startingCash', 'startingInvestments', 'startingDebt'].forEach(function (k) { p[k] = num(raw[k], 0, 10000000, 0); });
        p.startingDebtRatePct = num(raw.startingDebtRatePct, 0, 30, 7);
        ['trainingSupportMonthly', 'studyIncomeMonthly', 'retirementIncomeMonthly'].forEach(function (k) { p[k] = num(raw[k], 0, 20000, 0); });
        p.firstChildAge = wholeNum(raw.firstChildAge, 16, 60, 30);
        p.childSpacingYears = wholeNum(raw.childSpacingYears, 1, 10, 2);
        p.childcareYears = wholeNum(raw.childcareYears, 0, 13, 5);
        p.secondEarnerAge = wholeNum(raw.secondEarnerAge, 14, 80, null);
        var g = raw.goals && typeof raw.goals === 'object' ? raw.goals : {};
        p.goals.house = wholeNum(g.house, 14, 90, 30);
        p.goals.car = wholeNum(g.car, 14, 90, null);
        p.goals.travel = wholeNum(g.travel, 14, 90, null);
        p.goals.savings = wholeNum(g.savings, 14, 90, 30);
        p.goals.savingsTarget = num(g.savingsTarget, 0, 10000000, 10000);
        p.goals.retirement = wholeNum(g.retirement, 40, 90, 67);
        return p;
    }

    /** Defensive client-side clean-up of a scenario from a link or storage (the server re-validates). */
    function sanitize(raw) {
        var d = defaultScenario();
        if (!raw || typeof raw !== 'object') return d;
        var s = d;
        if (/^\d{5}$/.test(raw.cbsa || '')) s.cbsa = raw.cbsa;
        if (/^[A-Z]{2}$/.test(raw.state || '')) s.state = raw.state;
        s.nycResident = raw.nycResident === true && s.state === 'NY';
        s.filingStatus = ['single', 'mfj', 'hoh'].indexOf(raw.filingStatus) >= 0 ? raw.filingStatus : 'single';
        s.adults = raw.adults === 2 ? 2 : 1;
        if (Array.isArray(raw.earners) && raw.earners.length) {
            s.earners = raw.earners.slice(0, 2).map(function (e) {
                return {
                    soc: /^\d{2}-\d{4}$/.test(e.soc || '') ? e.soc : '',
                    percentile: ['p10', 'p25', 'median', 'p75', 'p90', 'mean'].indexOf(e.percentile) >= 0 ? e.percentile : 'median',
                    workFraction: num(e.workFraction, 0.1, 1, 1),
                    customWage: num(e.customWage, 0, 5000000, null)
                };
            });
        }
        if (Array.isArray(raw.tiles)) {
            var seen = {};
            s.tiles = raw.tiles.filter(function (t) { return t && TILES[t.type] && !seen[t.type] && (seen[t.type] = true); }).map(function (t) {
                var base = defaultTile(t.type);
                Object.keys(base).forEach(function (k) { if (k !== 'type' && k !== 'trips' && t[k] !== undefined) base[k] = t[k]; });
                var group = { house: 'house', car: 'car', second_car: 'car', childcare: 'childcare' }[t.type];
                if (group && !PRESETS[group][base.tier]) base.tier = defaultTile(t.type).tier;
                if (t.type === 'apartment') { base.benchmark = 'acs'; base.customRent = null; }
                if (t.type === 'travel' && t.trips && typeof t.trips === 'object') {
                    E.TRIP_KINDS.forEach(function (k) { base.trips[k] = Math.round(num(t.trips[k], 0, MAX_TRIPS, 0)); });
                }
                return base;
            });
        }
        if (raw.education && typeof raw.education === 'object') {
            var ed = raw.education;
            s.education.pathway = /^[a-z_]{1,40}$/.test(ed.pathway || '') ? ed.pathway : '';
            s.education.years = num(ed.years, 0, 15, 0);
            s.education.unitid = num(ed.unitid, 1, 999999999, null);
            s.education.cip = /^\d{2}(\.\d{2}(\d{2})?)?$/.test(ed.cip || '') ? ed.cip : '';
            s.education.annualNetPrice = num(ed.annualNetPrice, 0, 200000, null);
            s.education.grantsAnnual = num(ed.grantsAnnual, 0, 200000, 0);
            s.education.familyAnnual = num(ed.familyAnnual, 0, 200000, 0);
            s.education.loanKey = ['direct_undergrad', 'direct_grad', 'direct_plus'].indexOf(ed.loanKey) >= 0 ? ed.loanKey : 'direct_undergrad';
        }
        if (raw.assumptions && typeof raw.assumptions === 'object') {
            Object.keys(raw.assumptions).forEach(function (k) {
                var def = DEF.items[k];
                if (def) { var v = num(raw.assumptions[k], def.min, def.max, null); if (v !== null) s.assumptions[k] = v; }
            });
        }
        if (raw.timeline && raw.timeline.mode === 'projected') s.timeline.mode = 'projected';
        if (raw.timeline) s.timeline.startAge = wholeNum(raw.timeline.startAge, 14, 40, 18);
        s.plan = sanitizePlan(raw.plan);
        if (s.earners.length === 2) s.adults = 2;
        return s;
    }

    // ------------------------------------------------------------------ state, history, persistence
    var state = defaultScenario();
    var undoStack = [], redoStack = [];
    var lastResult = null;
    var lastProjection = null;
    var ui = { age: null };
    var cache = { occupations: {}, programs: {}, careersForCip: {}, pathways: null, metros: {} };

    function snapshot() { return JSON.stringify(state); }

    function commit(mutator, message, opts) {
        var before = snapshot();
        mutator(state);
        if (snapshot() === before) return;
        undoStack.push(before);
        if (undoStack.length > 60) undoStack.shift();
        redoStack = [];
        afterChange(message, opts);
    }

    function afterChange(message, opts) {
        opts = opts || {};
        if (FP.storage.get('fp.remember') === true) FP.storage.set('fp.scenario', state);
        if (opts.open) modalType = opts.open;
        try { renderAll(); } catch (err) { /* keep the editor usable if a results pane fails */ }
        if (opts.open) openTileModal(opts.open);
        ensureBundle();
        if (message) window.setTimeout(function () {
            var p = lastProjection;
            var s = p && p.available ? snapAt(selectedAge().age) : null;
            FP.announce(message + (p ? '. ' + p.overallStatus.message : '') + (s ? ' At age ' + s.age + ': ' + (s.leftoverMonthly >= 0 ? FP.money(s.leftoverMonthly) + ' left over a month.' : FP.money(-s.leftoverMonthly) + ' short a month.') : ''));
        }, 60);
    }

    function undo() { if (!undoStack.length) return; redoStack.push(snapshot()); state = JSON.parse(undoStack.pop()); afterChange('Undone'); }
    function redo() { if (!redoStack.length) return; undoStack.push(snapshot()); state = JSON.parse(redoStack.pop()); afterChange('Redone'); }

    function hasTile(type) { return state.tiles.some(function (t) { return t.type === type; }); }
    function getTile(type) { return state.tiles.filter(function (t) { return t.type === type; })[0] || null; }

    function addTile(type, index) {
        if (!TILES[type]) return;
        if (hasTile(type)) { openTileModal(type); return; }
        commit(function (s) {
            var t = defaultTile(type);
            if (type === 'roommates') { var apt = s.tiles.filter(function (x) { return x.type === 'apartment'; })[0]; if (apt && apt.bedrooms < 2) apt.bedrooms = 2; }
            if (type === 'children') { /* children change food, healthcare and taxes */ }
            if (index === undefined || index < 0 || index > s.tiles.length) s.tiles.push(t); else s.tiles.splice(index, 0, t);
        }, 'Added ' + TILES[type].label, { open: type });
    }
    function removeTile(type) {
        if (!hasTile(type)) return;
        commit(function (s) { s.tiles = s.tiles.filter(function (t) { return t.type !== type; }); }, 'Removed ' + TILES[type].label);
    }
    function moveTile(type, delta) {
        commit(function (s) {
            var i = s.tiles.findIndex(function (t) { return t.type === type; });
            var j = i + delta;
            if (i < 0 || j < 0 || j >= s.tiles.length) return;
            var t = s.tiles.splice(i, 1)[0];
            s.tiles.splice(j, 0, t);
        }, 'Moved ' + TILES[type].label);
    }
    function updateTile(type, patch, message) {
        commit(function (s) { var t = s.tiles.filter(function (x) { return x.type === type; })[0]; if (t) Object.keys(patch).forEach(function (k) { t[k] = patch[k]; }); }, message);
    }

    // ------------------------------------------------------------------ reference bundles
    var bundles = {};
    var bundleSeq = 0;
    var projSeq = 0;
    var current = { key: '', bundle: null };

    function bundleKey(s) {
        var socs = s.earners.map(function (e) { return e.soc; }).filter(Boolean).sort().join(',');
        return [s.cbsa, s.state, s.nycResident ? 1 : 0, socs, s.education.unitid || ''].join('|');
    }
    function bundleUrl(s) {
        var socs = s.earners.map(function (e) { return e.soc; }).filter(Boolean);
        var q = 'cbsa=' + encodeURIComponent(s.cbsa) + '&state=' + encodeURIComponent(s.state) + '&nyc=' + (s.nycResident ? 1 : 0) + '&socs=' + encodeURIComponent(socs.join(','));
        if (s.education.unitid) q += '&unitid=' + encodeURIComponent(s.education.unitid);
        return '/api/v1/reference/bundle?' + q;
    }
    function fetchBundle(s) {
        var key = bundleKey(s);
        if (bundles[key] && bundles[key].data) return Promise.resolve(bundles[key].data);
        if (bundles[key] && bundles[key].promise) return bundles[key].promise;
        var p = FP.api(bundleUrl(s)).then(function (data) { bundles[key] = { data: data }; return data; }, function (err) { delete bundles[key]; throw err; });
        bundles[key] = { promise: p };
        return p;
    }
    function ensureBundle() {
        var key = bundleKey(state);
        if (current.key === key && current.bundle) { recalc(); return; }
        var mySeq = ++bundleSeq;
        setStale(true);
        fetchBundle(state).then(function (b) {
            if (mySeq !== bundleSeq) return; // a newer request superseded this one
            current = { key: key, bundle: b };
            setStale(false);
            onBundle(b);
            recalc();
        }).catch(function (err) {
            if (mySeq !== bundleSeq) return;
            setStale(false);
            showBudgetError(err.message);
        });
    }
    function setStale(on) { $('staleBadge').hidden = !on; $('budgetPanel').classList.toggle('is-stale', on); }

    function recalc() {
        if (!current.bundle || current.key !== bundleKey(state)) return; // waiting for data; keep showing the previous result
        try {
            lastResult = E.compute(state, current.bundle, DEF);
        } catch (e) {
            showBudgetError(e.message);
            return;
        }
        renderPathSummary();
        renderTileModal();
        refreshCompareFromState();
        var snap = snapshot(), bundle = current.bundle, my = ++projSeq;
        setStale(true);
        window.setTimeout(function () {
            if (my !== projSeq) return;
            try {
                lastProjection = P.evaluate(JSON.parse(snap), bundle, DEF, { alternative: false });
            } catch (e) {
                if (my !== projSeq) return;
                setStale(false);
                showBudgetError(e.message);
                return;
            }
            if (my !== projSeq) return;
            setStale(false);
            try { renderResults(); } catch (err) { /* tile editing must stay responsive */ }
            scheduleAlternative();
        }, 0);
    }

    function onBundle(b) {
        cache.metros[b.metro.cbsa] = b.metro;
        Object.keys(b.occupations || {}).forEach(function (soc) { cache.occupations[soc] = b.occupations[soc]; });
        renderMetro(b);
        renderCanvas();
    }

    // ------------------------------------------------------------------ rendering: palette & canvas
    function renderPalette() {
        var pal = $('palette');
        pal.textContent = '';
        PALETTE_ORDER.forEach(function (type) {
            var t = TILES[type];
            var active = hasTile(type);
            var li = el('li', { class: 'tile-card' + (active ? ' is-active' : ''), draggable: active ? null : 'true', dataset: { tile: type } }, [
                el('span', { class: 'tile-icon', 'aria-hidden': 'true', text: t.icon }),
                el('span', { class: 'tile-text' }, [el('span', { class: 'tile-label', text: t.label }), el('span', { class: 'tile-desc', text: t.desc })]),
                el('button', { type: 'button', class: 'btn btn-sm ' + (active ? 'btn-light' : 'btn-outline-primary'), disabled: active, 'aria-label': active ? t.label + ' is in My Future' : 'Add ' + t.label + ' to My Future', 'aria-haspopup': 'dialog',
                    onclick: function () { addTile(type); } }, [active ? 'Added' : 'Add'])
            ]);
            li.addEventListener('dragstart', function (e) { e.dataTransfer.setData('text/plain', JSON.stringify({ kind: 'tile', type: type })); e.dataTransfer.effectAllowed = 'copy'; li.classList.add('is-dragging'); });
            li.addEventListener('dragend', function () { li.classList.remove('is-dragging'); });
            pal.appendChild(li);
        });
    }

    function focusCanvasTile(type) {
        window.setTimeout(function () { var b = document.querySelector('#canvas [data-tile="' + type + '"] .tile-toggle'); if (b) b.focus(); }, 30);
    }

    function bedLabel(n) { return n === 0 ? 'Studio' : n + ' bedroom' + (n > 1 ? 's' : ''); }
    function acsRent(n) { var b = current.bundle; return b && b.housing.acs.rents ? b.housing.acs.rents[String(n)] : null; }
    function housePrice(tier) {
        var b = current.bundle, p = PRESETS.house[tier];
        return b && b.housing.homeValue ? b.housing.homeValue.value * (p ? p.priceMultiplier : 1) : null;
    }
    function carPrice(tier) { var p = PRESETS.car[tier]; return assumption('carPrice') * (p ? p.priceMultiplier : 1); }
    function careRate(tier) { var p = PRESETS.childcare[tier]; return assumption('childcareMonthlyPerChild') * (p ? p.costMultiplier : 1); }
    function travelers() { var k = getTile('children'); return state.adults + (k ? k.count : 0); }
    function travelAnnual(trips) {
        var people = travelers();
        return E.TRIP_KINDS.reduce(function (sum, k) { var p = PRESETS.travel[k]; return sum + (p ? (trips[k] || 0) * p.costPerPerson * people : 0); }, 0);
    }
    function tripsSummary(trips) {
        var parts = E.TRIP_KINDS.filter(function (k) { return trips[k] > 0 && PRESETS.travel[k]; }).map(function (k) { return trips[k] + ' ' + PRESETS.travel[k].label.toLowerCase(); });
        return parts.length ? parts.join(', ') : 'No trips planned';
    }

    function tileSummary(t) {
        var level;
        switch (t.type) {
            case 'apartment': return bedLabel(t.bedrooms) + ' · ' + FP.money(acsRent(t.bedrooms), { fallback: 'rent not published' }) + '/mo Census median';
            case 'house':
                level = PRESETS.house[t.tier];
                if (t.price !== null) return FP.money(t.price) + ' home';
                return (level ? level.label + ' · ' + level.size : 'Metro median home') + (housePrice(t.tier) !== null ? ' · ' + FP.money(housePrice(t.tier)) : '');
            case 'roommates': return t.count + ' roommate' + (t.count > 1 ? 's' : '');
            case 'car': case 'second_car':
                level = PRESETS.car[t.tier];
                return (level ? level.label + ' · ' : '') + FP.money(t.price !== null ? t.price : carPrice(t.tier)) + (level ? ' · like a ' + level.examples.split(',')[0] : ' car');
            case 'children': return t.count + ' child' + (t.count > 1 ? 'ren' : '');
            case 'childcare':
                level = PRESETS.childcare[t.tier];
                return (level ? level.label + ' · ' : '') + FP.money(careRate(t.tier)) + '/child · ' + (t.children === null ? 'all children' : t.children + ' in care');
            case 'travel':
                if (t.annual !== null) return FP.money(t.annual) + ' per year';
                return tripsSummary(t.trips) + ' · ' + FP.money(travelAnnual(t.trips)) + '/yr';
            case 'savings': return FP.money(t.monthly !== null ? t.monthly : assumption('emergencySavingsMonthly')) + ' per month';
            case 'student_debt':
                if (t.principal !== null) return FP.money(t.principal) + ' borrowed';
                return lastResult && lastResult.education.borrowed !== null ? FP.money(lastResult.education.borrowed) + ' from your school choice' : 'From your school choice';
        }
        return '';
    }
    function assumption(k) { return state.assumptions[k] !== undefined ? state.assumptions[k] : DEF.items[k].value; }

    function segControl(label, options, value, onPick) {
        var wrap = el('div', { class: 'seg seg-sm', role: 'radiogroup', 'aria-label': label });
        options.forEach(function (o) {
            wrap.appendChild(el('button', { type: 'button', role: 'radio', 'aria-checked': String(o.value === value), onclick: function () { onPick(o.value); } }, [o.label]));
        });
        return wrap;
    }
    function numberField(id, label, value, placeholder, onChange, attrs) {
        attrs = attrs || {};
        var input = el('input', { class: 'form-control form-control-sm', type: 'number', id: id, inputmode: 'decimal', min: attrs.min || '0', max: attrs.max || null, step: attrs.step || 'any', value: value === null || value === undefined ? '' : String(value), placeholder: placeholder || '' });
        input.addEventListener('change', function () { var v = input.value.trim(); onChange(v === '' ? null : Number(v)); });
        return el('div', { class: 'mb-2' }, [el('label', { class: 'form-label small mb-0', for: id, text: label }), input]);
    }

    // ------------------------------------------------------------------ tile modal
    // Every card is edited in one pop-up with big picture options. Choices apply immediately (the budget behind the
    // dialog updates live); Done closes it and Undo still works.
    var modalType = null, modal = null;

    /** Monthly cost this card adds to the budget (with the card vs without it), or null while data loads. */
    function monthlyWith(type, patch) {
        if (!current.bundle) return null;
        var without = JSON.parse(JSON.stringify(state));
        without.tiles = without.tiles.filter(function (t) { return t.type !== type; });
        var withIt = JSON.parse(JSON.stringify(state));
        var t = withIt.tiles.filter(function (x) { return x.type === type; })[0];
        if (!t) { t = defaultTile(type); withIt.tiles.push(t); }
        Object.keys(patch || {}).forEach(function (k) { t[k] = patch[k]; });
        if (type === 'apartment') withIt.tiles = withIt.tiles.filter(function (x) { return x.type !== 'house'; });
        try {
            return E.compute(withIt, current.bundle, DEF, { includeTimeline: false }).costs.monthlyTotal - E.compute(without, current.bundle, DEF, { includeTimeline: false }).costs.monthlyTotal;
        } catch (e) { return null; }
    }
    function perMonth(v) { return v === null ? '…' : (v < 0 ? 'saves ' + FP.money(-v) : 'about ' + FP.money(v)) + '/mo'; }

    /** Big radio cards: [{ value, icon, title, sub, examples, cue }]. */
    function optionGrid(label, idPrefix, options, value, onPick) {
        var grid = el('div', { class: 'opt-grid', role: 'radiogroup', 'aria-label': label });
        options.forEach(function (o) {
            grid.appendChild(el('button', { type: 'button', class: 'opt-card', role: 'radio', id: idPrefix + '-' + o.value, 'aria-checked': String(o.value === value), dataset: { value: String(o.value) },
                onclick: function () { onPick(o.value); } }, [
                o.icon ? el('span', { class: 'opt-icon', 'aria-hidden': 'true', text: o.icon }) : null,
                el('span', { class: 'opt-title', text: o.title }),
                o.sub ? el('span', { class: 'opt-sub', text: o.sub }) : null,
                o.examples ? el('span', { class: 'opt-examples', text: o.examples }) : null,
                o.cue ? el('span', { class: 'opt-cue', text: o.cue }) : null
            ]));
        });
        return grid;
    }
    function levelOptions(group, mapCue) {
        return Object.keys(PRESETS[group] || {}).map(function (k) {
            var p = PRESETS[group][k];
            return { value: k, icon: LEVEL_ICONS[group][k], title: p.label, sub: p.size || '', examples: p.examples, cue: mapCue(k, p) };
        });
    }
    function note(text) { return el('p', { class: 'small text-body-secondary mt-3 mb-0', text: text }); }
    function heading(text) { return el('h3', { class: 'h6 mt-3 mb-2', text: text }); }

    function modalBody(t) {
        var box = el('div');
        var b = current.bundle;
        switch (t.type) {
            case 'apartment':
                box.appendChild(el('p', { class: 'mb-2', text: 'How many bedrooms?' }));
                box.appendChild(optionGrid('Bedrooms', 'opt-apt', [0, 1, 2, 3, 4].map(function (n) {
                    return { value: n, icon: n === 0 ? '\u{1F6CB}️' : '\u{1F6CF}️'.repeat(Math.min(n, 3)) + (n > 3 ? '+' : ''), title: bedLabel(n), cue: FP.money(acsRent(n), { fallback: 'not published' }) + '/mo rent' };
                }), t.bedrooms, function (v) { updateTile('apartment', { bedrooms: v }, 'Apartment set to ' + bedLabel(v).toLowerCase()); }));
                box.appendChild(note('Census median rent for this metro' + (b && b.housing.acs.period ? ' (ACS ' + b.housing.acs.period + ')' : '') + ', utilities included. Half of renters pay less, half pay more.'));
                break;
            case 'house':
                box.appendChild(el('p', { class: 'mb-2', text: 'What kind of home do you see yourself in?' }));
                box.appendChild(optionGrid('Home style', 'opt-house', levelOptions('house', function (k) {
                    var price = housePrice(k);
                    return (price !== null ? FP.money(price) + ' · ' : '') + perMonth(monthlyWith('house', { tier: k, price: null }));
                }), t.price === null ? t.tier : null, function (v) { updateTile('house', { tier: v, price: null, bedrooms: PRESETS.house[v].bedrooms }, PRESETS.house[v].label + ' home'); }));
                box.appendChild(note('Prices start from the metro median home value' + (b && b.housing.homeValue ? ' (' + FP.money(b.housing.homeValue.value) + ', ' + b.housing.homeValue.period + ')' : '') + ' and scale up with size. Monthly cost includes mortgage, property tax, insurance, maintenance and utilities with ' + assumption('downPaymentPct') + '% down at ' + assumption('mortgageRatePct') + '% (change in advanced assumptions).'));
                break;
            case 'car': case 'second_car':
                box.appendChild(el('p', { class: 'mb-2', text: 'What kind of car?' }));
                box.appendChild(optionGrid('Car type', 'opt-' + t.type, levelOptions('car', function (k) {
                    return FP.money(carPrice(k)) + ' · ' + perMonth(monthlyWith(t.type, { tier: k, price: null }));
                }), t.price === null ? t.tier : null, function (v) { updateTile(t.type, { tier: v, price: null }, PRESETS.car[v].label + ' car'); }));
                box.appendChild(note('Monthly cost includes the loan payment, insurance, gas and maintenance. Fancier cars cost more to insure and run.'));
                break;
            case 'children':
                box.appendChild(el('p', { class: 'mb-2', text: 'How many kids?' }));
                box.appendChild(optionGrid('Number of children', 'opt-kids', [1, 2, 3, 4, 5, 6].map(function (n) {
                    return { value: n, icon: '\u{1F9D2}'.repeat(Math.min(n, 3)) + (n > 3 ? '+' : ''), title: n + (n === 1 ? ' child' : ' children'), cue: perMonth(monthlyWith('children', { count: n })) };
                }), t.count, function (v) { updateTile('children', { count: v }, v + (v === 1 ? ' child' : ' children')); }));
                box.appendChild(note('Kids change groceries (USDA food plans), health costs and taxes (Child Tax Credit). Add Daycare if they need care while you work.'));
                break;
            case 'childcare':
                var kids = getTile('children') ? getTile('children').count : 0;
                if (!kids) {
                    box.appendChild(el('div', { class: 'alert alert-info d-flex flex-wrap align-items-center gap-2' }, [
                        el('span', { class: 'me-auto', text: 'Daycare needs kids. Add the Children card first.' }),
                        el('button', { type: 'button', class: 'btn btn-sm btn-primary', onclick: function () { addTile('children'); } }, ['Add children'])
                    ]));
                }
                box.appendChild(el('p', { class: 'mb-2', text: 'What kind of daycare?' }));
                box.appendChild(optionGrid('Daycare level', 'opt-care', levelOptions('childcare', function (k) { return FP.money(careRate(k)) + ' per child/mo'; }), t.tier, function (v) { updateTile('childcare', { tier: v }, PRESETS.childcare[v].label + ' daycare'); }));
                if (kids > 1) {
                    box.appendChild(heading('How many kids in daycare?'));
                    box.appendChild(segControl('Children in care', Array.from({ length: kids }, function (_, i) { return { value: i + 1 === kids ? null : i + 1, label: i + 1 === kids ? 'All ' + kids : String(i + 1) }; }), t.children, function (v) { updateTile('childcare', { children: v }, 'Childcare updated'); }));
                }
                box.appendChild(note('Full-time care prices vary a lot by city and age; babies cost the most. Middle is ' + FP.money(assumption('childcareMonthlyPerChild')) + ' per child (change in advanced assumptions).'));
                break;
            case 'travel':
                box.appendChild(el('p', { class: 'mb-2', text: 'What kind of trips, and how many times a year?' }));
                var trips = t.trips || { local: 0, usa: 0, cruise: 0, world: 0 };
                var people = travelers();
                var list = el('div', { class: 'trip-list' });
                E.TRIP_KINDS.forEach(function (k) {
                    var p = PRESETS.travel[k];
                    if (!p) return;
                    var n = trips[k] || 0;
                    var setN = function (v) {
                        var next = Object.assign({}, trips); next[k] = Math.max(0, Math.min(MAX_TRIPS, v));
                        updateTile('travel', { trips: next, annual: null }, p.label + ': ' + next[k] + ' a year');
                    };
                    list.appendChild(el('div', { class: 'trip-card' + (n > 0 ? ' is-on' : '') }, [
                        el('span', { class: 'opt-icon', 'aria-hidden': 'true', text: LEVEL_ICONS.travel[k] }),
                        el('div', { class: 'trip-text' }, [
                            el('span', { class: 'opt-title', text: p.label }),
                            el('span', { class: 'opt-examples', text: p.examples }),
                            el('span', { class: 'opt-cue', text: 'about ' + FP.money(p.costPerPerson) + ' per person per trip' })
                        ]),
                        el('div', { class: 'stepper', role: 'group', 'aria-label': p.label + ' per year' }, [
                            el('button', { type: 'button', class: 'icon-btn', id: 'trip-' + k + '-minus', 'aria-label': 'Fewer ' + p.label.toLowerCase(), disabled: n <= 0, onclick: function () { setN(n - 1); } }, ['−']),
                            el('span', { class: 'stepper-value', 'aria-live': 'polite', text: n + 'x/yr' }),
                            el('button', { type: 'button', class: 'icon-btn', id: 'trip-' + k + '-plus', 'aria-label': 'More ' + p.label.toLowerCase(), disabled: n >= MAX_TRIPS, onclick: function () { setN(n + 1); } }, ['+'])
                        ])
                    ]));
                });
                box.appendChild(list);
                var yearly = t.annual !== null ? t.annual : travelAnnual(trips);
                box.appendChild(el('div', { class: 'trip-total' }, [
                    el('span', { text: 'Travel budget: ' }),
                    el('strong', { text: FP.money(yearly) + ' a year' }),
                    el('span', { text: ' (' + FP.money(yearly / 12) + '/mo) for ' + people + ' traveler' + (people === 1 ? '' : 's') })
                ]));
                box.appendChild(note('Costs are typical per person and include getting there, a place to stay, food and fun. Everyone in your household travels.'));
                break;
            case 'roommates':
                box.appendChild(el('p', { class: 'mb-2', text: 'How many roommates?' }));
                box.appendChild(optionGrid('Number of roommates', 'opt-roomies', [1, 2, 3, 4].map(function (n) {
                    return { value: n, icon: '\u{1F9CD}'.repeat(n), title: n + ' roommate' + (n > 1 ? 's' : ''), cue: perMonth(monthlyWith('roommates', { count: n })) };
                }), t.count, function (v) { updateTile('roommates', { count: v }, v + ' roommates'); }));
                box.appendChild(note('Rent is split evenly. Pick enough bedrooms in the Apartment card so everyone has a room.'));
                break;
            case 'savings':
                box.appendChild(numberField('savings-monthly', 'Save each month', t.monthly, 'Default ' + FP.money(assumption('emergencySavingsMonthly')), function (v) { updateTile('savings', { monthly: v }, 'Savings updated'); }, { max: 20000 }));
                box.appendChild(numberField('retire-pct', 'Pre-tax retirement (% of pay)', assumption('retirementPct'), '', function (v) { setAssumption('retirementPct', v); }, { max: 30 }));
                break;
            case 'student_debt':
                var fromSchool = lastResult && lastResult.education.borrowed !== null ? lastResult.education.borrowed : null;
                var hasDegree = SCHOOL_PATHS.indexOf(state.education.pathway) >= 0;
                box.appendChild(el('div', { class: 'need-box' }, hasDegree ? [
                    el('div', { class: 'small', text: 'From your school choice in step 3' }),
                    el('div', { class: 'need-amount', text: fromSchool !== null ? FP.money(fromSchool) + ' borrowed' : 'Pick a college to estimate' }),
                    el('div', { class: 'small', text: lastResult && lastResult.education.monthlyPayment ? FP.money(lastResult.education.monthlyPayment) + '/mo for 10 years' : '' })
                ] : [el('div', { text: 'Pick a degree path in step 3 and your student debt shows up here automatically.' })]));
                box.appendChild(heading('Loan type'));
                var loanSel = el('select', { class: 'form-select form-select-sm mb-2', 'aria-label': 'Loan type' });
                [['direct_undergrad', 'Federal undergraduate loan'], ['direct_grad', 'Federal graduate loan'], ['direct_plus', 'PLUS loan']].forEach(function (o) {
                    var opt = el('option', { value: o[0], text: o[1] + (b && b.loans[o[0]] ? ' (' + b.loans[o[0]].rate + '%)' : '') }); if (state.education.loanKey === o[0]) opt.selected = true; loanSel.appendChild(opt);
                });
                loanSel.addEventListener('change', function () { commit(function (s) { s.education.loanKey = loanSel.value; }, 'Loan type changed'); });
                box.appendChild(loanSel);
                box.appendChild(numberField('debt-principal', 'Or enter the amount you expect to borrow', t.principal, fromSchool !== null ? FP.money(fromSchool) : 'Amount', function (v) { updateTile('student_debt', { principal: v }, 'Student debt updated'); }, { max: 1000000 }));
                break;
        }
        return box;
    }

    function renderTileModal() {
        if (!modalType) return;
        var t = getTile(modalType);
        var root = $('tileModal');
        if (!t) { if (modal) modal.hide(); return; }
        var focusedId = document.activeElement && root.contains(document.activeElement) ? document.activeElement.id : null;
        $('tileModalTitle').textContent = TILES[t.type].icon + ' ' + TILES[t.type].label;
        var body = $('tileModalBody');
        body.textContent = '';
        body.appendChild(modalBody(t));
        var add = null;
        try { add = monthlyWith(t.type, {}); } catch (err) { add = null; }
        $('tileModalCost').textContent = add === null ? '' : (add < 0 ? 'Saves you ' + FP.money(-add) + ' a month' : 'Adds about ' + FP.money(add) + ' a month');
        $('tileModalRemove').setAttribute('aria-label', 'Remove ' + TILES[t.type].label + ' from My Future');
        if (focusedId && $(focusedId)) $(focusedId).focus();
    }

    function openTileModal(type) {
        if (!hasTile(type)) return;
        modalType = type;
        renderTileModal();
        if (!modal && window.bootstrap) {
            modal = window.bootstrap.Modal.getOrCreateInstance($('tileModal'));
            $('tileModal').addEventListener('hidden.bs.modal', function () { var t = modalType; modalType = null; if (t) focusCanvasTile(t); });
            $('tileModalRemove').addEventListener('click', function () { var t = modalType; if (modal) modal.hide(); if (t) removeTile(t); });
        }
        if (modal) modal.show();
    }

    function setAssumption(key, value) {
        var def = DEF.items[key];
        commit(function (s) {
            if (value === null || value === undefined || !isFinite(value)) delete s.assumptions[key];
            else s.assumptions[key] = Math.min(def.max, Math.max(def.min, value));
        }, def.label + ' updated');
    }

    function renderCanvas() {
        var canvas = $('canvas');
        var focusedId = document.activeElement && canvas.contains(document.activeElement) ? document.activeElement.id : null;
        canvas.textContent = '';
        $('canvasEmpty').hidden = state.tiles.length > 0;
        state.tiles.forEach(function (t, i) {
            var meta = TILES[t.type];
            var li = el('li', { class: 'active-tile', draggable: 'true', dataset: { tile: t.type } }, [
                el('div', { class: 'active-tile-head' }, [
                    el('button', { type: 'button', class: 'tile-toggle', id: 'tile-toggle-' + t.type, 'aria-haspopup': 'dialog', 'aria-label': 'Change ' + meta.label + ': ' + tileSummary(t),
                        onclick: function () { openTileModal(t.type); } }, [
                        el('span', { class: 'tile-icon', 'aria-hidden': 'true', text: meta.icon }),
                        el('span', { class: 'tile-text' }, [el('span', { class: 'tile-label', text: meta.label }), el('span', { class: 'tile-desc', text: tileSummary(t) })]),
                        el('span', { class: 'tile-edit', 'aria-hidden': 'true', text: 'Change' })
                    ]),
                    el('div', { class: 'tile-actions' }, [
                        el('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Move ' + meta.label + ' up', disabled: i === 0, onclick: function () { moveTile(t.type, -1); } }, ['↑']),
                        el('button', { type: 'button', class: 'icon-btn', 'aria-label': 'Move ' + meta.label + ' down', disabled: i === state.tiles.length - 1, onclick: function () { moveTile(t.type, 1); } }, ['↓']),
                        el('button', { type: 'button', class: 'icon-btn icon-remove', 'aria-label': 'Remove ' + meta.label, onclick: function () { removeTile(t.type); var n = document.querySelector('#palette [data-tile="' + t.type + '"] button'); if (n) n.focus(); } }, ['×'])
                    ])
                ])
            ]);
            li.addEventListener('dragstart', function (e) {
                if (e.target !== li) return;
                e.dataTransfer.setData('text/plain', JSON.stringify({ kind: 'active', type: t.type }));
                e.dataTransfer.effectAllowed = 'move';
                li.classList.add('is-dragging');
            });
            li.addEventListener('dragend', function () { li.classList.remove('is-dragging'); });
            canvas.appendChild(li);
        });
        if (focusedId && $(focusedId)) $(focusedId).focus();
    }

    // ------------------------------------------------------------------ drag and drop
    function readDrag(e) {
        try { return JSON.parse(e.dataTransfer.getData('text/plain')); } catch (err) { return null; }
    }
    function dropIndex(container, y) {
        var items = Array.prototype.slice.call(container.querySelectorAll('.active-tile'));
        for (var i = 0; i < items.length; i++) {
            var r = items[i].getBoundingClientRect();
            if (y < r.top + r.height / 2) return i;
        }
        return items.length;
    }
    function bindDropZones() {
        var canvas = $('canvas'), palette = $('palette'), slot = $('pathSlot');
        [canvas, palette, slot].forEach(function (z) {
            z.addEventListener('dragover', function (e) { e.preventDefault(); z.classList.add('drag-over'); });
            z.addEventListener('dragleave', function () { z.classList.remove('drag-over'); });
        });
        canvas.addEventListener('drop', function (e) {
            e.preventDefault(); canvas.classList.remove('drag-over');
            var d = readDrag(e); if (!d) return;
            var idx = dropIndex(canvas, e.clientY);
            if (d.kind === 'tile') addTile(d.type, idx);
            else if (d.kind === 'active') {
                commit(function (s) {
                    var from = s.tiles.findIndex(function (t) { return t.type === d.type; });
                    if (from < 0) return;
                    var t = s.tiles.splice(from, 1)[0];
                    s.tiles.splice(from < idx ? idx - 1 : idx, 0, t);
                }, 'Moved ' + TILES[d.type].label);
            }
        });
        palette.addEventListener('drop', function (e) {
            e.preventDefault(); palette.classList.remove('drag-over');
            var d = readDrag(e); if (d && d.kind === 'active') removeTile(d.type);
        });
        slot.addEventListener('drop', function (e) {
            e.preventDefault(); slot.classList.remove('drag-over');
            var d = readDrag(e); if (!d) return;
            if (d.kind === 'career') chooseCareer(d.soc, d.title);
            else if (d.kind === 'program') chooseProgram(d.cip, d.title, d.unitid || null);
            else if (d.kind === 'pathway') choosePathway(d.key);
        });
    }
    function draggableCard(payload, children, attrs) {
        var card = el('div', Object.assign({ class: 'pick-card', draggable: 'true' }, attrs || {}), children);
        card.addEventListener('dragstart', function (e) { e.dataTransfer.setData('text/plain', JSON.stringify(payload)); e.dataTransfer.effectAllowed = 'copy'; });
        return card;
    }

    // ------------------------------------------------------------------ pickers
    function renderMetro(b) {
        var m = b ? b.metro : cache.metros[state.cbsa];
        if (!m) return;
        $('metroInput').value = m.name;
        var hud = b && b.housing.hud.areas.length ? b.housing.hud.areas[0] : null;
        $('metroInfo').textContent = '';
        $('metroInfo').appendChild(el('span', { class: 'text-body-secondary', text: 'CBSA ' + m.cbsa + ' · ' + m.states.map(function (s) { return s.code; }).join(', ') + (b && b.dataYears ? ' · wages May ' + b.dataYears.wages : '') + (hud && hud.quality === 'partial' ? ' · HUD rent area covers part of this metro' : '') }));
        var sel = $('stateSelect');
        sel.textContent = '';
        m.states.forEach(function (s) { var o = el('option', { value: s.code, text: s.name }); if (s.code === state.state) o.selected = true; sel.appendChild(o); });
        $('nycWrap').hidden = !(m.hasNycOption && state.state === 'NY');
        $('nycCheck').checked = state.nycResident;
        document.querySelectorAll('[data-metro]').forEach(function (btn) { btn.setAttribute('aria-pressed', String(btn.dataset.metro === state.cbsa)); });
    }

    function chooseMetro(cbsa, statesHint) {
        commit(function (s) {
            s.cbsa = cbsa;
            var states = statesHint || (cache.metros[cbsa] ? cache.metros[cbsa].states.map(function (x) { return x.code; }) : []);
            if (states.length && states.indexOf(s.state) < 0) s.state = states[0];
            if (s.state !== 'NY') s.nycResident = false;
        }, 'City changed');
    }

    function chooseCareer(soc, title, earnerIndex) {
        var i = earnerIndex || 0;
        if (title) cache.occupations[soc] = cache.occupations[soc] || { title: title };
        commit(function (s) {
            while (s.earners.length <= i) s.earners.push({ soc: '', percentile: 'median', workFraction: 1, customWage: null });
            s.earners[i].soc = soc;
            s.earners[i].customWage = null;
        }, 'Career set to ' + (title || soc));
        if (i === 0) {
            $('careerInput').value = title || '';
            loadPathwaysFor(soc);
        }
    }

    function choosePathway(key) {
        var p = cache.pathways && cache.pathways[key];
        commit(function (s) {
            s.education.pathway = key;
            s.education.years = p ? p.typicalYears : 0;
            s.education.loanKey = GRAD_PATHS.indexOf(key) >= 0 ? 'direct_grad' : 'direct_undergrad';
            if (SCHOOL_PATHS.indexOf(key) < 0) { s.education.unitid = null; s.education.cip = ''; s.education.annualNetPrice = null; }
            syncStudentDebt(s);
        }, 'Path set to ' + (p ? p.name : key));
        $('pathwaySelect').value = key;
        renderSchoolPicker();
    }

    /** Student debt follows the degree: added with a school path, dropped without one (unless the user typed an amount). */
    function syncStudentDebt(s) {
        var debt = s.tiles.filter(function (t) { return t.type === 'student_debt'; })[0];
        var degree = SCHOOL_PATHS.indexOf(s.education.pathway) >= 0;
        if (degree && !debt) s.tiles.push(defaultTile('student_debt'));
        if (!degree && debt && debt.principal === null) s.tiles = s.tiles.filter(function (t) { return t !== debt; });
    }

    function chooseCollege(inst) {
        commit(function (s) {
            s.education.unitid = inst.unitid;
            s.education.cip = '';
            if (!s.education.pathway || SCHOOL_PATHS.indexOf(s.education.pathway) < 0) {
                var map = { Certificate: 'certificate', Associate: 'associate', "Bachelor's": 'bachelor', Graduate: 'bachelor' };
                var key = map[inst.predominantDegree] || 'bachelor';
                s.education.pathway = key;
                s.education.years = cache.pathways && cache.pathways[key] ? cache.pathways[key].typicalYears : 4;
            }
            syncStudentDebt(s);
        }, inst.name + ' selected; Student debt is in My Future');
        $('collegeInput').value = inst.name;
        loadPrograms(inst.unitid);
    }

    function chooseProgram(cip, title, unitid) {
        commit(function (s) { s.education.cip = cip; if (unitid) s.education.unitid = unitid; }, 'Program set to ' + title);
        loadCareersForCip(cip, title);
    }

    function loadPathwaysFor(soc) {
        if (!soc) return;
        FP.api('/api/v1/occupations/' + soc + '/pathways').then(function (d) {
            cache.occupations[soc] = cache.occupations[soc] || {};
            cache.occupations[soc].pathways = d.pathways;
            renderPathSummary();
        }).catch(function () { /* optional */ });
    }

    function loadPrograms(unitid) {
        var sel = $('programSelect');
        sel.disabled = true;
        sel.textContent = '';
        sel.appendChild(el('option', { value: '', text: 'Loading programs...' }));
        var p = cache.programs[unitid] ? Promise.resolve(cache.programs[unitid]) : FP.api('/api/v1/institutions/' + unitid + '/programs');
        p.then(function (d) {
            cache.programs[unitid] = d;
            sel.textContent = '';
            sel.appendChild(el('option', { value: '', text: d.programs.length ? 'Choose a program (' + d.programs.length + ')' : 'No program data imported' }));
            var byCred = {};
            d.programs.forEach(function (pr) { (byCred[pr.credential] = byCred[pr.credential] || []).push(pr); });
            Object.keys(byCred).forEach(function (cred) {
                var g = el('optgroup', { label: cred });
                byCred[cred].forEach(function (pr) {
                    var o = el('option', { value: pr.cip + '|' + pr.credentialLevel, text: pr.title + (pr.earningsAvailable ? ' ★' : '') });
                    if (state.education.cip === pr.cip) o.selected = true;
                    g.appendChild(o);
                });
                sel.appendChild(g);
            });
            sel.disabled = !d.programs.length;
            renderCollegeInfo();
        }).catch(function (err) {
            sel.textContent = '';
            sel.appendChild(el('option', { value: '', text: 'Programs unavailable: ' + err.message }));
        });
    }

    function loadCareersForCip(cip, title) {
        var box = $('possibleCareers');
        box.textContent = '';
        box.appendChild(el('p', { class: 'small text-body-secondary', text: 'Loading possible careers...' }));
        var key = cip + '|' + state.cbsa;
        var p = cache.careersForCip[key] ? Promise.resolve(cache.careersForCip[key]) : FP.api('/api/v1/programs/' + encodeURIComponent(cip) + '/careers?cbsa=' + state.cbsa);
        p.then(function (d) {
            cache.careersForCip[key] = d;
            renderPossibleCareers(d, title);
        }).catch(function (err) { box.textContent = ''; box.appendChild(el('p', { class: 'small text-danger', text: err.message })); });
    }

    function renderPossibleCareers(d, title) {
        var box = $('possibleCareers');
        box.textContent = '';
        box.appendChild(el('h3', { class: 'h6 mb-1', text: 'Possible careers for ' + (d.title || title || d.cip) }));
        box.appendChild(el('p', { class: 'small text-body-secondary', text: d.caveat }));
        var prog = currentProgram();
        if (prog) box.appendChild(observedEarningsBox(prog));
        if (!d.careers.length) { box.appendChild(el('p', { class: 'small', text: 'The crosswalk has no occupations mapped to this program.' })); return; }
        var list = el('div', { class: 'pick-list' });
        d.careers.slice().sort(function (a, b) { return (b.localMedian || 0) - (a.localMedian || 0); }).forEach(function (c) {
            var wageText = c.localStatus === 'available' ? 'Local median ' + FP.money(c.localMedian) : (c.localStatus === 'partial' ? 'Local wage partly published' : (c.nationalMedian ? 'No local wage · U.S. median ' + FP.money(c.nationalMedian) : 'No wage published'));
            list.appendChild(draggableCard({ kind: 'career', soc: c.soc, title: c.title }, [
                el('div', { class: 'pick-card-main' }, [el('span', { class: 'fw-semibold', text: c.title }), el('span', { class: 'small text-body-secondary', text: wageText + (c.entryEducation ? ' · typical entry: ' + c.entryEducation : '') })]),
                el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', 'aria-label': 'Choose ' + c.title + ' as your career', onclick: function () { chooseCareer(c.soc, c.title); } }, ['Choose'])
            ]));
        });
        box.appendChild(list);
        box.appendChild(el('p', { class: 'small text-body-secondary mt-2 mb-0' }, ['Source: ', el('a', { href: d.source.url, target: '_blank', rel: 'noopener', text: d.source.name })]));
    }

    function currentProgram() {
        var progs = state.education.unitid && cache.programs[state.education.unitid] ? cache.programs[state.education.unitid].programs : [];
        return progs.filter(function (p) { return p.cip === state.education.cip; })[0] || null;
    }

    function observedEarningsBox(pr) {
        var rows = ['1_yr', '4_yr', '5_yr'].map(function (h) {
            var e = pr.observedEarnings[h];
            return el('li', {}, [h.replace('_yr', '') + ' year(s) after completing: ', el('strong', { text: e && e.median !== null ? FP.money(e.median) : 'suppressed / not reported' })]);
        });
        return el('div', { class: 'observed-box' }, [
            el('div', { class: 'small fw-semibold', text: 'Observed earnings of former ' + pr.credential.toLowerCase() + ' students in this field at this school (College Scorecard)' }),
            el('ul', { class: 'small mb-1' }, rows),
            el('div', { class: 'small text-body-secondary', text: 'Median debt of completers: ' + (pr.debtMedian !== null ? FP.money(pr.debtMedian) : 'not reported') + '. This is a different measure from the local occupational wages below: it describes former students of this program wherever they work.' })
        ]);
    }

    function renderCollegeInfo() {
        var box = $('collegeInfo');
        box.textContent = '';
        var b = current.bundle;
        var inst = b && b.institution && b.institution.unitid === state.education.unitid ? b.institution : null;
        if (!inst) return;
        var c = inst.costs;
        box.appendChild(el('ul', { class: 'list-unstyled mb-1' }, [
            el('li', {}, ['Average net price per year: ', el('strong', { text: FP.money(c.averageNetPrice, { fallback: 'not reported' }) })]),
            el('li', {}, ['Tuition: ', el('span', { text: FP.money(c.inStateTuition, { fallback: 'n/a' }) + ' in-state · ' + FP.money(c.outOfStateTuition, { fallback: 'n/a' }) + ' out-of-state' })]),
            el('li', {}, ['Completion rate: ', el('span', { text: inst.outcomes.completionRate !== null ? FP.pct(inst.outcomes.completionRate) : 'not reported' })])
        ]));
        box.appendChild(el('p', { class: 'text-body-secondary mb-0', text: c.note }));
    }

    function renderSchoolPicker() {
        var key = state.education.pathway;
        $('schoolPicker').hidden = SCHOOL_PATHS.indexOf(key) < 0;
        var info = $('pathwayInfo');
        info.textContent = '';
        var p = cache.pathways && cache.pathways[key];
        if (p) {
            info.appendChild(el('p', { class: 'mb-1', text: p.description + ' Typical time: ' + p.typicalYears + ' year' + (p.typicalYears === 1 ? '' : 's') + '.' }));
            if (p.licensingNotes) info.appendChild(el('p', { class: 'text-body-secondary mb-0', text: p.licensingNotes }));
        }
    }

    function renderPathSummary() {
        var box = $('pathSummary');
        box.textContent = '';
        var e0 = state.earners[0] || {};
        var r = lastResult;
        var occ = cache.occupations[e0.soc] || {};
        if (e0.soc) {
            var er = r && r.income.earners[0] && r.income.earners[0].soc === e0.soc ? r.income.earners[0] : null;
            var wageLine = er ? (er.annualWage !== null ? FP.money(er.annualWage) + '/yr ' + (er.percentile === 'median' ? 'median' : er.percentile.replace('p', '') + 'th percentile') + ' pay' + (er.wageYear ? ' (BLS May ' + er.wageYear + ')' : '') : er.message) : 'Loading local wage...';
            box.appendChild(el('div', { class: 'path-item' }, [
                el('span', { class: 'path-kind', text: 'Career' }),
                el('a', { class: 'fw-semibold', href: '/careers/' + e0.soc + '?cbsa=' + state.cbsa, text: occ.title || e0.soc }),
                el('span', { class: 'small d-block', text: wageLine })
            ]));
            if (occ.pathways && occ.pathways.length) {
                var common = occ.pathways.filter(function (p) { return p.status === 'common'; })[0] || occ.pathways[0];
                if (common && common.key !== state.education.pathway) {
                    box.appendChild(el('div', { class: 'small mt-1' }, ['Typical path: ' + common.name + ' (' + common.typicalYears + ' yrs). ',
                        el('button', { type: 'button', class: 'btn btn-link btn-sm p-0 align-baseline', onclick: function () { choosePathway(common.key); } }, ['Use this path'])]));
                }
            }
        }
        if (state.education.pathway) {
            var p = cache.pathways && cache.pathways[state.education.pathway];
            var inst = current.bundle && current.bundle.institution && current.bundle.institution.unitid === state.education.unitid ? current.bundle.institution : null;
            var prog = currentProgram();
            box.appendChild(el('div', { class: 'path-item' }, [
                el('span', { class: 'path-kind', text: 'Path' }),
                el('span', { class: 'fw-semibold', text: p ? p.name : state.education.pathway }),
                inst ? el('span', { class: 'small d-block', text: inst.name + (prog ? ' · ' + prog.title : '') }) : null,
                el('button', { type: 'button', class: 'btn btn-link btn-sm p-0 d-block', onclick: function () { commit(function (s) { s.education = { pathway: '', years: 0, unitid: null, cip: '', annualNetPrice: null, grantsAnnual: 0, familyAnnual: 0, loanKey: 'direct_undergrad' }; syncStudentDebt(s); }, 'Path cleared'); $('pathwaySelect').value = ''; renderSchoolPicker(); } }, ['Clear path'])
            ]));
        }
        $('pathSlot').classList.toggle('has-content', !!(e0.soc || state.education.pathway));
    }

    function initPickers() {
        FP.Typeahead(document.querySelector('[data-typeahead=metro]'), {
            minChars: 2,
            search: function (q, signal) { return FP.api('/api/v1/geographies?limit=8&q=' + encodeURIComponent(q), { signal: signal }); },
            render: function (m) { return { label: m.name, detail: 'CBSA ' + m.cbsa }; },
            empty: function (q) { return 'No imported metro matches "' + q + '". Try a nearby big city.'; },
            onSelect: function (m) { cache.metros[m.cbsa] = cache.metros[m.cbsa] || { cbsa: m.cbsa, name: m.name, states: m.states.map(function (c) { return { code: c, name: c }; }) }; chooseMetro(m.cbsa, m.states); remember('metro', { cbsa: m.cbsa, name: m.name, states: m.states }); },
            onFocusEmpty: function () { return recent('metro'); }
        });
        document.querySelectorAll('[data-metro]').forEach(function (btn) {
            btn.addEventListener('click', function () { var f = BOOT.featured.filter(function (m) { return m.cbsa === btn.dataset.metro; })[0]; chooseMetro(btn.dataset.metro, f ? f.states : null); });
        });
        var careerSearch = function (q, signal) { return FP.api('/api/v1/occupations?limit=10&cbsa=' + state.cbsa + '&q=' + encodeURIComponent(q), { signal: signal }); };
        var careerRender = function (o) {
            var w = o.localStatus === 'available' ? 'local median ' + FP.money(o.localMedian) : (o.localStatus === 'partial' ? 'local wage partly published' : 'no local wage published');
            return { label: o.title, detail: o.soc + ' · ' + w };
        };
        FP.Typeahead(document.querySelector('[data-typeahead=career]'), {
            minChars: 2, search: careerSearch, render: careerRender,
            empty: function (q) { return 'No careers match "' + q + '". Try a simpler word like nurse, teacher, cook.'; },
            onSelect: function (o) { chooseCareer(o.soc, o.title); remember('career', o); },
            onFocusEmpty: function () { return recent('career'); }
        });
        FP.Typeahead(document.querySelector('[data-typeahead=career2]'), {
            minChars: 2, search: careerSearch, render: careerRender,
            empty: function (q) { return 'No careers match "' + q + '".'; },
            onSelect: function (o) { chooseCareer(o.soc, o.title, 1); $('career2Input').value = o.title; }
        });
        FP.Typeahead(document.querySelector('[data-typeahead=college]'), {
            minChars: 2,
            search: function (q, signal) { return FP.api('/api/v1/institutions?limit=10&q=' + encodeURIComponent(q), { signal: signal }); },
            render: function (i) { return { label: i.name, detail: (i.city || '') + ', ' + (i.state || '') + ' · net price ' + FP.money(i.costs.averageNetPrice, { fallback: 'n/a' }) }; },
            empty: function () { return 'No imported college matches. An admin can import more College Scorecard schools.'; },
            onSelect: chooseCollege
        });
        FP.Typeahead(document.querySelector('[data-typeahead=major]'), {
            minChars: 2,
            search: function (q, signal) { return FP.api('/api/v1/programs?limit=10&q=' + encodeURIComponent(q), { signal: signal }); },
            render: function (p) { return { label: p.title, detail: 'CIP ' + p.cip + ' · ' + p.mappedCareers + ' possible careers' }; },
            empty: function (q) { return 'No fields of study match "' + q + '".'; },
            onSelect: function (p) { chooseProgram(p.cip, p.title, null); $('majorInput').value = p.title; }
        });
        $('programSelect').addEventListener('change', function () {
            var v = $('programSelect').value; if (!v) return;
            var cip = v.split('|')[0];
            var pr = (cache.programs[state.education.unitid] || { programs: [] }).programs.filter(function (p) { return p.cip === cip; })[0];
            if (pr && pr.pathway && SCHOOL_PATHS.indexOf(pr.pathway) >= 0 && pr.pathway !== state.education.pathway) {
                commit(function (s) { s.education.pathway = pr.pathway; s.education.years = cache.pathways && cache.pathways[pr.pathway] ? cache.pathways[pr.pathway].typicalYears : s.education.years; syncStudentDebt(s); }, null);
                $('pathwaySelect').value = pr.pathway;
            }
            chooseProgram(cip, pr ? pr.title : cip, state.education.unitid);
        });
        $('pathwaySelect').addEventListener('change', function () { if ($('pathwaySelect').value) choosePathway($('pathwaySelect').value); });
        document.querySelectorAll('#percentileSeg [data-percentile]').forEach(function (btn) {
            btn.addEventListener('click', function () { commit(function (s) { s.earners[0].percentile = btn.dataset.percentile; }, 'Pay level ' + btn.textContent); });
        });
        $('partTime').addEventListener('change', function () { commit(function (s) { s.earners[0].workFraction = $('partTime').checked ? 0.5 : 1; }, $('partTime').checked ? 'Part-time' : 'Full-time'); });
        $('adultsSelect').addEventListener('change', function () { commit(function (s) { s.adults = Number($('adultsSelect').value); if (s.adults === 1 && s.earners.length > 1) s.earners = s.earners.slice(0, 1); }, 'Household updated'); });
        $('filingSelect').addEventListener('change', function () { commit(function (s) { s.filingStatus = $('filingSelect').value; }, 'Filing status updated'); });
        $('stateSelect').addEventListener('change', function () { commit(function (s) { s.state = $('stateSelect').value; if (s.state !== 'NY') s.nycResident = false; }, 'State updated'); });
        $('nycCheck').addEventListener('change', function () { commit(function (s) { s.nycResident = $('nycCheck').checked; }, 'NYC residence updated'); });
        $('secondEarner').addEventListener('change', function () {
            var on = $('secondEarner').checked;
            $('secondEarnerBox').hidden = !on;
            commit(function (s) {
                if (on) { s.adults = 2; if (s.earners.length < 2) s.earners.push({ soc: '', percentile: 'median', workFraction: 1, customWage: null }); if (s.filingStatus === 'single') s.filingStatus = 'mfj'; }
                else { s.earners = s.earners.slice(0, 1); }
            }, on ? 'Second earner added' : 'Second earner removed');
        });
        document.querySelectorAll('#timelineSeg [data-mode]').forEach(function (btn) {
            btn.addEventListener('click', function () { commit(function (s) { s.timeline.mode = btn.dataset.mode; }, 'Timeline: ' + btn.textContent); });
        });
        document.querySelectorAll('[data-assumption]').forEach(function (input) {
            input.addEventListener('change', function () { var v = input.value.trim(); setAssumption(input.dataset.assumption, v === '' ? null : Number(v)); });
        });
        $('rememberCheck').checked = FP.storage.get('fp.remember') === true;
        $('rememberCheck').addEventListener('change', function () {
            if ($('rememberCheck').checked) { FP.storage.set('fp.remember', true); FP.storage.set('fp.scenario', state); FP.announce('Your scenario will be remembered in this browser.'); }
            else { FP.storage.remove('fp.remember'); FP.storage.remove('fp.scenario'); FP.storage.remove('fp.recent'); FP.announce('Saved scenario and recent choices removed from this browser.'); }
        });
    }

    function remember(kind, item) {
        if (FP.storage.get('fp.remember') !== true) return;
        var all = FP.storage.get('fp.recent') || {};
        var list = (all[kind] || []).filter(function (x) { return JSON.stringify(x) !== JSON.stringify(item); });
        list.unshift(item);
        all[kind] = list.slice(0, 5);
        FP.storage.set('fp.recent', all);
    }
    function recent(kind) { var all = FP.storage.get('fp.recent') || {}; return all[kind] || []; }

    function syncControls() {
        var e0 = state.earners[0] || {};
        document.querySelectorAll('#percentileSeg [data-percentile]').forEach(function (b) { b.setAttribute('aria-checked', String(b.dataset.percentile === e0.percentile)); });
        document.querySelectorAll('#timelineSeg [data-mode]').forEach(function (b) { b.setAttribute('aria-checked', String(b.dataset.mode === state.timeline.mode)); });
        $('partTime').checked = e0.workFraction < 1;
        $('adultsSelect').value = String(state.adults);
        $('filingSelect').value = state.filingStatus;
        $('secondEarner').checked = state.earners.length > 1;
        $('secondEarnerBox').hidden = state.earners.length < 2;
        $('pathwaySelect').value = state.education.pathway || '';
        document.querySelectorAll('[data-assumption]').forEach(function (input) {
            var k = input.dataset.assumption;
            if (document.activeElement !== input) input.value = String(assumption(k));
        });
        if (e0.soc && cache.occupations[e0.soc] && document.activeElement !== $('careerInput')) $('careerInput').value = cache.occupations[e0.soc].title || '';
        var e1 = state.earners[1];
        if (e1 && e1.soc && cache.occupations[e1.soc] && document.activeElement !== $('career2Input')) $('career2Input').value = cache.occupations[e1.soc].title || '';
        document.querySelector('[data-action=undo]').disabled = !undoStack.length;
        document.querySelector('[data-action=redo]').disabled = !redoStack.length;
        renderSchoolPicker();
    }

    // ------------------------------------------------------------------ budget rendering
    var CATEGORY_LABELS = { housing: 'Housing', transportation: 'Transportation', food: 'Food', childcare: 'Childcare', healthcare: 'Health', education_debt: 'Student loans', savings: 'Travel & savings', other: 'Phone & other' };
    var BASIS_LABELS = { sourced: 'Sourced', assumption: 'Assumption', user: 'Yours', missing: 'Missing' };

    function showBudgetError(msg) {
        var box = $('budgetSummary');
        box.textContent = '';
        box.appendChild(el('div', { class: 'alert alert-warning mb-0', role: 'alert', text: 'We could not load data for this choice: ' + msg }));
    }

    function bar(label, value, max, cls) {
        var fill = el('span', { class: 'hbar-fill ' + cls });
        fill.style.width = (max > 0 ? Math.max(1.5, Math.min(100, value / max * 100)) : 0) + '%';
        return el('div', { class: 'hbar-row' }, [el('span', { class: 'hbar-label', text: label }), el('span', { class: 'hbar' }, [fill]), el('span', { class: 'hbar-value', text: FP.money(value) })]);
    }

    // ------------------------------------------------------------------ results: summary, age timeline, goals
    var DECADES = [20, 30, 40, 50, 60, 70];
    var GOAL_ICONS = { education: '\u{1F393}', house: '\u{1F3E1}', car: '\u{1F697}', travel: '✈️', savings: '\u{1F437}', retirement: '\u{1F334}' };
    var GOAL_MARKERS = { education: 'School done', house: 'House', car: 'Car', travel: 'Travel', savings: 'Savings goal', retirement: 'Retire' };
    var STATUS_CLASS = { on_track: 'ok', later: 'warn', not_achievable: 'bad', info: 'info' };
    var STATUS_ICON = { ok: '✓', warn: '◷', bad: '!', info: '?' };
    var OVERALL_CLASS = { achievable: 'ok', adjust: 'warn', not_funded: 'bad', info: 'info' };
    var GAP_LABELS = { upfront_cash: 'Upfront cash', monthly_cash_flow: 'Monthly cash flow', retirement_funding: 'Retirement funding' };
    var PLAN_FIELDS = {
        endAge: [60, 90], planningAge: [60, 105], startingCash: [0, 10000000], startingInvestments: [0, 10000000], startingDebt: [0, 10000000], startingDebtRatePct: [0, 30],
        trainingSupportMonthly: [0, 20000], studyIncomeMonthly: [0, 20000], retirementIncomeMonthly: [0, 20000],
        firstChildAge: [16, 60], childSpacingYears: [1, 10], childcareYears: [0, 13], secondEarnerAge: [14, 80]
    };

    function statusPill(cls, text) {
        return el('span', { class: 'status-pill status-' + cls }, [el('span', { 'aria-hidden': 'true', text: STATUS_ICON[cls] + ' ' }), text]);
    }
    function snapAt(age) { return lastProjection ? lastProjection.ageSnapshots.filter(function (s) { return s.age === age; })[0] || null : null; }
    function goalOf(key) { return lastProjection ? lastProjection.goals.filter(function (g) { return g.key === key; })[0] || null : null; }
    function preferredAge() { return hasTile('house') && typeof state.plan.goals.house === 'number' ? state.plan.goals.house : 30; }

    /** The age shown in the summary: the chosen age, or the nearest modeled age with an explanation. */
    function selectedAge() {
        var h = lastProjection ? lastProjection.horizon : { startAge: state.timeline.startAge, endAge: state.plan.endAge };
        var want = ui.age !== null ? ui.age : preferredAge();
        var age = Math.min(Math.max(want, h.startAge), h.endAge);
        var note = '';
        if (want < h.startAge) note = 'Age ' + want + ' is before this scenario starts (age ' + h.startAge + '), so this shows age ' + age + '.';
        else if (want > h.endAge) note = 'Age ' + want + ' is past the end of this timeline (age ' + h.endAge + '), so this shows age ' + age + '.';
        return { age: age, wanted: want, note: note };
    }

    function setAge(age, focusCard) {
        ui.age = age;
        renderSummary();
        renderAgeTimeline();
        renderAgeDetail();
        renderMobileBar();
        if (focusCard) { var b = document.querySelector('#ageCards [data-age="' + age + '"]'); if (b) b.focus(); }
    }

    function renderResults() {
        renderSummary();
        renderAgeTimeline();
        renderAgeDetail();
        renderGoals();
        renderGoalDates();
        renderNumbers(lastResult);
        renderBreakdown(lastResult);
        renderEducation(lastResult);
        renderYearTable();
        renderSources(lastResult, current.bundle);
        renderMobileBar();
        renderCanvasSummaries();
    }

    // ---- SimpleBudgetSummary
    function figure(label, value, sub, cls) {
        return el('div', { class: 'fig ' + (cls || '') }, [
            el('div', { class: 'fig-label', text: label }),
            el('div', { class: 'fig-value', text: value }),
            sub ? el('div', { class: 'fig-sub', text: sub }) : null
        ]);
    }

    function renderSummary() {
        var box = $('budgetSummary');
        box.textContent = '';
        var p = lastProjection;
        if (!p) return;
        var ov = p.overallStatus, cls = OVERALL_CLASS[ov.code];
        box.appendChild(el('div', { class: 'overall overall-' + cls }, [el('span', { class: 'overall-icon', 'aria-hidden': 'true', text: STATUS_ICON[cls] }), el('strong', { text: ov.message })]));
        if (!p.available) {
            var ul = el('ul', { class: 'small mb-2 mt-2' });
            (ov.missing || []).forEach(function (m) { ul.appendChild(el('li', { text: 'Needed: ' + m.text })); });
            box.appendChild(ul);
        }
        var h = p.horizon, sel = selectedAge();
        var select = el('select', { id: 'summaryAge', class: 'form-select form-select-sm w-auto' });
        for (var a = h.startAge; a <= h.endAge; a++) {
            var o = el('option', { value: String(a), text: String(a) });
            if (a === sel.age) o.selected = true;
            select.appendChild(o);
        }
        select.addEventListener('change', function () { setAge(Number(select.value)); });
        box.appendChild(el('div', { class: 'd-flex align-items-center gap-2 mt-3' }, [el('label', { for: 'summaryAge', class: 'h5 mb-0', text: 'At age' }), select]));
        if (sel.note) box.appendChild(el('p', { class: 'small text-body-secondary mb-0 mt-1', text: sel.note }));
        var s = p.available ? snapAt(sel.age) : null;
        var hasCareer = !(ov.missing || []).some(function (m) { return m.key === 'career'; });
        var grid = el('div', { class: 'fig-grid mt-2' });
        if (s) {
            var parts = [];
            if (s.livingMonthly) parts.push('living ' + FP.money(s.livingMonthly));
            if (s.debtMonthly > 0.5) parts.push('debt ' + FP.money(s.debtMonthly));
            if (s.savingsPlannedMonthly > 0.5) parts.push('savings ' + FP.money(s.savingsPlannedMonthly));
            grid.appendChild(figure('Monthly take-home', FP.money(s.takeHomeMonthly), s.stage === 'training' ? 'Study income and support' : s.stage === 'retired' ? 'Retirement income you entered' : 'After taxes and deductions'));
            grid.appendChild(figure('Planned spending', FP.money(s.plannedSpendingMonthly), parts.join(' + ')));
            grid.appendChild(figure(s.leftoverMonthly >= 0 ? 'Left over' : 'Shortfall', FP.money(Math.abs(s.leftoverMonthly)), 'per month', s.leftoverMonthly >= 0 ? 'fig-plus' : 'fig-minus'));
        } else {
            grid.appendChild(figure('Monthly take-home', hasCareer ? 'Incomplete' : 'Not available', hasCareer ? 'Some data is missing' : 'Choose a career'));
            grid.appendChild(figure('Planned spending', lastResult && lastResult.complete ? FP.money(lastResult.costs.monthlyTotal) : 'Incomplete', lastResult && lastResult.complete ? 'Today, with every card' : 'Some costs are missing'));
            grid.appendChild(figure('Left over / Shortfall', 'Not available', 'Needs income and housing'));
        }
        box.appendChild(grid);
        if (s && s.stage === 'training') box.appendChild(el('p', { class: 'small text-body-secondary mt-2 mb-0', text: 'You are in school or training at this age. A shortfall here needs support or savings; it is not a verdict on the whole plan.' }));
        else if (s) box.appendChild(el('p', { class: 'small text-body-secondary mt-2 mb-0', text: 'This is the money picture at age ' + s.age + ' only. The message above covers every goal on your timeline.' }));
        if (s && s.unfundedThisYear > 0.5) box.appendChild(el('p', { class: 'small text-danger-emphasis mt-1 mb-0', text: 'Unfunded shortfall this year: ' + FP.money(s.unfundedThisYear) + ' (cash has run out).' }));
        if (!p.available && !hasCareer) {
            box.appendChild(el('div', { class: 'd-flex flex-wrap gap-2 mt-3' }, [
                el('button', { type: 'button', class: 'btn btn-sm btn-primary', onclick: function () { runReverse(); } }, ['Find careers that pay for this']),
                el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { $('careerInput').focus(); } }, ['Pick a career'])
            ]));
        }
        box.appendChild(el('p', { class: 'illustrative-label mt-3 mb-0', text: 'Illustrative projection · Based on your selections and editable assumptions' }));
    }

    function renderMobileBar() {
        var p = lastProjection, s = p && p.available ? snapAt(selectedAge().age) : null;
        $('mbAge').textContent = String(selectedAge().age);
        $('mbTake').textContent = s ? FP.money(s.takeHomeMonthly) : 'n/a';
        $('mbCost').textContent = s ? FP.money(s.plannedSpendingMonthly) : (lastResult && lastResult.complete ? FP.money(lastResult.costs.monthlyTotal) : 'n/a');
        $('mbGap').textContent = s ? (s.leftoverMonthly >= 0 ? FP.money(s.leftoverMonthly) + ' left' : FP.money(-s.leftoverMonthly) + ' short') : 'More info needed';
        $('mobileBar').className = 'mobile-budget-bar no-print ' + (s ? (s.leftoverMonthly >= 0 ? 'is-plus' : 'is-minus') : '');
    }

    // ---- FutureAgeTimeline
    function goalsDueBy(age) {
        return (lastProjection.goals || []).filter(function (g) { return g.key !== 'education' && g.requestedAge <= age && (g.projectedAge === null || g.projectedAge > age); });
    }

    function ageCard(age) {
        var p = lastProjection, h = p.horizon;
        if (!p.available) return { icon: '❔', stage: 'More information needed', lines: ['Add a career and a place to live.'], money: '', status: { cls: 'info', text: 'More information needed' } };
        if (age < h.startAge) return { icon: '⏪', stage: 'Before this scenario starts', lines: ['This scenario starts at age ' + h.startAge + '.'], money: '', status: { cls: 'info', text: 'Not modeled' } };
        if (age > h.endAge) return { icon: '⏩', stage: 'Beyond this timeline', lines: ['The timeline ends at age ' + h.endAge + '.'], money: '', status: { cls: 'info', text: 'Not modeled' } };
        var s = snapAt(age), ret = goalOf('retirement'), house = goalOf('house');
        var stage = s.stage === 'training' ? 'In training' : s.stage === 'working' ? 'Working' : (ret && ret.status === 'not_achievable' ? 'Retired, not fully funded' : 'Retirement projected');
        var icon = s.stage === 'training' ? '\u{1F393}' : s.stage === 'retired' ? '\u{1F334}' : (s.housing === 'own' ? '\u{1F3E1}' : '\u{1F4BC}');
        var lines = [];
        if (s.stage === 'training') lines.push('Sharing housing; career starts at ' + Math.ceil(h.careerStartAge));
        else if (s.housing === 'own') lines.push('Owns a home');
        else if (house && age >= house.requestedAge) lines.push(house.projectedAge === null ? 'Renting; home goal not reached' : 'Renting; home around ' + house.projectedAge);
        else lines.push(s.housing === 'rent' ? 'Renting' : 'Housing not chosen');
        var ev = s.events.filter(function (e) { return e !== 'Career starts'; })[0];
        if (ev) lines.push(ev);
        else if (s.kidsHome) lines.push(s.kidsHome + (s.kidsHome > 1 ? ' kids' : ' kid') + ' at home' + (s.kidsInCare ? ', ' + s.kidsInCare + ' in daycare' : ''));
        var money = s.unfundedThisYear > 0.5 ? 'Unfunded gap ' + FP.money(s.unfundedThisYear / 12) + '/mo'
            : (s.leftoverMonthly >= 0 ? FP.money(s.leftoverMonthly) + '/mo left over' : FP.money(-s.leftoverMonthly) + '/mo shortfall');
        var status;
        if (s.unfundedThisYear > 0.5) status = { cls: 'bad', text: 'Shortfall' };
        else if (goalsDueBy(age).length) status = { cls: 'warn', text: 'Goal delayed' };
        else if (s.leftoverMonthly < 0) status = { cls: 'warn', text: 'Using savings' };
        else status = { cls: 'ok', text: 'On track' };
        return { icon: icon, stage: stage, lines: lines.slice(0, 2), money: money, status: status };
    }

    function goalMarkers() {
        if (!lastProjection || !lastProjection.available) return [];
        return lastProjection.goals.filter(function (g) { return g.projectedAge !== null; }).map(function (g) {
            return { key: g.key, age: g.projectedAge, text: GOAL_MARKERS[g.key] + ' around ' + g.projectedAge, icon: GOAL_ICONS[g.key] };
        }).sort(function (a, b) { return a.age - b.age; });
    }

    function renderAgeTimeline() {
        var p = lastProjection;
        if (!p) return;
        var h = p.horizon, sel = selectedAge();
        var shown = ui.age !== null ? ui.age : sel.age;
        $('horizonNote').textContent = p.available
            ? 'Ages ' + h.startAge + ' to ' + h.endAge + ' in ' + h.dollarBasis + (h.mode === 'projected' ? ' (raises in projected mode)' : '') + '. Retirement money is checked to age ' + h.retirementPlanningAge + '. Starting age ' + h.startAge + ' is a scenario setting, not your birth date.'
            : 'Add a career and a place to live to see your timeline.';
        var btns = $('ageButtons');
        btns.textContent = '';
        DECADES.forEach(function (a) {
            btns.appendChild(el('button', { type: 'button', role: 'radio', class: 'age-btn', 'aria-checked': String(shown === a), onclick: function () { setAge(a); } }, [String(a)]));
        });
        if (DECADES.indexOf(shown) < 0) btns.appendChild(el('span', { class: 'small text-body-secondary ms-1', text: 'Showing age ' + shown }));
        var list = $('ageCards');
        list.textContent = '';
        var text = $('textTimeline');
        text.textContent = '';
        DECADES.forEach(function (a, i) {
            var c = ageCard(a);
            var btn = el('button', { type: 'button', class: 'age-card status-' + c.status.cls + (shown === a ? ' is-selected' : '') + (c.status.text === 'Not modeled' ? ' is-muted' : ''), dataset: { age: String(a) }, 'aria-pressed': String(shown === a),
                'aria-label': 'Age ' + a + ': ' + c.stage + '. ' + c.lines.join('. ') + (c.money ? '. ' + c.money : '') + '. ' + c.status.text, onclick: function () { setAge(a); } }, [
                el('span', { class: 'age-card-head' }, [el('span', { class: 'age-num', text: String(a) }), el('span', { class: 'age-icon', 'aria-hidden': 'true', text: c.icon })]),
                el('span', { class: 'age-stage', text: c.stage }),
                el('span', { class: 'age-lines' }, c.lines.map(function (l) { return el('span', { class: 'd-block', text: l }); })),
                c.money ? el('span', { class: 'age-money', text: c.money }) : null,
                statusPill(c.status.cls, c.status.text)
            ]);
            btn.addEventListener('keydown', function (e) {
                var j = { ArrowRight: i + 1, ArrowDown: i + 1, ArrowLeft: i - 1, ArrowUp: i - 1, Home: 0, End: DECADES.length - 1 }[e.key];
                if (j === undefined) return;
                e.preventDefault();
                setAge(DECADES[Math.max(0, Math.min(DECADES.length - 1, j))], true);
            });
            list.appendChild(el('li', {}, [btn]));
            text.appendChild(el('li', { text: 'Age ' + a + ': ' + c.stage + '. ' + c.lines.join('. ') + (c.money ? '. ' + c.money : '') + '. ' + c.status.text + '.' }));
        });
        var track = $('milestoneTrack');
        track.textContent = '';
        var rows = [];
        goalMarkers().forEach(function (m) {
            var row = 0;
            while (rows[row] !== undefined && m.age - rows[row] < 7) row++;
            rows[row] = m.age;
            var left = Math.max(2, Math.min(98, ((m.age - 20) / 10 + 0.5) / DECADES.length * 100));
            var chip = el('span', { class: 'milestone milestone-' + m.key, text: m.icon + ' ' + m.text });
            chip.style.left = left + '%';
            chip.style.top = (row * 30) + 'px';
            track.appendChild(chip);
            text.appendChild(el('li', { text: m.text + ' (estimated).' }));
        });
        track.style.height = (rows.length ? rows.length * 30 + 4 : 0) + 'px';
    }

    // ---- AgeDetailPanel
    function goalAtAge(g, age) {
        if (g.projectedAge !== null && g.projectedAge <= age) return { cls: 'ok', text: g.key === 'retirement' ? 'Retired from ' + g.projectedAge : 'Done around ' + g.projectedAge };
        if (age < g.requestedAge) return { cls: 'info', text: 'Planned for age ' + g.requestedAge };
        return g.projectedAge !== null ? { cls: 'warn', text: 'Delayed; projected around ' + g.projectedAge } : { cls: 'bad', text: 'Not reached in this timeline' };
    }

    function renderAgeDetail() {
        var box = $('ageDetail');
        box.textContent = '';
        var p = lastProjection;
        if (!p) return;
        var sel = selectedAge(), want = sel.wanted;
        if (!p.available) {
            box.appendChild(el('h3', { class: 'h6 mb-2', text: 'At age ' + sel.age + ': More information needed' }));
            var miss = (p.overallStatus.missing || []).map(function (m) { return m.text; }).join('; ') || 'Choose a career and a place to live.';
            var na = el('dl', { class: 'kv detail-kv small mb-2' });
            [['Career or training', 'Not available'], ['Housing', hasTile('house') || hasTile('apartment') ? (hasTile('house') ? 'House selected' : 'Apartment selected') : 'Not chosen'],
                ['Take-home pay', 'Not available'], ['Planned spending', lastResult && lastResult.complete ? FP.money(lastResult.costs.monthlyTotal) + '/mo today' : 'Incomplete'],
                ['Left over / Shortfall', 'Not available']].forEach(function (row) { na.appendChild(el('dt', { text: row[0] })); na.appendChild(el('dd', { text: row[1] })); });
            box.appendChild(na);
            box.appendChild(el('p', { class: 'small mb-0', text: miss }));
            return;
        }
        if (want < p.horizon.startAge) {
            box.appendChild(el('h3', { class: 'h6 mb-1', text: 'Age ' + want + ': Before this scenario starts' }));
            box.appendChild(el('p', { class: 'small mb-0', text: 'This scenario starts at age ' + p.horizon.startAge + '. Change the scenario starting age under "Change my goal dates" to model earlier years.' }));
            var early = el('dl', { class: 'kv detail-kv small mb-0 mt-2' });
            [['Modeled start', 'Age ' + p.horizon.startAge], ['This age', 'Before this scenario starts']].forEach(function (row) { early.appendChild(el('dt', { text: row[0] })); early.appendChild(el('dd', { text: row[1] })); });
            box.appendChild(early);
            return;
        }
        if (want > p.horizon.endAge) {
            box.appendChild(el('h3', { class: 'h6 mb-1', text: 'Age ' + want + ': Beyond this timeline' }));
            box.appendChild(el('p', { class: 'small mb-0', text: 'The timeline ends at age ' + p.horizon.endAge + '. You can extend it under "Change my goal dates".' }));
            var late = el('dl', { class: 'kv detail-kv small mb-0 mt-2' });
            [['Modeled end', 'Age ' + p.horizon.endAge], ['This age', 'Beyond this timeline']].forEach(function (row) { late.appendChild(el('dt', { text: row[0] })); late.appendChild(el('dd', { text: row[1] })); });
            box.appendChild(late);
            return;
        }
        var s = snapAt(sel.age);
        if (!s) return;
        var r = lastResult, e0 = r && r.income.earners[0];
        var career = s.stage === 'training' ? 'In school or training' + (r && r.education.pathwayName ? ' (' + r.education.pathwayName + ')' : '') + '; career starts at ' + Math.ceil(p.horizon.careerStartAge)
            : s.stage === 'retired' ? 'Retired' : ((e0 && e0.title) || 'Working') + (state.earners.length > 1 && s.age >= (state.plan.secondEarnerAge || Math.floor(p.horizon.careerStartAge)) ? ' + second earner' : '');
        var houseTile = getTile('house'), apt = getTile('apartment');
        var housing = s.stage === 'training' ? 'Shared housing (training assumption)'
            : s.housing === 'own' ? 'Owns a ' + ((PRESETS.house[houseTile && houseTile.tier] || {}).label || '').toLowerCase() + ' home'
            : s.housing === 'rent' ? 'Renting' + (apt ? ' a ' + bedLabel(apt.bedrooms).toLowerCase() : '') : 'Not chosen';
        var household = state.adults + (state.adults > 1 ? ' adults' : ' adult') + (s.kidsHome ? ', ' + s.kidsHome + (s.kidsHome > 1 ? ' kids' : ' kid') + ' at home' : '') + (s.kidsInCare ? ' (' + s.kidsInCare + ' in daycare)' : '');
        var b = s.balances;
        var debt = b.studentDebt + b.otherDebt + b.mortgage;
        var debtParts = [];
        if (b.studentDebt > 0.5) debtParts.push('student ' + FP.money(b.studentDebt));
        if (b.otherDebt > 0.5) debtParts.push('other ' + FP.money(b.otherDebt));
        if (b.mortgage > 0.5) debtParts.push('mortgage ' + FP.money(b.mortgage));
        var rows = [
            ['Career or training', career], ['Housing', housing], ['Household', household],
            ['Take-home pay', FP.money(s.takeHomeMonthly) + '/mo'], ['Planned spending', FP.money(s.plannedSpendingMonthly) + '/mo'],
            [s.leftoverMonthly >= 0 ? 'Left over' : 'Shortfall', FP.money(Math.abs(s.leftoverMonthly)) + '/mo'],
            ['Cash on hand', FP.money(b.cash)], ['Savings account', FP.money(b.savings)], ['Retirement account', FP.money(b.retirement)],
            ['Debt', debt > 0.5 ? FP.money(debt) + ' (' + debtParts.join(', ') + ')' : 'None'],
            ['Home equity', b.homeEquity > 0.5 ? FP.money(b.homeEquity) + ' (not spending money)' : 'None']
        ];
        if (s.cumulativeUnfunded > 0.5) rows.push(['Unfunded so far', FP.money(s.cumulativeUnfunded)]);
        box.appendChild(el('h3', { class: 'h6 mb-2', text: 'At age ' + s.age + ': ' + (s.stage === 'training' ? 'In training' : s.stage === 'working' ? 'Working' : 'Retired') }));
        var dl = el('dl', { class: 'kv detail-kv small mb-2' });
        rows.forEach(function (row) { dl.appendChild(el('dt', { text: row[0] })); dl.appendChild(el('dd', { text: row[1] })); });
        box.appendChild(dl);
        var goalsUl = el('ul', { class: 'list-unstyled goal-progress small mb-1' });
        p.goals.forEach(function (g) {
            var st = goalAtAge(g, s.age);
            goalsUl.appendChild(el('li', {}, [el('span', { 'aria-hidden': 'true', text: GOAL_ICONS[g.key] + ' ' }), g.label + ': ', statusPill(st.cls, st.text)]));
        });
        box.appendChild(goalsUl);
        if (s.events.length) box.appendChild(el('p', { class: 'small mb-0', text: 'This year: ' + s.events.join(', ') + '.' }));
    }

    // ---- GoalMilestones
    function gapText(gaps, age) {
        return gaps.map(function (g) { return GAP_LABELS[g.type] + ' gap at ' + age + ': ' + FP.money(g.amount) + (g.type === 'monthly_cash_flow' ? '/month' : ''); }).join(' · ');
    }

    function renderGoals() {
        var box = $('goalsList');
        box.textContent = '';
        var p = lastProjection;
        if (!p) return;
        if (!p.available) {
            box.appendChild(el('div', { class: 'goal-row status-info' }, [statusPill('info', 'More information needed'),
                el('span', { class: 'small ms-2', text: (p.overallStatus.missing || []).map(function (m) { return m.text; }).join('; ') })]));
            return;
        }
        var ul = el('ul', { class: 'list-unstyled goal-list mb-0' });
        p.goals.forEach(function (g) {
            var cls = STATUS_CLASS[g.status] || 'info';
            var when = 'Wanted at ' + g.requestedAge + ' · ' + (g.projectedAge !== null ? 'Projected around ' + g.projectedAge + (g.yearsDelayed ? ' (' + g.yearsDelayed + (g.yearsDelayed === 1 ? ' year' : ' years') + ' later)' : '') : 'Not within this timeline (to age ' + p.horizon.endAge + ')');
            var gapsNow = gapText(g.gaps.atRequestedAge, g.requestedAge);
            var gapsEnd = g.gaps.atEndAge.length ? gapText(g.gaps.atEndAge, p.horizon.endAge).replace(/gap at \d+/g, 'gap still at ' + p.horizon.endAge) : '';
            ul.appendChild(el('li', { class: 'goal-row status-' + cls }, [
                el('span', { class: 'goal-icon', 'aria-hidden': 'true', text: GOAL_ICONS[g.key] }),
                el('div', { class: 'goal-main' }, [
                    el('div', { class: 'd-flex flex-wrap align-items-center gap-2' }, [el('strong', { text: g.label }), statusPill(cls, g.statusText)]),
                    el('div', { class: 'small', text: when }),
                    g.reason ? el('div', { class: 'small text-body-secondary', text: g.reason }) : null,
                    gapsNow ? el('div', { class: 'small gap-line', text: gapsNow }) : null,
                    gapsEnd ? el('div', { class: 'small gap-line', text: gapsEnd }) : null,
                    g.conditional ? el('div', { class: 'small text-warning-emphasis', text: 'Depends on covering an earlier money gap first.' }) : null
                ])
            ]));
        });
        box.appendChild(ul);
    }

    // ---- RequestedVsProjected
    var altSeq = 0, altTimer = null;
    function scheduleAlternative() {
        var my = ++altSeq;
        window.clearTimeout(altTimer);
        if (!lastProjection || !lastProjection.available || lastProjection.overallStatus.code === 'achievable') { renderAlternative(null); return; }
        renderAlternative('pending');
        var snap = JSON.parse(snapshot()), bundle = current.bundle;
        altTimer = window.setTimeout(function () {
            var alt;
            try { alt = P.evaluate(snap, bundle, DEF).alternative; } catch (e) { alt = { available: false, feasible: false, reason: e.message, changes: [] }; }
            if (my !== altSeq) return;
            lastProjection.alternative = alt;
            renderAlternative(alt);
        }, 250);
    }

    function renderAlternative(alt) {
        var box = $('alternativePanel');
        box.textContent = '';
        if (!alt) return;
        box.appendChild(el('h3', { class: 'h6 mb-2', text: 'What your current path could support' }));
        if (alt === 'pending') { box.appendChild(el('p', { class: 'small text-body-secondary mb-0', text: 'Checking what could fit with the same city, career and school...' })); return; }
        if (!alt.available) { box.appendChild(el('p', { class: 'small mb-0', text: 'An alternative is not available: ' + alt.reason })); return; }
        if (!alt.feasible) {
            box.appendChild(el('div', { class: 'alt-none' }, [
                el('p', { class: 'mb-1 fw-semibold', text: alt.reason }),
                alt.changes.length ? el('p', { class: 'small mb-2', text: 'Even with: ' + alt.changes.map(function (c) { return c.alternative.toLowerCase(); }).join(', ') + '.' }) : null,
                el('div', { class: 'd-flex flex-wrap gap-2' }, [
                    el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { runReverse(); } }, ['Compare careers']),
                    el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { showActions(); tryOtherCities(); } }, ['Try another city'])
                ])
            ]));
            return;
        }
        var table = el('table', { class: 'table table-sm alt-table mb-2' }, [
            el('caption', { class: 'visually-hidden', text: 'Your requested future compared with a projected alternative' }),
            el('thead', {}, [el('tr', {}, [el('th', { scope: 'col', text: 'You requested' }), el('th', { scope: 'col', text: 'Projected alternative' }), el('th', { scope: 'col', text: 'Why' })])])
        ]);
        var tb = el('tbody');
        alt.changes.forEach(function (c) { tb.appendChild(el('tr', {}, [el('td', { text: c.requested }), el('td', { text: c.alternative }), el('td', { class: 'small', text: c.why })])); });
        table.appendChild(tb);
        box.appendChild(el('div', { class: 'table-responsive' }, [table]));
        var chips = el('div', { class: 'd-flex flex-wrap gap-2 mb-2' });
        alt.goals.forEach(function (g) { chips.appendChild(statusPill(STATUS_CLASS[g.status] || 'info', g.label + (g.projectedAge !== null ? ' at ' + g.projectedAge : ''))); });
        box.appendChild(el('p', { class: 'small mb-1', text: 'With these changes: ' + alt.overallStatus.message }));
        box.appendChild(chips);
        box.appendChild(el('p', { class: 'small text-body-secondary', text: 'Same city, career, school and family. Your requested future stays exactly as you built it unless you choose Apply.' }));
        box.appendChild(el('div', { class: 'd-flex flex-wrap gap-2' }, [
            el('button', { type: 'button', class: 'btn btn-sm btn-primary', id: 'applyAlternative', onclick: function () {
                var copy = JSON.parse(JSON.stringify(alt.scenario));
                commit(function (s) { Object.keys(copy).forEach(function (k) { s[k] = copy[k]; }); }, 'Applied the alternative. Undo brings back your original plan');
            } }, ['Apply this alternative']),
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { addFuture(alt.scenario); } }, ['Add to compare'])
        ]));
    }

    // ---- goal dates and starting point (inline controls)
    function planField(id, label, value, onValue, attrs, help) {
        var f = numberField(id, label, value, (attrs && attrs.placeholder) || '', onValue, attrs);
        if (help) f.appendChild(el('div', { class: 'form-text small', text: help }));
        return el('div', { class: 'col-6 col-md-4 col-xl-3' }, [f]);
    }
    function clampIn(v, lo, hi) { return v === null ? null : Math.min(hi, Math.max(lo, v)); }
    function setGoal(key, v, lo, hi, def) { commit(function (s) { s.plan.goals[key] = v === null ? def : Math.round(clampIn(v, lo, hi)); }, 'Goal date updated'); }
    function setPlan(key, v, def, whole) {
        var r = PLAN_FIELDS[key];
        commit(function (s) { var x = v === null ? def : clampIn(v, r[0], r[1]); s.plan[key] = whole && x !== null ? Math.round(x) : x; if (s.plan.planningAge < s.plan.endAge) s.plan.planningAge = s.plan.endAge; }, 'Plan updated');
    }

    function renderGoalDates() {
        var box = $('goalDatesPanel');
        if (box.hidden) return;
        box.textContent = '';
        var g = state.plan.goals, pl = state.plan;
        box.appendChild(el('h3', { class: 'h6', text: 'When would you like each goal?' }));
        var row1 = el('div', { class: 'row g-2' });
        if (hasTile('house')) row1.appendChild(planField('goal-house', 'Buy a home at age', g.house, function (v) { setGoal('house', v, 14, 90, 30); }, { min: 14, max: 90, step: 1 }));
        if (hasTile('car')) row1.appendChild(planField('goal-car', 'Buy your car at age', g.car, function (v) { setGoal('car', v, 14, 90, null); }, { min: 14, max: 90, step: 1, placeholder: 'When work starts' }));
        if (hasTile('travel')) row1.appendChild(planField('goal-travel', 'Start traveling at age', g.travel, function (v) { setGoal('travel', v, 14, 90, null); }, { min: 14, max: 90, step: 1, placeholder: 'When work starts' }));
        if (hasTile('savings')) {
            row1.appendChild(planField('goal-savings-target', 'Savings target ($)', g.savingsTarget, function (v) { commit(function (s) { s.plan.goals.savingsTarget = v === null ? 10000 : clampIn(v, 0, 10000000); }, 'Savings target updated'); }, { min: 0, max: 10000000 }));
            row1.appendChild(planField('goal-savings', 'Reach it by age', g.savings, function (v) { setGoal('savings', v, 14, 90, 30); }, { min: 14, max: 90, step: 1 }));
        }
        row1.appendChild(planField('goal-retirement', 'Retire at age', g.retirement, function (v) { setGoal('retirement', v, 40, 90, 67); }, { min: 40, max: 90, step: 1 }));
        box.appendChild(row1);
        box.appendChild(el('h3', { class: 'h6 mt-3', text: 'Your starting point' }));
        var row2 = el('div', { class: 'row g-2' });
        row2.appendChild(planField('plan-start-age', 'Scenario starting age', state.timeline.startAge, function (v) { commit(function (s) { s.timeline.startAge = v === null ? 18 : Math.round(clampIn(v, 14, 40)); }, 'Starting age updated'); }, { min: 14, max: 40, step: 1 }, 'A what-if age, not your birth date.'));
        row2.appendChild(planField('plan-end-age', 'Timeline ends at age', pl.endAge, function (v) { setPlan('endAge', v, 70, true); }, { min: 60, max: 90, step: 1 }));
        row2.appendChild(planField('plan-planning-age', 'Check retirement money to age', pl.planningAge, function (v) { setPlan('planningAge', v, 95, true); }, { min: 60, max: 105, step: 1 }));
        row2.appendChild(planField('plan-cash', 'Cash you start with ($)', pl.startingCash, function (v) { setPlan('startingCash', v, 0); }, { min: 0, max: 10000000 }));
        row2.appendChild(planField('plan-investments', 'Savings/investments you start with ($)', pl.startingInvestments, function (v) { setPlan('startingInvestments', v, 0); }, { min: 0, max: 10000000 }));
        row2.appendChild(planField('plan-debt', 'Debt you already have ($)', pl.startingDebt, function (v) { setPlan('startingDebt', v, 0); }, { min: 0, max: 10000000 }, 'Repaid over 10 years.'));
        row2.appendChild(planField('plan-debt-rate', 'Interest on that debt (%)', pl.startingDebtRatePct, function (v) { setPlan('startingDebtRatePct', v, 7); }, { min: 0, max: 30 }));
        row2.appendChild(planField('plan-support', 'Family support while training ($/month)', pl.trainingSupportMonthly, function (v) { setPlan('trainingSupportMonthly', v, 0); }, { min: 0, max: 20000 }));
        row2.appendChild(planField('plan-study-income', 'Income from work while studying ($/month)', pl.studyIncomeMonthly, function (v) { setPlan('studyIncomeMonthly', v, 0); }, { min: 0, max: 20000 }));
        row2.appendChild(planField('plan-retire-income', 'Retirement income you expect ($/month)', pl.retirementIncomeMonthly, function (v) { setPlan('retirementIncomeMonthly', v, 0); }, { min: 0, max: 20000 }, 'For example a Social Security estimate or a pension. None is assumed.'));
        box.appendChild(row2);
        var kids = getTile('children');
        if (kids || hasTile('childcare') || state.earners.length > 1) {
            box.appendChild(el('h3', { class: 'h6 mt-3', text: 'Family timing' }));
            var row3 = el('div', { class: 'row g-2' });
            if (kids) row3.appendChild(planField('plan-first-child', 'First child arrives at your age', pl.firstChildAge, function (v) { setPlan('firstChildAge', v, 30, true); }, { min: 16, max: 60, step: 1 }));
            if (kids && kids.count > 1) row3.appendChild(planField('plan-child-spacing', 'Years between children', pl.childSpacingYears, function (v) { setPlan('childSpacingYears', v, 2, true); }, { min: 1, max: 10, step: 1 }));
            if (hasTile('childcare')) row3.appendChild(planField('plan-childcare-years', 'Years of daycare per child', pl.childcareYears, function (v) { setPlan('childcareYears', v, 5, true); }, { min: 0, max: 13, step: 1 }));
            if (state.earners.length > 1) row3.appendChild(planField('plan-earner2', 'Second earner starts working at your age', pl.secondEarnerAge, function (v) { setPlan('secondEarnerAge', v, null, true); }, { min: 14, max: 80, step: 1, placeholder: 'When your career starts' }));
            box.appendChild(row3);
        }
        box.appendChild(el('p', { class: 'small text-body-secondary mt-2 mb-0', text: 'Children, daycare and a second income only count when you add them. Changes update the timeline immediately and can be undone.' }));
    }

    function toggleGoalDates(open) {
        var box = $('goalDatesPanel');
        box.hidden = open === undefined ? !box.hidden : !open;
        document.querySelector('[data-action=goal-dates]').setAttribute('aria-expanded', String(!box.hidden));
        renderGoalDates();
        if (!box.hidden) { var first = box.querySelector('input'); if (first) first.focus(); }
    }

    // ---- See the numbers
    function renderNumbers(r) {
        var box = $('budgetNumbers');
        box.textContent = '';
        if (!r) return;
        var take = r.income.takeHomeMonthly, cost = r.costs.monthlyTotal;
        var hasIncome = r.income.earners.some(function (e) { return e.annualWage !== null; });
        var max = Math.max(take, cost, 1);
        box.appendChild(el('div', { class: 'hbars' }, [
            bar('Take-home pay', Math.max(0, take), max, 'fill-income'),
            bar('Monthly costs', cost, max, 'fill-cost')
        ]));
        var dl = el('dl', { class: 'kv mt-3' }, [
            el('dt', { text: 'Pay before taxes' }), el('dd', { text: FP.money(r.income.grossAnnual) + '/yr' }),
            el('dt', { text: 'Estimated taxes' }), el('dd', { text: FP.money(r.income.taxes.total) + '/yr (' + FP.pct(r.income.taxes.effectiveRate, 1) + ')' }),
            el('dt', { text: 'Pre-tax retirement' }), el('dd', { text: FP.money(r.income.pretaxRetirementAnnual) + '/yr' }),
            el('dt', { text: 'Take-home pay' }), el('dd', { text: hasIncome ? FP.money(take) + '/mo' : 'Not available' }),
            el('dt', { text: 'Left over / short' }), el('dd', { text: hasIncome ? FP.money(r.monthlySurplus, { signed: true }) + '/mo' : 'Not available' }),
            el('dt', { text: 'Costs covered' }), el('dd', { text: r.coveragePercent !== null ? Math.round(r.coveragePercent) + '%' : '—' })
        ]);
        box.appendChild(dl);
        box.appendChild(el('p', { class: 'small text-body-secondary mb-1', text: 'This is today\'s full budget with every card at once. The timeline above adds each cost at the age it starts.' }));
        if (r.upfront.downPayment > 0) box.appendChild(el('p', { class: 'small mb-1', text: 'Cash needed to buy: ' + FP.money(r.upfront.downPayment) + ' down payment + about ' + FP.money(r.upfront.closingCosts) + ' closing costs.' }));
        if (!r.complete) box.appendChild(el('p', { class: 'small text-warning-emphasis mb-1', text: 'Some numbers are missing, so this budget is incomplete.' }));
        if (r.warnings.length) {
            var ul = el('ul', { class: 'warnings small mb-0' });
            r.warnings.forEach(function (w) { ul.appendChild(el('li', { text: w })); });
            box.appendChild(ul);
        }
    }

    function renderCanvasSummaries() {
        document.querySelectorAll('#canvas .active-tile').forEach(function (li) {
            var t = getTile(li.dataset.tile);
            var d = li.querySelector('.tile-desc');
            if (t && d) d.textContent = tileSummary(t);
            var b = li.querySelector('.tile-toggle');
            if (t && b) b.setAttribute('aria-label', 'Change ' + TILES[t.type].label + ': ' + tileSummary(t));
        });
    }

    function renderBreakdown(r) {
        var box = $('breakdown');
        box.textContent = '';
        var stack = el('div', { class: 'stackbar', role: 'img', 'aria-label': 'Monthly costs by category' });
        var legend = el('ul', { class: 'legend small' });
        Object.keys(CATEGORY_LABELS).forEach(function (k, i) {
            var v = r.costs.categories[k];
            if (!v) return;
            var seg = el('span', { class: 'stack-seg c' + i, title: CATEGORY_LABELS[k] + ' ' + FP.money(v) });
            seg.style.width = (v / Math.max(1, r.costs.monthlyTotal) * 100) + '%';
            stack.appendChild(seg);
            legend.appendChild(el('li', {}, [el('span', { class: 'swatch c' + i, 'aria-hidden': 'true' }), CATEGORY_LABELS[k] + ' ' + FP.money(v)]));
        });
        if (r.income.taxes.total > 0) legend.appendChild(el('li', {}, [el('span', { class: 'swatch ctax', 'aria-hidden': 'true' }), 'Taxes ' + FP.money(r.income.taxes.total / 12) + ' (taken from pay)']));
        box.appendChild(stack);
        box.appendChild(legend);
        var table = el('table', { class: 'table table-sm budget-table mb-0' }, [
            el('caption', { class: 'visually-hidden', text: 'Monthly costs, line by line' }),
            el('thead', {}, [el('tr', {}, [el('th', { scope: 'col', text: 'Item' }), el('th', { scope: 'col', class: 'text-end', text: 'Per month' }), el('th', { scope: 'col', text: 'Basis' })])])
        ]);
        var tb = el('tbody');
        r.costs.lines.forEach(function (l) {
            tb.appendChild(el('tr', {}, [
                el('td', {}, [el('span', { text: l.label }), l.detail ? el('span', { class: 'd-block small text-body-secondary', text: l.detail }) : null]),
                el('td', { class: 'text-end', text: l.monthly === null ? 'Missing' : FP.money(l.monthly) }),
                el('td', {}, [el('span', { class: 'basis basis-' + l.basis, text: BASIS_LABELS[l.basis] || l.basis })])
            ]));
        });
        tb.appendChild(el('tr', { class: 'fw-semibold' }, [el('td', { text: 'Total' }), el('td', { class: 'text-end', text: FP.money(r.costs.monthlyTotal) }), el('td')]));
        table.appendChild(tb);
        box.appendChild(el('div', { class: 'table-responsive mt-2' }, [table]));
    }

    function renderEducation(r) {
        var box = $('educationPanel');
        box.textContent = '';
        var ed = r.education;
        if (!ed.pathway) { box.appendChild(el('p', { class: 'small mb-0', text: 'Choose a path in step 3 to see school costs and loans.' })); return; }
        var rows = [
            ['Path', ed.pathwayName || ed.pathway], ['Years in school/training', String(ed.years)],
            ['Yearly price used', ed.annualNetPrice === null ? 'Pick a school' : FP.money(ed.annualNetPrice) + (ed.priceBasis === 'sourced' ? ' (Scorecard average net price)' : ed.priceBasis === 'user' ? ' (yours)' : '')],
            ['Total out of pocket', FP.money(ed.totalCost, { fallback: '—' })], ['Borrowed (estimate)', FP.money(ed.borrowed, { fallback: '—' })],
            ['Loan payment', ed.monthlyPayment ? FP.money(ed.monthlyPayment) + '/mo for 10 years' : 'Add the Student debt card'],
            ['Interest over the loan', ed.totalInterest ? FP.money(ed.totalInterest) : '—']
        ];
        box.appendChild(el('dl', { class: 'kv small' }, rows.reduce(function (acc, row) { acc.push(el('dt', { text: row[0] })); acc.push(el('dd', { text: row[1] })); return acc; }, [])));
        var g = numberField('ed-grants', 'Extra scholarships per year (beyond average aid)', state.education.grantsAnnual || null, '0', function (v) { commit(function (s) { s.education.grantsAnnual = v || 0; }, 'Scholarships updated'); }, { max: 200000 });
        var f = numberField('ed-family', 'Family/work contribution per year', state.education.familyAnnual || null, '0', function (v) { commit(function (s) { s.education.familyAnnual = v || 0; }, 'Family contribution updated'); }, { max: 200000 });
        var p = numberField('ed-price', 'Or enter your own yearly price', state.education.annualNetPrice, 'Uses the school average net price', function (v) { commit(function (s) { s.education.annualNetPrice = v; }, 'School price updated'); }, { max: 200000 });
        box.appendChild(g); box.appendChild(f); box.appendChild(p);
        box.appendChild(el('p', { class: 'small text-body-secondary mb-0', text: 'Average net price already subtracts typical grants for students who get aid; your aid may differ. Interest that builds up while in school is not included. Aid is individual: check studentaid.gov.' }));
    }

    function renderTimeline(r) {
        var box = $('timelinePanel');
        box.textContent = '';
        if (!r.timeline.length) return;
        var head = el('tr', {}, [el('th', { scope: 'col', text: 'Age' })].concat(r.timeline.map(function (p) { return el('th', { scope: 'col', class: 'text-end', text: String(p.age) }); })));
        var rows = [
            ['Stage', function (p) { return p.phase === 'school' ? 'School' : 'Working'; }],
            ['Pay (yr)', function (p) { return FP.money(p.wage); }],
            ['Take-home (yr)', function (p) { return FP.money(p.takeHome); }],
            ['Living costs (yr)', function (p) { return p.phase === 'school' ? 'n/a' : FP.money(p.livingCosts); }],
            ['School cost (yr)', function (p) { return FP.money(p.educationCost); }],
            ['Student debt owed', function (p) { return FP.money(p.debtBalance); }],
            ['Saved/short so far', function (p) { return FP.money(p.cumulativeSurplus); }]
        ];
        var tb = el('tbody');
        rows.forEach(function (row) { tb.appendChild(el('tr', {}, [el('th', { scope: 'row', text: row[0] })].concat(r.timeline.map(function (p) { return el('td', { class: 'text-end', text: row[1](p) }); })))); });
        box.appendChild(el('div', { class: 'table-responsive' }, [el('table', { class: 'table table-sm timeline-table mb-1' }, [el('caption', { class: 'visually-hidden', text: 'Timeline by age' }), el('thead', {}, [head]), tb])]));
        box.appendChild(el('p', { class: 'small text-body-secondary mb-0', text: state.timeline.mode === 'today'
            ? "Today's dollars: pay and prices are held at today's levels. Real careers usually change; this is a scenario, not a prediction. Living costs during school aren't modeled."
            : 'Projection uses your assumed yearly raise and inflation (Advanced assumptions). BLS percentiles are not a career ladder.' }));
    }

    function renderSources(r, b) {
        var box = $('sourcesPanel');
        box.textContent = '';
        var ul = el('ul', { class: 'mb-2' });
        r.citations.forEach(function (c) { ul.appendChild(el('li', {}, [c.url ? el('a', { href: c.url, target: '_blank', rel: 'noopener', text: c.text }) : c.text])); });
        box.appendChild(ul);
        var dy = b.dataYears || {};
        box.appendChild(el('p', { class: 'mb-1', text: 'Data years: wages May ' + dy.wages + '; rent ' + (dy.rentAcs || 'n/a') + ' (ACS) / ' + (dy.rentHud || 'n/a') + ' (HUD); home value ' + (dy.homeValue || 'n/a') + '; food ' + (dy.food || 'n/a') + '; tax year ' + dy.taxYear + '.' }));
        box.appendChild(el('p', { class: 'mb-0 text-body-secondary', text: 'Lines marked "Assumption" use FuturePath defaults you can change in Advanced assumptions. Taxes are a simplified estimate (standard deduction, wages only). ' }));
        if (lastProjection && lastProjection.provenance) {
            var pr = lastProjection.provenance;
            box.appendChild(el('p', { class: 'mt-2 mb-1 fw-semibold', text: 'Projection assumptions' }));
            box.appendChild(el('p', { class: 'mb-1', text: 'Dollar basis: today\'s dollars. Surplus rule: ' + pr.assumptions.surplusRule + ' Investment growth ' + pr.assumptions.investmentReturnPct + '%/yr. Emergency reserve ' + pr.assumptions.emergencyReserveMonths + ' months. Training living cost ' + FP.money(pr.assumptions.trainingLivingMonthly) + '/mo. Retirement income entered: ' + FP.money(pr.assumptions.retirementIncomeMonthly) + '/mo.' }));
            var om = el('ul', { class: 'mb-2' });
            (pr.omissions || []).forEach(function (o) { om.appendChild(el('li', { text: o })); });
            box.appendChild(om);
            if (pr.unavailable && pr.unavailable.length) {
                var miss = el('ul', { class: 'mb-2' });
                pr.unavailable.forEach(function (m) { miss.appendChild(el('li', { text: 'Unavailable: ' + m.text })); });
                box.appendChild(miss);
            }
        }
        box.appendChild(el('a', { href: '/sources', text: 'All sources and assumptions' }));
    }

    // ------------------------------------------------------------------ tradeoff suggestions
    var suggestionSeq = 0;
    function renderSuggestions(r, b) {
        var box = $('suggestions');
        box.textContent = '';
        var hasIncome = r.income.earners.some(function (e) { return e.annualWage !== null; });
        if (!hasIncome) {
            box.appendChild(el('div', { class: 'd-flex flex-wrap gap-2' }, [
                el('button', { type: 'button', class: 'btn btn-sm btn-primary', onclick: function () { runReverse(); } }, ['Find careers that pay for this']),
                el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { $('careerInput').focus(); } }, ['Pick a career'])
            ]));
            return;
        }
        if (r.monthlySurplus >= 0) return;
        box.appendChild(el('p', { class: 'small fw-semibold mb-2', text: 'Ways to close the ' + FP.money(-r.monthlySurplus) + '/month gap:' }));
        box.appendChild(el('div', { class: 'd-flex flex-wrap gap-2' }, [
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { runReverse(); } }, ['Explore higher-paying careers']),
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { tryOtherCities(); } }, ['Try another city']),
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { adjustHousing(); } }, ['Adjust housing']),
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', onclick: function () { lowerCostPath(); } }, ['See a lower-cost path'])
        ]));
        box.appendChild(el('div', { id: 'suggestionResults', class: 'mt-2', 'aria-live': 'polite' }));
    }

    function suggestionList(title, items, emptyText) {
        var out = $('suggestionResults') || $('actionResults');
        if (!out) return;
        out.textContent = '';
        out.appendChild(el('div', { class: 'small fw-semibold mb-1', text: title }));
        if (!items.length) { out.appendChild(el('p', { class: 'small mb-0', text: emptyText })); return; }
        var ul = el('ul', { class: 'list-unstyled suggestion-list mb-0' });
        items.forEach(function (it) {
            ul.appendChild(el('li', {}, [
                el('span', { text: it.label }),
                el('span', { class: 'ms-1 ' + (it.surplus >= 0 ? 'text-success-emphasis' : 'text-danger-emphasis'), text: it.surplus >= 0 ? FP.money(it.surplus) + ' left' : FP.money(-it.surplus) + ' short' }),
                el('button', { type: 'button', class: 'btn btn-link btn-sm p-0 ms-2', onclick: it.apply }, ['Apply'])
            ]));
        });
        out.appendChild(ul);
    }

    function variant(mutator) {
        var s = JSON.parse(JSON.stringify(state));
        mutator(s);
        return { s: s, r: E.compute(s, current.bundle, DEF, { includeTimeline: false }) };
    }

    function adjustHousing() {
        var items = [];
        var apt = getTile('apartment'), house = getTile('house');
        if (house) {
            var v = variant(function (s) { s.tiles = s.tiles.filter(function (t) { return t.type !== 'house'; }); if (!s.tiles.some(function (t) { return t.type === 'apartment'; })) s.tiles.unshift(defaultTile('apartment')); s.tiles.filter(function (t) { return t.type === 'apartment'; })[0].bedrooms = Math.min(4, house.bedrooms); });
            items.push({ label: 'Rent a ' + Math.min(4, house.bedrooms) + '-bedroom instead of buying:', surplus: v.r.monthlySurplus, apply: function () { commit(function (s) { s.tiles = v.s.tiles; }, 'Switched to renting'); } });
        }
        if (apt && apt.bedrooms > 0) {
            var v2 = variant(function (s) { s.tiles.filter(function (t) { return t.type === 'apartment'; })[0].bedrooms = apt.bedrooms - 1; });
            items.push({ label: 'One fewer bedroom (' + (apt.bedrooms - 1 === 0 ? 'studio' : apt.bedrooms - 1 + ' BR') + '):', surplus: v2.r.monthlySurplus, apply: function () { updateTile('apartment', { bedrooms: apt.bedrooms - 1 }, 'Bedrooms reduced'); } });
        }
        if (apt && !getTile('roommates') && !getTile('children')) {
            var v3 = variant(function (s) { s.tiles.push({ type: 'roommates', count: 1 }); var a = s.tiles.filter(function (t) { return t.type === 'apartment'; })[0]; if (a.bedrooms < 2) a.bedrooms = 2; });
            items.push({ label: 'Share a 2-bedroom with a roommate:', surplus: v3.r.monthlySurplus, apply: function () { commit(function (s) { s.tiles = v3.s.tiles; }, 'Roommate added'); } });
        }
        if (getTile('second_car')) {
            var v4 = variant(function (s) { s.tiles = s.tiles.filter(function (t) { return t.type !== 'second_car'; }); });
            items.push({ label: 'One car instead of two:', surplus: v4.r.monthlySurplus, apply: function () { removeTile('second_car'); } });
        }
        var houseTiers = Object.keys(PRESETS.house);
        var houseIdx = house ? houseTiers.indexOf(house.tier) : -1;
        if (house && house.price === null && houseIdx > 0) {
            var smaller = houseTiers[houseIdx - 1];
            var v5 = variant(function (s) { var h = s.tiles.filter(function (t) { return t.type === 'house'; })[0]; h.tier = smaller; h.bedrooms = PRESETS.house[smaller].bedrooms; });
            items.push({ label: 'A ' + PRESETS.house[smaller].label.toLowerCase() + ' home instead:', surplus: v5.r.monthlySurplus, apply: function () { updateTile('house', { tier: smaller, bedrooms: PRESETS.house[smaller].bedrooms }, PRESETS.house[smaller].label + ' home'); } });
        }
        ['car', 'second_car'].forEach(function (ct) {
            var c = getTile(ct);
            if (!c || c.price !== null || c.tier === 'compact' || !PRESETS.car.compact) return;
            var v6 = variant(function (s) { s.tiles.filter(function (t) { return t.type === ct; })[0].tier = 'compact'; });
            items.push({ label: 'A compact ' + (ct === 'car' ? 'car' : 'second car') + ' (' + PRESETS.car.compact.examples.split(',')[0] + '):', surplus: v6.r.monthlySurplus, apply: function () { updateTile(ct, { tier: 'compact' }, 'Compact car'); } });
        });
        suggestionList('Housing and car changes (same city and career)', items, 'No housing changes to suggest. Try another city or career.');
    }

    function tryOtherCities() {
        var mySeq = ++suggestionSeq;
        var others = BOOT.featured.filter(function (m) { return m.cbsa !== state.cbsa; });
        $('suggestionResults').textContent = 'Checking other cities...';
        Promise.all(others.map(function (m) {
            var s = JSON.parse(JSON.stringify(state));
            s.cbsa = m.cbsa; s.state = m.states[0]; s.nycResident = false;
            if (s.education.unitid) s.education.unitid = s.education.unitid; // school stays the same
            return fetchBundle(s).then(function (bundle) { return { m: m, s: s, r: E.compute(s, bundle, DEF, { includeTimeline: false }) }; }).catch(function () { return null; });
        })).then(function (rows) {
            if (mySeq !== suggestionSeq) return;
            var items = rows.filter(Boolean).map(function (x) {
                var missing = !x.r.complete ? ' (some data missing)' : '';
                return { label: x.m.name + missing + ':', surplus: x.r.monthlySurplus, apply: function () { chooseMetro(x.m.cbsa, x.m.states); } };
            });
            suggestionList('Same life and career in another city', items, 'No other cities could be compared.');
        });
    }

    function lowerCostPath() {
        var mySeq = ++suggestionSeq;
        var ed = state.education;
        if (!ed.cip || !ed.unitid) {
            suggestionList('Lower-cost education paths', [], 'Pick a college and program first, or compare an apprenticeship or community college path in step 3.');
            return;
        }
        $('suggestionResults').textContent = 'Looking for imported schools with the same program...';
        FP.api('/api/v1/institutions?limit=30&cip=' + encodeURIComponent(ed.cip)).then(function (list) {
            if (mySeq !== suggestionSeq) return;
            var cheaper = list.filter(function (i) { return i.unitid !== ed.unitid && i.costs.averageNetPrice !== null; })
                .sort(function (a, b) { return a.costs.averageNetPrice - b.costs.averageNetPrice; }).slice(0, 4);
            var items = cheaper.map(function (i) {
                var v = variant(function (s) { s.education.annualNetPrice = i.costs.averageNetPrice; });
                return { label: i.name + ' (net price ' + FP.money(i.costs.averageNetPrice) + '/yr):', surplus: v.r.monthlySurplus,
                    apply: function () { chooseCollege(i); } };
            });
            suggestionList('Same program at other imported schools (Scorecard average net price)', items, 'No other imported school reports this program with a net price.');
        }).catch(function (err) { if (mySeq === suggestionSeq) suggestionList('Lower-cost education paths', [], err.message); });
    }

    // ------------------------------------------------------------------ reverse search
    var reverseSeq = 0;
    function runReverse() {
        var mySeq = ++reverseSeq;
        var box = $('reverseResults');
        box.textContent = '';
        box.appendChild(el('p', { class: 'small', text: 'Calculating the pay this life needs and checking local wages...' }));
        $('reversePanel').scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
        FP.api('/api/v1/simulations/reverse-careers', { method: 'POST', body: { scenario: state, options: {
            percentile: $('reversePercentile').value, sort: $('reverseSort').value, maxTrainingYears: Number($('reverseYears').value), limit: 24 } } }).then(function (d) {
            if (mySeq !== reverseSeq) return;
            renderReverse(d);
        }).catch(function (err) {
            if (mySeq !== reverseSeq) return;
            box.textContent = '';
            box.appendChild(el('div', { class: 'alert alert-warning', text: err.message }));
        });
    }

    function careerCard(c, needed) {
        var margin = c.margin;
        return draggableCard({ kind: 'career', soc: c.soc, title: c.title }, [
            el('div', { class: 'pick-card-main' }, [
                el('span', { class: 'fw-semibold', text: c.title }),
                el('span', { class: 'small', text: FP.money(c.wage) + '/yr local ' + (c.percentile === 'median' ? 'median' : c.percentile.replace('p', '') + 'th pct') + (margin !== null ? ' · ' + (margin >= 0 ? FP.money(margin) + ' above need' : FP.money(-margin) + ' below need') : '') }),
                el('span', { class: 'small text-body-secondary', text: (c.pathwayName ? 'Typical path: ' + c.pathwayName + (c.trainingYears !== null ? ' (' + c.trainingYears + ' yrs)' : '') : (c.entryEducation || 'Entry education not listed')) + (c.outlookPercent !== null && c.outlookPercent !== undefined ? ' · BLS outlook ' + (c.outlookPercent > 0 ? '+' : '') + c.outlookPercent + '% (' + c.outlookPeriod + ')' : '') + (c.employment ? ' · ' + c.employment.toLocaleString('en-US') + ' local jobs' : '') })
            ]),
            el('button', { type: 'button', class: 'btn btn-sm btn-outline-primary', 'aria-label': 'Try ' + c.title + ' in the builder', onclick: function () { chooseCareer(c.soc, c.title); window.scrollTo({ top: 0, behavior: 'auto' }); } }, ['Try it'])
        ]);
    }

    function renderReverse(d) {
        var box = $('reverseResults');
        box.textContent = '';
        if (!d.required) {
            box.appendChild(el('div', { class: 'alert alert-info', text: 'This budget is above what any wage could cover in our calculator. Try removing some cards.' }));
            return;
        }
        box.appendChild(el('div', { class: 'need-box' }, [
            el('div', { class: 'small', text: 'To cover ' + FP.money(d.required.monthlyCosts) + ' a month after taxes, ' + (state.earners.length > 1 ? 'earner 1 needs about' : 'you need about') }),
            el('div', { class: 'need-amount', text: FP.money(d.required.earner1Gross) + ' a year before taxes' }),
            state.earners.length > 1 ? el('div', { class: 'small', text: 'Household total: ' + FP.money(d.required.householdGross) + '/yr' }) : null
        ]));
        box.appendChild(el('p', { class: 'small text-body-secondary', text: d.explanation }));
        var grid = el('div', { class: 'row g-3' });
        var col1 = el('div', { class: 'col-md-6' }, [el('h3', { class: 'h6', text: d.affordableCount + ' careers could cover it here' })]);
        var l1 = el('div', { class: 'pick-list' });
        d.affordable.forEach(function (c) { l1.appendChild(careerCard(c)); });
        if (!d.affordable.length) l1.appendChild(el('p', { class: 'small', text: 'None at this pay level with these filters. Try fewer cards, a two-earner household or another city.' }));
        col1.appendChild(l1);
        var col2 = el('div', { class: 'col-md-6' }, [el('h3', { class: 'h6', text: 'Close, with a tradeoff' })]);
        var l2 = el('div', { class: 'pick-list' });
        d.close.slice(0, 12).forEach(function (c) { l2.appendChild(careerCard(c)); });
        col2.appendChild(l2);
        grid.appendChild(col1); grid.appendChild(col2);
        box.appendChild(grid);
        box.appendChild(el('p', { class: 'small text-body-secondary mt-2 mb-0', text: d.occupationsWithoutPublishedWage + ' occupations have no published wage at this level in this metro and are not ranked. Source: ' + d.source.name + '.' }));
    }

    // ------------------------------------------------------------------ compare futures
    var futures = [];
    var futureSeq = 0;
    function showActions() {
        var box = $('actionResults');
        if (!box.querySelector('#suggestionResults')) box.appendChild(el('div', { id: 'suggestionResults' }));
        box.scrollIntoView({ block: 'nearest' });
    }

    function addFuture(scenario) {
        if (futures.length >= 3) { FP.announce('You can compare up to three futures.'); return; }
        futures.push({ id: ++futureSeq, scenario: JSON.parse(JSON.stringify(scenario || state)), result: null, bundleKey: '', reqSeq: 0, linked: futures.length === 0 });
        $('comparePanel').hidden = false;
        renderCompare();
        futures.forEach(computeFuture);
        $('comparePanel').scrollIntoView({ block: 'start' });
        FP.announce('Future ' + futures.length + ' added to the comparison.');
    }
    function refreshCompareFromState() { /* columns are independent copies; nothing to sync */ }

    function computeFuture(f) {
        var key = bundleKey(f.scenario);
        var my = ++f.reqSeq;
        f.loading = true;
        fetchBundle(f.scenario).then(function (b) {
            if (my !== f.reqSeq) return;
            f.loading = false;
            f.bundle = b;
            f.result = E.compute(f.scenario, b, DEF);
            f.bundleKey = key;
            renderCompare();
        }).catch(function (err) { if (my !== f.reqSeq) return; f.loading = false; f.error = err.message; renderCompare(); });
    }

    function updateFuture(f, mutator) {
        mutator(f.scenario);
        computeFuture(f);
        renderCompare();
    }

    function compareValue(f, key) {
        var r = f.result;
        if (!r) return null;
        switch (key) {
            case 'city': return f.bundle ? f.bundle.metro.shortName : '';
            case 'career': return r.income.earners[0] ? (r.income.earners[0].title || 'Not chosen') : 'Not chosen';
            case 'gross': return FP.money(r.income.grossAnnual) + '/yr';
            case 'take': return FP.money(r.income.takeHomeMonthly);
            case 'costs': return FP.money(r.costs.monthlyTotal);
            case 'gap': return (r.monthlySurplus >= 0 ? '+' : '') + FP.money(r.monthlySurplus);
            case 'school': return r.education.totalCost === null ? '—' : FP.money(r.education.totalCost);
            case 'debt': return r.education.borrowed === null ? '—' : FP.money(r.education.borrowed);
            case 'at30': var p = r.timeline.filter(function (t) { return t.age === 30; })[0]; return p ? FP.money(p.cumulativeSurplus) : '—';
            case 'cards': return f.scenario.tiles.map(function (t) { return TILES[t.type].label; }).join(', ');
        }
        return '';
    }

    function renderCompare() {
        var grid = $('compareGrid');
        grid.textContent = '';
        $('comparePanel').hidden = !futures.length;
        var rows = [['city', 'City'], ['career', 'Career'], ['cards', 'Lifestyle'], ['gross', 'Pay before taxes'], ['take', 'Take-home / month'], ['costs', 'Costs / month'], ['gap', 'Left over / short'], ['school', 'School cost (total)'], ['debt', 'Borrowed'], ['at30', 'Saved by age 30']];
        futures.forEach(function (f, idx) {
            var col = el('div', { class: 'compare-col', dataset: { future: String(f.id) } });
            col.addEventListener('dragover', function (e) { e.preventDefault(); col.classList.add('drag-over'); });
            col.addEventListener('dragleave', function () { col.classList.remove('drag-over'); });
            col.addEventListener('drop', function (e) {
                e.preventDefault(); col.classList.remove('drag-over');
                var d = readDrag(e); if (!d) return;
                if (d.kind === 'tile') updateFuture(f, function (s) { if (!s.tiles.some(function (t) { return t.type === d.type; })) s.tiles.push(defaultTile(d.type)); });
                if (d.kind === 'career') updateFuture(f, function (s) { s.earners[0].soc = d.soc; s.earners[0].customWage = null; });
            });
            col.appendChild(el('div', { class: 'd-flex align-items-center justify-content-between mb-2' }, [
                el('h3', { class: 'h6 mb-0', text: 'Future ' + (idx + 1) }),
                el('button', { type: 'button', class: 'icon-btn icon-remove', 'aria-label': 'Remove future ' + (idx + 1), onclick: function () { futures = futures.filter(function (x) { return x !== f; }); renderCompare(); } }, ['×'])
            ]));
            var citySel = el('select', { class: 'form-select form-select-sm mb-2', 'aria-label': 'City for future ' + (idx + 1) });
            var metros = BOOT.featured.slice();
            if (!metros.some(function (m) { return m.cbsa === f.scenario.cbsa; }) && cache.metros[f.scenario.cbsa]) metros.push({ cbsa: f.scenario.cbsa, name: cache.metros[f.scenario.cbsa].name, states: cache.metros[f.scenario.cbsa].states.map(function (s) { return s.code; }) });
            metros.forEach(function (m) { var o = el('option', { value: m.cbsa, text: m.name }); if (m.cbsa === f.scenario.cbsa) o.selected = true; citySel.appendChild(o); });
            citySel.addEventListener('change', function () {
                var m = metros.filter(function (x) { return x.cbsa === citySel.value; })[0];
                updateFuture(f, function (s) { s.cbsa = m.cbsa; s.state = m.states[0]; s.nycResident = false; });
            });
            col.appendChild(citySel);
            var tId = 'cmp-career-' + f.id;
            var ta = el('div', { class: 'fp-typeahead mb-2' }, [
                el('label', { class: 'visually-hidden', for: tId, text: 'Career for future ' + (idx + 1) }),
                el('input', { id: tId, class: 'form-control form-control-sm', type: 'text', autocomplete: 'off', role: 'combobox', 'aria-autocomplete': 'list', 'aria-expanded': 'false', 'aria-controls': tId + '-list', placeholder: 'Swap career...' }),
                el('ul', { id: tId + '-list', class: 'fp-listbox', role: 'listbox', hidden: true })
            ]);
            col.appendChild(ta);
            FP.Typeahead(ta, {
                minChars: 2,
                search: function (q, signal) { return FP.api('/api/v1/occupations?limit=8&cbsa=' + f.scenario.cbsa + '&q=' + encodeURIComponent(q), { signal: signal }); },
                render: function (o) { return { label: o.title, detail: o.localStatus === 'available' ? 'local median ' + FP.money(o.localMedian) : 'no local wage' }; },
                onSelect: function (o) { cache.occupations[o.soc] = cache.occupations[o.soc] || { title: o.title }; updateFuture(f, function (s) { s.earners[0].soc = o.soc; s.earners[0].customWage = null; }); }
            });
            var chips = el('div', { class: 'chip-row mb-2', role: 'group', 'aria-label': 'Lifestyle cards for future ' + (idx + 1) });
            TILE_ORDER.forEach(function (type) {
                var on = f.scenario.tiles.some(function (t) { return t.type === type; });
                chips.appendChild(el('button', { type: 'button', class: 'chip chip-sm', 'aria-pressed': String(on), onclick: function () {
                    updateFuture(f, function (s) { if (on) s.tiles = s.tiles.filter(function (t) { return t.type !== type; }); else s.tiles.push(defaultTile(type)); });
                } }, [TILES[type].icon + ' ' + TILES[type].label]));
            });
            col.appendChild(chips);
            var dl = el('dl', { class: 'compare-dl' });
            rows.forEach(function (row) {
                var v = compareValue(f, row[0]);
                var differs = futures.length > 1 && futures.some(function (o) { return o !== f && compareValue(o, row[0]) !== v; });
                dl.appendChild(el('dt', { text: row[1] }));
                dl.appendChild(el('dd', { class: differs ? 'is-diff' : '', text: f.loading && !f.result ? 'Loading...' : (v === null ? '—' : v) }));
            });
            col.appendChild(dl);
            if (f.error) col.appendChild(el('p', { class: 'small text-danger', text: f.error }));
            col.appendChild(el('button', { type: 'button', class: 'btn btn-sm btn-outline-secondary w-100', onclick: function () {
                commit(function (s) { var copy = JSON.parse(JSON.stringify(f.scenario)); Object.keys(copy).forEach(function (k) { s[k] = copy[k]; }); }, 'Loaded future ' + (idx + 1) + ' into the builder');
                window.scrollTo({ top: 0 });
            } }, ['Edit in builder']));
            grid.appendChild(col);
        });
    }

    // ------------------------------------------------------------------ toolbar
    function encodeScenario(s) {
        var json = JSON.stringify(s);
        var b64 = window.btoa(unescape(encodeURIComponent(json)));
        return b64.replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
    }
    function decodeScenario(str) {
        try {
            var b64 = str.replace(/-/g, '+').replace(/_/g, '/');
            while (b64.length % 4) b64 += '=';
            return JSON.parse(decodeURIComponent(escape(window.atob(b64))));
        } catch (e) { return null; }
    }
    function copyLink() {
        var url = window.location.origin + '/builder#s=' + encodeScenario(state);
        var done = function () { FP.announce('Link copied. It contains only your choices, nothing personal.'); flashButton('copy-link', 'Copied!'); };
        if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(url).then(done, function () { window.prompt('Copy this link:', url); });
        else window.prompt('Copy this link:', url);
        history.replaceState(null, '', '/builder#s=' + encodeScenario(state));
    }
    function flashButton(action, text) {
        var b = document.querySelector('[data-action=' + action + ']');
        if (!b) return;
        var old = b.textContent; b.textContent = text;
        window.setTimeout(function () { b.textContent = old; }, 1600);
    }
    function bindToolbar() {
        document.addEventListener('click', function (e) {
            var btn = e.target.closest('[data-action]');
            if (!btn) return;
            switch (btn.dataset.action) {
                case 'undo': undo(); break;
                case 'redo': redo(); break;
                case 'reset': commit(function (s) { var d = defaultScenario(); Object.keys(d).forEach(function (k) { s[k] = d[k]; }); }, 'Scenario reset'); $('careerInput').value = ''; $('collegeInput').value = ''; $('possibleCareers').textContent = ''; break;
                case 'copy-link': copyLink(); break;
                case 'print': document.querySelectorAll('#numbersDetails, #sourcesDetails, #textTimelineDetails').forEach(function (d) { d.open = true; }); window.print(); break;
                case 'compare-add': addFuture(); break;
                case 'reverse': runReverse(); break;
                case 'adjust-lifestyle': showActions(); adjustHousing(); $('lifeHeading').scrollIntoView({ block: 'start' }); break;
                case 'goal-dates': toggleGoalDates(); break;
            }
        });
        document.addEventListener('keydown', function (e) {
            if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key.toLowerCase() === 'z' && !/input|select|textarea/i.test(document.activeElement.tagName)) { e.preventDefault(); undo(); }
            if ((e.ctrlKey || e.metaKey) && (e.key.toLowerCase() === 'y' || (e.shiftKey && e.key.toLowerCase() === 'z')) && !/input|select|textarea/i.test(document.activeElement.tagName)) { e.preventDefault(); redo(); }
        });
    }

    function renderAll() {
        renderPalette();
        renderCanvas();
        syncControls();
        renderPathSummary();
        renderTileModal();
        if (current.bundle && current.bundle.metro.cbsa === state.cbsa) renderMetro(current.bundle);
    }

    // ------------------------------------------------------------------ boot
    function loadPathwayOptions() {
        return FP.api('/api/v1/pathways').then(function (list) {
            cache.pathways = {};
            var sel = $('pathwaySelect');
            list.forEach(function (p) {
                cache.pathways[p.key] = p;
                sel.appendChild(el('option', { value: p.key, text: p.name + (p.typicalYears ? ' (~' + p.typicalYears + ' yrs)' : '') }));
            });
            sel.value = state.education.pathway || '';
            renderSchoolPicker();
        }).catch(function () { /* pathway list is optional */ });
    }

    function initialScenario() {
        var hash = window.location.hash.match(/s=([A-Za-z0-9_\-]+)/);
        if (hash) { var decoded = decodeScenario(hash[1]); if (decoded) return Promise.resolve(sanitize(decoded)); }
        if (BOOT.sharedId) {
            return FP.api('/api/v1/scenarios/' + BOOT.sharedId).then(function (d) { return sanitize(d.scenario); }).catch(function () { return defaultScenario(); });
        }
        if (FP.storage.get('fp.remember') === true) { var saved = FP.storage.get('fp.scenario'); if (saved) return Promise.resolve(sanitize(saved)); }
        return Promise.resolve(defaultScenario());
    }

    function start() {
        bindDropZones();
        bindToolbar();
        initPickers();
        Promise.all([initialScenario(), loadPathwayOptions()]).then(function (res) {
            state = res[0];
            renderAll();
            ensureBundle();
            state.earners.forEach(function (e, i) { if (e.soc) FP.api('/api/v1/occupations/' + e.soc).then(function (o) { cache.occupations[e.soc] = { title: o.title, pathways: o.pathways }; renderAll(); }).catch(function () {}); });
            if (state.education.unitid) loadPrograms(state.education.unitid);
            if (state.education.cip) loadCareersForCip(state.education.cip, '');
            if (BOOT.start === 'job') $('careerInput').focus();
            else if (BOOT.start === 'school') { var tab = $('tab-school'); if (tab && window.bootstrap) window.bootstrap.Tab.getOrCreateInstance(tab).show(); $('pathwaySelect').focus(); }
        });
    }

    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();

    // Exposed for automated UI tests only (no secrets in here).
    window.FPBuilder = { getState: function () { return JSON.parse(JSON.stringify(state)); }, addTile: addTile, removeTile: removeTile, undo: undo, redo: redo, lastResult: function () { return lastResult; }, lastProjection: function () { return lastProjection; }, setAge: setAge };
}(window, document));
