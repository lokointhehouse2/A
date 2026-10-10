<cfscript>
/**
 * Front controller. Every request outside /assets is rewritten here by server.json rules.
 * Order: route -> dev gate -> API rate limit / JSON POST guard -> admin auth -> CSRF (admin forms) -> controller -> render.
 */
b = application.beans;
path = b.routes.normalize( cgi.path_info );
method = uCase( cgi.request_method );
isApi = reFindNoCase( "^/api(/|$)", path ) > 0;
match = b.routes.match( path, method );
request.path = path;

if ( !match.found ) {
    status = match.methodAllowed ? 404 : 405;
    if ( isApi ) b.json.send( b.json.fail( status == 404 ? "Not found." : "Method not allowed.", {}, status == 404 ? "not_found" : "method_not_allowed" ), status );
    getPageContext().getResponse().setStatus( status );
    request.errorStatus = status;
    include "/views/errors/error.cfm";
    abort;
}

route = match.route;
request.route = route;

if ( route.dev && !application.config.isDev ) {
    getPageContext().getResponse().setStatus( 404 );
    request.errorStatus = 404;
    include "/views/errors/error.cfm";
    abort;
}

rc = {};
structAppend( rc, url, true );
structAppend( rc, form, true );
structAppend( rc, match.params, true );
headers = getHttpRequestData( false ).headers;

// ---- public JSON API: per-client rate limit, JSON body + same-origin for POST
if ( route.api ) {
    if ( !b.rateLimiter.allow( "api:" & cgi.remote_addr ) ) {
        cfheader( name = "Retry-After", value = "60" );
        b.json.send( b.json.fail( "Too many requests. Please wait a minute and try again.", {}, "rate_limited" ), 429 );
    }
    if ( method == "POST" ) {
        contentType = lCase( headers[ "Content-Type" ] ?: "" );
        if ( !find( "application/json", contentType ) ) {
            b.json.send( b.json.fail( "Send a JSON body with Content-Type: application/json.", {}, "unsupported_media_type" ), 415 );
        }
        if ( !b.originGuard.isSameOrigin( headers ) ) {
            b.json.send( b.json.fail( "Cross-origin requests are not allowed.", {}, "forbidden_origin" ), 403 );
        }
        rawBody = toString( getHttpRequestData( true ).content ?: "" );
        if ( len( rawBody ) > 200000 ) b.json.send( b.json.fail( "Request body is too large.", {}, "payload_too_large" ), 413 );
        if ( !len( trim( rawBody ) ) || !isJSON( rawBody ) ) b.json.send( b.json.fail( "The request body must be valid JSON.", {}, "invalid_json" ), 400 );
        rc.body = deserializeJSON( rawBody );
        if ( !isStruct( rc.body ) ) b.json.send( b.json.fail( "The request body must be a JSON object.", {}, "invalid_json" ), 400 );
    }
}

// ---- admin: authenticated session + CSRF on every state-changing form post
if ( route.admin && !b.adminAuth.isAuthenticated() ) {
    location( url = "/admin/login?next=" & encodeForURL( path ), addToken = false );
}
if ( method == "POST" && !route.api ) {
    csrfCandidate = rc._csrf ?: ( headers[ "X-CSRF-Token" ] ?: "" );
    if ( !b.csrf.verify( csrfCandidate ) ) {
        b.logger.warn( "CSRF validation failed for #path#" );
        session.flash = { type: "warning", message: "Your session expired. Please try again." };
        location( url = path, addToken = false, statusCode = 303 );
    }
}

// ---- dispatch
try {
    response = invoke( b.controllers[ route.controller ], route.action, { rc: rc } );
} catch ( any e ) {
    if ( e.type == "NotFound" ) {
        if ( route.api ) b.json.send( b.json.fail( e.message, {}, "not_found" ), 404 );
        getPageContext().getResponse().setStatus( 404 );
        request.errorStatus = 404;
        request.errorMessage = e.message;
        include "/views/errors/error.cfm";
        abort;
    }
    if ( e.type == "Validation" ) {
        fields = isJSON( e.extendedInfo ?: "" ) ? deserializeJSON( e.extendedInfo ) : {};
        if ( route.api ) b.json.send( b.json.fail( e.message, fields, "validation_failed" ), 422 );
        getPageContext().getResponse().setStatus( 422 );
        request.errorStatus = 422;
        request.errorMessage = e.message;
        include "/views/errors/error.cfm";
        abort;
    }
    rethrow;
}

// ---- render
switch ( response.type ) {
    case "redirect":
        location( url = response.url, addToken = false, statusCode = method == "POST" ? 303 : 302 );
        break;
    case "json":
        b.json.send( response.payload, response.status ?: 200 );
        break;
    case "text":
        cfcontent( type = response.mime ?: "text/plain; charset=utf-8", reset = true );
        writeOutput( response.body );
        break;
    default:
        vm = response.data;
        h = b.viewHelper;
        if ( !isNull( response.status ) ) getPageContext().getResponse().setStatus( response.status );
        savecontent variable="body" {
            include "/views/#response.view#.cfm";
        }
        include "/views/layouts/#response.layout ?: 'main'#.cfm";
}
</cfscript>
