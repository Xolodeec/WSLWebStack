# Dot-source from Install-WslWebStack.ps1 — fixes Windows browser -> WSL HTTPS when 127.0.0.1:443 is not forwarded.
# Strategy: (1) optional [wsl2] networkingMode=mirrored + wsl --shutdown (2) hosts fallback to current WSL vNIC IP.

function Test-WindowsLocalWslHttps {
    param([string]$Domain = "localhost")
    $curlExe = Join-Path $env:WINDIR "System32\curl.exe"
    if (-not (Test-Path -LiteralPath $curlExe)) { return $false }
    # Must use -f: without it, curl exits 0 on any TLS response (e.g. wrong service on :443), so we would skip hosts->WSL IP fallback and leave 127.0.0.1 -> ERR_CONNECTION_REFUSED in the browser.
    $null = & $curlExe -fsSk --connect-timeout 5 -m 12 -H "Host: $Domain" "https://127.0.0.1/" -o NUL 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Get-WslPrimaryIp {
    param([Parameter(Mandatory)][string]$Distro)
    $raw = (& wsl.exe -d $Distro -- hostname -I 2>$null | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        foreach ($tok in ($raw -split '\s+', [StringSplitOptions]::RemoveEmptyEntries)) {
            if ($tok -eq '127.0.0.1' -or $tok -eq '::1') { continue }
            if ($tok -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return $tok }
        }
    }
    $routeLine = (& wsl.exe -d $Distro -- bash -lc "ip -4 route get 8.8.8.8 2>/dev/null" 2>$null | Out-String).Trim()
    if ($routeLine -match '\bsrc\s+((?:\d{1,3}\.){3}\d{1,3})\b') { return $Matches[1] }
    return $null
}

function Merge-WslConfigMirroredForBrowser {
    $path = Join-Path $env:USERPROFILE ".wslconfig"
    $raw = if (Test-Path -LiteralPath $path) { (Get-Content -LiteralPath $path -Raw) } else { "" }
    if ($raw -match '(?m)^\s*networkingMode\s*=') {
        Write-Host ".wslconfig already contains networkingMode= — not changing (remove or set to mirrored manually if needed)."
        return $false
    }
    $block = @"

# --- WSLWebStack: Windows browser access to HTTPS in WSL (mirrored NIC; WSL 2.0+ / Windows 11 22H2+) ---
[wsl2]
networkingMode=mirrored
"@

    Add-Content -LiteralPath $path -Value $block
    Write-Host "Updated $path : added [wsl2] networkingMode=mirrored (localhostForwarding omitted; ignored in mirrored mode)"
    return $true
}

function Invoke-WslShutdownAndWake {
    param([Parameter(Mandatory)][string]$Distro)
    Write-Host "Restarting WSL to apply .wslconfig (wsl --shutdown)..."
    & wsl.exe --shutdown 2>$null
    Start-Sleep -Seconds 12
    $null = & wsl.exe -d $Distro --exec /bin/true 2>&1
    Start-Sleep -Seconds 18
}

function Test-LineReferencesDomain {
    param([string]$Line, [string]$EscapedDomain)
    if ($Line.TrimStart().StartsWith("#")) { return $false }
    return ($Line -match "(?i)(^|\s)$EscapedDomain(\s|$)")
}

function Update-HostsDomainBinding {
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][string]$Ip
    )
    Sync-HostsLocalDomainsToIp -Domains @($Domain) -Ip $Ip
}

function Sync-HostsLocalDomainsToIp {
    param(
        [Parameter(Mandatory)][string[]]$Domains,
        [Parameter(Mandatory)][string]$Ip
    )
    $hostsPath = Join-Path $env:WINDIR "System32\drivers\etc\hosts"
    $escapedList = @($Domains | ForEach-Object { [regex]::Escape($_) })
    $lines = Get-Content -LiteralPath $hostsPath -ErrorAction Stop
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $t = $line.TrimStart()
        if ($t.StartsWith("#")) {
            $out.Add($line) | Out-Null
            continue
        }
        $drop = $false
        foreach ($ex in $escapedList) {
            if (Test-LineReferencesDomain -Line $line -EscapedDomain $ex) { $drop = $true; break }
        }
        if (-not $drop) { $out.Add($line) | Out-Null }
    }
    foreach ($d in $Domains) {
        $out.Add("$Ip $d") | Out-Null
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($hostsPath, $out.ToArray(), $utf8NoBom)
    Write-Host "hosts: bound $($Domains -join ', ') -> $Ip"
}

function Repair-WindowsToWslHttps {
    param(
        [Parameter(Mandatory)][string]$Distro,
        [string]$Domain = "localhost"
    )
    if (Test-WindowsLocalWslHttps -Domain $Domain) {
        Write-Host "Post-check (Windows): https://127.0.0.1:443 with Host $Domain already works."
        return
    }
    Write-Host "Windows cannot reach WSL on 127.0.0.1:443 — applying automatic fix (mirrored networking, then hosts fallback)..."
    $merged = Merge-WslConfigMirroredForBrowser
    if ($merged) {
        Invoke-WslShutdownAndWake -Distro $Distro
    }
    if (Test-WindowsLocalWslHttps -Domain $Domain) {
        Write-Host "Post-check (Windows): https://$Domain/ should work in the browser (mirrored networking)."
        return
    }
    if ($Domain -ieq "localhost") {
        Write-Host "Fallback to hosts mapping is skipped for localhost."
        return
    }
    $wslIp = Get-WslPrimaryIp -Distro $Distro
    if (-not $wslIp) {
        Write-Host "Could not read WSL IP (hostname -I). Open WSL manually, then re-run install.bat or sync-hosts.ps1."
        return
    }
    Update-HostsDomainBinding -Domain $Domain -Ip $wslIp
    $null = & ipconfig.exe /flushdns 2>&1
    Write-Host "Fallback: hosts now maps $Domain -> $wslIp. After each wsl --shutdown the IP may change — run: powershell -ExecutionPolicy Bypass -File .\sync-hosts.ps1 -BindToWslPrimaryIp"
}
