/*
 * Development-only UI tests for the Future Builder (served at /dev/ui-tests, run in a real browser or headless:
 *   chrome --headless=new --dump-dom --virtual-time-budget=90000 http://127.0.0.1:42005/dev/ui-tests
 * Each check prints PASS/FAIL into #results.
 */
(function () {
    'use strict';
    var out = document.getElementById('results');
    var pass = 0, fail = 0;
    function log(ok, name, detail) {
        if (ok) pass++; else fail++;
        out.textContent += (ok ? 'PASS ' : 'FAIL ') + name + (detail ? ' :: ' + detail : '') + '\n';
    }
    function sleep(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
    async function waitFor(fn, ms, label) {
        var t0 = Date.now();
        while (Date.now() - t0 < (ms || 15000)) {
            try { var v = fn(); if (v) return v; } catch (e) { /* not ready */ }
            await sleep(100);
        }
        throw new Error('timeout waiting for ' + (label || 'condition'));
    }
    function frame(id) { return document.getElementById(id).contentWindow; }
    function q(w, sel) { return w.document.querySelector(sel); }
    function tilesOf(w) { return w.FPBuilder.getState().tiles.map(function (t) { return t.type; }); }
    function costs(w) { var r = w.FPBuilder.lastResult(); return r ? Math.round(r.costs.monthlyTotal * 100) / 100 : null; }
    function dragDrop(w, sourceSel, targetSel) {
        var src = q(w, sourceSel), dst = q(w, targetSel);
        var dt = new w.DataTransfer();
        src.dispatchEvent(new w.DragEvent('dragstart', { bubbles: true, cancelable: true, dataTransfer: dt }));
        var rect = dst.getBoundingClientRect();
        var opts = { bubbles: true, cancelable: true, dataTransfer: dt, clientX: rect.left + 5, clientY: rect.bottom - 2 };
        dst.dispatchEvent(new w.DragEvent('dragover', opts));
        dst.dispatchEvent(new w.DragEvent('drop', opts));
        src.dispatchEvent(new w.DragEvent('dragend', { bubbles: true, dataTransfer: dt }));
    }
    async function reset(w) {
        q(w, '[data-action=reset]').click();
        await waitFor(function () { return w.FPBuilder.lastResult() && tilesOf(w).join() === 'apartment'; }, 15000, 'reset');
    }

    async function run() {
        var w = frame('desk');
        try {
            await waitFor(function () { return w.FPBuilder && w.FPBuilder.lastResult(); }, 30000, 'builder first result');
            w.__noReloadMarker = 42;
            log(true, 'builder renders a first result without a Calculate button');

            // Button path vs drag path reach identical scenario states.
            await reset(w);
            q(w, '#palette [data-tile=car] button').click();
            q(w, '#palette [data-tile=children] button').click();
            var viaButtons = JSON.stringify(w.FPBuilder.getState().tiles);
            var costButtons = costs(w);
            await reset(w);
            dragDrop(w, '#palette [data-tile=car]', '#canvas');
            dragDrop(w, '#palette [data-tile=children]', '#canvas');
            var viaDrag = JSON.stringify(w.FPBuilder.getState().tiles);
            log(viaButtons === viaDrag, 'drag-and-drop and Add buttons produce identical states', viaDrag);
            log(costs(w) === costButtons && costButtons > 0, 'identical budgets for both input methods', costs(w) + ' vs ' + costButtons);

            // Keyboard: the Add/Remove controls are real, focusable buttons with accessible names.
            var addBtn = q(w, '#palette [data-tile=travel] button');
            addBtn.focus();
            log(w.document.activeElement === addBtn && /Add Travel/.test(addBtn.getAttribute('aria-label')), 'Add buttons are keyboard focusable with accessible names');
            var before = costs(w);
            addBtn.click();
            await waitFor(function () { return costs(w) !== before; }, 5000, 'travel added');
            log(tilesOf(w).indexOf('travel') >= 0 && costs(w) > before, 'adding a tile updates the budget immediately', before + ' -> ' + costs(w));

            // Undo restores the previous numbers; redo re-applies.
            q(w, '[data-action=undo]').click();
            await waitFor(function () { return costs(w) === before; }, 5000, 'undo');
            log(tilesOf(w).indexOf('travel') < 0 && costs(w) === before, 'Undo restores previous values');
            q(w, '[data-action=redo]').click();
            await waitFor(function () { return tilesOf(w).indexOf('travel') >= 0; }, 5000, 'redo');
            log(true, 'Redo re-applies the change');

            // Remove via button and via dragging back to the palette.
            q(w, '#canvas [data-tile=travel] .icon-remove').click();
            log(tilesOf(w).indexOf('travel') < 0, 'Remove button removes a tile');
            dragDrop(w, '#canvas [data-tile=children]', '#palette');
            log(tilesOf(w).indexOf('children') < 0, 'dragging a tile out of My Future removes it');

            // Inline editing without a page transition.
            q(w, '#canvas [data-tile=apartment] .tile-toggle').click();
            var twoBr = await waitFor(function () { return Array.prototype.filter.call(w.document.querySelectorAll('#canvas [data-tile=apartment] .seg button'), function (b) { return b.textContent === '2'; })[0]; }, 3000, 'bedroom control');
            var c1 = costs(w);
            twoBr.click();
            log(w.FPBuilder.getState().tiles[0].bedrooms === 2 && costs(w) !== c1, 'inline tile controls update the budget in place', c1 + ' -> ' + costs(w));

            // Fast successive city changes: the last choice wins even if earlier responses arrive late.
            q(w, '[data-metro="35620"]').click();
            q(w, '[data-metro="47900"]').click();
            q(w, '[data-metro="36740"]').click();
            q(w, '[data-metro="47900"]').click();
            await waitFor(function () { return w.document.getElementById('staleBadge').hidden && q(w, '#metroInfo').textContent.indexOf('47900') >= 0; }, 20000, 'metro settles');
            await sleep(1500);
            var cites = w.FPBuilder.lastResult().citations.map(function (c) { return c.text; }).join(' ');
            log(w.FPBuilder.getState().cbsa === '47900' && /Washington|HUD|ACS/.test(cites) && q(w, '#metroInput').value.indexOf('Washington') === 0, 'rapid city changes never show a stale city', q(w, '#metroInput').value);

            // Compare futures stay independent.
            q(w, '[data-action=compare-add]').click();
            q(w, '[data-action=compare-add]').click();
            await waitFor(function () { return w.document.querySelectorAll('.compare-col').length === 2 && !/Loading/.test(w.document.querySelector('.compare-col').textContent); }, 20000, 'compare columns');
            var col2Select = w.document.querySelectorAll('.compare-col select')[1];
            col2Select.value = '36740';
            col2Select.dispatchEvent(new w.Event('change', { bubbles: true }));
            await waitFor(function () { return /Orlando/.test(w.document.querySelectorAll('.compare-col')[1].textContent) && !/Loading/.test(w.document.querySelectorAll('.compare-col')[1].textContent); }, 20000, 'column 2 recomputed');
            var c1text = w.document.querySelectorAll('.compare-col')[0].querySelector('dd').textContent;
            log(/Washington/.test(c1text) && w.FPBuilder.getState().cbsa === '47900', 'editing one compare column leaves the others and the builder unchanged', c1text);
            log(w.document.querySelectorAll('.compare-col dd.is-diff').length > 0, 'compare highlights only differing values');

            log(w.__noReloadMarker === 42, 'no full page reload happened during all edits');
        } catch (e) {
            log(false, 'desktop flow', e.message);
        }

        // Mobile layout: no horizontal overflow at phone width.
        try {
            var m = frame('phone');
            await waitFor(function () { return m.FPBuilder && m.FPBuilder.lastResult(); }, 30000, 'mobile builder');
            q(m, '#palette [data-tile=car] button').click();
            await sleep(300);
            var sw = m.document.documentElement.scrollWidth, cw = m.document.documentElement.clientWidth;
            log(sw <= cw + 1, 'no horizontal overflow at 375px', sw + ' <= ' + cw);
            log(m.getComputedStyle(q(m, '#mobileBar')).display !== 'none', 'mobile budget bar is visible on phones');
        } catch (e) {
            log(false, 'mobile flow', e.message);
        }
        out.textContent += 'UI TESTS DONE pass=' + pass + ' fail=' + fail + '\n';
        document.title = 'UI TESTS DONE pass=' + pass + ' fail=' + fail;
    }
    window.addEventListener('load', function () { setTimeout(run, 200); });
}());
