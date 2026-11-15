<#
.SYNOPSIS
    Unified Windows system and developer toolchain updater.
.DESCRIPTION
    Windows-native counterpart to home-settings/bin/update-system.
    Updates WinGet packages, Mise runtimes and direct PATH caches, PowerShell modules,
    Rustup, Elan, Neovim Lazy.nvim plugins, Tealdeer tldr pages, bat binary cache,
    and compiled shell and IDE startup caches in a single run.
#>

$ErrorActionPreference = 'Stop'

$script:UsageText = @"
Usage: update-system [OPTIONS]

Update Windows packages, Mise runtimes, PowerShell modules, toolchains, Neovim plugins, and caches.

Options:
  --system-only, -SystemOnly     Update WinGet system packages only
  --skip-winget, -SkipWinget     Skip WinGet package upgrades
  --skip-mise, -SkipMise         Skip Mise runtime and CLI upgrades
  --skip-modules, -SkipModules   Skip PowerShell Gallery module updates
  --skip-nvim, -SkipNvim         Skip Neovim Lazy.nvim plugin sync
  -n, --dry-run, -DryRun         Preview update commands without executing changes
  -h, --help, -Help              Show this help message and exit
"@

$dryRun = $false
$systemOnly = $false
$skipWinget = $false
$skipMise = $false
$skipModules = $false
$skipNvim = $false

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
        '^(--skip-winget|-SkipWinget)$' {
            $skipWinget = $true
            continue ArgLoop
        }
        '^(--skip-mise|-SkipMise)$' {
            $skipMise = $true
            continue ArgLoop
        }
        '^(--skip-modules|-SkipModules)$' {
            $skipModules = $true
            continue ArgLoop
        }
        '^(--skip-nvim|-SkipNvim)$' {
            $skipNvim = $true
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
if (-not $skipWinget) {
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'WinGet Package Upgrades' `
            -PreviewText 'winget upgrade --all --accept-source-agreements --accept-package-agreements' `
            -Action {
                & winget upgrade --all --accept-source-agreements --accept-package-agreements
            }
    } else {
        Write-Warning 'winget not found in PATH; skipping WinGet package upgrades.'
    }
}

