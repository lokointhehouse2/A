# FuturePath — Age Timeline and Simplified Budget

## Instructions for Claude Code

Implement this change in the existing FuturePath application. The original `FuturePath_Claude_Code_Build_Spec(3).md` has already been implemented. This is an incremental change specification, not instructions to rebuild the application.

Use the existing Lucee CFML, CommandBox, MariaDB, Bootstrap and JavaScript architecture. Keep HTTP port **42005**. Preserve career, college, geography, lifestyle selection, compare, Undo/Redo, save/share, source disclosures and existing calculation behavior unless explicitly changed below.

Inspect the relevant builder, calculation and scenario persistence files once. Implement continuously without routine approval pauses or repeated audits. Reuse existing services and components. Run focused calculation checks and one final desktop/mobile smoke check. Restart only when a configuration change or diagnosed failure requires it. Do not reinstall, reimport datasets or rebuild the project unnecessarily.

This specification supersedes the original budget dashboard presentation and promotes age progression from an optional expansion to a required feature of the current builder. Original data provenance, privacy, accessibility and security requirements still apply.

## 1. Intended outcome

Replace the visually dense **Your monthly budget** panel with a simple answer and an age-based view of the user's future.

A user should immediately understand:

1. Whether their selected education/career path supports their requested lifestyle.
2. What life could look like at ages **20, 30, 40, 50, 60 and 70**.
3. When each requested goal could be achieved under the selected assumptions.
4. Which goals would be delayed or remain out of reach, and the dollar gap.
5. What an affordable alternative could look like using the same career and education path.

Make the experience friendly, attractive and easy to scan. Keep detailed math available without making it the main experience. Use **projected outcomes**, not claims about what will actually happen.

## 2. Page layout

Retain the existing location, career/education and lifestyle builder controls. Replace the current tall right-hand budget panel with a compact summary. Below the builder, place **Your Future at a Glance** across the full content width.

Display order:

1. Existing builder controls with compact result summary.
2. Full-width age timeline with six decade cards.
3. Requested goals and projected goal dates.
4. Requested lifestyle versus affordable alternative when applicable.
5. Three actions: **Adjust my lifestyle**, **Compare careers**, **Change my goal dates**.
6. Collapsed **See the numbers** and **Sources & assumptions** sections.

On mobile, stack builder panels and show the summary before the timeline. Make decade cards horizontally swipeable with a visible age selector and a clear indication that additional cards exist. Never require swipe or drag: provide selectable age buttons and keyboard navigation. Detailed content must fit the screen without horizontal overflow outside the intentional timeline scroller.

## 3. Simplified monthly summary

Show three primary figures for the selected age and requested scenario:

| Figure | Meaning |
|---|---|
| Monthly take-home | Estimated income after taxes and modeled payroll deductions |
| Planned spending | Living expenses, debt payments and planned post-tax savings allocations |
| Left over / Shortfall | Take-home minus planned spending |

Label the age visibly: **At age 30**. The initial selected age is the user's goal age when available, otherwise 30. If that age is outside the modeled range, choose the nearest valid age and show why.

Use a short overall explanation above the numbers, such as:

- **Your plan looks achievable under these assumptions.**
- **Your future needs a few adjustments.**
- **Your current path does not fund every goal by age 70.**
- **Choose a career and housing to see your future.**

Keep the selected-age cash-flow result distinct from the overall goal summary. A surplus at one age does not mean every goal is achievable, and a deficit during training does not prove the entire plan fails.

Hide gross income, taxes, deductions, detailed categories and expense charts inside **See the numbers**. Preserve all calculations and source disclosures. Missing wages or housing must show **Not available** or **Incomplete**, never a false $0 income or false success/failure verdict.

## 4. Your Future at a Glance

Show six visually consistent cards headed **20 · 30 · 40 · 50 · 60 · 70**. Each card contains:

