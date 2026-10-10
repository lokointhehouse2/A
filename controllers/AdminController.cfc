/**
 * Protected data administration: source catalogue, import history, upload with preview, allowlisted downloads.
 * Every route except the login form requires an admin session (front controller) and every POST a CSRF token.
 */
component extends="BaseController" {

    variables.uploadExtensions = { zip: "zip", xlsx: "xlsx", dat: "dat", json: "json" };

    public struct function loginForm( required struct rc ) {
        if ( variables.b.adminAuth.isAuthenticated() ) return redirect( "/admin" );
        return view( "admin/login", { title: "Admin sign in", next: safeNext( arguments.rc.next ?: "" ) } );
    }

    public struct function login( required struct rc ) {
        var err = variables.b.adminAuth.login( arguments.rc.email ?: "", arguments.rc.password ?: "", cgi.remote_addr );
        if ( len( err ) ) {
            flash( "danger", err );
            return redirect( "/admin/login" );
        }
        return redirect( safeNext( arguments.rc.next ?: "" ) );
    }

    public struct function logout( required struct rc ) {
        variables.b.adminAuth.logout();
        return redirect( "/" );
    }

    public struct function index( required struct rc ) {
        return redirect( "/admin/imports" );
    }

    public struct function imports( required struct rc ) {
        return view( "admin/imports", {
            title: "Data imports",
            datasets: variables.b.importRunner.status(),
            history: variables.b.importRunner.history( 40 ),
            busy: variables.b.importRunner.isBusy(),
            scorecardKey: len( variables.b.config.scorecardApiKey ) > 0,
            blsContact: len( variables.b.config.blsContactEmail ) > 0
        }, "admin" );
    }

    public struct function importRun( required struct rc ) {
        return view( "admin/run", { title: "Import run", run: variables.b.importRunner.runSummary( arguments.rc.id ) }, "admin" );
    }

    /** Re-imports the newest raw file for a dataset in the background. */
    public struct function runImport( required struct rc ) {
        var d = variables.b.importRunner.dataset( arguments.rc.dataset ?: "" );
        if ( variables.b.importRunner.isBusy() ) {
            flash( "warning", "Another import is still running. Try again when it finishes." );
            return redirect( "/admin/imports" );
        }
        if ( !len( variables.b.importRunner.findRawFile( d.key ) ) ) {
            flash( "warning", "No file is available for #d.label#. Upload one or use Download." );
            return redirect( "/admin/imports" );
        }
        variables.b.importRunner.runInBackground( d.key, "", "admin:" & variables.b.adminAuth.currentEmail() );
        flash( "success", "Import of #d.label# started. Refresh to follow its progress." );
        return redirect( "/admin/imports" );
    }

    /** Downloads the newest official file through an allowlisted connector (no user-supplied URLs). */
    public struct function fetch( required struct rc ) {
        var d = variables.b.importRunner.dataset( arguments.rc.dataset ?: "" );
        var options = {};
        if ( d.key == "scorecard" && len( trim( arguments.rc.places ?: "" ) ) ) options.places = left( trim( arguments.rc.places ), 400 );
        try {
            var res = variables.b.importConnectors.fetch( d.key, options );
            flash( res.ok ? "success" : "warning", res.message & ( res.ok ? ". Review it below, then select Import." : "" ) );
        } catch ( Validation e ) {
            flash( "warning", e.message );
        }
        return redirect( "/admin/imports" );
    }

    /** Stores an uploaded file under the dataset's expected name pattern, then shows a preview before commit. */
    public struct function upload( required struct rc ) {
        var d = variables.b.importRunner.dataset( arguments.rc.dataset ?: "" );
        var raw = variables.b.config.importRawPath;
        var work = variables.b.config.importWorkPath & "upload/";
        if ( !directoryExists( work ) ) directoryCreate( work, true );
        var up = fileUpload( work, "file", "", "makeUnique" );
        var tmp = up.serverDirectory & "/" & up.serverFile;
        try {
            var ext = lCase( up.serverFileExt );
            if ( !structKeyExists( variables.uploadExtensions, ext ) || ( d.upload != ext && !( d.upload == "zip" && ext == "zip" ) ) ) {
                throw( type = "Validation", message = "#d.label# expects a .#d.upload# file." );
            }
            if ( up.fileSize > variables.b.config.uploadMaxBytes ) throw( type = "Validation", message = "That file is larger than 200 MB." );
            var name = reReplace( up.clientFile, "[^A-Za-z0-9._-]", "_", "all" );
            var target = "";
            if ( d.kind == "dir" ) {
                if ( !directoryExists( raw & "scorecard/" ) ) directoryCreate( raw & "scorecard/", true );
                target = raw & "scorecard/" & name;
            } else {
                if ( !reFindNoCase( d.accept ?: d.pattern, name ) ) throw( type = "Validation", message = "File name '#name#' doesn't match the expected pattern for #d.label# (#d.description#). Rename it and try again." );
                target = raw & name;
            }
            fileMove( tmp, target );
            var preview = previewFile( d, target );
            return view( "admin/preview", { title: "Preview upload", dataset: d, fileName: name, preview: preview }, "admin" );
        } catch ( Validation e ) {
            if ( fileExists( tmp ) ) fileDelete( tmp );
            flash( "warning", e.message );
            return redirect( "/admin/imports" );
        }
    }

    /** Commit an uploaded/previewed file. */
    public struct function preview( required struct rc ) {
        return runImport( arguments.rc );
    }

    // ------------------------------------------------------------------ helpers

    private struct function previewFile( required struct d, required string path ) {
        var rows = [];
        var ext = lCase( listLast( arguments.path, "." ) );
        try {
            if ( ext == "xlsx" ) {
                new modules.imports.XlsxStreamReader().eachRow( arguments.path, 1, function( cells, n ) {
                    arrayAppend( rows, cells );
                    return arrayLen( rows ) < 8;
                } );
            } else if ( ext == "dat" ) {
                var lines = 0;
                new modules.imports.BaseImporter( variables.b.importRunner, variables.b.logger ).eachLine( arguments.path, function( line, n ) {
                    arrayAppend( rows, listToArray( left( line, 400 ), "|", true ) );
                    return arrayLen( rows ) < 6;
                } );
            } else if ( ext == "zip" ) {
                var zip = createObject( "java", "java.util.zip.ZipFile" ).init( arguments.path );
                try {
                    var entries = zip.entries();
                    while ( entries.hasMoreElements() ) {
                        var en = entries.nextElement();
                        arrayAppend( rows, [ en.getName(), numberFormat( en.getSize(), "," ) & " bytes" ] );
                    }
                } finally { zip.close(); }
            } else if ( ext == "json" ) {
                var doc = deserializeJSON( fileRead( arguments.path, "utf-8" ) );
                for ( var s in ( doc.results ?: [] ) ) {
                    arrayAppend( rows, [ s.id ?: "", s[ "school.name" ] ?: "", s[ "school.city" ] ?: "", s[ "school.state" ] ?: "" ] );
                    if ( arrayLen( rows ) >= 10 ) break;
                }
            }
        } catch ( any e ) {
            return { ok: false, message: "We couldn't read that file: " & e.message, rows: [] };
        }
        return { ok: true, message: "", rows: rows };
    }

    private string function safeNext( string next = "" ) {
        return reFind( "^/admin(/[a-z0-9/_\-]*)?$", arguments.next ) ? arguments.next : "/admin/imports";
    }

}
