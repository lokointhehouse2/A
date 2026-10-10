/**
 * Orchestrates dataset imports: dataset registry, allowlisted download connectors, run history with checksums,
 * one-import-at-a-time locking and the development bootstrap (import whatever raw files are present).
 *
 * Imports are idempotent upserts keyed on natural keys (SOC + area + year, HUD area + bedrooms + year, ...),
 * so re-running a file reproduces the same rows; a different vintage adds rows alongside the old ones.
 */
component {

    variables.dsn = "futurepathDB";

    public ImportRunner function init( required any config, required any logger ) {
        variables.config = arguments.config;
        variables.logger = arguments.logger;
        variables.sourceIds = {};
        variables.importers = {};
        variables.datasets = [
            { key: "oews_metro", label: "BLS OEWS wages by metro area", sourceKey: "bls_oews", importer: "oews", pattern: "^oesm([0-9]{2})ma\.zip$", kind: "file", upload: "zip", description: "oesmYYma.zip from bls.gov/oes/tables.htm (metropolitan areas)" },
            { key: "oews_national", label: "BLS OEWS national wages", sourceKey: "bls_oews", importer: "oews", pattern: "^oesm([0-9]{2})nat\.zip$", kind: "file", upload: "zip", description: "oesmYYnat.zip (national)" },
            { key: "bls_ep", label: "BLS Employment Projections (entry education, outlook)", sourceKey: "bls_ep", importer: "ep", pattern: "^ep_education\.xlsx$", accept: "^ep_(education|occupation)\.xlsx$", kind: "file", upload: "xlsx", description: "education.xlsx and occupation.xlsx from bls.gov/emp/tables.htm (saved as ep_education.xlsx / ep_occupation.xlsx)" },
            { key: "cip_soc", label: "NCES CIP 2020 to SOC 2018 crosswalk", sourceKey: "nces_cip_soc", importer: "cipsoc", pattern: "^CIP2020_SOC2018_Crosswalk\.xlsx$", kind: "file", upload: "xlsx", description: "CIP2020_SOC2018_Crosswalk.xlsx from nces.ed.gov" },
            { key: "hud_fmr", label: "HUD Fair Market Rents", sourceKey: "hud_fmr", importer: "hud", pattern: "^FY([0-9]{2})_FMRs\.xlsx$", kind: "file", upload: "xlsx", description: "FYYY_FMRs.xlsx from huduser.gov" },
            { key: "acs_rent", label: "Census ACS median gross rent by bedrooms (B25031)", sourceKey: "census_acs", importer: "acs", pattern: "^acsdt5y([0-9]{4})-b25031\.dat$", kind: "file", upload: "dat", description: "acsdt5yYYYY-b25031.dat (ACS 5-year table-based summary file)" },
            { key: "acs_home_value", label: "Census ACS median home value (B25077)", sourceKey: "census_acs", importer: "acs", pattern: "^acsdt5y([0-9]{4})-b25077\.dat$", kind: "file", upload: "dat", description: "acsdt5yYYYY-b25077.dat (ACS 5-year table-based summary file)" },
            { key: "scorecard", label: "College Scorecard institutions and fields of study", sourceKey: "ed_scorecard", importer: "scorecard", pattern: "^scorecard$", kind: "dir", upload: "json", description: "College Scorecard API pages saved as JSON in storage/imports/raw/scorecard/" }
        ];
        return this;
    }

    public void function setImporters( required struct importers ) {
        variables.importers = arguments.importers;
    }

    public void function setConnectors( required any connectors ) {
        variables.connectors = arguments.connectors;
    }

    public array function datasets() {
        return duplicate( variables.datasets );
    }

    public struct function dataset( required string key ) {
        for ( var d in variables.datasets ) if ( d.key == arguments.key ) return d;
        throw( type = "NotFound", message = "Unknown dataset." );
    }

    public numeric function sourceId( required string sourceKey ) {
        if ( !structKeyExists( variables.sourceIds, arguments.sourceKey ) ) {
            var q = queryExecute( "SELECT id FROM data_sources WHERE source_key = :k", { k: { value: arguments.sourceKey, cfsqltype: "varchar" } }, { datasource: variables.dsn } );
            if ( !q.recordCount ) throw( type = "ImportException", message = "Data source #arguments.sourceKey# is not registered." );
            variables.sourceIds[ arguments.sourceKey ] = q.id;
        }
        return variables.sourceIds[ arguments.sourceKey ];
    }

    // ------------------------------------------------------------------ discovery

    /** Latest raw file (or directory) for a dataset, or "" when none is present. */
    public string function findRawFile( required string datasetKey ) {
        var d = dataset( arguments.datasetKey );
        var raw = variables.config.importRawPath;
        if ( !directoryExists( raw ) ) return "";
        if ( d.kind == "dir" ) {
            var dir = raw & "scorecard/";
            return directoryExists( dir ) && arrayLen( directoryList( dir, false, "name", "*.json" ) ) ? dir : "";
        }
        var best = "";
        var bestYear = -1;
        for ( var name in directoryList( raw, false, "name" ) ) {
            var m = reFindNoCase( d.pattern, name, 1, true );
            if ( m.pos[ 1 ] == 0 ) continue;
            var y = arrayLen( m.pos ) > 1 && m.pos[ 2 ] > 0 ? val( mid( name, m.pos[ 2 ], m.len[ 2 ] ) ) : 0;
            if ( y > bestYear ) { bestYear = y; best = raw & name; }
        }
        return best;
    }

    public string function checksum( required string path ) {
        var md = createObject( "java", "java.security.MessageDigest" ).getInstance( "SHA-256" );
        var files = directoryExists( arguments.path ) ? directoryList( arguments.path, false, "path", "*.json", "name asc" ) : [ arguments.path ];
        for ( var f in files ) {
            md.update( charsetDecode( getFileFromPath( f ), "utf-8" ) );
            var input = createObject( "java", "java.io.FileInputStream" ).init( f );
            try {
                var buffer = createObject( "java", "java.nio.ByteBuffer" ).allocate( 1048576 ).array();
                var n = input.read( buffer );
                while ( n > 0 ) {
                    md.update( buffer, 0, n );
                    n = input.read( buffer );
                }
            } finally {
                input.close();
            }
        }
        return lCase( binaryEncode( md.digest(), "hex" ) );
    }

    // ------------------------------------------------------------------ running

    /** Runs one dataset import synchronously. Returns the run summary. */
    public struct function run( required string datasetKey, string path = "", string triggeredBy = "system" ) {
        var d = dataset( arguments.datasetKey );
        var file = len( arguments.path ) ? arguments.path : findRawFile( d.key );
        if ( !len( file ) ) throw( type = "ImportException", message = "No file is available for #d.label#. Upload one or use Download." );
        var result = {};
        lock name="futurepath-import" type="exclusive" timeout="2" throwOnTimeout="true" {
            var ctx = startRun( d, file, arguments.triggeredBy );
            try {
                var importer = variables.importers[ d.importer ];
                var info = importer.import( file, ctx, d.key );
                ctx.vintageYear = info.vintageYear ?: ctx.vintageYear;
                ctx.vintageLabel = info.vintageLabel ?: ctx.vintageLabel;
                finishRun( ctx, arrayLen( ctx.warnings ) ? "partial" : "success", "" );
            } catch ( any e ) {
                variables.logger.error( "Import #d.key# failed", e );
                finishRun( ctx, "failed", left( e.message & ( len( e.detail ?: "" ) ? " | " & e.detail : "" ), 2000 ) );
            }
            result = runSummary( ctx.runId );
        }
        return result;
    }

    public boolean function hasSuccess( required string datasetKey ) {
        return queryExecute( "SELECT COUNT(*) AS n FROM data_import_runs WHERE dataset_key = :k AND result_status IN ('success','partial')",
            { k: { value: arguments.datasetKey, cfsqltype: "varchar" } }, { datasource: variables.dsn } ).n > 0;
    }

    public boolean function isBusy() {
        return queryExecute( "SELECT COUNT(*) AS n FROM data_import_runs WHERE result_status = 'running' AND started_at > UTC_TIMESTAMP() - INTERVAL 2 HOUR", {}, { datasource: variables.dsn } ).n > 0;
    }

    /** Runs a dataset in a background thread so the admin page returns immediately. */
    public void function runInBackground( required string datasetKey, string path = "", string triggeredBy = "admin" ) {
        thread name="fp-import-#createUUID()#" action="run" datasetKey=arguments.datasetKey filePath=arguments.path triggeredBy=arguments.triggeredBy {
            try {
                application.beans.importRunner.run( attributes.datasetKey, attributes.filePath, attributes.triggeredBy );
            } catch ( any e ) {
                // already recorded on the run row; nothing else to do in a detached thread
            }
        }
    }

    /**
     * Development bootstrap: imports each dataset whose raw file is present and has not yet been imported
     * successfully with the same checksum. Runs once per application start in a background thread.
     */
    public void function bootstrapInBackground() {
        if ( structKeyExists( application, "importBootstrapStarted" ) ) return;
        application.importBootstrapStarted = now();
        thread name="fp-bootstrap-#createUUID()#" action="run" {
            application.beans.importRunner.bootstrap();
        }
    }

    public array function bootstrap() {
        var ran = [];
        // Stale "running" rows from an interrupted server are marked failed first.
        queryExecute( "UPDATE data_import_runs SET result_status = 'failed', ended_at = UTC_TIMESTAMP(), error_summary = 'Interrupted (server stopped during import)' WHERE result_status = 'running'", {}, { datasource: variables.dsn } );
        for ( var d in variables.datasets ) {
            try {
                var file = findRawFile( d.key );
                if ( !len( file ) && variables.config.importAutoDownload && !isNull( variables.connectors ) && !hasSuccess( d.key ) ) {
                    // Fresh install: fetch the newest official file through the allowlisted connector.
                    try {
                        var fetched = variables.connectors.fetch( d.key );
                        if ( !fetched.ok ) variables.logger.warn( "Auto-download #d.key#: " & fetched.message );
                    } catch ( any fe ) {
                        variables.logger.warn( "Auto-download #d.key# skipped: " & fe.message );
                    }
                    file = findRawFile( d.key );
                }
                if ( !len( file ) ) continue;
                var sum = checksum( file );
                var done = queryExecute( "SELECT COUNT(*) AS n FROM data_import_runs WHERE dataset_key = :k AND checksum = :c AND result_status IN ('success','partial')", {
                    k: { value: d.key, cfsqltype: "varchar" }, c: { value: sum, cfsqltype: "char" }
                }, { datasource: variables.dsn } ).n;
                if ( done ) continue;
                run( d.key, file, "bootstrap" );
                arrayAppend( ran, d.key );
            } catch ( any e ) {
                variables.logger.error( "Bootstrap import #d.key# failed", e );
            }
        }
        return ran;
    }

    public void function progress( required struct ctx, required string note ) {
        queryExecute( "UPDATE data_import_runs SET rows_seen = :seen, rows_inserted = :ins, rows_updated = :upd, rows_skipped = :skp, progress_note = :note WHERE id = :id", {
            seen: { value: arguments.ctx.seen, cfsqltype: "integer" },
            ins: { value: arguments.ctx.inserted, cfsqltype: "integer" },
            upd: { value: arguments.ctx.updated, cfsqltype: "integer" },
            skp: { value: arguments.ctx.skipped, cfsqltype: "integer" },
            note: { value: left( arguments.note, 255 ), cfsqltype: "varchar" },
            id: { value: arguments.ctx.runId, cfsqltype: "bigint" }
        }, { datasource: variables.dsn } );
    }

    // ------------------------------------------------------------------ status / history

    public array function history( numeric limit = 50 ) {
        return queryExecute( "
            SELECT r.id, r.dataset_key, r.vintage_year, r.vintage_label, r.file_name, r.started_at, r.ended_at, r.result_status,
                   r.rows_seen, r.rows_inserted, r.rows_updated, r.rows_skipped, r.progress_note, r.warnings, r.error_summary, r.checksum, r.triggered_by,
                   s.name AS source_name
            FROM data_import_runs r JOIN data_sources s ON s.id = r.source_id
            ORDER BY r.id DESC LIMIT #int( arguments.limit )#", {}, { datasource: variables.dsn, returntype: "array" } );
    }

    public struct function runSummary( required numeric runId ) {
        var rows = queryExecute( "SELECT * FROM data_import_runs WHERE id = :id", { id: { value: arguments.runId, cfsqltype: "bigint" } }, { datasource: variables.dsn, returntype: "array" } );
        if ( !arrayLen( rows ) ) throw( type = "NotFound", message = "Import run not found." );
        return rows[ 1 ];
    }

    /** Per dataset: latest successful vintage, last run, and whether a raw file is waiting. */
    public array function status() {
        var out = [];
        for ( var d in variables.datasets ) {
            var last = queryExecute( "SELECT id, result_status, started_at, ended_at, vintage_label, rows_inserted, error_summary FROM data_import_runs WHERE dataset_key = :k ORDER BY id DESC LIMIT 1",
                { k: { value: d.key, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );
            var ok = queryExecute( "SELECT id, vintage_year, vintage_label, ended_at, rows_inserted, checksum FROM data_import_runs WHERE dataset_key = :k AND result_status IN ('success','partial') ORDER BY id DESC LIMIT 1",
                { k: { value: d.key, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );
            var file = "";
            try { file = findRawFile( d.key ); } catch ( any e ) {}
            arrayAppend( out, {
                key: d.key, label: d.label, sourceKey: d.sourceKey, description: d.description, upload: d.upload,
                lastRun: arrayLen( last ) ? last[ 1 ] : javacast( "null", "" ),
                lastSuccess: arrayLen( ok ) ? ok[ 1 ] : javacast( "null", "" ),
                rawFile: len( file ) ? getFileFromPath( reReplace( file, "/$", "" ) ) : "",
                available: arrayLen( ok ) > 0
            } );
        }
        return out;
    }

    // ------------------------------------------------------------------ internals

    private struct function startRun( required struct d, required string file, required string triggeredBy ) {
        var ctx = {
            runId: 0, datasetKey: arguments.d.key, sourceId: sourceId( arguments.d.sourceKey ),
            seen: 0, inserted: 0, updated: 0, skipped: 0, warnings: [],
            vintageYear: javacast( "null", "" ), vintageLabel: javacast( "null", "" )
        };
        var sum = checksum( arguments.file );
        var res = {};
        queryExecute( "INSERT INTO data_import_runs (source_id, dataset_key, file_name, started_at, result_status, checksum, triggered_by, progress_note)
                       VALUES (:src, :k, :f, UTC_TIMESTAMP(), 'running', :c, :t, 'Starting')", {
            src: { value: ctx.sourceId, cfsqltype: "integer" },
            k: { value: arguments.d.key, cfsqltype: "varchar" },
            f: { value: getFileFromPath( reReplace( arguments.file, "/$", "" ) ), cfsqltype: "varchar" },
            c: { value: sum, cfsqltype: "char" },
            t: { value: left( arguments.triggeredBy, 120 ), cfsqltype: "varchar" }
        }, { datasource: variables.dsn, result: "res" } );
        ctx.runId = res.generatedKey;
        return ctx;
    }

    private void function finishRun( required struct ctx, required string status, required string errorSummary ) {
        queryExecute( "UPDATE data_import_runs SET result_status = :s, ended_at = UTC_TIMESTAMP(), rows_seen = :seen, rows_inserted = :ins, rows_updated = :upd,
                       rows_skipped = :skp, vintage_year = :vy, vintage_label = :vl, warnings = :w, error_summary = :e, progress_note = :note WHERE id = :id", {
            s: { value: arguments.status, cfsqltype: "varchar" },
            seen: { value: arguments.ctx.seen, cfsqltype: "integer" },
            ins: { value: arguments.ctx.inserted, cfsqltype: "integer" },
            upd: { value: arguments.ctx.updated, cfsqltype: "integer" },
            skp: { value: arguments.ctx.skipped, cfsqltype: "integer" },
            vy: { value: arguments.ctx.vintageYear ?: "", cfsqltype: "smallint", null: isNull( arguments.ctx.vintageYear ) },
            vl: { value: arguments.ctx.vintageLabel ?: "", cfsqltype: "varchar", null: isNull( arguments.ctx.vintageLabel ) },
            w: { value: arrayToList( arguments.ctx.warnings, chr( 10 ) ), cfsqltype: "longvarchar", null: !arrayLen( arguments.ctx.warnings ) },
            e: { value: arguments.errorSummary, cfsqltype: "longvarchar", null: !len( arguments.errorSummary ) },
            note: { value: arguments.status == "failed" ? "Failed" : "Complete", cfsqltype: "varchar" },
            id: { value: arguments.ctx.runId, cfsqltype: "bigint" }
        }, { datasource: variables.dsn } );
    }

}
