# =============================================================
# setup/modules/99-Uninstall.ps1 - Modular Workstation Uninstall
# =============================================================
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot,
    [string[]]$Targets = @('all'),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupBanner -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Sync-ZellijPluginPermission -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}
if (-not (Get-Command Remove-UserPathEntry -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Env.ps1')
}

$doDotfiles = $false
$doFonts = $false
$doBin = $false

foreach ($rawTok in $Targets) {
    foreach ($tok in ("$rawTok" -split ',')) {
        $cleanTok = $tok.Trim().ToLowerInvariant()
        if (-not $cleanTok) { continue }
        switch ($cleanTok) {
            'all'      { $doDotfiles = $true; $doFonts = $true; $doBin = $true }
            'dotfiles' { $doDotfiles = $true }
            'fonts'    { $doFonts = $true }
            'bin'      { $doBin = $true }
            default {
                [Console]::Error.WriteLine("Error: Unknown uninstall target '$cleanTok' (expected: all, dotfiles, fonts, or bin)")
                exit 1
            }
        }
    }
}

Write-SetupBanner -Title 'Windows Settings Uninstall Workflow' -DryRun:$DryRun
$userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }

if ($doDotfiles) {
    Write-SetupStage -Stage 'Dotfiles' -Message 'Removing deployed dotfiles, module, fragments, and shell hooks...'

    # 1. PowerShell Module
    $moduleDest = Join-Path (Join-Path (Join-Path (Join-Path $userHome 'Documents') 'PowerShell') 'Modules') 'WindowsSettings'
    if (Test-Path -LiteralPath $moduleDest) {
        if ($DryRun) {
            Write-SetupDryRun "Would remove PowerShell module directory $moduleDest"
        } else {
            Remove-Item -Recurse -Force -LiteralPath $moduleDest -ErrorAction SilentlyContinue
            Write-Host "  Removed $moduleDest" -ForegroundColor Green
        }
    }

    # 2. PowerShell $PROFILE (non-destructive backup before stripping Import-Module line)
    if ($PROFILE -and (Test-Path -LiteralPath $PROFILE -PathType Leaf)) {
        $profRaw = [System.IO.File]::ReadAllText($PROFILE, [System.Text.Encoding]::UTF8)
        if ($profRaw -match 'WindowsSettings') {
            $profBackup = Get-TimestampedBackupPath $PROFILE
            if ($DryRun) {
                Write-SetupDryRun "Would backup $PROFILE to $profBackup and remove WindowsSettings import"
            } else {
                Copy-Item -LiteralPath $PROFILE -Destination $profBackup -Force
                $cleaned = [regex]::Replace($profRaw, '(?m)^\s*#\s*=+\r?\n\s*#\s*PowerShell Profile - windows-settings\r?\n\s*#\s*=+\r?\n?', '')
                $cleaned = [regex]::Replace($cleaned, '(?m)^\s*Import-Module\s+WindowsSettings[^\r\n]*\r?\n?', '').Trim()
                if ($cleaned) {
                    Write-CacheFileCrlf -Path $PROFILE -Content $cleaned
                } else {
                    Remove-Item -Force -LiteralPath $PROFILE -ErrorAction SilentlyContinue
                }
                Write-Host "  Cleaned WindowsSettings import from $PROFILE (backup: $profBackup)" -ForegroundColor Green
            }
        }
    }

    # 3. Windows Terminal Fragments
    if ($env:LOCALAPPDATA) {
        $fragDirs = @(
            (Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'Windows Terminal') 'Fragments\WindowsSettings'),
            (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') 'Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings'),
            (Join-Path (Join-Path $env:LOCALAPPDATA 'Packages') 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings')
        )
        foreach ($fd in $fragDirs) {
            if (Test-Path -LiteralPath $fd) {
                if ($DryRun) {
                    Write-SetupDryRun "Would remove Windows Terminal fragment directory $fd"
                } else {
                    Remove-Item -Recurse -Force -LiteralPath $fd -ErrorAction SilentlyContinue
                    Write-Host "  Removed $fd" -ForegroundColor Green
                }
            }
        }
    }

    # 4. CMD AutoRun & Registry Hook
    $cmdFiles = @(
        (Join-Path (Join-Path (Join-Path $userHome '.config') 'cmd') 'autorun.cmd'),
        (Join-Path (Join-Path (Join-Path $userHome '.config') 'cmd') 'macros.doskey')
    )
    if ($env:LOCALAPPDATA) {
        $localCmdDir = Join-Path $env:LOCALAPPDATA 'cmd'
        $cmdFiles += @(
            (Join-Path $localCmdDir 'autorun.cmd'),
            (Join-Path $localCmdDir 'macros.doskey'),
            (Join-Path $localCmdDir 'mise_paths.cmd'),
            (Join-Path $localCmdDir 'theme_env.cmd')
        )
    }
    foreach ($cf in $cmdFiles) {
        if (Test-Path -LiteralPath $cf) {
            if ($DryRun) {
                Write-SetupDryRun "Would remove CMD AutoRun file $cf"
            } else {
                Remove-Item -Force -LiteralPath $cf -ErrorAction SilentlyContinue
            }
        }
    }
    $cmdProcessorKey = 'HKCU:\Software\Microsoft\Command Processor'
    if (Test-Path -LiteralPath $cmdProcessorKey) {
        $apProp = Get-ItemProperty -Path $cmdProcessorKey -Name 'AutoRun' -ErrorAction SilentlyContinue
        if ($apProp -and $apProp.AutoRun -like '*autorun.cmd*') {
            if ($DryRun) {
                Write-SetupDryRun "Would remove autorun.cmd hook from $cmdProcessorKey\AutoRun"
            } else {
                $autoRunTarget = 'if exist "%LOCALAPPDATA%\cmd\autorun.cmd" call "%LOCALAPPDATA%\cmd\autorun.cmd"'
                $updatedAr = $apProp.AutoRun.Replace(" & $autoRunTarget", '').Replace($autoRunTarget, '').Trim()
                if ($updatedAr) {
                    Set-ItemProperty -Path $cmdProcessorKey -Name 'AutoRun' -Value $updatedAr -Type ExpandString -Force
                } else {
                    Remove-ItemProperty -Path $cmdProcessorKey -Name 'AutoRun' -ErrorAction SilentlyContinue
                }
                Write-Host '  Removed autorun.cmd hook from registry' -ForegroundColor Green
            }
        }
    }

    # 5. State & Compiled Caches
    $psCacheDir = Join-Path (Join-Path $userHome '.cache') 'powershell'
    foreach ($cacheTarget in @(
        (Join-Path (Join-Path $userHome '.config') 'windows-settings'),
        (Join-Path (Join-Path $userHome '.cache') 'windows-settings'),
        (Join-Path $psCacheDir 'omp_init.ps1'),
        (Join-Path $psCacheDir 'theme_env.ps1'),
        (Join-Path $psCacheDir 'mise_paths.ps1'),
        (Join-Path $psCacheDir 'zoxide_init.ps1'),
        (Join-Path $psCacheDir 'gh_completion.ps1'),
        (Join-Path $psCacheDir 'completions_cache.ps1'),
        (Join-Path $psCacheDir 'completions')
    )) {
        if (Test-Path -LiteralPath $cacheTarget) {
            if ($DryRun) {
                Write-SetupDryRun "Would remove $cacheTarget"
            } else {
                Remove-Item -Recurse -Force -LiteralPath $cacheTarget -ErrorAction SilentlyContinue
            }
        }
    }

    # 6. Git Delta include.path cleanup
    $gitCmd = Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $gitCmd) {
        $deltaInclude = '~/.config/windows-settings/delta-theme.gitconfig'
        $existingIncludes = @(& $gitCmd.Source config --global --get-all include.path 2>$null)
        if ($existingIncludes -contains $deltaInclude) {
            if ($DryRun) {
                Write-SetupDryRun "Would remove git global include.path $deltaInclude"
            } else {
                & $gitCmd.Source config --global --unset-all include.path "^$([regex]::Escape($deltaInclude))$" 2>$null
            }
        }
    }

    # 7. Zellij Config, Layouts, Theme, WASM Bar & Permissions
    if ($env:APPDATA) {
        $zellijCfgRoot = Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
        foreach ($zf in @(
            (Join-Path $zellijCfgRoot 'config.kdl'),
            (Join-Path (Join-Path $zellijCfgRoot 'layouts') 'ide-3pane.kdl'),
            (Join-Path (Join-Path $zellijCfgRoot 'layouts') 'ide-2pane.kdl'),
            (Join-Path (Join-Path $zellijCfgRoot 'themes') 'windows-settings.kdl'),
            (Join-Path (Get-ZellijPluginDir) 'windows-settings-bar.wasm')
        )) {
            if (Test-Path -LiteralPath $zf) {
                if ($DryRun) {
                    Write-SetupDryRun "Would remove Zellij file $zf"
                } else {
                    Remove-Item -Force -LiteralPath $zf -ErrorAction SilentlyContinue
                    Write-Host "  Removed $zf" -ForegroundColor Green
                }
            }
        }
    }
    Sync-ZellijPluginPermission -Remove -DryRun:$DryRun

    # 8. AI CLI Lifecycle Hooks (agy, claude, codex)
    $aiHooksModule = Join-Path $PSScriptRoot '75-AiHooks.ps1'
    if (Test-Path -LiteralPath $aiHooksModule -PathType Leaf) {
        & $aiHooksModule -RepoRoot $RepoRoot -Remove -DryRun:$DryRun
    }
}

