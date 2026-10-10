/**
 * Public API validation, rate limiting and admin protection (HTTP against the running dev server).
 */
component extends="testbox.system.BaseSpec" {

    function beforeAll() {
        variables.base = application.config.baseUrl;
    }

    function call( required string path, string method = "GET", string body = "", string contentType = "application/json", struct headers = {} ) {
        var res = {};
        cfhttp( url = variables.base & arguments.path, method = arguments.method, result = "res", redirect = false, throwOnError = false, timeout = 60 ) {
            if ( len( arguments.body ) ) {
                cfhttpparam( type = "header", name = "Content-Type", value = arguments.contentType );
                cfhttpparam( type = "body", value = arguments.body );
            }
            for ( var h in arguments.headers ) cfhttpparam( type = "header", name = h, value = arguments.headers[ h ] );
        }
        return { status: val( res.status_code ), body: res.fileContent, json: isJSON( res.fileContent ) ? deserializeJSON( res.fileContent ) : {}, location: res.responseHeader.Location ?: "" };
    }

    function run() {
        describe( "Public JSON API", function() {
            it( "returns typed validation errors", function() {
                var r = call( "/api/v1/occupations?cbsa=abc" );
                expect( r.status ).toBe( 422 );
                expect( r.json.error.code ).toBe( "validation_failed" );
            } );
            it( "returns 404 for unknown occupations and routes", function() {
                expect( call( "/api/v1/occupations/99-9998/wages" ).status ).toBe( 404 );
                expect( call( "/api/v1/nothing-here" ).json.error.code ).toBe( "not_found" );
            } );
            it( "requires JSON bodies and same-origin browsers for POST", function() {
                expect( call( "/api/v1/simulations/calculate", "POST", "x", "text/plain" ).status ).toBe( 415 );
                expect( call( "/api/v1/simulations/calculate", "POST", "{bad", "application/json" ).status ).toBe( 400 );
                expect( call( "/api/v1/simulations/calculate", "POST", '{"scenario":{"cbsa":"36740"}}', "application/json", { Origin: "https://evil.example" } ).status ).toBe( 403 );
            } );
            it( "calculates a scenario through the endpoint", function() {
                var r = call( "/api/v1/simulations/calculate", "POST", serializeJSON( { scenario: { cbsa: "36740", state: "FL", earners: [ { soc: "47-2031" } ], tiles: [ { type: "apartment", bedrooms: 1 } ] } } ) );
                expect( r.status ).toBe( 200 );
                expect( r.json.data.result.income.earners[ 1 ].status ).toBe( "sourced" );
            } );
            it( "provides sourced local wages with year and definitions", function() {
                var r = call( "/api/v1/occupations/15-1252/wages?cbsa=36740" );
                expect( r.json.data.local.status ).toBe( "available" );
                expect( r.json.data.local.year ).toBeGTE( 2025 );
                expect( r.json.data.definitions ).toHaveKey( "percentileCaveat" );
            } );
        } );

        describe( "Rate limiting", function() {
            it( "blocks requests above the per-minute limit", function() {
                var rl = new core.utils.RateLimiter( 3 );
                var key = "test:" & createUUID();
                expect( rl.allow( key ) ).toBeTrue();
                expect( rl.allow( key ) ).toBeTrue();
                expect( rl.allow( key ) ).toBeTrue();
                expect( rl.allow( key ) ).toBeFalse();
            } );
        } );

        describe( "Admin", function() {
            it( "requires authentication for admin pages", function() {
                var r = call( "/admin/imports" );
                expect( r.status ).toBe( 302 );
                expect( r.location ).toInclude( "/admin/login" );
            } );
            it( "rejects state-changing admin posts without a CSRF token", function() {
                var r = call( "/admin/imports", "POST", "dataset=hud_fmr", "application/x-www-form-urlencoded" );
                expect( r.status ).toBeGTE( 300 );
                expect( r.status ).toBeLT( 400 );
                expect( r.location ).toInclude( "/admin" );
            } );
        } );
    }

}
