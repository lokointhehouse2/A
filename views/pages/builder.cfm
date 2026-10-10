<cfset vm.scripts = [ "js/engine.js", "js/builder.js" ]>
<cfoutput>
<script type="application/json" id="fp-boot">#h.jsonData( {
    start: vm.start,
    sharedId: vm.sharedId,
    featured: vm.featured.map( function( m ) { return { cbsa: m.cbsa, name: m.name, shortName: m.shortName, states: m.states.map( function( s ) { return s.code; } ), hasNycOption: m.hasNycOption }; } ),
    assumptions: vm.assumptions
} )#</script>

<div class="builder-toolbar no-print">
    <div class="container-xxl d-flex flex-wrap align-items-center gap-2 py-2">
        <h1 class="h5 mb-0 me-auto">Future Builder</h1>
        <button type="button" class="btn btn-sm btn-outline-secondary" data-action="undo" disabled aria-label="Undo last change">&##8630; Undo</button>
        <button type="button" class="btn btn-sm btn-outline-secondary" data-action="redo" disabled aria-label="Redo">&##8631; Redo</button>
        <button type="button" class="btn btn-sm btn-outline-secondary" data-action="reset">Reset</button>
        <button type="button" class="btn btn-sm btn-outline-primary" data-action="copy-link">Copy link</button>
        <button type="button" class="btn btn-sm btn-outline-primary" data-action="print">Print summary</button>
        <button type="button" class="btn btn-sm btn-primary" data-action="compare-add">+ Compare another future</button>
    </div>
</div>

