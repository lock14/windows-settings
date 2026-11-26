<#
.SYNOPSIS
    Modular workstation provisioner and dotfiles orchestrator for windows-settings.
.DESCRIPTION
    Provisions WinGet CLI and optional GUI packages, MesloLGS Nerd Font Mono,
    Mise polyglot runtimes, Neovim and Vim configurations, PowerShell and Command
    Prompt environments, Zellij workspace and WASM top bar, Windows Terminal
    fragments, TrueColor themes, and AI CLI lifecycle hooks.
#>

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupLibDir = Join-Path (Join-Path $RootDir 'setup') 'lib'
$SetupModulesDir = Join-Path (Join-Path $RootDir 'setup') 'modules'

. (Join-Path $SetupLibDir 'Log.ps1')
. (Join-Path $SetupLibDir 'Deploy.ps1')
. (Join-Path $SetupLibDir 'Env.ps1')

$script:UsageText = @'
Usage: setup.ps1 [OPTIONS]

Modular Windows workstation provisioner and dotfiles engine.

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

$isUser = $false
$isSystemOnly = $false
$useDsc = $false
$dryRun = $false
$isHelp = $false
$isUninstall = $false
$uninstallTargets = [System.Collections.Generic.List[string]]::new()
$guiApps = [System.Collections.Generic.List[string]]::new()
$skipStages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$themeValue = ''

function ConvertTo-FlatTokenList($RawValue) {
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
            if ($trimmed) {
                $result.Add($trimmed)
            }
        }
    }
    return , $result.ToArray()
}

function Add-ValidatedUninstallList($RawValue) {
    $tokens = ConvertTo-FlatTokenList $RawValue
    if ($tokens.Count -eq 0) {
        [Console]::Error.WriteLine('Error: -Uninstall requires a target (all, dotfiles, fonts, or bin).')
        exit 1
    }
    foreach ($tok in $tokens) {
        $low = $tok.ToLowerInvariant()
        if ($low -notin $validUninstallTokens) {
            [Console]::Error.WriteLine("Error: Unknown -Uninstall target '$tok' (expected: all, dotfiles, fonts, or bin).")
            exit 1
        }
        if ($low -eq 'all') {
            $uninstallTargets.Clear()
            $uninstallTargets.Add('all')
            return
        }
        if (-not $uninstallTargets.Contains('all') -and -not $uninstallTargets.Contains($low)) {
            $uninstallTargets.Add($low)
        }
    }
}

function Add-ValidatedGuiList($RawValue) {
    $tokens = ConvertTo-FlatTokenList $RawValue
    if ($tokens.Count -eq 0) {
        [Console]::Error.WriteLine('Error: -Gui requires an app list (all, vscode, terminal, docker, or none).')
        exit 1
    }
    foreach ($tok in $tokens) {
        $low = $tok.ToLowerInvariant()
        if ($low -notin $validGuiTokens) {
            [Console]::Error.WriteLine("Error: '$tok' is not a supported -Gui app (expected: all, vscode, terminal, docker, or none).")
            exit 1
        }
        if ($low -eq 'none') {
            $guiApps.Clear()
        } elseif ($low -eq 'all') {
            foreach ($app in @('vscode', 'terminal', 'docker')) {
                if (-not $guiApps.Contains($app)) { $guiApps.Add($app) }
            }
        } else {
            if (-not $guiApps.Contains($low)) { $guiApps.Add($low) }
        }
    }
}

function Add-ValidatedSkipList($RawValue) {
    $tokens = ConvertTo-FlatTokenList $RawValue
    if ($tokens.Count -eq 0) {
        [Console]::Error.WriteLine('Error: -Skip requires one or more stage names.')
        exit 1
    }
    foreach ($tok in $tokens) {
        $low = $tok.ToLowerInvariant()
        if ($low -notin $validSkipTokens) {
            [Console]::Error.WriteLine("Error: Unknown -Skip stage '$tok' (expected: $($validSkipTokens -join ', ')).")
            exit 1
        }
        [void]$skipStages.Add($low)
    }
}

