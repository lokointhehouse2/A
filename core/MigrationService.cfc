/**
 * Sequential SQL migrations: db/migrations/NNN_name.sql applied in filename order, tracked in schema_migrations.
 * Statements are split on lines that end with ";" (no stored procedures in migration files).
 */
component {

    variables.dsn = "futurepathDB";

    public MigrationService function init( required any logger ) {
        variables.logger = arguments.logger;
        return this;
    }

    /** Applies pending migrations; returns the names applied. */
    public array function migrate( required string directory ) {
        var applied = [];
        ensureTable();
        var done = {};
        for ( var r in queryExecute( "SELECT migration_name FROM schema_migrations", {}, { datasource: variables.dsn, returntype: "array" } ) ) {
            done[ r.migration_name ] = true;
        }
        var files = directoryList( arguments.directory, false, "name", "*.sql", "name asc" );
        for ( var fileName in files ) {
            if ( !reFind( "^[0-9]{3}_.+\.sql$", fileName ) || structKeyExists( done, fileName ) ) continue;
            var statements = split( fileRead( arguments.directory & "/" & fileName, "utf-8" ) );
            transaction {
                for ( var stmt in statements ) {
                    queryExecute( stmt, {}, { datasource: variables.dsn } );
                }
                queryExecute( "INSERT INTO schema_migrations (migration_name, applied_at) VALUES (:name, UTC_TIMESTAMP())",
                    { name: { value: fileName, cfsqltype: "varchar" } }, { datasource: variables.dsn } );
            }
            arrayAppend( applied, fileName );
            variables.logger.info( "Migration applied: " & fileName );
        }
        return applied;
    }

    public array function split( required string sql ) {
        var statements = [];
        var buffer = createObject( "java", "java.lang.StringBuilder" ).init();
        var lines = listToArray( replace( arguments.sql, chr( 13 ), "", "all" ), chr( 10 ), true );
        for ( var line in lines ) {
            var trimmed = trim( line );
            if ( !len( trimmed ) || left( trimmed, 2 ) == "--" ) continue;
            buffer.append( line ).append( chr( 10 ) );
            if ( right( trimmed, 1 ) == ";" ) {
                var stmt = trim( buffer.toString() );
                stmt = trim( left( stmt, len( stmt ) - 1 ) );
                if ( len( stmt ) ) arrayAppend( statements, stmt );
                buffer.setLength( 0 );
            }
        }
        var tail = trim( buffer.toString() );
        if ( len( tail ) ) arrayAppend( statements, tail );
        return statements;
    }

    private void function ensureTable() {
        queryExecute( "
            CREATE TABLE IF NOT EXISTS schema_migrations (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
                migration_name VARCHAR(190) NOT NULL,
                applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                UNIQUE KEY uq_schema_migrations_name (migration_name)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci", {}, { datasource: variables.dsn } );
    }

}
