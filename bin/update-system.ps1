<#
.SYNOPSIS
    Unified Windows system and developer toolchain maintenance utility.
.DESCRIPTION
    Updates WinGet packages and performs cache cleanup by default.
    When invoked with --all, also updates Mise runtimes and PATH caches,
    PowerShell Gallery modules, Rustup, Elan, lockfile-faithful headless
    Neovim plugins, Zellij WASM top bar, Tealdeer pages, bat binary cache,
    and compiled shell and IDE startup caches.
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$SetupLibDir = Join-Path (Join-Path $RepoRoot 'setup') 'lib'
$SetupModulesDir = Join-Path (Join-Path $RepoRoot 'setup') 'modules'

$script:UsageText = @'
Usage: update-system [OPTIONS]

Windows package, runtime, editor, and cache maintenance utility.

Options:
  --all, -All                    Include Mise runtimes, PowerShell modules, Rustup, Elan,
                                 Neovim lockfile sync, WASM bar, Tealdeer, bat, and shell caches
  --system-only, -SystemOnly     Update WinGet system packages only
  --skip, -Skip <TARGET,...>     Skip comma-separated phases: winget,mise,modules,nvim,cleanup
  -i, --interactive              Prompt for confirmation during package updates
  -n, --dry-run, -DryRun         Preview update commands without modifying the system
  -h, --help, -Help              Display this help message and exit

Examples:
  update-system                        Update WinGet packages and clean stale artifacts
  update-system --all                  Update packages, toolchains, lockfile plugins, and caches
  update-system --all --skip nvim      Run full update while skipping Neovim plugin sync
  update-system -n                     Preview planned actions without executing changes
'@

if (Test-Path -LiteralPath (Join-Path $SetupLibDir 'Deploy.ps1') -PathType Leaf) {
    . (Join-Path $SetupLibDir 'Deploy.ps1')
}
if (Test-Path -LiteralPath (Join-Path $SetupLibDir 'Env.ps1') -PathType Leaf) {
    . (Join-Path $SetupLibDir 'Env.ps1')
}
if (Test-Path -LiteralPath (Join-Path $SetupModulesDir '50-Nvim.ps1') -PathType Leaf) {
    . (Join-Path $SetupModulesDir '50-Nvim.ps1') -FunctionsOnly
}

$validSkipTargets = @('winget', 'mise', 'modules', 'nvim', 'cleanup')
$withAll = $false
$systemOnly = $false
$interactive = $false
$isUpdateDryRun = $false
$skipSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

function Add-UpdateSkipList($RawValue) {
    $items = if ($RawValue -is [System.Collections.IEnumerable] -and -not ($RawValue -is [string])) {
        @($RawValue)
    } else {
        @($RawValue)
    }
    $parsed = [System.Collections.Generic.List[string]]::new()
    foreach ($it in $items) {
        if ($null -eq $it) { continue }
        foreach ($piece in ("$it" -split ',')) {
            $t = $piece.Trim()
            if ($t) { $parsed.Add($t) }
        }
    }
    if ($parsed.Count -eq 0) {
        [Console]::Error.WriteLine('update-system: option --skip requires one or more targets (winget, mise, modules, nvim, cleanup)')
        exit 1
    }
    foreach ($tok in $parsed) {
        $low = $tok.ToLowerInvariant()
        if ($low -notin $validSkipTargets) {
            [Console]::Error.WriteLine("update-system: invalid --skip target '$tok' (expected: winget, mise, modules, nvim, cleanup)")
            exit 1
        }
        [void]$skipSet.Add($low)
    }
}

