/**
 * NCES CIP 2020 -> SOC 2018 crosswalk importer (official XLSX, sheet "CIP-SOC").
 * CIP codes keep their exact dotted form ("23.0101"); numeric-looking cells are re-padded to NN.NNNN.
 * "NO MATCH" rows (SOC 99-9999) are skipped and counted. This is a many-to-many mapping of programs that
 * PREPARE people for occupations; it is not a record of where graduates work.
 */
component extends="BaseImporter" {

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var ctx = arguments.ctx;
        var importer = this;
        var hdr = {};
        var cipRows = {};
        var linkRows = [];
        new XlsxStreamReader().eachRow( arguments.path, "CIP-SOC", function( cells, rowNumber ) {
            if ( structIsEmpty( hdr ) ) {
                for ( var i = 1; i <= arrayLen( cells ); i++ ) {
                    if ( cells[ i ] == "CIP2020Code" ) hdr.cip = i;
                    if ( cells[ i ] == "CIP2020Title" ) hdr.cipTitle = i;
                    if ( cells[ i ] == "SOC2018Code" ) hdr.soc = i;
                    if ( cells[ i ] == "SOC2018Title" ) hdr.socTitle = i;
                }
                if ( !structKeyExists( hdr, "soc" ) ) structClear( hdr );
                return true;
            }
            ctx.seen++;
            var cip = importer.normalizeCip( importer.cellAt( cells, hdr.cip ) );
            var soc = trim( importer.cellAt( cells, hdr.soc ) );
            if ( !len( cip ) ) { ctx.skipped++; return true; }
            if ( soc == "99-9999" || !reFind( "^[0-9]{2}-[0-9]{4}$", soc ) ) { ctx.skipped++; return true; }
            if ( !structKeyExists( cipRows, cip ) ) {
                cipRows[ cip ] = [ cip, reReplace( trim( importer.cellAt( cells, hdr.cipTitle ) ), "\.$", "" ), 6, 2020 ];
            }
            arrayAppend( linkRows, [ cip, soc, trim( importer.cellAt( cells, hdr.socTitle ) ), 2018, ctx.sourceId ] );
            return true;
        } );
        if ( structIsEmpty( hdr ) ) throw( type = "ImportException", message = "The CIP-SOC sheet header (CIP2020Code, SOC2018Code) was not found." );

        var programs = [];
        for ( var k in cipRows ) arrayAppend( programs, cipRows[ k ] );
        var counts = { seen: 0, inserted: 0, updated: 0, skipped: 0 };
        upsert( "cip_programs", [ "cip_code", "title", "cip_level", "taxonomy_year" ], [ "varchar", "varchar", "tinyint", "smallint" ], programs, [ "title", "taxonomy_year" ], counts );
        upsert( "cip_soc_crosswalk", [ "cip_code", "soc_code", "soc_title", "crosswalk_year", "source_id" ], [ "varchar", "varchar", "varchar", "smallint", "integer" ],
            linkRows, [ "soc_title", "source_id" ], ctx );
        return { vintageYear: 2020, vintageLabel: "CIP 2020 to SOC 2018 crosswalk" };
    }

    /** "23.0101" stays as is; numeric renderings such as "1.0101" or "23.0101000" become "01.0101" / "23.0101". */
    public string function normalizeCip( required string raw ) {
        var s = trim( arguments.raw );
        if ( reFind( "^[0-9]{2}\.[0-9]{4}$", s ) ) return s;
        if ( !reFind( "^[0-9]{1,2}\.[0-9]{1,8}$", s ) ) return "";
        var whole = listFirst( s, "." );
        var frac = listLast( s, "." );
        if ( len( frac ) > 4 ) {
            if ( reFind( "[1-9]", mid( frac, 5, len( frac ) ) ) ) return "";
            frac = left( frac, 4 );
        }
        return numberFormat( val( whole ), "00" ) & "." & left( frac & "0000", 4 );
    }

}
