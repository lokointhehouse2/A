# Data sources

FuturePath stores versioned copies of public datasets in MariaDB. Every import is recorded in `data_import_runs` with the source, file name, vintage, SHA-256 checksum, row counts, warnings and who triggered it. The site reads only from the database; it never calls external APIs on user interactions.

Imported in this build (October 2026):

| Dataset | Source and URL | Vintage | Import | Rows | Notes |
|---|---|---|---|---|---|
| Occupational wages by metro | BLS OEWS, https://www.bls.gov/oes/tables.htm (`oesm25ma.zip` → `MSA_M2025_dl.xlsx`) | May 2025 | `BlsOewsImporter` (streaming XLSX) | 141,408 wage rows, 393 metros | `*` wage not available, `**` employment not available and `#` top-coded at $115/hr or $239,200/yr are stored as **NULL** with `suppression_code` / `topcoded_fields`, never 0. `ANNUAL=TRUE` / `HOURLY=TRUE` flags are kept. Metros are keyed by published CBSA code. |
| National wages | BLS OEWS (`oesm25nat.zip`) | May 2025 | same | 831 occupations | Shown only as a labeled "U.S." reference, never silently substituted for local wages. |
| Entry education, training, projections | BLS Employment Projections, https://www.bls.gov/emp/tables.htm (`education.xlsx` Table 5.4, `occupation.xlsx` Table 1.2) | 2025–35 | `BlsProjectionsImporter` | 831 | Drives `occupation_profiles` and `occupation_pathways` (status "common" or "alternative"; never claimed as legally required). |
| Program to occupation crosswalk | NCES, https://nces.ed.gov/ipeds/cipcode/Files/CIP2020_SOC2018_Crosswalk.xlsx | CIP 2020 / SOC 2018 | `CipSocImporter` | 5,903 links | Many-to-many. "NO MATCH" rows are skipped (194). CIP codes keep their dotted text form (`01.0000`). Shows what programs prepare people for, **not** where graduates work. |
| Fair Market Rents | HUD, https://www.huduser.gov/portal/datasets/fmr.html (`FY27_FMRs.xlsx`) | FY2027 | `HudRentImporter` | 13,030 | Stored per HUD FMR area. `geo_source_mappings` links each area to a CBSA as `exact` (e.g. `METRO36740M36740`) or `partial` (e.g. `METRO35620MM5600`, the New York HUD area that covers only part of the NY CBSA). FMR is a policy benchmark (about the 40th percentile gross rent), not a median or a listing price. |
| Median gross rent by bedrooms | Census ACS 5-year table-based summary file `acsdt5y2024-b25031.dat` (https://www2.census.gov/programs-surveys/acs/summary_file/2024/table-based-SF/) | 2020–2024 | `CensusAcsImporter` | 6,545 | CBSA rows (`310M…US<CBSA>`) only, with margins of error. Gross rent includes utilities. The Census Data API now requires a key; the summary files do not. |
| Median home value | ACS `acsdt5y2024-b25077.dat` | 2020–2024 | same | 935 | Owners' estimate of value, not current sale prices. |
| Colleges, costs, completion, fields of study | U.S. Department of Education College Scorecard API, https://collegescorecard.ed.gov/data/api-documentation/ | "latest" release, fetched 2026-10-09 | `CollegeScorecardImporter` | 34 institutions | Fields used are documented in the importer header. Tuition, cost of attendance and average net price are kept separate and never summed. Program earnings (1, 4 and 5 years after completion) and debt are stored as observed outcomes and are often suppressed. |
| Federal and payroll tax rules | IRS Rev. Proc. 2025-32 (https://www.irs.gov/irb/2025-45_IRB); SSA wage base (https://www.ssa.gov/oact/cola/cbb.html) | Tax year 2026 | `db/seeds/103_tax_rules.sql` | — | Brackets for single, MFJ and HoH; standard deductions $16,100 / $32,200 / $24,150; CTC $2,200 ($1,700 refundable); SS wage base $184,500; additional Medicare 0.9% above $200k / $250k. |
| New York State and NYC tax | NY DTF Form IT-2105-I (2026) | 2026 | seed | — | Rate schedules and standard deductions; NYC resident tax applies only when "Live inside NYC" is checked. |
| DC tax | DC OTR | 2025 (latest published) | seed | — | Used for 2026 scenarios with a visible note. |
| Virginia tax | Virginia Tax (deductions page; 2025 Form 760 rate schedule) | 2026 standard deduction; statutory rates | seed | — | |
| States without wage tax | FL, TX, NV, WA, TN, SD, WY, AK, NH | 2026 | seed | — | |
| Student loan rates | Federal Student Aid (Direct Loans first disbursed 7/1/2026–6/30/2027) | 2026–27 | `db/seeds/104_loans_pathways.sql` | — | Undergraduate 6.52%, graduate 8.07%, PLUS 9.07%; 10-year standard repayment. |
| Food | USDA Food Plans: Cost of Food at Home, U.S. average | August 2026 (issued Sept 2026) | `db/seeds/105_food_costs.sql` | 21 | Low, Moderate and Liberal plans for children and adults aged 19–50. FuturePath uses the Moderate plan, with USDA household-size adjustments. |

## Refreshing data

- Use **/admin/imports** to "Download latest" (allowlisted URL templates in `modules/imports/ImportConnectors.cfc`) or to upload a file. Review the preview, then select **Import**.
- Imports are idempotent upserts on natural keys, so re-importing the same file reproduces the same rows. A new vintage adds rows next to the old ones; the app reads the latest year.
- Tax rules, loan rates and food costs are versioned seed files. To update, add a new numbered seed with the new year's rows (from the official publication) and restart in development.

## Verifying field layouts

Before importing a new vintage, verify the file layout (the preview page shows the first rows). The importers check for required headers (e.g. `OCC_CODE`, `A_MEDIAN`, `CIP2020Code`, `hud_area_code`, `fmr_0`…`fmr_4`, `GEO_ID`) and fail loudly instead of guessing.
