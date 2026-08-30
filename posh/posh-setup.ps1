<#
.SYNOPSIS
    Installs Oh My Posh, configures theme, and sets up the PowerShell profile.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Checking Oh My Posh installation..." -ForegroundColor Cyan
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would install Oh My Posh via winget" -ForegroundColor DarkCyan
        } else {
            Write-Host "Installing Oh My Posh via winget..." -ForegroundColor Yellow
            winget install JanDeDobbeleer.OhMyPosh -s winget --accept-package-agreements --accept-source-agreements
        }
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
        if ($DryRun) {
            Write-Host "  [DryRun] Would install fzf via winget" -ForegroundColor DarkCyan
        } else {
            Write-Host "Installing fzf via winget..." -ForegroundColor Yellow
            winget install --id junegunn.fzf -e --source winget --accept-package-agreements --accept-source-agreements
        }
    } else {
        Write-Warning "winget not found. Please install fzf manually."
    }
} else {
    Write-Host "fzf is already installed." -ForegroundColor Green
}

# Check uutils-coreutils installation (Rust GNU coreutils enabled by default)
Write-Host "==> Checking uutils-coreutils installation..." -ForegroundColor Cyan
$wingetLinksDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
if (-not (Get-Command coreutils -ErrorAction SilentlyContinue) -and -not (Test-Path "$wingetLinksDir\coreutils.exe")) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would install uutils.coreutils and uutils.diffutils via winget" -ForegroundColor DarkCyan
        } else {
            Write-Host "Installing uutils.coreutils via winget..." -ForegroundColor Yellow
            winget install --id uutils.coreutils -e --source winget --accept-package-agreements --accept-source-agreements
            winget install --id uutils.diffutils -e --source winget --accept-package-agreements --accept-source-agreements
        }
    } else {
        Write-Warning "winget not found. Please install uutils-coreutils manually."
    }
} else {
    Write-Host "uutils-coreutils is already installed." -ForegroundColor Green
}

# Ensure .poshthemes directory exists and copy theme
$poshThemesDir = Join-Path $HOME ".poshthemes"
if (-not $DryRun -and -not (Test-Path $poshThemesDir)) {
    New-Item -ItemType Directory -Force -Path $poshThemesDir | Out-Null
}

$themeSource = Join-Path $ScriptDir "p10k.omp.json"
$themeDest = Join-Path $poshThemesDir "p10k_single_line.omp.json"
if (Test-Path $themeDest) {
    $existingTheme = Get-Content $themeDest -Raw
    $newTheme = Get-Content $themeSource -Raw
    if ($existingTheme -ne $newTheme) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupTheme = "$themeDest.bak_$timestamp"
        if ($DryRun) {
            Write-Host "  [DryRun] Would backup $themeDest to $backupTheme" -ForegroundColor DarkCyan
            Write-Host "  [DryRun] Would copy $themeSource to $themeDest" -ForegroundColor DarkCyan
        } else {
            Write-Host "Backing up existing theme to $backupTheme..." -ForegroundColor Yellow
            Copy-Item -Path $themeDest -Destination $backupTheme -Force
            Copy-Item -Path $themeSource -Destination $themeDest -Force
            Write-Host "==> Updated theme at $themeDest" -ForegroundColor Green
        }
    } else {
        Write-Host "==> Theme at $themeDest is already up to date." -ForegroundColor Green
    }
} else {
    if ($DryRun) {
        Write-Host "  [DryRun] Would install theme from $themeSource to $themeDest" -ForegroundColor DarkCyan
    } else {
        Write-Host "==> Installing theme to $themeDest..." -ForegroundColor Cyan
        Copy-Item -Path $themeSource -Destination $themeDest -Force
    }
}

# Setup PowerShell Profile
$profileDir = Split-Path -Parent $PROFILE
if (-not $DryRun -and -not (Test-Path $profileDir)) {
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
}

$profileSource = Join-Path $ScriptDir "Microsoft.PowerShell_profile.ps1"
$sourceContent = Get-Content $profileSource -Raw

if (Test-Path $PROFILE) {
    $currentContent = Get-Content $PROFILE -Raw
    $targetContent = $sourceContent
    $isDiff = ($currentContent.Trim() -ne $targetContent.Trim())

    if ($isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupProfile = "$PROFILE.bak_$timestamp"
        if ($DryRun) {
            Write-Host "  [DryRun] Would backup $PROFILE to $backupProfile" -ForegroundColor DarkCyan
            Write-Host "  [DryRun] Would deploy clean repository PowerShell profile to $PROFILE" -ForegroundColor DarkCyan
        } else {
            Write-Host "Backing up existing profile to $backupProfile..." -ForegroundColor Yellow
            Copy-Item -Path $PROFILE -Destination $backupProfile -Force

            Write-Host "Deploying clean repository PowerShell profile to $PROFILE..." -ForegroundColor Cyan
            [System.IO.File]::WriteAllText($PROFILE, $targetContent, [System.Text.Encoding]::UTF8)
            Write-Host "==> PowerShell profile updated successfully!" -ForegroundColor Green
        }
    } else {
        Write-Host "==> PowerShell profile is already up to date." -ForegroundColor Green
    }
} else {
    if ($DryRun) {
        Write-Host "  [DryRun] Would create new PowerShell profile at $PROFILE from $profileSource" -ForegroundColor DarkCyan
    } else {
        Write-Host "Creating new PowerShell profile at $PROFILE..." -ForegroundColor Cyan
        Copy-Item -Path $profileSource -Destination $PROFILE -Force
        Write-Host "==> PowerShell profile created successfully!" -ForegroundColor Green
    }
}

Write-Host "==> Oh My Posh & PowerShell Profile setup complete!" -ForegroundColor Green