if ($doFonts) {
    Write-SetupStage -Stage 'Fonts' -Message 'Removing MesloLGS Nerd Font Mono files and registry entries...'
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $fontsDir = if ($isAdmin) { Join-Path $env:SystemRoot 'Fonts' } else { Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'Microsoft') 'Windows') 'Fonts' }
    $regKey = if ($isAdmin) { 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' } else { 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts' }
    $monoFonts = @(
        @{ File = 'MesloLGSNerdFontMono-Regular.ttf';    RegName = 'MesloLGS Nerd Font Mono Regular (TrueType)' },
        @{ File = 'MesloLGSNerdFontMono-Bold.ttf';       RegName = 'MesloLGS Nerd Font Mono Bold (TrueType)' },
        @{ File = 'MesloLGSNerdFontMono-Italic.ttf';     RegName = 'MesloLGS Nerd Font Mono Italic (TrueType)' },
        @{ File = 'MesloLGSNerdFontMono-BoldItalic.ttf'; RegName = 'MesloLGS Nerd Font Mono Bold Italic (TrueType)' }
    )
    foreach ($mf in $monoFonts) {
        $fp = Join-Path $fontsDir $mf.File
        if ($DryRun) {
            Write-SetupDryRun "Would unregister $($mf.RegName) and remove $fp"
        } else {
            if (Test-Path -LiteralPath $regKey) {
                Remove-ItemProperty -Path $regKey -Name $mf.RegName -ErrorAction SilentlyContinue
            }
            if (Test-Path -LiteralPath $fp) {
                Remove-Item -Force -LiteralPath $fp -ErrorAction SilentlyContinue
            }
        }
    }
}

if ($doBin) {
    $binDir = Join-Path $RepoRoot 'bin'
    Write-SetupStage -Stage 'Bin' -Message "Removing $binDir from User PATH..."
    Remove-UserPathEntry -Directory $binDir -DryRun:$DryRun
}

Write-SetupFooter -SuccessMessage 'Uninstall workflow completed successfully!' `
    -DryRunMessage 'Uninstall dry run complete! No changes were made.' `
    -DryRun:$DryRun
