# Focused smoke check of a running FuturePath instance (one pass; re-run only after fixing a failure).
. "$PSScriptRoot\_common.ps1"
$envValues = Read-DotEnv
$base = Get-EnvValue $envValues 'APP_BASE_URL' 'http://127.0.0.1:42005'
$failures = 0
function Check([string]$name, [scriptblock]$test) {
    try { $ok = & $test } catch { $ok = $false; $err = $_.Exception.Message }
    if ($ok) { Write-Host "  PASS $name" -ForegroundColor Green } else { Write-Host "  FAIL $name $err" -ForegroundColor Red; $script:failures++ }
}
function Get-Json([string]$path) { Invoke-RestMethod -Uri "$base$path" -TimeoutSec 60 }
function Post-Json([string]$path, $body) { Invoke-RestMethod -Uri "$base$path" -Method Post -ContentType 'application/json' -Body ($body | ConvertTo-Json -Depth 10) -TimeoutSec 120 }

Write-Step "Smoke checking $base"
Check 'health' { (Get-Json '/api/health').data.database -eq 'ok' }
foreach ($soc in '15-1252', '47-2031', '35-3023') {
    foreach ($cbsa in '36740', '35620', '47900') {
        Check "wage $soc in $cbsa (sourced or explicit status)" {
            $w = (Get-Json "/api/v1/occupations/$soc/wages?cbsa=$cbsa").data
            ($w.local.status -eq 'available' -and $w.local.annual.median -gt 0 -and $w.local.year -ge 2025) -or ($w.local.status -in 'partial', 'not_published' -and $w.local.message)
        }
    }
}
Check 'English program -> possible careers (CIP-SOC)' { @((Get-Json '/api/v1/programs/23.01/careers?cbsa=36740').data.careers | Where-Object { $_.soc -eq '25-1123' }).Count -eq 1 }
Check 'college search + programs' { (Get-Json '/api/v1/institutions/132903/programs').data.programs.Count -gt 10 }
$scenario = @{ cbsa = '36740'; state = 'FL'; filingStatus = 'mfj'; adults = 2; earners = @(@{ soc = '25-2031'; percentile = 'median' });
    tiles = @(@{ type = 'house'; bedrooms = 3 }, @{ type = 'car' }, @{ type = 'second_car' }, @{ type = 'children'; count = 2 }, @{ type = 'savings' }) }
Check 'calculate (3-bedroom house, 2 kids, 2 cars, savings)' { $r = (Post-Json '/api/v1/simulations/calculate' @{ scenario = $scenario }).data.result; $r.complete -and $r.costs.monthlyTotal -gt 0 -and $r.citations.Count -gt 2 }
Check 'reverse careers suggests occupations with local wage evidence' { $d = (Post-Json '/api/v1/simulations/reverse-careers' @{ scenario = $scenario; options = @{ limit = 10 } }).data; $d.required.earner1Gross -gt 0 -and $d.affordable.Count -gt 0 }
Check 'admin requires sign-in' {
    $req = [System.Net.HttpWebRequest]::Create("$base/admin/imports")
    $req.AllowAutoRedirect = $false
    try { $resp = $req.GetResponse() } catch [System.Net.WebException] { $resp = $_.Exception.Response }
    $ok = ([int]$resp.StatusCode -eq 302) -and ($resp.Headers['Location'] -match '/admin/login')
    $resp.Close()
    $ok
}
Check 'home page renders' { (Invoke-WebRequest -Uri "$base/" -UseBasicParsing).Content -match 'Dream big' }
if ($failures) { Write-Host "$failures check(s) failed" -ForegroundColor Red; exit 1 } else { Write-Host 'All smoke checks passed' -ForegroundColor Green }
