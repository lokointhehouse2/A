/**
 * BLS Occupational Employment and Wage Statistics (OEWS) importer.
 * Accepts the official special-request archives: oesmYYma.zip (metropolitan areas) or oesmYYnat.zip (national).
 *
 * Published codes are preserved, never coerced to 0:
 *   *  wage estimate not available        -> NULL + suppression_code "FIELD:*"
 *   ** employment estimate not available  -> NULL + suppression_code "FIELD:**"
 *   #  wage >= top-code ($115/hr, $239,200/yr in May 2025) -> NULL + topcoded_fields
 * Metro areas are keyed by their published CBSA code (AREA), never by fuzzy city-name matching.
 */
component extends="BaseImporter" {

    variables.wageFields = [
        { col: "A_MEAN", db: "annual_mean" }, { col: "H_MEAN", db: "hourly_mean" },
        { col: "A_MEDIAN", db: "annual_median" }, { col: "H_MEDIAN", db: "hourly_median" },
        { col: "A_PCT10", db: "annual_p10" }, { col: "A_PCT25", db: "annual_p25" },
        { col: "A_PCT75", db: "annual_p75" }, { col: "A_PCT90", db: "annual_p90" }
    ];

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var fileName = getFileFromPath( arguments.path );
        var m = reFindNoCase( "oesm([0-9]{2})(ma|nat)\.zip$", fileName, 1, true );
        if ( m.pos[ 1 ] == 0 ) throw( type = "ImportException", message = "Expected an OEWS archive named like oesm25ma.zip or oesm25nat.zip." );
        var year = 2000 + val( mid( fileName, m.pos[ 2 ], m.len[ 2 ] ) );
        var scope = lCase( mid( fileName, m.pos[ 3 ], m.len[ 3 ] ) );
        var workDir = application.config.importWorkPath & "oews_" & scope & year & "/";
        progress( arguments.ctx, "Extracting workbook" );
        var xlsx = extractZipEntry( arguments.path, scope == "ma" ? "MSA_M[0-9]{4}_dl\.xlsx$" : "national_M[0-9]{4}_dl\.xlsx$", workDir );

        var sourceId = arguments.ctx.sourceId;
        var stateFips = loadStateFips();
        var knownMetros = {};
        var knownOccupations = {};
        var occRows = [];
        var wageRows = [];
        var header = {};
        var importer = this;
        var ctx = arguments.ctx;

        new XlsxStreamReader().eachRow( xlsx, 1, function( cells, rowNumber ) {
            if ( structIsEmpty( header ) ) {
                if ( arrayFindNoCase( cells, "OCC_CODE" ) ) {
                    for ( var i = 1; i <= arrayLen( cells ); i++ ) header[ uCase( cells[ i ] ) ] = i;
                    for ( var required in [ "AREA", "AREA_TITLE", "AREA_TYPE", "OCC_CODE", "OCC_TITLE", "O_GROUP", "TOT_EMP", "A_MEDIAN" ] ) {
                        if ( !structKeyExists( header, required ) ) throw( type = "ImportException", message = "OEWS workbook is missing the #required# column; the file layout may have changed." );
                    }
                }
                return true;
            }
            ctx.seen++;
            var get = function( name ) {
                var idx = header[ name ] ?: 0;
                return idx > 0 && idx <= arrayLen( cells ) ? cells[ idx ] : "";
            };
            var areaType = get( "AREA_TYPE" );
            var group = lCase( get( "O_GROUP" ) );
            var soc = get( "OCC_CODE" );
            if ( !reFind( "^[0-9]{2}-[0-9]{4}$", soc ) ) { ctx.skipped++; return true; }
            if ( scope == "ma" && areaType != "4" ) { ctx.skipped++; return true; }

            // occupations (all levels kept for grouping; detailed ones are searchable)
            if ( !structKeyExists( knownOccupations, soc ) ) {
                knownOccupations[ soc ] = true;
                arrayAppend( occRows, [ soc, get( "OCC_TITLE" ), group, year ] );
            }

            var areaLevel = scope == "ma" ? "metro" : "national";
            var areaCode = scope == "ma" ? get( "AREA" ) : "99";
            var cbsa = javacast( "null", "" );
            if ( scope == "ma" ) {
                if ( !reFind( "^[0-9]{5}$", areaCode ) ) { ctx.skipped++; importer.warn( ctx, "Skipped non-CBSA area code #areaCode#" ); return true; }
                cbsa = areaCode;
                if ( !structKeyExists( knownMetros, cbsa ) ) {
                    knownMetros[ cbsa ] = { name: get( "AREA_TITLE" ), primaryState: get( "PRIM_STATE" ) };
                }
            }
            if ( group != "detailed" && group != "total" ) return true;

            var suppression = [];
            var topcoded = [];
            var values = {};
            for ( var f in variables.wageFields ) {
                var raw = get( f.col );
                if ( raw == "*" ) arrayAppend( suppression, f.col & ":*" );
                else if ( raw == "##" ) arrayAppend( topcoded, f.col );
                values[ f.db ] = importer.num( raw );
            }
            var empRaw = get( "TOT_EMP" );
            if ( empRaw == "**" ) arrayAppend( suppression, "TOT_EMP:**" );
            var emp = importer.num( empRaw );

            arrayAppend( wageRows, [
                soc, areaLevel, areaCode, cbsa, year,
                isNull( emp ) ? javacast( "null", "" ) : int( emp ),
                importer.num( get( "EMP_PRSE" ) ),
                values.hourly_mean, values.annual_mean, importer.num( get( "MEAN_PRSE" ) ),
                values.hourly_median, values.annual_median,
                values.annual_p10, values.annual_p25, values.annual_p75, values.annual_p90,
                uCase( get( "ANNUAL" ) ) == "TRUE" ? 1 : 0,
                uCase( get( "HOURLY" ) ) == "TRUE" ? 1 : 0,
                arrayLen( suppression ) ? arrayToList( suppression, ";" ) : javacast( "null", "" ),
                arrayLen( topcoded ) ? arrayToList( topcoded, "," ) : javacast( "null", "" ),
                sourceId, ctx.runId
            ] );

            if ( arrayLen( wageRows ) >= 2000 ) {
                importer.flush( knownMetros, stateFips, occRows, wageRows, year, ctx );
                importer.progress( ctx, "Imported #numberFormat( ctx.inserted )# wage rows" );
            }
            return true;
        } );

        if ( structIsEmpty( header ) ) throw( type = "ImportException", message = "Could not find the OEWS header row (OCC_CODE)." );
        flush( knownMetros, stateFips, occRows, wageRows, year, arguments.ctx );
        try { directoryDelete( workDir, true ); } catch ( any e ) {}
        return { vintageYear: year, vintageLabel: "May #year# OEWS (#scope == 'ma' ? 'metropolitan areas' : 'national'#)" };
    }

    /** Writes buffered metros, occupations and wage rows (in FK order) and clears the buffers. */
    public void function flush( required struct knownMetros, required struct stateFips, required array occRows, required array wageRows, required numeric year, required struct ctx ) {
        var metroRows = [];
        var mapRows = [];
        for ( var cbsa in arguments.knownMetros ) {
            var meta = arguments.knownMetros[ cbsa ];
            if ( meta.written ?: false ) continue;
            meta.written = true;
            arrayAppend( metroRows, [ cbsa, meta.name, "MSA", left( meta.primaryState, 2 ), arguments.year, 1 ] );
            // States are the postal codes after the comma in the official title, e.g. "Washington-Arlington-Alexandria, DC-VA-MD-WV"
            var statePart = trim( listLast( meta.name, "," ) );
            for ( var st in listToArray( statePart, "-" ) ) {
                st = uCase( trim( st ) );
                if ( structKeyExists( arguments.stateFips, st ) ) arrayAppend( mapRows, [ cbsa, arguments.stateFips[ st ] ] );
            }
        }
        var counts = { seen: 0, inserted: 0, updated: 0, skipped: 0 };
        upsert( "metro_areas", [ "cbsa_code", "name", "geographic_type", "primary_state_code", "source_year", "active_flag" ],
            [ "char", "varchar", "varchar", "char", "smallint", "tinyint" ], metroRows, [ "name", "primary_state_code", "source_year", "active_flag" ], counts );
        upsert( "metro_state_map", [ "cbsa_code", "state_fips" ], [ "char", "char" ], mapRows, [ "state_fips" ], counts );
        upsert( "occupations", [ "soc_code", "title", "occupation_group", "source_year" ], [ "varchar", "varchar", "varchar", "smallint" ],
            arguments.occRows, [ "title", "occupation_group", "source_year" ], counts );
        upsert( "occupational_wages", [
                "soc_code", "area_level", "area_code", "cbsa_code", "wage_year", "employment_count", "employment_prse",
                "hourly_mean", "annual_mean", "mean_prse", "hourly_median", "annual_median",
                "annual_p10", "annual_p25", "annual_p75", "annual_p90", "annual_only", "hourly_only",
                "suppression_code", "topcoded_fields", "source_id", "import_run_id" ],
            [ "varchar", "varchar", "varchar", "char", "smallint", "integer", "decimal",
              "decimal", "decimal", "decimal", "decimal", "decimal",
              "decimal", "decimal", "decimal", "decimal", "tinyint", "tinyint",
              "varchar", "varchar", "integer", "bigint" ],
            arguments.wageRows,
            [ "cbsa_code", "employment_count", "employment_prse", "hourly_mean", "annual_mean", "mean_prse", "hourly_median", "annual_median",
              "annual_p10", "annual_p25", "annual_p75", "annual_p90", "annual_only", "hourly_only", "suppression_code", "topcoded_fields",
              "source_id", "import_run_id" ],
            arguments.ctx );
        arrayClear( arguments.occRows );
        arrayClear( arguments.wageRows );
    }

    private struct function loadStateFips() {
        var out = {};
        for ( var r in queryExecute( "SELECT state_code, state_fips FROM states", {}, { datasource: variables.dsn, returntype: "array" } ) ) {
            out[ r.state_code ] = r.state_fips;
        }
        return out;
    }

}
