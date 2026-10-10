/**
 * Streaming .xlsx reader built on Apache POI's event (SAX) API: rows are handed to a callback one at a time,
 * so very large government workbooks (e.g. the ~150k-row OEWS metro file) never load into memory.
 *
 *   reader.eachRow( path, "Sheet name or 1-based index", function( cells, rowNumber ) { ...; return true; } );
 *
 * cells is an array of trimmed strings (missing cells = ""). Return false from the callback to stop early.
 */
component {

    public array function sheetNames( required string path ) {
        var names = [];
        var pkg = openPackage( arguments.path );
        try {
            var it = createObject( "java", "org.apache.poi.xssf.eventusermodel.XSSFReader" ).init( pkg ).getSheetsData();
            while ( it.hasNext() ) {
                var stream = it.next();
                arrayAppend( names, it.getSheetName() );
                stream.close();
            }
        } finally {
            pkg.revert();
        }
        return names;
    }

    public void function eachRow( required string path, required any sheet, required any callback ) {
        var pkg = openPackage( arguments.path );
        try {
            var reader = createObject( "java", "org.apache.poi.xssf.eventusermodel.XSSFReader" ).init( pkg );
            var strings = createObject( "java", "org.apache.poi.xssf.eventusermodel.ReadOnlySharedStringsTable" ).init( pkg );
            var styles = reader.getStylesTable();
            var it = reader.getSheetsData();
            var index = 0;
            var found = false;
            while ( it.hasNext() ) {
                var stream = it.next();
                index++;
                var name = it.getSheetName();
                var wanted = isNumeric( arguments.sheet ) ? index == arguments.sheet : name == arguments.sheet;
                if ( wanted && !found ) {
                    found = true;
                    try {
                        parseSheet( stream, styles, strings, arguments.callback );
                    } finally {
                        stream.close();
                    }
                } else {
                    stream.close();
                }
            }
            if ( !found ) throw( type = "ImportException", message = "Worksheet '#arguments.sheet#' was not found in #getFileFromPath( arguments.path )#." );
        } finally {
            pkg.revert();
        }
    }

    private void function parseSheet( required any stream, required any styles, required any strings, required any callback ) {
        var collector = new SheetRowCollector( arguments.callback );
        var proxy = createDynamicProxy( collector, [ "org.apache.poi.xssf.eventusermodel.XSSFSheetXMLHandler$SheetContentsHandler" ] );
        var formatter = createObject( "java", "org.apache.poi.ss.usermodel.DataFormatter" ).init();
        var handler = createObject( "java", "org.apache.poi.xssf.eventusermodel.XSSFSheetXMLHandler" ).init( arguments.styles, arguments.strings, proxy, formatter, false );
        var parser = createObject( "java", "org.apache.poi.util.XMLHelper" ).newXMLReader();
        parser.setContentHandler( handler );
        try {
            parser.parse( createObject( "java", "org.xml.sax.InputSource" ).init( arguments.stream ) );
        } catch ( any e ) {
            // The collector stops parsing by throwing; anything else is a real failure.
            if ( !collector.wasStopped() ) rethrow;
        }
    }

    private any function openPackage( required string path ) {
        if ( !fileExists( arguments.path ) ) throw( type = "ImportException", message = "File not found: #getFileFromPath( arguments.path )#" );
        var access = createObject( "java", "org.apache.poi.openxml4j.opc.PackageAccess" ).READ;
        return createObject( "java", "org.apache.poi.openxml4j.opc.OPCPackage" ).open( arguments.path, access );
    }

}
