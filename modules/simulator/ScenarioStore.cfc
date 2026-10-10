/**
 * Optional server-side save for share links. Stores only the normalized, non-identifying scenario configuration
 * under an unguessable UUID (no names, emails, ages, addresses or session identifiers).
 */
component {

    variables.dsn = "futurepathDB";

    public ScenarioStore function init( required any config ) {
        variables.config = arguments.config;
        return this;
    }

    public string function save( required struct scenario, string title = "", any result = "" ) {
        var id = lCase( createObject( "java", "java.util.UUID" ).randomUUID().toString() );
        var s = arguments.scenario;
        var socs = s.earners.map( function( e ) { return e.soc; } );
        queryExecute( "
            INSERT INTO simulation_scenarios (scenario_uuid, title, selected_soc_code, unitid, cip_code, cbsa_code, household_json, education_json, income_json, assumptions_json, data_years_json)
            VALUES (:id, :title, :soc, :unitid, :cip, :cbsa, :household, :education, :income, :assumptions, :years)", {
            id: { value: id, cfsqltype: "char" },
            title: { value: left( reReplace( arguments.title, "[<>]", "", "all" ), 120 ), cfsqltype: "varchar", null: !len( arguments.title ) },
            soc: { value: arrayLen( socs ) ? socs[ 1 ] : "", cfsqltype: "varchar", null: !arrayLen( socs ) || !len( socs[ 1 ] ) },
            unitid: { value: s.education.unitid ?: 0, cfsqltype: "integer", null: isNull( s.education.unitid ) },
            cip: { value: s.education.cip, cfsqltype: "varchar", null: !len( s.education.cip ) },
            cbsa: { value: s.cbsa, cfsqltype: "char" },
            household: { value: serializeJSON( { adults: s.adults, tiles: s.tiles, state: s.state, nycResident: s.nycResident, filingStatus: s.filingStatus, taxYear: s.taxYear } ), cfsqltype: "longvarchar" },
            education: { value: serializeJSON( s.education ), cfsqltype: "longvarchar" },
            income: { value: serializeJSON( s.earners ), cfsqltype: "longvarchar" },
            assumptions: { value: serializeJSON( { assumptions: s.assumptions, timeline: s.timeline, plan: s.plan ?: {} } ), cfsqltype: "longvarchar" },
            years: { value: isStruct( arguments.result ) ? serializeJSON( arguments.result.dataYears ?: {} ) : "{}", cfsqltype: "longvarchar" }
        }, { datasource: variables.dsn } );
        if ( isStruct( arguments.result ) ) {
            queryExecute( "INSERT INTO simulation_results (scenario_uuid, calculation_version, result_json) VALUES (:id, :v, :r)", {
                id: { value: id, cfsqltype: "char" }, v: { value: variables.config.calculationVersion, cfsqltype: "varchar" },
                r: { value: serializeJSON( arguments.result ), cfsqltype: "longvarchar" }
            }, { datasource: variables.dsn } );
        }
        return id;
    }

    /** Rebuilds the raw scenario (to be re-normalized by the caller). */
    public struct function get( required string uuid ) {
        var rows = queryExecute( "SELECT * FROM simulation_scenarios WHERE scenario_uuid = :id", { id: { value: lCase( arguments.uuid ), cfsqltype: "char" } }, { datasource: variables.dsn, returntype: "array" } );
        if ( !arrayLen( rows ) ) throw( type = "NotFound", message = "That shared scenario doesn't exist (it may have been removed)." );
        var r = rows[ 1 ];
        var household = deserializeJSON( r.household_json );
        var extra = deserializeJSON( r.assumptions_json );
        return {
            title: r.title,
            createdAt: r.created_at,
            scenario: {
                v: 1, cbsa: r.cbsa_code, state: household.state, nycResident: household.nycResident, filingStatus: household.filingStatus,
                taxYear: household.taxYear, adults: household.adults, tiles: household.tiles,
                earners: deserializeJSON( r.income_json ), education: deserializeJSON( r.education_json ),
                assumptions: extra.assumptions, timeline: extra.timeline, plan: extra.plan ?: {}
            }
        };
    }

}
