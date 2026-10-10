# Stops FuturePath (Lucee). Pass -Database to also stop the development MariaDB container.
param([switch]$Database)
. "$PSScriptRoot\_common.ps1"
Set-Location $ProjectRoot
$box = Find-Box
if ($box) { & $box server stop }
if ($Database -and (Test-DockerReady)) { & docker compose stop }
