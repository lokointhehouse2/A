/*
 * FuturePath calculation engine (browser + Node). A line-by-line mirror of the CFML services
 * TaxEstimatorService, LoanCalculatorService and LifestyleSimulatorService so the page can recalculate instantly.
 * Both implementations are checked against tests/fixtures/scenarios/*.json.
 * Pure functions only: no DOM, no network.
 */
(function (root, factory) {
    if (typeof module === 'object' && module.exports) module.exports = factory();
    else root.FPEngine = factory();
}(typeof self !== 'undefined' ? self : this, function () {
    'use strict';

    var STATUSES = ['single', 'mfj', 'hoh'];
    var isNum = function (v) { return typeof v === 'number' && isFinite(v); };
    var nz = function (v, d) { return v === null || v === undefined ? d : v; };
    var sum = function (arr) { return arr.reduce(function (a, b) { return a + b; }, 0); };

    // ------------------------------------------------------------------ loans
    function amortize(principal, aprPercent, months) {
        if (!(months > 0) || Math.floor(months) !== months) throw new Error('Loan term must be a whole number of months greater than zero.');
        if (aprPercent < 0) throw new Error('Interest rate cannot be negative.');
        if (principal <= 0) return { payment: 0, totalPaid: 0, totalInterest: 0, months: months, aprPercent: aprPercent, principal: 0 };
        var r = aprPercent / 100 / 12;
        var payment = r === 0 ? principal / months : principal * r / (1 - Math.pow(1 + r, -months));
        return { payment: payment, totalPaid: payment * months, totalInterest: payment * months - principal, months: months, aprPercent: aprPercent, principal: principal };
    }

    function balanceAfter(principal, aprPercent, months, paymentsMade) {
        if (principal <= 0) return 0;
        var k = Math.min(Math.max(0, paymentsMade), months);
        var r = aprPercent / 100 / 12;
        if (r === 0) return Math.max(0, principal - principal / months * k);
        var payment = amortize(principal, aprPercent, months).payment;
        return Math.max(0, principal * Math.pow(1 + r, k) - payment * ((Math.pow(1 + r, k) - 1) / r));
    }

    // ------------------------------------------------------------------ taxes
    function bracketTax(taxable, brackets) {
        var tax = 0;
        (brackets || []).forEach(function (b) {
            if (taxable <= b.lower) return;
            var top = b.upper === null || b.upper === undefined ? taxable : Math.min(taxable, b.upper);
            tax += (top - b.lower) * b.rate;
        });
        return tax;
    }

    function estimateReturn(wages, pretax, status, children, inp) {
        var fed = inp.packs.federal;
        var warnings = [];
        var rulesUsed = [];
        var totalWages = 0, totalPretax = 0, ss = 0, medicare = 0;
        for (var i = 0; i < wages.length; i++) {
            var w = Math.max(0, wages[i]);
            totalWages += w;
            totalPretax += Math.min(w, Math.max(0, nz(pretax[i], 0)));
            ss += Math.min(w, fed.socialSecurity.wageBase) * fed.socialSecurity.rate;
            medicare += w * fed.medicare.rate;
        }
        var addl = (fed.additionalMedicare || {})[status] || { threshold: 200000, rate: 0.009 };
        var additionalMedicare = Math.max(0, totalWages - addl.threshold) * addl.rate;
        var agi = totalWages - totalPretax;
        var fedTaxable = Math.max(0, agi - nz(fed.standardDeduction[status], 0));
        var fedTax = bracketTax(fedTaxable, fed.brackets[status]);
        rulesUsed.push({ jurisdiction: 'US', taxYear: fed.taxYear, sources: fed.sources });

        var ctc = 0;
        if (children > 0 && fed.childTaxCredit) {
            var c = fed.childTaxCredit;
            var credit = children * c.amountPerChild;
            var start = nz(c.phaseoutStart[status], 200000);
            if (agi > start) credit = Math.max(0, credit - Math.ceil((agi - start) / 1000) * c.phaseoutPerThousand);
            var nonRefundable = Math.min(credit, fedTax);
            var refundable = Math.min(Math.min(credit - nonRefundable, children * c.refundableMaxPerChild), Math.max(0, (totalWages - c.refundableEarnedIncomeFloor) * c.refundableRate));
            ctc = nonRefundable + Math.max(0, refundable);
        }

        var stateTax = 0, stateModeled = true, stateTaxable = 0;
        var st = inp.packs.state || null;
        var stateCode = inp.stateCode || '';
        if (!st) {
            stateModeled = false;
            if (stateCode) warnings.push('State income tax for ' + stateCode + ' is not modeled yet, so take-home pay is overstated for ' + stateCode + ' residents.');
        } else if (st.noIncomeTax) {
            rulesUsed.push({ jurisdiction: st.jurisdiction, taxYear: st.taxYear, sources: st.sources });
        } else {
            stateTaxable = Math.max(0, agi - nz(st.standardDeduction[status], 0));
            stateTax = bracketTax(stateTaxable, st.brackets[status] || []);
            rulesUsed.push({ jurisdiction: st.jurisdiction, taxYear: st.taxYear, sources: st.sources });
            if (st.taxYear !== st.requestedYear) warnings.push(st.jurisdiction + ' tax uses the latest published ' + st.taxYear + ' rules.');
        }
        var localTax = 0;
        var loc = inp.packs.local || null;
        if (loc) {
            localTax = bracketTax(stateTaxable, loc.brackets[status] || []);
            rulesUsed.push({ jurisdiction: loc.jurisdiction, taxYear: loc.taxYear, sources: loc.sources });
        }
        var federalIncomeTax = fedTax - ctc;
        var total = federalIncomeTax + stateTax + localTax + ss + medicare + additionalMedicare;
        return {
            agi: agi, federalTaxableIncome: fedTaxable, stateTaxableIncome: stateTaxable,
            federalIncomeTax: federalIncomeTax, federalIncomeTaxBeforeCredits: fedTax, childTaxCredit: ctc,
            stateIncomeTax: stateTax, localIncomeTax: localTax,
            socialSecurity: ss, medicare: medicare, additionalMedicare: additionalMedicare,
            total: total, effectiveRate: totalWages > 0 ? total / totalWages : 0,
            stateModeled: stateModeled, warnings: warnings, rulesUsed: rulesUsed
        };
    }

    function estimateTaxes(inp) {
        var wages = inp.wages, pretax = inp.pretax || [];
        if (wages.length === 2 && inp.filingStatus !== 'mfj') {
            var a = estimateReturn([wages[0]], [nz(pretax[0], 0)], inp.filingStatus, inp.children || 0, inp);
            var b = estimateReturn([wages[1]], [nz(pretax[1], 0)], 'single', 0, inp);
            var combined = {};
            ['federalIncomeTax', 'childTaxCredit', 'stateIncomeTax', 'localIncomeTax', 'socialSecurity', 'medicare', 'additionalMedicare', 'total', 'agi'].forEach(function (k) { combined[k] = a[k] + b[k]; });
            combined.returns = [a, b];
            combined.filing = 'separate';
            combined.warnings = a.warnings.slice();
            b.warnings.forEach(function (w) { if (combined.warnings.indexOf(w) < 0) combined.warnings.push(w); });
            combined.warnings.push('Two earners who are not married file separate returns; earner 1 claims the children.');
            combined.stateModeled = a.stateModeled;
            combined.rulesUsed = a.rulesUsed;
            return combined;
        }
        var single = estimateReturn(wages, pretax, inp.filingStatus, inp.children || 0, inp);
        single.filing = wages.length === 2 ? 'joint' : 'single-return';
        single.returns = [JSON.parse(JSON.stringify(single))];
        return single;
    }

    // ------------------------------------------------------------------ simulator helpers
    function effectiveAssumptions(scenario, defaults) {
        var out = {};
        Object.keys(defaults.items).forEach(function (k) {
            var o = scenario.assumptions ? scenario.assumptions[k] : undefined;
            out[k] = isNum(o) ? o : defaults.items[k].value;
        });
        return out;
    }

    function line(key, label, category, monthly, basis, detail, note) {
        return { key: key, label: label, category: category, monthly: isNum(monthly) ? monthly : null, basis: basis, detail: detail || '', note: note || '' };
    }

    function addCitation(citations, topic, text, url) {
        for (var i = 0; i < citations.length; i++) if (citations[i].text === text) return;
        citations.push({ topic: topic, text: text, url: url || '' });
    }

    function fmt(n) { return Math.round(n).toLocaleString('en-US'); }

    function benchmarkRent(apt, housing, warnings) {
        var key = String(apt.bedrooms);
        if (isNum(apt.customRent)) return { value: apt.customRent, basis: 'user', label: 'Your rent', note: '', citation: null };
        var acsValue = housing.acs && housing.acs.rents ? nz(housing.acs.rents[key], null) : null;
        var hudArea = housing.hud && housing.hud.areas && housing.hud.areas.length ? housing.hud.areas[0] : null;
        var hudValue = hudArea ? nz(hudArea.rents[key], null) : null;
        var bedLabel = apt.bedrooms === 0 ? 'studio' : apt.bedrooms + '-bedroom';
        var useAcs = apt.benchmark === 'acs';
        if (useAcs && acsValue === null && hudValue !== null) {
            warnings.push('No ACS median rent for a ' + bedLabel + ' here; using the HUD Fair Market Rent instead.');
            useAcs = false;
        } else if (!useAcs && hudValue === null && acsValue !== null) {
            warnings.push('No HUD Fair Market Rent for a ' + bedLabel + ' here; using the ACS median rent instead.');
            useAcs = true;
        }
        if (useAcs && acsValue !== null) {
            return { value: acsValue, basis: 'sourced', label: 'ACS median gross rent, ' + bedLabel + ', ' + housing.acs.period, note: housing.acs.note,
                citation: { name: 'Census ACS median gross rent (' + housing.acs.period + ')', url: housing.acs.sourceUrl } };
        }
        if (!useAcs && hudValue !== null) {
            if (hudArea.quality === 'partial') warnings.push("HUD splits this metro into several rent areas; using '" + hudArea.name + "'.");
            return { value: hudValue, basis: 'sourced', label: 'HUD Fair Market Rent, ' + bedLabel + ', ' + hudArea.period, note: housing.hud.note,
                citation: { name: 'HUD Fair Market Rents ' + hudArea.period + ' (' + hudArea.name + ')', url: housing.hud.sourceUrl } };
        }
        warnings.push('No rent benchmark is published for a ' + bedLabel + ' in this metro. Enter your own rent.');
        return { value: null, basis: 'missing', label: 'Not available', note: '', citation: null };
    }

    function foodCost(adults, children, ageGroup, food) {
        if (!food || !food.moderate) return { value: null };
        var plan = food.moderate;
        if (!isNum(plan.female_19_50) || !isNum(plan.male_19_50)) return { value: null };
        var total = adults * (plan.female_19_50 + plan.male_19_50) / 2 + children * nz(plan[ageGroup], plan.child_6_8);
        var size = adults + children;
        var factor = size === 1 ? 1.20 : (size === 2 ? 1.10 : (size === 3 ? 1.05 : (size === 4 ? 1 : (size <= 6 ? 0.95 : 0.90))));
        return { value: total * factor };
    }

    function educationCosts(s, ref, warnings, citations) {
        var ed = s.education;
        var path = (ref.pathways || {})[ed.pathway] || null;
        var years = ed.years > 0 ? ed.years : (path ? path.typicalYears : 0);
        var out = {
            pathway: ed.pathway, pathwayName: path ? path.name : '', years: years,
            annualNetPrice: null, totalCost: null, borrowed: null, outOfPocketAnnual: null,
            monthlyPayment: 0, totalInterest: 0, institution: null, priceBasis: ''
        };
        var noTuition = ['work', 'ged', 'apprenticeship'].indexOf(ed.pathway) >= 0;
        if (noTuition || years === 0) {
            out.annualNetPrice = 0; out.totalCost = 0; out.borrowed = 0; out.outOfPocketAnnual = 0; out.priceBasis = 'none';
            return out;
        }
        var price = isNum(ed.annualNetPrice) ? ed.annualNetPrice : null;
        if (price !== null) {
            out.priceBasis = 'user';
        } else if (ref.institution && ref.institution.costs && isNum(ref.institution.costs.averageNetPrice)) {
            price = ref.institution.costs.averageNetPrice;
            out.priceBasis = 'sourced';
            out.institution = { unitid: ref.institution.unitid, name: ref.institution.name };
            addCitation(citations, 'education', 'College Scorecard average net price, ' + ref.institution.name, 'https://collegescorecard.ed.gov/data/');
        }
        if (price === null) {
            warnings.push('Pick a college (or enter a yearly price) to estimate education costs.');
            return out;
        }
        var outOfPocket = Math.max(0, price - ed.grantsAnnual);
        var borrowedPerYear = Math.max(0, outOfPocket - ed.familyAnnual);
        out.annualNetPrice = price;
        out.outOfPocketAnnual = outOfPocket;
        out.totalCost = outOfPocket * years;
        out.borrowed = borrowedPerYear * years;
        return out;
    }

    function buildTimeline(s, ref, A, earners, monthlyCosts, education, monthlyDebt, children) {
        var startAge = s.timeline.startAge;
        var ages = s.timeline.ages || [];
        var maxAge = ages.length ? ages[ages.length - 1] : 40;
        var projected = s.timeline.mode === 'projected';
        var infl = projected ? A.inflationPct / 100 : 0;
        var growth = projected ? (1 + infl) * (1 + A.wageGrowthPct / 100) - 1 : 0;
        var schoolYears = Math.floor(nz(education.years, 0));
        var borrowed = nz(education.borrowed, 0);
        var loan = (ref.loans || {})[s.education.loanKey] || { rate: 0, months: 120 };
        var baseWages = earners.map(function (e) { return e.grossAnnual; });
        var nonDebtAnnual = (monthlyCosts - monthlyDebt) * 12;
        var debtAnnual = monthlyDebt * 12;
        var cumulative = 0;
        var points = [];
        for (var age = startAge; age <= maxAge; age++) {
            var t = age - startAge;
            var inSchool = t < schoolYears;
            var row = { age: age, phase: inSchool ? 'school' : 'working', wage: 0, takeHome: 0, livingCosts: 0, debtPayments: 0, debtBalance: 0, educationCost: 0, surplus: 0, cumulativeSurplus: 0 };
            if (inSchool) {
                row.educationCost = nz(education.outOfPocketAnnual, 0);
                row.debtBalance = schoolYears > 0 ? borrowed / schoolYears * (t + 1) : 0;
            } else {
                var yearsWorking = t - schoolYears;
                var factor = Math.pow(1 + growth, yearsWorking);
                var w = baseWages.map(function (bw) { return bw * factor; });
                var gross = sum(w);
                var pre = w.map(function (x) { return x * A.retirementPct / 100; });
                var tax = w.length ? estimateTaxes({ wages: w, pretax: pre, filingStatus: s.filingStatus, children: children, stateCode: s.state, packs: ref.taxPacks }).total : 0;
                row.wage = gross;
                row.takeHome = gross - tax - sum(pre);
                row.livingCosts = nonDebtAnnual * Math.pow(1 + infl, t);
                row.debtPayments = yearsWorking < loan.months / 12 ? debtAnnual : 0;
                row.debtBalance = borrowed > 0 && debtAnnual > 0 ? balanceAfter(borrowed, loan.rate, loan.months, yearsWorking * 12) : (debtAnnual > 0 ? 0 : borrowed);
                row.surplus = row.takeHome - row.livingCosts - row.debtPayments;
                cumulative += row.surplus;
            }
            row.cumulativeSurplus = cumulative;
            if (ages.indexOf(age) >= 0) points.push(row);
        }
        return points;
    }

    // ------------------------------------------------------------------ main
    /**
     * compute(scenario, ref, defaults, options) -> result. `scenario` must already be normalized
     * (the client keeps it normalized; the server normalizes untrusted input).
     */
    function compute(s, ref, defaults, options) {
        options = options || {};
        var includeTimeline = options.includeTimeline !== false;
        var A = effectiveAssumptions(s, defaults);
        var warnings = [], citations = [], complete = true;
        var tile = {};
        (s.tiles || []).forEach(function (t) { tile[t.type] = t; });

        // income
        var earners = [], wages = [], pretax = [];
        (s.earners || []).forEach(function (e) {
            var w = (ref.wages || {})[e.soc] || null;
            var annual = null, status = 'missing', message = '';
            if (isNum(e.customWage)) { annual = e.customWage; status = 'custom'; }
            else if (!e.soc) { message = 'Choose a career to see income.'; }
            else if (!w) { message = 'Wage data for this occupation has not been loaded.'; }
            else {
                var candidate = w.annual ? nz(w.annual[e.percentile], null) : null;
                if (candidate !== null) { annual = candidate; status = 'sourced'; }
                else message = w.message ? w.message : 'BLS does not publish this wage percentile for this occupation here.';
            }
            if (annual === null) { complete = false; if (message) warnings.push(message); }
            var gross = annual === null ? 0 : annual * e.workFraction;
            var retirement = gross * A.retirementPct / 100;
            wages.push(gross);
            pretax.push(retirement);
            earners.push({
                soc: e.soc, title: ((ref.occupations || {})[e.soc] || {}).title || '', percentile: e.percentile, workFraction: e.workFraction,
                annualWage: annual, grossAnnual: gross, retirementAnnual: retirement, status: status, message: message,
                wageYear: w ? w.year : null, areaLevel: w ? w.areaLevel : null
            });
            if (status === 'sourced') addCitation(citations, 'wages', 'BLS OEWS May ' + w.year + ', ' + ref.metro.name + ' (' + e.percentile + ')', 'https://www.bls.gov/oes/tables.htm');
        });
        if (!earners.length) { complete = false; warnings.push('Add a career (or a custom wage) to see income.'); }
        var children = tile.children ? tile.children.count : 0;
        var taxResult = estimateTaxes({ wages: wages.length ? wages : [0], pretax: pretax.length ? pretax : [0], filingStatus: s.filingStatus, children: children, stateCode: s.state, packs: ref.taxPacks });
        taxResult.warnings.forEach(function (w) { warnings.push(w); });
        taxResult.rulesUsed.forEach(function (ru) { (ru.sources || []).forEach(function (src) { addCitation(citations, 'taxes', src.name + ' (' + ru.jurisdiction + ' ' + ru.taxYear + ')', src.url || ''); }); });
        if ((s.earners || []).length === 2 && s.filingStatus === 'single') warnings.push('Two earners filing as single: each earner is taxed on a separate return.');
        if (s.filingStatus === 'hoh' && children === 0) warnings.push('Head of household status usually requires a qualifying dependent.');
        var grossAnnual = sum(wages);
        var retirementAnnual = sum(pretax);
        var takeHomeAnnual = grossAnnual - taxResult.total - retirementAnnual;
        var takeHomeMonthly = takeHomeAnnual / 12;

        // costs
        var lines = [];
        var members = s.adults + children;
        var upfront = { downPayment: 0, closingCosts: 0 };
        var housingMode = tile.house ? 'own' : (tile.apartment ? 'rent' : 'none');
        if (tile.house && tile.apartment) warnings.push('You picked both House and Apartment. Only the house is counted (no rent and mortgage for the same home).');
        if (tile.roommates && housingMode !== 'rent') warnings.push('Roommates only apply when renting an apartment.');

        if (housingMode === 'rent') {
            var apt = tile.apartment;
            var rentInfo = benchmarkRent(apt, ref.housing, warnings);
            var rent = rentInfo.value;
            var share = 1;
            if (tile.roommates) {
                share = 1 / (tile.roommates.count + 1);
                if (apt.bedrooms < tile.roommates.count + 1) warnings.push('With ' + tile.roommates.count + ' roommate(s), most people need at least ' + (tile.roommates.count + 1) + ' bedrooms.');
            }
            if (rent === null) complete = false;
            lines.push(line('rent', share < 1 ? 'Your share of rent (incl. utilities)' : 'Rent (incl. utilities)', 'housing', rent === null ? null : rent * share, rentInfo.basis, rentInfo.label, rentInfo.note));
            if (rentInfo.citation) addCitation(citations, 'housing', rentInfo.citation.name, rentInfo.citation.url);
            lines.push(line('renters_insurance', "Renter's insurance", 'housing', A.renterInsuranceMonthly, 'assumption', 'FuturePath assumption', ''));
        } else if (housingMode === 'own') {
            var house = tile.house;
            var hv = ref.housing && ref.housing.homeValue ? ref.housing.homeValue : null;
            var price = isNum(house.price) ? house.price : (hv ? hv.value : null);
            var priceBasis = isNum(house.price) ? 'user' : 'sourced';
            if (!isNum(price)) {
                complete = false;
                warnings.push('No home value is available for this metro; enter a home price.');
                lines.push(line('mortgage', 'Mortgage (principal + interest)', 'housing', null, 'missing', '', ''));
            } else {
                if (priceBasis === 'sourced') addCitation(citations, 'housing', 'Census ACS median home value, ' + hv.period, hv.sourceUrl);
                var loanAmount = price * (1 - A.downPaymentPct / 100);
                var mort = amortize(loanAmount, A.mortgageRatePct, A.mortgageTermYears * 12);
                upfront.downPayment = price * A.downPaymentPct / 100;
                upfront.closingCosts = price * A.closingCostPct / 100;
                var priceLabel = (priceBasis === 'sourced' ? 'Metro median home value ' : 'Home price ') + '$' + fmt(price);
                lines.push(line('mortgage', 'Mortgage (principal + interest)', 'housing', mort.payment, 'assumption', priceLabel + ', ' + A.downPaymentPct + '% down, ' + A.mortgageRatePct + '% for ' + A.mortgageTermYears + ' years', ''));
                lines.push(line('property_tax', 'Property tax', 'housing', price * A.propertyTaxPct / 100 / 12, 'assumption', A.propertyTaxPct + '% of value per year', 'Property tax rates vary by county.'));
                lines.push(line('home_insurance', "Homeowner's insurance", 'housing', A.homeInsuranceMonthly, 'assumption', 'FuturePath assumption', ''));
                if (A.downPaymentPct < 20) lines.push(line('pmi', 'Mortgage insurance (PMI)', 'housing', loanAmount * A.pmiPct / 100 / 12, 'assumption', A.pmiPct + '% of loan per year until 20% equity', ''));
                lines.push(line('maintenance', 'Home maintenance', 'housing', price * A.maintenancePct / 100 / 12, 'assumption', A.maintenancePct + '% of value per year', ''));
                if (A.hoaMonthly > 0) lines.push(line('hoa', 'HOA fees', 'housing', A.hoaMonthly, 'assumption', '', ''));
                lines.push(line('utilities', 'Utilities', 'housing', A.ownerUtilitiesMonthly, 'assumption', 'FuturePath assumption', 'Homeowners pay utilities separately.'));
            }
        } else {
            warnings.push('Add an Apartment or a House to include housing costs.');
        }

        var cars = (tile.car ? 1 : 0) + (tile.second_car ? 1 : 0);
        ['car', 'second_car'].forEach(function (ct) {
            if (!tile[ct]) return;
            var carPrice = isNum(tile[ct].price) ? tile[ct].price : A.carPrice;
            var carLoan = amortize(carPrice * (1 - A.carDownPaymentPct / 100), A.carAprPct, A.carTermMonths);
            var label = ct === 'car' ? 'Car' : 'Second car';
            lines.push(line(ct + '_payment', label + ' payment', 'transportation', carLoan.payment, 'assumption', '$' + fmt(carPrice) + ' car, ' + A.carDownPaymentPct + '% down, ' + A.carAprPct + '% for ' + A.carTermMonths + ' months', ''));
            lines.push(line(ct + '_insurance', label + ' insurance', 'transportation', A.carInsuranceMonthly, 'assumption', 'FuturePath assumption', ''));
            lines.push(line(ct + '_running', label + ' gas and maintenance', 'transportation', A.carFuelMaintenanceMonthly, 'assumption', 'FuturePath assumption', ''));
        });
        if (cars === 0) lines.push(line('transit', 'Public transit', 'transportation', A.transitMonthlyPerAdult * s.adults, 'assumption', 'FuturePath assumption', ''));

        var food = foodCost(s.adults, children, tile.children ? tile.children.ageGroup : 'child_6_8', ref.food);
        if (food.value === null) { complete = false; warnings.push('USDA food plan costs are not loaded.'); }
        else addCitation(citations, 'food', 'USDA Food Plans, Moderate-Cost, U.S. average (' + ref.food.period + ')', ref.food.sourceUrl);
        lines.push(line('food', 'Groceries', 'food', food.value, 'sourced', 'USDA Moderate-Cost Food Plan, U.S. average', 'National average for food prepared at home; local prices differ.'));
        lines.push(line('dining_out', 'Eating out', 'food', A.diningOutMonthlyPerAdult * s.adults, 'assumption', 'FuturePath assumption', ''));

        if (tile.childcare) {
            if (children === 0) warnings.push('Childcare needs the Children tile.');
            else {
                var inCare = Math.min(children, isNum(tile.childcare.children) ? tile.childcare.children : children);
                lines.push(line('childcare', 'Childcare (' + inCare + ' child' + (inCare === 1 ? '' : 'ren') + ')', 'childcare', inCare * A.childcareMonthlyPerChild, 'assumption', 'FuturePath assumption', 'Childcare prices vary a lot by city and age.'));
            }
        }

        lines.push(line('healthcare', 'Health insurance and care', 'healthcare', s.adults * A.healthcareMonthlyPerAdult + children * A.healthcareMonthlyPerChild, 'assumption', 'FuturePath assumption', 'Employer plans vary widely.'));
        lines.push(line('phone_internet', 'Phone and internet', 'other', A.phoneInternetMonthly, 'assumption', 'FuturePath assumption', ''));
        lines.push(line('other', 'Clothing, personal care and household', 'other', A.otherMonthlyPerPerson * members, 'assumption', 'FuturePath assumption', ''));

        var education = educationCosts(s, ref, warnings, citations);
        if (tile.student_debt) {
            var principal = isNum(tile.student_debt.principal) ? tile.student_debt.principal : education.borrowed;
            var loan = (ref.loans || {})[s.education.loanKey] || null;
            if (!isNum(principal)) {
                complete = false;
                warnings.push('Pick a school (or enter an amount) to estimate the student loan payment.');
                lines.push(line('student_loan', 'Student loan payment', 'education_debt', null, 'missing', '', ''));
            } else if (!loan) {
                complete = false;
                lines.push(line('student_loan', 'Student loan payment', 'education_debt', null, 'missing', 'Loan rate not loaded', ''));
            } else {
                var sl = amortize(principal, loan.rate, loan.months);
                education.monthlyPayment = sl.payment;
                education.totalInterest = sl.totalInterest;
                lines.push(line('student_loan', 'Student loan payment', 'education_debt', sl.payment, isNum(tile.student_debt.principal) ? 'user' : 'sourced',
                    '$' + fmt(principal) + ' at ' + loan.rate + '% for ' + (loan.months / 12) + ' years', loan.description));
                addCitation(citations, 'education', 'Federal Student Aid, ' + loan.description + ' (' + loan.rate + '%)', loan.sourceUrl);
            }
        }

        if (tile.travel) lines.push(line('travel', 'Travel and vacations', 'savings', (isNum(tile.travel.annual) ? tile.travel.annual : A.travelAnnual) / 12, isNum(tile.travel.annual) ? 'user' : 'assumption', '', ''));
        if (tile.savings) lines.push(line('emergency_savings', 'Savings', 'savings', isNum(tile.savings.monthly) ? tile.savings.monthly : A.emergencySavingsMonthly, isNum(tile.savings.monthly) ? 'user' : 'assumption', '', ''));

        var monthlyCosts = 0;
        var categories = { housing: 0, transportation: 0, food: 0, childcare: 0, healthcare: 0, education_debt: 0, savings: 0, other: 0 };
        lines.forEach(function (l) {
            if (l.monthly === null) return;
            monthlyCosts += l.monthly;
            categories[l.category] += l.monthly;
        });
        var surplus = takeHomeMonthly - monthlyCosts;
        var timeline = includeTimeline ? buildTimeline(s, ref, A, earners, monthlyCosts, education, categories.education_debt, children) : [];

        return {
            calculationVersion: ref.calculationVersion || '',
            complete: complete,
            income: { earners: earners, grossAnnual: grossAnnual, pretaxRetirementAnnual: retirementAnnual, taxes: taxResult, takeHomeAnnual: takeHomeAnnual, takeHomeMonthly: takeHomeMonthly },
            costs: { lines: lines, monthlyTotal: monthlyCosts, categories: categories },
            upfront: upfront,
            monthlySurplus: surplus,
            affordabilityRatio: takeHomeMonthly > 0 ? monthlyCosts / takeHomeMonthly : null,
            coveragePercent: monthlyCosts > 0 ? Math.min(999, Math.max(0, takeHomeMonthly / monthlyCosts * 100)) : null,
            education: education,
            timeline: timeline,
            warnings: warnings,
            citations: citations,
            assumptionsUsed: A,
            dataYears: ref.dataYears || {}
        };
    }

    /** Gross pay earner 1 needs so take-home covers monthly costs (earner 2 unchanged); null if unreachable. */
    function requiredGross(scenario, ref, defaults) {
        var s = JSON.parse(JSON.stringify(scenario));
        if (!s.earners || !s.earners.length) s.earners = [{ soc: '', percentile: 'median', workFraction: 1, customWage: 0 }];
        s.earners[0].customWage = 0;
        s.earners[0].workFraction = 1;
        var base = compute(s, ref, defaults, { includeTimeline: false });
        var target = base.costs.monthlyTotal;
        var takeHomeAt = function (g) { s.earners[0].customWage = g; return compute(s, ref, defaults, { includeTimeline: false }).income.takeHomeMonthly; };
        var lo = 0, hi = 3000000;
        if (takeHomeAt(hi) < target) return null;
        for (var i = 0; i < 50; i++) {
            var mid = (lo + hi) / 2;
            if (takeHomeAt(mid) >= target) hi = mid; else lo = mid;
            if (hi - lo < 1) break;
        }
        return { earner1Gross: Math.ceil(hi), householdGross: Math.ceil(hi) + (s.earners.length > 1 ? base.income.earners[1].grossAnnual : 0), monthlyCosts: target };
    }

    return {
        amortize: amortize, balanceAfter: balanceAfter, bracketTax: bracketTax, estimateTaxes: estimateTaxes,
        compute: compute, requiredGross: requiredGross, effectiveAssumptions: effectiveAssumptions, STATUSES: STATUSES
    };
}));