<div class="container-xxl builder py-3">
    <div id="fp-status" class="visually-hidden" role="status" aria-live="polite"></div>
    <noscript><div class="alert alert-warning">The Future Builder needs JavaScript for live calculations. You can still <a href="/careers">explore careers</a> and <a href="/colleges">colleges</a>.</div></noscript>
    <div class="row g-3">

        <!-- ============ LEFT: where + path ============ -->
        <div class="col-12 col-lg-4 col-xl-3 order-1">
            <section class="panel" aria-labelledby="whereHeading">
                <h2 id="whereHeading" class="panel-title"><span class="step">1</span> Where do you want to live?</h2>
                <div class="fp-typeahead" data-typeahead="metro">
                    <label for="metroInput" class="form-label small">City or metro area</label>
                    <input id="metroInput" class="form-control" type="text" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="metroList" placeholder="Try Orlando, New York, Denver...">
                    <ul id="metroList" class="fp-listbox" role="listbox" hidden></ul>
                </div>
                <div class="chip-row mt-2" aria-label="Quick picks">
                    <cfloop array="#vm.featured#" item="m"><button type="button" class="chip" data-metro="#h.attr( m.cbsa )#">#h.e( m.shortName )#</button></cfloop>
                </div>
                <div class="mt-2 small" id="metroInfo"></div>
            </section>

            <section class="panel" aria-labelledby="pathHeading">
                <h2 id="pathHeading" class="panel-title"><span class="step">3</span> How do you get there?</h2>
                <div class="path-slot" id="pathSlot" data-dropzone="path" aria-describedby="pathSlotHelp">
                    <p id="pathSlotHelp" class="small mb-0 text-body-secondary">Drop a career, college program or path card here, or choose one below.</p>
                    <div id="pathSummary"></div>
                </div>
                <ul class="nav nav-pills nav-fill small mt-3" role="tablist">
                    <li class="nav-item" role="presentation"><button class="nav-link active" id="tab-career" data-bs-toggle="pill" data-bs-target="##pane-career" type="button" role="tab" aria-controls="pane-career" aria-selected="true">Career</button></li>
                    <li class="nav-item" role="presentation"><button class="nav-link" id="tab-school" data-bs-toggle="pill" data-bs-target="##pane-school" type="button" role="tab" aria-controls="pane-school" aria-selected="false">School / training</button></li>
                </ul>
                <div class="tab-content pt-3">
                    <div class="tab-pane fade show active" id="pane-career" role="tabpanel" aria-labelledby="tab-career" tabindex="0">
                        <div class="fp-typeahead" data-typeahead="career">
                            <label for="careerInput" class="form-label small">Search careers</label>
                            <input id="careerInput" class="form-control" type="text" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="careerList" placeholder="Carpenter, nurse, software developer...">
                            <ul id="careerList" class="fp-listbox" role="listbox" hidden></ul>
                        </div>
                        <fieldset class="mt-3">
                            <legend class="form-label small mb-1">Which pay level?</legend>
                            <div class="seg" role="radiogroup" aria-label="Wage percentile" id="percentileSeg">
                                <cfloop list="p10,p25,median,p75,p90" item="p">
                                    <button type="button" role="radio" aria-checked="#p == 'median' ? 'true' : 'false'#" data-percentile="#p#">#p == 'median' ? 'Median' : mid( p, 2, 2 ) & 'th'#</button>
                                </cfloop>
                            </div>
                            <p class="small text-body-secondary mt-1 mb-0">Percentiles show how pay is spread across current workers. They aren't years of experience.</p>
                        </fieldset>
                        <div class="form-check form-switch mt-2">
                            <input class="form-check-input" type="checkbox" role="switch" id="partTime">
                            <label class="form-check-label small" for="partTime">Part-time (half of full-time pay)</label>
                        </div>
                    </div>
                    <div class="tab-pane fade" id="pane-school" role="tabpanel" aria-labelledby="tab-school" tabindex="0">
                        <label for="pathwaySelect" class="form-label small">Path after high school</label>
                        <select id="pathwaySelect" class="form-select">
                            <option value="">Choose a path...</option>
                        </select>
                        <div id="pathwayInfo" class="small mt-2"></div>
                        <div id="schoolPicker" class="mt-3" hidden>
                            <div class="fp-typeahead" data-typeahead="college">
                                <label for="collegeInput" class="form-label small">College</label>
                                <input id="collegeInput" class="form-control" type="text" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="collegeList" placeholder="UCF, Valencia, NYU, Howard...">
                                <ul id="collegeList" class="fp-listbox" role="listbox" hidden></ul>
                            </div>
                            <div id="collegeInfo" class="small mt-2"></div>
                            <label for="programSelect" class="form-label small mt-2">Program / major</label>
                            <select id="programSelect" class="form-select" disabled><option value="">Pick a college first</option></select>
                            <div class="fp-typeahead mt-2" data-typeahead="major">
                                <label for="majorInput" class="form-label small">...or search a major without a college</label>
                                <input id="majorInput" class="form-control" type="text" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="majorList" placeholder="English, computer science, nursing...">
                                <ul id="majorList" class="fp-listbox" role="listbox" hidden></ul>
                            </div>
                        </div>
                        <div id="possibleCareers" class="mt-3"></div>
                    </div>
                </div>
            </section>
        </div>

        <!-- ============ MIDDLE: lifestyle canvas ============ -->
        <div class="col-12 col-lg-8 col-xl-5 order-2">
            <section class="panel" aria-labelledby="lifeHeading">
                <h2 id="lifeHeading" class="panel-title"><span class="step">2</span> What does your life look like?</h2>
                <p class="small text-body-secondary">Tap <strong>Add</strong> (or drag a card onto <strong>My Future</strong>) and pick what fits your dream life. Tap a card in My Future to change it.</p>
                <ul class="tile-palette" id="palette" aria-label="Lifestyle choices" data-dropzone="palette"></ul>
                <h3 class="h6 mt-3 mb-2" id="canvasHeading">My Future</h3>
                <ol class="future-canvas" id="canvas" aria-labelledby="canvasHeading" data-dropzone="canvas"></ol>
                <p class="small text-body-secondary mb-0" id="canvasEmpty">Nothing here yet. Add a place to live to start.</p>

                <details class="assumptions mt-3" id="assumptionsDrawer">
                    <summary>Household, taxes and advanced assumptions</summary>
                    <div class="row g-2 mt-1">
                        <div class="col-6">
                            <label class="form-label small" for="adultsSelect">Adults in household</label>
                            <select id="adultsSelect" class="form-select form-select-sm"><option value="1">1</option><option value="2">2</option></select>
                        </div>
                        <div class="col-6">
                            <label class="form-label small" for="filingSelect">Tax filing status</label>
                            <select id="filingSelect" class="form-select form-select-sm">
                                <option value="single">Single</option>
                                <option value="mfj">Married filing jointly</option>
                                <option value="hoh">Head of household</option>
                            </select>
                        </div>
                        <div class="col-6">
                            <label class="form-label small" for="stateSelect">State you'd live in</label>
                            <select id="stateSelect" class="form-select form-select-sm"></select>
                        </div>
                        <div class="col-6 d-flex align-items-end">
                            <div class="form-check" id="nycWrap" hidden>
                                <input class="form-check-input" type="checkbox" id="nycCheck">
                                <label class="form-check-label small" for="nycCheck">Live inside NYC (city tax)</label>
                            </div>
                        </div>
                        <div class="col-12">
                            <div class="form-check form-switch">
                                <input class="form-check-input" type="checkbox" role="switch" id="secondEarner">
                                <label class="form-check-label small" for="secondEarner">Second earner in the household</label>
                            </div>
                            <div id="secondEarnerBox" class="mt-2" hidden>
                                <div class="fp-typeahead" data-typeahead="career2">
                                    <label for="career2Input" class="form-label small">Second earner's career</label>
                                    <input id="career2Input" class="form-control form-control-sm" type="text" autocomplete="off" role="combobox" aria-autocomplete="list" aria-expanded="false" aria-controls="career2List" placeholder="Search careers">
                                    <ul id="career2List" class="fp-listbox" role="listbox" hidden></ul>
                                </div>
                                <div class="small mt-1" id="career2Info"></div>
                            </div>
                        </div>
                        <div class="col-12">
                            <fieldset>
                                <legend class="form-label small mb-1">Timeline</legend>
                                <div class="seg seg-sm" role="radiogroup" aria-label="Timeline mode" id="timelineSeg">
                                    <button type="button" role="radio" aria-checked="true" data-mode="today">Today's dollars</button>
                                    <button type="button" role="radio" aria-checked="false" data-mode="projected">Projected (raises + inflation)</button>
                                </div>
                            </fieldset>
                        </div>
                        <div class="col-12"><hr class="my-2"><p class="small text-body-secondary mb-2">#h.e( vm.assumptions.note )#</p></div>
                        <cfloop collection="#vm.assumptions.items#" item="key">
                            <cfset a = vm.assumptions.items[ key ]>
                            <div class="col-6 col-md-4 col-lg-6 col-xxl-4">
                                <label class="form-label small mb-0" for="as-#h.attr( key )#">#h.e( a.label )#</label>
                                <input class="form-control form-control-sm" type="number" id="as-#h.attr( key )#" data-assumption="#h.attr( key )#" value="#h.attr( a.value )#" min="#h.attr( a.min )#" max="#h.attr( a.max )#" step="any" aria-describedby="as-#h.attr( key )#-unit">
                                <span class="form-text small" id="as-#h.attr( key )#-unit">#h.e( a.unit )#</span>
                            </div>
                        </cfloop>
                        <div class="col-12">
                            <div class="form-check mt-2">
                                <input class="form-check-input" type="checkbox" id="rememberCheck">
                                <label class="form-check-label small" for="rememberCheck">Remember my scenario on this device (saved only in this browser; nothing is sent to us)</label>
                            </div>
                        </div>
                    </div>
                </details>
            </section>
        </div>

        <!-- ============ RIGHT: live budget ============ -->
        <div class="col-12 col-xl-4 order-3">
            <section class="panel budget-panel" aria-labelledby="budgetHeading" id="budgetPanel">
                <div class="d-flex align-items-center justify-content-between">
                    <h2 id="budgetHeading" class="panel-title mb-0"><span class="step">4</span> Your monthly budget</h2>
                    <span class="badge text-bg-light" id="staleBadge" hidden>Updating...</span>
                </div>
                <div id="budgetSummary" class="mt-3" aria-live="polite">
                    <div class="skeleton"></div><div class="skeleton"></div><div class="skeleton short"></div>
                </div>
                <div id="suggestions" class="mt-3"></div>
                <details class="mt-3" id="breakdownDetails" open>
                    <summary class="fw-semibold">Where the money goes</summary>
                    <div id="breakdown" class="mt-2"></div>
                </details>
                <details class="mt-2" id="educationDetails">
                    <summary class="fw-semibold">School investment</summary>
                    <div id="educationPanel" class="mt-2"></div>
                </details>
                <details class="mt-2" id="timelineDetails">
                    <summary class="fw-semibold">Timeline</summary>
                    <div id="timelinePanel" class="mt-2"></div>
                </details>
                <details class="mt-2" id="sourcesDetails">
                    <summary class="fw-semibold">Sources &amp; assumptions</summary>
                    <div id="sourcesPanel" class="mt-2 small"></div>
                </details>
            </section>
        </div>
    </div>

    <!-- ============ Reverse planning ============ -->
    <section class="panel mt-3" aria-labelledby="reverseHeading" id="reversePanel">
        <div class="d-flex flex-wrap align-items-center gap-2">
            <h2 id="reverseHeading" class="panel-title mb-0 me-auto">Careers that could pay for this life</h2>
            <label class="small" for="reversePercentile">Using</label>
            <select id="reversePercentile" class="form-select form-select-sm w-auto">
                <option value="p25">25th percentile pay</option>
                <option value="median" selected>median pay</option>
                <option value="p75">75th percentile pay</option>
            </select>
            <select id="reverseSort" class="form-select form-select-sm w-auto" aria-label="Sort careers">
                <option value="jobs">Most local jobs</option>
                <option value="training">Shortest training</option>
                <option value="growth">Fastest growing (BLS projection)</option>
                <option value="margin">Most room to spare</option>
            </select>
            <select id="reverseYears" class="form-select form-select-sm w-auto" aria-label="Maximum training">
                <option value="99">Any training</option>
                <option value="0">No college needed</option>
                <option value="2">Up to 2 years</option>
                <option value="4">Up to 4 years</option>
            </select>
            <button type="button" class="btn btn-primary btn-sm" data-action="reverse">Find careers</button>
        </div>
        <div id="reverseResults" class="mt-3" aria-live="polite">
            <p class="small text-body-secondary mb-0">Build your lifestyle above, then find careers whose local pay could cover it. We calculate the pay you'd need before taxes, then compare it with real local wages.</p>
        </div>
    </section>

    <!-- ============ Compare futures ============ -->
    <section class="panel mt-3" aria-labelledby="compareHeading" id="comparePanel" hidden>
        <div class="d-flex align-items-center gap-2">
            <h2 id="compareHeading" class="panel-title mb-0 me-auto">Compare futures</h2>
            <button type="button" class="btn btn-outline-primary btn-sm" data-action="compare-add">+ Add the current future</button>
        </div>
        <p class="small text-body-secondary">Each column is its own future. Change its city, career or cards; only the numbers that differ are highlighted.</p>
        <div class="compare-grid" id="compareGrid"></div>
    </section>

    <div class="print-only mt-4 small">
        <p>FuturePath summary printed <span id="printDate"></span>. Educational estimate using public data and editable assumptions; not financial, tax or career advice.</p>
    </div>
</div>

<div class="modal fade tile-modal" id="tileModal" tabindex="-1" aria-labelledby="tileModalTitle" aria-hidden="true">
    <div class="modal-dialog modal-dialog-centered modal-dialog-scrollable modal-lg">
        <div class="modal-content">
            <div class="modal-header">
                <h2 class="modal-title h5" id="tileModalTitle"></h2>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body" id="tileModalBody"></div>
            <div class="modal-footer">
                <span class="me-auto fw-semibold" id="tileModalCost" aria-live="polite"></span>
                <button type="button" class="btn btn-outline-danger btn-sm" id="tileModalRemove">Remove</button>
                <button type="button" class="btn btn-primary" data-bs-dismiss="modal">Done</button>
            </div>
        </div>
    </div>
</div>

<div class="mobile-budget-bar no-print" id="mobileBar" aria-hidden="true">
    <span>Take-home <strong id="mbTake">—</strong></span>
    <span>Costs <strong id="mbCost">—</strong></span>
    <span id="mbGap">—</span>
</div>
</cfoutput>
