<cfoutput>
<div class="container-xl py-4 narrow">
    <h1 class="h2 fw-bold">How FuturePath works</h1>
    <p class="lead">FuturePath connects four questions: where you want to live, how you want to live, what work you might do, and what training gets you there.</p>
    <h2 class="h4 mt-4">The math</h2>
    <ol>
        <li><strong>Pay.</strong> We use the wage BLS publishes for that occupation in that metro area (you pick the percentile). Part-time multiplies it by the share of full time.</li>
        <li><strong>Take-home.</strong> We subtract estimated federal income tax, state (and New York City) income tax where we've modeled it, Social Security and Medicare, and your pre-tax retirement savings: <code>(pay &minus; taxes &minus; retirement) &divide; 12</code>.</li>
        <li><strong>Costs.</strong> Rent or mortgage (never both), transportation, groceries, eating out, childcare, health costs, phone, student loans, travel and savings.</li>
        <li><strong>Result.</strong> Take-home minus costs = what's left (or how much you're short) each month.</li>
        <li><strong>Reverse search.</strong> We find the pay that covers your budget after taxes by trying values (taxes aren't a fixed percentage), then compare it with real local wages for every occupation BLS publishes there.</li>
    </ol>
    <h2 class="h4 mt-4">What the numbers are&mdash;and aren't</h2>
    <ul>
        <li>A wage percentile describes how pay is spread among people doing the job today. The 90th percentile is not "where you'll be in 20 years."</li>
        <li>A degree doesn't guarantee a job. The program-to-career links come from an official crosswalk of what programs prepare people for, not where graduates ended up.</li>
        <li>College Scorecard earnings describe former students of a program. BLS wages describe workers in an occupation. We show them separately because they measure different things.</li>
        <li>Some jobs need more: K&ndash;12 teachers need a state license, professors typically need a doctorate, physicians need medical school plus residency, many trades need a license after an apprenticeship.</li>
        <li>When a value isn't published (too few workers, privacy rules), we say so. We never fill it in with a made-up number or a zero.</li>
    </ul>
    <h2 class="h4 mt-4">Every path is real</h2>
    <p>Working right after high school, earning a GED, an apprenticeship, a certificate, an associate degree, a bachelor's or graduate school can all lead to good lives. FuturePath helps you compare time, cost, pay and lifestyle so you can decide what fits you.</p>
    <p><a class="btn btn-primary" href="/builder">Build My Future</a> <a class="btn btn-outline-primary ms-2" href="/sources">See all data sources</a></p>
</div>
</cfoutput>
