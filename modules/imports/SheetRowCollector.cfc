/**
 * Implements POI's XSSFSheetXMLHandler.SheetContentsHandler (via createDynamicProxy) and turns cell events into rows.
 */
component {

    public SheetRowCollector function init( required any callback ) {
        variables.callback = arguments.callback;
        variables.cells = {};
        variables.maxCol = 0;
        variables.stopped = false;
        return this;
    }

    public boolean function wasStopped() {
        return variables.stopped;
    }

    public void function startRow( numeric rowNum ) {
        variables.cells = {};
        variables.maxCol = 0;
    }

    public void function endRow( numeric rowNum ) {
        if ( variables.stopped ) return;
        var row = [];
        for ( var i = 1; i <= variables.maxCol; i++ ) {
            arrayAppend( row, variables.cells[ i ] ?: "" );
        }
        if ( variables.callback( row, arguments.rowNum + 1 ) === false ) {
            variables.stopped = true;
            throw( type = "XlsxStream.Stop", message = "stop" );
        }
    }

    public void function cell( any cellReference, any formattedValue, any comment ) {
        if ( isNull( arguments.cellReference ) ) return;
        var ref = arguments.cellReference;
        var col = 0;
        var i = 1;
        var n = len( ref );
        while ( i <= n ) {
            var c = asc( mid( ref, i, 1 ) );
            if ( c < 65 || c > 90 ) break;
            col = col * 26 + ( c - 64 );
            i++;
        }
        if ( col == 0 ) return;
        variables.cells[ col ] = isNull( arguments.formattedValue ) ? "" : trim( arguments.formattedValue );
        if ( col > variables.maxCol ) variables.maxCol = col;
    }

    public void function headerFooter( any text, any isHeader, any tagName ) {}

    public void function endSheet() {}

    public void function hyperlinkCell( any cellReference, any formattedValue, any url, any toolTip, any comment ) {
        cell( arguments.cellReference, arguments.formattedValue, arguments.comment );
    }

}
