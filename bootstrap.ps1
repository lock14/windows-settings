<#
.SYNOPSIS
    Zero-dependency bootstrap script for windows-settings.
    Clones or updates the repository and runs the modular setup orchestrator.
.DESCRIPTION
    Can be invoked locally or streamed directly in PowerShell 7.
#>

$ErrorActionPreference = 'Stop'

$script:UsageText = @'
Usage: bootstrap.ps1 [OPTIONS]

Clone or update windows-settings and run the modular workstation setup orchestrator.

Workflows and Scope:
  (default)               Provision WinGet packages and user environment
  -User, --user           Configure user dotfiles, fonts, runtimes, editor, shell, terminal, and hooks only
  -SystemOnly             Provision WinGet system packages only
  -UseDSC                 Provision WinGet packages using configuration.dsc.yaml
  -Uninstall [TARGET]     Remove managed artifacts: all (default) or comma-separated dotfiles,fonts,bin

Component Options:
  -Gui [APP,...]          Optional desktop apps: all (default: vscode,terminal,docker) or
                          comma-separated vscode,terminal,docker,none
  -Theme <NAME>           Initial color theme to apply (default: existing user theme or solarized-dark)
  -Skip <STAGE,...>       Skip comma-separated stages:
                          packages,dotfiles,bin,fonts,tools,nvim,vim,posh,cmd,completions,terminal,hooks

Execution Options:
  -n, -DryRun, --dry-run  Preview actions without modifying the system
  -h, -Help, --help       Show this help message and exit
'@

$validUninstallTokens = @('all', 'dotfiles', 'fonts', 'bin')
$validGuiTokens = @('all', 'vscode', 'terminal', 'docker', 'none')
$validSkipTokens = @(
    'packages', 'dotfiles', 'bin', 'fonts', 'tools',
    'nvim', 'vim', 'posh', 'cmd', 'completions', 'terminal', 'hooks'
)

$dryRun = $false
$isHelp = $false
$forwardArgs = [System.Collections.Generic.List[string]]::new()

function ConvertTo-BootstrapTokenList($RawValue) {
    $result = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $RawValue) { return , $result.ToArray() }
    $items = if ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) {
        @($RawValue)
    } else {
        @($RawValue)
    }
    foreach ($it in $items) {
        if ($null -eq $it) { continue }
        foreach ($piece in ("$it" -split ',')) {
            $trimmed = $piece.Trim()
            if ($trimmed) { $result.Add($trimmed) }
        }
    }
    return , $result.ToArray()
}

