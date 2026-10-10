/**
 * Typed application configuration built from Env. Secrets stay here and are never rendered.
 */
component {

    public AppConfig function init( required any env, required string rootPath ) {
        this.rootPath = arguments.rootPath;
        this.appName = "FuturePath";
        this.appEnv = lCase( arguments.env.get( "APP_ENV", "production" ) );
        this.isDev = this.appEnv == "development";
        this.appPort = arguments.env.integer( "APP_PORT", 42005 );
        this.baseUrl = reReplace( arguments.env.get( "APP_BASE_URL", "http://127.0.0.1:42005" ), "/+$", "" );
        this.dbAutoMigrate = this.isDev || arguments.env.bool( "DB_AUTO_MIGRATE", false );
        this.appSecret = arguments.env.get( "APP_SECRET", "" );

        var storage = arguments.env.get( "IMPORT_STORAGE_PATH", "./storage/imports" );
        if ( left( storage, 2 ) == "./" ) storage = arguments.rootPath & mid( storage, 3, len( storage ) );
        this.importStoragePath = reReplace( replace( storage, "\", "/", "all" ), "/+$", "" ) & "/";
        this.importRawPath = this.importStoragePath & "raw/";
        this.importWorkPath = this.importStoragePath & "work/";
        this.importAutoBootstrap = this.isDev && arguments.env.bool( "IMPORT_AUTO_BOOTSTRAP", true );
        this.importAutoDownload = this.importAutoBootstrap && arguments.env.bool( "IMPORT_AUTO_DOWNLOAD", true );
        this.uploadMaxBytes = 200 * 1024 * 1024;

        this.scorecardApiKey = arguments.env.get( "COLLEGE_SCORECARD_API_KEY", "" );
        this.censusApiKey = arguments.env.get( "CENSUS_API_KEY", "" );
        this.blsContactEmail = arguments.env.get( "BLS_CONTACT_EMAIL", "" );

        this.adminInitialEmail = arguments.env.get( "ADMIN_INITIAL_EMAIL", "" );
        this.adminInitialPassword = arguments.env.get( "ADMIN_INITIAL_PASSWORD", "" );

        this.apiRateLimitPerMinute = max( 10, arguments.env.integer( "API_RATE_LIMIT_PER_MINUTE", 120 ) );

        // Calculation engine version: stored with every saved result.
        this.calculationVersion = "2026.1";
        this.defaultTaxYear = 2026;

        // Featured metros for the landing-page comparison (CBSA codes).
        this.featuredMetros = [ "36740", "35620", "47900" ];

        // Everything is served from this origin; no third-party scripts, fonts, trackers or CDNs.
        this.contentSecurityPolicy = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; "
            & "font-src 'self'; connect-src 'self'; frame-ancestors 'self'; form-action 'self'; base-uri 'self'; object-src 'none'";
        return this;
    }

}
