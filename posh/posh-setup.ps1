<#
.SYNOPSIS
    Installs Starship / Oh My Posh, provisions WindowsSettings module, and configures PowerShell profile.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRootDir = Split-Path -Parent $ScriptDir

# -------------------------------------------------------------
# 1. Starship Prompt & Oh My Posh Setup
# -------------------------------------------------------------
Write-Host "==> Checking Prompt Engine (Starship & Oh My Posh)..." -ForegroundColor Cyan

# Deploy starship.toml to $HOME\.config\starship.toml
$starshipSource = Join-Path $RepoRootDir "starship.toml"
$configDir = Join-Path $HOME ".config"
$starshipDest = Join-Path $configDir "starship.toml"

if (Test-Path $starshipSource) {
    if (-not (Test-Path $configDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $configDir | Out-Null
        }
    }
    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy starship.toml to $starshipDest" -ForegroundColor DarkCyan
    } else {
        Copy-Item -Path $starshipSource -Destination $starshipDest -Force
        Write-Host "==> Starship prompt configuration deployed to $starshipDest" -ForegroundColor Green
    }
}

# Deploy Oh My Posh theme fallback
$themeSource = Join-Path $ScriptDir "p10k.omp.json"
$poshThemesDir = Join-Path $HOME ".poshthemes"
$themeDest = Join-Path $poshThemesDir "p10k_single_line.omp.json"

if (Test-Path $themeSource) {
    if (-not (Test-Path $poshThemesDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $poshThemesDir | Out-Null
        }
    }
    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy Oh My Posh theme to $themeDest" -ForegroundColor DarkCyan
    } else {
        Copy-Item -Path $themeSource -Destination $themeDest -Force
        Write-Host "==> Oh My Posh theme deployed to $themeDest" -ForegroundColor Green
    }
}

# Deploy Solarized Dark TrueColor theme for bat
$batThemeSource = Join-Path $RepoRootDir "colors\Solarized-Dark-TrueColor.tmTheme"
$batConfigDir = "$env:APPDATA\bat"
$batThemesDir = Join-Path $batConfigDir "themes"
if (Test-Path $batThemeSource) {
    if (-not (Test-Path $batThemesDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $batThemesDir | Out-Null }
    }
    $batThemeDest = Join-Path $batThemesDir "Solarized-Dark-TrueColor.tmTheme"
    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy bat theme to $batThemeDest" -ForegroundColor DarkCyan
    } else {
        Copy-Item -Path $batThemeSource -Destination $batThemeDest -Force
        '--theme="Solarized-Dark-TrueColor"' | Set-Content -Path "$batConfigDir\config" -Encoding utf8
        if (Get-Command bat -ErrorAction SilentlyContinue) {
            & bat cache --build | Out-Null
        }
        Write-Host "==> Solarized Dark TrueColor theme deployed for bat" -ForegroundColor Green
    }
}

# -------------------------------------------------------------
# 2. Deploy WindowsSettings PowerShell Module
# -------------------------------------------------------------
Write-Host "==> Deploying WindowsSettings PowerShell Module..." -ForegroundColor Cyan
$moduleSource = Join-Path $RepoRootDir "Modules\WindowsSettings"
$userModulesDir = Join-Path $HOME "Documents\PowerShell\Modules"
$moduleDest = Join-Path $userModulesDir "WindowsSettings"

if (Test-Path $moduleSource) {
    if (-not (Test-Path $userModulesDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $userModulesDir | Out-Null
        }
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy WindowsSettings module to $moduleDest" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $moduleDest)) {
            New-Item -ItemType Directory -Force -Path $moduleDest | Out-Null
        }
        Copy-Item -Path "$moduleSource\*" -Destination $moduleDest -Recurse -Force
        Write-Host "==> WindowsSettings module deployed to $moduleDest" -ForegroundColor Green
    }
}

# -------------------------------------------------------------
# 3. Configure PowerShell Profile ($PROFILE)
# -------------------------------------------------------------
Write-Host "==> Configuring PowerShell profile at $PROFILE..." -ForegroundColor Cyan
$profileDir = Split-Path -Parent $PROFILE
if (-not (Test-Path $profileDir)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    }
}

$targetProfileContent = @'
# =============================================================
# PowerShell Profile - windows-settings
# =============================================================

Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue
'@

if (Test-Path $PROFILE) {
    $currentContent = Get-Content $PROFILE -Raw
    $isDiff = ($currentContent.Trim() -ne $targetProfileContent.Trim())

    if ($isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupProfile = "$PROFILE.bak_$timestamp"
        if ($DryRun) {
            Write-Host "  [DryRun] Would backup $PROFILE to $backupProfile" -ForegroundColor DarkCyan
            Write-Host "  [DryRun] Would update PowerShell profile to load WindowsSettings module" -ForegroundColor DarkCyan
        } else {
            Write-Host "Backing up existing profile to $backupProfile..." -ForegroundColor Yellow
            Copy-Item -Path $PROFILE -Destination $backupProfile -Force

            Write-Host "Updating PowerShell profile at $PROFILE..." -ForegroundColor Cyan
            [System.IO.File]::WriteAllText($PROFILE, $targetProfileContent, [System.Text.Encoding]::UTF8)
            Write-Host "==> PowerShell profile updated successfully!" -ForegroundColor Green
        }
    } else {
        Write-Host "==> PowerShell profile is already up to date." -ForegroundColor Green
    }
} else {
    if ($DryRun) {
        Write-Host "  [DryRun] Would create new PowerShell profile at $PROFILE" -ForegroundColor DarkCyan
    } else {
        Write-Host "Creating new PowerShell profile at $PROFILE..." -ForegroundColor Cyan
        [System.IO.File]::WriteAllText($PROFILE, $targetProfileContent, [System.Text.Encoding]::UTF8)
        Write-Host "==> PowerShell profile created successfully!" -ForegroundColor Green
    }
}

Write-Host "==> Prompt & Shell setup complete!" -ForegroundColor Green
