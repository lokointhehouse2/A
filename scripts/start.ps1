# Starts the development MariaDB (when Docker is available) and FuturePath on port 42005.
. "$PSScriptRoot\_common.ps1"

Set-Location $ProjectRoot
Initialize-DotEnv
$envValues = Read-DotEnv
$baseUrl = Get-EnvValue $envValues 'APP_BASE_URL' 'http://127.0.0.1:42005'
$box = Find-Box
if (-not $box) { Show-BoxInstallHelp; exit 1 }
Set-JavaTrust
$free = Assert-PortFree
if (Start-DockerIfNeeded) { Start-Database | Out-Null } else { Write-Warn2 'Docker unavailable: using the MariaDB server configured in .env' }
if ($free) {
    Write-Step 'Starting CommandBox / Lucee'
    & $box server start
    if ($LASTEXITCODE -ne 0) { exit 1 }
}
if (Wait-ForHealth $baseUrl 240) { Write-Ok 'Healthy' } else { Write-Warn2 "Not healthy yet; check $baseUrl/api/health" }
Write-Host "  FuturePath is running at $baseUrl" -ForegroundColor Green
