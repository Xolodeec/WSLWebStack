# Windows-side constants for the WSLWebStack installer.
# Dot-source from other scripts: . "$PSScriptRoot\WSLWebStackConfig.ps1"
#
# Registered WSL distro name as shown in `wsl -l`.
$script:WslDistroName = "WSLWebStack"

# Expected Store-style name for the Ubuntu you install manually before install.bat (README step 1).
# Used in error hints; cloning prefers this distro when several Ubuntu entries exist (`lsb_release -cs` should be an LTS).
$script:WslBootstrapDistroName = "Ubuntu-24.04"

function Get-WslWebStackRepoRoot {
    param(
        [string]$WindowsScriptsFolder = $PSScriptRoot
    )
    (Resolve-Path (Join-Path $WindowsScriptsFolder "..")).Path
}
