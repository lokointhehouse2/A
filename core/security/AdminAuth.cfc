/**
 * Admin authentication: Argon2id password hashes, session rotation on login, login throttling.
 */
component {

    variables.dsn = "futurepathDB";

    public AdminAuth function init( required any passwords, required any rateLimiter, required any logger ) {
        variables.passwords = arguments.passwords;
        variables.rateLimiter = arguments.rateLimiter;
        variables.logger = arguments.logger;
        return this;
    }

    /** Creates the first admin from ADMIN_INITIAL_EMAIL / ADMIN_INITIAL_PASSWORD when no admin exists. */
    public void function ensureInitialAdmin( required string email, required string password ) {
        var count = queryExecute( "SELECT COUNT(*) AS n FROM admin_users", {}, { datasource: variables.dsn } ).n;
        if ( count > 0 ) return;
        if ( !len( arguments.email ) || !len( arguments.password ) ) {
            variables.logger.warn( "No admin user exists. Set ADMIN_INITIAL_EMAIL and ADMIN_INITIAL_PASSWORD in .env to create one." );
            return;
        }
        if ( len( variables.passwords.strengthError( arguments.password ) ) ) {
            variables.logger.warn( "ADMIN_INITIAL_PASSWORD is too short (minimum 10 characters); admin not created." );
            return;
        }
        queryExecute( "INSERT INTO admin_users (email, password_hash, role) VALUES (:email, :hash, 'admin')", {
            email: { value: lCase( trim( arguments.email ) ), cfsqltype: "varchar" },
            hash: { value: variables.passwords.hashPassword( arguments.password ), cfsqltype: "varchar" }
        }, { datasource: variables.dsn } );
        variables.logger.info( "Initial admin user created." );
    }

    /** Returns "" on success or a user-facing error message. */
    public string function login( required string email, required string password, required string clientIp ) {
        if ( !variables.rateLimiter.allow( "login:" & arguments.clientIp, 10 ) ) {
            return "Too many sign-in attempts. Please wait a minute and try again.";
        }
        var rows = queryExecute( "SELECT id, email, password_hash, role FROM admin_users WHERE email = :email", {
            email: { value: lCase( trim( arguments.email ) ), cfsqltype: "varchar" }
        }, { datasource: variables.dsn, returntype: "array" } );
        var hashValue = arrayLen( rows ) ? rows[ 1 ].password_hash : "";
        if ( !variables.passwords.verify( arguments.password, hashValue ) || !arrayLen( rows ) ) {
            return "That email and password combination didn't work.";
        }
        sessionRotate();
        session.admin = { id: rows[ 1 ].id, email: rows[ 1 ].email, role: rows[ 1 ].role, at: now() };
        queryExecute( "UPDATE admin_users SET last_login_at = UTC_TIMESTAMP() WHERE id = :id", { id: { value: rows[ 1 ].id, cfsqltype: "integer" } }, { datasource: variables.dsn } );
        return "";
    }

    public void function logout() {
        structDelete( session, "admin" );
        sessionRotate();
    }

    public boolean function isAuthenticated() {
        return structKeyExists( session, "admin" ) && isStruct( session.admin ) && val( session.admin.id ?: 0 ) > 0;
    }

    public string function currentEmail() {
        return isAuthenticated() ? session.admin.email : "";
    }

}
