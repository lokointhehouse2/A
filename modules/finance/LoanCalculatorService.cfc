/**
 * Standard amortization: payment = P * r / (1 - (1 + r)^-n), r = APR / 12. Zero rate -> P / n.
 */
component {

    public struct function amortize( required numeric principal, required numeric aprPercent, required numeric months ) {
        if ( arguments.months <= 0 || int( arguments.months ) != arguments.months ) throw( type = "Validation", message = "Loan term must be a whole number of months greater than zero." );
        if ( arguments.aprPercent < 0 ) throw( type = "Validation", message = "Interest rate cannot be negative." );
        if ( arguments.principal <= 0 ) return { payment: 0, totalPaid: 0, totalInterest: 0, months: arguments.months, aprPercent: arguments.aprPercent, principal: 0 };
        var r = arguments.aprPercent / 100 / 12;
        var payment = r == 0 ? arguments.principal / arguments.months : arguments.principal * r / ( 1 - ( 1 + r ) ^ ( -arguments.months ) );
        return {
            payment: payment, totalPaid: payment * arguments.months, totalInterest: payment * arguments.months - arguments.principal,
            months: arguments.months, aprPercent: arguments.aprPercent, principal: arguments.principal
        };
    }

    /** Remaining balance after k payments. */
    public numeric function balanceAfter( required numeric principal, required numeric aprPercent, required numeric months, required numeric paymentsMade ) {
        if ( arguments.principal <= 0 ) return 0;
        var k = min( max( 0, arguments.paymentsMade ), arguments.months );
        var r = arguments.aprPercent / 100 / 12;
        if ( r == 0 ) return max( 0, arguments.principal - arguments.principal / arguments.months * k );
        var payment = amortize( arguments.principal, arguments.aprPercent, arguments.months ).payment;
        return max( 0, arguments.principal * ( 1 + r ) ^ k - payment * ( ( ( 1 + r ) ^ k - 1 ) / r ) );
    }

}
