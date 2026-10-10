<cfoutput>
<div class="container-xl py-4">
    <h1 class="h2 fw-bold">Data sources and assumptions</h1>
    <p class="text-body-secondary">Every number in FuturePath comes from one of these public sources, or is a labeled assumption you can change.</p>
    <section class="panel">
        <h2 class="h5 fw-bold">Imported datasets</h2>
        <div class="table-responsive">
        <table class="table table-sm">
            <thead><tr><th scope="col">Dataset</th><th scope="col">Vintage</th><th scope="col">Imported</th><th scope="col" class="text-end">Rows</th></tr></thead>
            <tbody>
            <cfloop array="#vm.datasets#" item="d">
                <tr>
                    <td>#h.e( d.label )#</td>
                    <td><cfif d.available>#h.e( d.lastSuccess.vintage_label )#<cfelse><span class="text-body-secondary">Not imported</span></cfif></td>
                    <td class="small"><cfif d.available>#dateTimeFormat( d.lastSuccess.ended_at, "yyyy-mm-dd HH:nn" )# UTC</cfif></td>
                    <td class="text-end">#d.available ? h.num( d.lastSuccess.rows_inserted ) : ''#</td>
                </tr>
            </cfloop>
            </tbody>
        </table>
        </div>
    </section>
    <section class="panel">
        <h2 class="h5 fw-bold">Sources</h2>
        <ul class="list-unstyled">
            <cfloop array="#vm.sources#" item="s">
                <li class="mb-3"><a href="#h.attr( s.source_url )#" target="_blank" rel="noopener" class="fw-semibold">#h.e( s.name )#</a> &mdash; #h.e( s.agency )#
                <div class="small">#h.e( s.license_notes ?: '' )#</div><div class="small text-body-secondary">Updates: #h.e( s.refresh_cadence ?: 'varies' )#</div></li>
            </cfloop>
        </ul>
    </section>
    <section class="panel">
        <h2 class="h5 fw-bold">Editable default assumptions</h2>
        <p class="small">#h.e( vm.assumptions.note )#</p>
        <div class="table-responsive">
        <table class="table table-sm">
            <thead><tr><th scope="col">Assumption</th><th scope="col" class="text-end">Default</th><th scope="col">Unit</th><th scope="col">Note</th></tr></thead>
            <tbody>
            <cfloop collection="#vm.assumptions.items#" item="k"><cfset a = vm.assumptions.items[ k ]>
                <tr><td>#h.e( a.label )#</td><td class="text-end">#h.e( a.value )#</td><td class="small">#h.e( a.unit )#</td><td class="small">#h.e( a.note ?: '' )#</td></tr>
            </cfloop>
            </tbody>
        </table>
        </div>
    </section>
    <section class="panel">
        <h2 class="h5 fw-bold">Simplifications</h2>
        <ul class="small mb-0">
            <li>Taxes: wages only, standard deduction, Child Tax Credit; state tax modeled for FL (none), NY and NYC (2026), DC (latest published 2025 rules), VA (2026), and states without wage tax. Other states show a warning and no state tax.</li>
            <li>Rents: Census ACS medians are gross rent (including utilities) for the metro; HUD Fair Market Rents are a policy benchmark and HUD sometimes splits a metro into several areas.</li>
            <li>Food: USDA Moderate-Cost plan, national average, adjusted for household size.</li>
            <li>Student loans: federal Direct Loan rates for 2026&ndash;27, 10-year standard repayment; interest during school is not included.</li>
            <li>No forecast here is a promise. Projections use your own raise and inflation assumptions.</li>
        </ul>
    </section>
</div>
</cfoutput>
