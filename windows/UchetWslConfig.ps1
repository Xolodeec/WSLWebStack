# Shared constants for Uchet WSL installer (Windows side).
# Dot-source from other scripts: . "$PSScriptRoot\UchetWslConfig.ps1"

$script:UchetWslDistro = "WSLWebStack"

function Get-UchetRepoRoot {
    param(
        [string]$WindowsScriptsFolder = $PSScriptRoot
    )
    (Resolve-Path (Join-Path $WindowsScriptsFolder "..")).Path
}
