# FuturePath — Complete Claude Code Build Specification

**Working name:** FuturePath (configurable; check trademark/domain availability before launch)  
**Product:** Interactive education, career, and future-lifestyle simulator for teenagers  
**Stack:** Lucee CFML, CommandBox, MariaDB, HTML/CSS, Bootstrap 5, JavaScript, REST-style JSON services  
**Audience:** U.S. students (roughly 13–18), families, teachers, and counselors  
**Instruction target:** Claude Code working in VS Code  
**Status:** Direct-build MVP specification — continuous implementation, minimal validation overhead, no repeated builds or audits

---

## 1. Instructions to Claude Code

Build a complete, usable MVP, not a mockup. Work directly in this project repository and make sensible implementation decisions without repeatedly asking for permission. Scaffold once, run migrations once, implement vertical slices, and only run targeted checks at meaningful milestones. Never silently replace real missing source data with fabricated salaries, tuition, employment outcomes, or housing prices. Add source/year labels throughout the UI.

1. Inspect the existing directory once; preserve existing files if present.
2. Initialize Lucee under CommandBox with `server.json`, configurable environment settings, and MariaDB datasource. Do not hardcode secrets.
3. Build migrations, seed data, reusable CFML services, importers, REST endpoints, user interface, and focused tests.
4. Favor straightforward server-rendered CFML plus vanilla JS/fetch for interactivity. Avoid unnecessary frontend frameworks and dependencies. Use a small, accessible drag-and-drop library only if it materially reduces complexity; provide keyboard/touch alternatives.
5. Use parameterized SQL (`queryExecute` with typed parameters), encode output, validate inputs, and handle import/API failures gracefully.
6. Create `.env.example`, `README.md`, `docs/DATA_SOURCES.md`, `docs/ASSUMPTIONS.md`, and run instructions.
7. Work in direct-build mode: implement phases consecutively without pausing for routine confirmations, repeated builds, or exploratory audit loops. Run one short startup/smoke check when the site is first runnable, and one focused final verification; rerun only a specific failed check after a fix.
8. Use live public sources only after validating current schema/API terms. Provide import-from-file fallbacks when an API is unavailable.

### Mandatory execution mode — BUILD FIRST, NO REPEATED CHECKING

These are explicit instructions for Claude Code in VS Code and take priority over optional process suggestions elsewhere in this document:

- **Implement immediately.** Read this spec once, inspect the repository once, choose reasonable defaults, and start writing working files. Do not repeatedly summarize the plan, re-read the entire repo, or ask approval for ordinary implementation choices.
- **One continuous build flow.** Finish Phase 1, then continue directly through Phases 2–4 without pausing to request a go-ahead. Treat Phase 5 as optional after the MVP works.
- **Do not run `box server start`, stop/restart the server, recompile, reinstall dependencies, or re-run migrations after every edit.** Scaffold and install once; use normal hot reload where available. Restart only if configuration changes actually require it or a diagnosed failure makes it necessary.
- **No repetitive test loops.** Do not continuously run lint, full test suites, UI audits, screenshots, browser checks, dependency updates, performance scans, or documentation reviews. Prefer one minimal startup smoke check and one final focused check covering critical functionality. If a check fails, fix the specific issue and rerun only that check.
- **Preserve essential correctness and security.** Still validate critical computations, imports, SQL parameters, authentication, and input handling. Do not skip a required check needed to diagnose an actual failure; avoid *redundant* checks, not meaningful safeguards.
- **Do not block the build on unavailable external API keys or downloads.** Implement adapters and imports with a clear unavailable state or explicitly labeled demo mode, then continue with other features; never invent real data.
- **Minimal reporting.** Give a concise completion summary with implemented features, unresolved blockers, and exact start instructions. Do not repeatedly report status or solicit confirmation between phases.
- **Use HTTP port `42005` for this application everywhere.** In `server.json`, set `web.http.port` to `42005`; in `.env.example`, use `APP_PORT=42005` and `APP_BASE_URL=http://127.0.0.1:42005`; update README, examples and local links accordingly. Do not silently fall back to 8080 or select a random port. If 42005 is occupied, report the conflict rather than switching ports.

Example `server.json` port setting (merge into a valid CommandBox configuration):

```json
{
  "name": "FuturePath",
  "web": {
    "http": { "port": 42005 }
  }
}
```

**Primary objective:** A student can choose a city, career, education route, and desired lifestyle; compare realistic projected take-home income and monthly expenses; then reverse-search for career pathways that might support the dream.

---

## 2. Product philosophy

Show possibilities, tradeoffs, and multiple legitimate paths — never shame jobs or educational choices. A fast-food job is a valid path and can be modeled for long-term earning power, but distinguish an **entry-level crew position** from a **shift supervisor**, **restaurant manager**, and **franchise owner** (ownership requires different assumptions and is not an ordinary wage). A GED, apprenticeship, certification, associate degree, bachelor's degree, and advanced education should be presented fairly.

Do not predict a student's personal fate or guarantee employment. Every forecast is an illustrative scenario using publicly sourced estimates and editable assumptions. Explain that degrees do not guarantee an occupation and that some professions require additional licensing, residency, or graduate education.

---

## 3. User journeys

### A. Start with your dream

1. Choose target city/metro: Orlando, New York City, Washington DC, or any imported U.S. metro.
2. Choose living situation: roommate, apartment rental, or home purchase.
3. Configure desired housing size, vehicles, household adults, children, childcare, eating out, travel, savings, and other major expenses.
4. Set target age/year, income scenario (single earner or two earners), and debt assumptions.
5. Calculate estimated monthly/annual required household income; display what changes if location or lifestyle changes.
6. Show occupations whose local wages could support that budget, with education requirements, duration, and career information.
7. Allow comparisons of three selected pathways in a single view.

### B. Start with a career

1. Search occupations: carpenter, English teacher, college English professor, software developer, physician, fast-food worker, etc.
2. Choose location and wage scenario (10th, 25th, median, 75th, 90th percentile where published; do **not** pretend percentiles correspond directly to years of experience).
3. Show gross annual wages, estimated take-home pay, expected monthly spending, affordability, and missing/unavailable wage indicators.
4. Show training routes and approximate time to enter the occupation, then recommend comparable alternatives.
5. Let student adjust lifestyle and see a live monthly budget and shortfall/surplus.

### C. Start with a school or degree

1. Search colleges by state, name, degree level, and program/major.
2. Display institution-level tuition, net price and completion data; field-of-study debt and earnings **only when that granularity is available and properly matched**.
3. Match program CIP code to candidate SOC occupations using the official CIP–SOC crosswalk.
4. Let users choose a **specific occupation** from mapped *possibilities*; never claim that choosing this major ensures that job.
5. Pull local occupational wage observations by SOC + metro; use that occupational wage in the career lifestyle simulation.
6. Show an independent panel with *observed field-of-study earnings* (when available), clearly differentiated from *local occupational wages*.
7. Compare upfront costs, expected years enrolled, grants/scholarships, debt payments, and approximate breakeven/ROI under explicitly stated assumptions.

