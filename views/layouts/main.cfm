<cfoutput><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#h.e( vm.title ?: "FuturePath" )# · FuturePath</title>
    <meta name="description" content="Pick your future lifestyle, a career, or a college and see how the numbers connect, using public U.S. government data.">
    <link rel="stylesheet" href="#h.asset( 'vendor/bootstrap/bootstrap.min.css' )#">
    <link rel="stylesheet" href="#h.asset( 'css/app.css' )#">
    <link rel="icon" href="#h.asset( 'img/favicon.svg' )#" type="image/svg+xml">
</head>
<body>
<a class="visually-hidden-focusable skip-link" href="##main">Skip to main content</a>
<header class="site-header">
    <nav class="navbar navbar-expand-md" aria-label="Main">
        <div class="container-xl">
            <a class="navbar-brand brand" href="/"><span class="brand-mark" aria-hidden="true">&##9733;</span> FuturePath</a>
            <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="##mainNav" aria-controls="mainNav" aria-expanded="false" aria-label="Toggle navigation">
                <span class="navbar-toggler-icon"></span>
            </button>
            <div class="collapse navbar-collapse" id="mainNav">
                <ul class="navbar-nav ms-auto align-items-md-center gap-md-1">
                    <li class="nav-item"><a class="nav-link #( request.path ?: '' ) == '/builder' ? 'active' : ''#" href="/builder">Future Builder</a></li>
                    <li class="nav-item"><a class="nav-link #reFind( '^/careers', request.path ?: '' ) ? 'active' : ''#" href="/careers">Careers</a></li>
                    <li class="nav-item"><a class="nav-link #reFind( '^/colleges', request.path ?: '' ) ? 'active' : ''#" href="/colleges">Colleges</a></li>
                    <li class="nav-item"><a class="nav-link #( request.path ?: '' ) == '/sources' ? 'active' : ''#" href="/sources">Data &amp; sources</a></li>
                    <li class="nav-item ms-md-2"><a class="btn btn-primary btn-sm px-3" href="/builder">Build My Future</a></li>
                </ul>
            </div>
        </div>
    </nav>
</header>
<cfset flashMsg = h.takeFlash()>
<cfif !isNull( flashMsg )>
    <div class="container-xl mt-3"><div class="alert alert-#h.attr( flashMsg.type )#" role="status">#h.e( flashMsg.message )#</div></div>
</cfif>
<main id="main" tabindex="-1">
#body#
</main>
<footer class="site-footer">
    <div class="container-xl">
        <div class="row g-4">
            <div class="col-md-6">
                <p class="fw-semibold mb-1">FuturePath shows possibilities, not predictions.</p>
                <p class="small mb-0">Every number is an educational estimate built from public data and editable assumptions. It is not financial, tax, lending or career-placement advice, and no school, degree or job guarantees an outcome.</p>
            </div>
            <div class="col-md-6 small">
                <ul class="list-inline mb-2">
                    <li class="list-inline-item"><a href="/about">How it works</a></li>
                    <li class="list-inline-item"><a href="/sources">Data sources</a></li>
                    <li class="list-inline-item"><a href="/privacy">Privacy</a></li>
                    <li class="list-inline-item"><a href="/admin">Admin</a></li>
                </ul>
                <p class="mb-0">Wages: BLS OEWS. Rents and home values: Census ACS and HUD. Colleges: U.S. Department of Education College Scorecard. Programs to careers: NCES CIP&ndash;SOC crosswalk.</p>
            </div>
        </div>
    </div>
</footer>
<script src="#h.asset( 'vendor/bootstrap/bootstrap.bundle.min.js' )#"></script>
<script src="#h.asset( 'js/common.js' )#"></script>
<cfif structKeyExists( vm, "scripts" )><cfloop array="#vm.scripts#" item="s"><script src="#h.asset( s )#"></script></cfloop></cfif>
</body>
</html>
</cfoutput>