for ($i = 0; $i -lt $args.Count; $i++) {
    $rawArg = $args[$i]
    $arg = "$rawArg"
    $hasColon = $arg.EndsWith(':')
    $normOpt = if ($hasColon) { $arg.Substring(0, $arg.Length - 1) } else { $arg }

    switch -Regex ($normOpt) {
        '^(?i)(-h|--help|-Help|-\?)$' {
            Write-Output $script:UsageText
            exit 0
        }
        '^(?i)(-n|--dry-run|-DryRun)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $isUpdateDryRun = [bool]$args[++$i]
            } else {
                $isUpdateDryRun = $true
            }
            continue
        }
        '^(?i)(-i|--interactive|-Interactive)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                $interactive = [bool]$args[++$i]
            } else {
                $interactive = $true
            }
            continue
        }
        '^(?i)(--all|-All)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) {
                    $withAll = $true
                    $systemOnly = $false
                }
            } else {
                $withAll = $true
                $systemOnly = $false
            }
            continue
        }
        '^(?i)(--system-only|-SystemOnly)$' {
            if ($hasColon -and $i + 1 -lt $args.Count -and ($args[$i + 1] -is [bool])) {
                if ([bool]$args[++$i]) {
                    $systemOnly = $true
                    $withAll = $false
                }
            } else {
                $systemOnly = $true
                $withAll = $false
            }
            continue
        }
        '^(?i)^--skip=(.*)$' {
            Add-UpdateSkipList $Matches[1]
            continue
        }
        '^(?i)(--skip|-Skip)$' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('update-system: option --skip requires comma-separated targets (winget, mise, modules, nvim, cleanup)')
                exit 1
            }
            $nextVal = $args[++$i]
            if ($hasColon -and ($nextVal -is [System.Collections.IEnumerable]) -and -not ($nextVal -is [string]) -and @($nextVal).Count -eq 0) {
                continue
            }
            if (-not ($nextVal -is [System.Collections.IEnumerable] -and -not ($nextVal -is [string])) -and ("$nextVal").StartsWith('-')) {
                [Console]::Error.WriteLine('update-system: option --skip requires comma-separated targets (winget, mise, modules, nvim, cleanup)')
                exit 1
            }
            Add-UpdateSkipList $nextVal
            continue
        }
        default {
            [Console]::Error.WriteLine("update-system: unknown option '$arg' (try 'update-system --help')")
            exit 1
        }
    }
}

function Invoke-UpdateStep([string]$Title, [string]$PreviewText, [scriptblock]$Action) {
    Write-Host "==> $Title" -ForegroundColor Cyan
    if ($isUpdateDryRun) {
        Write-Output "[DRY-RUN] Would run: $PreviewText"
        return
    }
    try {
        & $Action
    } catch {
        Write-Warning "$Title encountered a non-fatal error: $_"
    }
}

# 1. WinGet System Packages
if (-not $skipSet.Contains('winget')) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wgPreview = if ($interactive) {
            'winget upgrade --all --interactive --accept-source-agreements --accept-package-agreements'
        } else {
            'winget upgrade --all --accept-source-agreements --accept-package-agreements'
        }
        Invoke-UpdateStep -Title 'WinGet Package Upgrades' -PreviewText $wgPreview -Action {
            if ($interactive) {
                & winget upgrade --all --interactive --accept-source-agreements --accept-package-agreements
            } else {
                & winget upgrade --all --accept-source-agreements --accept-package-agreements
            }
        }
    } else {
        Write-Warning 'winget not found in PATH; skipping WinGet package upgrades.'
    }
}

