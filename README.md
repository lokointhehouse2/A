# FuturePath

**Dream big. See what it takes.** An education, career and future-lifestyle simulator for teenagers.

Pick a city, a lifestyle (apartment or house, cars, kids, travel, savings), and a career or school path. FuturePath then shows estimated take-home pay against monthly costs, using real public U.S. data with the source and year on every number. It can also work backwards from a dream life to the careers whose local wages could support it.

- **Stack:** Lucee 6.2 (CommandBox), MariaDB, server-rendered CFML, Bootstrap 5 (vendored), vanilla JS.
- **Port:** the app always runs on **http://127.0.0.1:42005**. If the port is taken, the scripts stop and report the conflict.
- **Data:** BLS OEWS wages (May 2025), BLS Employment Projections (2025–35), NCES CIP 2020 to SOC 2018 crosswalk, HUD Fair Market Rents (FY2027), Census ACS 2020–2024 5-year (rent by bedrooms, home value), College Scorecard, IRS/SSA and state tax rules (2026), USDA food plans (Aug 2026) and federal student-loan rates (2026–27). See [docs/DATA_SOURCES.md](docs/DATA_SOURCES.md).

## Quick start (Windows)

Requirements:
- CommandBox 6.x (`box`, or `C:\App\box.exe`)
- Docker Desktop (for the optional dev MariaDB on port 3308), or any MariaDB 10.6+ server
- Node 18+ (only for the JS engine tests)

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
```

`setup.ps1` works through these steps:
1. Creates `.env` from `.env.example` with random local passwords.
2. Starts the MariaDB container `futurepath-mariadb` on `127.0.0.1:3308`.
3. Installs TestBox.
4. Runs `box server start`.

On first start the app:
1. Applies `db/migrations` and `db/seeds`.
2. Creates the admin user from `ADMIN_INITIAL_EMAIL` / `ADMIN_INITIAL_PASSWORD`.
3. Imports public data in the background from `storage/imports/raw`.

If no raw files are present, it first downloads them from the official sources (`IMPORT_AUTO_DOWNLOAD=true`). Import takes about 2 minutes.

> **BLS downloads need a contact email.** BLS blocks automated downloads unless the User-Agent identifies a contact (its published usage policy). Set `BLS_CONTACT_EMAIL` in `.env`, or download `oesm25ma.zip`, `oesm25nat.zip`, `education.xlsx` and `occupation.xlsx` in a browser and upload them at `/admin/imports`.

Everyday commands:

```powershell
scripts\start.ps1          # start DB + app
scripts\stop.ps1           # stop app   (scripts\stop.ps1 -Database also stops MariaDB)
scripts\smoke.ps1          # one focused smoke check against the running app
scripts\run-tests.ps1      # JS engine tests + TestBox + headless browser UI tests
box server log             # Lucee/CommandBox log
```

Manual equivalent: `docker compose up -d`, then `box server start` (uses `server.json`: Lucee 6.2.7+16, Java 21, port 42005).

### Database without Docker

Create the database and a least-privilege user:

```sql
CREATE DATABASE futurepath CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'futurepath_app'@'%' IDENTIFIED BY '<strong password>';
-- Development (the app applies its own migrations on start):
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON futurepath.* TO 'futurepath_app'@'%';
-- Production: run migrations with a separate admin account, set DB_AUTO_MIGRATE=false and APP_ENV=production,
-- and give the app user only: GRANT SELECT, INSERT, UPDATE, DELETE ON futurepath.* TO 'futurepath_app'@'%';
```

Then set `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER` and `DB_PASSWORD` in `.env`. Secrets are never committed; `.env` is gitignored.

## What's where

| Path | Purpose |
|---|---|
| `Application.cfc`, `index.cfm` | Bootstrap (datasource, migrations, security headers) and front controller (routing, rate limit, CSRF, admin auth) |
| `config/` | `Routes.cfc`, `Beans.cfc` (service wiring), `AppConfig.cfc`, `assumptions.json` (editable defaults) |
| `db/migrations`, `db/seeds` | Numbered SQL: schema (001–005), sources, states, tax rules, loan rates, pathways, USDA food costs |
| `modules/careers` | `OccupationService`, `WageService` (OEWS with explicit availability status) |
| `modules/education` | `InstitutionService`, `ProgramService`, `CareerMappingService` (CIP to SOC) |
| `modules/geo`, `modules/housing` | CBSA metros; ACS/HUD rent and home-value benchmarks with explicit geography mapping |
| `modules/finance` | `TaxEstimatorService` (versioned tax packs), `LoanCalculatorService` |
| `modules/simulator` | `LifestyleSimulatorService` (pure calculation), `ReverseCareerSearchService`, `ReferenceDataService`, `ScenarioStore` |
| `modules/imports` | `ImportRunner`, streaming `XlsxStreamReader`, OEWS/EP/CIP–SOC/HUD/ACS/Scorecard importers, allowlisted `ImportConnectors` |
| `api/v1` | JSON API controllers |
| `controllers`, `views` | Pages and admin |
| `assets/js` | `engine.js` (browser mirror of the calculation engine), `builder.js` (Future Builder), `common.js` |
| `tests/` | TestBox specs, JS engine tests, shared fixtures, browser UI tests |

## JSON API (v1)

| Method | Endpoint | Notes |
|---|---|---|
| GET | `/api/v1/geographies?q=orlando` | Metro (CBSA) search |
| GET | `/api/v1/geographies/{cbsa}` | Metro + housing benchmarks |
| GET | `/api/v1/occupations?q=carpenter&cbsa=36740` | SOC search with local availability |
| GET | `/api/v1/occupations/{soc}/wages?cbsa=&year=` | Local and national wages, percentile definitions, provenance |
| GET | `/api/v1/occupations/{soc}/pathways` | Training routes (BLS typical entry education) |
| GET | `/api/v1/institutions?q=&state=FL&cip=23.01` | College search |
| GET | `/api/v1/institutions/{unitid}` | Costs and completion |
| GET | `/api/v1/institutions/{unitid}/programs` | Programs with observed field-of-study outcomes |
| GET | `/api/v1/programs?q=english`, `/api/v1/programs/{cip}/careers?cbsa=` | Fields of study; possible careers (crosswalk) |
| GET | `/api/v1/reference/bundle?cbsa=&socs=&state=&nyc=&unitid=` | Everything the browser needs to recalculate locally |
| POST | `/api/v1/simulations/calculate` | `{ scenario }` gives the authoritative budget |
| POST | `/api/v1/simulations/reverse-careers` | `{ scenario, options }` gives the required pay plus matching careers |
| POST | `/api/v1/simulations/compare` | `{ scenarios: [..3] }` |
| POST/GET | `/api/v1/scenarios`, `/api/v1/scenarios/{uuid}` | Optional anonymous saved scenario (config only) |
| GET | `/api/v1/sources/status`, `/api/health` | Data vintages; health |

Responses use `{ success, data, message }`, and errors return `{ success:false, error:{ code, fields } }`. Status codes are 400, 404, 405, 413, 415, 422, 403 for cross-origin POSTs, and 429 when the per-IP limit (`API_RATE_LIMIT_PER_MINUTE`) is exceeded.

## Admin

`/admin` requires sign-in with Argon2id password hashes, session rotation, login throttling and CSRF tokens on every form. It provides:
- A source catalogue with current vintages and row counts.
- Import history with checksums.
- Upload with a preview before commit.
- "Download latest" through allowlisted official URLs only.
- Background re-imports.

## Tests

- `node tests/js/engine.test.js` checks the browser engine against frozen fixtures plus hand-checked tax and loan cases. `--generate` (with the server running) rebuilds the fixtures from live data and asserts that the JS engine equals the server's CFML engine.
- `/dev/tests` (development only) runs the TestBox specs: engine fixtures, taxes, loans, rent/mortgage exclusivity, validation, data integrity (code formats, many-to-many crosswalk, suppressed values never zero, CBSA resolution, HUD partial areas), API validation, rate limiting and admin protection.
- `/dev/ui-tests` (development only) drives the real builder. It checks that drag-and-drop and buttons produce identical states, that undo/redo and remove work, that rapid city changes never leave stale results, that compare columns stay independent, and that the 375px layout has no horizontal overflow.

## Privacy and safety

Anonymous by default: no accounts, names, ages, addresses or grades. Scenarios live in the browser, and saving to local storage is opt-in. Share links carry only scenario settings. There are no trackers, ads or third-party scripts; a strict CSP allows same-origin content only. See `/privacy`.

## Known limitations

See [docs/ASSUMPTIONS.md](docs/ASSUMPTIONS.md). The main ones:
- State income tax is modeled for FL, NY + NYC, DC (latest published 2025 rules), VA and the states with no wage tax. NJ and MD residents (parts of the NYC and DC metros) see a "not modeled" warning.
- College Scorecard uses the rate-limited `DEMO_KEY` until `COLLEGE_SCORECARD_API_KEY` is set. 34 schools in Orlando, Manhattan and Washington DC are imported by default.
- The Census Data API now requires a key; FuturePath reads the key-free ACS summary files instead.
- Nonmetropolitan (balance-of-state) OEWS areas are not imported.
