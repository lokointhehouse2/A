<cfset inst = vm.institution>
<cfoutput>
<div class="container-xl py-4">
    <nav aria-label="Breadcrumb" class="small mb-2"><a href="/colleges">Colleges</a> / #h.e( inst.name )#</nav>
    <h1 class="h2 fw-bold">#h.e( inst.name )#</h1>
    <p class="text-body-secondary">#h.e( inst.city )#, #h.e( inst.state )# &middot; #h.e( inst.control ?: '' )# &middot; mostly awards #h.e( inst.predominantDegree ?: '' )# degrees<cfif !isNull( inst.website )> &middot; <a href="#h.attr( inst.website )#" target="_blank" rel="noopener">Website</a></cfif></p>
    <div class="row g-4">
        <div class="col-lg-5">
            <section class="panel">
                <h2 class="h5 fw-bold">Costs (per year)</h2>
                <dl class="kv">
                    <dt>Average net price</dt><dd>#h.money( inst.costs.averageNetPrice, 'Not reported' )#</dd>
                    <dt>Tuition, in-state</dt><dd>#h.money( inst.costs.inStateTuition, 'Not reported' )#</dd>
                    <dt>Tuition, out-of-state</dt><dd>#h.money( inst.costs.outOfStateTuition, 'Not reported' )#</dd>
                    <dt>Cost of attendance</dt><dd>#h.money( inst.costs.costOfAttendance, 'Not reported' )#</dd>
                </dl>
                <p class="source-note mb-0">#h.e( inst.costs.note )#</p>
            </section>
            <section class="panel">
                <h2 class="h5 fw-bold">Outcomes</h2>
                <dl class="kv">
                    <dt>Completion rate</dt><dd>#h.pct( inst.outcomes.completionRate, 0, 'Not reported' )#</dd>
                    <dt>Retention rate</dt><dd>#h.pct( inst.outcomes.retentionRate, 0, 'Not reported' )#</dd>
                    <dt>Median debt of completers</dt><dd>#h.money( inst.outcomes.medianDebt, 'Not reported' )#</dd>
                </dl>
                <cfloop collection="#inst.outcomes.definitions#" item="k"><p class="source-note mb-1">#h.e( inst.outcomes.definitions[ k ] )#</p></cfloop>
                <p class="source-note mb-0">Source: <a href="#h.attr( inst.source.url )#" target="_blank" rel="noopener">College Scorecard</a> (#h.e( inst.source.vintage ?: 'latest' )#).</p>
            </section>
            <a class="btn btn-primary" href="/builder?start=school">Use this college in the Future Builder</a>
        </div>
        <div class="col-lg-7">
            <section class="panel">
                <h2 class="h5 fw-bold">Programs and observed earnings</h2>
                <p class="source-note">Median earnings of former students who received federal aid, by field and credential, measured after they finished. Often suppressed for small programs. This is not the same as local pay for an occupation.</p>
                <div class="table-responsive">
                <table class="table table-sm">
                    <thead><tr><th scope="col">Program</th><th scope="col">Credential</th><th scope="col" class="text-end">1 yr after</th><th scope="col" class="text-end">4 yrs after</th><th scope="col" class="text-end">Median debt</th></tr></thead>
                    <tbody>
                    <cfloop array="#vm.programs#" item="p">
                        <tr>
                            <td>#h.e( p.title )# <span class="small text-body-secondary">#h.e( p.cip )#</span></td>
                            <td class="small">#h.e( p.credential )#</td>
                            <td class="text-end">#h.money( p.observedEarnings[ '1_yr' ].median ?: javacast( 'null', '' ), '—' )#</td>
                            <td class="text-end">#h.money( p.observedEarnings[ '4_yr' ].median ?: javacast( 'null', '' ), '—' )#</td>
                            <td class="text-end">#h.money( p.debtMedian, '—' )#</td>
                        </tr>
                    </cfloop>
                    </tbody>
                </table>
                </div>
                <p class="source-note mb-0">&mdash; means suppressed or not reported (never zero).</p>
            </section>
        </div>
    </div>
</div>
</cfoutput>
