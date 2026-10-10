/**
 * Password hashing with Argon2id (BouncyCastle via Lucee Maven integration).
 * Hashes use the standard PHC string format: $argon2id$v=19$m=19456,t=2,p=1$<salt>$<hash>
 * Never log or return hashes.
 */
component {

    variables.memoryKiB = 19456; // OWASP baseline: 19 MiB, 2 iterations, 1 lane
    variables.iterations = 2;
    variables.parallelism = 1;
    variables.hashLength = 32;
    variables.saltLength = 16;
    variables.minLength = 10;
    variables.maxLength = 200;

    public string function hashPassword( required string password ) {
        var salt = randomBytes( variables.saltLength );
        var digest = argon2( arguments.password, salt, variables.memoryKiB, variables.iterations, variables.parallelism, variables.hashLength );
        return "$argon2id$v=19$m=#variables.memoryKiB#,t=#variables.iterations#,p=#variables.parallelism#$" & b64( salt ) & "$" & b64( digest );
    }

    public boolean function verify( required string password, required string passwordHash ) {
        // $argon2id$v=19$m=19456,t=2,p=1$salt$hash
        var parts = listToArray( arguments.passwordHash, "$" );
        if ( arrayLen( parts ) != 5 || parts[ 1 ] != "argon2id" ) {
            // Burn comparable time so unknown accounts are not distinguishable by timing.
            hashPassword( arguments.password );
            return false;
        }
        try {
            var p = {};
            for ( var kv in listToArray( parts[ 3 ], "," ) ) p[ listFirst( kv, "=" ) ] = val( listLast( kv, "=" ) );
            var decoder = createObject( "java", "java.util.Base64" ).getDecoder();
            var salt = decoder.decode( parts[ 4 ] );
            var expected = decoder.decode( parts[ 5 ] );
            var actual = argon2( arguments.password, salt, p.m, p.t, p.p, arrayLen( expected ) );
            return createObject( "java", "java.security.MessageDigest" ).isEqual( expected, actual );
        } catch ( any e ) {
            return false;
        }
    }

    /** Returns an error message, or "" when acceptable. */
    public string function strengthError( required string password ) {
        if ( len( arguments.password ) < variables.minLength ) return "Password must be at least #variables.minLength# characters.";
        if ( len( arguments.password ) > variables.maxLength ) return "Password must be #variables.maxLength# characters or fewer.";
        return "";
    }

    public string function temporaryPassword() {
        var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
        var rnd = createObject( "java", "java.security.SecureRandom" ).init();
        var out = "";
        for ( var i = 1; i <= 14; i++ ) {
            out &= mid( alphabet, rnd.nextInt( len( alphabet ) ) + 1, 1 );
        }
        return out;
    }

    private any function argon2( required string password, required any salt, required numeric memory, required numeric iterations, required numeric parallelism, required numeric length ) {
        var paramsClass = createObject( "java", "org.bouncycastle.crypto.params.Argon2Parameters" );
        var params = createObject( "java", "org.bouncycastle.crypto.params.Argon2Parameters$Builder" )
            .init( paramsClass.ARGON2_id )
            .withVersion( paramsClass.ARGON2_VERSION_13 )
            .withIterations( javacast( "int", arguments.iterations ) )
            .withMemoryAsKB( javacast( "int", arguments.memory ) )
            .withParallelism( javacast( "int", arguments.parallelism ) )
            .withSalt( arguments.salt )
            .build();
        var generator = createObject( "java", "org.bouncycastle.crypto.generators.Argon2BytesGenerator" ).init();
        generator.init( params );
        var out = createObject( "java", "java.nio.ByteBuffer" ).allocate( javacast( "int", arguments.length ) ).array();
        generator.generateBytes( charsetDecode( arguments.password, "utf-8" ), out );
        return out;
    }

    private any function randomBytes( required numeric count ) {
        var bytes = createObject( "java", "java.nio.ByteBuffer" ).allocate( javacast( "int", arguments.count ) ).array();
        createObject( "java", "java.security.SecureRandom" ).init().nextBytes( bytes );
        return bytes;
    }

    private string function b64( required any bytes ) {
        return createObject( "java", "java.util.Base64" ).getEncoder().withoutPadding().encodeToString( arguments.bytes );
    }

}