- Large age heading and one tasteful icon or small illustration.
- One life-stage line, such as **In training**, **Working**, or **Retirement projected**.
- One or two important lifestyle/goal lines.
- A compact financial line: monthly amount left over, shortfall, or goal funding gap.
- A status label with an icon and accessible color.

Limit each card to a few short lines. Do not render a miniature spreadsheet in every card.

Selecting a card reveals a single inline detail area showing that age's career/training state, modeled housing, household events, take-home pay, spending, cash savings, investment savings, debt and goal progress. No new page or mandatory modal.

Example presentation only, not seed data or a promised outcome:

| Age | Main line | Supporting line |
|---|---|---|
| 20 | In training | Sharing housing; selected career starts at 23 |
| 30 | Working | Apartment fits; house deposit still short |
| 40 | Home goal delayed | Show remaining deposit gap |
| 50 | Home goal achieved in model | Estimated purchase age 46 |
| 60 | Retirement goal not funded | Show remaining retirement gap |
| 70 | Retirement may be achievable | Estimated retirement age 68 |

Calculate at least monthly internally and expose annual age summaries. Determine goal dates at individual ages; do not round an age-46 outcome to 50. Show a compact marker or badge **House around 46** between the appropriate decade milestones. If an age is before the simulation start, label it **Before this scenario starts** rather than fabricating past finances.

## 5. Goal setup and statuses

Use the selected lifestyle tiles to offer relevant goal controls inline: desired age for home purchase, education completion, car purchase, travel budget, savings target and retirement. Do not infer a personal life event merely from age. Children, childcare and a second earner activate only through explicit scenario inputs and editable start ages.

Use a hypothetical **Scenario starting age**, default 18, instead of collecting a birth date. Support optional starting balances and existing debt. Starting age is a simulation assumption, not required identity information. Default end age is 70; allow an optional extension with a clearly displayed horizon.

| Status | Display rule |
|---|---|
| On track | Goal meets its funding and ongoing cash-flow requirements by the requested age |
| Later than planned | Goal meets those requirements later within the modeled horizon; show estimated age and years delayed |
| Not achievable by 70 with this plan | No qualifying achievement date in the modeled horizon; show the limiting gap |
| More information needed | Required source data or assumptions are missing; name what is needed |

Use green, amber, coral and neutral styling respectively, always with text/icons. Never use color alone or a probability-of-success score.

For every goal return its requested age, projected achievable age or null, status, required resources, available resources, gap and reason. Show the gap at the requested age and, if still unmet, at the modeled end age. Label whether the gap is **monthly cash flow**, **upfront cash**, or **retirement funding**; do not combine unlike gaps into one unexplained number.

Do not say **You can never do this**. Use **Not achievable within this timeline under the current assumptions**.

## 6. Projection rules

Extend the existing calculation engine rather than replacing it with hardcoded examples or AI-generated financial numbers.

### Income and costs

- Tie career income to the selected sourced occupational wage and explicit work fraction/start age. School duration and employment while studying must be modeled separately.
- A selected BLS percentile is a wage scenario, not an automatic career stage. Do not move users from the 10th to the 90th percentile as they age.
- Default to the existing current-wage, today's-dollar mode without automatic raises or investment growth. Additional growth assumptions are editable and visibly labeled.
- Support an optional inflation/growth mode, distinguishing nominal calculations from today's-dollar display. Never mix nominal future costs with unadjusted current wages. Disclose how versioned tax rules are projected; future tax law is unknown.
- Apply household events at their configured dates. Calculate childcare from child ages and configured duration, not as a permanent cost or a guessed life event.
- Calculate taxes, deductions, loans and costs through existing services. Prevent double counting payroll retirement deductions, post-tax savings, tuition/net price, loan-funded tuition, rent/mortgage and upfront goal payments.

### Balances and transitions

