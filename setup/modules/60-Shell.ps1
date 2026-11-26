# =============================================================
# setup/modules/60-Shell.ps1 - PowerShell Module, Prompt & CMD
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [switch]$SkipPosh,
    [switch]$SkipCmd,
    [switch]$SkipCompletions,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Deploy-ConfigFile -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}
if (-not (Get-Command Sync-ShellCompiledCaches -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Env.ps1')
}

if ($SkipPosh -and $SkipCmd -and $SkipCompletions) {
    Write-SetupSkip -Stage '60-Shell' -Message 'Skipping PowerShell, Command Prompt, and CLI completions setup.'
    return
}

Write-SetupStage -Stage '60-Shell' -Message 'Configuring PowerShell module, Oh My Posh, Command Prompt, and completions...'
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }

if (-not $SkipPosh) {
    $p10kSource = Join-Path (Join-Path (Join-Path $RepoRoot 'config') 'powershell') 'p10k_single_line.omp.json'
    $p10kDest = Join-Path (Join-Path $userHome '.poshthemes') 'p10k_single_line.omp.json'
    if (-not (Test-Path -LiteralPath $p10kDest -PathType Leaf) -or $DryRun) {
        Deploy-ConfigFile -Name 'Oh My Posh theme' -SourcePath $p10kSource -DestinationPath $p10kDest -DryRun:$DryRun
    }

    Write-SetupStep 'Deploying WindowsSettings PowerShell module...'
    $moduleSource = Join-Path $RepoRoot 'module'
    $userModulesDir = Join-Path (Join-Path (Join-Path $userHome 'Documents') 'PowerShell') 'Modules'
    $moduleDest = Join-Path $userModulesDir 'WindowsSettings'
    if (Test-Path -LiteralPath $moduleSource -PathType Container) {
        if ($DryRun) {
            Write-SetupDryRun "Would deploy WindowsSettings module to $moduleDest"
        } else {
            if (-not (Test-Path -LiteralPath $moduleDest -PathType Container)) {
                New-Item -ItemType Directory -Force -Path $moduleDest | Out-Null
            } else {
                foreach ($legacySub in @('Public', 'Completions')) {
                    $staleDir = Join-Path $moduleDest $legacySub
                    if (Test-Path -LiteralPath $staleDir) {
                        Remove-Item -Recurse -Force -LiteralPath $staleDir -ErrorAction SilentlyContinue
                    }
                }
            }
            Copy-Item -Path (Join-Path $moduleSource '*') -Destination $moduleDest -Recurse -Force
            Write-SetupSuccess "WindowsSettings module deployed to $moduleDest"
        }
    }

    if ($PROFILE) {
        Write-SetupStep "Configuring PowerShell profile at $PROFILE..."
        $profileDir = Split-Path -Parent $PROFILE
        if ($profileDir -and -not (Test-Path -LiteralPath $profileDir -PathType Container) -and -not $DryRun) {
            New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
        }
        $profileLine = 'Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue'
        if (Test-Path -LiteralPath $PROFILE -PathType Leaf) {
            $currentContent = [System.IO.File]::ReadAllText($PROFILE, [System.Text.Encoding]::UTF8)
            if ($currentContent -notmatch 'Import-Module\s+WindowsSettings') {
                $backupProfile = Get-TimestampedBackupPath $PROFILE
                if ($DryRun) {
                    Write-SetupDryRun "Would backup $PROFILE to $backupProfile"
                    Write-SetupDryRun "Would append WindowsSettings module import to $PROFILE"
                } else {
                    Copy-Item -LiteralPath $PROFILE -Destination $backupProfile -Force
                    $trimmedCur = $currentContent.Replace("`r`n", "`n").TrimEnd("`n")
                    $nextProf = if ([string]::IsNullOrWhiteSpace($trimmedCur)) {
                        "$profileLine`r`n"
                    } else {
                        ($trimmedCur -replace "`n", "`r`n") + "`r`n`r`n$profileLine`r`n"
                    }
                    Write-CacheFileCrlf -Path $PROFILE -Content $nextProf
                    Write-SetupSuccess 'PowerShell profile updated.'
                }
            } else {
                Write-SetupSuccess 'PowerShell profile is already up to date.'
            }
        } else {
            if ($DryRun) {
                Write-SetupDryRun "Would create 1-line PowerShell profile at $PROFILE"
            } else {
                Write-CacheFileCrlf -Path $PROFILE -Content $profileLine
                Write-SetupSuccess 'PowerShell profile created.'
            }
        }
    }

    $userColorTerm = [Environment]::GetEnvironmentVariable('COLORTERM', 'User')
    if ($userColorTerm -ne 'truecolor') {
        if ($DryRun) {
            Write-SetupDryRun 'Would set User environment variable COLORTERM=truecolor'
        } else {
            [Environment]::SetEnvironmentVariable('COLORTERM', 'truecolor', 'User')
            $env:COLORTERM = 'truecolor'
        }
    }
}

