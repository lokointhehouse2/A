/**
 * Housing benchmarks for a metro, each with its own geography, period and caveat:
 *   ACS median gross rent by bedrooms (CBSA, exact geography; gross rent includes utilities)
 *   HUD Fair Market Rents (HUD FMR areas linked to the CBSA via geo_source_mappings: exact or partial)
 *   ACS median home value (CBSA)
 * Missing values stay null; no benchmark is substituted from another geography without a label.
 */
component {

    variables.dsn = "futurepathDB";

    public struct function forMetro( required string cbsa ) {
        var acs = { available: false, rents: {}, moe: {}, year: javacast( "null", "" ), period: javacast( "null", "" ) };
        var acsRows = queryExecute( "
            SELECT bedroom_key, monthly_rent, margin_of_error, year, period_label FROM rent_observations
            WHERE geo_system = 'ACS_CBSA' AND geo_code = :c AND measurement_type = 'ACS_MEDIAN_GROSS_RENT'
              AND year = (SELECT MAX(year) FROM rent_observations WHERE geo_system = 'ACS_CBSA' AND measurement_type = 'ACS_MEDIAN_GROSS_RENT')",
            { c: { value: arguments.cbsa, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );
        for ( var r in acsRows ) {
            acs.rents[ r.bedroom_key ] = r.monthly_rent;
            acs.moe[ r.bedroom_key ] = r.margin_of_error;
            acs.year = r.year;
            acs.period = r.period_label;
            if ( !isNull( r.monthly_rent ) ) acs.available = true;
        }
        acs.label = "Census ACS median gross rent";
        acs.note = "Median monthly gross rent (rent plus utilities) paid by renter households in this metro area. A survey estimate for #acs.period ?: 'the latest period'#, not today's listing prices.";
        acs.sourceUrl = "https://www.census.gov/programs-surveys/acs/data/summary-file.html";

        var hudRows = queryExecute( "
            SELECT g.external_geo_code, g.external_name, g.mapping_quality, g.population, g.notes, r.bedroom_key, r.monthly_rent, r.year, r.period_label
            FROM geo_source_mappings g
            JOIN rent_observations r ON r.geo_system = 'HUD_FMR_AREA' AND r.geo_code = g.external_geo_code AND r.measurement_type = 'HUD_FMR'
            WHERE g.geo_system = 'HUD_FMR_AREA' AND g.cbsa_code = :c
              AND r.year = (SELECT MAX(year) FROM rent_observations WHERE geo_system = 'HUD_FMR_AREA')
            ORDER BY CASE g.mapping_quality WHEN 'exact' THEN 0 ELSE 1 END, g.population DESC",
            { c: { value: arguments.cbsa, cfsqltype: "char" } }, { datasource: variables.dsn, returntype: "array" } );
        var hudAreas = [];
        var hudIndex = {};
        for ( var h in hudRows ) {
            if ( !structKeyExists( hudIndex, h.external_geo_code ) ) {
                arrayAppend( hudAreas, { code: h.external_geo_code, name: h.external_name, quality: h.mapping_quality, population: h.population, notes: h.notes, year: h.year, period: h.period_label, rents: {} } );
                hudIndex[ h.external_geo_code ] = arrayLen( hudAreas );
            }
            hudAreas[ hudIndex[ h.external_geo_code ] ].rents[ h.bedroom_key ] = h.monthly_rent;
        }

        var homeRows = queryExecute( "
            SELECT value, margin_of_error, year, period_label FROM housing_price_observations
            WHERE geo_system = 'ACS_CBSA' AND geo_code = :c AND metric_type = 'ACS_MEDIAN_HOME_VALUE'
            ORDER BY year DESC LIMIT 1", { c: { value: arguments.cbsa, cfsqltype: "varchar" } }, { datasource: variables.dsn, returntype: "array" } );

        return {
            cbsa: arguments.cbsa,
            acs: acs,
            hud: {
                areas: hudAreas,
                label: "HUD Fair Market Rent",
                note: "A HUD policy benchmark (generally the 40th percentile of gross rents for standard-quality units), not a median and not current listings.",
                sourceUrl: "https://www.huduser.gov/portal/datasets/fmr.html"
            },
            homeValue: arrayLen( homeRows ) ? {
                value: homeRows[ 1 ].value, moe: homeRows[ 1 ].margin_of_error, year: homeRows[ 1 ].year, period: homeRows[ 1 ].period_label,
                label: "Census ACS median home value",
                note: "Owners' estimate of their home's value, #homeRows[ 1 ].period_label#. Homes for sale today may cost more or less.",
                sourceUrl: "https://www.census.gov/programs-surveys/acs/data/summary-file.html"
            } : javacast( "null", "" )
        };
    }

}
