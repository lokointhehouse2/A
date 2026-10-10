/**
 * Simplified, versioned income and payroll tax estimator (not tax advice).
 *
 * Tax rules live in tax_rules and are assembled into "tax packs" (the same structure the browser engine uses):
 *   { jurisdiction, taxYear, requestedYear, noIncomeTax, standardDeduction{status}, brackets{status:[{lower,upper,rate}]},
 *     socialSecurity{rate,wageBase}, medicare{rate}, additionalMedicare{status:{threshold,rate}}, childTaxCredit{...}, sources[] }
 *
 * Simplifications (documented in docs/ASSUMPTIONS.md): wages are the only income; standard deduction only;
 * state taxable income starts from federal AGI; personal exemptions, most credits, NY supplemental tax,
 * and local taxes other than NYC are not modeled. Pre-tax retirement contributions reduce income tax but not FICA.
 */
component {

    variables.dsn = "futurepathDB";
    variables.statuses = [ "single", "mfj", "hoh" ];

    /** Tax pack for a jurisdiction; falls back to the latest earlier year (flagged), or null when nothing is modeled. */
    public any function pack( required string jurisdiction, required numeric taxYear ) {
        var yq = queryExecute( "SELECT MAX(tax_year) AS y FROM tax_rules WHERE jurisdiction_code = :j AND tax_year <= :y", {
            j: { value: arguments.jurisdiction, cfsqltype: "varchar" }, y: { value: arguments.taxYear, cfsqltype: "smallint" }
        }, { datasource: variables.dsn } );
        if ( isNull( yq.y ) || !len( yq.y ) ) return javacast( "null", "" );
        var year = yq.y;
        var rows = queryExecute( "
            SELECT r.filing_status, r.rule_type, r.lower_bound, r.upper_bound, r.rate, r.fixed_amount, r.parameters_json, r.source_url, s.name AS source_name
            FROM tax_rules r JOIN data_sources s ON s.id = r.source_id
            WHERE r.jurisdiction_code = :j AND r.tax_year = :y ORDER BY r.rule_type, r.filing_status, r.lower_bound", {
            j: { value: arguments.jurisdiction, cfsqltype: "varchar" }, y: { value: year, cfsqltype: "smallint" }
        }, { datasource: variables.dsn, returntype: "array" } );
        var p = {
            jurisdiction: arguments.jurisdiction, taxYear: year, requestedYear: arguments.taxYear, noIncomeTax: false,
            standardDeduction: {}, brackets: {}, socialSecurity: javacast( "null", "" ), medicare: javacast( "null", "" ),
            additionalMedicare: {}, childTaxCredit: javacast( "null", "" ), sources: []
        };
        var seenSources = {};
        for ( var r in rows ) {
            var statuses = r.filing_status == "all" ? variables.statuses : [ r.filing_status ];
            switch ( r.rule_type ) {
                case "no_income_tax": p.noIncomeTax = true; break;
                case "standard_deduction":
                    for ( var s in statuses ) p.standardDeduction[ s ] = val( r.fixed_amount );
                    break;
                case "bracket":
                    for ( var s in statuses ) {
                        if ( !structKeyExists( p.brackets, s ) ) p.brackets[ s ] = [];
                        arrayAppend( p.brackets[ s ], { lower: val( r.lower_bound ), upper: isNull( r.upper_bound ) ? javacast( "null", "" ) : val( r.upper_bound ), rate: val( r.rate ) } );
                    }
                    break;
                case "social_security": p.socialSecurity = { rate: val( r.rate ), wageBase: val( r.upper_bound ) }; break;
                case "medicare": p.medicare = { rate: val( r.rate ) }; break;
                case "additional_medicare":
                    for ( var s in statuses ) p.additionalMedicare[ s ] = { threshold: val( r.lower_bound ), rate: val( r.rate ) };
                    break;
                case "child_tax_credit":
                    var params = deserializeJSON( r.parameters_json );
                    p.childTaxCredit = {
                        amountPerChild: val( r.fixed_amount ), refundableMaxPerChild: params.refundableMaxPerChild,
                        refundableEarnedIncomeFloor: params.refundableEarnedIncomeFloor, refundableRate: params.refundableRate,
                        phaseoutStart: params.phaseoutStart, phaseoutPerThousand: params.phaseoutPerThousand
                    };
                    break;
            }
            if ( !structKeyExists( seenSources, r.source_name ) ) {
                seenSources[ r.source_name ] = true;
                arrayAppend( p.sources, { name: r.source_name, url: r.source_url } );
            }
        }
        return p;
    }

    /** Packs needed for a residence: federal, state and (NYC residents) local. */
    public struct function packsFor( required string stateCode, required boolean nycResident, required numeric taxYear ) {
        var out = { federal: pack( "US", arguments.taxYear ), state: javacast( "null", "" ), local: javacast( "null", "" ) };
        if ( len( arguments.stateCode ) ) out.state = pack( arguments.stateCode, arguments.taxYear );
        if ( arguments.nycResident && arguments.stateCode == "NY" ) out.local = pack( "NYC", arguments.taxYear );
        return out;
    }

    /** Progressive bracket tax: sum of rate x (min(income, upper) - lower) over brackets. */
    public numeric function bracketTax( required numeric taxable, required array brackets ) {
        var tax = 0;
        for ( var b in arguments.brackets ) {
            if ( arguments.taxable <= b.lower ) continue;
            var top = isNull( b.upper ) ? arguments.taxable : min( arguments.taxable, b.upper );
            tax += ( top - b.lower ) * b.rate;
        }
        return tax;
    }

    /**
     * input: { wages:[w1,(w2)], pretax:[p1,(p2)], filingStatus, children, stateCode, packs:{federal,state,local} }
     * Two earners with filingStatus "mfj" file jointly; otherwise each earner files separately
     * (earner 1 with the chosen status and the children, earner 2 as single).
     */
    public struct function estimate( required struct input ) {
        var inp = arguments.input;
        var wages = inp.wages;
        var pretax = inp.pretax ?: [];
        if ( arrayLen( wages ) == 2 && inp.filingStatus != "mfj" ) {
            var a = estimateReturn( [ wages[ 1 ] ], [ pretax[ 1 ] ?: 0 ], inp.filingStatus, inp.children ?: 0, inp );
            var b = estimateReturn( [ wages[ 2 ] ], [ pretax[ 2 ] ?: 0 ], "single", 0, inp );
            var combined = {};
            for ( var k in [ "federalIncomeTax", "childTaxCredit", "stateIncomeTax", "localIncomeTax", "socialSecurity", "medicare", "additionalMedicare", "total", "agi" ] ) combined[ k ] = a[ k ] + b[ k ];
            combined.returns = [ a, b ];
            combined.filing = "separate";
            combined.warnings = a.warnings;
            for ( var w in b.warnings ) if ( !arrayFind( combined.warnings, w ) ) arrayAppend( combined.warnings, w );
            arrayAppend( combined.warnings, "Two earners who are not married file separate returns; earner 1 claims the children." );
            combined.stateModeled = a.stateModeled;
            combined.rulesUsed = a.rulesUsed;
            return combined;
        }
        var single = estimateReturn( wages, pretax, inp.filingStatus, inp.children ?: 0, inp );
        single.filing = arrayLen( wages ) == 2 ? "joint" : "single-return";
        single.returns = [ duplicate( single ) ];
        return single;
    }

    private struct function estimateReturn( required array wages, required array pretax, required string status, required numeric children, required struct inp ) {
        var fed = arguments.inp.packs.federal;
        var warnings = [];
        var rulesUsed = [];
        var totalWages = 0;
        var totalPretax = 0;
        var ss = 0;
        var medicare = 0;
        for ( var i = 1; i <= arrayLen( arguments.wages ); i++ ) {
            var w = max( 0, arguments.wages[ i ] );
            totalWages += w;
            totalPretax += min( w, max( 0, arguments.pretax[ i ] ?: 0 ) );
            ss += min( w, fed.socialSecurity.wageBase ) * fed.socialSecurity.rate;
            medicare += w * fed.medicare.rate;
        }
        var addl = fed.additionalMedicare[ arguments.status ] ?: { threshold: 200000, rate: 0.009 };
        var additionalMedicare = max( 0, totalWages - addl.threshold ) * addl.rate;
        var agi = totalWages - totalPretax;

        var fedTaxable = max( 0, agi - ( fed.standardDeduction[ arguments.status ] ?: 0 ) );
        var fedTax = bracketTax( fedTaxable, fed.brackets[ arguments.status ] );
        arrayAppend( rulesUsed, { jurisdiction: "US", taxYear: fed.taxYear, sources: fed.sources } );

        // Child Tax Credit: nonrefundable up to tax liability; refundable part limited per child and by earned income.
        var ctc = 0;
        if ( arguments.children > 0 && !isNull( fed.childTaxCredit ) ) {
            var c = fed.childTaxCredit;
            var credit = arguments.children * c.amountPerChild;
            var start = c.phaseoutStart[ arguments.status ] ?: 200000;
            if ( agi > start ) credit = max( 0, credit - ceiling( ( agi - start ) / 1000 ) * c.phaseoutPerThousand );
            var nonRefundable = min( credit, fedTax );
            var refundable = min( min( credit - nonRefundable, arguments.children * c.refundableMaxPerChild ), max( 0, ( totalWages - c.refundableEarnedIncomeFloor ) * c.refundableRate ) );
            ctc = nonRefundable + max( 0, refundable );
        }

        var stateTax = 0;
        var stateModeled = true;
        var st = arguments.inp.packs.state ?: javacast( "null", "" );
        var stateCode = arguments.inp.stateCode ?: "";
        var stateTaxable = 0;
        if ( isNull( st ) ) {
            stateModeled = false;
            if ( len( stateCode ) ) arrayAppend( warnings, "State income tax for #stateCode# is not modeled yet, so take-home pay is overstated for #stateCode# residents." );
        } else if ( st.noIncomeTax ) {
            arrayAppend( rulesUsed, { jurisdiction: st.jurisdiction, taxYear: st.taxYear, sources: st.sources } );
        } else {
            stateTaxable = max( 0, agi - ( st.standardDeduction[ arguments.status ] ?: 0 ) );
            stateTax = bracketTax( stateTaxable, st.brackets[ arguments.status ] ?: [] );
            arrayAppend( rulesUsed, { jurisdiction: st.jurisdiction, taxYear: st.taxYear, sources: st.sources } );
            if ( st.taxYear != st.requestedYear ) arrayAppend( warnings, "#st.jurisdiction# tax uses the latest published #st.taxYear# rules." );
        }
        var localTax = 0;
        var loc = arguments.inp.packs.local ?: javacast( "null", "" );
        if ( !isNull( loc ) ) {
            localTax = bracketTax( stateTaxable, loc.brackets[ arguments.status ] ?: [] );
            arrayAppend( rulesUsed, { jurisdiction: loc.jurisdiction, taxYear: loc.taxYear, sources: loc.sources } );
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

}
