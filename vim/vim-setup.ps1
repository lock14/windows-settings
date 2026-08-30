<#
.SYNOPSIS
    Configures modern Lua Neovim and legacy Vim runtime environments.
#>
[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRootDir = Split-Path -Parent $ScriptDir

# -------------------------------------------------------------
# 1. Modern Lua Neovim Setup
# -------------------------------------------------------------
Write-Host "==> Checking Neovim configuration..." -ForegroundColor Cyan
$nvimSource = Join-Path $RepoRootDir "config\nvim"
$nvimDest = Join-Path $env:LOCALAPPDATA "nvim"

if (Test-Path $nvimSource) {
    if (-not (Test-Path $nvimDest)) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy Neovim configuration to $nvimDest" -ForegroundColor DarkCyan
        } else {
            Write-Host "Deploying Neovim configuration to $nvimDest..." -ForegroundColor Cyan
            Copy-Item -Path $nvimSource -Destination $nvimDest -Recurse -Force
            Write-Host "==> Neovim configuration deployed successfully!" -ForegroundColor Green
        }
    } else {
        # Check if init.lua differs
        $sourceInit = Join-Path $nvimSource "init.lua"
        $destInit = Join-Path $nvimDest "init.lua"
        $isDiff = $true
        if (Test-Path $destInit) {
            $isDiff = ((Get-Content $sourceInit -Raw).Trim() -ne (Get-Content $destInit -Raw).Trim())
        }

        if ($isDiff) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupNvim = "$nvimDest.bak_$timestamp"
            if ($DryRun) {
                Write-Host "  [DryRun] Would backup $nvimDest to $backupNvim" -ForegroundColor DarkCyan
                Write-Host "  [DryRun] Would update Neovim configuration at $nvimDest" -ForegroundColor DarkCyan
            } else {
                Write-Host "Backing up existing Neovim config to $backupNvim..." -ForegroundColor Yellow
                Copy-Item -Path $nvimDest -Destination $backupNvim -Recurse -Force
                Copy-Item -Path "$nvimSource\*" -Destination $nvimDest -Recurse -Force
                Write-Host "==> Neovim configuration updated successfully!" -ForegroundColor Green
            }
        } else {
            Write-Host "==> Neovim configuration at $nvimDest is already up to date." -ForegroundColor Green
        }
    }
}

# -------------------------------------------------------------
# 2. Legacy Vim Setup (_vimrc & Pathogen Bundles)
# -------------------------------------------------------------
Write-Host "==> Checking legacy Vim installation..." -ForegroundColor Cyan
$vimrcSource = Join-Path $ScriptDir "_vimrc"
$destinations = @(
    (Join-Path $HOME "_vimrc"),
    (Join-Path $HOME ".vimrc")
)

if (Test-Path $vimrcSource) {
    $sourceContent = Get-Content $vimrcSource -Raw
    foreach ($dest in $destinations) {
        if (Test-Path $dest) {
            $existingContent = Get-Content $dest -Raw
            if ($existingContent -ne $sourceContent) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backupFile = "$dest.bak_$timestamp"
                if ($DryRun) {
                    Write-Host "  [DryRun] Would backup $dest to $backupFile" -ForegroundColor DarkCyan
                    Write-Host "  [DryRun] Would deploy Vim configuration from $vimrcSource to $dest" -ForegroundColor DarkCyan
                } else {
                    Write-Host "Backing up existing Vim config to $backupFile..." -ForegroundColor Yellow
                    Copy-Item -Path $dest -Destination $backupFile -Force
                    Copy-Item -Path $vimrcSource -Destination $dest -Force
                    Write-Host "Vim configuration deployed successfully to $dest." -ForegroundColor Green
                }
            } else {
                Write-Host "==> Vim configuration at $dest is already up to date." -ForegroundColor Green
            }
        } else {
            if ($DryRun) {
                Write-Host "  [DryRun] Would deploy Vim configuration to $dest" -ForegroundColor DarkCyan
            } else {
                Copy-Item -Path $vimrcSource -Destination $dest -Force
                Write-Host "Vim configuration deployed successfully to $dest." -ForegroundColor Green
            }
        }
    }
}
Write-Host "==> Editor setup complete!" -ForegroundColor Green