if (-not $systemOnly) {
    # 2. Mise Developer Runtimes & CLI Tools (+ direct PATH cache refresh before downstream steps)
    if (-not $skipMise -and (Get-Command mise -ErrorAction SilentlyContinue)) {
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
                    $installsRoot = if ($env:LOCALAPPDATA) {
                        Join-Path $env:LOCALAPPDATA 'mise\installs'
                    } else {
                        Split-Path -Parent (Split-Path -Parent $cleanDirs[0])
                    }
                    $joined = ($cleanDirs -join ';')
                    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($joined.ToLowerInvariant()))
                    $stamp = [System.BitConverter]::ToString($hashBytes, 0, 4).Replace('-', '')
                    $psCacheFile = Join-Path (Join-Path $userHome '.cache') 'powershell\mise_paths.ps1'
                    $psParent = Split-Path -Parent $psCacheFile
                    if (-not [System.IO.Directory]::Exists($psParent)) {
                        New-Item -ItemType Directory -Force -Path $psParent | Out-Null
                    }
                    $psLines = @(
                        "`$script:_wsMiseInstallsDir = '$($installsRoot.Replace("'", "''"))'",
                        "`$script:_wsMiseStamp = '$stamp'",
                        "`$script:_wsMisePathBlock = '$($joined.Replace("'", "''"))'",
                        'if ([System.IO.Directory]::Exists($script:_wsMiseInstallsDir)) {',
                        '    if (-not $env:Path.Contains($script:_wsMisePathBlock, [System.StringComparison]::OrdinalIgnoreCase)) {',
                        '        $cleanSegs = foreach ($seg in $env:Path.Split('';'', [System.StringSplitOptions]::RemoveEmptyEntries)) {',
                        '            if ($seg.IndexOf(''\mise\installs\'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and',
                        '                $seg.IndexOf(''/mise/installs/'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {',
                        '                $seg',
                        '            }',
                        '        }',
                        '        $restPath = $cleanSegs -join '';''',
                        '        $env:Path = if ($restPath) { "$script:_wsMisePathBlock;$restPath" } else { $script:_wsMisePathBlock }',
                        '    }',
                        '    $env:_WS_MISE_STAMP = $script:_wsMiseStamp',
                        '}'
                    )
                    [System.IO.File]::WriteAllText($psCacheFile, ($psLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
                    . $psCacheFile
                    if ($env:LOCALAPPDATA) {
                        $cmdCacheFile = Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'mise_paths.cmd'
                        $cmdParent = Split-Path -Parent $cmdCacheFile
                        if (-not [System.IO.Directory]::Exists($cmdParent)) {
                            New-Item -ItemType Directory -Force -Path $cmdParent | Out-Null
                        }
                        $cmdLines = @(
                            "@if not exist `"$installsRoot`" exit /b 0",
                            "@if /i `"%_WS_MISE_STAMP%`"==`"$stamp`" exit /b 0",
                            "@set `"_WS_MISE_STAMP=$stamp`"",
                            "@set `"PATH=$joined;%PATH%`"",
                            '@exit /b 0'
                        )
                        [System.IO.File]::WriteAllText($cmdCacheFile, ($cmdLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
                    }
                }
            }
    }

    # 3. PowerShell Installed Modules
    if (-not $skipModules -and (Get-Command Update-Module -ErrorAction SilentlyContinue)) {
        Invoke-UpdateStep -Title 'PowerShell Gallery Modules' `
            -PreviewText 'Update-Module -ErrorAction SilentlyContinue' `
            -Action {
                Update-Module -ErrorAction SilentlyContinue
            }
    }

    # 4. Rust & Lean 4 Toolchains
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

    # 5. Neovim Lazy.nvim Plugins
    if (-not $skipNvim -and (Get-Command nvim -ErrorAction SilentlyContinue)) {
        Invoke-UpdateStep -Title 'Neovim Lazy.nvim Plugins' -PreviewText 'nvim --headless "+Lazy! sync" +qa' -Action {
            & nvim --headless '+Lazy! sync' '+qa'
        }
    }

    # 6. Tealdeer tldr Page Cache
    if (Get-Command tldr -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'Tealdeer tldr Page Cache' -PreviewText 'tldr --update' -Action {
            & tldr --update
        }
    }

    # 7. Active Theme Deployment & bat Binary Syntax/Theme Cache
    $scriptDir = Split-Path -Parent $PSCommandPath
    $themeScript = Join-Path $scriptDir 'theme.ps1'
    if (Get-Command bat -ErrorAction SilentlyContinue) {
        Invoke-UpdateStep -Title 'bat Theme & Syntax Cache' -PreviewText 'theme --set <active> --no-live && bat cache --build' -Action {
            if (Test-Path -LiteralPath $themeScript) {
                $activeSlug = (& $themeScript --current).Trim()
                if (-not $activeSlug) { $activeSlug = 'solarized-dark' }
                & $themeScript --set $activeSlug --no-live *> $null
            }
            & bat cache --build
        }
    }

    # 8. Compiled Shell & IDE Startup Caches
    Invoke-UpdateStep -Title 'Compiled Shell & IDE Startup Caches' `
        -PreviewText 'Regenerate omp_init.ps1, zoxide_init.ps1, gh_completion.ps1, and IDE modal caches' `
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
            $ideScript = Join-Path $scriptDir 'ide.ps1'
            if (Test-Path -LiteralPath $ideScript) {
                & $ideScript --write-keys-cache *> $null
            }
        }
}

Write-Host '==> System update finished.' -ForegroundColor Green