- Maintain separate liquid cash, investments, debt balances and home equity where applicable. Home equity is not liquid spending money.
- Allocate savings only once: the amount subtracted from monthly available spending is the same amount credited to its savings account. Remaining unallocated surplus goes to liquid cash by default, with a disclosed editable rule.
- Show deficits and any resulting depletion of liquid cash. When cash is exhausted, record an **unfunded shortfall**; never silently assume unlimited borrowing, family support or investment withdrawals.
- Apply goal purchases as actual balance changes in the projected scenario. The same deposit cannot fund both a car and a house. Recalculate ongoing expenses after transitions.
- Tuition borrowing requires explicit loan assumptions; service loan balances and payments through time. Training-period living expenses need a declared funding source or an unfunded-gap warning.
- Evaluate feasibility through the full path. If an earlier unfunded gap requires support, describe a later achievable goal as conditional on resolving that gap.

### Home goal

A home is achievable only when liquid funds cover down payment and closing costs while preserving the configured emergency reserve, and projected ongoing mortgage, taxes, insurance, HOA and maintenance fit the budget. Show whether the blocker is deposit, monthly cost or both. This is an educational affordability estimate, not mortgage approval.

### Car, travel and savings goals

Cash purchases need adequate available funds. Financed purchases need explicit terms, any deposit and sustainable ongoing payments. Recurring travel must fit its annual/monthly allocation. A savings goal is achieved when its assigned account reaches the target without using funds already committed to another goal.

### Retirement goal

Do not declare retirement affordable merely because savings exceed one year's spending. Reuse an existing retirement model if present; otherwise implement a transparent monthly drawdown simulation through an editable planning age beyond retirement, default 95. Include spending, inflation/growth mode, balances and only explicitly configured retirement income. Show the planning horizon and assumptions. Do not invent pension or Social Security benefits.

A projected retirement date requires enough modeled accessible resources to fund the retirement period without an unfunded shortfall. If account access constraints are not modeled, label that limitation and avoid treating restricted funds as freely available. Return the funding gap at the requested retirement age using the same model. Label every result as conditional on assumptions, never guaranteed.

## 7. Requested future versus affordable alternative

Keep the requested scenario intact. If it falls short, display a derived comparison headed **What your current path could support**. Use the same city, career, education and earnings assumptions unless the user explicitly chooses to compare a changed path.

Show a concise table:

| You requested | Projected alternative | Why |
|---|---|---|
| House at 30 | Rent longer; buy at the calculated age if feasible | Deposit and/or monthly cost gap |
| Two trips each year | A lower travel budget, if sufficient | Dollar reduction required |
| Retirement at 60 | Later retirement if supported within the horizon | Funding gap and extra modeled work years |

All rows must come from calculated candidate scenarios. Preserve family composition, essential expenses and minimum reserve assumptions. Never suggest removing children or automatically assume a second income. Ask users to prioritize goals only through optional inline controls; use a visible deterministic default adjustment order: discretionary travel, vehicle cost, housing option, then goal timing.

Respect essential cost floors supported by data or labeled user assumptions. Try a bounded set of available housing/vehicle choices and date changes. Do not reduce every category arbitrarily until a budget appears balanced.

Replay the entire projection after each candidate adjustment. An alternative is affordable only when its full trajectory is funded, not just one snapshot. If none works, show **Everyday expenses still exceed estimated income by $X/month at age Y** and offer career/location comparisons. Missing alternative cost data produces an unavailable state, not invented savings.

Display the proposed changes and their effect. Provide **Apply this alternative** as an explicit action with Undo support. Never silently rewrite the user's dream scenario. Existing compare-three-futures behavior should accept the derived alternative as an independent scenario.

## 8. Interaction and visual design

- Match the existing purple FuturePath branding; use soft backgrounds, rounded cards, generous spacing and readable typography.
- Give goal achievement markers a subtle celebratory treatment. Keep shortfalls calm and constructive.
- Update summary, timeline, dates and comparison together whenever career, school, city, lifestyle, event age or assumptions change.
- Reuse centralized scenario state and pure calculation functions; avoid network calls when selecting a cached age.
- Debounce source lookups and ignore stale responses. Clearly mark calculations as updating when inputs changed.
- Preserve keyboard/touch alternatives, visible focus, screen-reader labels and reduced-motion support. Provide a text timeline equivalent.
- Collapse advanced controls by default. Reach a useful first result with the existing simple selections.
- Do not add photorealistic age progression, avatars, image generation or external AI dependencies. Age progression here means life and financial milestones.
- Display a compact label: **Illustrative projection · Based on your selections and editable assumptions**.