for ($i = 0; $i -lt $args.Count; $i++) {
    $rawItem = $args[$i]
    $arg = "$rawItem"
    $hasColon = $arg.EndsWith(':')
    $normOpt = if ($hasColon) { $arg.Substring(0, $arg.Length - 1) } else { $arg }

    switch -Regex ($normOpt) {
        '^(?i)(-h|--help|-Help|-\?)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) { $isHelp = $true }
            } else {
                $isHelp = $true
            }
            continue
        }
        '^(?i)(-n|--dry-run|-DryRun)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) {
                    $dryRun = $true
                    $forwardArgs.Add('-DryRun')
                }
            } else {
                $dryRun = $true
                $forwardArgs.Add('-DryRun')
            }
            continue
        }
        '^(?i)(-User|--user)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) { $forwardArgs.Add('-User') }
            } else {
                $forwardArgs.Add('-User')
            }
            continue
        }
        '^(?i)(-SystemOnly|--system-only)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) { $forwardArgs.Add('-SystemOnly') }
            } else {
                $forwardArgs.Add('-SystemOnly')
            }
            continue
        }
        '^(?i)(-UseDSC|--use-dsc)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) { $forwardArgs.Add('-UseDSC') }
            } else {
                $forwardArgs.Add('-UseDSC')
            }
            continue
        }
        '^(?i)^--uninstall=(.*)$' {
            $toks = ConvertTo-BootstrapTokenList $Matches[1]
            if ($toks.Count -eq 0) {
                [Console]::Error.WriteLine('Error: -Uninstall requires a target (all, dotfiles, fonts, or bin).')
                exit 1
            }
            foreach ($t in $toks) {
                if ($t.ToLowerInvariant() -notin $validUninstallTokens) {
                    [Console]::Error.WriteLine("Error: Unknown -Uninstall target '$t' (expected: all, dotfiles, fonts, or bin).")
                    exit 1
                }
            }
            $forwardArgs.Add('-Uninstall')
            $forwardArgs.Add(($toks -join ','))
            continue
        }
        '^(?i)(-Uninstall|--uninstall)$' {
            if ($hasColon) {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine('Error: -Uninstall requires a value.')
                    exit 1
                }
                $val = $args[++$i]
                if ($val -is [bool]) {
                    if ($val) {
                        $forwardArgs.Add('-Uninstall')
                        $forwardArgs.Add('all')
                    }
                    continue
                }
                $toks = ConvertTo-BootstrapTokenList $val
                if ($toks.Count -eq 0) { continue }
                foreach ($t in $toks) {
                    if ($t.ToLowerInvariant() -notin $validUninstallTokens) {
                        [Console]::Error.WriteLine("Error: Unknown -Uninstall target '$t' (expected: all, dotfiles, fonts, or bin).")
                        exit 1
                    }
                }
                $forwardArgs.Add('-Uninstall')
                $forwardArgs.Add(($toks -join ','))
                continue
            }
            if ($i + 1 -lt $args.Count -and -not ("$($args[$i + 1])").StartsWith('-')) {
                $toks = ConvertTo-BootstrapTokenList $args[++$i]
                if ($toks.Count -eq 0) {
                    [Console]::Error.WriteLine('Error: -Uninstall requires a target (all, dotfiles, fonts, or bin).')
                    exit 1
                }
                foreach ($t in $toks) {
                    if ($t.ToLowerInvariant() -notin $validUninstallTokens) {
                        [Console]::Error.WriteLine("Error: Unknown -Uninstall target '$t' (expected: all, dotfiles, fonts, or bin).")
                        exit 1
                    }
                }
                $forwardArgs.Add('-Uninstall')
                $forwardArgs.Add(($toks -join ','))
            } else {
                $forwardArgs.Add('-Uninstall')
                $forwardArgs.Add('all')
            }
            continue
        }
        '^(?i)^--gui=(.*)$' {
            $toks = ConvertTo-BootstrapTokenList $Matches[1]
            if ($toks.Count -eq 0) {
                [Console]::Error.WriteLine('Error: -Gui requires an app list (all, vscode, terminal, docker, or none).')
                exit 1
            }
            foreach ($t in $toks) {
                if ($t.ToLowerInvariant() -notin $validGuiTokens) {
                    [Console]::Error.WriteLine("Error: '$t' is not a supported -Gui app (expected: all, vscode, terminal, docker, or none).")
                    exit 1
                }
            }
            $forwardArgs.Add('-Gui')
            $forwardArgs.Add(($toks -join ','))
            continue
        }
        '^(?i)(-Gui|--gui)$' {
            if ($hasColon) {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine('Error: -Gui requires a value.')
                    exit 1
                }
                $val = $args[++$i]
                if ($val -is [bool]) {
                    if ($val) {
                        $forwardArgs.Add('-Gui')
                        $forwardArgs.Add('all')
                    }
                    continue
                }
                $toks = ConvertTo-BootstrapTokenList $val
                if ($toks.Count -eq 0) { continue }
                foreach ($t in $toks) {
                    if ($t.ToLowerInvariant() -notin $validGuiTokens) {
                        [Console]::Error.WriteLine("Error: '$t' is not a supported -Gui app (expected: all, vscode, terminal, docker, or none).")
                        exit 1
                    }
                }
                $forwardArgs.Add('-Gui')
                $forwardArgs.Add(($toks -join ','))
                continue
            }
            if ($i + 1 -lt $args.Count -and -not ("$($args[$i + 1])").StartsWith('-')) {
                $toks = ConvertTo-BootstrapTokenList $args[++$i]
                if ($toks.Count -eq 0) {
                    [Console]::Error.WriteLine('Error: -Gui requires an app list (all, vscode, terminal, docker, or none).')
                    exit 1
                }
                foreach ($t in $toks) {
                    if ($t.ToLowerInvariant() -notin $validGuiTokens) {
                        [Console]::Error.WriteLine("Error: '$t' is not a supported -Gui app (expected: all, vscode, terminal, docker, or none).")
                        exit 1
                    }
                }
                $forwardArgs.Add('-Gui')
                $forwardArgs.Add(($toks -join ','))
            } else {
                $forwardArgs.Add('-Gui')
                $forwardArgs.Add('all')
            }
            continue
        }
        '^(?i)^--theme=(.*)$' {
            $tVal = $Matches[1].Trim()
            if (-not $tVal -or $tVal.StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $forwardArgs.Add('-Theme')
            $forwardArgs.Add($tVal)
            continue
        }
        '^(?i)(-Theme|--theme)$' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $tVal = "$($args[++$i])".Trim()
            if ($hasColon -and -not $tVal) { continue }
            if (-not $tVal -or $tVal.StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $forwardArgs.Add('-Theme')
            $forwardArgs.Add($tVal)
            continue
        }
        '^(?i)^--skip=(.*)$' {
            $toks = ConvertTo-BootstrapTokenList $Matches[1]
            if ($toks.Count -eq 0) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            foreach ($t in $toks) {
                if ($t.ToLowerInvariant() -notin $validSkipTokens) {
                    [Console]::Error.WriteLine("Error: Unknown -Skip stage '$t' (expected: $($validSkipTokens -join ', ')).")
                    exit 1
                }
            }
            $forwardArgs.Add('-Skip')
            $forwardArgs.Add(($toks -join ','))
            continue
        }
        '^(?i)(-Skip|--skip)$' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            $nextVal = $args[++$i]
            if ($hasColon -and ($nextVal -is [System.Collections.IEnumerable]) -and -not ($nextVal -is [string]) -and @($nextVal).Count -eq 0) {
                continue
            }
            if (-not ($nextVal -is [System.Collections.IEnumerable] -and -not ($nextVal -is [string])) -and ("$nextVal").StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            $toks = ConvertTo-BootstrapTokenList $nextVal
            if ($toks.Count -eq 0) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            foreach ($t in $toks) {
                if ($t.ToLowerInvariant() -notin $validSkipTokens) {
                    [Console]::Error.WriteLine("Error: Unknown -Skip stage '$t' (expected: $($validSkipTokens -join ', ')).")
                    exit 1
                }
            }
            $forwardArgs.Add('-Skip')
            $forwardArgs.Add(($toks -join ','))
            continue
        }
        '^(?i)(-Verbose|-Debug)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) { $i++ }
            continue
        }
        '^(?i)(-ErrorAction|-WarningAction|-InformationAction)$' {
            if ($i + 1 -lt $args.Count) { $i++ }
            continue
        }
        default {
            [Console]::Error.WriteLine("Error: Unknown option '$arg' (run 'bootstrap.ps1 -Help' for usage).")
            exit 1
        }
    }
}

