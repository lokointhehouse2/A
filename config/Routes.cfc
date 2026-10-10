/**
 * Front-controller route table.
 *   api:   JSON responses (typed errors, rate limiting)
 *   admin: requires an authenticated admin session
 *   dev:   only available when APP_ENV=development
 * Path parameters are validated by type-specific patterns before any controller runs.
 */
component {

    variables.table = [];
    variables.paramPatterns = {
        soc: "([0-9]{2}-[0-9]{4})",
        cip: "([0-9]{2}(?:\.[0-9]{2}(?:[0-9]{2})?)?)",
        unitid: "([0-9]{3,9})",
        cbsa: "([0-9]{5})",
        id: "([0-9]{1,18})",
        uuid: "([0-9a-fA-F\-]{36})",
        key: "([a-z0-9_\-]{1,60})"
    };

    public Routes function init() {
        // Pages
        add( "GET", "/", "pages", "home" );
        add( "GET", "/builder", "pages", "builder" );
        add( "GET", "/careers", "pages", "careers" );
        add( "GET", "/careers/{soc}", "pages", "career" );
        add( "GET", "/colleges", "pages", "colleges" );
        add( "GET", "/colleges/{unitid}", "pages", "college" );
        add( "GET", "/about", "pages", "about" );
        add( "GET", "/sources", "pages", "sources" );
        add( "GET", "/privacy", "pages", "privacy" );
        add( "GET", "/s/{uuid}", "pages", "sharedScenario" );

        // Public JSON API v1
        add( "GET", "/api/health", "apiSources", "health", { api: true } );
        add( "GET", "/api/v1/geographies", "apiGeo", "search", { api: true } );
        add( "GET", "/api/v1/geographies/{cbsa}", "apiGeo", "detail", { api: true } );
        add( "GET", "/api/v1/occupations", "apiCareers", "search", { api: true } );
        add( "GET", "/api/v1/occupations/{soc}", "apiCareers", "detail", { api: true } );
        add( "GET", "/api/v1/occupations/{soc}/wages", "apiCareers", "wages", { api: true } );
        add( "GET", "/api/v1/occupations/{soc}/pathways", "apiCareers", "pathways", { api: true } );
        add( "GET", "/api/v1/occupations/{soc}/programs", "apiCareers", "programs", { api: true } );
        add( "GET", "/api/v1/institutions", "apiEducation", "searchInstitutions", { api: true } );
        add( "GET", "/api/v1/institutions/{unitid}", "apiEducation", "institution", { api: true } );
        add( "GET", "/api/v1/institutions/{unitid}/programs", "apiEducation", "institutionPrograms", { api: true } );
        add( "GET", "/api/v1/programs", "apiEducation", "searchPrograms", { api: true } );
        add( "GET", "/api/v1/programs/{cip}/careers", "apiEducation", "programCareers", { api: true } );
        add( "GET", "/api/v1/pathways", "apiEducation", "pathways", { api: true } );
        add( "GET", "/api/v1/reference/bundle", "apiSimulations", "referenceBundle", { api: true } );
        add( "POST", "/api/v1/simulations/calculate", "apiSimulations", "calculate", { api: true } );
        add( "POST", "/api/v1/simulations/reverse-careers", "apiSimulations", "reverseCareers", { api: true } );
        add( "POST", "/api/v1/simulations/compare", "apiSimulations", "compare", { api: true } );
        add( "POST", "/api/v1/scenarios", "apiSimulations", "saveScenario", { api: true } );
        add( "GET", "/api/v1/scenarios/{uuid}", "apiSimulations", "getScenario", { api: true } );
        add( "GET", "/api/v1/sources/status", "apiSources", "status", { api: true } );

        // Admin (protected)
        add( "GET", "/admin", "admin", "index", { admin: true } );
        add( "GET", "/admin/login", "admin", "loginForm" );
        add( "POST", "/admin/login", "admin", "login" );
        add( "POST", "/admin/logout", "admin", "logout", { admin: true } );
        add( "GET", "/admin/imports", "admin", "imports", { admin: true } );
        add( "POST", "/admin/imports", "admin", "runImport", { admin: true } );
        add( "POST", "/admin/imports/upload", "admin", "upload", { admin: true } );
        add( "POST", "/admin/imports/preview", "admin", "preview", { admin: true } );
        add( "POST", "/admin/imports/fetch", "admin", "fetch", { admin: true } );
        add( "GET", "/admin/imports/{id}", "admin", "importRun", { admin: true } );

        // Development only
        add( "GET", "/dev/tests", "dev", "tests", { dev: true } );
        add( "GET", "/dev/ui-tests", "dev", "uiTests", { dev: true } );
        add( "GET", "/dev/ui-tests.js", "dev", "uiTestsScript", { dev: true } );
        return this;
    }

    public string function normalize( string path = "" ) {
        var p = reReplace( arguments.path, "/{2,}", "/", "all" );
        p = reReplace( p, "(?i)^/index\.cfm", "" );
        if ( !len( p ) ) p = "/";
        if ( len( p ) > 1 ) p = reReplace( p, "/+$", "" );
        return p;
    }

    /** Returns { found, methodAllowed, route, params }. */
    public struct function match( required string path, required string method ) {
        var result = { found: false, methodAllowed: true, route: {}, params: {} };
        var pathMatched = false;
        for ( var r in variables.table ) {
            var m = reFind( r.regex, arguments.path, 1, true );
            if ( m.pos[ 1 ] == 0 ) continue;
            pathMatched = true;
            if ( r.method != uCase( arguments.method ) && !( r.method == "GET" && uCase( arguments.method ) == "HEAD" ) ) continue;
            result.found = true;
            result.route = r;
            for ( var i = 1; i <= arrayLen( r.paramNames ); i++ ) {
                result.params[ r.paramNames[ i ] ] = mid( arguments.path, m.pos[ i + 1 ], m.len[ i + 1 ] );
            }
            return result;
        }
        result.methodAllowed = !pathMatched;
        return result;
    }

    private void function add( required string method, required string pattern, required string controller, required string action, struct options = {} ) {
        var names = [];
        var regex = "";
        for ( var part in listToArray( arguments.pattern, "/" ) ) {
            if ( reFind( "^\{[a-zA-Z]+\}$", part ) ) {
                var name = mid( part, 2, len( part ) - 2 );
                arrayAppend( names, name );
                regex &= "/" & ( variables.paramPatterns[ name ] ?: "([a-z0-9\-]+)" );
            } else {
                regex &= "/" & part; // static segments are plain [a-z0-9-]
            }
        }
        if ( !len( regex ) ) regex = "/";
        arrayAppend( variables.table, {
            method: uCase( arguments.method ),
            pattern: arguments.pattern,
            regex: "^" & regex & "$",
            paramNames: names,
            controller: arguments.controller,
            action: arguments.action,
            api: arguments.options.api ?: false,
            admin: arguments.options.admin ?: false,
            dev: arguments.options.dev ?: false
        } );
    }

}