## 9. Implementation and response contract

Reuse the existing `/api/v1/simulations/calculate` endpoint, extending its versioned response while preserving legacy fields. The server calculation is authoritative; client previews must use equivalent formulas.

Add logical modules as appropriate to the actual repository:

- `TimelineProjectionService`: monthly trajectory, annual snapshots and events.
- `GoalFeasibilityService`: goal funding, dates, statuses and gaps.
- `AffordableAlternativeService`: bounded candidate evaluation and explanations.
- UI components: `SimpleBudgetSummary`, `FutureAgeTimeline`, `AgeDetailPanel`, `GoalMilestones`, `RequestedVsProjected`.

Persist scenario start/end ages, dollar mode, starting balances, goal dates, household events and explicit projection assumptions using the existing scenario JSON fields where suitable. Add a migration only if genuinely needed. Do not overwrite imported source data. Older saved scenarios must receive documented defaults and continue to load.

Return these conceptual fields with documented units and definitions:

| Field | Contents |
|---|---|
| `projectionVersion` | Calculation version |
| `horizon` | Starting age, ending age, retirement planning age and dollar basis |
| `ageSnapshots` | Annual ages with income, expenses, allocations, surplus, balances, life stage and funding warnings |
| `goals` | Requested/projected age, status, reason and age-specific typed gaps |
| `overallStatus` | Goal summary distinct from selected-age cash flow |
| `alternative` | Derived scenario, explicit changes, recalculated results and feasibility or unavailable reason |
| `provenance` | Source vintages, editable assumptions, omissions and unavailable data |

An unavailable amount or projected date is null with a reason, never a fabricated value. Store money with appropriate decimal precision; round for presentation only. Keep anonymous sharing free of identifiers and birth dates.

## 10. Focused acceptance checks

1. Ages 20–70 display immediately for a complete scenario; exact achievement ages appear between decades.
2. Selecting age 40 updates all selected-age figures and details consistently without a page reload.
3. A funded goal is On track; a delayed goal shows its estimated age and delay; an unmet goal shows the correct typed gap at the requested age and horizon.
4. Missing wages/housing produce More information needed, not $0 or a false failure verdict.
5. A delayed career start produces the correct training-period funding gap; later goals remain conditional if that gap is unresolved.
6. Changing starting savings, debt, tuition funding or a child's start age changes the trajectory correctly.
7. Home/car purchases consume funds once, preserve the configured reserve and update ongoing costs; mutually competing goals cannot reuse the same cash.
8. Savings deductions and account credits reconcile; pretax retirement contributions are not deducted twice; cash exhaustion produces an unfunded gap.
9. Retirement feasibility uses its full drawdown horizon, explicit income and assumptions; zero assumed returns and missing benefit data are handled without invented income.
10. A derived alternative stays within allowed changes, is recalculated across the full timeline and does not mutate the original until Apply is selected. Undo restores the prior scenario.
11. Old saved scenarios still load; source years and projection assumptions remain visible.
12. One final desktop/mobile smoke check confirms six readable cards, accessible age selection, inline detail, compact budget and collapsed math, with no unintended overflow.

Use deterministic synthetic fixtures for calculation tests, clearly separated from real datasets. No external data downloads are required to verify the logic. Run targeted checks once; fix and rerun only failed checks rather than entering a repeated audit loop.

## 11. Completion

Implement this change now in the existing builder. Report changed files, implemented behaviors, any remaining data/model limitations, focused verification results and start instructions for port **42005**. The finished screen must answer **Can my selected future work, when could my goals happen, and what could fit if they do not?** without requiring the user to study a detailed budget.
