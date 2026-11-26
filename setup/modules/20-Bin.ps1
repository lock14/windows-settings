# =============================================================
# setup/modules/20-Bin.ps1 - User PATH Registration for bin/
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Add-UserPathEntry -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Env.ps1')
}

$binDir = Join-Path $RepoRoot 'bin'
Write-SetupStage -Stage '20-Bin' -Message "Registering utility scripts directory ($binDir) in User PATH..."

if (Test-Path -LiteralPath $binDir -PathType Container) {
    Add-UserPathEntry -Directory $binDir -DryRun:$DryRun
}

if ($env:LOCALAPPDATA) {
    $winlibsRoot = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'WinGet') 'Packages'
    if (Test-Path -LiteralPath $winlibsRoot -PathType Container) {
        $winlibsPackages = @(Get-ChildItem -LiteralPath $winlibsRoot -Filter 'BrechtSanders.WinLibs*' -Directory -ErrorAction SilentlyContinue)
        if ($winlibsPackages.Count -gt 0) {
            $winlibsBin = Join-Path (Join-Path $winlibsPackages[0].FullName 'mingw64') 'bin'
            if (Test-Path -LiteralPath $winlibsBin -PathType Container) {
                Add-UserPathEntry -Directory $winlibsBin -Prepend -DryRun:$DryRun
            }
        }
    }
}
