/**
 * Census ACS 5-year table-based summary file importer (pipe-delimited .dat, all geographies in one file).
 * Only CBSA rows (GEO_ID 310M...US<CBSA>) are kept; the CBSA code is read from the GEO_ID, not from a name.
 *   B25031  median gross rent by bedrooms (gross rent includes utilities)  -> rent_observations
 *   B25077  median value, owner-occupied housing units                    -> housing_price_observations
 * Negative "jam" values (-666666666 etc.) mean the estimate is not available and are stored as NULL.
 * The Census Data API now requires a key; the summary files used here do not.
 */
component extends="BaseImporter" {

    variables.bedroomColumns = { "E001": "all", "E002": "0", "E003": "1", "E004": "2", "E005": "3", "E006": "4", "E007": "5+" };

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var fileName = getFileFromPath( arguments.path );
        var m = reFindNoCase( "^acsdt5y([0-9]{4})-(b[0-9]{5})\.dat$", fileName, 1, true );
        if ( m.pos[ 1 ] == 0 ) throw( type = "ImportException", message = "Expected an ACS table-based summary file named like acsdt5y2024-b25031.dat." );
        var year = val( mid( fileName, m.pos[ 2 ], m.len[ 2 ] ) );
        var table = uCase( mid( fileName, m.pos[ 3 ], m.len[ 3 ] ) );
        if ( table != "B25031" && table != "B25077" ) throw( type = "ImportException", message = "Only ACS tables B25031 and B25077 are supported." );
        var period = "#year - 4#-#year# ACS 5-year";
        var ctx = arguments.ctx;
        var importer = this;
        var cols = {};
        var rows = [];
        var metros = {};
        for ( var r in queryExecute( "SELECT cbsa_code FROM metro_areas", {}, { datasource: variables.dsn, returntype: "array" } ) ) metros[ r.cbsa_code ] = true;

        eachLine( arguments.path, function( line, lineNo ) {
            if ( lineNo > 1 && left( line, 4 ) != "310M" ) return true;
            var parts = listToArray( line, "|", true );
            if ( lineNo == 1 ) {
                for ( var i = 1; i <= arrayLen( parts ); i++ ) cols[ uCase( parts[ i ] ) ] = i;
                if ( !structKeyExists( cols, "GEO_ID" ) ) throw( type = "ImportException", message = "ACS file header (GEO_ID) not found." );
                return true;
            }
            if ( left( parts[ 1 ], 4 ) != "310M" ) return true;
            ctx.seen++;
            var cbsa = right( parts[ 1 ], 5 );
            if ( !reFind( "^[0-9]{5}$", cbsa ) ) { ctx.skipped++; return true; }
            var mapped = structKeyExists( metros, cbsa ) ? cbsa : javacast( "null", "" );
            if ( table == "B25031" ) {
                for ( var suffix in variables.bedroomColumns ) {
                    var est = importer.acsValue( parts, cols, "B25031_" & suffix );
                    var moe = importer.acsValue( parts, cols, "B25031_M" & right( suffix, 3 ) );
                    arrayAppend( rows, [ "ACS_CBSA", cbsa, mapped, variables.bedroomColumns[ suffix ], est, moe, year, period, "ACS_MEDIAN_GROSS_RENT", ctx.sourceId, ctx.runId ] );
                }
            } else {
                arrayAppend( rows, [ "ACS_CBSA", cbsa, mapped, importer.acsValue( parts, cols, "B25077_E001" ), importer.acsValue( parts, cols, "B25077_M001" ), year, period, "ACS_MEDIAN_HOME_VALUE", ctx.sourceId, ctx.runId ] );
            }
            return true;
        } );

        if ( table == "B25031" ) {
            upsert( "rent_observations", [ "geo_system", "geo_code", "cbsa_code", "bedroom_key", "monthly_rent", "margin_of_error", "year", "period_label", "measurement_type", "source_id", "import_run_id" ],
                [ "varchar", "varchar", "char", "varchar", "decimal", "decimal", "smallint", "varchar", "varchar", "integer", "bigint" ],
                rows, [ "cbsa_code", "monthly_rent", "margin_of_error", "period_label", "source_id", "import_run_id" ], ctx );
        } else {
            upsert( "housing_price_observations", [ "geo_system", "geo_code", "cbsa_code", "value", "margin_of_error", "year", "period_label", "metric_type", "source_id", "import_run_id" ],
                [ "varchar", "varchar", "char", "decimal", "decimal", "smallint", "varchar", "varchar", "integer", "bigint" ],
                rows, [ "cbsa_code", "value", "margin_of_error", "period_label", "source_id", "import_run_id" ], ctx );
        }
        return { vintageYear: year, vintageLabel: "ACS #period# (#table#)" };
    }

    public any function acsValue( required array parts, required struct cols, required string column ) {
        var idx = arguments.cols[ arguments.column ] ?: 0;
        if ( idx == 0 || idx > arrayLen( arguments.parts ) ) return javacast( "null", "" );
        var v = num( arguments.parts[ idx ] );
        if ( isNull( v ) || v < 0 ) return javacast( "null", "" );
        return v;
    }

}
