/**
 * Development-only helpers (route is 404 unless APP_ENV=development).
 * GET /dev/tests            run the TestBox suite (text report)
 */
component extends="BaseController" {

    public struct function tests( required struct rc ) {
        if ( !directoryExists( expandPath( "/testbox" ) ) ) {
            return { type: "text", body: "TestBox is not installed. Run: box install --dev   (installs testbox/ in the project root)", mime: "text/plain; charset=utf-8" };
        }
        var bundles = len( arguments.rc.bundle ?: "" ) && reFind( "^[A-Za-z]+$", arguments.rc.bundle ) ? "tests.specs." & arguments.rc.bundle : "";
        var tb = len( bundles ) ? new testbox.system.TestBox( bundles = bundles ) : new testbox.system.TestBox( directory = { mapping: "tests.specs", recurse: true } );
        return { type: "text", body: tb.run( reporter = "text" ), mime: "text/plain; charset=utf-8" };
    }


    public struct function uiTests( required struct rc ) {
        var html = '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>FuturePath UI tests</title></head><body>'
            & '<h1>FuturePath UI tests</h1><pre id="results"></pre>'
            & '<iframe id="desk" title="Builder desktop" src="/builder" width="1400" height="900"></iframe>'
            & '<iframe id="phone" title="Builder phone" src="/builder" width="375" height="800"></iframe>'
            & '<script src="/dev/ui-tests.js"></script></body></html>';
        return { type: "text", body: html, mime: "text/html; charset=utf-8" };
    }

    public struct function uiTestsScript( required struct rc ) {
        return { type: "text", body: fileRead( variables.b.config.rootPath & "tests/js/ui-tests.js", "utf-8" ), mime: "application/javascript; charset=utf-8" };
    }

}