### D. Compare alternate futures

Examples: GED → full-time employment; high school → skilled trades apprenticeship → carpenter; associate degree → technician; bachelor's in English → K–12 teacher (license required) vs English professor (typically advanced degree required); bachelor's in computer science → software developer; premed → medical school → residency → physician.

Display a timeline (ages 18, 22, 25, 30, 40 and adjustable), with education cost, annual wages, student debt, savings, and living costs. Changes in earnings through time are modeled assumptions or sourced projections, not guaranteed trajectories.

---

## 4. Primary data sources and integration strategy

**Default architectural principle: ingest/cache versioned government datasets into MariaDB, then serve the website from your database.** Do not call multiple external APIs for every slider interaction.

| Domain | Authoritative source | Data to use | Integration method | Important caveat |
|---|---|---|---|---|
| Occupations and metro wages | BLS Occupational Employment and Wage Statistics (OEWS) | SOC code; metro/CBSAs; annual/hourly wages; percentiles | Download annual national/state/metro tables and import | An occupational wage is not a job offer or a starting salary; some cells suppressed |
| Job outlook, entry education | BLS Occupational Outlook Handbook / Employment Projections | descriptions, entry education, projected growth | Import licensed/public structured releases where available, or curated links | Do not assume all OOH content is exposed as a uniform API |
| Occupation tasks and skills | O*NET Web Services / O*NET database | tasks, skills, interests, training context | API with credentials/license terms or downloadable database | Check current terms and mapping versions |
| Colleges and programs | U.S. Department of Education College Scorecard | schools, tuition, net price, completion, program-level debt/earnings | API key through api.data.gov or bulk CSV downloads | Many program outcomes are suppressed, missing, or not comparable |
| Major-to-career mappings | NCES 2020 CIP → 2018 SOC crosswalk | many-to-many academic program to potential occupations | Download official XLSX and import | **Not actual graduate placement outcomes** |
| College catalog and characteristics | NCES IPEDS | institution/program completions, awards, institutional costs | Data downloads | May differ in reporting years and cohort definitions |
| Rental housing | HUD Fair Market Rents | area-level benchmark rent by bedroom count | Published downloads or HUD API if available | FMR is a policy benchmark, not a current apartment listing or a local median |
| Household and housing statistics | Census ACS API | income, median gross rent, home value, commuting | API with geographies and vintage | ACS estimates have margins of error and geographic constraints |
| Taxes | IRS, state revenue agencies | brackets, standard deduction, payroll taxes, state tax | Versioned tables implemented in app | Simplified estimator; not tax advice |
| Living expenses | BEA Regional Price Parities; MIT Living Wage Calculator (if terms permit); USDA food plans; local datasets | price-level factors, food, childcare proxies | Curated/versioned estimates with explicit provenance | Avoid claiming complete authoritative household budgets from one dataset |
| Postsecondary aid and loan costs | StudentAid.gov, College Scorecard, current federal loan-rate tables | loan rates, repayment terms, grants context | Versioned configuration and official links | Aid is individualized; example calculations only |

### Official reference URLs

- BLS OEWS data tables: https://www.bls.gov/oes/tables.htm
- BLS metro estimates: https://www.bls.gov/oes/current/oessrcma.htm
- BLS API documentation: https://www.bls.gov/developers/
- BLS OOH: https://www.bls.gov/ooh/
- College Scorecard: https://collegescorecard.ed.gov/data/
- College Scorecard API: https://collegescorecard.ed.gov/data/api-documentation/
- API key registration: https://api.data.gov/signup/
- NCES CIP/SOC: https://nces.ed.gov/ipeds/cipcode/resources.aspx?y=56
- Official 2020 CIP / 2018 SOC file: https://nces.ed.gov/ipeds/cipcode/Files/CIP2020_SOC2018_Crosswalk.xlsx
- IPEDS: https://nces.ed.gov/ipeds/use-the-data
- HUD rents: https://www.huduser.gov/portal/datasets/fmr.html
- Census ACS API: https://www.census.gov/data/developers/data-sets/acs-5year.html
- O*NET: https://services.onetcenter.org/
- BEA Regional Price Parities: https://www.bea.gov/data/prices-inflation/regional-price-parities-state-and-metro-area
- Federal Student Aid: https://studentaid.gov/

**Implementation notes:** BLS OEWS annual bulk metro tables are the best first source for detailed local occupational wages. Do not assume the BLS time-series API directly substitutes for full OEWS bulk data. College Scorecard's schema varies by year; use its latest published data dictionary, dynamically configure field mappings and do not invent exact field names beyond verified examples. Verify all source endpoints on first integration; store requests, timestamps, data vintages, source URLs and import history.

---

## 5. Data relationship design

```text
college institution (UNITID)
    | 1:N
    v
school/program offering (CIP code + credential level)
    | N:M using official CIP-SOC crosswalk
    v
occupation (SOC 2018 code)
    | 1:N
    v
occupational wage observation (SOC + geography + reference year)
    |
    v
income/tax calculator ------> lifestyle cost model (geography + household)
    |                                   |
    +-----------------+-----------------+
                      v
           affordability comparison
                      |
                      v
             alternative pathways
```

**Crucial:** College Scorecard program earnings describe observed outcomes for qualifying former students grouped by field/institution and reporting cohort; BLS OEWS describes occupations in labor markets. They are *not the same measure*. Keep the datasets distinct and visible as separate metrics; never splice them into a purported school → guaranteed job → salary chain.

### Geography

Create geography reference tables for state FIPS, counties, CBSA metro areas, and relevant HUD FMR area codes. Maintain explicit geography mapping tables and confidence/exception records. Orlando city, Orlando metro area, and Orlando HUD rent area are not necessarily identical geographies. Where no valid geographic mapping exists, show the missing data rather than using an unmarked substitute.

---

## 6. MariaDB schema (create numbered SQL migrations)

Create migrations with `utf8mb4`, InnoDB, foreign keys, indexes and unique constraints. Implement the following entities; choose precise column types and indexes in actual SQL.

### Source and taxonomy

