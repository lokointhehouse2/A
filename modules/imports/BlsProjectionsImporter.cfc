/**
 * BLS Employment Projections importer.
 *   ep_education.xlsx  Table 5.4  typical entry-level education, work experience, on-the-job training
 *   ep_occupation.xlsx Table 1.2  employment projections and annual openings (same folder, optional)
 * Also derives occupation_pathways from the BLS education assignment. These are "common" routes for the typical
 * worker, never presented as legal requirements, and alternatives (GED, apprenticeship) are added where relevant.
 */
component extends="BaseImporter" {

    public struct function import( required string path, required struct ctx, required string datasetKey ) {
        var dir = getDirectoryFromPath( arguments.path );
        var reader = new XlsxStreamReader();
        var ctx = arguments.ctx;
        var importer = this;

        // ---------------- Table 5.4 education and training assignments
        var education = {};
        var meta = { baseYear: 0, period: "" };
        var hdr = {};
        reader.eachRow( arguments.path, "Table 5.4", function( cells, rowNumber ) {
            if ( structIsEmpty( hdr ) ) {
                for ( var i = 1; i <= arrayLen( cells ); i++ ) {
                    var c = cells[ i ];
                    if ( reFindNoCase( "National Employment Matrix code", c ) ) {
                        hdr.code = i;
                        var y = reMatch( "[0-9]{4}", c );
                        if ( arrayLen( y ) ) meta.baseYear = val( y[ 1 ] );
                    }
                    if ( reFindNoCase( "National Employment Matrix title", c ) ) hdr.title = i;
                    if ( reFindNoCase( "^Typical education", c ) ) hdr.edu = i;
                    if ( reFindNoCase( "^Work experience", c ) ) hdr.exp = i;
                    if ( reFindNoCase( "on-the-job training", c ) ) hdr.ojt = i;
                }
                if ( !structKeyExists( hdr, "edu" ) ) structClear( hdr );
                return true;
            }
            var code = importer.cellAt( cells, hdr.code );
            if ( !reFind( "^[0-9]{2}-[0-9]{4}$", code ) ) return true;
            education[ code ] = {
                title: reReplace( importer.cellAt( cells, hdr.title ), "\[[0-9]+\]", "", "all" ),
                edu: importer.cellAt( cells, hdr.edu ), exp: importer.cellAt( cells, hdr.exp ), ojt: importer.cellAt( cells, hdr.ojt )
            };
            return true;
        } );
        if ( structIsEmpty( education ) ) throw( type = "ImportException", message = "Table 5.4 (education and training assignments) was not found or was empty." );

        // ---------------- Table 1.2 projections (optional companion file)
        var projections = {};
        var projFile = dir & "ep_occupation.xlsx";
        if ( fileExists( projFile ) ) {
            var ph = {};
            reader.eachRow( projFile, "Table 1.2", function( cells, rowNumber ) {
                if ( !len( meta.period ) && arrayLen( cells ) && reFind( "[0-9]{4}.[0-9]{2}", cells[ 1 ] ) ) {
                    var pm = reMatch( "[0-9]{4}.[0-9]{2}", cells[ 1 ] );
                    meta.period = left( pm[ 1 ], 4 ) & "-" & right( pm[ 1 ], 2 );
                }
                if ( structIsEmpty( ph ) ) {
                    for ( var i = 1; i <= arrayLen( cells ); i++ ) {
                        var c = cells[ i ];
                        if ( reFindNoCase( "National Employment Matrix code", c ) ) ph.code = i;
                        if ( reFindNoCase( "^Occupation type", c ) ) ph.type = i;
                        if ( reFindNoCase( "^Employment, [0-9]{4}$", c ) && !structKeyExists( ph, "empBase" ) ) ph.empBase = i;
                        else if ( reFindNoCase( "^Employment, [0-9]{4}$", c ) ) ph.empProj = i;
                        if ( reFindNoCase( "^Employment change, percent", c ) ) ph.pct = i;
                        if ( reFindNoCase( "^Occupational openings", c ) ) ph.openings = i;
                    }
                    if ( !structKeyExists( ph, "pct" ) ) structClear( ph );
                    return true;
                }
                var code = importer.cellAt( cells, ph.code );
                if ( !reFind( "^[0-9]{2}-[0-9]{4}$", code ) || ( importer.cellAt( cells, ph.type ) ) != "Line item" ) return true;
                projections[ code ] = {
                    empBase: importer.num( importer.cellAt( cells, ph.empBase ) ), empProj: importer.num( importer.cellAt( cells, ph.empProj ) ),
                    pct: importer.num( importer.cellAt( cells, ph.pct ) ), openings: importer.num( importer.cellAt( cells, ph.openings ) )
                };
                return true;
            } );
        } else {
            warn( ctx, "ep_occupation.xlsx not found next to ep_education.xlsx; outlook figures were not imported." );
        }

        // ---------------- write
        var pathwayIds = {};
        for ( var p in queryExecute( "SELECT id, pathway_key FROM education_pathways", {}, { datasource: variables.dsn, returntype: "array" } ) ) pathwayIds[ p.pathway_key ] = p.id;

        var occRows = [];
        var profileRows = [];
        var pathRows = [];
        var srcUrl = "https://www.bls.gov/emp/tables.htm";
        for ( var code in education ) {
            ctx.seen++;
            var e = education[ code ];
            var pr = projections[ code ] ?: {};
            arrayAppend( occRows, [ code, trim( e.title ), "detailed", e.edu, meta.baseYear ] );
            arrayAppend( profileRows, [
                code,
                "Typical entry-level education: #e.edu#. Work experience in a related occupation: #e.exp#. Typical on-the-job training: #e.ojt#.",
                e.edu, e.exp, e.ojt,
                pr.empBase ?: javacast( "null", "" ), pr.empProj ?: javacast( "null", "" ), pr.pct ?: javacast( "null", "" ), pr.openings ?: javacast( "null", "" ),
                len( meta.period ) ? meta.period : javacast( "null", "" ), meta.baseYear, ctx.sourceId, srcUrl
            ] );
            for ( var link in pathwaysFor( code, e.edu, e.ojt ) ) {
                if ( structKeyExists( pathwayIds, link.key ) ) arrayAppend( pathRows, [ code, pathwayIds[ link.key ], link.status, link.note ] );
            }
        }

        // Occupations seen only in EP (no OEWS wages) are added so profiles can reference them; OEWS titles are kept.
        upsert( "occupations", [ "soc_code", "title", "occupation_group", "education_category", "source_year" ],
            [ "varchar", "varchar", "varchar", "varchar", "smallint" ], occRows, [ "education_category" ], ctx );
        ctx.inserted = 0;
        ctx.updated = 0;
        upsert( "occupation_profiles", [ "soc_code", "education_notes", "typical_entry_education", "work_experience", "ojt_training",
                "employment_base_thousands", "employment_projected_thousands", "outlook_percent", "annual_openings_thousands",
                "outlook_period", "outlook_year", "source_id", "source_url" ],
            [ "varchar", "varchar", "varchar", "varchar", "varchar", "decimal", "decimal", "decimal", "decimal", "varchar", "smallint", "integer", "varchar" ],
            profileRows,
            [ "education_notes", "typical_entry_education", "work_experience", "ojt_training", "employment_base_thousands", "employment_projected_thousands",
              "outlook_percent", "annual_openings_thousands", "outlook_period", "outlook_year", "source_id", "source_url" ], ctx );
        queryExecute( "DELETE FROM occupation_pathways", {}, { datasource: variables.dsn } );
        var pathCounts = { seen: 0, inserted: 0, updated: 0, skipped: 0 };
        upsert( "occupation_pathways", [ "soc_code", "pathway_id", "requirement_status", "source_notes" ], [ "varchar", "integer", "varchar", "varchar" ],
            pathRows, [ "requirement_status", "source_notes" ], pathCounts );

        return { vintageYear: meta.baseYear, vintageLabel: "BLS Employment Projections #len( meta.period ) ? meta.period : meta.baseYear#" };
    }

    /** Maps a BLS typical-entry-education assignment (plus OJT) to generic pathway links. */
    public array function pathwaysFor( required string soc, required string education, required string ojt ) {
        var e = lCase( arguments.education );
        var apprenticeship = findNoCase( "apprenticeship", arguments.ojt ) > 0;
        var note = "BLS typical entry-level education: #arguments.education#";
        var out = [];
        if ( e == "no formal educational credential" ) {
            arrayAppend( out, { key: "work", status: "common", note: note } );
            arrayAppend( out, { key: "ged", status: "alternative", note: "Optional; many employers value a high school credential" } );
        } else if ( findNoCase( "high school diploma", e ) ) {
            arrayAppend( out, { key: apprenticeship ? "apprenticeship" : "work", status: "common", note: note & ( apprenticeship ? "; training: apprenticeship" : "" ) } );
            arrayAppend( out, { key: "ged", status: "alternative", note: "A GED is generally accepted as the equivalent of a high school diploma" } );
            if ( apprenticeship ) arrayAppend( out, { key: "work", status: "alternative", note: "Some workers start as helpers before or instead of a formal apprenticeship" } );
        } else if ( findNoCase( "postsecondary nondegree", e ) || findNoCase( "some college", e ) ) {
            arrayAppend( out, { key: "certificate", status: "common", note: note } );
            arrayAppend( out, { key: "associate", status: "alternative", note: "Some programs are offered as associate degrees" } );
        } else if ( findNoCase( "associate", e ) ) {
            arrayAppend( out, { key: "associate", status: "common", note: note } );
        } else if ( findNoCase( "bachelor", e ) ) {
            arrayAppend( out, { key: "bachelor", status: "common", note: note } );
        } else if ( findNoCase( "master", e ) ) {
            arrayAppend( out, { key: "master", status: "common", note: note } );
        } else if ( findNoCase( "doctoral or professional", e ) ) {
            var key = "doctoral";
            if ( reFind( "^29-12", arguments.soc ) ) key = "medicine";
            else if ( listFind( "23-1011,29-1021,29-1022,29-1023,29-1024,29-1029,29-1051,29-1131,29-1041,29-1081,29-1011,29-1123,29-1122", arguments.soc ) ) key = "professional";
            arrayAppend( out, { key: key, status: "common", note: note } );
        }
        if ( apprenticeship && !findNoCase( "high school", e ) ) arrayAppend( out, { key: "apprenticeship", status: "alternative", note: "BLS lists apprenticeship as typical on-the-job training" } );
        return out;
    }

}
