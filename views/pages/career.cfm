<cfset o = vm.occupation>
<cfset w = vm.wages>
<cfoutput>
<div class="container-xl py-4">
    <nav aria-label="Breadcrumb" class="small mb-2"><a href="/careers">Careers</a> / #h.e( o.soc )#</nav>
    <h1 class="h2 fw-bold">#h.e( o.title )#</h1>
    <p class="text-body-secondary mb-3">SOC #h.e( o.soc )# &middot; Typical entry-level education: <strong>#h.e( o.entryEducation ?: 'not listed' )#</strong><cfif len( o.workExperience ?: '' ) && o.workExperience != 'None'> &middot; Experience: #h.e( o.workExperience )#</cfif><cfif len( o.onTheJobTraining ?: '' ) && o.onTheJobTraining != 'None'> &middot; Training: #h.e( o.onTheJobTraining )#</cfif></p>

    <form method="get" class="d-flex flex-wrap gap-2 align-items-end mb-3">
        <div><label for="cbsa" class="form-label small mb-0">Metro area</label>
        <select id="cbsa" name="cbsa" class="form-select form-select-sm">
            <cfloop array="#vm.featured#" item="m"><option value="#h.attr( m.cbsa )#" #!isNull( vm.metro ) && vm.metro.cbsa == m.cbsa ? 'selected' : ''#>#h.e( m.name )#</option></cfloop>
        </select></div>
        <button class="btn btn-sm btn-outline-primary" type="submit">Show local pay</button>
        <a class="btn btn-sm btn-primary" href="/builder?start=job">Build a future with this career</a>
    </form>

    <div class="row g-4">
        <div class="col-lg-7">
            <section class="panel">
                <h2 class="h5 fw-bold">Pay in #h.e( isNull( vm.metro ) ? 'this area' : vm.metro.name )#</h2>
                <cfset lw = w.local>
                <cfif isNull( lw ) || lw.status == "not_published">
                    <p class="mb-2">#h.e( isNull( lw ) ? 'Choose a metro area.' : lw.message )#</p>
                <cfelse>
                    <cfif len( lw.message )><p class="small text-warning-emphasis">#h.e( lw.message )#</p></cfif>
                    <div class="wage-grid mb-2">
                        <cfloop list="p10,p25,median,p75,p90,mean" item="k">
                            <div class="wage-cell"><span class="k">#k == 'median' ? 'Median' : ( k == 'mean' ? 'Average' : mid( k, 2, 2 ) & 'th percentile' )#</span>
                            <span class="v"><cfif isNull( lw.annual[ k ] ) && arrayFindNoCase( lw.flags.topcoded, 'A_' & ( k == 'median' ? 'MEDIAN' : ( k == 'mean' ? 'MEAN' : 'PCT' & mid( k, 2, 2 ) ) ) )>&ge; $239,200<cfelse>#h.money( lw.annual[ k ] )#</cfif></span></div>
                        </cfloop>
                    </div>
                    <p class="small mb-1">About #h.num( lw.employment, 'an unpublished number of' )# people work in this occupation here. <cfif lw.flags.annualOnly>#h.e( w.definitions.annualOnly )#</cfif></p>
                </cfif>
                <p class="small mb-1">U.S. median: <strong>#h.money( w.national.annual.median ?: javacast( "null", "" ) )#</strong></p>
                <p class="source-note mb-0">#h.e( w.definitions.percentileCaveat )# #h.e( w.source.note )# Source: <a href="#h.attr( w.source.url )#" target="_blank" rel="noopener">#h.e( w.source.name )#</a>.</p>
            </section>

            <section class="panel">
                <h2 class="h5 fw-bold">Same job in other cities</h2>
                <ul class="list-unstyled mb-0">
                    <cfloop from="1" to="#arrayLen( vm.featured )#" index="i">
                        <cfset c = vm.comparison[ i ]>
                        <li class="d-flex justify-content-between border-bottom py-1"><span>#h.e( vm.featured[ i ].name )#</span><strong><cfif c.status == 'available'>#h.money( c.annual.median )#<cfelse><span class="small text-body-secondary">#h.e( h.statusLabel( c.status ) )#</span></cfif></strong></li>
                    </cfloop>
                </ul>
            </section>
        </div>
        <div class="col-lg-5">
            <section class="panel">
                <h2 class="h5 fw-bold">Ways to get there</h2>
                <cfif !arrayLen( vm.pathways )>
                    <p class="small">No pathway information is imported for this occupation.</p>
                <cfelse>
                    <ul class="list-unstyled">
                    <cfloop array="#vm.pathways#" item="p">
                        <li class="mb-2"><span class="badge #p.status == 'common' ? 'text-bg-primary' : 'text-bg-light'#">#p.status == 'common' ? 'Common' : ( p.status == 'required' ? 'Required' : 'Alternative' )#</span> <strong>#h.e( p.name )#</strong> <span class="small text-body-secondary">(~#h.e( p.typicalYears )# yrs)</span>
                        <cfif len( p.licensingNotes ?: '' )><div class="small">#h.e( p.licensingNotes )#</div></cfif>
                        <div class="small text-body-secondary">#h.e( p.sourceNotes ?: '' )#</div></li>
                    </cfloop>
                    </ul>
                </cfif>
                <p class="source-note mb-0">#h.e( o.caveat )#</p>
            </section>
            <cfif !isNull( o.outlook )>
            <section class="panel">
                <h2 class="h5 fw-bold">Job outlook</h2>
                <cfset outlookText = ( o.outlook.percentChange > 0 ? "+" : "" ) & o.outlook.percentChange & "%">
                <p class="mb-1">Projected change in U.S. jobs, #h.e( o.outlook.period )#: <strong>#h.e( outlookText )#</strong></p>
                <p class="small mb-1">About #h.num( o.outlook.annualOpeningsThousands * 1000 )# openings a year nationally (including people who retire or change jobs).</p>
                <p class="source-note mb-0">BLS Employment Projections. Projections are estimates, not promises.</p>
            </section>
            </cfif>
            <section class="panel">
                <h2 class="h5 fw-bold">Programs that prepare you</h2>
                <cfif !arrayLen( vm.programs )><p class="small mb-0">The CIP&ndash;SOC crosswalk lists no programs for this occupation (many jobs are learned at work).</p>
                <cfelse>
                    <ul class="small">
                        <cfloop from="1" to="#min( 12, arrayLen( vm.programs ) )#" index="i"><li>#h.e( vm.programs[ i ].title )# <span class="text-body-secondary">(CIP #h.e( vm.programs[ i ].cip )#)</span></li></cfloop>
                    </ul>
                    <p class="source-note mb-0">NCES CIP 2020&ndash;SOC 2018 crosswalk: programs that can prepare people for this job. Not a guarantee of employment.</p>
                </cfif>
            </section>
        </div>
    </div>
</div>
</cfoutput>
