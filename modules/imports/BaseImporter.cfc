/**
 * Shared helpers for dataset importers: batched idempotent upserts, safe number parsing, progress reporting.
 * Importers implement: public struct function import( required string path, required struct ctx )
 */
component {

    variables.dsn = "futurepathDB";
    variables.batchSize = 400;

    public any function init( required any runner, required any logger ) {
        variables.runner = arguments.runner;
        variables.logger = arguments.logger;
        return this;
    }

    /**
     * Parses a published numeric cell. Returns null for blanks and for statistical suppression / special codes
     * (*, **, #, ~, N/A, negative ACS jam values). The caller records WHY a value is null.
     */
    public any function num( any raw ) {
        if ( isNull( arguments.raw ) ) return javacast( "null", "" );
        var s = trim( toString( arguments.raw ) );
        if ( !len( s ) ) return javacast( "null", "" );
        s = replace( replace( replace( s, ",", "", "all" ), "$", "", "all" ), "%", "", "all" );
        if ( !isNumeric( s ) ) return javacast( "null", "" );
        return val( s );
    }

    /** Bounds-safe cell access: rows can be shorter than the header when trailing cells are empty. */
    public string function cellAt( required array cells, any index ) {
        if ( isNull( arguments.index ) || !isNumeric( arguments.index ) || arguments.index < 1 || arguments.index > arrayLen( arguments.cells ) ) return "";
        var v = arguments.cells[ arguments.index ];
        return isNull( v ) ? "" : v;
    }

    public boolean function isCode( any raw, required string code ) {
        return !isNull( arguments.raw ) && trim( toString( arguments.raw ) ) == arguments.code;
    }

    /**
     * Multi-row INSERT ... ON DUPLICATE KEY UPDATE.
     * columns: [ "col", ... ]   types: [ "varchar", "decimal", ... ]   rows: [ [v1, v2, ...], ... ]
     * updateColumns: columns refreshed when the unique key already exists.
     */
    public numeric function upsert( required string table, required array columns, required array types, required array rows, required array updateColumns, required struct ctx ) {
        if ( !arrayLen( arguments.rows ) ) return 0;
        var placeholders = "(" & repeatString( "?,", arrayLen( arguments.columns ) - 1 ) & "?)";
        var updates = [];
        for ( var c in arguments.updateColumns ) arrayAppend( updates, "#c# = VALUES(#c#)" );
        var written = 0;
        var start = 1;
        while ( start <= arrayLen( arguments.rows ) ) {
            var stop = min( start + variables.batchSize - 1, arrayLen( arguments.rows ) );
            var params = [];
            var groups = [];
            for ( var r = start; r <= stop; r++ ) {
                arrayAppend( groups, placeholders );
                var row = arguments.rows[ r ];
                for ( var i = 1; i <= arrayLen( arguments.columns ); i++ ) {
                    var v = row[ i ];
                    arrayAppend( params, isNull( v ) ? { value: "", cfsqltype: arguments.types[ i ], null: true } : { value: v, cfsqltype: arguments.types[ i ] } );
                }
            }
            var sql = "INSERT INTO #arguments.table# (#arrayToList( arguments.columns )#) VALUES #arrayToList( groups )#"
                & ( arrayLen( updates ) ? " ON DUPLICATE KEY UPDATE #arrayToList( updates )#" : "" );
            var res = {};
            queryExecute( sql, params, { datasource: variables.dsn, result: "res" } );
            var affected = val( res.recordcount ?: 0 );
            var n = stop - start + 1;
            arguments.ctx.inserted += n;
            if ( affected > n ) arguments.ctx.updated += ( affected - n );
            written += n;
            start = stop + 1;
        }
        return written;
    }

    public void function progress( required struct ctx, required string note ) {
        variables.runner.progress( arguments.ctx, arguments.note );
    }

    public void function warn( required struct ctx, required string message ) {
        if ( arrayLen( arguments.ctx.warnings ) < 50 ) arrayAppend( arguments.ctx.warnings, arguments.message );
    }

    public numeric function sourceId( required string sourceKey ) {
        return variables.runner.sourceId( arguments.sourceKey );
    }

    /** Extracts the first zip entry whose name matches regex into the work directory; returns its path. */
    public string function extractZipEntry( required string zipPath, required string entryRegex, required string workDir ) {
        var zip = createObject( "java", "java.util.zip.ZipFile" ).init( arguments.zipPath );
        try {
            var entries = zip.entries();
            while ( entries.hasMoreElements() ) {
                var entry = entries.nextElement();
                if ( entry.isDirectory() || !reFindNoCase( arguments.entryRegex, entry.getName() ) ) continue;
                var safeName = reReplace( getFileFromPath( replace( entry.getName(), "\", "/", "all" ) ), "[^A-Za-z0-9._-]", "_", "all" );
                var target = arguments.workDir & safeName;
                if ( !directoryExists( arguments.workDir ) ) directoryCreate( arguments.workDir );
                var input = zip.getInputStream( entry );
                var output = createObject( "java", "java.io.FileOutputStream" ).init( target, false );
                try {
                    input.transferTo( output );
                } finally {
                    output.close();
                    input.close();
                }
                return target;
            }
        } finally {
            zip.close();
        }
        throw( type = "ImportException", message = "The archive does not contain a file matching #arguments.entryRegex#." );
    }

    /** Streams a text file line by line (UTF-8). Return false from the callback to stop. */
    public void function eachLine( required string path, required function callback ) {
        var reader = createObject( "java", "java.io.BufferedReader" ).init(
            createObject( "java", "java.io.InputStreamReader" ).init( createObject( "java", "java.io.FileInputStream" ).init( arguments.path ), "UTF-8" ), 1048576 );
        try {
            var lineNo = 0;
            var line = reader.readLine();
            while ( !isNull( line ) ) {
                lineNo++;
                if ( arguments.callback( line, lineNo ) === false ) break;
                line = reader.readLine();
            }
        } finally {
            reader.close();
        }
    }

}
