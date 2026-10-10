<cfset r = vm.run>
<cfoutput>
<p><a href="/admin/imports">&larr; All imports</a></p>
<h1 class="h3 fw-bold">Import run ###r.id#: #h.e( r.dataset_key )#</h1>
<dl class="kv narrow">
    <dt>Status</dt><dd>#h.e( r.result_status )#</dd>
    <dt>Vintage</dt><dd>#h.e( r.vintage_label ?: '' )#</dd>
    <dt>File</dt><dd>#h.e( r.file_name ?: '' )#</dd>
    <dt>Checksum (SHA-256)</dt><dd><code class="small">#h.e( r.checksum ?: '' )#</code></dd>
    <dt>Started</dt><dd>#dateTimeFormat( r.started_at, "yyyy-mm-dd HH:nn:ss" )# UTC</dd>
    <dt>Ended</dt><dd><cfif !isNull( r.ended_at )>#dateTimeFormat( r.ended_at, "yyyy-mm-dd HH:nn:ss" )# UTC</cfif></dd>
    <dt>Rows seen / written / skipped</dt><dd>#h.num( r.rows_seen )# / #h.num( r.rows_inserted )# / #h.num( r.rows_skipped )#</dd>
    <dt>Progress</dt><dd>#h.e( r.progress_note ?: '' )#</dd>
    <dt>Triggered by</dt><dd>#h.e( r.triggered_by ?: '' )#</dd>
</dl>
<cfif len( r.warnings ?: '' )><h2 class="h6">Warnings</h2><pre class="small bg-white p-2 border rounded">#h.e( r.warnings )#</pre></cfif>
<cfif len( r.error_summary ?: '' )><h2 class="h6">Error</h2><pre class="small bg-white p-2 border rounded text-danger">#h.e( r.error_summary )#</pre></cfif>
</cfoutput>
