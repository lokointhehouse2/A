/**
 * FuturePath — application bootstrap: datasource, Maven (Apache POI, BouncyCastle), sessions,
 * migrations + seeds, initial admin, background data bootstrap, security headers, error handling.
 *
 * Full NULL support is on: a database NULL (suppressed / unpublished value) stays null all the way
 * to the JSON API instead of silently becoming "" or 0.
 */
component {

    variables.rootPath = getDirectoryFromPath( getCurrentTemplatePath() );
    variables.env = loadEnv();

    this.name = "FuturePath_" & hash( variables.rootPath );
    this.applicationTimeout = createTimeSpan( 1, 0, 0, 0 );
    this.sessionManagement = true;
    this.sessionTimeout = createTimeSpan( 0, 2, 0, 0 );
    this.sessionStorage = "memory";
    this.setClientCookies = true;
    this.clientManagement = false;
    this.localMode = "modern";
    this.scopeCascading = "standard";
    this.searchImplicitScopes = false;
    this.nullSupport = true;
    this.regex = { type: "java" };
    this.timezone = "UTC";
    this.scriptProtect = "none";
    this.serialization = { preserveCaseForStructKey: true, preserveCaseForQueryColumn: true, serializeQueryAs: "struct" };
    this.sessionCookie = {
        httpOnly: true,
        secure: lCase( left( variables.env.get( "APP_BASE_URL", "http://127.0.0.1:42005" ), 5 ) ) == "https",
        sameSite: "Lax",
        timeout: createTimeSpan( 0, 2, 0, 0 )
    };

    this.mappings = {
        "/core": variables.rootPath & "core",
        "/config": variables.rootPath & "config",
        "/modules": variables.rootPath & "modules",
        "/api": variables.rootPath & "api",
        "/admin": variables.rootPath & "admin",
        "/controllers": variables.rootPath & "controllers",
        "/views": variables.rootPath & "views",
        "/tests": variables.rootPath & "tests",
        "/testbox": variables.rootPath & "testbox"
    };

    this.javaSettings = {
        maven: [
            "org.apache.poi:poi:5.4.1",
            "org.apache.poi:poi-ooxml:5.4.1",
            "org.bouncycastle:bcprov-jdk18on:1.80"
        ],
        loadCFMLClassPath: false,
        reloadOnChange: false
    };

    this.datasources[ "futurepathDB" ] = {
        class: "com.mysql.cj.jdbc.Driver",
        bundleName: "com.mysql.cj",
        connectionString: "jdbc:mysql://" & variables.env.get( "DB_HOST", "127.0.0.1" ) & ":" & variables.env.get( "DB_PORT", "3308" ) & "/" & variables.env.get( "DB_NAME", "futurepath" )
            & "?useUnicode=true&characterEncoding=UTF-8&connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true"
            & "&useSSL=" & ( variables.env.bool( "DB_SSL", false ) ? "true" : "false" )
            & "&allowPublicKeyRetrieval=true&tinyInt1isBit=false&zeroDateTimeBehavior=CONVERT_TO_NULL",
        username: variables.env.get( "DB_USER", "futurepath_app" ),
        password: variables.env.get( "DB_PASSWORD", "" ),
        connectionLimit: 20,
        connectionTimeout: 1,
        liveTimeout: 15,
        validate: true,
        storage: false,
        blob: false,
        clob: true
    };
    this.datasource = "futurepathDB";

    // ------------------------------------------------------------------ lifecycle

    public boolean function onApplicationStart() {
        application.rootPath = variables.rootPath;
        application.env = variables.env;
        application.config = new config.AppConfig( variables.env, variables.rootPath );
        application.beans = new config.Beans().build( application.config );
        application.dbReady = false;
        application.startedAt = now();
        prepareDatabase();
        return true;
    }

    public boolean function onRequestStart( required string targetPage ) {
        if ( structKeyExists( url, "reinit" ) && application.config.isDev ) {
            lock scope="application" type="exclusive" timeout="60" {
                onApplicationStart();
            }
        }
        if ( !application.dbReady ) {
            lock name="futurepath-migrate" type="exclusive" timeout="60" {
                if ( !application.dbReady ) prepareDatabase();
            }
        }
        cfheader( name = "X-Content-Type-Options", value = "nosniff" );
        cfheader( name = "X-Frame-Options", value = "SAMEORIGIN" );
        cfheader( name = "Referrer-Policy", value = "strict-origin-when-cross-origin" );
        cfheader( name = "Permissions-Policy", value = "camera=(), microphone=(), geolocation=(), interest-cohort=()" );
        cfheader( name = "Content-Security-Policy", value = application.config.contentSecurityPolicy );
        return true;
    }

    public void function onMissingTemplate( required string targetPage ) {
        renderError( 404 );
    }

    public void function onError( required any exception, required string eventName ) {
        if ( ( arguments.exception.type ?: "" ) == "lucee.runtime.exp.Abort" ) return;
        var ex = structKeyExists( arguments.exception, "rootCause" ) && isStruct( arguments.exception.rootCause ) ? arguments.exception.rootCause : arguments.exception;
        try {
            if ( isDefined( "application.beans.logger" ) ) {
                application.beans.logger.error( "Unhandled exception on #cgi.request_method# #cgi.script_name##cgi.path_info#", ex );
            }
        } catch ( any ignored ) {}
        request.errorException = ex;
        renderError( 500 );
    }

    // ------------------------------------------------------------------ helpers

    private void function prepareDatabase() {
        var b = application.beans;
        try {
            if ( application.config.dbAutoMigrate ) {
                var applied = b.migrations.migrate( variables.rootPath & "db/migrations" );
                arrayAppend( applied, b.migrations.migrate( variables.rootPath & "db/seeds" ), true );
                if ( arrayLen( applied ) ) b.logger.info( "Applied migrations/seeds: " & arrayToList( applied ) );
            }
            application.dbReady = true;
        } catch ( any e ) {
            b.logger.error( "Startup database migration failed", e );
            return;
        }
        try {
            b.adminAuth.ensureInitialAdmin( application.config.adminInitialEmail, application.config.adminInitialPassword );
        } catch ( any e ) {
            b.logger.error( "Initial admin provisioning failed", e );
        }
        if ( application.config.importAutoBootstrap ) {
            try {
                b.importRunner.bootstrapInBackground();
            } catch ( any e ) {
                b.logger.error( "Data bootstrap could not start", e );
            }
        }
    }

    private void function renderError( required numeric status ) {
        try {
            getPageContext().getResponse().setStatus( arguments.status );
            var path = len( cgi.path_info ) ? cgi.path_info : cgi.script_name;
            if ( reFindNoCase( "^/api(/|$)", path ) ) {
                var json = new core.utils.JsonResponse();
                json.send( json.fail( arguments.status == 404 ? "Not found." : "An unexpected error occurred.", {}, arguments.status == 404 ? "not_found" : "server_error" ), arguments.status );
            }
            cfcontent( type = "text/html; charset=utf-8", reset = true );
            request.errorStatus = arguments.status;
            include "/views/errors/error.cfm";
        } catch ( any e ) {
            writeOutput( arguments.status == 404 ? "Page not found." : "Something went wrong. Please try again." );
        }
    }

    private any function loadEnv() {
        var key = "futurepath_env_" & hash( variables.rootPath );
        if ( !structKeyExists( server, key ) || structKeyExists( url, "reinit" ) ) {
            server[ key ] = new core.utils.Env( variables.rootPath );
        }
        return server[ key ];
    }

}
