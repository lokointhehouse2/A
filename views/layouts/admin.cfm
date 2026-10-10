<cfoutput><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title>#h.e( vm.title ?: "Admin" )# · FuturePath admin</title>
    <link rel="stylesheet" href="#h.asset( 'vendor/bootstrap/bootstrap.min.css' )#">
    <link rel="stylesheet" href="#h.asset( 'css/app.css' )#">
</head>
<body class="admin">
<header class="site-header">
    <nav class="navbar" aria-label="Admin">
        <div class="container-xl">
            <a class="navbar-brand brand" href="/admin/imports"><span class="brand-mark" aria-hidden="true">&##9733;</span> FuturePath admin</a>
            <div class="d-flex align-items-center gap-3">
                <a href="/" class="small">View site</a>
                <cfif application.beans.adminAuth.isAuthenticated()>
                    <span class="small text-body-secondary d-none d-sm-inline">#h.e( application.beans.adminAuth.currentEmail() )#</span>
                    <form method="post" action="/admin/logout" class="m-0">#h.csrfField()#<button class="btn btn-outline-secondary btn-sm" type="submit">Sign out</button></form>
                </cfif>
            </div>
        </div>
    </nav>
</header>
<cfset flashMsg = h.takeFlash()>
<cfif !isNull( flashMsg )>
    <div class="container-xl mt-3"><div class="alert alert-#h.attr( flashMsg.type )#" role="status">#h.e( flashMsg.message )#</div></div>
</cfif>
<main id="main" class="container-xl py-4">
#body#
</main>
<script src="#h.asset( 'vendor/bootstrap/bootstrap.bundle.min.js' )#"></script>
</body>
</html>
</cfoutput>
