/**
 * Lifestyle simulator: a deterministic, auditable pure function of (scenario, reference data).
 * The browser runs the same algorithm (assets/js/engine.js) for instant updates; both are checked
 * against the same fixtures in tests/fixtures/scenarios.
 *
 *   monthlyTakeHome = (grossWages - estimatedTaxes - pretaxRetirement) / 12
 *   monthlyCosts    = housing + transportation + food + childcare + healthcare + student debt + phone/internet
 *                     + eating out + other + travel + savings          (pre-tax retirement is NOT counted again)
 *   monthlySurplus  = monthlyTakeHome - monthlyCosts
 *   affordabilityRatio = monthlyCosts / monthlyTakeHome  (when take-home > 0)
 * Rent and mortgage are mutually exclusive. Missing sourced values stay null and mark the result incomplete.
 */
component {

    variables.tileTypes = "apartment,house,roommates,car,second_car,children,childcare,travel,savings,student_debt";
    variables.percentiles = "p10,p25,median,p75,p90,mean";
    variables.ageGroups = "child_1,child_2_3,child_4_5,child_6_8,child_9_11";

    public LifestyleSimulatorService function init( required any config, required any taxes, required any loans ) {
        variables.config = arguments.config;
        variables.taxes = arguments.taxes;
        variables.loans = arguments.loans;
        variables.assumptions = deserializeJSON( fileRead( arguments.config.rootPath & "config/assumptions.json", "utf-8" ) );
        return this;
    }

    public struct function assumptionDefaults() {
        return duplicate( variables.assumptions );
    }

    // ------------------------------------------------------------------ validation / normalization

    /** Validates an untrusted scenario (from JSON) and returns a normalized copy with defaults filled in. */
    public struct function normalize( required struct raw ) {
        var v = new core.utils.Validator();
        var r = arguments.raw;
        var s = {};
        s.v = 1;
        s.cbsa = v.cbsa( r.cbsa ?: "" );
        s.state = v.stateCode( r.state ?: "" );
        s.nycResident = isBoolean( r.nycResident ?: false ) && ( r.nycResident ?: false ) && s.state == "NY";
        s.taxYear = v.intInRange( r.taxYear ?: variables.config.defaultTaxYear, 2020, 2035, variables.config.defaultTaxYear, "taxYear" );
        s.filingStatus = v.oneOf( r.filingStatus ?: "single", "single,mfj,hoh", "single", "filingStatus" );
        s.adults = v.intInRange( r.adults ?: 1, 1, 2, 1, "adults" );
        s.earners = [];
        var rawEarners = isArray( r.earners ?: "" ) ? r.earners : [];
        if ( arrayLen( rawEarners ) > 2 ) v.fail( "At most two earners are supported.", { earners: "Too many earners" } );
        for ( var e in rawEarners ) {
            if ( !isStruct( e ) ) continue;
            var soc = len( e.soc ?: "" ) ? v.soc( e.soc ) : "";
            arrayAppend( s.earners, {
                soc: soc,
                percentile: v.oneOf( e.percentile ?: "median", variables.percentiles, "median", "percentile" ),
                workFraction: v.numberInRange( e.workFraction ?: 1, 0.1, 1, 1, "workFraction" ),
                customWage: isNull( e.customWage ) || !len( toString( e.customWage ) ) ? javacast( "null", "" ) : v.numberInRange( e.customWage, 0, 5000000, 0, "customWage" )
            } );
        }
        if ( arrayLen( s.earners ) == 2 && s.adults < 2 ) s.adults = 2;
        s.tiles = [];
        var seen = {};
        for ( var t in ( isArray( r.tiles ?: "" ) ? r.tiles : [] ) ) {
            if ( !isStruct( t ) || !listFind( variables.tileTypes, t.type ?: "" ) || structKeyExists( seen, t.type ) ) continue;
            seen[ t.type ] = true;
            arrayAppend( s.tiles, normalizeTile( t, v ) );
        }
        var ed = isStruct( r.education ?: "" ) ? r.education : {};
        s.education = {
            pathway: reFind( "^[a-z_]{1,40}$", ed.pathway ?: "" ) ? ed.pathway : "",
            years: v.numberInRange( ed.years ?: 0, 0, 15, 0, "education.years" ),
            unitid: isNumeric( ed.unitid ?: "" ) ? int( ed.unitid ) : javacast( "null", "" ),
            cip: reFind( "^[0-9]{2}(\.[0-9]{2}([0-9]{2})?)?$", ed.cip ?: "" ) ? ed.cip : "",
            annualNetPrice: isNull( ed.annualNetPrice ) || !len( toString( ed.annualNetPrice ) ) ? javacast( "null", "" ) : v.numberInRange( ed.annualNetPrice, 0, 200000, 0, "education.annualNetPrice" ),
            grantsAnnual: v.numberInRange( ed.grantsAnnual ?: 0, 0, 200000, 0, "education.grantsAnnual" ),
            familyAnnual: v.numberInRange( ed.familyAnnual ?: 0, 0, 200000, 0, "education.familyAnnual" ),
            loanKey: v.oneOf( ed.loanKey ?: "direct_undergrad", "direct_undergrad,direct_grad,direct_plus", "direct_undergrad", "education.loanKey" )
        };
        s.assumptions = {};
        var overrides = isStruct( r.assumptions ?: "" ) ? r.assumptions : {};
        for ( var k in overrides ) {
            if ( !structKeyExists( variables.assumptions.items, k ) ) continue;
            var def = variables.assumptions.items[ k ];
            s.assumptions[ k ] = v.numberInRange( overrides[ k ], def.min, def.max, def.value, k );
        }
        var tl = isStruct( r.timeline ?: "" ) ? r.timeline : {};
        s.timeline = {
            startAge: v.intInRange( tl.startAge ?: 18, 14, 40, 18, "timeline.startAge" ),
            mode: v.oneOf( tl.mode ?: "today", "today,projected", "today", "timeline.mode" ),
            ages: []
        };
        for ( var a in ( isArray( tl.ages ?: "" ) ? tl.ages : [ 18, 22, 25, 30, 40 ] ) ) {
            if ( isNumeric( a ) && a >= 14 && a <= 80 && arrayLen( s.timeline.ages ) < 8 ) arrayAppend( s.timeline.ages, int( a ) );
        }
        arraySort( s.timeline.ages, "numeric" );
        return s;
    }

    private struct function normalizeTile( required struct t, required any v ) {
        var out = { type: arguments.t.type };
        switch ( arguments.t.type ) {
            case "apartment":
                out.bedrooms = arguments.v.intInRange( arguments.t.bedrooms ?: 1, 0, 4, 1, "apartment.bedrooms" );
                out.benchmark = arguments.v.oneOf( arguments.t.benchmark ?: "acs", "acs,hud", "acs", "apartment.benchmark" );
                out.customRent = optionalNumber( arguments.t.customRent ?: javacast( "null", "" ), arguments.v, 0, 50000, "apartment.customRent" );
                break;
            case "house":
                out.bedrooms = arguments.v.intInRange( arguments.t.bedrooms ?: 3, 1, 6, 3, "house.bedrooms" );
                out.price = optionalNumber( arguments.t.price ?: javacast( "null", "" ), arguments.v, 10000, 20000000, "house.price" );
                break;
            case "roommates":
                out.count = arguments.v.intInRange( arguments.t.count ?: 1, 1, 4, 1, "roommates.count" );
                break;
            case "car":
            case "second_car":
                out.price = optionalNumber( arguments.t.price ?: javacast( "null", "" ), arguments.v, 0, 300000, "car.price" );
                break;
            case "children":
                out.count = arguments.v.intInRange( arguments.t.count ?: 1, 1, 6, 1, "children.count" );
                out.ageGroup = arguments.v.oneOf( arguments.t.ageGroup ?: "child_6_8", variables.ageGroups, "child_6_8", "children.ageGroup" );
                break;
            case "childcare":
                out.children = isNull( arguments.t.children ) ? javacast( "null", "" ) : arguments.v.intInRange( arguments.t.children, 0, 6, 1, "childcare.children" );
                break;
            case "travel":
                out.annual = optionalNumber( arguments.t.annual ?: javacast( "null", "" ), arguments.v, 0, 100000, "travel.annual" );
                break;
            case "savings":
                out.monthly = optionalNumber( arguments.t.monthly ?: javacast( "null", "" ), arguments.v, 0, 20000, "savings.monthly" );
                break;
            case "student_debt":
                out.principal = optionalNumber( arguments.t.principal ?: javacast( "null", "" ), arguments.v, 0, 1000000, "student_debt.principal" );
                break;
        }
        return out;
    }

    private any function optionalNumber( any value, required any v, required numeric lo, required numeric hi, required string field ) {
        if ( isNull( arguments.value ) || ( isSimpleValue( arguments.value ) && !len( trim( toString( arguments.value ) ) ) ) ) return javacast( "null", "" );
        return arguments.v.numberInRange( arguments.value, arguments.lo, arguments.hi, 0, arguments.field );
    }

    // ------------------------------------------------------------------ calculation

    public struct function compute( required struct scenario, required struct ref, boolean includeTimeline = true ) {
        var s = arguments.scenario;
        var ref = arguments.ref;
        var A = effectiveAssumptions( s );
        var warnings = [];
        var citations = [];
        var complete = true;
        var tile = tileIndex( s.tiles );

        // ---------------- income
        var earners = [];
        var wages = [];
        var pretax = [];
        for ( var e in s.earners ) {
            var w = ref.wages[ e.soc ] ?: javacast( "null", "" );
            var annual = javacast( "null", "" );
            var status = "missing";
            var message = "";
            if ( !isNull( e.customWage ) ) {
                annual = e.customWage;
                status = "custom";
            } else if ( !len( e.soc ) ) {
                message = "Choose a career to see income.";
            } else if ( isNull( w ) ) {
                message = "Wage data for this occupation has not been loaded.";
            } else {
                var candidate = isStruct( w.annual ?: "" ) ? ( w.annual[ e.percentile ] ?: javacast( "null", "" ) ) : javacast( "null", "" );
                if ( !isNull( candidate ) ) { annual = candidate; status = "sourced"; }
                else message = len( w.message ?: "" ) ? w.message : "BLS does not publish this wage percentile for this occupation here.";
            }
            if ( isNull( annual ) ) {
                complete = false;
                if ( len( message ) ) arrayAppend( warnings, message );
            }
            var gross = isNull( annual ) ? 0 : annual * e.workFraction;
            var retirement = gross * A.retirementPct / 100;
            arrayAppend( wages, gross );
            arrayAppend( pretax, retirement );
            arrayAppend( earners, {
                soc: e.soc, title: ref.occupations[ e.soc ].title ?: "", percentile: e.percentile, workFraction: e.workFraction,
                annualWage: annual, grossAnnual: gross, retirementAnnual: retirement, status: status, message: message,
                wageYear: isNull( w ) ? javacast( "null", "" ) : w.year, areaLevel: isNull( w ) ? javacast( "null", "" ) : w.areaLevel
            } );
            if ( status == "sourced" ) addCitation( citations, "wages", "BLS OEWS May #w.year#, #ref.metro.name# (#e.percentile#)", "https://www.bls.gov/oes/tables.htm" );
        }
        if ( !arrayLen( earners ) ) {
            complete = false;
            arrayAppend( warnings, "Add a career (or a custom wage) to see income." );
        }
        var children = structKeyExists( tile, "children" ) ? tile.children.count : 0;
        var taxResult = variables.taxes.estimate( {
            wages: arrayLen( wages ) ? wages : [ 0 ], pretax: arrayLen( pretax ) ? pretax : [ 0 ],
            filingStatus: s.filingStatus, children: children, stateCode: s.state, packs: ref.taxPacks
        } );
        for ( var tw in taxResult.warnings ) arrayAppend( warnings, tw );
        for ( var ru in taxResult.rulesUsed ) for ( var src in ru.sources ) addCitation( citations, "taxes", "#src.name# (#ru.jurisdiction# #ru.taxYear#)", src.url ?: "" );
        if ( arrayLen( s.earners ) == 2 && s.filingStatus == "single" ) arrayAppend( warnings, "Two earners filing as single: each earner is taxed on a separate return." );
        if ( s.filingStatus == "hoh" && children == 0 ) arrayAppend( warnings, "Head of household status usually requires a qualifying dependent." );
        var grossAnnual = arraySum( wages );
        var retirementAnnual = arraySum( pretax );
        var takeHomeAnnual = grossAnnual - taxResult.total - retirementAnnual;
        var takeHomeMonthly = takeHomeAnnual / 12;

        // ---------------- costs
        var lines = [];
        var members = s.adults + children;
        var upfront = { downPayment: 0, closingCosts: 0 };
        var housingMode = structKeyExists( tile, "house" ) ? "own" : ( structKeyExists( tile, "apartment" ) ? "rent" : "none" );
        if ( structKeyExists( tile, "house" ) && structKeyExists( tile, "apartment" ) ) arrayAppend( warnings, "You picked both House and Apartment. Only the house is counted (no rent and mortgage for the same home)." );
        if ( structKeyExists( tile, "roommates" ) && housingMode != "rent" ) arrayAppend( warnings, "Roommates only apply when renting an apartment." );

        if ( housingMode == "rent" ) {
            var apt = tile.apartment;
            var rentInfo = benchmarkRent( apt, ref.housing, warnings );
            var rent = rentInfo.value;
            var share = 1;
            if ( structKeyExists( tile, "roommates" ) ) {
                share = 1 / ( tile.roommates.count + 1 );
                if ( apt.bedrooms < tile.roommates.count + 1 ) arrayAppend( warnings, "With #tile.roommates.count# roommate(s), most people need at least #tile.roommates.count + 1# bedrooms." );
            }
            if ( isNull( rent ) ) complete = false;
            arrayAppend( lines, line( "rent", share < 1 ? "Your share of rent (incl. utilities)" : "Rent (incl. utilities)", "housing",
                isNull( rent ) ? javacast( "null", "" ) : rent * share, rentInfo.basis, rentInfo.label, rentInfo.note ) );
            if ( !isNull( rentInfo.citation ) ) addCitation( citations, "housing", rentInfo.citation.name, rentInfo.citation.url );
            arrayAppend( lines, line( "renters_insurance", "Renter's insurance", "housing", A.renterInsuranceMonthly, "assumption", "FuturePath assumption", "" ) );
        } else if ( housingMode == "own" ) {
            var house = tile.house;
            var price = house.price ?: ( isStruct( ref.housing.homeValue ?: "" ) ? ref.housing.homeValue.value : javacast( "null", "" ) );
            var priceBasis = isNull( house.price ) ? "sourced" : "user";
            if ( isNull( price ) ) {
                complete = false;
                arrayAppend( warnings, "No home value is available for this metro; enter a home price." );
                arrayAppend( lines, line( "mortgage", "Mortgage (principal + interest)", "housing", javacast( "null", "" ), "missing", "", "" ) );
            } else {
                if ( priceBasis == "sourced" ) addCitation( citations, "housing", "Census ACS median home value, #ref.housing.homeValue.period#", ref.housing.homeValue.sourceUrl );
                var loanAmount = price * ( 1 - A.downPaymentPct / 100 );
                var mort = variables.loans.amortize( loanAmount, A.mortgageRatePct, A.mortgageTermYears * 12 );
                upfront.downPayment = price * A.downPaymentPct / 100;
                upfront.closingCosts = price * A.closingCostPct / 100;
                var priceLabel = ( priceBasis == "sourced" ? "Metro median home value " : "Home price " ) & "$" & numberFormat( price, "," );
                arrayAppend( lines, line( "mortgage", "Mortgage (principal + interest)", "housing", mort.payment, "assumption", priceLabel & ", #A.downPaymentPct#% down, #A.mortgageRatePct#% for #A.mortgageTermYears# years", "" ) );
                arrayAppend( lines, line( "property_tax", "Property tax", "housing", price * A.propertyTaxPct / 100 / 12, "assumption", "#A.propertyTaxPct#% of value per year", "Property tax rates vary by county." ) );
                arrayAppend( lines, line( "home_insurance", "Homeowner's insurance", "housing", A.homeInsuranceMonthly, "assumption", "FuturePath assumption", "" ) );
                if ( A.downPaymentPct < 20 ) arrayAppend( lines, line( "pmi", "Mortgage insurance (PMI)", "housing", loanAmount * A.pmiPct / 100 / 12, "assumption", "#A.pmiPct#% of loan per year until 20% equity", "" ) );
                arrayAppend( lines, line( "maintenance", "Home maintenance", "housing", price * A.maintenancePct / 100 / 12, "assumption", "#A.maintenancePct#% of value per year", "" ) );
                if ( A.hoaMonthly > 0 ) arrayAppend( lines, line( "hoa", "HOA fees", "housing", A.hoaMonthly, "assumption", "", "" ) );
                arrayAppend( lines, line( "utilities", "Utilities", "housing", A.ownerUtilitiesMonthly, "assumption", "FuturePath assumption", "Homeowners pay utilities separately." ) );
            }
        } else {
            arrayAppend( warnings, "Add an Apartment or a House to include housing costs." );
        }

        // transportation
        var cars = ( structKeyExists( tile, "car" ) ? 1 : 0 ) + ( structKeyExists( tile, "second_car" ) ? 1 : 0 );
        for ( var ct in [ "car", "second_car" ] ) {
            if ( !structKeyExists( tile, ct ) ) continue;
            var carPrice = tile[ ct ].price ?: A.carPrice;
            var carLoan = variables.loans.amortize( carPrice * ( 1 - A.carDownPaymentPct / 100 ), A.carAprPct, A.carTermMonths );
            var label = ct == "car" ? "Car" : "Second car";
            arrayAppend( lines, line( ct & "_payment", "#label# payment", "transportation", carLoan.payment, "assumption", "$#numberFormat( carPrice, ',' )# car, #A.carDownPaymentPct#% down, #A.carAprPct#% for #A.carTermMonths# months", "" ) );
            arrayAppend( lines, line( ct & "_insurance", "#label# insurance", "transportation", A.carInsuranceMonthly, "assumption", "FuturePath assumption", "" ) );
            arrayAppend( lines, line( ct & "_running", "#label# gas and maintenance", "transportation", A.carFuelMaintenanceMonthly, "assumption", "FuturePath assumption", "" ) );
        }
        if ( cars == 0 ) arrayAppend( lines, line( "transit", "Public transit", "transportation", A.transitMonthlyPerAdult * s.adults, "assumption", "FuturePath assumption", "" ) );

        // food (USDA, national average, household-size adjusted)
        var food = foodCost( s.adults, children, structKeyExists( tile, "children" ) ? tile.children.ageGroup : "child_6_8", ref.food );
        if ( isNull( food.value ) ) {
            complete = false;
            arrayAppend( warnings, "USDA food plan costs are not loaded." );
        } else {
            addCitation( citations, "food", "USDA Food Plans, Moderate-Cost, U.S. average (#ref.food.period#)", ref.food.sourceUrl );
        }
        arrayAppend( lines, line( "food", "Groceries", "food", food.value, "sourced", "USDA Moderate-Cost Food Plan, U.S. average", "National average for food prepared at home; local prices differ." ) );
        arrayAppend( lines, line( "dining_out", "Eating out", "food", A.diningOutMonthlyPerAdult * s.adults, "assumption", "FuturePath assumption", "" ) );

        // childcare
        if ( structKeyExists( tile, "childcare" ) ) {
            if ( children == 0 ) {
                arrayAppend( warnings, "Childcare needs the Children tile." );
            } else {
                var inCare = min( children, tile.childcare.children ?: children );
                arrayAppend( lines, line( "childcare", "Childcare (#inCare# child#inCare == 1 ? '' : 'ren'#)", "childcare", inCare * A.childcareMonthlyPerChild, "assumption", "FuturePath assumption", "Childcare prices vary a lot by city and age." ) );
            }
        }

        // healthcare, phone, other
        arrayAppend( lines, line( "healthcare", "Health insurance and care", "healthcare", s.adults * A.healthcareMonthlyPerAdult + children * A.healthcareMonthlyPerChild, "assumption", "FuturePath assumption", "Employer plans vary widely." ) );
        arrayAppend( lines, line( "phone_internet", "Phone and internet", "other", A.phoneInternetMonthly, "assumption", "FuturePath assumption", "" ) );
        arrayAppend( lines, line( "other", "Clothing, personal care and household", "other", A.otherMonthlyPerPerson * members, "assumption", "FuturePath assumption", "" ) );

        // education
        var education = educationCosts( s, ref, warnings, citations );
        if ( structKeyExists( tile, "student_debt" ) ) {
            var principal = tile.student_debt.principal ?: education.borrowed;
            var loan = ref.loans[ s.education.loanKey ] ?: javacast( "null", "" );
            if ( isNull( principal ) ) {
                complete = false;
                arrayAppend( warnings, "Pick a school (or enter an amount) to estimate the student loan payment." );
                arrayAppend( lines, line( "student_loan", "Student loan payment", "education_debt", javacast( "null", "" ), "missing", "", "" ) );
            } else if ( isNull( loan ) ) {
                complete = false;
                arrayAppend( lines, line( "student_loan", "Student loan payment", "education_debt", javacast( "null", "" ), "missing", "Loan rate not loaded", "" ) );
            } else {
                var sl = variables.loans.amortize( principal, loan.rate, loan.months );
                education.monthlyPayment = sl.payment;
                education.totalInterest = sl.totalInterest;
                arrayAppend( lines, line( "student_loan", "Student loan payment", "education_debt", sl.payment, isNull( tile.student_debt.principal ) ? "sourced" : "user",
                    "$#numberFormat( principal, ',' )# at #loan.rate#% for #loan.months / 12# years", loan.description ) );
                addCitation( citations, "education", "Federal Student Aid, #loan.description# (#loan.rate#%)", loan.sourceUrl );
            }
        }

        // goals
        if ( structKeyExists( tile, "travel" ) ) arrayAppend( lines, line( "travel", "Travel and vacations", "savings", ( tile.travel.annual ?: A.travelAnnual ) / 12, isNull( tile.travel.annual ) ? "assumption" : "user", "", "" ) );
        if ( structKeyExists( tile, "savings" ) ) arrayAppend( lines, line( "emergency_savings", "Savings", "savings", tile.savings.monthly ?: A.emergencySavingsMonthly, isNull( tile.savings.monthly ) ? "assumption" : "user", "", "" ) );

        var monthlyCosts = 0;
        var categories = { housing: 0, transportation: 0, food: 0, childcare: 0, healthcare: 0, education_debt: 0, savings: 0, other: 0 };
        for ( var l in lines ) {
            if ( isNull( l.monthly ) ) continue;
            monthlyCosts += l.monthly;
            categories[ l.category ] += l.monthly;
        }
        var surplus = takeHomeMonthly - monthlyCosts;
        var timeline = arguments.includeTimeline ? buildTimeline( s, ref, A, earners, monthlyCosts, education, categories.education_debt, children ) : [];

        return {
            calculationVersion: variables.config.calculationVersion,
            complete: complete,
            income: {
                earners: earners, grossAnnual: grossAnnual, pretaxRetirementAnnual: retirementAnnual,
                taxes: taxResult, takeHomeAnnual: takeHomeAnnual, takeHomeMonthly: takeHomeMonthly
            },
            costs: { lines: lines, monthlyTotal: monthlyCosts, categories: categories },
            upfront: upfront,
            monthlySurplus: surplus,
            affordabilityRatio: takeHomeMonthly > 0 ? monthlyCosts / takeHomeMonthly : javacast( "null", "" ),
            coveragePercent: monthlyCosts > 0 ? min( 999, max( 0, takeHomeMonthly / monthlyCosts * 100 ) ) : javacast( "null", "" ),
            education: education,
            timeline: timeline,
            warnings: warnings,
            citations: citations,
            assumptionsUsed: A,
            dataYears: ref.dataYears ?: {}
        };
    }

    /**
     * Gross annual pay earner 1 would need for take-home to cover monthly costs (earner 2 unchanged).
     * Net-to-gross is not a fixed percentage, so this bisects over the tax calculator. Returns null if unreachable.
     */
    public any function requiredGross( required struct scenario, required struct ref ) {
        var s = duplicate( arguments.scenario );
        if ( !arrayLen( s.earners ) ) arrayAppend( s.earners, { soc: "", percentile: "median", workFraction: 1, customWage: 0 } );
        s.earners[ 1 ].customWage = 0;
        s.earners[ 1 ].workFraction = 1;
        var base = compute( s, arguments.ref, false );
        var target = base.costs.monthlyTotal;
        var lo = 0;
        var hi = 3000000;
        if ( takeHomeAt( s, arguments.ref, hi ) < target ) return javacast( "null", "" );
        for ( var i = 1; i <= 50; i++ ) {
            var mid = ( lo + hi ) / 2;
            if ( takeHomeAt( s, arguments.ref, mid ) >= target ) hi = mid; else lo = mid;
            if ( hi - lo < 1 ) break;
        }
        return { earner1Gross: ceiling( hi ), householdGross: ceiling( hi ) + ( arrayLen( s.earners ) > 1 ? base.income.earners[ 2 ].grossAnnual : 0 ), monthlyCosts: target };
    }

    private numeric function takeHomeAt( required struct s, required struct ref, required numeric gross ) {
        arguments.s.earners[ 1 ].customWage = arguments.gross;
        return compute( arguments.s, arguments.ref, false ).income.takeHomeMonthly;
    }

    // ------------------------------------------------------------------ helpers

    public struct function effectiveAssumptions( required struct scenario ) {
        var out = {};
        for ( var k in variables.assumptions.items ) {
            out[ k ] = arguments.scenario.assumptions[ k ] ?: variables.assumptions.items[ k ].value;
        }
        return out;
    }

    private struct function tileIndex( required array tiles ) {
        var idx = {};
        for ( var t in arguments.tiles ) idx[ t.type ] = t;
        return idx;
    }

    private struct function line( required string key, required string label, required string category, any monthly, required string basis, string detail = "", string note = "" ) {
        return { key: arguments.key, label: arguments.label, category: arguments.category, monthly: isNull( arguments.monthly ) ? javacast( "null", "" ) : arguments.monthly,
            basis: arguments.basis, detail: arguments.detail, note: arguments.note };
    }

    private void function addCitation( required array citations, required string topic, required string text, string url = "" ) {
        for ( var c in arguments.citations ) if ( c.text == arguments.text ) return;
        arrayAppend( arguments.citations, { topic: arguments.topic, text: arguments.text, url: arguments.url } );
    }

    private struct function benchmarkRent( required struct apt, required struct housing, required array warnings ) {
        var key = toString( arguments.apt.bedrooms );
        if ( !isNull( arguments.apt.customRent ) ) return { value: arguments.apt.customRent, basis: "user", label: "Your rent", note: "", citation: javacast( "null", "" ) };
        var acsValue = arguments.housing.acs.rents[ key ] ?: javacast( "null", "" );
        var hudArea = arrayLen( arguments.housing.hud.areas ?: [] ) ? arguments.housing.hud.areas[ 1 ] : javacast( "null", "" );
        var hudValue = isNull( hudArea ) ? javacast( "null", "" ) : ( hudArea.rents[ key ] ?: javacast( "null", "" ) );
        var bedLabel = arguments.apt.bedrooms == 0 ? "studio" : "#arguments.apt.bedrooms#-bedroom";
        var useAcs = arguments.apt.benchmark == "acs";
        if ( useAcs && isNull( acsValue ) && !isNull( hudValue ) ) {
            arrayAppend( arguments.warnings, "No ACS median rent for a #bedLabel# here; using the HUD Fair Market Rent instead." );
            useAcs = false;
        } else if ( !useAcs && isNull( hudValue ) && !isNull( acsValue ) ) {
            arrayAppend( arguments.warnings, "No HUD Fair Market Rent for a #bedLabel# here; using the ACS median rent instead." );
            useAcs = true;
        }
        if ( useAcs && !isNull( acsValue ) ) {
            return { value: acsValue, basis: "sourced", label: "ACS median gross rent, #bedLabel#, #arguments.housing.acs.period#", note: arguments.housing.acs.note,
                citation: { name: "Census ACS median gross rent (#arguments.housing.acs.period#)", url: arguments.housing.acs.sourceUrl } };
        }
        if ( !useAcs && !isNull( hudValue ) ) {
            if ( hudArea.quality == "partial" ) arrayAppend( arguments.warnings, "HUD splits this metro into several rent areas; using '#hudArea.name#'." );
            return { value: hudValue, basis: "sourced", label: "HUD Fair Market Rent, #bedLabel#, #hudArea.period#", note: arguments.housing.hud.note,
                citation: { name: "HUD Fair Market Rents #hudArea.period# (#hudArea.name#)", url: arguments.housing.hud.sourceUrl } };
        }
        arrayAppend( arguments.warnings, "No rent benchmark is published for a #bedLabel# in this metro. Enter your own rent." );
        return { value: javacast( "null", "" ), basis: "missing", label: "Not available", note: "", citation: javacast( "null", "" ) };
    }

    /** USDA Moderate-Cost plan: adults use the average of female and male 19-50; household-size adjustment per USDA. */
    private struct function foodCost( required numeric adults, required numeric children, required string ageGroup, any food ) {
        if ( isNull( arguments.food ) || !isStruct( arguments.food.moderate ?: "" ) ) return { value: javacast( "null", "" ) };
        var plan = arguments.food.moderate;
        if ( isNull( plan.female_19_50 ) || isNull( plan.male_19_50 ) ) return { value: javacast( "null", "" ) };
        var total = arguments.adults * ( plan.female_19_50 + plan.male_19_50 ) / 2 + arguments.children * ( plan[ arguments.ageGroup ] ?: plan.child_6_8 );
        var size = arguments.adults + arguments.children;
        var factor = size == 1 ? 1.20 : ( size == 2 ? 1.10 : ( size == 3 ? 1.05 : ( size == 4 ? 1 : ( size <= 6 ? 0.95 : 0.90 ) ) ) );
        return { value: total * factor };
    }

    private struct function educationCosts( required struct s, required struct ref, required array warnings, required array citations ) {
        var ed = arguments.s.education;
        var path = arguments.ref.pathways[ ed.pathway ] ?: javacast( "null", "" );
        var years = ed.years > 0 ? ed.years : ( isNull( path ) ? 0 : path.typicalYears );
        var out = {
            pathway: ed.pathway, pathwayName: isNull( path ) ? "" : path.name, years: years,
            annualNetPrice: javacast( "null", "" ), totalCost: javacast( "null", "" ), borrowed: javacast( "null", "" ),
            outOfPocketAnnual: javacast( "null", "" ), monthlyPayment: 0, totalInterest: 0, institution: javacast( "null", "" ), priceBasis: ""
        };
        var noTuition = listFind( "work,ged,apprenticeship", ed.pathway ) > 0;
        if ( noTuition || years == 0 ) {
            out.annualNetPrice = 0; out.totalCost = 0; out.borrowed = 0; out.outOfPocketAnnual = 0; out.priceBasis = "none";
            return out;
        }
        var price = ed.annualNetPrice;
        if ( !isNull( price ) ) {
            out.priceBasis = "user";
        } else if ( isStruct( arguments.ref.institution ?: "" ) && !isNull( arguments.ref.institution.costs.averageNetPrice ) ) {
            price = arguments.ref.institution.costs.averageNetPrice;
            out.priceBasis = "sourced";
            out.institution = { unitid: arguments.ref.institution.unitid, name: arguments.ref.institution.name };
            addCitation( arguments.citations, "education", "College Scorecard average net price, #arguments.ref.institution.name#", "https://collegescorecard.ed.gov/data/" );
        }
        if ( isNull( price ) ) {
            arrayAppend( arguments.warnings, "Pick a college (or enter a yearly price) to estimate education costs." );
            return out;
        }
        // Net price already subtracts average grants; extra grants here are scholarships beyond that average.
        var outOfPocket = max( 0, price - ed.grantsAnnual );
        var borrowedPerYear = max( 0, outOfPocket - ed.familyAnnual );
        out.annualNetPrice = price;
        out.outOfPocketAnnual = outOfPocket;
        out.totalCost = outOfPocket * years;
        out.borrowed = borrowedPerYear * years;
        return out;
    }

    /** Ages x phases: school years (cost, borrowing) then working years (wage, take-home, costs, debt, cumulative surplus). */
    private array function buildTimeline( required struct s, required struct ref, required struct A, required array earners, required numeric monthlyCosts, required struct education, required numeric monthlyDebt, numeric children = 0 ) {
        var startAge = arguments.s.timeline.startAge;
        var maxAge = arrayLen( arguments.s.timeline.ages ) ? arguments.s.timeline.ages[ arrayLen( arguments.s.timeline.ages ) ] : 40;
        var projected = arguments.s.timeline.mode == "projected";
        var infl = projected ? arguments.A.inflationPct / 100 : 0;
        var growth = projected ? ( 1 + infl ) * ( 1 + arguments.A.wageGrowthPct / 100 ) - 1 : 0;
        var schoolYears = int( arguments.education.years ?: 0 );
        var borrowed = arguments.education.borrowed ?: 0;
        var loan = arguments.ref.loans[ arguments.s.education.loanKey ] ?: { rate: 0, months: 120 };
        var baseWages = [];
        for ( var e in arguments.earners ) arrayAppend( baseWages, e.grossAnnual );
        var nonDebtAnnual = ( arguments.monthlyCosts - arguments.monthlyDebt ) * 12;
        var debtAnnual = arguments.monthlyDebt * 12;
        var cumulative = 0;
        var points = [];
        for ( var age = startAge; age <= maxAge; age++ ) {
            var t = age - startAge;
            var inSchool = t < schoolYears;
            var row = { age: age, phase: inSchool ? "school" : "working", wage: 0, takeHome: 0, livingCosts: 0, debtPayments: 0, debtBalance: 0, educationCost: 0, surplus: 0, cumulativeSurplus: 0 };
            if ( inSchool ) {
                row.educationCost = ( arguments.education.outOfPocketAnnual ?: 0 );
                row.debtBalance = schoolYears > 0 ? borrowed / schoolYears * ( t + 1 ) : 0;
            } else {
                var yearsWorking = t - schoolYears;
                var factor = ( 1 + growth ) ^ yearsWorking;
                var w = [];
                for ( var bw in baseWages ) arrayAppend( w, bw * factor );
                var gross = arraySum( w );
                var pre = [];
                for ( var x in w ) arrayAppend( pre, x * arguments.A.retirementPct / 100 );
                var tax = arrayLen( w ) ? variables.taxes.estimate( { wages: w, pretax: pre, filingStatus: arguments.s.filingStatus, children: arguments.children, stateCode: arguments.s.state, packs: arguments.ref.taxPacks } ).total : 0;
                row.wage = gross;
                row.takeHome = gross - tax - arraySum( pre );
                row.livingCosts = nonDebtAnnual * ( 1 + infl ) ^ t;
                row.debtPayments = yearsWorking < loan.months / 12 ? debtAnnual : 0;
                row.debtBalance = borrowed > 0 && debtAnnual > 0 ? variables.loans.balanceAfter( borrowed, loan.rate, loan.months, yearsWorking * 12 ) : ( debtAnnual > 0 ? 0 : borrowed );
                row.surplus = row.takeHome - row.livingCosts - row.debtPayments;
                cumulative += row.surplus;
            }
            row.cumulativeSurplus = cumulative;
            if ( arrayFind( arguments.s.timeline.ages, age ) ) arrayAppend( points, row );
        }
        return points;
    }

}
