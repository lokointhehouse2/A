<cfoutput>
<h1 class="h3 fw-bold">Data imports</h1>
<p class="text-body-secondary">Source catalogue, current vintages and import history. Imports are idempotent upserts; re-importing a file reproduces the same rows. Downloads use fixed, allowlisted official URLs only.</p>
<cfif vm.busy><div class="alert alert-info">An import is running. Refresh this page to see progress.</div></cfif>
<cfif !vm.blsContact><div class="alert alert-warning">BLS_CONTACT_EMAIL is not set, so BLS downloads are disabled (BLS requires a contact email for automated access). You can still upload BLS files.</div></cfif>
<cfif !vm.scorecardKey><div class="alert alert-light border">College Scorecard downloads use the rate-limited <code>DEMO_KEY</code>. Add COLLEGE_SCORECARD_API_KEY (free at api.data.gov) for wider imports.</div></cfif>

<div class="table-responsive">
<table class="table bg-white">
    <thead><tr><th scope="col">Dataset</th><th scope="col">Current vintage</th><th scope="col">Last run</th><th scope="col">Waiting file</th><th scope="col">Actions</th></tr></thead>
    <tbody>
    <cfloop array="#vm.datasets#" item="d">
        <tr>
            <td><strong>#h.e( d.label )#</strong><div class="small text-body-secondary">#h.e( d.description )#</div></td>
            <td class="small"><cfif d.available>#h.e( d.lastSuccess.vintage_label )#<br>#h.num( d.lastSuccess.rows_inserted )# rows<cfelse><span class="text-danger">Not imported</span></cfif></td>
            <td class="small"><cfif !isNull( d.lastRun )><a href="/admin/imports/#d.lastRun.id#">#h.e( d.lastRun.result_status )#</a><br>#dateTimeFormat( d.lastRun.started_at, "yyyy-mm-dd HH:nn" )#</cfif></td>
            <td class="small">#h.e( d.rawFile )#</td>
            <td>
                <div class="d-flex flex-column gap-1">
                    <form method="post" action="/admin/imports" class="m-0">#h.csrfField()#<input type="hidden" name="dataset" value="#h.attr( d.key )#"><button class="btn btn-sm btn-primary w-100" type="submit" #len( d.rawFile ) ? '' : 'disabled'#>Import</button></form>
                    <form method="post" action="/admin/imports/fetch" class="m-0">#h.csrfField()#<input type="hidden" name="dataset" value="#h.attr( d.key )#">
                        <cfif d.key == "scorecard"><label class="visually-hidden" for="places-#d.key#">Places</label><input id="places-#d.key#" name="places" class="form-control form-control-sm mb-1" value="Orlando|FL;New York|NY;Washington|DC" aria-describedby="places-help"><span id="places-help" class="visually-hidden">City|ST pairs separated by semicolons</span></cfif>
                        <button class="btn btn-sm btn-outline-primary w-100" type="submit">Download latest</button></form>
                    <form method="post" action="/admin/imports/upload" enctype="multipart/form-data" class="m-0">#h.csrfField()#<input type="hidden" name="dataset" value="#h.attr( d.key )#">
                        <label class="visually-hidden" for="file-#d.key#">Upload .#d.upload# for #h.e( d.label )#</label>
                        <input id="file-#d.key#" type="file" name="file" accept=".#d.upload#" class="form-control form-control-sm" required>
                        <button class="btn btn-sm btn-outline-secondary w-100 mt-1" type="submit">Upload &amp; preview</button></form>
                </div>
            </td>
        </tr>
    </cfloop>
    </tbody>
</table>
</div>

<h2 class="h5 fw-bold mt-4">History</h2>
<div class="table-responsive">
<table class="table table-sm bg-white">
    <thead><tr><th scope="col">##</th><th scope="col">Dataset</th><th scope="col">Status</th><th scope="col">Vintage</th><th scope="col">File</th><th scope="col" class="text-end">Seen</th><th scope="col" class="text-end">Written</th><th scope="col" class="text-end">Skipped</th><th scope="col">Started</th><th scope="col">By</th><th scope="col">Checksum</th></tr></thead>
    <tbody>
    <cfloop array="#vm.history#" item="r">
        <tr>
            <td><a href="/admin/imports/#r.id#">#r.id#</a></td><td>#h.e( r.dataset_key )#</td>
            <td><span class="badge #r.result_status == 'success' ? 'text-bg-success' : ( r.result_status == 'failed' ? 'text-bg-danger' : 'text-bg-warning' )#">#h.e( r.result_status )#</span><cfif r.result_status == 'running'><div class="small">#h.e( r.progress_note )#</div></cfif></td>
            <td class="small">#h.e( r.vintage_label ?: '' )#</td><td class="small">#h.e( r.file_name ?: '' )#</td>
            <td class="text-end">#h.num( r.rows_seen )#</td><td class="text-end">#h.num( r.rows_inserted )#</td><td class="text-end">#h.num( r.rows_skipped )#</td>
            <td class="small">#dateTimeFormat( r.started_at, "yyyy-mm-dd HH:nn" )#</td><td class="small">#h.e( r.triggered_by ?: '' )#</td>
            <td class="small"><code>#h.e( left( r.checksum ?: '', 12 ) )#</code></td>
        </tr>
    </cfloop>
    </tbody>
</table>
</div>
</cfoutput>
