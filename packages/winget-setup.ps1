<#
.SYNOPSIS
    Automates developer tool installation on Windows using winget or declarative DSC.
#>
[CmdletBinding()]
param(
    [switch]$IncludeGUI,
    [switch]$WithGUI,
    [switch]$DryRun,
    [switch]$UseDSC
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRootDir = Split-Path -Parent $ScriptDir
$enableGUI = $IncludeGUI -or $WithGUI

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "winget is required but was not found. Please install the Windows App Installer."
    exit 1
}

# Use Declarative DSC Configuration if requested or available
$dscFile = Join-Path $RepoRootDir "configuration.dsc.yaml"
if ($UseDSC -and (Test-Path $dscFile)) {
    Write-Host "==> Executing Declarative WinGet DSC Configuration ($dscFile)..." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "  [DryRun] Would execute: winget configure $dscFile" -ForegroundColor DarkCyan
        return
    } else {
        winget configure $dscFile --accept-configuration-agreements
        return
    }
}

# Core CLI Developer Packages
$cliPackages = @(
    'uutils.coreutils',
    'uutils.diffutils',
    'Git.Git',
    'GitHub.cli',
    'Starship.Starship',
    'ajeetdsouza.zoxide',
    'eza-community.eza',
    'sharkdp.bat',
    'JanDeDobbeleer.OhMyPosh',
    'BurntSushi.ripgrep.MSVC',
    'sharkdp.fd',
    'junegunn.fzf',
    'jqlang.jq',
    'Neovim.Neovim',
    'jdx.mise',
    'GoLang.Go',
    'Python.Python.3.12',
    'Hashicorp.Terraform',
    'vim.vim'
)

# GUI Developer Packages (Optional)
$guiPackages = @(
    'Microsoft.VisualStudioCode',
    'Microsoft.WindowsTerminal',
    'Docker.DockerDesktop'
)

$targetPackages = $cliPackages
if ($enableGUI) {
    $targetPackages += $guiPackages
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "       Workstation Tool Package Provisioning        " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

foreach ($pkg in $targetPackages) {
    Write-Host "`n==> Checking package: $pkg" -ForegroundColor Yellow
    if ($DryRun) {
        Write-Host "  [DryRun] Would install $pkg via winget" -ForegroundColor DarkCyan
        continue
    }

    # Install package via winget
    winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements
}

Write-Host "`n==> Workstation provisioning complete!" -ForegroundColor Green
