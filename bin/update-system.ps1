<#
.SYNOPSIS
    Unified Windows system and developer toolchain updater.
.DESCRIPTION
    Windows-native counterpart to home-settings/bin/update-system.
    Updates WinGet packages, PowerShell modules, Mise runtimes, and (with --with-dev / --all)
    Rustup, Elan, Neovim Lazy plugins, Tealdeer tldr pages, bat cache, and compiled shell caches.
#>

$ErrorActionPreference = 'Stop'

$script:UsageText = @"
Usage: update-system [OPTIONS]

Update Windows system packages and developer toolchains.

Options:
  --system-only, -SystemOnly   Update WinGet system packages only (skip Mise & dev toolchains)
  --with-dev, --all, -All      Also update Rustup, Elan, Neovim plugins, tldr cache, and shell caches
  -n, --dry-run, -DryRun       Preview update commands without executing changes
  -h, --help, -Help            Show this help message and exit
"@

$dryRun = $false
$systemOnly = $false
$withDev = $false

:ArgLoop foreach ($rawArg in $args) {
    $arg = [string]$rawArg
    switch -Regex ($arg) {
        '^(-h|--help|-Help|-\?)$' {
            Write-Output $script:UsageText
            exit 0
        }
        '^(-n|--dry-run|-DryRun)$' {
            $dryRun = $true
            continue ArgLoop
        }
        '^(--system-only|-SystemOnly)$' {
            $systemOnly = $true
            continue ArgLoop
        }
        '^(--with-dev|--all|-All|-WithDev)$' {
            $withDev = $true
            continue ArgLoop
        }
        default {
            [Console]::Error.WriteLine("update-system: unknown option '$arg' (try 'update-system --help')")
            exit 1
        }
    }
}