# 2. Developer Toolchains, Editor Lockfile Restore, WASM Bar & Shell Caches (--all)
if ($withAll -and -not $systemOnly) {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $elanHome = if ($env:ELAN_HOME -and $env:ELAN_HOME.Trim()) {
        $env:ELAN_HOME.Trim()
    } else {
        Join-Path (Join-Path (Join-Path $userHome '.local') 'share') 'elan'
    }
    $env:ELAN_HOME = $elanHome
    if ($null -ne ${function:Add-SessionPathEntry}) {
        if ($env:LOCALAPPDATA) {
            Add-SessionPathEntry -Directory (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'shims') -Prepend
        }
        Add-SessionPathEntry -Directory (Join-Path $elanHome 'bin') -Prepend
    }

    if (-not $skipSet.Contains('mise') -and ((Get-Command mise -ErrorAction SilentlyContinue) -or $isUpdateDryRun)) {
        $doPrune = (-not $skipSet.Contains('cleanup'))
        $misePreview = if ($doPrune) {
            'mise plugins update && mise upgrade && mise prune -y && Sync-MisePathsCache'
        } else {
            'mise plugins update && mise upgrade && Sync-MisePathsCache'
        }
        Invoke-UpdateStep -Title 'Mise Toolchain and CLI Upgrades' -PreviewText $misePreview -Action {
            & mise plugins update
            & mise upgrade
            if ($doPrune) {
                & mise prune -y
            }
            if ($null -ne ${function:Sync-MisePathsCache}) {
                Sync-MisePathsCache
            }
        }
    }

    if (-not $skipSet.Contains('modules') -and (Get-Command Update-Module -ErrorAction SilentlyContinue)) {
        $modPreview = if ($interactive) {
            'Update-Module -Confirm'
        } else {
            'Update-Module -Confirm:$false -ErrorAction SilentlyContinue'
        }
        Invoke-UpdateStep -Title 'PowerShell Gallery Modules' -PreviewText $modPreview -Action {
            if ($interactive) {
                Update-Module -Confirm
            } else {
                Update-Module -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
    }

    if ((Get-Command rustup -ErrorAction SilentlyContinue) -or $isUpdateDryRun) {
        Invoke-UpdateStep -Title 'Rust Toolchain (rustup)' -PreviewText 'rustup update --no-self-update' -Action {
            if (Get-Command rustup -ErrorAction SilentlyContinue) {
                & rustup update --no-self-update
            }
        }
    }

    if ((Get-Command elan -ErrorAction SilentlyContinue) -or $isUpdateDryRun) {
        Invoke-UpdateStep -Title 'Lean 4 Toolchain (elan)' -PreviewText 'elan update' -Action {
            if (Get-Command elan -ErrorAction SilentlyContinue) {
                & elan update
            }
        }
    }

    if (-not $skipSet.Contains('nvim') -and ((Get-Command nvim -ErrorAction SilentlyContinue) -or $isUpdateDryRun)) {
        Invoke-UpdateStep -Title 'Neovim Lockfile Plugin Sync' `
            -PreviewText 'Invoke-HeadlessNvimSync (lockfile-faithful restore with -i NONE)' `
            -Action {
                if ($null -ne ${function:Invoke-HeadlessNvimSync}) {
                    Invoke-HeadlessNvimSync -RepoRoot $RepoRoot
                }
            }
    }

    if ($null -ne ${function:Sync-ZellijBarPlugin}) {
        Invoke-UpdateStep -Title 'Zellij WASM Top-Bar Plugin' `
            -PreviewText 'Sync-ZellijBarPlugin' `
            -Action {
                [void](Sync-ZellijBarPlugin -RepoRoot $RepoRoot)
            }
    }

    if ((Get-Command tldr -ErrorAction SilentlyContinue) -or $isUpdateDryRun) {
        Invoke-UpdateStep -Title 'Tealdeer tldr Page Cache' -PreviewText 'tldr --update' -Action {
            if (Get-Command tldr -ErrorAction SilentlyContinue) {
                & tldr --update
            }
        }
    }

    $themeScript = Join-Path $ScriptDir 'theme.ps1'
    if ((Get-Command bat -ErrorAction SilentlyContinue) -or $isUpdateDryRun) {
        Invoke-UpdateStep -Title 'Active Theme and bat Syntax Cache' `
            -PreviewText 'theme --set <active> --no-live && bat cache --build' `
            -Action {
                if (Test-Path -LiteralPath $themeScript -PathType Leaf) {
                    $activeSlug = (& $themeScript --current).Trim()
                    if (-not $activeSlug) { $activeSlug = 'solarized-dark' }
                    & $themeScript --set $activeSlug --no-live *> $null
                }
                if (Get-Command bat -ErrorAction SilentlyContinue) {
                    & bat cache --build
                }
            }
    }

    Invoke-UpdateStep -Title 'Compiled Shell and IDE Startup Caches' `
        -PreviewText 'Regenerate omp_init.ps1, zoxide_init.ps1, gh_completion.ps1, completions_cache.ps1, and IDE keys cache' `
        -Action {
            if ($null -ne ${function:Sync-ShellCompiledCaches}) {
                Sync-ShellCompiledCaches
            }
            $ideScript = Join-Path $ScriptDir 'ide.ps1'
            if (Test-Path -LiteralPath $ideScript -PathType Leaf) {
                & $ideScript _internal write-keys-cache *> $null
            }
        }
}

# 3. Stale Artifact & Cache Cleanup
if (-not $systemOnly -and -not $skipSet.Contains('cleanup')) {
    Invoke-UpdateStep -Title 'Temporary Cache and Lock Cleanup' `
        -PreviewText 'Prune leftover tree-sitter temp directories and expired cache locks' `
        -Action {
            $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
            $nvimData = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'nvim-data' } else { Join-Path (Join-Path (Join-Path $userHome '.local') 'share') 'nvim' }
            if (Test-Path -LiteralPath $nvimData -PathType Container) {
                foreach ($tsTmp in (Get-ChildItem -LiteralPath $nvimData -Filter 'tree-sitter-*' -Force -ErrorAction SilentlyContinue)) {
                    Remove-Item -LiteralPath $tsTmp.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $psLock = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'mise_paths.lock'
            if ((Test-Path -LiteralPath $psLock -PathType Leaf) -and (([DateTime]::UtcNow - (Get-Item -LiteralPath $psLock).LastWriteTimeUtc).TotalMinutes -gt 5)) {
                Remove-Item -LiteralPath $psLock -Force -ErrorAction SilentlyContinue
            }
        }
}

Write-Host '==> System update finished.' -ForegroundColor Green
exit 0
