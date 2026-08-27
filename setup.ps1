<#
.SYNOPSIS
    Master setup script for windows-settings.
    Automates fonts, Oh My Posh, PowerShell profile, CLI completions, utility PATH, and Windows Terminal.
#>
[CmdletBinding()]
param(
    [switch]$SkipFonts,
    [switch]$SkipTerminal,
    [switch]$SkipPosh,
    [switch]$SkipCompletions,
    [switch]$SkipVim,
    [switch]$InstallPackages
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "         Windows Settings Setup Automation           " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 0. Optional: Workstation Package Provisioning (Install CLI tools upfront)
if ($InstallPackages) {
    Write-Host "`n[0/6] Installing Workstation Packages via winget..." -ForegroundColor Yellow
    & (Join-Path $RootDir "packages\winget-setup.ps1")
}

# 1. Fonts Setup
if (-not $SkipFonts) {
    Write-Host "`n[1/6] Setting up Fonts (MesloLGS NF)..." -ForegroundColor Yellow
    & (Join-Path $RootDir "fonts\font-setup.ps1")
} else {
    Write-Host "`n[1/6] Skipping Fonts Setup." -ForegroundColor DarkCyan
}

# 2. Oh My Posh & Profile Setup
if (-not $SkipPosh) {
    Write-Host "`n[2/6] Setting up Oh My Posh & PowerShell Profile..." -ForegroundColor Yellow
    & (Join-Path $RootDir "posh\posh-setup.ps1")
} else {
    Write-Host "`n[2/6] Skipping Oh My Posh Setup." -ForegroundColor DarkCyan
}

# 3. CLI Tab Completions Setup
if (-not $SkipCompletions) {
    Write-Host "`n[3/6] Setting up CLI Completions..." -ForegroundColor Yellow
    & (Join-Path $RootDir "completions\completions-setup.ps1")
} else {
    Write-Host "`n[3/6] Skipping CLI Completions." -ForegroundColor DarkCyan
}

# 4. Windows Terminal Setup
if (-not $SkipTerminal) {
    Write-Host "`n[4/6] Setting up Windows Terminal..." -ForegroundColor Yellow
    & (Join-Path $RootDir "terminal\terminal-setup.ps1")
} else {
    Write-Host "`n[4/6] Skipping Windows Terminal Setup." -ForegroundColor DarkCyan
}

# 5. Vim & _vimrc Setup
if (-not $SkipVim) {
    Write-Host "`n[5/6] Setting up Vim & _vimrc configuration..." -ForegroundColor Yellow
    & (Join-Path $RootDir "vim\vim-setup.ps1")
} else {
    Write-Host "`n[5/6] Skipping Vim Setup." -ForegroundColor DarkCyan
}

# 6. Add bin directory to User PATH
$binDir = Join-Path $RootDir "bin"
if (Test-Path $binDir) {
    Write-Host "`n[6/6] Checking User PATH for utility scripts ($binDir)..." -ForegroundColor Yellow
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = if ($userPath) { $userPath -split ';' } else { @() }
    if ($pathParts -notcontains $binDir) {
        Write-Host "  Adding $binDir to User PATH..." -ForegroundColor Cyan
        $newPath = ($pathParts + $binDir) -join ';'
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        $env:Path = "$env:Path;$binDir"
        Write-Host "  Added to User PATH successfully." -ForegroundColor Green
    } else {
        Write-Host "  $binDir is already in User PATH." -ForegroundColor Green
    }
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " Setup complete! Restart Windows Terminal to apply.  " -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