function Invoke-UpdateStep([string]$Title, [string]$PreviewText, [scriptblock]$Action) {
    Write-Host "==> $Title" -ForegroundColor Cyan
    if ($dryRun) {
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
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Invoke-UpdateStep -Title 'WinGet Package Upgrades' `
        -PreviewText 'winget upgrade --all --accept-source-agreements --accept-package-agreements' `
        -Action {
            & winget upgrade --all --accept-source-agreements --accept-package-agreements
        }
} else {
    Write-Warning 'winget not found in PATH; skipping WinGet package upgrades.'
}

if (-not $systemOnly) {
    # 2. Mise Developer Runtimes & CLI Tools
    if (Get-Command mise -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Mise Toolchain & CLI Upgrades' `
            -PreviewText 'mise plugins update && mise upgrade && mise prune -y && refresh mise_paths cache' `
            -Action {
                & mise plugins update
                & mise upgrade
                & mise prune -y
                $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
                $rawPaths = @(& mise bin-paths 2>$null)
                $cleanDirs = [System.Collections.Generic.List[string]]::new()
                foreach ($rp in $rawPaths) {
                    if (-not $rp -or -not "$rp".Trim()) { continue }
                    $norm = "$rp".Trim().Replace('/', '\').TrimEnd('\')
                    if ([System.IO.Directory]::Exists($norm) -and -not $cleanDirs.Contains($norm)) {
                        $cleanDirs.Add($norm)
                    }
                }
                if ($cleanDirs.Count -gt 0) {
                    $marker = $cleanDirs[0]
                    $joined = ($cleanDirs -join ';')
                    $psCacheFile = Join-Path (Join-Path $userHome '.cache') 'powershell\mise_paths.ps1'
                    $psParent = Split-Path -Parent $psCacheFile
                    if (-not [System.IO.Directory]::Exists($psParent)) {
                        New-Item -ItemType Directory -Force -Path $psParent | Out-Null
                    }
                    $psLines = @(
                        "`$script:_wsMiseMarker = '$($marker.Replace("'", "''"))'",
                        "`$script:_wsMisePathBlock = '$($joined.Replace("'", "''"))'",
                        'if ([System.IO.Directory]::Exists($script:_wsMiseMarker) -and -not $env:Path.Contains($script:_wsMiseMarker, [System.StringComparison]::OrdinalIgnoreCase)) {',
                        '    $env:Path = "$script:_wsMisePathBlock;$env:Path"',
                        '}'
                    )
                    [System.IO.File]::WriteAllText($psCacheFile, ($psLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
                    if ($env:LOCALAPPDATA) {
                        $cmdCacheFile = Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'mise_paths.cmd'
                        $cmdParent = Split-Path -Parent $cmdCacheFile
                        if (-not [System.IO.Directory]::Exists($cmdParent)) {
                            New-Item -ItemType Directory -Force -Path $cmdParent | Out-Null
                        }
                        $cmdLines = @(
                            "@if not exist `"$marker`" exit /b 0",
                            "@call :ws_mise_has `"$marker`"",
                            "@if errorlevel 1 set `"PATH=$joined;%PATH%`"",
                            '@exit /b 0',
                            ':ws_mise_has',
                            '@setlocal EnableDelayedExpansion',
                            '@set "_P=;!PATH!;"',
                            '@set "_T=!_P:*;%~1;=FOUND!"',
                            '@if "!_T:~0,5!"=="FOUND" (endlocal & exit /b 0)',
                            '@endlocal & exit /b 1'
                        )
                        [System.IO.File]::WriteAllText($cmdCacheFile, ($cmdLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
                    }
                }
            }
    }

    # 3. PowerShell Installed Modules
    if (Get-Command Update-Module -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'PowerShell Gallery Modules' `
            -PreviewText 'Update-Module -ErrorAction SilentlyContinue' `
            -Action {
                Update-Module -ErrorAction SilentlyContinue
            }
    }
}

if ($withDev -and -not $systemOnly) {
    if (Get-Command rustup -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Rust Toolchain (rustup)' -PreviewText 'rustup update' -Action {
            & rustup update
        }
    }
    if (Get-Command elan -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Lean 4 Toolchain (elan)' -PreviewText 'elan update' -Action {
            & elan update
        }
    }
    if (Get-Command tldr -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Tealdeer tldr Page Cache' -PreviewText 'tldr --update' -Action {
            & tldr --update
        }
    }
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'bat Theme & Syntax Cache' -PreviewText 'bat cache --build' -Action {
            & bat cache --build
        }
    }
    if (Get-Command nvim -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Neovim Lazy.nvim Plugins' -PreviewText 'nvim --headless "+Lazy! sync" +qa' -Action {
            & nvim --headless '+Lazy! sync' '+qa'
        }
    }

    Invoke-UpdateStep -Title 'Compiled PowerShell Startup Caches' `
        -PreviewText 'Regenerate omp_init.ps1, zoxide_init.ps1, and gh_completion.ps1' `
        -Action {
            $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
            $psCacheDir = Join-Path (Join-Path $userHome '.cache') 'powershell'
            New-Item -ItemType Directory -Force -Path $psCacheDir | Out-Null
            $ompTheme = Join-Path (Join-Path $userHome '.poshthemes') 'p10k_single_line.omp.json'
            if ((Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $ompTheme)) {
                oh-my-posh init pwsh --config $ompTheme --print | Out-File -FilePath (Join-Path $psCacheDir 'omp_init.ps1') -Encoding utf8 -Force
            }
            if (Get-Command zoxide -ErrorAction SilentlyContinue) {
                zoxide init powershell | Out-File -FilePath (Join-Path $psCacheDir 'zoxide_init.ps1') -Encoding utf8 -Force
            }
            if (Get-Command gh -ErrorAction SilentlyContinue) {
                gh completion -s powershell | Out-File -FilePath (Join-Path $psCacheDir 'gh_completion.ps1') -Encoding utf8 -Force
            }
            $scriptDir = Split-Path -Parent $PSCommandPath
            $themeScript = Join-Path $scriptDir 'theme.ps1'
            if (Test-Path -LiteralPath $themeScript) {
                & $themeScript --sync-assets *> $null
            }
        }
}

Write-Host '==> System update finished.' -ForegroundColor Green
