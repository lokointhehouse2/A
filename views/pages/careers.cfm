<cfoutput>
<div class="container-xl py-4">
    <h1 class="h2 fw-bold">Explore careers</h1>
    <p class="text-body-secondary">Search any of the 800+ detailed occupations in the federal Standard Occupational Classification. Pick a metro area to see local pay.</p>
    <form class="row g-2 align-items-end mb-4" method="get" action="/careers" role="search">
        <div class="col-md-6">
            <label for="q" class="form-label">Career</label>
            <input id="q" name="q" class="form-control" value="#h.attr( vm.q )#" placeholder="Carpenter, English teacher, physician, fast food...">
        </div>
        <div class="col-md-4">
            <label for="cbsa" class="form-label">Metro area</label>
            <select id="cbsa" name="cbsa" class="form-select">
                <option value="">National only</option>
                <cfloop array="#vm.featured#" item="m"><option value="#h.attr( m.cbsa )#" #vm.cbsa == m.cbsa ? 'selected' : ''#>#h.e( m.name )#</option></cfloop>
            </select>
        </div>
        <div class="col-md-2"><button class="btn btn-primary w-100" type="submit">Search</button></div>
    </form>
    <cfif len( vm.q )>
        <h2 class="h5">#arrayLen( vm.results )# result#arrayLen( vm.results ) == 1 ? '' : 's'# for &ldquo;#h.e( vm.q )#&rdquo;</h2>
        <cfif !arrayLen( vm.results )>
            <p>No occupations matched. Try a shorter word (&ldquo;nurse&rdquo;, &ldquo;cook&rdquo;, &ldquo;teacher&rdquo;) or a SOC code like 15-1252.</p>
        <cfelse>
            <div class="table-responsive">
            <table class="table bg-white align-middle">
                <thead><tr><th scope="col">Occupation</th><th scope="col">Typical entry education (BLS)</th><cfif len( vm.cbsa )><th scope="col" class="text-end">Local median</th></cfif><th scope="col" class="text-end">U.S. median</th></tr></thead>
                <tbody>
                <cfloop array="#vm.results#" item="o">
                    <tr>
                        <th scope="row"><a href="/careers/#h.attr( o.soc )##len( vm.cbsa ) ? '?cbsa=' & h.u( vm.cbsa ) : ''#">#h.e( o.title )#</a> <span class="small text-body-secondary">#h.e( o.soc )#</span></th>
                        <td>#h.e( o.entryEducation ?: 'Not listed' )#</td>
                        <cfif len( vm.cbsa )><td class="text-end">#o.localStatus == 'available' ? h.money( o.localMedian ) : '<span class="small text-body-secondary">' & h.e( h.statusLabel( o.localStatus ) ) & '</span>'#</td></cfif>
                        <td class="text-end">#h.money( o.nationalMedian )#</td>
                    </tr>
                </cfloop>
                </tbody>
            </table>
            </div>
            <p class="source-note">Wages: BLS Occupational Employment and Wage Statistics, May 2025. Entry education: BLS Employment Projections.</p>
        </cfif>
    </cfif>
</div>
</cfoutput>
