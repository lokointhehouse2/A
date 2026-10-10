/**
 * Assembles the reference data a scenario needs (wages, housing, tax packs, food, loans, pathways) into one
 * "reference bundle". The browser downloads it once per city/career change and recalculates locally;
 * the server uses the identical bundle for authoritative calculations.
 */
component {

    variables.dsn = "futurepathDB";

    public ReferenceDataService function init( required any config, required any geography, required any occupations, required any wages, required any housing, required any taxes, required any institutions ) {
        variables.config = arguments.config;
        variables.geography = arguments.geography;
        variables.occupations = arguments.occupations;
        variables.wages = arguments.wages;
        variables.housing = arguments.housing;
        variables.taxes = arguments.taxes;
        variables.institutions = arguments.institutions;
        return this;
    }

    public struct function bundle( required string cbsa, array socs = [], string stateCode = "", boolean nycResident = false, numeric taxYear = 0, any unitid = "" ) {
        var year = arguments.taxYear > 0 ? arguments.taxYear : variables.config.defaultTaxYear;
        var metro = variables.geography.get( arguments.cbsa );
        var st = len( arguments.stateCode ) ? arguments.stateCode : ( metro.primaryState ?: "" );
        var wageMap = {};
        var nationalMap = {};
        var occMap = {};
        for ( var soc in arguments.socs ) {
            if ( !reFind( "^[0-9]{2}-[0-9]{4}$", soc ) || structKeyExists( occMap, soc ) ) continue;
            try {
                var o = variables.occupations.get( soc );
                occMap[ soc ] = { title: o.title, entryEducation: o.entryEducation };
                var w = variables.wages.forOccupation( soc, arguments.cbsa );
                wageMap[ soc ] = w.local;
                nationalMap[ soc ] = w.national;
            } catch ( NotFound e ) {}
        }
        var housing = variables.housing.forMetro( arguments.cbsa );
        var institution = javacast( "null", "" );
        if ( isNumeric( arguments.unitid ) && arguments.unitid > 0 ) {
            try { institution = variables.institutions.get( arguments.unitid ); } catch ( NotFound e ) {}
        }
        var food = foodPlans();
        return {
            metro: metro,
            stateCode: st,
            wages: wageMap,
            nationalWages: nationalMap,
            occupations: occMap,
            wageDefinitions: variables.wages.definitions(),
            housing: housing,
            taxPacks: variables.taxes.packsFor( st, arguments.nycResident, year ),
            food: food,
            loans: loanRates(),
            pathways: pathwayMap(),
            institution: institution,
            dataYears: {
                wages: variables.wages.latestYear( "metro" ),
                rentAcs: housing.acs.period,
                rentHud: arrayLen( housing.hud.areas ) ? housing.hud.areas[ 1 ].period : javacast( "null", "" ),
                homeValue: isStruct( housing.homeValue ?: "" ) ? housing.homeValue.period : javacast( "null", "" ),
                food: food.period,
                taxYear: year
            }
        };
    }

    /** USDA plans keyed plan -> ageGroup -> monthly cost (latest period). */
    public struct function foodPlans() {
        var rows = queryExecute( "
            SELECT category, amount, period_label FROM regional_cost_observations
            WHERE geo_system = 'US' AND category LIKE 'food\_%'
              AND period_label = (SELECT MAX(period_label) FROM regional_cost_observations WHERE geo_system = 'US' AND category LIKE 'food\_%')",
            {}, { datasource: variables.dsn, returntype: "array" } );
        var out = { period: javacast( "null", "" ), sourceUrl: "https://www.fns.usda.gov/cnpp/usda-food-plans-cost-food-monthly-reports", low: {}, moderate: {}, liberal: {} };
        for ( var r in rows ) {
            // category: food_<plan>_<ageGroup>
            var rest = mid( r.category, 6, len( r.category ) );
            var plan = listFirst( rest, "_" );
            var group = mid( rest, len( plan ) + 2, len( rest ) );
            if ( structKeyExists( out, plan ) ) out[ plan ][ group ] = val( r.amount );
            out.period = r.period_label;
        }
        return out;
    }

    public struct function loanRates() {
        var out = {};
        for ( var r in queryExecute( "
            SELECT l.loan_key, l.description, l.annual_interest_rate, l.duration_months, l.valid_from, l.valid_to, l.source_url
            FROM loan_assumptions l
            WHERE l.valid_from <= UTC_DATE() ORDER BY l.valid_from DESC", {}, { datasource: variables.dsn, returntype: "array" } ) ) {
            if ( structKeyExists( out, r.loan_key ) ) continue;
            out[ r.loan_key ] = {
                rate: val( r.annual_interest_rate ), months: r.duration_months, description: r.description,
                validFrom: dateFormat( r.valid_from, "yyyy-mm-dd" ), validTo: isNull( r.valid_to ) ? javacast( "null", "" ) : dateFormat( r.valid_to, "yyyy-mm-dd" ),
                sourceUrl: r.source_url
            };
        }
        return out;
    }

    public struct function pathwayMap() {
        var out = {};
        for ( var p in variables.occupations.allPathways() ) out[ p.key ] = p;
        return out;
    }

}
