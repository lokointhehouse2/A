/**
 * Allowlisted download connectors. Only the fixed official URL templates below can be fetched; admins can never
 * supply an arbitrary URL. Downloads land in storage/imports/raw and are imported by ImportRunner like uploads.
 */
component {

    variables.allowedHosts = "www.bls.gov,nces.ed.gov,www.huduser.gov,www2.census.gov,api.data.gov";

    public ImportConnectors function init( required any config, required any logger ) {
        variables.config = arguments.config;
        variables.logger = arguments.logger;
        return this;
    }

    /** Downloads the newest available file for a dataset. Returns { ok, files:[], message }. */
    public struct function fetch( required string datasetKey, struct options = {} ) {
        var y = year( now() );
        switch ( arguments.datasetKey ) {
            case "oews_metro":
            case "oews_national":
                requireBlsContact();
                var suffix = arguments.datasetKey == "oews_metro" ? "ma" : "nat";
                return firstAvailable( [ y - 1, y - 2 ].map( function( yr ) {
                    var yy = right( yr, 2 );
                    return { url: "https://www.bls.gov/oes/special-requests/oesm#yy##suffix#.zip", file: "oesm#yy##suffix#.zip", kind: "zip", bls: true };
                } ) );
            case "bls_ep":
                requireBlsContact();
                var a = download( "https://www.bls.gov/emp/ind-occ-matrix/education.xlsx", "ep_education.xlsx", "zip", true );
                if ( !a.ok ) return a;
                var b = download( "https://www.bls.gov/emp/ind-occ-matrix/occupation.xlsx", "ep_occupation.xlsx", "zip", true );
                return { ok: b.ok, files: a.files.append( b.files, true ), message: b.ok ? "Downloaded" : b.message };
            case "cip_soc":
                return download( "https://nces.ed.gov/ipeds/cipcode/Files/CIP2020_SOC2018_Crosswalk.xlsx", "CIP2020_SOC2018_Crosswalk.xlsx", "zip", false );
            case "hud_fmr":
                // HUD fiscal years start October 1; try the current FY first.
                var fy = month( now() ) >= 10 ? y + 1 : y;
                return firstAvailable( [ fy, fy - 1 ].map( function( f ) {
                    return { url: "https://www.huduser.gov/portal/datasets/fmr/fmr#f#/FY#right( f, 2 )#_FMRs.xlsx", file: "FY#right( f, 2 )#_FMRs.xlsx", kind: "zip", bls: false };
                } ) );
            case "acs_rent":
            case "acs_home_value":
                var table = arguments.datasetKey == "acs_rent" ? "b25031" : "b25077";
                return firstAvailable( [ y - 1, y - 2, y - 3 ].map( function( yr ) {
                    return { url: "https://www2.census.gov/programs-surveys/acs/summary_file/#yr#/table-based-SF/data/5YRData/acsdt5y#yr#-#table#.dat", file: "acsdt5y#yr#-#table#.dat", kind: "text", bls: false };
                } ) );
            case "scorecard":
                return fetchScorecard( arguments.options.places ?: "Orlando|FL;New York|NY;Washington|DC" );
        }
        throw( type = "Validation", message = "No download connector exists for that dataset." );
    }

    // ------------------------------------------------------------------ Scorecard API

    private struct function fetchScorecard( required string places ) {
        var key = len( variables.config.scorecardApiKey ) ? variables.config.scorecardApiKey : "DEMO_KEY";
        var fields = "id,school.name,school.city,school.state,school.school_url,school.ownership,school.degrees_awarded.predominant,location.lat,location.lon,"
            & "latest.student.size,latest.cost.tuition.in_state,latest.cost.tuition.out_of_state,latest.cost.attendance.academic_year,latest.cost.avg_net_price.overall,"
            & "latest.completion.rate_suppressed.overall,latest.student.retention_rate.four_year.full_time,latest.aid.median_debt.completers.overall,latest.programs.cip_4_digit";
        var dir = variables.config.importRawPath & "scorecard/";
        if ( !directoryExists( dir ) ) directoryCreate( dir );
        var files = [];
        for ( var place in listToArray( arguments.places, ";" ) ) {
            var city = trim( listFirst( place, "|" ) );
            var st = uCase( trim( listLast( place, "|" ) ) );
            if ( !reFind( "^[A-Za-z .'\-]{2,60}$", city ) || !reFind( "^[A-Z]{2}$", st ) ) throw( type = "Validation", message = "Places must look like City|ST; separated by semicolons." );
            var slug = lCase( reReplace( city, "[^A-Za-z]+", "_", "all" ) ) & "_" & lCase( st );
            for ( var page = 0; page < 5; page++ ) {
                var u = "https://api.data.gov/ed/collegescorecard/v1/schools.json?api_key=#encodeForURL( key )#&school.city=#encodeForURL( city )#&school.state=#st#"
                    & "&school.operating=1&latest.student.size__range=1000..&per_page=50&page=#page#&fields=#fields#";
                var res = httpGet( u, false );
                if ( res.status != 200 ) return { ok: false, files: files, message: "Scorecard API returned HTTP #res.status# for #city#, #st#" & ( key == "DEMO_KEY" ? " (DEMO_KEY is rate-limited; add COLLEGE_SCORECARD_API_KEY)" : "" ) };
                var doc = deserializeJSON( res.body );
                if ( !arrayLen( doc.results ?: [] ) ) break;
                var name = "#slug#_p#page#.json";
                fileWrite( dir & name, res.body, "utf-8" );
                arrayAppend( files, name );
                if ( ( page + 1 ) * 50 >= ( doc.metadata.total ?: 0 ) ) break;
            }
        }
        return { ok: true, files: files, message: "Saved #arrayLen( files )# Scorecard page(s)" & ( key == "DEMO_KEY" ? " using the rate-limited DEMO_KEY" : "" ) };
    }

    // ------------------------------------------------------------------ helpers

    private struct function firstAvailable( required array candidates ) {
        var last = { ok: false, files: [], message: "No published file was found." };
        for ( var c in arguments.candidates ) {
            last = download( c.url, c.file, c.kind, c.bls );
            if ( last.ok ) return last;
        }
        return last;
    }

    private struct function download( required string urlValue, required string fileName, required string kind, required boolean bls ) {
        var res = httpGet( arguments.urlValue, arguments.bls, true );
        if ( res.status != 200 ) return { ok: false, files: [], message: "HTTP #res.status# from #arguments.urlValue#" };
        var bytes = res.body;
        if ( !isBinary( bytes ) ) bytes = charsetDecode( bytes, "utf-8" );
        // Zip-based formats (.zip, .xlsx) must start with "PK"; this rejects HTML error pages served with HTTP 200.
        var head = left( charsetEncode( bytes, "ISO-8859-1" ), 16 );
        if ( arguments.kind == "zip" && left( head, 2 ) != "PK" ) {
            return { ok: false, files: [], message: "The server did not return the expected file (it may be blocking automated downloads)." };
        }
        if ( arguments.kind == "text" && ( len( bytes ) < 100 || findNoCase( "<html", head ) ) ) return { ok: false, files: [], message: "Downloaded file was empty or an error page." };
        var raw = variables.config.importRawPath;
        if ( !directoryExists( raw ) ) directoryCreate( raw );
        fileWrite( raw & arguments.fileName, bytes );
        variables.logger.info( "Downloaded #arguments.fileName# (#len( bytes )# bytes)" );
        return { ok: true, files: [ arguments.fileName ], message: "Downloaded #arguments.fileName#" };
    }

    private struct function httpGet( required string urlValue, boolean bls = false, boolean binary = false ) {
        var hm = reFind( "^https://([^/]+)/", arguments.urlValue, 1, true );
        var host = hm.pos[ 1 ] ? mid( arguments.urlValue, hm.pos[ 2 ], hm.len[ 2 ] ) : "";
        if ( !listFindNoCase( variables.allowedHosts, host ) ) throw( type = "Validation", message = "Host #host# is not an allowlisted data source." );
        var ua = arguments.bls
            ? "FuturePath-import/0.1 (educational data import; contact: #variables.config.blsContactEmail#)"
            : "Mozilla/5.0 (compatible; FuturePath-import/0.1; educational data import)";
        var result = {};
        cfhttp( url = arguments.urlValue, method = "GET", result = "result", timeout = 600, userAgent = ua, getAsBinary = arguments.binary ? "yes" : "auto", redirect = true, throwOnError = false );
        return { status: val( result.status_code ?: 0 ), body: result.fileContent ?: "" };
    }

    private void function requireBlsContact() {
        if ( !len( variables.config.blsContactEmail ) ) {
            throw( type = "Validation", message = "BLS only allows automated downloads that identify a contact email. Set BLS_CONTACT_EMAIL in .env, or download the file in a browser and upload it." );
        }
    }

}
