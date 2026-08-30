# =============================================================
# PowerShell Profile - windows-settings
# =============================================================

# Add User Modules directory to PSModulePath if needed
$userModulesDir = Join-Path $HOME "Documents\PowerShell\Modules"
if ((Test-Path $userModulesDir) -and ($env:PSModulePath -notlike "*$userModulesDir*")) {
    $env:PSModulePath = "$userModulesDir;$env:PSModulePath"
}

# Import Modern Workstation Module
Import-Module WindowsSettings -ErrorAction SilentlyContinue
