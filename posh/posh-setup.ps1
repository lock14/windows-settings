<#
.SYNOPSIS
    Installs Oh My Posh, configures theme, and sets up the PowerShell profile.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Oh My Posh installation..." -ForegroundColor Cyan
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing Oh My Posh via winget..." -ForegroundColor Yellow
        winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
    } else {
        Write-Warning "winget not found. Please install Oh My Posh manually from https://ohmyposh.dev"
    }
} else {
    Write-Host "Oh My Posh is already installed." -ForegroundColor Green
}

# Check fzf installation (for interactive Ctrl+R search)
Write-Host "==> Checking fzf installation..." -ForegroundColor Cyan
if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Host "Installing fzf via winget..." -ForegroundColor Yellow
        winget install --id junegunn.fzf -e --source winget --accept-package-agreements --accept-source-agreements
    } else {
        Write-Warning "winget not found. Please install fzf manually."
    }
} else {
    Write-Host "fzf is already installed." -ForegroundColor Green
}

# Ensure .poshthemes directory exists and copy theme
$poshThemesDir = Join-Path $HOME ".poshthemes"
if (-not (Test-Path $poshThemesDir)) {
    New-Item -ItemType Directory -Force -Path $poshThemesDir | Out-Null
}

$themeSource = Join-Path $ScriptDir "p10k.omp.json"
$themeDest = Join-Path $poshThemesDir "p10k_single_line.omp.json"
Write-Host "==> Installing theme to $themeDest..." -ForegroundColor Cyan
Copy-Item -Path $themeSource -Destination $themeDest -Force

# Setup PowerShell Profile
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$profileSource = Join-Path $ScriptDir "Microsoft.PowerShell_profile.ps1"
if (Test-Path $PROFILE) {
    # Check if profile already loads p10k_single_line
    $content = Get-Content $PROFILE -Raw
    if ($content -notmatch 'p10k_single_line\.omp\.json') {
        Write-Host "Backing up existing profile to $PROFILE.bak..." -ForegroundColor Yellow
        Copy-Item -Path $PROFILE -Destination "$PROFILE.bak" -Force

        Write-Host "Appending windows-settings profile additions to $PROFILE..." -ForegroundColor Cyan
        Add-Content -Path $PROFILE -Value "`n# --- Added by windows-settings ---`n$(Get-Content $profileSource -Raw)"
    } else {
        Write-Host "PowerShell profile already configured for p10k_single_line." -ForegroundColor Green
    }

    # Ensure coreutils does not shadow custom numeric sum function
    $currentProfileContent = Get-Content $PROFILE -Raw
    if ($currentProfileContent -match '\$script:__COREUTILS__' -and $currentProfileContent -match "'sum'") {
        $cleanedContent = $currentProfileContent -replace "'sum',\s*", ""
        Set-Content -Path $PROFILE -Value $cleanedContent -Force
    }
} else {
    Write-Host "Creating new PowerShell profile at $PROFILE..." -ForegroundColor Cyan
    Copy-Item -Path $profileSource -Destination $PROFILE -Force
}

Write-Host "==> Oh My Posh & PowerShell Profile setup complete!" -ForegroundColor Green
