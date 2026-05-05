$ErrorActionPreference = "Stop"

. "$PSScriptRoot\UchetWslConfig.ps1"
. "$PSScriptRoot\Ensure-WslLocalhostRouting.ps1"
$repoRoot = Get-UchetRepoRoot

function Require-Admin {
    $current = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $current.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Run install.bat as Administrator."
    }
}

function Get-WslDistroNames {
    $raw = & wsl.exe -l -q 2>$null
    if (-not $raw) { return @() }
    @($raw) | ForEach-Object {
        ($_ -replace "`0", "").Trim()
    } | Where-Object { $_ }
}

function Test-WslDistro([string]$Name) {
    (Get-WslDistroNames) -contains $Name
}

function Get-UbuntuSourceDistroName {
    foreach ($c in @("Ubuntu", "Ubuntu-24.04", "Ubuntu-22.04", "Ubuntu-20.04")) {
        if (Test-WslDistro $c) { return $c }
    }
    return $null
}

function Ensure-WSL {
    $statusOk = $false
    try {
        wsl --status *> $null
        $statusOk = $true
    } catch {
        $statusOk = $false
    }

    if (-not $statusOk) {
        Write-Host "Installing WSL and Ubuntu..."
        wsl --install -d Ubuntu
        Write-Host "WSL installed. Reboot Windows and run install.bat again."
        exit 0
    }
}

function Ensure-UbuntuForFirstRun {
    if (Test-WslDistro $script:UchetWslDistro) { return }
    if ($null -ne (Get-UbuntuSourceDistroName)) { return }
    Write-Host "Installing Ubuntu (one-time, then it becomes $script:UchetWslDistro)..."
    wsl --install -d Ubuntu
    Write-Host "Ubuntu installed. Reboot Windows and run install.bat again."
    exit 0
}

function Ensure-HostsEntry {
    param([string]$Domain)
    $hostsPath = "$env:WINDIR\System32\drivers\etc\hosts"
    $content = Get-Content -Path $hostsPath -ErrorAction Stop
    $match = $content | Where-Object { $_ -match "(^|\s)$([regex]::Escape($Domain))($|\s)" }
    if (-not $match) {
        Add-Content -Path $hostsPath -Value "127.0.0.1 $Domain"
    }
}

function Import-UbuntuAsUchetDistro {
    param([string]$SourceName)
    $exportTar = Join-Path $env:TEMP ("uchet-wsl-export-" + [guid]::NewGuid().ToString("n") + ".tar")
    $folderSafe = ($script:UchetWslDistro -replace '[^A-Za-z0-9_-]', '_')
    $installRoot = Join-Path $env:LOCALAPPDATA ($folderSafe + "-WSL")

    Write-Host "Creating '$script:UchetWslDistro' from '$SourceName' (export/import, a few minutes)..."
    Write-Host "NOTE: '$SourceName' stays installed. This adds a second distro; remove either later via Windows Apps and Features or: wsl --unregister."

    wsl.exe --shutdown
    Start-Sleep -Seconds 4

    wsl.exe --export $SourceName $exportTar
    if (-not (Test-Path $exportTar)) {
        throw "wsl --export failed (tar not created)."
    }

    if (Test-Path $installRoot) {
        Remove-Item -Recurse -Force $installRoot
    }
    New-Item -ItemType Directory -Force -Path $installRoot | Out-Null

    wsl.exe --import $script:UchetWslDistro $installRoot $exportTar --version 2
    Remove-Item -Force $exportTar -ErrorAction SilentlyContinue

    wsl.exe --set-default $script:UchetWslDistro
    Write-Host "WSL distro ready: $script:UchetWslDistro (set as default). Source '$SourceName' is unchanged."
}

$logDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$installLog = Join-Path $logDir ("install-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
try {
    Start-Transcript -LiteralPath $installLog -Force | Out-Null
    Write-Host "Windows installer log: $installLog"
    Require-Admin
    Ensure-WSL

    $targetDistro = $script:UchetWslDistro
    $haveTarget = Test-WslDistro $targetDistro
    if ($haveTarget) {
        Write-Host ('WSL distro "' + $targetDistro + '" already exists; skipping import, running Linux provisioning only.')
    }
    if (-not $haveTarget) {
        Ensure-UbuntuForFirstRun
        $src = Get-UbuntuSourceDistroName
        if (-not $src) {
            throw "No Ubuntu-based WSL distro found to copy from. Install Ubuntu (wsl --install -d Ubuntu), reboot if asked, then run the installer again."
        }
        Import-UbuntuAsUchetDistro -SourceName $src
    }

    wsl.exe --set-default $targetDistro 2>$null | Out-Null

    # Pass a Windows path with forward slashes; backslashes are often stripped by argv handling (breaks wslpath: "C:Users...").
    $repoForWslpath = ($repoRoot -replace '\\', '/')
    $wslpathLines = & wsl.exe -d $targetDistro -- wslpath -a $repoForWslpath 2>$null
    $scriptDirWsl = $null
    if ($wslpathLines) {
        $first = @($wslpathLines)[0]
        if ($first -is [string]) { $scriptDirWsl = $first.Trim() }
    }
    if ([string]::IsNullOrWhiteSpace($scriptDirWsl) -or ($scriptDirWsl -notmatch '^/')) {
        if ($repoForWslpath -match '^([A-Za-z]):/(.*)$') {
            $driveLetter = $Matches[1].ToLower()
            $rest = $Matches[2]
            $scriptDirWsl = "/mnt/$driveLetter/$rest"
            Write-Host "wslpath did not return a Unix path; using /mnt fallback: $scriptDirWsl"
        }
    }
    if ([string]::IsNullOrWhiteSpace($scriptDirWsl)) {
        throw "Cannot convert repo path to WSL path (wslpath). Windows path: $repoRoot"
    }

    Write-Host "Running Linux provisioning in distro: $targetDistro"
    # Build bash -lc argument with single-quoted PS fragments so Windows PowerShell 5.1 does not misparse "&&".
    $cmd = 'cd ' + "'" + $scriptDirWsl + "'" + ' && chmod +x linux/Provision-UchetWslStack.sh && WSL_DOMAIN=localhost SSL_MODE=local sudo -E ./linux/Provision-UchetWslStack.sh'
    wsl.exe -d $targetDistro -- bash -lc "$cmd"

    Ensure-HostsEntry -Domain "localhost"

    # From Windows, localhost can still fail if WSL networking is misconfigured; inside WSL Apache should answer.
    $probe = "systemctl is-active --quiet apache2 && curl -fsSk --connect-timeout 5 -o /dev/null -w '%{http_code}' -H 'Host: localhost' https://127.0.0.1/ || echo ERR"
    try {
        $hc = (& wsl.exe -d $targetDistro -- bash -lc $probe 2>$null | Out-String).Trim()
        if ($hc -eq "200") {
            Write-Host "Post-check: Apache returned HTTP 200 for https://localhost/ (from inside WSL)."
        } else {
            Write-Host "Post-check: expected HTTP 200 from WSL, got '$hc'. In distro run: systemctl status apache2"
        }
    } catch {
        Write-Host "Post-check: could not probe Apache in WSL."
    }

    Repair-UchetWindowsToWslHttps -Distro $targetDistro -Domain "localhost"

    $message = @"
Done.

WSL distribution name: $targetDistro
  (list: wsl -l -v)

Open:
  https://localhost/

Credentials:
  $(Join-Path $repoRoot 'credentials')

If the browser warns about the certificate, accept it (self-signed local cert).

Windows log (this run):
  $installLog

Linux provision logs (each sudo run, under repo):
  $(Join-Path $repoRoot 'logs')\provision-*.log
"@

    Write-Host $message
}
finally {
    try {
        Stop-Transcript | Out-Null
    } catch {
        # No active transcript (e.g. Start-Transcript failed)
    }
}