- `data_sources`: id, name, agency, source_url, license_notes, refresh_cadence, created_at.
- `data_import_runs`: id, source_id, dataset_key, vintage_year, started_at, ended_at, result_status, rows_seen, rows_inserted, rows_updated, error_summary, checksum.
- `states`: state_fips, state_code, name.
- `metro_areas`: cbsa_code PK, name, geographic_type, active_flag.
- `metro_state_map`: cbsa_code, state_fips.
- `geo_source_mappings`: id, geo_system, external_geo_code, cbsa_code nullable, mapping_quality, notes.
- `occupations`: soc_code PK (CHAR/VARCHAR, retain hyphens), title, description, education_category, source_year, active_flag.
- `occupational_wages`: id, soc_code, cbsa_code nullable, state_fips nullable, area_level, wage_year, employment_count nullable, hourly_mean nullable, annual_mean nullable, hourly_median nullable, annual_median nullable, annual_p10/p25/p75/p90 nullable, suppression_code nullable, source_id, imported_at. Unique SOC + area type/code + wage year.
- `occupation_profiles`: soc_code, tasks_summary, education_notes, outlook_percent nullable, outlook_year, source_id, source_url.
- `cip_programs`: cip_code PK VARCHAR(10) (preserve decimal formatting), title, description, taxonomy_year.
- `cip_soc_crosswalk`: cip_code, soc_code, crosswalk_year, source_id; unique on code pair + version.

### Institutions and education

- `institutions`: unitid PK, name, city, state_code, website_url, control_type, predominant_degree, latitude/longitude optional, active_flag, source_year.
- `institution_costs`: id, unitid, academic_year, in_state_tuition nullable, out_state_tuition nullable, total_cost_of_attendance nullable, average_net_price nullable, reporting_population, source_id.
- `institution_outcomes`: id, unitid, report_year, completion_rate nullable, retention_rate nullable, median_debt nullable, published_definitions_json.
- `institution_programs`: id, unitid, cip_code, credential_level_code, program_label, reported_awards nullable, reporting_year; unique by institution + CIP + credential + reporting year.
- `program_outcomes`: id, unitid, cip_code, credential_level_code, report_year, earnings_median nullable, earnings_measure nullable, earnings_horizon nullable, debt_median nullable, cohort_info_json, suppressed_flag, source_id.
- `education_pathways`: id, name, type (work/GED/certificate/apprenticeship/associate/bachelor/master/doctoral/professional), minimum_years, typical_years, cost_basis, licensing_notes, source_id nullable.
- `occupation_pathways`: soc_code, pathway_id, requirement_status (common/required/alternative), source_notes; do not model all pathways as guaranteed or universally required.

### Cost of living and calculation

- `rent_observations`: id, geo_system, geo_code, bedroom_count, monthly_rent, year, measurement_type (`HUD_FMR`, `ACS_MEDIAN_GROSS_RENT`, etc.), source_id.
- `housing_price_observations`: id, geo_system, geo_code, value, year, metric_type, source_id.
- `regional_cost_observations`: id, geo_system, geo_code, category, period_year, amount, unit, household_profile_json, source_id, confidence_notes.
- `tax_rules`: id, jurisdiction_code, tax_year, filing_status, rule_type, lower_bound, upper_bound nullable, rate, fixed_amount nullable, parameters_json.
- `loan_assumptions`: id, description, annual_interest_rate, duration_months, valid_from, source_id.
- `simulation_scenarios`: UUID PK, anonymous_session_id nullable, user_id nullable, title, selected_soc_code nullable, unitid nullable, cip_code nullable, cbsa_code, household_json, education_json, income_json, assumptions_json, data_years_json, created_at, updated_at.
- `simulation_results`: id, scenario_uuid, calculation_version, result_json, calculated_at.
- `admin_users`: id, email, password_hash, role, created_at, last_login_at. No plaintext passwords.

Every money observation must include dollar period, observation year, geography and source metadata; use `DECIMAL` for currency values, not FLOAT.

---

## 7. Backend module structure

```text
/
  Application.cfc
  index.cfm
  server.json
  box.json
  .env.example
  README.md
  /config
  /db/migrations
  /db/seeds
  /modules
    /careers/OccupationService.cfc
    /careers/WageService.cfc
    /education/InstitutionService.cfc
    /education/ProgramService.cfc
    /education/CareerMappingService.cfc
    /geo/GeographyService.cfc
    /housing/HousingCostService.cfc
    /finance/TaxEstimatorService.cfc
    /finance/LoanCalculatorService.cfc
    /simulator/LifestyleSimulatorService.cfc
    /simulator/ReverseCareerSearchService.cfc
    /imports/ImportRunner.cfc
    /imports/BlsOewsImporter.cfc
    /imports/CollegeScorecardImporter.cfc
    /imports/CipSocImporter.cfc
    /imports/HudRentImporter.cfc
    /imports/CensusAcsImporter.cfc
  /api/v1
  /admin
  /assets/css
  /assets/js
  /views
  /tests
  /docs
```

Use `Application.cfc` for configuration, datasource mapping, session configuration, error handling and dependency/service wiring. Build basic migration runner or use an established compatible CFML migration tool if already available; do not over-engineer.

### REST-style endpoints

| Method | Endpoint | Function |
|---|---|---|
| GET | `/api/v1/geographies?q=orlando` | search imported geographies |
| GET | `/api/v1/occupations?q=carpenter` | search SOC occupations |
| GET | `/api/v1/occupations/{soc}/wages?cbsa=...&year=...` | get local wages + provenance |
| GET | `/api/v1/institutions?q=...&state=FL` | search colleges |
| GET | `/api/v1/institutions/{unitid}` | college costs and completion |
| GET | `/api/v1/institutions/{unitid}/programs` | available degrees with known outcomes |
| GET | `/api/v1/programs/{cip}/careers` | possible SOC careers from crosswalk |
| GET | `/api/v1/occupations/{soc}/pathways` | training/certification routes |
| POST | `/api/v1/simulations/calculate` | calculate affordability |
| POST | `/api/v1/simulations/reverse-careers` | match income goal to candidates |
| POST | `/api/v1/simulations/compare` | compare up to three scenarios |
| GET | `/api/v1/sources/status` | data vintages and availability |
| GET/POST | `/admin/imports` | protected data import controls |

Support simple page routing and JSON endpoints in Lucee; real routes must return correct status codes and typed errors. Input validation, CSRF protection on applicable state-changing browser requests, rate limiting for public JSON/search, parameterized queries and safe error messages required.

---

## 8. Calculation engine

### Monthly income

1. `annualGross = annualOccupationWage * workFraction` (default fraction 1.0; account for part-time jobs).
2. For two earners, include the second earner as a separate input and validate that household expenses and tax filing scenario match.
3. `annualEstimatedTaxes = federalIncomeTax + stateIncomeTax + employeePayrollTaxes` using versioned simplifications, optional deductions/credits.
4. `monthlyTakeHome = (annualGross - annualEstimatedTaxes - pretaxContributions) / 12` (avoid double-counting pretax contributions in tax calculation).
5. Benefits, insurance premiums and retirement contributions shown as distinct adjustable inputs.

