# Focused test run (development): JS engine fixtures (Node), TestBox suite and browser UI tests (headless Chrome/Edge).
. "$PSScriptRoot\_common.ps1"
Set-Location $ProjectRoot
$envValues = Read-DotEnv
$base = Get-EnvValue $envValues 'APP_BASE_URL' 'http://127.0.0.1:42005'
$failed = $false

Write-Step 'JS engine (node tests/js/engine.test.js)'
& node tests/js/engine.test.js
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Step 'TestBox suite (/dev/tests)'
$report = (Invoke-WebRequest -Uri "$base/dev/tests" -UseBasicParsing -TimeoutSec 600).Content
$summary = ($report -split "`n" | Select-String 'Passed: .*Failed: .*Errors' | Select-Object -Last 1).ToString()
Write-Host "    $summary"
if ($summary -notmatch 'Failed: 0\] \[Errors: 0') { $failed = $true; Write-Host $report }

Write-Step 'Browser UI tests (/dev/ui-tests)'
$browser = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($browser) {
    $uiProfile = Join-Path $env:TEMP 'futurepath-ui-tests'
    $outFile = Join-Path $env:TEMP 'futurepath-ui-tests.html'
    # Chrome/Edge are GUI-subsystem executables: run them to completion and read the dumped DOM from a file.
    Start-Process -FilePath $browser -Wait -NoNewWindow -RedirectStandardOutput $outFile -ArgumentList @('--headless=new', '--disable-gpu', '--no-first-run', "--user-data-dir=$uiProfile", '--window-size=1800,1000', '--virtual-time-budget=120000', '--dump-dom', "$base/dev/ui-tests")
    $dom = Get-Content $outFile -Raw
    $lines = ($dom -join "`n") -split "`n" | Where-Object { $_ -match '^(PASS|FAIL|UI TESTS DONE)' -or $_ -match '<pre id="results">' }
    $lines | ForEach-Object { Write-Host ('    ' + ($_ -replace '<[^>]+>', '')) }
    if (($dom -join "`n") -notmatch 'UI TESTS DONE pass=\d+ fail=0') { $failed = $true }
} else { Write-Warn2 'Chrome/Edge not found; open /dev/ui-tests in a browser to run the UI tests.' }

if ($failed) { Write-Host 'Some tests failed' -ForegroundColor Red; exit 1 } else { Write-Host 'All tests passed' -ForegroundColor Green }
