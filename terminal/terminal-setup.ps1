<#
.SYNOPSIS
    Configures Windows Terminal using native JSON Fragment Extensions (zero-touch)
    and optional deep JSON settings merge.
#>
[CmdletBinding()]
param(
    [switch]$BackupOnly,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# -------------------------------------------------------------
# 1. Deploy Windows Terminal JSON Fragment Extension
# -------------------------------------------------------------
$fragmentSource = Join-Path $ScriptDir "Fragments\windows-settings.json"
if (-not (Test-Path $fragmentSource)) {
    $fragmentSource = Join-Path $ScriptDir "settings.json"
}

$fragmentDirs = @(
    "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\WindowsSettings",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings",
    "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings"
)

foreach ($fDir in $fragmentDirs) {
    $parentPkgDir = Split-Path -Parent (Split-Path -Parent $fDir)
    if ((Test-Path $parentPkgDir) -or ($fDir -like "*Microsoft\Windows Terminal*")) {
        $fDest = Join-Path $fDir "windows-settings.json"
        if ($DryRun) {
            Write-Host "  [DryRun] Would install Windows Terminal JSON Fragment at $fDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $fDir)) {
                New-Item -ItemType Directory -Force -Path $fDir | Out-Null
            }
            Copy-Item -Path $fragmentSource -Destination $fDest -Force
            Write-Host "==> Windows Terminal JSON Fragment installed at $fDest" -ForegroundColor Green
        }
    }
}

# -------------------------------------------------------------
# 2. Settings.json Deep Merge (Legacy / Default Profile alignment)
# -------------------------------------------------------------
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
    $targetDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }
}

$destFile = Join-Path $targetDir "settings.json"
$sourceFile = Join-Path $ScriptDir "settings.json"

Write-Host "==> Target Windows Terminal settings: $destFile" -ForegroundColor Cyan

function Merge-TerminalHashtable {
    param(
        [System.Collections.IDictionary]$Target,
        [System.Collections.IDictionary]$Source
    )

    foreach ($key in $Source.Keys) {
        if ($Target.Contains($key)) {
            if ($Target[$key] -is [System.Collections.IDictionary] -and $Source[$key] -is [System.Collections.IDictionary]) {
                Merge-TerminalHashtable -Target $Target[$key] -Source $Source[$key]
            } elseif ($key -eq "list" -and $Target[$key] -is [System.Collections.IList] -and $Source[$key] -is [System.Collections.IList]) {
                # Merge profile list by guid or name to preserve all user and WSL profiles
                $targetList = [System.Collections.Generic.List[object]]::new($Target[$key])
                foreach ($srcItem in $Source[$key]) {
                    $matched = $false
                    for ($i = 0; $i -lt $targetList.Count; $i++) {
                        $tgtItem = $targetList[$i]
                        if (($srcItem.guid -and $tgtItem.guid -and $srcItem.guid -eq $tgtItem.guid) -or
                            ($srcItem.name -and $tgtItem.name -and $srcItem.name -eq $tgtItem.name)) {
                            if ($tgtItem -is [System.Collections.IDictionary] -and $srcItem -is [System.Collections.IDictionary]) {
                                Merge-TerminalHashtable -Target $tgtItem -Source $srcItem
                            }
                            $matched = $true
                            break
                        }
                    }
                    if (-not $matched) {
                        $targetList.Add($srcItem)
                    }
                }
                $Target[$key] = $targetList
            } elseif ($key -eq "schemes" -and $Target[$key] -is [System.Collections.IList] -and $Source[$key] -is [System.Collections.IList]) {
                # Merge schemes by name to preserve custom user color schemes
                $targetList = [System.Collections.Generic.List[object]]::new($Target[$key])
                foreach ($srcScheme in $Source[$key]) {
                    $matched = $false
                    for ($i = 0; $i -lt $targetList.Count; $i++) {
                        $tgtScheme = $targetList[$i]
                        if ($srcScheme.name -and $tgtScheme.name -and $srcScheme.name -eq $tgtScheme.name) {
                            if ($tgtScheme -is [System.Collections.IDictionary] -and $srcScheme -is [System.Collections.IDictionary]) {
                                Merge-TerminalHashtable -Target $tgtScheme -Source $srcScheme
                            }
                            $matched = $true
                            break
                        }
                    }
                    if (-not $matched) {
                        $targetList.Add($srcScheme)
                    }
                }
                $Target[$key] = $targetList
            } else {
                $Target[$key] = $Source[$key]
            }
        } else {
            $Target[$key] = $Source[$key]
        }
    }
}

if (Test-Path $destFile) {
    try {
        $existingRaw = Get-Content $destFile -Raw
        $sourceRaw = Get-Content $sourceFile -Raw

        $existingHashtable = $existingRaw | ConvertFrom-Json -AsHashtable
        $sourceHashtable = $sourceRaw | ConvertFrom-Json -AsHashtable

        Merge-TerminalHashtable -Target $existingHashtable -Source $sourceHashtable
        $mergedJson = $existingHashtable | ConvertTo-Json -Depth 15

        # Normalize JSON strings for comparison to detect true structural changes
        $existingNormalized = ($existingRaw | ConvertFrom-Json | ConvertTo-Json -Depth 15)
        $mergedNormalized = ($mergedJson | ConvertFrom-Json | ConvertTo-Json -Depth 15)
        $isDiff = ($existingNormalized -ne $mergedNormalized)
    } catch {
        $isDiff = $true
        $mergedJson = Get-Content $sourceFile -Raw
    }

    if ($BackupOnly -or $isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $backupFile = "$destFile.bak_$timestamp"
        if ($DryRun) {
            Write-Host "  [DryRun] Would backup $destFile to $backupFile" -ForegroundColor DarkCyan
        } else {
            Write-Host "Backing up existing settings to $backupFile..." -ForegroundColor Yellow
            Copy-Item -Path $destFile -Destination $backupFile -Force
        }
    }

    if (-not $BackupOnly) {
        if ($isDiff) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would merge repository settings into $destFile" -ForegroundColor DarkCyan
            } else {
                Write-Host "Merging repository settings into Windows Terminal..." -ForegroundColor Cyan
                [System.IO.File]::WriteAllText($destFile, $mergedJson, [System.Text.Encoding]::UTF8)
                Write-Host "==> Windows Terminal settings merged successfully!" -ForegroundColor Green
            }
        } else {
            Write-Host "==> Windows Terminal settings are already up to date." -ForegroundColor Green
        }
    }
} else {
    if ($DryRun) {
        Write-Host "  [DryRun] Would deploy new Windows Terminal settings to $destFile" -ForegroundColor DarkCyan
    } else {
        Write-Host "==> Deploying initial Windows Terminal settings to $destFile..." -ForegroundColor Cyan
        Copy-Item -Path $sourceFile -Destination $destFile -Force
        Write-Host "==> Windows Terminal settings deployed successfully!" -ForegroundColor Green
    }
}
