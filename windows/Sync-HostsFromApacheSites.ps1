param([switch]$BindToWslPrimaryIp)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot\UchetWslConfig.ps1"
. "$PSScriptRoot\Ensure-WslLocalhostRouting.ps1"

$current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script as Administrator."
}

$hostsPath = "$env:WINDIR\System32\drivers\etc\hosts"
$domainsRaw = wsl -d $script:UchetWslDistro -- bash -lc "ls /etc/apache2/sites-available/*.local.conf 2>/dev/null | sed 's#.*/##' | sed 's#\.conf##' || true"
$domains = $domainsRaw -split "`r?`n" | Where-Object { $_ -match "^[a-z0-9-]+\.local$" } | Sort-Object -Unique

if (-not $domains -or $domains.Count -eq 0) {
    Write-Host "No .local domains found in Apache sites-available."
    exit 0
}

if ($BindToWslPrimaryIp) {
    $wslIp = Get-WslPrimaryIp -Distro $script:UchetWslDistro
    if (-not $wslIp) {
        throw "Could not read WSL IP (wsl -d $($script:UchetWslDistro) -- hostname -I). Start the distro and retry."
    }
    Sync-HostsLocalDomainsToIp -Domains $domains -Ip $wslIp
    $null = & ipconfig.exe /flushdns 2>&1
    Write-Host "flushdns done."
    exit 0
}

$content = Get-Content -Path $hostsPath -ErrorAction Stop
$append = @()

foreach ($domain in $domains) {
    $exists = $content | Where-Object { $_ -match "(^|\s)$([regex]::Escape($domain))($|\s)" }
    if (-not $exists) {
        $append += "127.0.0.1 $domain"
    }
}

if ($append.Count -gt 0) {
    Add-Content -Path $hostsPath -Value "`n# Added by Uchet WSL installer"
    Add-Content -Path $hostsPath -Value $append
    Write-Host "Added to hosts:"
    $append | ForEach-Object { Write-Host "  $_" }
} else {
    Write-Host "Hosts already contains all detected .local domains."
}
