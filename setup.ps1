<#
.SYNOPSIS
    Master setup script for windows-settings.
    Automates fonts, Oh My Posh, PowerShell profile, and Windows Terminal configuration.
#>
[CmdletBinding()]
param(
    [switch]$SkipFonts,
    [switch]$SkipTerminal,
    [switch]$SkipPosh
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "         Windows Settings Setup Automation           " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Fonts Setup
if (-not $SkipFonts) {
    Write-Host "`n[1/3] Setting up Fonts (MesloLGS NF)..." -ForegroundColor Yellow
    & (Join-Path $RootDir "fonts\font-setup.ps1")
} else {
    Write-Host "`n[1/3] Skipping Fonts Setup." -ForegroundColor DarkGray
}

# 2. Oh My Posh & Profile Setup
if (-not $SkipPosh) {
    Write-Host "`n[2/3] Setting up Oh My Posh & PowerShell Profile..." -ForegroundColor Yellow
    & (Join-Path $RootDir "posh\posh-setup.ps1")
} else {
    Write-Host "`n[2/3] Skipping Oh My Posh Setup." -ForegroundColor DarkGray
}

# 3. Windows Terminal Setup
if (-not $SkipTerminal) {
    Write-Host "`n[3/3] Setting up Windows Terminal..." -ForegroundColor Yellow
    & (Join-Path $RootDir "terminal\terminal-setup.ps1")
} else {
    Write-Host "`n[3/3] Skipping Windows Terminal Setup." -ForegroundColor DarkGray
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host " Setup complete! Restart Windows Terminal to apply.  " -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Green
