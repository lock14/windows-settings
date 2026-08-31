<#
.SYNOPSIS
    Master setup engine for windows-settings.
    Automates package provisioning, fonts, Starship prompt, WindowsSettings module,
    CLI completions, utility PATH, Neovim, and Windows Terminal.

.DESCRIPTION
    Execution Modes:
      -Bootstrap             Full new machine bootstrap (winget packages, fonts, starship, module, terminal, nvim)
      -DotfilesOnly          Configure user dotfiles, fonts, nvim, terminal, and shell module only (no package install)
      -SystemOnly            Provision winget packages and CLI tools only
      -UseDSC                Provision workstation packages using declarative WinGet DSC v3 manifest (configuration.dsc.yaml)
      -DryRun                Preview actions without modifying the system

    GUI Options:
      -WithGUI, -IncludeGUI  Install GUI desktop applications (VS Code, Windows Terminal, Docker Desktop via winget)

    Granular Skip Flags:
      -SkipPackages          Skip winget package installation
      -SkipFonts             Skip MesloLGS NF font installation
      -SkipPosh              Skip Starship / Oh My Posh & PowerShell module configuration
      -SkipCompletions       Skip CLI argument completions registration
      -SkipTerminal          Skip Windows Terminal settings & JSON fragment deployment
      -SkipVim               Skip Neovim & Vim configuration
      -SkipBin               Skip adding bin/ directory to User PATH
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
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Normalize GUI switch
$enableGUI = $WithGUI -or $IncludeGUI

# Resolve execution modes
$shouldInstallPackages = ($InstallPackages -or $Bootstrap -or $SystemOnly) -and (-not $SkipPackages) -and (-not $DotfilesOnly)
$skipUserConfig = $SystemOnly

if ($skipUserConfig) {
    $SkipFonts = $true
    $SkipPosh = $true
    $SkipCompletions = $true
    $SkipTerminal = $true
    $SkipVim = $true
    $SkipBin = $true
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "         Windows Settings Setup Automation           " -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "               [DRY RUN PREVIEW MODE]                " -ForegroundColor Magenta
}
Write-Host "=====================================================" -ForegroundColor Cyan

# 0. Workstation Package Provisioning via winget / DSC
if ($shouldInstallPackages) {
    Write-Host "`n[0/6] Installing Workstation Packages via winget / DSC..." -ForegroundColor Yellow
    $wingetArgs = @{}
    if ($enableGUI) { $wingetArgs['WithGUI'] = $true }
    if ($UseDSC) { $wingetArgs['UseDSC'] = $true }
    if ($DryRun) { $wingetArgs['DryRun'] = $true }
    & (Join-Path $RootDir "packages\winget-setup.ps1") @wingetArgs
} else {
    Write-Host "`n[0/6] Skipping Workstation Package Installation." -ForegroundColor DarkCyan
}

# 1. Fonts Setup (MesloLGS NF)
if (-not $SkipFonts) {
    Write-Host "`n[1/6] Setting up Fonts (MesloLGS NF)..." -ForegroundColor Yellow
    $fontArgs = @{}
    if ($DryRun) { $fontArgs['DryRun'] = $true }
    & (Join-Path $RootDir "fonts\font-setup.ps1") @fontArgs
} else {
    Write-Host "`n[1/6] Skipping Fonts Setup." -ForegroundColor DarkCyan
}

# 2. Starship Prompt & WindowsSettings Module Setup
if (-not $SkipPosh) {
    Write-Host "`n[2/6] Setting up Starship Prompt & WindowsSettings PowerShell Module..." -ForegroundColor Yellow
    $poshArgs = @{}
    if ($DryRun) { $poshArgs['DryRun'] = $true }
    & (Join-Path $RootDir "posh\posh-setup.ps1") @poshArgs
} else {
    Write-Host "`n[2/6] Skipping Shell & Prompt Setup." -ForegroundColor DarkCyan
}

# 3. CLI Tab Completions Setup
if (-not $SkipCompletions) {
    Write-Host "`n[3/6] Setting up CLI Completions..." -ForegroundColor Yellow
    $compArgs = @{}
    if ($DryRun) { $compArgs['DryRun'] = $true }
    & (Join-Path $RootDir "completions\completions-setup.ps1") @compArgs
} else {
    Write-Host "`n[3/6] Skipping CLI Completions." -ForegroundColor DarkCyan
}

# 4. Windows Terminal Setup (JSON Fragments & Settings)
if (-not $SkipTerminal) {
    Write-Host "`n[4/6] Setting up Windows Terminal (JSON Fragments & Settings)..." -ForegroundColor Yellow
    $termArgs = @{}
    if ($DryRun) { $termArgs['DryRun'] = $true }
    & (Join-Path $RootDir "terminal\terminal-setup.ps1") @termArgs
} else {
    Write-Host "`n[4/6] Skipping Windows Terminal Setup." -ForegroundColor DarkCyan
}

# 5. Neovim & Vim Setup
if (-not $SkipVim) {
    Write-Host "`n[5/6] Setting up Neovim & Vim configuration..." -ForegroundColor Yellow
    $vimArgs = @{}
    if ($DryRun) { $vimArgs['DryRun'] = $true }
    & (Join-Path $RootDir "vim\vim-setup.ps1") @vimArgs
} else {
    Write-Host "`n[5/6] Skipping Editor Setup." -ForegroundColor DarkCyan
}

# 6. Add bin directory to User PATH
if (-not $SkipBin) {
    $binDir = Join-Path $RootDir "bin"
    if (Test-Path $binDir) {
        Write-Host "`n[6/6] Checking User PATH for utility scripts ($binDir)..." -ForegroundColor Yellow
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathParts = if ($userPath) { $userPath -split ';' } else { @() }
        if ($pathParts -notcontains $binDir) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would add $binDir to User PATH" -ForegroundColor DarkCyan
            } else {
                Write-Host "Adding $binDir to User PATH..." -ForegroundColor Cyan
                $newPath = ($pathParts + $binDir) -join ';'
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                $env:Path = "$env:Path;$binDir"
                Write-Host "User PATH updated successfully." -ForegroundColor Green
            }
        } else {
            Write-Host "  $binDir is already in User PATH." -ForegroundColor Green
        }
    }
    # Ensure COLORTERM=truecolor is set in User Environment for 24-bit TrueColor CLI rendering
    $userColorTerm = [Environment]::GetEnvironmentVariable('COLORTERM', 'User')
    if ($userColorTerm -ne 'truecolor') {
        if ($DryRun) {
            Write-Host "  [DryRun] Would set User environment variable COLORTERM=truecolor" -ForegroundColor DarkCyan
        } else {
            [Environment]::SetEnvironmentVariable('COLORTERM', 'truecolor', 'User')
            $env:COLORTERM = 'truecolor'
        }
    }
} else {
    Write-Host "`n[6/6] Skipping User PATH configuration." -ForegroundColor DarkCyan
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " Dry run complete! No changes were made to system.   " -ForegroundColor Magenta
} else {
    Write-Host " Workstation configuration completed successfully!   " -ForegroundColor Green
}
Write-Host "=====================================================" -ForegroundColor Cyan
