# FuturePath first-time setup (Windows / PowerShell).
#   1. creates .env with random local secrets   2. finds CommandBox   3. starts Docker + MariaDB (port 3308)
#   4. installs TestBox (dev)   5. starts Lucee on port 42005 (migrations, seeds and data imports run automatically)
. "$PSScriptRoot\_common.ps1"

Set-Location $ProjectRoot
Write-Step 'Preparing environment file'
Initialize-DotEnv
$envValues = Read-DotEnv
$baseUrl = Get-EnvValue $envValues 'APP_BASE_URL' 'http://127.0.0.1:42005'
if (-not (Get-EnvValue $envValues 'BLS_CONTACT_EMAIL' '')) {
    Write-Warn2 'BLS_CONTACT_EMAIL is empty. BLS only allows automated downloads that identify a contact email;'
    Write-Warn2 'set it in .env (or upload the BLS files from /admin/imports) to load wage data.'
}

Write-Step 'Checking for CommandBox'
$box = Find-Box
if (-not $box) { Show-BoxInstallHelp; exit 1 }
Write-Ok "Using $box"
Set-JavaTrust

Write-Step "Checking port $AppPort"
$free = Assert-PortFree

Write-Step 'Checking Docker'
if (Start-DockerIfNeeded) { Start-Database | Out-Null }
else {
    Write-Warn2 'Skipping the Docker database. Create the database and a least-privilege user on your MariaDB server first:'
    Write-Host  "      CREATE DATABASE futurepath CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    Write-Host  "      CREATE USER 'futurepath_app'@'%' IDENTIFIED BY '<DB_PASSWORD>';"
    Write-Host  "      GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES ON futurepath.* TO 'futurepath_app'@'%';"
}

Write-Step 'Installing development dependencies (TestBox)'
& $box install --dev | Out-Null

if ($free) {
    Write-Step 'Starting CommandBox / Lucee on port 42005 (first start downloads Lucee, Java 21 and Apache POI)'
    & $box server start
    if ($LASTEXITCODE -ne 0) { Write-Warn2 'box server start reported an error. See: box server log'; exit 1 }
}

Write-Step 'Waiting for the application and database migrations'
if (Wait-ForHealth $baseUrl 420) { Write-Ok 'FuturePath is up. Public data imports continue in the background (see /admin/imports).' }
else { Write-Warn2 "The app did not report a healthy database yet. Check $baseUrl/api/health and 'box server log'." }

Write-Host ''
Write-Host "  FuturePath:   $baseUrl" -ForegroundColor Green
Write-Host "  Admin:        $baseUrl/admin  (email/password: ADMIN_INITIAL_EMAIL / ADMIN_INITIAL_PASSWORD in .env)" -ForegroundColor Green
Write-Host ''
