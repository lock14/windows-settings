<#
.SYNOPSIS
    Zero-dependency bootstrap script for windows-settings.
    Clones the repository and runs the master setup orchestrator.
.DESCRIPTION
    Can be run locally or streamed directly in PowerShell:
        irm https://raw.githubusercontent.com/lock14/windows-settings/main/bootstrap.ps1 | iex
#>
[CmdletBinding()]
param(
    [switch]$Bootstrap,
    [switch]$DotfilesOnly,
    [switch]$SystemOnly,
    [switch]$UseDSC,
    [switch]$DryRun,
    [switch]$WithGUI,
    [switch]$IncludeGUI,
    [switch]$InstallPackages,
    [switch]$SkipPackages,
    [switch]$SkipFonts,
    [switch]$SkipTerminal,
    [switch]$SkipPosh,
    [switch]$SkipCompletions,
    [switch]$SkipVim,
    [switch]$SkipBin
)

$ErrorActionPreference = 'Stop'

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "       windows-settings Turnkey Bootstrapper         " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Verify Git prerequisite
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "`n[1/3] Git not found. Attempting installation via winget..." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    } else {
        Write-Error "Error: Git is required to clone windows-settings. Please install Git and rerun."
        exit 1
    }
} else {
    Write-Host "`n[1/3] Git prerequisite satisfied." -ForegroundColor Green
}

# 2. Determine target repository location
$repoUrl = "https://github.com/lock14/windows-settings.git"
$targetDir = Join-Path $HOME "windows-settings"

# If invoked from an existing clone, reuse current directory
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "setup.ps1"))) {
    $targetDir = $PSScriptRoot
    Write-Host "`n[2/3] Using existing repository clone at $targetDir." -ForegroundColor Green
} elseif (-not (Test-Path $targetDir)) {
    if ($DryRun) {
        Write-Host "`n[2/3] [DryRun] Would clone $repoUrl to $targetDir..." -ForegroundColor DarkCyan
    } else {
        Write-Host "`n[2/3] Cloning windows-settings to $targetDir..." -ForegroundColor Yellow
        git clone $repoUrl $targetDir
    }
} else {
    if ($DryRun) {
        Write-Host "`n[2/3] [DryRun] Would update existing windows-settings at $targetDir via git pull..." -ForegroundColor DarkCyan
    } else {
        Write-Host "`n[2/3] Updating existing windows-settings at $targetDir..." -ForegroundColor Yellow
        git -C $targetDir pull --rebase origin main
    }
}

# 3. Execute setup orchestrator
$setupScript = Join-Path $targetDir "setup.ps1"
if (-not (Test-Path $setupScript)) {
    if ($DryRun) {
        Write-Host "`n[3/3] [DryRun] Setup orchestrator preview complete (target repository clone skipped in DryRun)." -ForegroundColor Magenta
        return
    }
    Write-Error "Setup script not found at $setupScript"
    exit 1
}

Write-Host "`n[3/3] Invoking master setup orchestrator..." -ForegroundColor Cyan
if ($PSBoundParameters.Count -gt 0) {
    & $setupScript @PSBoundParameters
} else {
    & $setupScript -Bootstrap
}
