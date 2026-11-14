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
            -PreviewText 'mise plugins update && mise upgrade && mise prune -y' `
            -Action {
                & mise plugins update
                & mise upgrade
                & mise prune -y
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
