# Formulas, assumptions and limitations

FuturePath produces **educational scenarios**, not predictions or advice. Calculations are deterministic: the same scenario plus the same data vintage always gives the same result. The server (`modules/simulator/LifestyleSimulatorService.cfc`) and the browser (`assets/js/engine.js`) implement the same algorithm and are tested against the same fixtures.

## Income

```
annualGross_i      = occupationalWage_i(percentile, metro) x workFraction_i      (or a custom wage)
pretaxRetirement_i = annualGross_i x retirementPct
taxes              = federalIncomeTax - childTaxCredit + stateIncomeTax + localIncomeTax + socialSecurity + medicare + additionalMedicare
monthlyTakeHome    = (sum annualGross - taxes - sum pretaxRetirement) / 12
```

- **Wage percentiles** (10th, 25th, median, 75th, 90th, mean) describe how pay is spread across current workers in that metro. They are **not** a career ladder or years of experience.
- An unpublished wage (`not_published`, suppressed `*`, or top-coded `#`) is never replaced by a number. The result is marked incomplete and explains why, and the user can enter a custom wage.

## Taxes (simplified estimator; not tax advice)

- Wages are the only income, and the standard deduction is always used. There are no itemized deductions, personal exemptions, EITC or state credits.
- Federal: 2026 progressive brackets on (wages − pre-tax retirement − standard deduction).
- Child Tax Credit:
  - $2,200 per child, phased out by $50 per $1,000 above $200k (single/HoH) or $400k (MFJ).
  - The non-refundable part is limited to tax.
  - The refundable part is limited to $1,700 per child and to 15% of earnings above $2,500.
- Payroll: Social Security at 6.2% up to $184,500 per earner, Medicare at 1.45%, plus 0.9% additional Medicare above $200k (single/HoH) or $250k (MFJ). Pre-tax retirement contributions do **not** reduce FICA.
- State taxable income = federal AGI − state standard deduction (simplification). New York's supplemental "recapture" tax for high incomes is not modeled.
- **Modeled:** FL, TX, NV, WA, TN, SD, WY, AK and NH (no wage tax); NY and NYC (2026); DC (2025 rules, the latest published); VA (2026). **Not modeled:** all other states. The result shows a warning, and take-home pay is overstated for those residents.
- **Two earners:**
  - Married filing jointly files one joint return.
  - Any other status files two separate returns: earner 1 with the chosen status and the children, earner 2 as single. Wages and taxes are never double-counted.

## Monthly costs

```
monthlyCosts = housing + transportation + groceries + eating out + childcare + health + phone/internet
             + other personal + student loan payment + travel + savings
monthlySurplus     = monthlyTakeHome - monthlyCosts
affordabilityRatio = monthlyCosts / monthlyTakeHome   (when take-home > 0)
```

Pre-tax retirement is already removed from take-home pay, so it is **not** counted again in costs.

| Category | Basis |
|---|---|
| Rent | **Sourced:** ACS median gross rent for the CBSA by bedrooms (default), or HUD FMR. Gross rent includes utilities, so no separate utilities line is added for renters. If the chosen benchmark is missing, the other is used **with a visible warning**; if both are missing, the line shows "Missing". Roommates split rent evenly. |
| Buying a home | Price = ACS median home value (sourced) or the user's price. Mortgage P&I uses standard amortization. Property tax, homeowner's insurance, PMI (when the down payment is under 20%), maintenance, HOA and owner utilities are **editable assumptions**. Down payment and closing costs appear as upfront cash. **House and apartment are mutually exclusive**: if both are chosen, only the house counts. |
| Cars | Loan on (price − down payment), plus insurance and gas/maintenance, all editable assumptions. With no car, a transit pass per adult. |
| Groceries | **Sourced:** USDA Moderate-Cost plan, U.S. average (Aug 2026). Adults use the average of female and male 19–50; children use the chosen age band. USDA size adjustment: 1 person +20%, 2 people +10%, 3 people +5%, 5–6 people −5%, 7+ people −10%. |
| Eating out, phone/internet, health, other personal, childcare, travel, savings | Editable assumptions (see `config/assumptions.json` and `/sources`). |
| Student loan | Borrowed = years × max(0, yearly price − extra scholarships − family/work contribution), where yearly price is the Scorecard average net price or the user's figure. Repaid over 10 years at the 2026–27 federal rate. Interest during school is not included. |

## Education

- Average net price already subtracts average grants for aid recipients. "Extra scholarships" means aid beyond that average.
- Tuition, cost of attendance and net price are separate measures and are never summed.
- Program earnings (College Scorecard) and occupational wages (BLS) are different measures and are always shown separately.
- The CIP to SOC crosswalk lists **possible** occupations only. Some need licenses or further education: K–12 teachers need a state license, professors usually need a doctorate, and physicians need medical school plus residency.
- Pathway lengths (`education_pathways`) are typical full-time durations and are labeled as such.

## Reverse search

Required pay is the smallest gross annual pay for earner 1 at which take-home covers monthly costs. It is found by bisection over the same tax calculator, because net-to-gross is not a fixed percentage; earner 2 is held fixed. Every occupation with a published wage at the chosen percentile in the metro is compared with it:
- **Could cover it** (wage ≥ need) can be sorted by local jobs, shortest typical training (BLS entry education), BLS projected growth, or most room to spare.
- **Close, with a tradeoff** lists the nearest options below the need. Lower-paying careers stay visible.
- Occupations without a published wage are counted, not ranked.

## Timeline

- **Today's dollars** (default): wages and costs stay at today's level.
- **Projected:** wages grow by (1 + inflation) × (1 + real raise) − 1 per year, and costs grow by inflation. Both rates are user assumptions.
- School years show yearly out-of-pocket cost and the borrowed balance. Living costs during school are not modeled.
- "Saved/short so far" is the cumulative cash surplus, not invested.
- Taxes in later years use the current year's rules.

## Not modeled (MVP)

- Raises tied to experience, and unemployment spells (set part-time or a custom wage instead).
- Local price differences for food, childcare, insurance and transportation (these are national or assumption values).
- Residency pay and franchise-owner income: ownership isn't an ordinary wage and is not simulated.
- O*NET interests, apprenticeship listings, FAFSA guidance and educator dashboards (Phase 5).
