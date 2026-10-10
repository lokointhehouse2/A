<cfoutput>
<section class="hero">
    <div class="container-xl">
        <div class="row align-items-center g-4">
            <div class="col-lg-7">
                <h1 class="hero-title">Dream big. See what it takes.</h1>
                <p class="hero-sub">Pick your future lifestyle, a career, or a college&mdash;and discover how the numbers connect.</p>
                <div class="d-flex flex-wrap gap-2 mt-4">
                    <a class="btn btn-primary btn-lg" href="/builder">Build My Future</a>
                    <a class="btn btn-outline-primary btn-lg" href="/careers">Explore Careers</a>
                </div>
                <p class="small mt-3 mb-0 text-body-secondary">No sign-up. Real public data with the source and year on every number. <a href="/about">Estimates, not guarantees.</a></p>
            </div>
            <div class="col-lg-5">
                <div class="hero-card" aria-hidden="true">
                    <div class="mini-tile">&##127968; Apartment</div>
                    <div class="mini-tile">&##128663; Car</div>
                    <div class="mini-tile">&##9992;&##65039; Travel</div>
                    <div class="mini-bar"><span class="mini-bar-fill"></span></div>
                    <div class="small">Take-home vs. monthly costs</div>
                </div>
            </div>
        </div>
    </div>
</section>

<section class="container-xl py-5" aria-labelledby="startHeading">
    <h2 id="startHeading" class="section-title">Where do you want to start?</h2>
    <div class="row g-4">
        <div class="col-md-4">
            <a class="entry-card" href="/builder?start=life">
                <span class="entry-icon" aria-hidden="true">&##127748;</span>
                <span class="entry-title">My Dream Life</span>
                <span class="entry-text">Choose a city, a home, a car, kids, travel. See the income that lifestyle needs and careers that could support it.</span>
            </a>
        </div>
        <div class="col-md-4">
            <a class="entry-card" href="/builder?start=job">
                <span class="entry-icon" aria-hidden="true">&##128188;</span>
                <span class="entry-title">My Dream Job</span>
                <span class="entry-text">Pick a career and a city. See local pay, estimated take-home and what kind of life the budget covers.</span>
            </a>
        </div>
        <div class="col-md-4">
            <a class="entry-card" href="/builder?start=school">
                <span class="entry-icon" aria-hidden="true">&##127891;</span>
                <span class="entry-title">My Education Path</span>
                <span class="entry-text">Choose a college and major, or a GED, apprenticeship or certificate. See costs, possible jobs and loan payments.</span>
            </a>
        </div>
    </div>
</section>

<cfset cmp = vm.comparison>
<cfif arrayLen( cmp.occupations ?: [] ) && arrayLen( cmp.metros ?: [] )>
<section class="container-xl pb-5" aria-labelledby="cmpHeading">
    <h2 id="cmpHeading" class="section-title">Same job, three cities</h2>
    <p class="text-body-secondary">Median yearly pay for the same occupation (BLS OEWS, May #h.e( cmp.year )#) next to the typical 1-bedroom rent in each metro (Census ACS #h.e( cmp.rents[ cmp.metros[ 1 ].cbsa ].period ?: '' )# median gross rent). Pay is before taxes.</p>
    <div class="table-responsive">
        <table class="table table-compare align-middle">
            <caption class="visually-hidden">Median annual wage by metro area</caption>
            <thead>
                <tr>
                    <th scope="col">Occupation</th>
                    <cfloop array="#cmp.metros#" item="m"><th scope="col" class="text-end">#h.e( m.shortName )#</th></cfloop>
                </tr>
            </thead>
            <tbody>
                <cfloop array="#cmp.occupations#" item="o">
                <tr>
                    <th scope="row"><a href="/careers/#h.attr( o.soc )#">#h.e( o.title )#</a></th>
                    <cfloop from="1" to="#arrayLen( o.wages )#" index="i">
                        <cfset w = o.wages[ i ]>
                        <td class="text-end">
                            <cfif w.status == "available">
                                <span class="fw-semibold">#h.money( w.annual.median )#</span>
                            <cfelseif w.status == "partial" && arrayLen( w.flags.topcoded )>
                                <span class="fw-semibold">&ge; $239,200</span>
                            <cfelse>
                                <span class="text-body-secondary small">Not published</span>
                            </cfif>
                        </td>
                    </cfloop>
                </tr>
                </cfloop>
                <tr class="table-light">
                    <th scope="row">Median 1-bedroom rent (per month)</th>
                    <cfloop array="#cmp.metros#" item="m">
                        <td class="text-end">#h.money( cmp.rents[ m.cbsa ].value ?: javacast( "null", "" ) )#</td>
                    </cfloop>
                </tr>
            </tbody>
        </table>
    </div>
    <p class="small text-body-secondary">Metro areas: <cfloop array="#cmp.metros#" item="m">#h.e( m.name )# (CBSA #h.e( m.cbsa )#)<cfif m.cbsa != cmp.metros[ arrayLen( cmp.metros ) ].cbsa>; </cfif></cfloop>. An occupational wage describes current workers; it isn't a job offer or a starting salary. <a href="/sources">Sources and caveats</a>.</p>
</section>
<cfelse>
<section class="container-xl pb-5">
    <div class="alert alert-info">Wage and rent data are still being imported. Check <a href="/sources">data sources</a> for status.</div>
</section>
</cfif>

<section class="container-xl pb-5" aria-labelledby="fairHeading">
    <div class="fair-box">
        <h2 id="fairHeading" class="h4">Every path counts</h2>
        <p class="mb-0">A GED, an apprenticeship, a certificate, an associate or bachelor's degree, and graduate school are all real routes. FuturePath shows the tradeoffs&mdash;time, cost, pay and lifestyle&mdash;so you can compare them fairly. Starting as crew at a fast-food restaurant, becoming a shift supervisor, a restaurant manager or one day an owner are different jobs with different numbers, and they're all worth exploring.</p>
    </div>
</section>
</cfoutput>