for ($i = 0; $i -lt $args.Count; $i++) {
    $rawItem = $args[$i]
    $arg = "$rawItem"
    $hasColon = $arg.EndsWith(':')
    $normOpt = if ($hasColon) { $arg.Substring(0, $arg.Length - 1) } else { $arg }

    switch -Regex ($normOpt) {
        '^(?i)(-h|--help|-Help|-\?)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $isHelp = [bool]$args[++$i]
            } else {
                $isHelp = $true
            }
            continue
        }
        '^(?i)(-n|--dry-run|-DryRun)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $dryRun = [bool]$args[++$i]
            } else {
                $dryRun = $true
            }
            continue
        }
        '^(?i)(-User|--user)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $isUser = [bool]$args[++$i]
            } else {
                $isUser = $true
            }
            continue
        }
        '^(?i)(-SystemOnly|--system-only)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $isSystemOnly = [bool]$args[++$i]
            } else {
                $isSystemOnly = $true
            }
            continue
        }
        '^(?i)(-UseDSC|--use-dsc)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $useDsc = [bool]$args[++$i]
            } else {
                $useDsc = $true
            }
            continue
        }
        '^(?i)^--uninstall=(.*)$' {
            $isUninstall = $true
            Add-ValidatedUninstallList $Matches[1]
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
                        $isUninstall = $true
                        Add-ValidatedUninstallList 'all'
                    }
                } elseif ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    $arr = @($val)
                    if ($arr.Count -gt 0) {
                        $isUninstall = $true
                        Add-ValidatedUninstallList $arr
                    }
                } else {
                    $isUninstall = $true
                    Add-ValidatedUninstallList $val
                }
                continue
            }
            $isUninstall = $true
            if ($i + 1 -lt $args.Count -and -not ("$($args[$i + 1])").StartsWith('-')) {
                Add-ValidatedUninstallList $args[++$i]
            } else {
                Add-ValidatedUninstallList 'all'
            }
            continue
        }
        '^(?i)^--gui=(.*)$' {
            Add-ValidatedGuiList $Matches[1]
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
                    if ($val) { Add-ValidatedGuiList 'all' }
                } elseif ($val -is [System.Collections.IEnumerable] -and -not ($val -is [string])) {
                    $arr = @($val)
                    if ($arr.Count -gt 0) { Add-ValidatedGuiList $arr }
                } else {
                    Add-ValidatedGuiList $val
                }
                continue
            }
            if ($i + 1 -lt $args.Count -and -not ("$($args[$i + 1])").StartsWith('-')) {
                Add-ValidatedGuiList $args[++$i]
            } else {
                Add-ValidatedGuiList 'all'
            }
            continue
        }
        '^(?i)^--theme=(.*)$' {
            $tVal = $Matches[1].Trim()
            if (-not $tVal -or $tVal.StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $themeValue = $tVal
            continue
        }
        '^(?i)(-Theme|--theme)$' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $nextRaw = "$($args[++$i])".Trim()
            if ($hasColon -and -not $nextRaw) { continue }
            if (-not $nextRaw -or $nextRaw.StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Theme requires a theme name.')
                exit 1
            }
            $themeValue = $nextRaw
            continue
        }
        '^(?i)^--skip=(.*)$' {
            Add-ValidatedSkipList $Matches[1]
            continue
        }
        '^(?i)(-Skip|--skip)$' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            $nextVal = $args[++$i]
            if ($hasColon -and ($nextVal -is [System.Collections.IEnumerable]) -and -not ($nextVal -is [string])) {
                $arr = @($nextVal)
                if ($arr.Count -eq 0) { continue }
            }
            if (-not ($nextVal -is [System.Collections.IEnumerable] -and -not ($nextVal -is [string])) -and ("$nextVal").StartsWith('-')) {
                [Console]::Error.WriteLine('Error: -Skip requires comma-separated stage names.')
                exit 1
            }
            Add-ValidatedSkipList $nextVal
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
            [Console]::Error.WriteLine("Error: Unknown option '$arg' (run 'setup.ps1 -Help' for usage).")
            exit 1
        }
    }
}

if ($isHelp) {
    Write-Output $script:UsageText
    exit 0
}

if ($isUninstall) {
    $resolvedTargets = if ($uninstallTargets.Count -gt 0) { $uninstallTargets.ToArray() } else { @('all') }
    & (Join-Path $SetupModulesDir '99-Uninstall.ps1') -RepoRoot $RootDir -Targets $resolvedTargets -DryRun:$dryRun
    exit 0
}

