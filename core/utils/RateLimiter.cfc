/**
 * In-memory fixed-window rate limiter (per key, per minute). Good enough for a single Lucee node;
 * put a shared limiter (reverse proxy or Redis) in front of a multi-node production deployment.
 */
component {

    public RateLimiter function init( required numeric perMinute ) {
        variables.perMinute = arguments.perMinute;
        variables.buckets = createObject( "java", "java.util.concurrent.ConcurrentHashMap" ).init();
        return this;
    }

    public boolean function allow( required string key, numeric limit = variables.perMinute ) {
        var window = int( getTickCount() / 60000 );
        var bucketKey = arguments.key & "|" & window;
        var counter = variables.buckets.get( bucketKey );
        if ( isNull( counter ) ) {
            variables.buckets.putIfAbsent( bucketKey, createObject( "java", "java.util.concurrent.atomic.AtomicInteger" ).init( 0 ) );
            counter = variables.buckets.get( bucketKey );
        }
        var count = counter.incrementAndGet();
        if ( variables.buckets.size() > 20000 ) prune( window );
        return count <= arguments.limit;
    }

    private void function prune( required numeric window ) {
        var it = variables.buckets.keySet().iterator();
        while ( it.hasNext() ) {
            var k = it.next();
            if ( val( listLast( k, "|" ) ) < arguments.window ) it.remove();
        }
    }

}
