# =============================================================
# setup/modules/40-Mise.ps1 - Mise Runtimes & Elan Toolchain
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
if (-not (Get-Command Deploy-ConfigFile -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}
if (-not (Get-Command Sync-MisePathsCache -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Env.ps1')
}

Write-SetupStage -Stage '40-Mise' -Message 'Configuring Mise runtime manager and polyglot toolchains...'

$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
$miseConfigSrc = Join-Path $RepoRoot 'mise.toml'
$miseConfigDest = Join-Path (Join-Path (Join-Path $userHome '.config') 'mise') 'config.toml'
Deploy-ConfigFile -Name 'Global Mise configuration' -SourcePath $miseConfigSrc -DestinationPath $miseConfigDest -DryRun:$DryRun

$elanHome = if ($env:ELAN_HOME -and $env:ELAN_HOME.Trim()) {
    $env:ELAN_HOME.Trim()
} else {
    Join-Path (Join-Path (Join-Path $userHome '.local') 'share') 'elan'
}
$env:ELAN_HOME = $elanHome

$miseShims = if ($env:LOCALAPPDATA) { Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims' } else { '' }
if ($miseShims -and (Test-Path -LiteralPath $miseShims -PathType Container)) {
    Add-UserPathEntry -Directory $miseShims -Prepend -DryRun:$DryRun
}

$miseCmd = Get-Command mise -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $miseCmd) {
    if ($DryRun) {
        Write-SetupDryRun "Would execute mise trust, mise install, elan default stable (ELAN_HOME=$elanHome), and Sync-MisePathsCache"
    } else {
        Write-SetupWarn 'mise binary not found on PATH; skipping declarative toolchain hydration.'
    }
    return
}

if ($DryRun) {
    Write-SetupDryRun "Would execute: mise trust --yes ($miseConfigSrc, $miseConfigDest)"
    Write-SetupDryRun "Would execute: mise install --yes (ELAN_HOME=$elanHome)"
    Write-SetupDryRun 'Would ensure Lean 4 stable default toolchain via elan when installed'
    Sync-MisePathsCache -DryRun
    return
}

$elanToolchainsDir = Join-Path $elanHome 'toolchains'
if (-not (Test-Path -LiteralPath $elanToolchainsDir -PathType Container)) {
    New-Item -ItemType Directory -Force -Path $elanToolchainsDir | Out-Null
}

Write-SetupStep 'Trusting and installing declarative toolchains from mise.toml...'
if (Test-Path -LiteralPath $miseConfigSrc -PathType Leaf) {
    & $miseCmd.Source trust $miseConfigSrc --yes *> $null
}
if (Test-Path -LiteralPath $miseConfigDest -PathType Leaf) {
    & $miseCmd.Source trust $miseConfigDest --yes *> $null
}
& $miseCmd.Source -C $RepoRoot install --yes

if ($miseShims -and (Test-Path -LiteralPath $miseShims -PathType Container)) {
    Add-UserPathEntry -Directory $miseShims -Prepend
}
Sync-MisePathsCache

$elanBinDir = Join-Path $elanHome 'bin'
Add-SessionPathEntry -Directory $elanBinDir -Prepend

$elanExe = ''
$elanCand = Join-Path $elanBinDir 'elan.exe'
if ([System.IO.File]::Exists($elanCand)) {
    $elanExe = $elanCand
} else {
    $elanFound = Get-Command elan.exe, elan -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $elanFound) { $elanExe = $elanFound.Source }
}

if (-not $elanExe) {
    $elanInitFound = Get-Command elan-init.exe, elan-init -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $elanInitFound) {
        Write-SetupStep 'Initializing Elan and Lean 4 stable toolchain...'
        & $elanInitFound.Source -y --default-toolchain stable --no-modify-path *> $null
        if ([System.IO.File]::Exists($elanCand)) {
            $elanExe = $elanCand
            Add-SessionPathEntry -Directory $elanBinDir -Prepend
        }
    }
}

if ($elanExe) {
    $elanShow = (& $elanExe show 2>$null | Out-String)
    if ($elanShow -notmatch '\(default\)') {
        Write-SetupStep 'Setting Elan default Lean 4 toolchain to stable...'
        & $elanExe default stable *> $null
    }
}