### Monthly lifestyle costs

`monthlyCosts = rentOrMortgage + propertyTaxes + homeInsurance + utilities + food + transportation + carLoans + autoInsurance + childcare + healthcare + studentLoanPayment + phoneInternet + discretionarySpending + travelSavings + emergencySavings + retirementSavings + otherExpenses`

- Mortgage affordability: home price, down payment, rate, loan term, closing costs, maintenance, property tax, insurance and HOA as separate configurable inputs. Show affordability based on actual cash flow, not only a mortgage-income ratio.
- Loan payment: standard amortization formula on principal, APR and months; show interest and debt total.
- Use amount-specific, year-specific sourcing and clearly mark **editable assumptions** for categories without reliable locality-level data.
- Do not double count employer payroll taxes or taxes already taken from gross wages.
- If a user selects "buy home," do not also charge rental housing.

`monthlySurplus = monthlyTakeHome - monthlyCosts`.

`affordabilityRatio = monthlyCosts / monthlyTakeHome` when denominator > 0.

Return rich outputs: full budget, warnings, scenario assumptions, source/year citations, wage percentile used, and percentage of estimated expenses covered.

### Reverse career search

Given lifestyle costs and a geographic market:

1. Estimate required gross household wage using a numerical bracket/binary search over the tax calculator (because net-to-gross isn't fixed percentage).
2. Retrieve occupations with **available wage observations** for the selected metro; compare chosen percentile wages to required gross, factoring household co-earner income.
3. Filter by education type, education length, interest tags and availability where known.
4. Rank by affordability margin, years/cost of training, student debt and occupational growth (only when sourced).
5. Show why a career appears, plus gaps and alternative scenarios. Do not exclude lower-paying careers from exploration simply because a luxury budget cannot be met.

### Career trajectory

Provide two modes: (a) current-wage-in-today's-dollars, held constant unless user sets raise assumption; (b) illustrative wage growth/inflation projections with editable rates. Never imply the BLS 10th-to-90th wage range represents a known career progression. Label assumed annual wage growth, price inflation, retirement savings return, school duration and unemployment gaps.

---

## 9. Main website UX

**Style:** polished, friendly, modern, age-appropriate; clear large typography, direct manipulation, drag-and-drop cards, sliders and live visual comparisons, accessible colors, mobile-first. **Design constraint: minimal clicks.** The primary experience should feel like building a future on one interactive canvas rather than filling out a long series of forms.

### Landing page

- Hero: **“Dream big. See what it takes.”**
- Subhead: **“Pick your future lifestyle, a career, or a college—and discover how the numbers connect.”**
- Primary CTA: **“Build My Future”**; secondary: **“Explore Careers”**.
- Three entry cards: **My Dream Life**, **My Dream Job**, **My Education Path**.
- Mini example comparing same career in Orlando vs New York vs Washington, with real data only.
- Source/transparency link explaining that outcomes are estimates, not guarantees.

### Interaction-first requirements (must implement, not just mock up)

- **One-screen Future Builder:** Keep dream lifestyle, chosen career/education, and resulting budget visible together on desktop. Use responsive stacked panels on phones. Avoid navigating users to separate pages for every variable.
- **Drag-and-drop lifestyle tiles:** Present choices as draggable or tap-to-add cards (Apartment, House, Roommates, Car, Second Car, Children, Childcare, Travel, Savings, Student Debt). Drag onto a **My Future** canvas to activate; drag within canvas to reorder, drag out/remove, or use a visible remove button. On touch screens use an obvious **Add** action as the primary reliable alternative to gesture dragging.
- **Inline editing:** Clicking/tapping an active tile expands controls **in place** (e.g., bedrooms, rent vs buy, number of cars/children, down payment, target savings) without a page transition or separate modal. Use small sliders, segmented controls and autocomplete with sensible defaults; do not force values that can be inferred only from user's personal details.
- **Dynamic recalculation:** Changes to city, job, school, degree, household and lifestyle instantly update the projected monthly budget, income gap, and affordability visuals **without a full page reload or a Submit/Calculate button**. Client calculates from a normalized JSON scenario and cached reference values; debounce server lookups (e.g., occupation/city search). Show loading/skeleton and stale-state indicators while new sourced data loads.
- **Career/education pathway cards:** Drag an occupation, college program, trade or GED/work path onto a **Path to My Future** slot; support tap-to-select for all devices. Dropping a degree shows mapped **possible** occupations, not guaranteed employment, and invites choosing a target job. Changing a job changes local wages and results immediately.
- **Compare futures:** Allow users to duplicate the current scenario into up to three compact columns, then drag or select different careers, cities and lifestyle tiles for each. Highlight only differences and show side-by-side take-home pay, education costs, monthly surplus/deficit and timelines.
- **Reverse planning:** When lifestyle cost exceeds the chosen career's estimated take-home income, show a clear gap and inline one-tap options like **Explore higher-paying careers**, **Try another city**, **Adjust housing**, or **See a lower-cost path**. Suggestions must rely on supported data rather than inventing outcomes.
- **Progressive disclosure:** Open with three entry choices (Dream Life / Career / College), then reach an editable first result with roughly three meaningful selections. Advanced assumptions (tax filing status, financing, aid, inflation) live in optional expandable drawers.
- **Smart search:** Typeahead for city, occupation, school and degree, with keyboard navigation, recent choices held locally if consent/settings permit, no dead-end empty states, and explicit data availability/source years.
- **Save/share without friction:** Keep the current scenario in client state and optionally local storage (clearly explained), with **Copy Link**, **Reset**, **Undo** and **Redo** where appropriate. Anonymous share links must contain only non-sensitive scenario configuration and avoid personal identifiers. Do not require account creation for simulation.
- **Accessible interaction parity:** Every drag operation has a keyboard-operable and screen-reader-labeled button/select alternative. Support mouse, touchscreen and keyboard, visible focus, reduced motion, generous touch targets, and a non-drag fallback. Never make essential functionality drag-only.
- **Performance:** Show the result optimistically on every client-side change using already-loaded assumptions; issue server calls only when datasets change, cancel/ignore obsolete responses, and avoid repeatedly downloading static tables.
- **UI visual feedback:** Animate tiles gently on add/remove and update simple budget bars, but do not sacrifice readability, motion preferences or numeric detail. Income gap must be shown explicitly in dollars alongside charts.

**Component plan:** `FutureBuilderCanvas`, `LifestyleTilePalette`, `ActiveLifestyleTile`, `LocationPicker`, `CareerPathPicker`, `EducationPathPicker`, `MonthlyBudgetSummary`, `TradeoffSuggestions`, `CompareFutures`, `AssumptionsDrawer`, `DataSourceDisclosure`. Implement as lightweight progressive-enhancement JS modules with CFML-rendered accessible initial HTML. Reuse a centralized `scenarioState` object and pure `calculateScenario()` function for live UI updates.

**Example flow:** Teen chooses Orlando → drags **House**, **Car**, and **Two Kids** onto the canvas → sees target income update live → searches **English professor** or drops **Computer Science at UCF** into the career/education slot → sees sourced career wage or mapped occupations, education costs, and monthly gap → taps **Compare another future**, swaps job/city in one action, and immediately sees a difference.

### Interactive wizard

**Step 1:** Where do you want to live? autocomplete U.S. metro; location can change later.  
**Step 2:** What does your life look like? household, housing, car, children, saving, travel; contextual estimates.  
**Step 3:** How do you want to get there? job, degree/school or reverse search.  
**Step 4:** Your future dashboard with income, expense waterfall, monthly surplus, education cost/debt, competing careers, and saved comparison.

### Dashboard panels

- **Income vs Lifestyle:** annual gross / estimated take-home / monthly lifestyle expense / difference.
- **Where the money goes:** housing, transportation, food, childcare, education debt, taxes, savings.
- **School investment:** total annual school price, net price, time, grants assumption, student debt payment.
- **Possible Jobs:** CIP-to-SOC mappings and local occupational wages; indicate actual licensing requirements.
- **Three futures:** side-by-side choice comparison with same dollars and time horizon.
- **Change one thing:** swap city, car, number of children, career, college, or housing.
- **Sources & assumptions:** expandable per panel, including vintage and any substituted geographic estimate.

Never show a false precision score such as “your future will be 73% successful.” Prefer explicit dollar ranges and scenario sensitivity.

---

## 10. Data admin and import tools

Admin dashboard available only to authorized users:

- Source catalogue with current data vintage, last successful import, source link, row counts, and warnings.
- Upload ZIP/CSV/XLSX for mapped datasets. Stream/chunk imports; do not load massive national files into memory.
- Manual job trigger, scheduled refresh, progress, import history, checksum, rollback/retry where reasonable.
- Field mapping preview before commit. Handle privacy/suppression codes and missing data; never coerce suppressed results to zero.
- Idempotent upserts, source-specific validators, and error log; imported snapshots remain reproducible.
- No arbitrary URL fetching from untrusted users; keep external provider fetches in allowlisted connectors.

Initial imports in order:

1. State/metro geography lookups.
2. SOC occupations and one chosen latest BLS OEWS metro dataset.
3. 2020 CIP taxonomy and official CIP–SOC crosswalk.
4. College Scorecard institutions and field-of-study datasets.
5. HUD rental benchmarks and relevant Census ACS figures.
6. Tax assumption tables and curated living-cost examples.

For demo usability, seed a **clearly labeled hypothetical demo dataset** only when external data is unavailable; keep it segregated and never portray the examples as reported real-world values.

---

## 11. Handling teens, student privacy and safety

- Default MVP to **anonymous sessions and local scenario URLs** (unguessable UUIDs, no personal name required). Do not collect age/date of birth, detailed address, grades, school attendance or contact information unless necessary.
- For audiences including users under 13, assess COPPA obligations before permitting account creation or collection of personal information; implement age-appropriate safeguards and parental/educator workflows as needed.
- Never profile children or sell student data. No targeted advertising to minors. Avoid invasive third-party trackers.
- Secure all admin endpoints, use HTTPS in production, secure cookies, hash passwords, add sensible retention/deletion policies.
- Display that financial/tax/college projections are educational estimates. Provide an easy way for users to inspect and change assumptions.
- Accessibility: keyboard navigation, labeled controls, WCAG-conscious contrast, chart data in text tables, reduced-motion support.

---

## 12. Phased implementation (execute in this order)

### Phase 1 — Functional foundation

**Deliver:** running Lucee/CommandBox site, MariaDB connection, migrations, navbar/layout, home page, occupation/metro search, working data importer for the first OEWS release, basic wage-by-city view. Include Orlando, New York metro and Washington metro when the imported dataset supports them. Add tests for empty/suppressed wage results and geo mismatches.

**Acceptance:** A student chooses a known SOC occupation and metro; the screen shows a real sourced wage, year and percentile/mean definition, or an explicit unavailable state.

### Phase 2 — Core lifestyle simulator

**Deliver:** drag-and-drop/tap-to-add Future Builder canvas, inline lifestyle tile controls, keyboard/touch alternatives, centralized scenario state and reactive budget updates; housing + household wizard; yearly wage to estimated monthly take-home conversion; configurable expense categories; visual surplus/shortfall; swap city and occupation; anonymous shareable scenario links. For first iteration, manually maintain tax tables with year labels and document omissions.

**Acceptance:** Scenario results are deterministic and auditable, changing rent/car/children updates monthly cash flow, and no data is silently fabricated.

### Phase 3 — College and degree connections

**Deliver:** drag-or-select education/career path cards with inline updates; College Scorecard importer/API adaptor, schools/programs search, tuition/average net price/field outcomes when available, NCES CIP–SOC crosswalk import, degree → possible occupation selector, occupation → metro wage lookup. Implement generic program cost/debt timeline calculator.

**Acceptance:** Choosing a college and English-related program returns mapped candidate careers where the crosswalk has them; choosing a career and Orlando or New York results in local occupational wage and corresponding lifestyle output. The UI separates observed degree earnings from occupational wages, and does not promise a particular job.

### Phase 4 — Dream-life reverse search

**Deliver:** required gross earnings solver, matching occupation lists, one-tap tradeoff suggestions, schooling and affordability tradeoffs, drag-or-select compare-three-futures dashboard, printable/exportable scenario summary.

**Acceptance:** User specifies 3-bedroom rental/house, two children, cars, savings, and city; tool computes a documented budget and suggests *possible* occupations with local wage evidence, highlighting whether the goal is plausible under selected assumptions.

### Phase 5 — Expansion (after MVP)

Career personality/interest matching using O*NET; apprenticeship/trades finder using official apprenticeship listings where practical; aid/grants and FAFSA educational guidance; career progression scenario editor; educator dashboards with school privacy review; PWA/mobile experience; regional data refresh automation; AI assistant for explaining tradeoffs (never as the unverified source of numbers).

---

## 13. Focused tests (implement as targeted test cases; do not run repeatedly)

- SOC/CIP formatting preserved exactly; one-to-many and many-to-many mappings correct.
- Same school/program can map to multiple occupations; same occupation can map from multiple programs.
- BLS metro jobs resolve by valid CBSA, not fuzzy city name guessing.
- Suppressed/null wage and college earnings never become `$0` or invented averages.
- Education costs are not summed as if institution tuition = net price + cost of attendance.
- Tax brackets calculate progressively with clear simplifications.
- Loan payment correct for zero interest, positive interest and zero term validation.
- Mortgage and rental expense categories mutually exclusive where applicable.
- Single and two-earner calculations supported without double-counting wages/taxes.
- Scenario results reflect exact data vintage and assumptions.
- Mouse drag/drop, touch add/remove, keyboard select/remove and screen-reader alternatives reach identical scenario states.
- A tile added, edited, or removed changes numeric budget results without a full page reload, and Undo restores the previous values.
- Fast successive city/career changes do not overwrite newer results with late API responses.
- Compare scenarios remain independent when editing one column; mobile layouts remain usable without horizontal overflow.
- Users can create a first scenario and see a result without navigating through multiple pages or mandatory registration.
- Public APIs validate and rate-limit requests; admin imports require authentication.
- Basic responsive smoke test at mobile and desktop widths.

---

## 14. Environment and deployment

`.env.example` should include:

```dotenv
APP_ENV=development
APP_PORT=42005
APP_BASE_URL=http://127.0.0.1:42005
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=futurepath
DB_USER=futurepath_app
DB_PASSWORD=CHANGE_ME
DB_SSL=false
COLLEGE_SCORECARD_API_KEY=
CENSUS_API_KEY=
ONET_USERNAME=
ONET_PASSWORD=
IMPORT_STORAGE_PATH=./storage/imports
APP_SECRET=REPLACE_WITH_RANDOM_SECRET
ADMIN_INITIAL_EMAIL=
ADMIN_INITIAL_PASSWORD=
```

Do not commit a populated `.env`. Provide MariaDB database/user creation directions with least-privilege grants. Pin tested compatible versions of Lucee/CommandBox/MariaDB driver rather than assuming latest versions work. Include `box server start` and datasource setup documentation, plus a Docker Compose **optional** development MariaDB container for convenience.

Production design: secure reverse proxy/TLS, routine backups, background/scheduled data imports with limited concurrency, source caching, monitoring, rate limiting and audit logs. No commercial paid provider required for basic MVP.

---

## 15. Final outputs expected from Claude Code

1. Running Lucee website with responsive landing page, wizard and dashboard.
2. MariaDB migrations, indexes, seed/reference data and safe local configuration.
3. Working public data import pipeline, with real source data and warnings when unavailable.
4. Search and calculations through actual JSON endpoints.
5. School → program (CIP) → candidate careers (SOC) → local BLS wage → lifestyle simulation.
6. Reverse search from chosen dream life to potentially affordable career choices.
7. Admin interface for data refresh and provenance.
8. README with exact install/start commands and public data setup.
9. Documented formula assumptions, limitations and focused tests.

## 16. First action for Claude Code

**Start Phase 1 now.** First establish the project structure, `server.json` with HTTP port **42005**, `.env.example` with `APP_PORT=42005` and `APP_BASE_URL=http://127.0.0.1:42005`, MariaDB migrations and a working homepage. Then implement and import real BLS OEWS wages for at least Orlando, New York and Washington metro areas if published. Build occupation autocomplete + sourced wage output. Proceed automatically to Phase 2 after the initial startup smoke check, then implement Phases 3 and 4 continuously. Run one final focused verification at the end; do not repeatedly rebuild or audit between phases. Report implemented files, any blocked integrations, and exact run instructions. Do not repeatedly stop to re-plan or rerun the full build.

---

*This specification is intended for educational simulation, not individual financial, tax, lending or career-placement advice. Data source fields and API availability should be verified against current official documentation at implementation time.*

---

# 17. REQUIRED UPDATE — Smart Life Defaults, Life-Stage Expenses, and Future Timeline (October 2026)

> **Applies to the EXISTING application, not a greenfield rebuild.** This section supersedes any earlier assumptions or UI flow that require users to manually configure every milestone, use a single fixed median salary for life, or charge constant child expenses forever. Preserve all existing working functionality, data imports, scenario history, drag/drop, undo/redo, compare, and authentication. Do not discard current user scenarios or reset the database.

## 17.1 Claude Code execution directive — implement straight through

- **Use port 42005** consistently (`http://127.0.0.1:42005/builder`); do not use another port or restart a working server just to check progress.
- **Direct-build mode:** Inspect only the files needed once, implement database/model changes first, then calculations, then UI, then integration. No repetitive planning, approvals, status recaps, rebuilds, browser loops, full-project audits or repeated validation after each edit.
- Keep current service/API conventions and UI framework; extend rather than rewrite. Apply additive, idempotent migrations preserving saved scenarios.
- Perform focused tests on essential financial behaviors and one final smoke check. Targeted reruns only when failures warrant them. Do not skip correctness checks involving money, dates, data source validity or state persistence.
- Do not invent statistical benchmarks or claim invented ages are government-derived. Store all defaults with provenance and vintage, and mark fallback assumptions as `illustrative_assumption`.
- Do not commit or push changes; leave final review and commit to the user.

## 17.2 Outcome and design principle

**The first Future Builder render must show a complete, usable illustrative future** after choosing a city and career (or use the current preselected city/career), with editable defaults rather than an empty questionnaire. All adjustments should recalculate without a page refresh. Use accessible direct manipulation, inline editing, and touch-friendly interactions to minimize clicks.

Separate these three concepts everywhere:

1. **Desired age:** when the student wants an event.
2. **Benchmark age:** a sourced national/appropriate-population descriptive statistic, if available.
3. **Estimated affordable/feasible age:** calculated based on projected finances, prerequisites, and explicitly described assumptions, which may be `not reached`.

Do NOT equate typical national age with an individually predicted age. Do NOT financially determine whether a person may have children; calculate cost and effects on other goals, not whether family formation is permitted.

## 17.3 Initial defaults (editable, not hard-coded as universal truth)

Supply an initial scenario when no saved scenario exists. Load dated records in `life_event_benchmarks` when validated; otherwise use explicitly labeled starter assumptions:

| Setting | Starter assumption / rule | Type |
|---|---|---|
| Starting age | 18 (or current chosen age) | planning setting |
| Work start | Based on education length/training/licensing; initial illustrative age 22 for four-year bachelor's route, 18 for work-now route | model logic / illustrative |
| Income | Entry-stage **local occupation wage**, not median treated as starting wage; grow by experience and scenario | derived estimate |
| Child 1 | age 28 | illustrative starter, editable/remove |
| Child 2 | age 31 | illustrative starter, editable/remove |
| First home goal | age 40 | editable goal; benchmark may use NAR first-time-buyer median with year/method shown |
| First car | configurable early adulthood goal, only when selected | illustrative |
| Retirement goal | age 67 | illustrative planning assumption, not universal statistic |
| Existing savings/debt | never silently assume substantial assets or debt; make defaults zero or clearly labeled | illustrative |

Default number of children to two for the demonstration only if the user explicitly chose a family or selected the 'sample future' template. In a neutral/default scenario, show family planning suggestions without implying everyone will have children; a simple toggle may initialize two children. Persist user overrides, including none, and never reapply smart defaults to override edits.

Benchmarks must carry `metric`, `population`, `geography`, `source_name`, `source_url`, `reference_year`, `value`, `methodology_note`, `updated_at`. Sources to investigate/verify: CDC/NCHS first-birth statistics, NAR first-time-homebuyer ages, BLS OEWS salary distributions, Census ACS age/occupation earnings, BLS employment and education, HUD/Census housing, regional childcare prices (e.g., state childcare market-rate surveys / licensed datasets). Not every item has an API; support verified CSV downloads and local versioned imports. Distinguish median from mean, first-birth **maternal** age from general parent age, and first-time buyers from all households.

If verified statistical data cannot be obtained, render an editable sample scenario with `Illustrative starting assumption` and no government provenance label. Do not block the entire build on external API credentials.

## 17.4 Life events and child expense schedule

Each event has an editable desired age (plus optional partner/child attributes), enable/disable, and source/assumption marker. Allow multiple children independently: child 1 desired birth age 28 and child 2 age 31 in example. An event can be moved by dragging its marker along the life timeline, by keyboard, or via a numeric age input; all methods must produce the same state.

For each modeled year `y` and each child `i`: `childAge = y - parentAgeAtBirth_i` (if negative, not yet born; age >= 0 is active). Calculate different expense categories per year and region; allow childcare options (parent at home, informal care, part-time, full-time daycare, after-school/summer care) and optional college support.

| Child age | Categories / lifecycle |
|---|---|
| 0–2 | Infant/toddler childcare, food, supplies, health costs |
| 3–4 | Preschool/daycare, food, clothing, healthcare |
| 5–12 | School-related expenses, optional after-school/summer care; **full-time infant daycare ends** |
| 13–17 | Teen expenses and optional activities/transport |
| 18–22 | Optional support, college and/or living at home; no automatic daycare |
| 23+ | Default dependent costs end unless explicitly extended |

Use sourced local costs wherever available; fallback inputs are visibly labeled editable illustrative assumptions, not asserted averages. Avoid charging full daycare if an alternate care arrangement is selected. Prevent double-counting food/housing/healthcare in adult baseline expense assumptions and household scaling. Child expenses must overlap naturally across siblings and change as their ages change. Sample scenario: at parent's age 40, children born at ages 28/31 are 12 and 9, not infants.

## 17.5 Year-by-year career income engine

Replace fixed lifetime 'median' wage with an annually computed career earnings trajectory, spanning ages 18–95 or through death horizon, depending on simulation settings:

- Recognize school/training/credentialing and realistic entry-to-occupation age; students do not receive professional wages before qualification, and may receive part-time wages if specified.
- For the chosen metro and SOC occupation, distinguish entry estimate, local 25th/50th/75th percentile wages and experience progression; percentiles **must not** be represented as observed career advancement data.
- Prefer a verified age/occupation earnings profile from Census or a relevant wage schedule when feasible; otherwise use a labeled assumption-driven progression calibrated to local BLS wage quantiles: early-career / mid-career / later-career plateaus. Do not guarantee promotions or automatic progression to the 90th percentile.
- Offer **Conservative / Typical / Faster** trajectories; optionally adjust real wage growth, promotion potential, career break, unemployment periods, and retirement age. A user-edited starting salary overrides the entry estimate if explicitly selected.
- Wage projections by year in **constant today's dollars by default**. Model real raises separately from price inflation. If offering nominal dollars, label them and apply inflation consistently to both income and expenses; never mix nominal income with real expenses.
- Calculate annual net income using the app's existing tax model, filing status and locality assumptions; age-based housing, education loan, benefits, and childcare expenses also update each year. Show methodology, uncertainties and published vintage.
- Plot annual salary over time with proper data points. Example labels: starting salary, expected mid-career, near-retirement. Never claim an unsourced example is BLS-observed.

## 17.6 Affordability engine and milestone outcomes

Use annual discrete cashflow / balances, not a single age-20 snapshot multiplied forward. For each age, compute wages, taxes, housing, loans, child costs, car costs, savings, retirement contributions, investment growth, debt and cashflow, all consistent in inflation basis. Show **desired** vs **estimated affordable** ages where calculable; explicitly report when no affordable age occurs before a horizon.

Home readiness must consider down payment, closing costs, emergency reserve, monthly payment (interest, taxes, insurance, HOA/maintenance where relevant), existing debt, and down-payment saving. Do not magically grant a mortgage just because a national benchmark age is reached. Mortgage affordability calculations are educational estimates, not lender decisions.

Car readiness must consider purchase, financing/lease if chosen, insurance, fuel, maintenance and replacement cycle. Retirement readiness must consider pre-retirement saving, drawdown, pension/Social Security as explicitly modeled, longevity through e.g. 95, and an editable return assumption; don't assert guaranteed retirement funding.

For goals with no single objective financial 'ready' age (marriage/children), show the **financial impact at desired age** and tradeoffs, not a delayed-or-forbidden result. If a goal is affordable later, recommend one or more changes with transparent math (lower home budget, different city, more saving, other career) rather than simply `Goal delayed`.

Display concise reason strings: `Home at 30: estimated at 37 (+7 years)`, `Child at 29: childcare increases spending through age 4`, `Retire at 65: funding gap of $X in today's dollars`, and a `Why?` disclosure for assumptions.

## 17.7 UI change — make timeline the primary navigation

Place **Your Future at a Glance / Your Life Journey** near the top of `/builder` instead of burying it below the forms. Desktop: visible age timeline plus compact goal summary, inputs on the side or in collapsible drawers. Mobile: horizontally scrollable/swipeable timeline with sticky chosen-age summary, no overflow or tiny targets. Keep the existing Career / City / Dream components but condense them.

- Default milestone ages 20, 30, 40, 50, 60, 70; optional yearly slider covering at least ages 18–95 (event-specific details). Selecting an age updates inline income, spending, children's ages, housing, debt/savings and upcoming event without navigation.
- On timeline, show distinct icons for career start, children, home, car and retirement. Drag events to desired age with immediate recalculation; support accessible age input and keyboard alternative. Keep undo/redo functional.
- Show a compact status for each age: **On track, Adjustments needed, Not affordable yet, Retired**. Avoid six nearly identical `Working/Renting/Goal delayed` cards. State important milestone differences.
- Use a succinct top summary: `X goals on track • Y delayed • Z need changes`, as applicable. Status should be based on consistent criteria; a positive monthly balance at one age does not override a long-horizon shortage.
- Inline edit via chips/popovers for city, career, children, home goal age/price, retirement age. Avoid launching modal wizards for every change.
- Always show annual or monthly units, real/nominal basis, and `Based on [data year] + editable assumptions`. Tap `How calculated?` for source/method details rather than cluttering the main screen.
- Offer `Make My Dream Possible` suggestions ranked by impact, showing financially feasible alternatives (e.g., smaller home, delay home age, different occupation or metro) without claiming the recommended career is guaranteed accessible.
- Compare two saved independent scenarios side-by-side. Any change to one should not silently modify the other. Preserve share URLs/serialization behavior.
- Debounce expensive client calculations; cancel/ignore stale API responses so fast interactions never show obsolete numbers. Use incremental UI updates, not full reloads.

## 17.8 Suggested MariaDB changes (adapt to existing schema)

Do not blindly create duplicate tables. Extend existing tables where possible. Suggested structures/fields:

```sql
CREATE TABLE IF NOT EXISTS life_event_benchmarks (
  benchmark_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  metric VARCHAR(120) NOT NULL,
  population VARCHAR(255) NULL,
  geography VARCHAR(120) NOT NULL DEFAULT 'US',
  source_name VARCHAR(255) NOT NULL,
  source_url VARCHAR(1000) NULL,
  reference_year SMALLINT NULL,
  numeric_value DECIMAL(12,3) NULL,
  methodology_note TEXT NULL,
  value_type VARCHAR(40) NOT NULL DEFAULT 'observed_statistic',
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_benchmark_metric (metric, geography, reference_year)
);

CREATE TABLE IF NOT EXISTS scenario_life_events (
  event_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  scenario_id BIGINT NOT NULL,
  event_type VARCHAR(50) NOT NULL,
  event_label VARCHAR(120) NULL,
  desired_age DECIMAL(5,2) NOT NULL,
  enabled TINYINT(1) NOT NULL DEFAULT 1,
  settings_json LONGTEXT NULL,
  sort_order INT NOT NULL DEFAULT 0,
  INDEX idx_scenario_event (scenario_id, event_type)
);

CREATE TABLE IF NOT EXISTS occupation_earnings_profiles (
  profile_id BIGINT AUTO_INCREMENT PRIMARY KEY,
  soc_code VARCHAR(16) NOT NULL,
  cbsa_code VARCHAR(10) NULL,
  age_from SMALLINT NOT NULL,
  age_to SMALLINT NOT NULL,
  earnings_amount DECIMAL(14,2) NOT NULL,
  dollar_year SMALLINT NOT NULL,
  source_name VARCHAR(255) NOT NULL,
  source_url VARCHAR(1000) NULL,
  method_type VARCHAR(60) NOT NULL,
  imported_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_earnings_soc (soc_code, cbsa_code, age_from)
);
```

Use existing project patterns for PK/FK ownership, migration versioning, ownership checks, referential integrity, indexes and JSON validation. Update scenario serialization and API response schema to include events, benchmark metadata, chosen career trajectory, and per-year outcomes. Add migration backfill logic that respects prior saved scenario settings.

## 17.9 APIs / calculation service (adapt existing routes)

Expose, or extend existing, equivalent capabilities:

- `GET /api/life-defaults?city=...&occupation=...&educationRoute=...` → suggested ages, wage trajectory defaults, provenance, fallback labels.
- `GET /api/life-benchmarks` → dated statistics with source, population and confidence/limitations metadata.
- `POST /api/scenarios/{id}/simulate` or existing simulator route → per-year ledger ages 18–95, milestone affordable ages, goal gaps and explanations.
- Existing scenario update endpoint supports add/move/remove life events and salary track changes; server validates ages, child counts and missing sources.
- Reuse existing import/admin tools for source updates; do not fetch government APIs on every slider movement. Cache normalized records by metro/SOC/vintage.

Illustrative response format (not claimed as observed results):

```json
{
  "baseDollarYear": 2026,
  "basis": "real",
  "careerTrack": "typical",
  "ages": [{"age": 40, "grossIncome": null, "takeHome": null, "children": [{"age": 12},{"age": 9}], "expenses": {"housing": null,"childcare": null}, "cashFlow": null}],
  "goals": [{"type": "home","desiredAge": 30,"estimatedAffordableAge": null,"status": "not_yet_determined","reason": "Requires local housing and income inputs"}],
  "sources": [],
  "warnings": ["Amounts unavailable until validated datasets or editable assumptions are present"]
}
```

## 17.10 Required financial test cases (focused, not repetitive)

1. Ages 28/31 child births: at parent age 30, children ages 2 and not-yet-born; at age 40, ages 12 and 9. Infant daycare ends after the configured age, school/after-school costs evolve, and overlapping expenses sum correctly.
2. For a bachelor's career, professional earnings start only when qualified; work-now route may begin earlier. Typical wages rise in real terms only according to documented trajectory; conservative/typical/faster produce ordered results where assumptions support it.
3. Changing child birth age changes childcare start/end years and cumulative savings, not only the current card.
4. Desired home at 30, affordable at 37: show both dates and +7 years, without auto-purchasing at 30 or 40.
5. No reachable home/retirement milestone displays `Not achievable under current assumptions` instead of a fabricated age.
6. Two scenario comparisons remain independent; undo/redo and share links round-trip life events and salary tracks.
7. Numeric results remain consistent when selecting age 20, 30, 40, 50, 60, 70 versus the year-by-year engine; no double-counted rent/home, daycare, inflation, or loan costs.
8. Source-unavailable conditions render `Illustrative assumption` / `Data unavailable`, never silent factual-looking estimates; desktop and mobile interactions remain usable.

## 17.11 Acceptance criteria and implementation order

Implement in this order, continuously: (1) additive migrations and scenario compatibility, (2) benchmark/default loader with source-year labels, (3) yearly salary and life-stage/child expense engine, (4) milestone affordability and goal-gap explanations, (5) primary timeline UI and inline editable events, (6) comparisons, caching, documentation, final focused validation.

**Done when:** a new visitor sees a coherent editable sample future quickly; choosing a career and city creates a sourced or clearly labeled trajectory; each child's care costs phase out; the user can drag a desired house or birth milestone to a different age and see annual results change immediately; desired vs affordable goal ages appear where appropriate; the UI clearly explains why a goal is delayed and what could change it; saved scenarios still work; app remains on **42005**.

### Exact build command for Claude Code

> Read `FuturePath_Claude_Code_Build_Spec.md` completely. Update the **existing** FuturePath project to implement **Section 17** without rewriting working features. Work straight through, choose sensible implementation details yourself, keep CommandBox port **42005**, minimize repeated checks/restarts, and do **not commit or push**. Run focused calculation tests and one final smoke check, then report the result and any real data gaps.
