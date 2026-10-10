/**
 * GET /api/health              liveness + database check
 * GET /api/v1/sources/status   data vintages and availability per dataset
 */
component extends="controllers.BaseController" {

    public struct function health( required struct rc ) {
        var db = "error";
        try {
            queryExecute( "SELECT 1 AS ok", {}, { datasource: "futurepathDB" } );
            db = application.dbReady ? "ok" : "migrating";
        } catch ( any e ) {}
        return ok( { status: db == "ok" ? "ok" : "degraded", database: db, importsRunning: db == "ok" ? variables.b.importRunner.isBusy() : false } );
    }

    public struct function status( required struct rc ) {
        var sources = queryExecute( "SELECT source_key, name, agency, source_url, license_notes, refresh_cadence FROM data_sources ORDER BY name", {}, { datasource: "futurepathDB", returntype: "array" } );
        var datasets = variables.b.importRunner.status().map( function( d ) {
            return {
                key: d.key, label: d.label, sourceKey: d.sourceKey, available: d.available,
                vintage: isNull( d.lastSuccess ) ? javacast( "null", "" ) : d.lastSuccess.vintage_label,
                importedAt: isNull( d.lastSuccess ) ? javacast( "null", "" ) : d.lastSuccess.ended_at,
                rows: isNull( d.lastSuccess ) ? 0 : d.lastSuccess.rows_inserted,
                lastRunStatus: isNull( d.lastRun ) ? javacast( "null", "" ) : d.lastRun.result_status
            };
        } );
        return ok( { datasets: datasets, sources: sources, scorecardKey: len( variables.b.config.scorecardApiKey ) ? "configured" : "DEMO_KEY (rate-limited)" } );
    }

}
