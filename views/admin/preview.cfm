<cfoutput>
<h1 class="h3 fw-bold">Preview: #h.e( vm.fileName )#</h1>
<p>Dataset: <strong>#h.e( vm.dataset.label )#</strong>. Check the columns below match the expected layout before importing. Suppressed values (*, **, ##) will be stored as missing, never as zero.</p>
<cfif !vm.preview.ok>
    <div class="alert alert-danger">#h.e( vm.preview.message )#</div>
<cfelse>
    <div class="table-responsive mb-3">
        <table class="table table-sm table-bordered bg-white">
            <tbody>
            <cfloop array="#vm.preview.rows#" item="row">
                <tr><cfloop from="1" to="#min( 14, arrayLen( row ) )#" index="i"><td class="small">#h.e( row[ i ] )#</td></cfloop><cfif arrayLen( row ) GT 14><td class="small text-body-secondary">+#arrayLen( row ) - 14# more</td></cfif></tr>
            </cfloop>
            </tbody>
        </table>
    </div>
</cfif>
<form method="post" action="/admin/imports/preview" class="d-inline">#h.csrfField()#<input type="hidden" name="dataset" value="#h.attr( vm.dataset.key )#"><button class="btn btn-primary" type="submit" #vm.preview.ok ? '' : 'disabled'#>Import this file</button></form>
<a class="btn btn-outline-secondary ms-2" href="/admin/imports">Cancel</a>
</cfoutput>