if ($themeValue) {
    $themeValidator = Join-Path (Join-Path $RootDir 'bin') 'theme.ps1'
    if (Test-Path -LiteralPath $themeValidator -PathType Leaf) {
        if ($themeValue.ToLowerInvariant() -eq 'holiday') {
            & $themeValidator --dry-run --no-live --holiday *> $null
        } else {
            & $themeValidator --dry-run --no-live --set $themeValue *> $null
        }
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("Error: Unknown or invalid theme '$themeValue' (run 'theme --list' to view themes).")
            exit 1
        }
    }
}

Write-SetupBanner -Title 'Windows Settings Setup Automation' -DryRun:$dryRun

$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
if (-not $env:ELAN_HOME) {
    $env:ELAN_HOME = Join-Path (Join-Path (Join-Path $userHome '.local') 'share') 'elan'
}
Add-SessionPathEntry -Directory (Join-Path (Join-Path $userHome '.local') 'bin') -Prepend

# 1. System Package Provisioning
if (-not $isUser -and -not $skipStages.Contains('packages')) {
    & (Join-Path $SetupModulesDir '00-Packages.ps1') `
        -RepoRoot $RootDir `
        -UseDSC:$useDsc `
        -Gui ($guiApps.ToArray()) `
        -DryRun:$dryRun
} else {
    Write-SetupSkip -Stage '00-Packages' -Message 'Skipping system package provisioning.'
}

# 2. User Environment Provisioning
if (-not $isSystemOnly) {
    if (-not $skipStages.Contains('dotfiles')) {
        & (Join-Path $SetupModulesDir '10-Dotfiles.ps1') -RepoRoot $RootDir -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '10-Dotfiles' -Message 'Skipping CLI dotfiles and theme specifications.'
    }

    if (-not $skipStages.Contains('bin')) {
        & (Join-Path $SetupModulesDir '20-Bin.ps1') -RepoRoot $RootDir -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '20-Bin' -Message 'Skipping User PATH registration.'
    }

    if (-not $skipStages.Contains('fonts')) {
        & (Join-Path $SetupModulesDir '30-Fonts.ps1') -RepoRoot $RootDir -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '30-Fonts' -Message 'Skipping MesloLGS Nerd Font Mono setup.'
    }

    if (-not $skipStages.Contains('tools')) {
        & (Join-Path $SetupModulesDir '40-Mise.ps1') -RepoRoot $RootDir -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '40-Mise' -Message 'Skipping Mise toolchain hydration.'
    }

    if ($env:LOCALAPPDATA) {
        Add-SessionPathEntry -Directory (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims') -Prepend
    }
    Add-SessionPathEntry -Directory (Join-Path $env:ELAN_HOME 'bin') -Prepend

    & (Join-Path $SetupModulesDir '50-Nvim.ps1') `
        -RepoRoot $RootDir `
        -SkipNvim:($skipStages.Contains('nvim')) `
        -SkipVim:($skipStages.Contains('vim')) `
        -DryRun:$dryRun

    & (Join-Path $SetupModulesDir '60-Shell.ps1') `
        -RepoRoot $RootDir `
        -SkipPosh:($skipStages.Contains('posh')) `
        -SkipCmd:($skipStages.Contains('cmd')) `
        -SkipCompletions:($skipStages.Contains('completions')) `
        -DryRun:$dryRun

    if (-not $skipStages.Contains('terminal')) {
        & (Join-Path $SetupModulesDir '70-Terminal.ps1') `
            -RepoRoot $RootDir `
            -Theme $themeValue `
            -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '70-Terminal' -Message 'Skipping Zellij, Windows Terminal, and theme deployment.'
    }

    if (-not $skipStages.Contains('hooks')) {
        & (Join-Path $SetupModulesDir '75-AiHooks.ps1') `
            -RepoRoot $RootDir `
            -DryRun:$dryRun
    } else {
        Write-SetupSkip -Stage '75-AiHooks' -Message 'Skipping AI CLI lifecycle hooks.'
    }

    if (-not $dryRun -and -not $skipStages.Contains('posh') -and $env:WS_TEST_MODE -ne '1') {
        try {
            Import-Module WindowsSettings -Force -Global -DisableNameChecking -ErrorAction SilentlyContinue
        } catch {
            $null = $_
        }
    }
}

Write-SetupFooter -SuccessMessage 'Workstation configuration completed successfully!' `
    -DryRunMessage 'Dry run complete! No changes were made to system.' `
    -DryRun:$dryRun
exit 0