if (-not $SkipCmd) {
    Write-SetupStep 'Configuring Command Prompt (cmd.exe) AutoRun and Doskey macros...'
    $cmdCfgDir = Join-Path (Join-Path $RepoRoot 'config') 'cmd'
    $cmdLocalDir = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'cmd' } else { Join-Path (Join-Path $userHome '.config') 'cmd' }
    $cmdAltDir = Join-Path (Join-Path $userHome '.config') 'cmd'

    $autorunAlts = if ($cmdLocalDir -ne $cmdAltDir) { @((Join-Path $cmdAltDir 'autorun.cmd')) } else { @() }
    Deploy-ConfigFile -Name 'CMD AutoRun script' `
        -SourcePath (Join-Path $cmdCfgDir 'autorun.cmd') `
        -DestinationPath (Join-Path $cmdLocalDir 'autorun.cmd') `
        -AltDestinations $autorunAlts `
        -DryRun:$DryRun

    $macrosAlts = if ($cmdLocalDir -ne $cmdAltDir) { @((Join-Path $cmdAltDir 'macros.doskey')) } else { @() }
    Deploy-ConfigFile -Name 'CMD Doskey macrofile' `
        -SourcePath (Join-Path $cmdCfgDir 'macros.doskey') `
        -DestinationPath (Join-Path $cmdLocalDir 'macros.doskey') `
        -AltDestinations $macrosAlts `
        -DryRun:$DryRun

    $consoleKey = 'HKCU:\Console'
    if (-not (Test-Path -LiteralPath $consoleKey) -and -not $DryRun) {
        New-Item -Path $consoleKey -Force | Out-Null
    }
    $vtProp = Get-ItemProperty -Path $consoleKey -Name 'VirtualTerminalLevel' -ErrorAction SilentlyContinue
    if (-not $vtProp -or $vtProp.VirtualTerminalLevel -ne 1) {
        if ($DryRun) {
            Write-SetupDryRun 'Would set HKCU:\Console\VirtualTerminalLevel = 1 (DWORD)'
        } else {
            Set-ItemProperty -Path $consoleKey -Name 'VirtualTerminalLevel' -Value 1 -Type DWord -Force
            Write-SetupSuccess 'Console VirtualTerminalLevel (ANSI) enabled.'
        }
    }

    $cmdProcessorKey = 'HKCU:\Software\Microsoft\Command Processor'
    $autoRunTarget = 'if exist "%LOCALAPPDATA%\cmd\autorun.cmd" call "%LOCALAPPDATA%\cmd\autorun.cmd"'
    if (-not (Test-Path -LiteralPath $cmdProcessorKey) -and -not $DryRun) {
        New-Item -Path $cmdProcessorKey -Force | Out-Null
    }
    $apProp = Get-ItemProperty -Path $cmdProcessorKey -Name 'AutoRun' -ErrorAction SilentlyContinue
    $existingAutoRun = if ($apProp) { $apProp.AutoRun } else { $null }
    if (-not $existingAutoRun -or $existingAutoRun -notlike '*autorun.cmd*') {
        if ($DryRun) {
            Write-SetupDryRun "Would configure CMD AutoRun in $cmdProcessorKey"
        } else {
            $newAutoRun = if ([string]::IsNullOrWhiteSpace($existingAutoRun)) {
                $autoRunTarget
            } else {
                "$existingAutoRun & $autoRunTarget"
            }
            Set-ItemProperty -Path $cmdProcessorKey -Name 'AutoRun' -Value $newAutoRun -Type ExpandString -Force
            Write-SetupSuccess 'CMD AutoRun configured in registry.'
        }
    } else {
        Write-SetupSuccess 'CMD AutoRun is already configured in registry.'
    }
}

Sync-ShellCompiledCaches -SkipPosh:$SkipPosh -SkipCompletions:$SkipCompletions -DryRun:$DryRun
