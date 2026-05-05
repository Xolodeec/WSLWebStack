# Windows-side constants for the WSLWebStack installer.
# Dot-source from other scripts: . "$PSScriptRoot\WSLWebStackConfig.ps1"
#
# Registered WSL distro name as shown in `wsl -l`.
$script:WslDistroName = "WSLWebStack"

function Get-WslWebStackRepoRoot {
    param(
        [string]$WindowsScriptsFolder = $PSScriptRoot
    )
    (Resolve-Path (Join-Path $WindowsScriptsFolder "..")).Path
}
