/**
 * Service wiring. Builds the singleton graph once per application start (reload in development with ?reinit).
 */
component {

    public struct function build( required any config ) {
        var b = {};
        b.config = arguments.config;

        // ---- core utilities and security
        b.logger = new core.utils.Logger();
        b.strings = new core.utils.StringUtil();
        b.json = new core.utils.JsonResponse();
        b.validator = new core.utils.Validator();
        b.rateLimiter = new core.utils.RateLimiter( b.config.apiRateLimitPerMinute );
        b.originGuard = new core.utils.OriginGuard( b.config.baseUrl );
        b.passwords = new core.security.PasswordService();
        b.csrf = new core.security.CSRFService( b.strings );
        b.adminAuth = new core.security.AdminAuth( b.passwords, b.rateLimiter, b.logger );
        b.migrations = new core.MigrationService( b.logger );

        // ---- data imports
        b.importRunner = new modules.imports.ImportRunner( b.config, b.logger );
        b.importRunner.setImporters( {
            oews: new modules.imports.BlsOewsImporter( b.importRunner, b.logger ),
            ep: new modules.imports.BlsProjectionsImporter( b.importRunner, b.logger ),
            cipsoc: new modules.imports.CipSocImporter( b.importRunner, b.logger ),
            hud: new modules.imports.HudRentImporter( b.importRunner, b.logger ),
            acs: new modules.imports.CensusAcsImporter( b.importRunner, b.logger ),
            scorecard: new modules.imports.CollegeScorecardImporter( b.importRunner, b.logger )
        } );
        b.importConnectors = new modules.imports.ImportConnectors( b.config, b.logger );
        b.importRunner.setConnectors( b.importConnectors );

        // ---- domain services
        b.geography = new modules.geo.GeographyService( b.strings );
        b.occupations = new modules.careers.OccupationService( b.strings );
        b.wages = new modules.careers.WageService();
        b.institutions = new modules.education.InstitutionService( b.strings );
        b.programs = new modules.education.ProgramService( b.strings );
        b.careerMapping = new modules.education.CareerMappingService();
        b.housing = new modules.housing.HousingCostService();
        b.taxes = new modules.finance.TaxEstimatorService();
        b.loans = new modules.finance.LoanCalculatorService();
        b.reference = new modules.simulator.ReferenceDataService( b.config, b.geography, b.occupations, b.wages, b.housing, b.taxes, b.institutions );
        b.simulator = new modules.simulator.LifestyleSimulatorService( b.config, b.taxes, b.loans );
        b.reverseSearch = new modules.simulator.ReverseCareerSearchService( b.simulator, b.wages );
        b.scenarios = new modules.simulator.ScenarioStore( b.config );

        // ---- web layer
        b.viewHelper = new core.utils.ViewHelper( b.csrf, b.config );
        b.routes = new config.Routes();
        b.controllers = {
            pages: new controllers.PagesController( b ),
            admin: new controllers.AdminController( b ),
            dev: new controllers.DevController( b ),
            apiGeo: new api.v1.GeoApi( b ),
            apiCareers: new api.v1.CareersApi( b ),
            apiEducation: new api.v1.EducationApi( b ),
            apiSimulations: new api.v1.SimulationsApi( b ),
            apiSources: new api.v1.SourcesApi( b )
        };
        return b;
    }

}
