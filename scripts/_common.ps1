# Shared helpers for FuturePath dev scripts. Dot-source: . "$PSScriptRoot\_common.ps1"
$ErrorActionPreference = 'Stop'
$script:ProjectRoot = Split-Path -Parent $PSScriptRoot
$script:DbContainer = 'futurepath-mariadb'
$script:AppPort = 42005

function Write-Step([string]$message) { Write-Host "==> $message" -ForegroundColor Cyan }
function Write-Ok([string]$message) { Write-Host "    $message" -ForegroundColor Green }
function Write-Warn2([string]$message) { Write-Host "    $message" -ForegroundColor Yellow }

function Read-DotEnv {
    $values = @{}
    $path = Join-Path $script:ProjectRoot '.env'
    if (-not (Test-Path $path)) { return $values }
    foreach ($line in Get-Content $path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#') -or -not $t.Contains('=')) { continue }
        $idx = $t.IndexOf('=')
        $values[$t.Substring(0, $idx).Trim()] = $t.Substring($idx + 1).Trim().Trim('"').Trim("'")
    }
    return $values
}

function Get-EnvValue([hashtable]$envValues, [string]$key, [string]$default) {
    if ($envValues.ContainsKey($key) -and $envValues[$key]) { return $envValues[$key] }
    return $default
}

function New-Secret([int]$bytes = 18) {
    $buffer = New-Object byte[] $bytes
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buffer)
    return ([Convert]::ToBase64String($buffer)).Replace('+', 'x').Replace('/', 'y').TrimEnd('=')
}

# Creates .env from .env.example with random local secrets (never committed). Existing .env is left alone.
function Initialize-DotEnv {
    $envPath = Join-Path $script:ProjectRoot '.env'
    if (-not (Test-Path $envPath)) {
        $content = Get-Content (Join-Path $script:ProjectRoot '.env.example') -Raw
        $content = $content -replace '(?m)^DB_PASSWORD=.*$', "DB_PASSWORD=$(New-Secret)"
        $content = $content -replace '(?m)^DB_ROOT_PASSWORD=.*$', "DB_ROOT_PASSWORD=$(New-Secret)"
        $content = $content -replace '(?m)^APP_SECRET=.*$', "APP_SECRET=$(New-Secret 32)"
        $content = $content -replace '(?m)^ADMIN_INITIAL_EMAIL=.*$', 'ADMIN_INITIAL_EMAIL=admin@futurepath.local'
        $content = $content -replace '(?m)^ADMIN_INITIAL_PASSWORD=.*$', "ADMIN_INITIAL_PASSWORD=$(New-Secret 12)"
        [System.IO.File]::WriteAllText($envPath, $content)  # UTF-8 without BOM
        Write-Ok 'Created .env with random local passwords (see ADMIN_INITIAL_PASSWORD for the admin login)'
    }
    if ($env:OS -eq 'Windows_NT') {
        $content = Get-Content $envPath -Raw
        if ($content -match '(?m)^JAVA_TRUSTSTORE_ARGS=\s*$') {
            $content = $content -replace '(?m)^JAVA_TRUSTSTORE_ARGS=\s*$', 'JAVA_TRUSTSTORE_ARGS=-Djavax.net.ssl.trustStoreType=Windows-ROOT'
            [System.IO.File]::WriteAllText($envPath, $content)
            Write-Ok 'Configured Java to trust the Windows certificate store (JAVA_TRUSTSTORE_ARGS)'
        }
    }
}

function Find-Box {
    $cmd = Get-Command box -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($candidate in @('C:\App\box.exe', "$env:USERPROFILE\CommandBox\box.exe", 'C:\CommandBox\box.exe', "$env:ProgramFiles\CommandBox\box.exe", "$env:LOCALAPPDATA\CommandBox\box.exe")) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

function Show-BoxInstallHelp {
    Write-Warn2 'CommandBox was not found. Install CommandBox 6.x (choco install commandbox, or https://www.ortussolutions.com/products/commandbox) and re-run.'
}

function Set-JavaTrust {
    if ($env:OS -eq 'Windows_NT' -and -not ($env:JAVA_TOOL_OPTIONS -match 'trustStoreType')) {
        $env:JAVA_TOOL_OPTIONS = (($env:JAVA_TOOL_OPTIONS + ' -Djavax.net.ssl.trustStoreType=Windows-ROOT').Trim())
    }
}

# FuturePath always uses port 42005. If something else holds it, stop and report (never pick another port).
function Assert-PortFree {
    $conn = Get-NetTCPConnection -State Listen -LocalPort $script:AppPort -ErrorAction SilentlyContinue
    if ($conn) {
        $proc = Get-Process -Id $conn[0].OwningProcess -ErrorAction SilentlyContinue
        $name = if ($proc) { $proc.ProcessName } else { 'unknown' }
        if ($name -eq 'java') { Write-Warn2 "Port $($script:AppPort) is already used by a Java process (probably FuturePath already running)."; return $false }
        throw "Port $($script:AppPort) is in use by '$name' (PID $($conn[0].OwningProcess)). FuturePath requires port $($script:AppPort); stop that process and try again."
    }
    return $true
}

function Test-DockerReady {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { return $false }
    & docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Start-DockerIfNeeded([int]$timeoutSeconds = 150) {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Warn2 'Docker is not installed. Install Docker Desktop, or point .env at an existing MariaDB server.'
        return $false
    }
    if (Test-DockerReady) { return $true }
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path $desktop) { Write-Step 'Starting Docker Desktop...'; Start-Process $desktop | Out-Null }
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerReady) { Write-Ok 'Docker engine is running'; return $true }
    }
    Write-Warn2 "Docker engine did not become ready within $timeoutSeconds seconds."
    return $false
}

function Start-Database([int]$timeoutSeconds = 120) {
    Push-Location $script:ProjectRoot
    try {
        Write-Step 'Starting MariaDB (docker compose up -d)...'
        & docker compose up -d
        if ($LASTEXITCODE -ne 0) { throw 'docker compose up failed.' }
        $deadline = (Get-Date).AddSeconds($timeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $status = (& docker inspect -f '{{.State.Health.Status}}' $script:DbContainer 2>$null)
            if ($status -eq 'healthy') { Write-Ok 'MariaDB is healthy'; return $true }
            Start-Sleep -Seconds 2
        }
        Write-Warn2 "MariaDB did not report healthy within $timeoutSeconds seconds."
        return $false
    } finally { Pop-Location }
}

function Wait-ForHealth([string]$baseUrl, [int]$timeoutSeconds = 300) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $r = Invoke-RestMethod -Uri "$baseUrl/api/health" -TimeoutSec 15
            if ($r.success -and $r.data.database -eq 'ok') { return $true }
        } catch { }
        Start-Sleep -Seconds 3
    }
    return $false
}
