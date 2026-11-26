# =============================================================
# Native Workstation Utilities, System Updaters & Theme Engine
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'CLI wrapper forwards --dry-run to bin/update-system.ps1')]
param()

# Cryptographically Secure Password Generator (Rejection-sampled RandomNumberGenerator)
function gen-passwd {
    $scriptPath = Resolve-WsBinScript 'gen-passwd'
    if ($scriptPath) {
        & $scriptPath @args
    } else {
        Write-Error "Error: bin/gen-passwd.ps1 was not found."
    }
}

# Repeat Command Until Success (Exit Code 0)
function repeat-until-success {
    $scriptPath = Resolve-WsBinScript 'repeat-until-success'
    if ($scriptPath) {
        & $scriptPath @args
    } else {
        Write-Error "Error: bin/repeat-until-success.ps1 was not found."
    }
}

# Numeric & IEC Human-Unit Pipeline Accumulator (1..10 | sum = 55; sum -H, -d, -k, -a, -s, -f)
function sum {
    $scriptPath = Resolve-WsBinScript 'sum'
    if (-not $scriptPath) {
        Write-Error "Error: bin/sum.ps1 was not found."
        return
    }
    if ($MyInvocation.ExpectingInput) {
        $input | & $scriptPath @args
    } else {
        & $scriptPath @args
    }
}

# Disk Space Tree Analyzer (`ds` = dust, matching home-settings)
function ds {
    $dustCmd = Get-Command dust -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($dustCmd) {
        & $dustCmd.Source @args
    } else {
        Write-Warning "dust is not installed (install via 'winget install bootandy.dust' or 'mise install dust')."
    }
}

# Interactive System Monitor (`btop` = btop4win on Windows)
function btop {
    if ($env:LOCALAPPDATA) {
        $wingetPkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path -LiteralPath $wingetPkgs -PathType Container) {
            $b4wDirs = @(Get-ChildItem -LiteralPath $wingetPkgs -Directory -Filter 'aristocratos.btop4win*' -ErrorAction SilentlyContinue)
            foreach ($d in $b4wDirs) {
                $hit = Get-ChildItem -LiteralPath $d.FullName -Filter 'btop4win.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hit) {
                    Push-Location -LiteralPath $hit.DirectoryName
                    try {
                        & $hit.FullName @args
                    } finally {
                        Pop-Location
                    }
                    return
                }
            }
        }
    }
    foreach ($binName in @('btop4win.exe', 'btop4win', 'btop.exe')) {
        $btopCmd = Get-Command $binName -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($btopCmd) {
            & $btopCmd.Source @args
            return
        }
    }
    Write-Warning "btop4win is not installed (install via 'winget install aristocratos.btop4win')."
}

# Unified Workstation Updater (`update` / `update-system`)
function update-system {
    $scriptPath = Resolve-WsBinScript 'update-system'
    if (-not $scriptPath) {
        Write-Error "Error: bin/update-system.ps1 was not found."
        return
    }
    $global:LASTEXITCODE = 0
    & $scriptPath @args
    $rc = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    if ($rc -eq 0) {
        $isReadOnly = $false
        foreach ($a in $args) {
            if ("$a" -in @('-n', '--dry-run', '-DryRun', '-h', '--help', '-Help', '-?')) {
                $isReadOnly = $true
                break
            }
        }
        if (-not $isReadOnly) {
            $miseCachePs1 = Join-Path $HOME '.cache\powershell\mise_paths.ps1'
            if ([System.IO.File]::Exists($miseCachePs1)) {
                . $miseCachePs1
                $script:_wsPathDirs = $env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
            }
            if ($null -ne ${function:Sync-OhMyPoshPromptCache}) {
                Sync-OhMyPoshPromptCache
            }
        }
    }
}

function update {
    update-system @args
}

# Multi-Theme Engine Shell Wrapper (Applies live env, PSReadLine & Oh My Posh colors in current shell)
function theme {
    $scriptPath = Resolve-WsBinScript 'theme'
    if (-not $scriptPath) {
        Write-Error "Error: bin/theme.ps1 was not found."
        return
    }

    $prevWrapper = $env:THEME_SHELL_WRAPPER
    $env:THEME_SHELL_WRAPPER = '1'
    try {
        $global:LASTEXITCODE = 0
        & $scriptPath @args
        $rc = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    } finally {
        $env:THEME_SHELL_WRAPPER = $prevWrapper
    }

    if ($rc -eq 0) {
        $isReadOnly = $false
        foreach ($a in $args) {
            if ("$a" -in @('-l', '--list', '-c', '--current', '-p', '--preview', '--env', '--path', '--check-assets', '--sync-assets', '--create', '-n', '--dry-run', '-h', '--help', '--plain') -or
                "$a" -match '^--(preview|env|create|dry-run)=') {
                $isReadOnly = $true
                break
            }
        }
        if (-not $isReadOnly) {
            $themeEnvPs1 = Join-Path $HOME '.cache\powershell\theme_env.ps1'
            if ([System.IO.File]::Exists($themeEnvPs1)) {
                . $themeEnvPs1
            }
            if (Get-Command Sync-PSReadLineThemePalette -ErrorAction SilentlyContinue) {
                Sync-PSReadLineThemePalette
            }
            if (Get-Command Sync-OhMyPoshPromptCache -ErrorAction SilentlyContinue) {
                Sync-OhMyPoshPromptCache
            } else {
                $ompCfg = Join-Path $HOME '.poshthemes\p10k_single_line.omp.json'
                if ([System.IO.File]::Exists($ompCfg)) { $env:POSH_CONFIG = $ompCfg }
                $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
            }
        }
    }
}
