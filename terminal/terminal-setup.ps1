<#
.SYNOPSIS
    Configures Windows Terminal settings, color schemes, and fonts.
#>
[CmdletBinding()]
param(
    [switch]$BackupOnly
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Locate Windows Terminal LocalState directory
$possiblePaths = @(
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState",
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal"
)

$targetDir = $null
foreach ($path in $possiblePaths) {
    if (Test-Path $path) {
        $targetDir = $path
        break
    }
}

if (-not $targetDir) {
    # If not installed yet, default to standard package path
    $targetDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
}

$destFile = Join-Path $targetDir "settings.json"
$sourceFile = Join-Path $ScriptDir "settings.json"

Write-Host "==> Target Windows Terminal settings: $destFile" -ForegroundColor Cyan

if (Test-Path $destFile) {
    $existingContent = Get-Content $destFile -Raw
    $sourceContent = Get-Content $sourceFile -Raw
    $isDiff = ($existingContent -ne $sourceContent)

    if ($BackupOnly -or $isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = "$destFile.bak_$timestamp"
        Write-Host "Backing up existing settings to $backupFile..." -ForegroundColor Yellow
        Copy-Item -Path $destFile -Destination $backupFile -Force
    }

    if (-not $BackupOnly) {
        if ($isDiff) {
            Write-Host "Deploying repository settings.json to Windows Terminal..." -ForegroundColor Cyan
            Copy-Item -Path $sourceFile -Destination $destFile -Force
            Write-Host "==> Windows Terminal settings applied successfully!" -ForegroundColor Green
        } else {
            Write-Host "==> Windows Terminal settings are already up to date." -ForegroundColor Green
        }
    }
} else {
    if (-not $BackupOnly) {
        Write-Host "Deploying repository settings.json to Windows Terminal..." -ForegroundColor Cyan
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "==> Windows Terminal settings applied successfully!" -ForegroundColor Green
    }
}
