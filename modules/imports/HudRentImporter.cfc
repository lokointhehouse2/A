/**
 * HUD Fair Market Rents importer (FYyy_FMRs.xlsx, one row per county/town with its HUD FMR area).
 * Rents are stored per HUD FMR area, and each area is mapped to a CBSA explicitly:
 *   METRO36740M36740  -> CBSA 36740, exact (HUD area equals the metro area)
 *   METRO35620MM5600  -> CBSA 35620, partial (HUD subdivides the metro; this area covers only part of it)
 *   NCNTY...          -> no CBSA (nonmetropolitan county)
 */
component extends="BaseImporter" {

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var fileName = getFileFromPath( arguments.path );
        var fm = reFindNoCase( "^FY([0-9]{2})", fileName, 1, true );
        if ( fm.pos[ 1 ] == 0 ) throw( type = "ImportException", message = "Expected a HUD file named like FY27_FMRs.xlsx." );
        var fy = 2000 + val( mid( fileName, fm.pos[ 2 ], fm.len[ 2 ] ) );
        var ctx = arguments.ctx;
        var importer = this;
        var hdr = {};
        var areas = {};
        var sheetName = "";
        for ( var n in new XlsxStreamReader().sheetNames( arguments.path ) ) {
            if ( reFindNoCase( "FMR", n ) && !len( sheetName ) ) sheetName = n;
        }
        if ( !len( sheetName ) ) sheetName = 1;

        new XlsxStreamReader().eachRow( arguments.path, sheetName, function( cells, rowNumber ) {
            if ( structIsEmpty( hdr ) ) {
                for ( var i = 1; i <= arrayLen( cells ); i++ ) hdr[ lCase( cells[ i ] ) ] = i;
                if ( !structKeyExists( hdr, "hud_area_code" ) || !structKeyExists( hdr, "fmr_2" ) ) structClear( hdr );
                return true;
            }
            ctx.seen++;
            var code = trim( importer.cellAt( cells, hdr.hud_area_code ) );
            if ( !len( code ) ) { ctx.skipped++; return true; }
            var pop = importer.num( importer.cellAt( cells, hdr.pop2024 ?: ( hdr.pop2023 ?: 0 ) ) );
            if ( !structKeyExists( areas, code ) ) {
                var rents = {};
                for ( var b = 0; b <= 4; b++ ) rents[ b ] = importer.num( importer.cellAt( cells, hdr[ "fmr_#b#" ] ?: 0 ) );
                areas[ code ] = { name: trim( importer.cellAt( cells, hdr.hud_area_name ) ), population: 0, rents: rents, states: {} };
            }
            areas[ code ].population += isNull( pop ) ? 0 : pop;
            areas[ code ].states[ importer.cellAt( cells, hdr.stusps ) ] = true;
            return true;
        } );
        if ( structIsEmpty( areas ) ) throw( type = "ImportException", message = "No FMR rows were found (expected hud_area_code and fmr_0..fmr_4 columns)." );

        var metros = {};
        for ( var r in queryExecute( "SELECT cbsa_code FROM metro_areas", {}, { datasource: variables.dsn, returntype: "array" } ) ) metros[ r.cbsa_code ] = true;

        var mapRows = [];
        var rentRows = [];
        for ( var code in areas ) {
            var a = areas[ code ];
            var cbsa = javacast( "null", "" );
            var quality = "none";
            var note = "Nonmetropolitan HUD area";
            var m = reFind( "^METRO([0-9]{5})M(.+)$", code, 1, true );
            if ( m.pos[ 1 ] ) {
                var candidate = mid( code, m.pos[ 2 ], m.len[ 2 ] );
                var suffix = mid( code, m.pos[ 3 ], m.len[ 3 ] );
                if ( structKeyExists( metros, candidate ) ) {
                    cbsa = candidate;
                    quality = suffix == candidate ? "exact" : "partial";
                    note = quality == "exact" ? "HUD FMR area matches the CBSA" : "HUD FMR area covers part of the CBSA (HUD subdivides this metro)";
                } else {
                    note = "CBSA #candidate# not present in imported metro areas";
                    warn( ctx, "HUD area #code# references CBSA #candidate#, which is not in metro_areas (import OEWS first)." );
                }
            }
            arrayAppend( mapRows, [ "HUD_FMR_AREA", code, a.name, cbsa, quality, int( a.population ), left( note, 500 ) ] );
            for ( var b = 0; b <= 4; b++ ) {
                arrayAppend( rentRows, [ "HUD_FMR_AREA", code, a.name, cbsa, toString( b ), a.rents[ b ], fy, "FY#fy#", "HUD_FMR", ctx.sourceId, ctx.runId ] );
            }
        }
        var counts = { seen: 0, inserted: 0, updated: 0, skipped: 0 };
        upsert( "geo_source_mappings", [ "geo_system", "external_geo_code", "external_name", "cbsa_code", "mapping_quality", "population", "notes" ],
            [ "varchar", "varchar", "varchar", "char", "varchar", "integer", "varchar" ], mapRows, [ "external_name", "cbsa_code", "mapping_quality", "population", "notes" ], counts );
        upsert( "rent_observations", [ "geo_system", "geo_code", "geo_name", "cbsa_code", "bedroom_key", "monthly_rent", "year", "period_label", "measurement_type", "source_id", "import_run_id" ],
            [ "varchar", "varchar", "varchar", "char", "varchar", "decimal", "smallint", "varchar", "varchar", "integer", "bigint" ],
            rentRows, [ "geo_name", "cbsa_code", "monthly_rent", "period_label", "source_id", "import_run_id" ], ctx );
        return { vintageYear: fy, vintageLabel: "HUD Fair Market Rents FY#fy#" };
    }

}
