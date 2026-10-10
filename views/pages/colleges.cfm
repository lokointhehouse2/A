<cfoutput>
<div class="container-xl py-4">
    <h1 class="h2 fw-bold">Explore colleges</h1>
    <p class="text-body-secondary">College costs and outcomes from the U.S. Department of Education College Scorecard. This MVP imports schools in the Orlando, New York and Washington areas; an admin can import more.</p>
    <form class="row g-2 align-items-end mb-4" method="get" action="/colleges" role="search">
        <div class="col-md-6"><label for="q" class="form-label">College name</label><input id="q" name="q" class="form-control" value="#h.attr( vm.q )#" placeholder="UCF, Howard, Hunter..."></div>
        <div class="col-md-3"><label for="state" class="form-label">State</label>
            <select id="state" name="state" class="form-select"><option value="">Any</option><cfloop list="FL,NY,DC" item="s"><option #vm.state == s ? 'selected' : ''#>#s#</option></cfloop></select></div>
        <div class="col-md-3"><button class="btn btn-primary w-100" type="submit">Search</button></div>
    </form>
    <div class="table-responsive">
    <table class="table bg-white align-middle">
        <thead><tr><th scope="col">College</th><th scope="col">Type</th><th scope="col" class="text-end">Average net price / yr</th><th scope="col" class="text-end">In-state tuition</th><th scope="col" class="text-end">Programs</th></tr></thead>
        <tbody>
        <cfloop array="#vm.results#" item="i">
            <tr>
                <th scope="row"><a href="/colleges/#h.attr( i.unitid )#">#h.e( i.name )#</a><span class="d-block small text-body-secondary">#h.e( i.city )#, #h.e( i.state )#</span></th>
                <td class="small">#h.e( i.control ?: '' )#<span class="d-block text-body-secondary">Mostly #h.e( i.predominantDegree ?: '' )#</span></td>
                <td class="text-end">#h.money( i.costs.averageNetPrice, 'Not reported' )#</td>
                <td class="text-end">#h.money( i.costs.inStateTuition, 'Not reported' )#</td>
                <td class="text-end">#h.num( i.programCount )#</td>
            </tr>
        </cfloop>
        </tbody>
    </table>
    </div>
    <p class="source-note">Average net price is what students who receive federal aid pay on average after grants and scholarships; it is different from tuition and from total cost of attendance.</p>
</div>
</cfoutput>
