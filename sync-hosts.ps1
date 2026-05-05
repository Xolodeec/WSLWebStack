# Delegates to windows/Sync-HostsFromApacheSites.ps1
# Use -BindToWslPrimaryIp after wsl --shutdown if .local sites only open via WSL NIC IP (mirrored mode unavailable).
param([switch]$BindToWslPrimaryIp)
$ErrorActionPreference = "Stop"
$inner = Join-Path $PSScriptRoot "windows\Sync-HostsFromApacheSites.ps1"
if ($BindToWslPrimaryIp) {
    & $inner -BindToWslPrimaryIp
} else {
    & $inner
}
