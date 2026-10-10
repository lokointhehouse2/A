/*
 * FuturePath shared front-end helpers: JSON fetch, formatting, announcements, accessible typeahead.
 * Vanilla JS, no dependencies (Bootstrap's bundle is used only for collapse/tabs).
 */
(function (window, document) {
    'use strict';

    var FP = window.FP = window.FP || {};

    FP.money = function (n, opts) {
        opts = opts || {};
        if (n === null || n === undefined || !isFinite(n)) return opts.fallback || '—';
        var v = Math.round(n);
        var s = '$' + Math.abs(v).toLocaleString('en-US');
        if (v < 0) s = '-' + s;
        if (opts.signed && v > 0) s = '+' + s;
        return s;
    };

    FP.pct = function (n, digits) {
        if (n === null || n === undefined || !isFinite(n)) return '—';
        return (n * 100).toFixed(digits || 0) + '%';
    };

    FP.esc = function (s) {
        return String(s === null || s === undefined ? '' : s)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    };

    /** Small DOM builder: FP.el('div', {class:'x', text:'y'}, [children]) — never uses innerHTML for data. */
    FP.el = function (tag, attrs, children) {
        var node = document.createElement(tag);
        Object.keys(attrs || {}).forEach(function (k) {
            var v = attrs[k];
            if (v === null || v === undefined || v === false) return;
            if (k === 'text') node.textContent = v;
            else if (k === 'class') node.className = v;
            else if (k.indexOf('on') === 0 && typeof v === 'function') node.addEventListener(k.slice(2), v);
            else if (k === 'dataset') Object.keys(v).forEach(function (d) { node.dataset[d] = v[d]; });
            else node.setAttribute(k, v === true ? '' : v);
        });
        (children || []).forEach(function (c) {
            if (c === null || c === undefined || c === false) return;
            node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
        });
        return node;
    };

    /** JSON API call with typed error handling. Resolves to `data`; rejects with {status, code, message}. */
    FP.api = function (url, options) {
        options = options || {};
        var init = { method: options.method || 'GET', headers: { Accept: 'application/json' }, credentials: 'same-origin', signal: options.signal };
        if (options.body !== undefined) {
            init.headers['Content-Type'] = 'application/json';
            init.body = JSON.stringify(options.body);
        }
        return fetch(url, init).then(function (res) {
            return res.json().catch(function () { return null; }).then(function (json) {
                if (!res.ok || !json || !json.success) {
                    var err = new Error((json && json.message) || ('Request failed (' + res.status + ')'));
                    err.status = res.status;
                    err.code = json && json.error ? json.error.code : 'http_error';
                    err.fields = json && json.error ? json.error.fields : {};
                    throw err;
                }
                return json.data;
            });
        });
    };

    var announcer;
    FP.announce = function (msg) {
        announcer = announcer || document.getElementById('fp-status');
        if (!announcer) return;
        announcer.textContent = '';
        window.setTimeout(function () { announcer.textContent = msg; }, 30);
    };

    FP.debounce = function (fn, ms) {
        var t;
        return function () {
            var args = arguments, self = this;
            window.clearTimeout(t);
            t = window.setTimeout(function () { fn.apply(self, args); }, ms);
        };
    };

    FP.storage = {
        get: function (k) { try { return JSON.parse(window.localStorage.getItem(k)); } catch (e) { return null; } },
        set: function (k, v) { try { window.localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* storage unavailable */ } },
        remove: function (k) { try { window.localStorage.removeItem(k); } catch (e) { /* ignore */ } }
    };

    /**
     * Accessible combobox typeahead (WAI-ARIA 1.2 pattern).
     *   options.search(query, signal) -> Promise<items>; options.render(item) -> {label, detail}; options.onSelect(item)
     *   options.empty(query) -> message for no results. Obsolete responses are ignored.
     */
    FP.Typeahead = function (root, options) {
        var input = root.querySelector('input');
        var list = root.querySelector('[role=listbox]');
        var items = [], active = -1, seq = 0, controller = null;
        var minChars = options.minChars === undefined ? 1 : options.minChars;

        function close() {
            list.hidden = true;
            input.setAttribute('aria-expanded', 'false');
            input.removeAttribute('aria-activedescendant');
            active = -1;
        }
        function highlight(i) {
            var opts = list.querySelectorAll('[role=option]');
            opts.forEach(function (o, idx) { o.setAttribute('aria-selected', idx === i ? 'true' : 'false'); });
            active = i;
            if (opts[i]) {
                input.setAttribute('aria-activedescendant', opts[i].id);
                opts[i].scrollIntoView({ block: 'nearest' });
            }
        }
        function choose(i) {
            var item = items[i];
            if (!item) return;
            close();
            options.onSelect(item);
        }
        function show(results, query) {
            items = results || [];
            list.textContent = '';
            if (!items.length) {
                list.appendChild(FP.el('li', { class: 'fp-empty', role: 'presentation', text: options.empty ? options.empty(query) : 'No matches.' }));
            }
            items.forEach(function (item, i) {
                var r = options.render(item);
                var li = FP.el('li', { id: list.id + '-opt-' + i, role: 'option', 'aria-selected': 'false', class: 'fp-option' }, [
                    FP.el('span', { class: 'fp-option-label', text: r.label }),
                    r.detail ? FP.el('span', { class: 'fp-option-detail', text: r.detail }) : null
                ]);
                li.addEventListener('mousedown', function (e) { e.preventDefault(); choose(i); });
                list.appendChild(li);
            });
            list.hidden = false;
            input.setAttribute('aria-expanded', 'true');
            active = -1;
        }
        var run = FP.debounce(function () {
            var q = input.value.trim();
            if (q.length < minChars) { close(); return; }
            var mySeq = ++seq;
            if (controller) controller.abort();
            controller = window.AbortController ? new AbortController() : null;
            root.classList.add('is-loading');
            options.search(q, controller ? controller.signal : undefined).then(function (results) {
                if (mySeq !== seq) return; // a newer search started; ignore this late response
                show(results, q);
            }).catch(function (err) {
                if (err && err.name === 'AbortError') return;
                if (mySeq === seq) show([], q);
            }).finally(function () { if (mySeq === seq) root.classList.remove('is-loading'); });
        }, options.delay || 220);

        input.addEventListener('input', run);
        input.addEventListener('focus', function () { if (!input.value && options.onFocusEmpty) { var r = options.onFocusEmpty(); if (r && r.length) show(r, ''); } });
        input.addEventListener('keydown', function (e) {
            if (list.hidden && (e.key === 'ArrowDown')) { run(); return; }
            if (e.key === 'ArrowDown') { e.preventDefault(); highlight(Math.min(items.length - 1, active + 1)); }
            else if (e.key === 'ArrowUp') { e.preventDefault(); highlight(Math.max(0, active - 1)); }
            else if (e.key === 'Enter') { if (!list.hidden && active >= 0) { e.preventDefault(); choose(active); } }
            else if (e.key === 'Escape') { close(); }
        });
        input.addEventListener('blur', function () { window.setTimeout(close, 150); });
        return { input: input, close: close, set: function (v) { input.value = v; } };
    };

    // Mark the current year in print footers etc.
    document.addEventListener('DOMContentLoaded', function () {
        var pd = document.getElementById('printDate');
        if (pd) pd.textContent = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'long', day: 'numeric' });
    });
}(window, document));
