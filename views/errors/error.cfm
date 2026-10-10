<cfscript>
status = request.errorStatus ?: 500;
messages = {
    "404": [ "We couldn't find that page.", request.errorMessage ?: "The link may be old, or the data it points to isn't imported." ],
    "405": [ "That action isn't allowed here.", "Try going back and using the page's buttons." ],
    "422": [ "Something in that request didn't look right.", request.errorMessage ?: "Please check the values and try again." ],
    "500": [ "Something went wrong on our side.", "Please try again in a moment." ]
};
pair = messages[ toString( status ) ] ?: messages[ "500" ];
</cfscript>
<cfoutput><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>#encodeForHTML( pair[ 1 ] )# · FuturePath</title>
    <link rel="stylesheet" href="/assets/vendor/bootstrap/bootstrap.min.css">
    <link rel="stylesheet" href="/assets/css/app.css">
</head>
<body>
<main class="container py-5 error-page">
    <p class="display-6 fw-bold">#encodeForHTML( pair[ 1 ] )#</p>
    <p class="lead">#encodeForHTML( pair[ 2 ] )#</p>
    <p><a class="btn btn-primary" href="/">Go to the home page</a> <a class="btn btn-outline-primary ms-2" href="/builder">Open the Future Builder</a></p>
</main>
</body>
</html>
</cfoutput>