if ($isHelp) {
    Write-Output $script:UsageText
    exit 0
}

Write-Host '=====================================================' -ForegroundColor Cyan
Write-Host '       windows-settings Turnkey Bootstrapper         ' -ForegroundColor Cyan
if ($dryRun) {
    Write-Host '               [DRY RUN PREVIEW MODE]                ' -ForegroundColor Magenta
}
Write-Host '=====================================================' -ForegroundColor Cyan

# 1. Verify Git prerequisite
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "`n[1/3] Git not found. Attempting installation via winget..." -ForegroundColor Yellow
    if ($dryRun) {
        Write-Host '  [DryRun] Would install Git.Git via winget' -ForegroundColor DarkCyan
    } elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    } else {
        [Console]::Error.WriteLine('Error: Git is required to clone windows-settings. Please install Git and rerun.')
        exit 1
    }
} else {
    Write-Host "`n[1/3] Git prerequisite satisfied." -ForegroundColor Green
}

# 2. Determine target repository location
$repoUrl = 'https://github.com/lock14/windows-settings.git'
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
$targetDir = Join-Path $userHome 'windows-settings'

if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'setup.ps1') -PathType Leaf)) {
    $targetDir = $PSScriptRoot
    Write-Host "`n[2/3] Using existing repository clone at $targetDir." -ForegroundColor Green
} elseif (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
    if ($dryRun) {
        Write-Host "`n[2/3] [DryRun] Would clone $repoUrl to $targetDir..." -ForegroundColor DarkCyan
    } else {
        Write-Host "`n[2/3] Cloning windows-settings to $targetDir..." -ForegroundColor Yellow
        & git clone $repoUrl $targetDir
    }
} else {
    if ($dryRun) {
        Write-Host "`n[2/3] [DryRun] Would update existing windows-settings at $targetDir via git pull..." -ForegroundColor DarkCyan
    } else {
        Write-Host "`n[2/3] Updating existing windows-settings at $targetDir..." -ForegroundColor Yellow
        & git -C $targetDir pull --rebase
    }
}

# 3. Execute setup orchestrator
$setupScript = Join-Path $targetDir 'setup.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    if ($dryRun) {
        Write-Host "`n[3/3] [DryRun] Setup orchestrator preview complete (target repository clone skipped in DryRun)." -ForegroundColor Magenta
        exit 0
    }
    [Console]::Error.WriteLine("Error: Setup script not found at $setupScript")
    exit 1
}

Write-Host "`n[3/3] Invoking master setup orchestrator..." -ForegroundColor Cyan
$fwd = $forwardArgs.ToArray()
& $setupScript @fwd
exit $LASTEXITCODE
