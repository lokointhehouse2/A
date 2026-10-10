<cfset vm.layoutNoNav = true>
<cfoutput>
<div class="container py-5 narrow">
    <h1 class="h3 fw-bold">Admin sign in</h1>
    <p class="text-body-secondary">Data administration is limited to authorized staff.</p>
    <form method="post" action="/admin/login" class="panel">
        #h.csrfField()#
        <input type="hidden" name="next" value="#h.attr( vm.next )#">
        <div class="mb-3"><label for="email" class="form-label">Email</label><input id="email" name="email" type="email" class="form-control" autocomplete="username" required></div>
        <div class="mb-3"><label for="password" class="form-label">Password</label><input id="password" name="password" type="password" class="form-control" autocomplete="current-password" required></div>
        <button class="btn btn-primary" type="submit">Sign in</button>
    </form>
</div>
</cfoutput>
