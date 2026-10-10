/**
 * SOC occupations: search (with everyday-language aliases), detail, BLS profile and training pathways.
 */
component {

    variables.dsn = "futurepathDB";

    // Everyday words students type -> words used in official SOC titles. Only rewrites search terms;
    // it never changes which occupation a code refers to.
    variables.wordAliases = {
        "professor": "postsecondary", "professors": "postsecondary", "college": "postsecondary",
        "doctor": "physicians", "doctors": "physicians", "physician": "physicians",
        "programmer": "software", "coder": "software", "developer": "developers", "dev": "developers",
        "nurse": "nurses", "teacher": "teachers", "cop": "police", "lawyer": "lawyers",
        "mechanic": "mechanics", "electrician": "electricians", "plumber": "plumbers", "carpenter": "carpenters",
        "chef": "chefs", "cook": "cooks", "vet": "veterinarians", "dentist": "dentists", "pilot": "pilots",
        "firefighter": "firefighters", "engineer": "engineers", "designer": "designers", "artist": "artists",
        "cashier": "cashiers", "accountant": "accountants", "pharmacist": "pharmacists", "therapist": "therapists"
    };
    // Whole phrases that SOC titles never contain, mapped to the codes students usually mean.
    variables.phraseAliases = {
        "english teacher": [ "25-2031", "25-2022", "25-1123" ],
        "high school teacher": [ "25-2031" ],
        "middle school teacher": [ "25-2022" ],
        "elementary teacher": [ "25-2021" ],
        "college professor": [ "25-1123", "25-1022", "25-1071", "25-1081" ],
        "english professor": [ "25-1123" ],
        "fast food": [ "35-3023", "35-1012", "11-9051" ],
        "fast food worker": [ "35-3023" ],
        "restaurant manager": [ "11-9051" ],
        "shift supervisor": [ "35-1012" ],
        "doctor": [ "29-1215", "29-1216", "29-1221", "29-1229" ],
        "software developer": [ "15-1252" ]
    };

    public OccupationService function init( required any strings ) {
        variables.strings = arguments.strings;
        return this;
    }

    /**
     * Detailed occupations matching q. When cbsa is given, each result says whether a local wage is published
     * for that metro (latest OEWS year) so the UI never dead-ends.
     */
    public array function search( string q = "", numeric limit = 12, string cbsa = "", string education = "" ) {
        var term = lCase( trim( reReplace( arguments.q, "[^A-Za-z0-9 ,'\-]", " ", "all" ) ) );
        term = reReplace( replace( term, "-", " ", "all" ), "\s+", " ", "all" );
        var params = { lim: { value: arguments.limit, cfsqltype: "integer" } };
        var where = "o.occupation_group = 'detailed' AND o.active_flag = 1 AND o.soc_code <> '00-0000'";
        var phraseCodes = variables.phraseAliases[ term ] ?: [];
        if ( reFind( "^[0-9]{2}-[0-9]{4}$", term ) ) {
            where &= " AND o.soc_code = :code";
            params.code = { value: term, cfsqltype: "varchar" };
        } else if ( len( term ) ) {
            var clauses = [];
            var i = 0;
            for ( var w in listToArray( term, " " ) ) {
                if ( len( w ) < 2 || listFindNoCase( "a,an,the,of,and,or,worker,workers,job", w ) ) continue;
                i++;
                if ( i > 5 ) break;
                var alias = variables.wordAliases[ w ] ?: w;
                arrayAppend( clauses, "(o.title LIKE :w#i# OR o.title LIKE :a#i#)" );
                params[ "w#i#" ] = { value: "%" & variables.strings.likeEscape( w ) & "%", cfsqltype: "varchar" };
                params[ "a#i#" ] = { value: "%" & variables.strings.likeEscape( alias ) & "%", cfsqltype: "varchar" };
            }
            var textMatch = arrayLen( clauses ) ? arrayToList( clauses, " AND " ) : "1=1";
            if ( arrayLen( phraseCodes ) ) {
                where &= " AND ( (#textMatch#) OR o.soc_code IN (:phrase) )";
                params.phrase = { value: arrayToList( phraseCodes ), cfsqltype: "varchar", list: true };
            } else {
                where &= " AND " & textMatch;
            }
        }
        if ( len( arguments.education ) ) {
            where &= " AND o.education_category = :edu";
            params.edu = { value: arguments.education, cfsqltype: "varchar" };
        }
        var localJoin = "";
        var localCols = ", NULL AS local_median, NULL AS local_status";
        if ( reFind( "^[0-9]{5}$", arguments.cbsa ) ) {
            localJoin = "LEFT JOIN occupational_wages lw ON lw.soc_code = o.soc_code AND lw.area_level = 'metro' AND lw.area_code = :cbsa
                         AND lw.wage_year = (SELECT MAX(wage_year) FROM occupational_wages WHERE area_level = 'metro')";
            localCols = ", lw.annual_median AS local_median, CASE WHEN lw.id IS NULL THEN 'not_published' WHEN lw.annual_median IS NULL THEN 'partial' ELSE 'available' END AS local_status";
            params.cbsa = { value: arguments.cbsa, cfsqltype: "varchar" };
        }
        var phraseOrder = arrayLen( phraseCodes ) ? "CASE WHEN o.soc_code IN (:phrase) THEN 0 ELSE 1 END, " : "";
        var rows = queryExecute( "
            SELECT o.soc_code, o.title, o.education_category, nw.annual_median AS national_median, nw.employment_count AS national_employment #localCols#
            FROM occupations o
            LEFT JOIN occupational_wages nw ON nw.soc_code = o.soc_code AND nw.area_level = 'national'
                 AND nw.wage_year = (SELECT MAX(wage_year) FROM occupational_wages WHERE area_level = 'national')
            #localJoin#
            WHERE #where#
            ORDER BY #phraseOrder# COALESCE(nw.employment_count, 0) DESC, o.title
            LIMIT :lim", params, { datasource: variables.dsn, returntype: "array" } );
        return rows.map( function( r ) {
            return {
                soc: r.soc_code, title: r.title, entryEducation: r.education_category,
                nationalMedian: r.national_median, nationalEmployment: r.national_employment,
                localMedian: r.local_median, localStatus: r.local_status
            };
        } );
    }

    public struct function get( required string soc ) {
        var rows = queryExecute( "
            SELECT o.soc_code, o.title, o.occupation_group, o.education_category, o.source_year,
                   p.education_notes, p.typical_entry_education, p.work_experience, p.ojt_training,
                   p.employment_base_thousands, p.employment_projected_thousands, p.outlook_percent, p.annual_openings_thousands,
                   p.outlook_period, p.outlook_year, p.source_url AS profile_source_url
            FROM occupations o LEFT JOIN occupation_profiles p ON p.soc_code = o.soc_code
            WHERE o.soc_code = :soc", { soc: { value: arguments.soc, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );
        if ( !arrayLen( rows ) ) throw( type = "NotFound", message = "That occupation code isn't in the imported data." );
        var r = rows[ 1 ];
        return {
            soc: r.soc_code, title: r.title, group: r.occupation_group, sourceYear: r.source_year,
            entryEducation: r.typical_entry_education ?: r.education_category,
            workExperience: r.work_experience, onTheJobTraining: r.ojt_training,
            outlook: isNull( r.outlook_percent ) ? javacast( "null", "" ) : {
                percentChange: r.outlook_percent, period: r.outlook_period,
                employmentBaseThousands: r.employment_base_thousands, employmentProjectedThousands: r.employment_projected_thousands,
                annualOpeningsThousands: r.annual_openings_thousands,
                source: "BLS Employment Projections", sourceUrl: r.profile_source_url
            },
            oohSearchUrl: "https://www.bls.gov/ooh/a-z-index.htm",
            caveat: "Typical entry-level education describes the typical worker. Some jobs also need a license, certification or more experience."
        };
    }

    public array function pathways( required string soc ) {
        return queryExecute( "
            SELECT ep.pathway_key, ep.name, ep.type, ep.minimum_years, ep.typical_years, ep.cost_basis, ep.licensing_notes, ep.description,
                   op.requirement_status, op.source_notes
            FROM occupation_pathways op JOIN education_pathways ep ON ep.id = op.pathway_id
            WHERE op.soc_code = :soc
            ORDER BY CASE op.requirement_status WHEN 'required' THEN 0 WHEN 'common' THEN 1 ELSE 2 END, ep.sort_order",
            { soc: { value: arguments.soc, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return {
                    key: r.pathway_key, name: r.name, type: r.type, minimumYears: r.minimum_years, typicalYears: r.typical_years,
                    costBasis: r.cost_basis, licensingNotes: r.licensing_notes, description: r.description,
                    status: r.requirement_status, sourceNotes: r.source_notes
                };
            } );
    }

    public array function allPathways() {
        return queryExecute( "SELECT pathway_key, name, type, minimum_years, typical_years, cost_basis, licensing_notes, description FROM education_pathways ORDER BY sort_order",
            {}, { datasource: variables.dsn, returntype: "array" } ).map( function( r ) {
                return { key: r.pathway_key, name: r.name, type: r.type, minimumYears: r.minimum_years, typicalYears: r.typical_years,
                    costBasis: r.cost_basis, licensingNotes: r.licensing_notes, description: r.description };
            } );
    }

}
