<#
.SYNOPSIS
    Master setup engine for windows-settings.
    Automates package provisioning, fonts, 17-theme palette engine, Oh My Posh prompt,
    WindowsSettings module, CLI completions, utility PATH, Neovim/Vim, CLI tool configs,
    Windows Terminal fragments, and modular uninstallation.

.DESCRIPTION
    Execution Modes:
      -Bootstrap             Full new machine bootstrap (winget packages, fonts, themes, oh-my-posh, module, terminal, nvim)
      -DotfilesOnly          Configure user dotfiles, fonts, themes, nvim, terminal, and shell module only (no package install)
      -SystemOnly            Provision winget packages and CLI tools only
      -UseDSC                Provision workstation packages using declarative WinGet DSC v3 manifest (configuration.dsc.yaml)
      -Theme <slug|holiday>  Apply initial color theme (default: existing user theme or 'solarized-dark'; supports 'holiday')
      -DryRun                Preview actions without modifying the system

    Uninstall Modes:
      -Uninstall             Cleanly remove deployed windows-settings dotfiles, module, fragments, fonts, and bin PATH entry
      -UninstallDotfiles     Remove deployed dotfiles, PowerShell module, CMD AutoRun, and Windows Terminal fragment only
      -UninstallFonts        Remove installed MesloLGS Nerd Font Mono files and registry entries only
      -UninstallBin          Remove repository bin/ directory from User PATH only

    GUI Options:
      -WithGUI, -IncludeGUI  Install GUI desktop applications (VS Code, Windows Terminal, Docker Desktop via winget)

    Granular Skip Flags:
      -SkipPackages          Skip winget package installation
      -SkipFonts             Skip MesloLGS Nerd Font Mono installation
      -SkipPosh              Skip Oh My Posh, Theme Engine & PowerShell module configuration
      -SkipCMD               Skip Windows Command Prompt (cmd.exe) AutoRun & Doskey configuration
      -SkipCompletions       Skip CLI argument completions registration
      -SkipTerminal          Skip Windows Terminal settings & JSON fragment deployment
      -SkipVim               Skip Neovim & Vim configuration
      -SkipBin               Skip adding bin/ directory to User PATH
#>
[CmdletBinding()]
param(
    [switch]$Bootstrap,
    [switch]$DotfilesOnly,
    [switch]$SystemOnly,
    [switch]$UseDSC,
    [switch]$DryRun,
    [switch]$WithGUI,
    [switch]$IncludeGUI,
    [switch]$InstallPackages,
    [string]$Theme = '',
    [switch]$Uninstall,
    [switch]$UninstallDotfiles,
    [switch]$UninstallFonts,
    [switch]$UninstallBin,
    [switch]$SkipPackages,
    [switch]$SkipFonts,
    [switch]$SkipTerminal,
    [switch]$SkipPosh,
    [switch]$SkipCMD,
    [switch]$SkipCompletions,
    [switch]$SkipVim,
    [switch]$SkipBin
)

$ErrorActionPreference = 'Stop'
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# -------------------------------------------------------------
# Reusable Declarative Deployment Function
# -------------------------------------------------------------
function Deploy-ConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath,
        [string[]]$AltDestinations = @(),
        [switch]$DryRun
    )

    if (-not (Test-Path $SourcePath)) { return }
    $sourceContent = Get-Content $SourcePath -Raw

    $allDests = @($DestinationPath) + $AltDestinations
    foreach ($dest in $allDests) {
        if (-not $dest) { continue }
        $destDir = Split-Path -Parent $dest
        if ($destDir -and -not (Test-Path $destDir)) {
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
        }

        if (Test-Path $dest) {
            $existingContent = Get-Content $dest -Raw
            $existingTrimmed = if ($null -ne $existingContent) { $existingContent.Trim() } else { '' }
            $isDiff = ($existingTrimmed -ne $sourceContent.Trim())

            if ($isDiff) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $backup = "$dest.bak_$timestamp"
                if ($DryRun) {
                    Write-Host "  [DryRun] Would backup $dest to $backup" -ForegroundColor DarkCyan
                    Write-Host "  [DryRun] Would update $Name at $dest" -ForegroundColor DarkCyan
                } else {
                    Write-Host "Backing up existing config to $backup..." -ForegroundColor Yellow
                    Copy-Item -Path $dest -Destination $backup -Force
                    Copy-Item -Path $SourcePath -Destination $dest -Force
                    Write-Host "==> $Name updated at $dest" -ForegroundColor Green
                }
            } else {
                Write-Host "==> $Name at $dest is already up to date." -ForegroundColor Green
            }
        } else {
            if ($DryRun) {
                Write-Host "  [DryRun] Would deploy $Name to $dest" -ForegroundColor DarkCyan
            } else {
                Copy-Item -Path $SourcePath -Destination $dest -Force
                Write-Host "==> $Name deployed to $dest" -ForegroundColor Green
            }
        }
    }
}

function ConvertTo-NormalizedZellijConfig([string]$Content) {
    if (-not $Content) { return '' }
    $norm = $Content.Replace("`r`n", "`n")
    $norm = [regex]::Replace($norm, '(?s)// BEGIN WINDOWS-SETTINGS TRAY COLORS.*?// END WINDOWS-SETTINGS TRAY COLORS', '// __WS_TRAY__')
    $norm = [regex]::Replace($norm, '(?s)// BEGIN WINDOWS-SETTINGS TERMINAL THEME.*?// END WINDOWS-SETTINGS TERMINAL THEME', '// __WS_TERM__')
    return $norm.Trim()
}

function Deploy-ZellijConfig([string]$SourcePath, [string]$DestinationPath, [switch]$DryRun) {
    if (-not (Test-Path -LiteralPath $SourcePath)) { return }
    $srcLf = (Get-Content -LiteralPath $SourcePath -Raw).Replace("`r`n", "`n")
    $destDir = Split-Path -Parent $DestinationPath
    if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
        if (-not $DryRun) {
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
        }
    }
    if (Test-Path -LiteralPath $DestinationPath) {
        $existingRaw = Get-Content -LiteralPath $DestinationPath -Raw
        $isSame = ((ConvertTo-NormalizedZellijConfig $existingRaw) -eq (ConvertTo-NormalizedZellijConfig $srcLf))
        if (-not $isSame) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            $backup = "$DestinationPath.bak_$timestamp"
            if ($DryRun) {
                Write-Host "  [DryRun] Would backup $DestinationPath to $backup" -ForegroundColor DarkCyan
                Write-Host "  [DryRun] Would update Zellij configuration at $DestinationPath" -ForegroundColor DarkCyan
            } else {
                Write-Host "Backing up existing Zellij config to $backup..." -ForegroundColor Yellow
                Copy-Item -LiteralPath $DestinationPath -Destination $backup -Force
                [System.IO.File]::WriteAllText($DestinationPath, $srcLf, [System.Text.UTF8Encoding]::new($false))
                Write-Host "==> Zellij configuration updated at $DestinationPath" -ForegroundColor Green
            }
        } else {
            Write-Host "==> Zellij configuration at $DestinationPath is already up to date." -ForegroundColor Green
        }
    } else {
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy Zellij configuration to $DestinationPath" -ForegroundColor DarkCyan
        } else {
            [System.IO.File]::WriteAllText($DestinationPath, $srcLf, [System.Text.UTF8Encoding]::new($false))
            Write-Host "==> Zellij configuration deployed to $DestinationPath" -ForegroundColor Green
        }
    }
}

function Sync-AntigravityHooksJson([switch]$Remove, [switch]$DryRun) {
    $hooksDir = Join-Path (Join-Path $HOME '.gemini') 'config'
    $hooksPath = Join-Path $hooksDir 'hooks.json'
    $hookKey = 'windows-settings-ide'

    $desiredSpec = [ordered]@{
        SessionStart = @(
            [ordered]@{
                type    = 'command'
                command = 'where ide.cmd >nul 2>nul && ide.cmd --agy-hook SessionStart || echo {}'
                timeout = 5
            }
        )
        PreInvocation = @(
            [ordered]@{
                type    = 'command'
                command = 'where ide.cmd >nul 2>nul && ide.cmd --agy-hook PreInvocation || echo {}'
                timeout = 5
            }
        )
        Stop = @(
            [ordered]@{
                type    = 'command'
                command = 'where ide.cmd >nul 2>nul && ide.cmd --agy-hook Stop || echo {"decision":"allow"}'
                timeout = 5
            }
        )
    }

    if ($Remove) {
        if (-not (Test-Path -LiteralPath $hooksPath)) { return }
        try {
            $rootObj = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json -AsHashtable
        } catch {
            return
        }
        if (-not $rootObj -or -not $rootObj.ContainsKey($hookKey)) { return }
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup = "$hooksPath.bak_$timestamp"
        if ($DryRun) {
            Write-Host "  [DryRun] Would backup $hooksPath to $backup and remove '$hookKey' hook" -ForegroundColor DarkCyan
            return
        }
        Copy-Item -LiteralPath $hooksPath -Destination $backup -Force
        [void]$rootObj.Remove($hookKey)
        if ($rootObj.Count -eq 0) {
            Remove-Item -LiteralPath $hooksPath -Force -ErrorAction SilentlyContinue
        } else {
            $jsonOut = ($rootObj | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"
            [System.IO.File]::WriteAllText($hooksPath, $jsonOut, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host "  Removed '$hookKey' from $hooksPath" -ForegroundColor Green
        return
    }

    $existingMap = [ordered]@{}
    $fileExists = Test-Path -LiteralPath $hooksPath
    if ($fileExists) {
        try {
            $parsed = Get-Content -LiteralPath $hooksPath -Raw | ConvertFrom-Json
            if ($parsed) {
                foreach ($prop in $parsed.PSObject.Properties) {
                    $existingMap[$prop.Name] = $prop.Value
                }
            }
        } catch {
            Write-Warning "Skipping $hooksPath hook merge because existing JSON could not be parsed: $_"
            return
        }
    }

    $desiredJsonCompact = ($desiredSpec | ConvertTo-Json -Depth 10 -Compress)
    $currentEntryCompact = if ($existingMap.Contains($hookKey)) {
        ($existingMap[$hookKey] | ConvertTo-Json -Depth 10 -Compress)
    } else {
        ''
    }

    if ($fileExists -and $currentEntryCompact -eq $desiredJsonCompact) {
        Write-Host "==> Antigravity OSC 7501 hook at $hooksPath is already up to date." -ForegroundColor Green
        return
    }

    $existingMap[$hookKey] = $desiredSpec
    $finalJson = ($existingMap | ConvertTo-Json -Depth 10).Replace("`r`n", "`n") + "`n"

    if ($DryRun) {
        if ($fileExists) {
            $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
            Write-Host "  [DryRun] Would backup $hooksPath to $hooksPath.bak_$timestamp" -ForegroundColor DarkCyan
        }
        Write-Host "  [DryRun] Would configure '$hookKey' OSC 7501 hook in $hooksPath" -ForegroundColor DarkCyan
        return
    }

    if (-not (Test-Path -LiteralPath $hooksDir)) {
        New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
    }
    if ($fileExists) {
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $backup = "$hooksPath.bak_$timestamp"
        Copy-Item -LiteralPath $hooksPath -Destination $backup -Force
    }
    [System.IO.File]::WriteAllText($hooksPath, $finalJson, [System.Text.UTF8Encoding]::new($false))
    Write-Host "==> Antigravity OSC 7501 hook configured in $hooksPath" -ForegroundColor Green
}

# -------------------------------------------------------------
# Modular Uninstall Handler (-Uninstall / -UninstallDotfiles / -UninstallFonts / -UninstallBin)
# -------------------------------------------------------------
function Invoke-WorkstationUninstall {
    param(
        [bool]$DoDotfiles,
        [bool]$DoFonts,
        [bool]$DoBin,
        [bool]$IsDryRun
    )

    Write-Host "=====================================================" -ForegroundColor Cyan
    Write-Host "        Windows Settings Uninstall Workflow          " -ForegroundColor Cyan
    if ($IsDryRun) {
        Write-Host "               [DRY RUN PREVIEW MODE]                " -ForegroundColor Magenta
    }
    Write-Host "=====================================================" -ForegroundColor Cyan

    if ($DoDotfiles) {
        Write-Host "`n==> Removing deployed dotfiles, module, fragments, and shell hooks..." -ForegroundColor Yellow

        # 1. PowerShell Module
        $moduleDest = Join-Path $HOME "Documents\PowerShell\Modules\WindowsSettings"
        if (Test-Path $moduleDest) {
            if ($IsDryRun) {
                Write-Host "  [DryRun] Would remove PowerShell module directory $moduleDest" -ForegroundColor DarkCyan
            } else {
                Remove-Item -Recurse -Force -Path $moduleDest -ErrorAction SilentlyContinue
                Write-Host "  Removed $moduleDest" -ForegroundColor Green
            }
        }

        # 2. PowerShell $PROFILE (non-destructive backup before stripping Import-Module line)
        if ($PROFILE -and (Test-Path $PROFILE)) {
            $profRaw = Get-Content $PROFILE -Raw
            if ($profRaw -match 'WindowsSettings') {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                $profBackup = "$PROFILE.bak_$timestamp"
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would backup $PROFILE to $profBackup and remove WindowsSettings import" -ForegroundColor DarkCyan
                } else {
                    Copy-Item -Path $PROFILE -Destination $profBackup -Force
                    $cleaned = [regex]::Replace($profRaw, '(?m)^\s*#\s*=+\r?\n\s*#\s*PowerShell Profile - windows-settings\r?\n\s*#\s*=+\r?\n?', '')
                    $cleaned = [regex]::Replace($cleaned, '(?m)^\s*Import-Module\s+WindowsSettings[^\r\n]*\r?\n?', '').Trim()
                    if ($cleaned) {
                        [System.IO.File]::WriteAllText($PROFILE, ($cleaned + "`n"), [System.Text.Encoding]::UTF8)
                    } else {
                        Remove-Item -Force -Path $PROFILE -ErrorAction SilentlyContinue
                    }
                    Write-Host "  Cleaned WindowsSettings import from $PROFILE (backup: $profBackup)" -ForegroundColor Green
                }
            }
        }

        # 3. Windows Terminal Fragments
        $fragDirs = @()
        if ($env:LOCALAPPDATA) {
            $fragDirs += Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\WindowsSettings"
            $fragDirs += Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings"
            $fragDirs += Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings"
        }
        foreach ($fd in $fragDirs) {
            if (Test-Path $fd) {
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would remove Windows Terminal fragment directory $fd" -ForegroundColor DarkCyan
                } else {
                    Remove-Item -Recurse -Force -Path $fd -ErrorAction SilentlyContinue
                    Write-Host "  Removed $fd" -ForegroundColor Green
                }
            }
        }

        # 4. CMD AutoRun & Registry Hook
        $cmdFiles = @((Join-Path $HOME ".config\cmd\autorun.cmd"))
        if ($env:LOCALAPPDATA) { $cmdFiles += (Join-Path $env:LOCALAPPDATA "cmd\autorun.cmd") }
        foreach ($cf in $cmdFiles) {
            if (Test-Path $cf) {
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would remove CMD AutoRun script $cf" -ForegroundColor DarkCyan
                } else {
                    Remove-Item -Force -Path $cf -ErrorAction SilentlyContinue
                }
            }
        }
        $cmdProcessorKey = "HKCU:\Software\Microsoft\Command Processor"
        if (Test-Path $cmdProcessorKey) {
            $apProp = Get-ItemProperty -Path $cmdProcessorKey -Name "AutoRun" -ErrorAction SilentlyContinue
            if ($apProp -and $apProp.AutoRun -like "*autorun.cmd*") {
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would remove autorun.cmd hook from $cmdProcessorKey\AutoRun" -ForegroundColor DarkCyan
                } else {
                    $autoRunTarget = 'if exist "%LOCALAPPDATA%\cmd\autorun.cmd" call "%LOCALAPPDATA%\cmd\autorun.cmd"'
                    $updatedAr = $apProp.AutoRun.Replace(" & $autoRunTarget", '').Replace($autoRunTarget, '').Trim()
                    if ($updatedAr) {
                        Set-ItemProperty -Path $cmdProcessorKey -Name "AutoRun" -Value $updatedAr -Type ExpandString -Force
                    } else {
                        Remove-ItemProperty -Path $cmdProcessorKey -Name "AutoRun" -ErrorAction SilentlyContinue
                    }
                    Write-Host "  Removed autorun.cmd hook from registry" -ForegroundColor Green
                }
            }
        }

        # 5. State & Compiled Caches
        foreach ($cacheTarget in @(
            (Join-Path $HOME ".config\windows-settings"),
            (Join-Path $HOME ".cache\windows-settings"),
            (Join-Path $HOME ".cache\powershell\omp_init.ps1"),
            (Join-Path $HOME ".cache\powershell\theme_env.ps1"),
            (Join-Path $HOME ".cache\powershell\zoxide_init.ps1"),
            (Join-Path $HOME ".cache\powershell\gh_completion.ps1")
        )) {
            if (Test-Path $cacheTarget) {
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would remove $cacheTarget" -ForegroundColor DarkCyan
                } else {
                    Remove-Item -Recurse -Force -Path $cacheTarget -ErrorAction SilentlyContinue
                }
            }
        }

        # 6. Git Delta include.path cleanup
        if (Get-Command git -ErrorAction SilentlyContinue) {
            $deltaInclude = '~/.config/windows-settings/delta-theme.gitconfig'
            $existingIncludes = @(git config --global --get-all include.path 2>$null)
            if ($existingIncludes -contains $deltaInclude) {
                if ($IsDryRun) {
                    Write-Host "  [DryRun] Would remove git global include.path $deltaInclude" -ForegroundColor DarkCyan
                } else {
                    git config --global --unset-all include.path "^$([regex]::Escape($deltaInclude))$" 2>$null
                }
            }
        }

        # 7. Zellij Config, Layouts, Theme & Antigravity OSC 7501 Hook cleanup
        if ($env:APPDATA) {
            $zellijCfgRoot = Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
            foreach ($zf in @(
                (Join-Path $zellijCfgRoot 'config.kdl'),
                (Join-Path (Join-Path $zellijCfgRoot 'layouts') 'ide-3pane.kdl'),
                (Join-Path (Join-Path $zellijCfgRoot 'layouts') 'ide-2pane.kdl'),
                (Join-Path (Join-Path $zellijCfgRoot 'themes') 'windows-settings.kdl')
            )) {
                if (Test-Path -LiteralPath $zf) {
                    if ($IsDryRun) {
                        Write-Host "  [DryRun] Would remove Zellij config file $zf" -ForegroundColor DarkCyan
                    } else {
                        Remove-Item -Force -LiteralPath $zf -ErrorAction SilentlyContinue
                        Write-Host "  Removed $zf" -ForegroundColor Green
                    }
                }
            }
        }
        Sync-AntigravityHooksJson -Remove -DryRun:$IsDryRun
    }

    if ($DoFonts) {
        Write-Host "`n==> Removing MesloLGS Nerd Font Mono files and registry entries..." -ForegroundColor Yellow
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        $fontsDir = if ($isAdmin) { Join-Path $env:SystemRoot "Fonts" } else { Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts" }
        $regKey = if ($isAdmin) { "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" } else { "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" }
        $monoFonts = @(
            @{ File = "MesloLGSNerdFontMono-Regular.ttf"; RegName = "MesloLGS Nerd Font Mono Regular (TrueType)" },
            @{ File = "MesloLGSNerdFontMono-Bold.ttf"; RegName = "MesloLGS Nerd Font Mono Bold (TrueType)" },
            @{ File = "MesloLGSNerdFontMono-Italic.ttf"; RegName = "MesloLGS Nerd Font Mono Italic (TrueType)" },
            @{ File = "MesloLGSNerdFontMono-BoldItalic.ttf"; RegName = "MesloLGS Nerd Font Mono Bold Italic (TrueType)" }
        )
        foreach ($mf in $monoFonts) {
            $fp = Join-Path $fontsDir $mf.File
            if ($IsDryRun) {
                Write-Host "  [DryRun] Would unregister $($mf.RegName) and remove $fp" -ForegroundColor DarkCyan
            } else {
                if (Test-Path $regKey) {
                    Remove-ItemProperty -Path $regKey -Name $mf.RegName -ErrorAction SilentlyContinue
                }
                if (Test-Path $fp) {
                    Remove-Item -Force -Path $fp -ErrorAction SilentlyContinue
                }
            }
        }
    }

    if ($DoBin) {
        $binDir = Join-Path $RootDir "bin"
        Write-Host "`n==> Removing $binDir from User PATH..." -ForegroundColor Yellow
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathParts = if ($userPath) { @($userPath -split ';' | Where-Object { $_ -and $_.Trim() }) } else { @() }
        if ($pathParts -contains $binDir) {
            if ($IsDryRun) {
                Write-Host "  [DryRun] Would remove $binDir from User PATH" -ForegroundColor DarkCyan
            } else {
                $filtered = @($pathParts | Where-Object { $_ -ne $binDir })
                [Environment]::SetEnvironmentVariable('Path', ($filtered -join ';'), 'User')
                Write-Host "  Removed $binDir from User PATH" -ForegroundColor Green
            }
        } else {
            Write-Host "  $binDir is not present in User PATH." -ForegroundColor Green
        }
    }

    Write-Host "`n=====================================================" -ForegroundColor Cyan
    if ($IsDryRun) {
        Write-Host " Uninstall dry run complete! No changes were made.   " -ForegroundColor Magenta
    } else {
        Write-Host " Uninstall workflow completed successfully!          " -ForegroundColor Green
    }
    Write-Host "=====================================================" -ForegroundColor Cyan
}

if ($Uninstall -or $UninstallDotfiles -or $UninstallFonts -or $UninstallBin) {
    $doDf = [bool]($Uninstall -or $UninstallDotfiles)
    $doFt = [bool]($Uninstall -or $UninstallFonts)
    $doBn = [bool]($Uninstall -or $UninstallBin)
    Invoke-WorkstationUninstall -DoDotfiles $doDf -DoFonts $doFt -DoBin $doBn -IsDryRun ([bool]$DryRun)
    return
}

# Normalize GUI switch
$enableGUI = $WithGUI -or $IncludeGUI

# Resolve execution modes
$shouldInstallPackages = ($InstallPackages -or $Bootstrap -or $SystemOnly -or $UseDSC) -and (-not $SkipPackages) -and (-not $DotfilesOnly)
$skipUserConfig = $SystemOnly

if ($skipUserConfig) {
    $SkipFonts = $true
    $SkipPosh = $true
    $SkipCMD = $true
    $SkipCompletions = $true
    $SkipTerminal = $true
    $SkipVim = $true
    $SkipBin = $true
}

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "         Windows Settings Setup Automation           " -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "               [DRY RUN PREVIEW MODE]                " -ForegroundColor Magenta
}
Write-Host "=====================================================" -ForegroundColor Cyan

# -------------------------------------------------------------
# 0. Workstation Package Provisioning via WinGet / DSC / Mise
# -------------------------------------------------------------
if ($shouldInstallPackages) {
    Write-Host "`n[0/6] Installing Workstation Packages via winget / DSC..." -ForegroundColor Yellow
    $dscFile = Join-Path $RootDir "configuration.dsc.yaml"

    if ($UseDSC -and (Test-Path $dscFile)) {
        Write-Host "==> Executing Declarative WinGet DSC Configuration ($dscFile)..." -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "  [DryRun] Would execute: winget configure $dscFile" -ForegroundColor DarkCyan
        } else {
            winget configure $dscFile --accept-configuration-agreements
        }
    } else {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Warning "winget is required but was not found. Please install Windows App Installer."
        } else {
            $cliPackages = @(
                'uutils.coreutils', 'uutils.diffutils', 'Git.Git', 'GitHub.cli',
                'ajeetdsouza.zoxide', 'JanDeDobbeleer.OhMyPosh', 'BurntSushi.ripgrep.MSVC',
                'sharkdp.fd', 'sharkdp.bat', 'eza-community.eza', 'dandavison.delta',
                'junegunn.fzf', 'jqlang.jq', 'MikeFarah.yq', 'bootandy.dust',
                'chmln.sd', 'dbrgn.tealdeer', 'aristocratos.btop4win', 'Zellij.Zellij',
                'jdx.mise', 'vim.vim', 'BrechtSanders.WinLibs.POSIX.UCRT'
            )
            $guiPackages = @('Microsoft.VisualStudioCode', 'Microsoft.WindowsTerminal', 'Docker.DockerDesktop')
            $targetPackages = if ($enableGUI) { $cliPackages + $guiPackages } else { $cliPackages }

            foreach ($pkg in $targetPackages) {
                Write-Host "`n==> Checking package: $pkg" -ForegroundColor Yellow
                if ($DryRun) {
                    Write-Host "  [DryRun] Would install $pkg via winget" -ForegroundColor DarkCyan
                } else {
                    winget install --id $pkg -e --source winget --accept-package-agreements --accept-source-agreements
                }
            }

            # Ensure portable WinGet packages are linked
            $linksDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links"
            $pkgDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
            if (Test-Path $pkgDir) {
                if (-not (Test-Path $linksDir)) {
                    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $linksDir | Out-Null }
                }
                $exes = Get-ChildItem -Path $pkgDir -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue
                foreach ($exe in $exes) {
                    $targetLink = Join-Path $linksDir $exe.Name
                    if (-not (Test-Path $targetLink)) {
                        if ($DryRun) {
                            Write-Host "  [DryRun] Would link $($exe.Name) into $linksDir" -ForegroundColor DarkCyan
                        } else {
                            try {
                                New-Item -ItemType HardLink -Path $targetLink -Target $exe.FullName -Force -ErrorAction SilentlyContinue | Out-Null
                            } catch {
                                Copy-Item -Path $exe.FullName -Destination $targetLink -Force -ErrorAction SilentlyContinue
                            }
                        }
                    }
                }
            }
        }
    }

    # Hydrate declarative polyglot toolchains via mise
    $miseConfig = Join-Path $RootDir "mise.toml"
    Deploy-ConfigFile -Name "Global Mise configuration" -SourcePath $miseConfig -DestinationPath (Join-Path $HOME ".config\mise\config.toml") -DryRun:$DryRun

    if (Get-Command mise -ErrorAction SilentlyContinue) {
        Write-Host "==> Hydrating declarative toolchains via mise..." -ForegroundColor Cyan
        if ($DryRun) {
            Write-Host "  [DryRun] Would execute mise trust --yes and mise install --yes in $RootDir" -ForegroundColor DarkCyan
        } else {
            if (Test-Path $miseConfig) {
                mise -C $RootDir trust --yes
                mise -C $RootDir install --yes
            } else {
                mise trust --yes
                mise install --yes
            }
        }
    }
} else {
    Write-Host "`n[0/6] Skipping Workstation Package Installation." -ForegroundColor DarkCyan
}

# 1. Fonts Setup (MesloLGS Nerd Font Mono - Nerd Fonts v3)
if (-not $SkipFonts) {
    Write-Host "`n[1/6] Setting up Fonts (MesloLGS Nerd Font Mono)..." -ForegroundColor Yellow
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $userFontsDir = Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts"
    $systemFontsDir = Join-Path $env:SystemRoot "Fonts"
    $targetFontsDir = if ($isAdmin) { $systemFontsDir } else { $userFontsDir }
    $registryKey = if ($isAdmin) { "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" } else { "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" }

    if (-not $DryRun -and -not (Test-Path $userFontsDir)) {
        New-Item -ItemType Directory -Force -Path $userFontsDir | Out-Null
    }

    if (-not $DryRun -and -not (Test-Path $registryKey)) {
        New-Item -Path $registryKey -Force | Out-Null
    }

    $fontVersion = "v3.5.1"
    $fontZipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/download/$fontVersion/Meslo.zip"
    $monoFonts = @(
        @{ File = "MesloLGSNerdFontMono-Regular.ttf"; RegName = "MesloLGS Nerd Font Mono Regular (TrueType)" },
        @{ File = "MesloLGSNerdFontMono-Bold.ttf"; RegName = "MesloLGS Nerd Font Mono Bold (TrueType)" },
        @{ File = "MesloLGSNerdFontMono-Italic.ttf"; RegName = "MesloLGS Nerd Font Mono Italic (TrueType)" },
        @{ File = "MesloLGSNerdFontMono-BoldItalic.ttf"; RegName = "MesloLGS Nerd Font Mono Bold Italic (TrueType)" }
    )

    $missingFonts = @()
    foreach ($mf in $monoFonts) {
        $destPath = Join-Path $targetFontsDir $mf.File
        $userPath = Join-Path $userFontsDir $mf.File
        if ((-not (Test-Path $destPath) -or ((Get-Item $destPath).Length -lt 2500000)) -and
            (-not (Test-Path $userPath) -or ((Get-Item $userPath).Length -lt 2500000))) {
            $missingFonts += $mf
        }
    }

    if ($missingFonts.Count -gt 0) {
        $cacheDir = Join-Path $HOME ".cache\windows-settings\fonts"
        $cachedZip = Join-Path $cacheDir "Meslo-$fontVersion.zip"

        if ($DryRun) {
            Write-Host "  [DryRun] Would download and extract MesloLGS Nerd Font Mono ($fontVersion) to $targetFontsDir" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
            if (-not (Test-Path $cachedZip) -or ((Get-Item $cachedZip).Length -lt 10000000)) {
                Write-Host "Downloading MesloLGS Nerd Font ($fontVersion)..." -ForegroundColor Yellow
                Invoke-WebRequest -Uri $fontZipUrl -OutFile $cachedZip -UseBasicParsing
            }
            Write-Host "Extracting MesloLGS Nerd Font Mono fonts into $targetFontsDir..." -ForegroundColor Cyan
            $tempExtract = Join-Path $cacheDir "extract"
            if (-not (Test-Path $tempExtract)) { New-Item -ItemType Directory -Force -Path $tempExtract | Out-Null }
            Expand-Archive -Path $cachedZip -DestinationPath $tempExtract -Force
            foreach ($mf in $monoFonts) {
                $src = Join-Path $tempExtract $mf.File
                $dst = Join-Path $targetFontsDir $mf.File
                if (Test-Path $src) {
                    Copy-Item -Path $src -Destination $dst -Force
                }
            }
            Remove-Item -Recurse -Force -Path $tempExtract -ErrorAction SilentlyContinue
        }
    } else {
        if ($isAdmin -and -not $DryRun) {
            foreach ($mf in $monoFonts) {
                $src = Join-Path $userFontsDir $mf.File
                $dst = Join-Path $systemFontsDir $mf.File
                if ((Test-Path $src) -and (-not (Test-Path $dst))) {
                    Copy-Item -Path $src -Destination $dst -Force
                }
            }
        }
        if (-not $DryRun) {
            Write-Host "MesloLGS Nerd Font Mono fonts already downloaded." -ForegroundColor Green
        }
    }

    foreach ($mf in $monoFonts) {
        $destPath = Join-Path $targetFontsDir $mf.File
        $regVal = if ($isAdmin) { $mf.File } else { $destPath }
        if ($DryRun) {
            Write-Host "  [DryRun] Would register font $($mf.RegName) in $registryKey" -ForegroundColor DarkCyan
        } else {
            if (Test-Path $destPath) {
                Set-ItemProperty -Path $registryKey -Name $mf.RegName -Value $regVal -ErrorAction SilentlyContinue
            }
        }
    }

    # Ensure ALL APPLICATION PACKAGES has read access for Windows Terminal AppContainer sandbox
    if (-not $DryRun -and -not $isAdmin) {
        Write-Host "Granting AppContainer permissions on user fonts folder..." -ForegroundColor Cyan
        & icacls "$userFontsDir" /grant "*S-1-15-2-1:(OI)(CI)(RX)" "*S-1-15-2-2:(OI)(CI)(RX)" "BUILTIN\Users:(OI)(CI)(RX)" /T /C /Q | Out-Null
    } elseif ($DryRun -and -not $isAdmin) {
        Write-Host "  [DryRun] Would grant AppContainer permissions (ALL APPLICATION PACKAGES) on $userFontsDir" -ForegroundColor DarkCyan
    }

    $scopeLabel = if ($isAdmin) { "system-wide in $systemFontsDir" } else { "user scope in $userFontsDir" }
    Write-Host "==> MesloLGS Nerd Font Mono fonts installed ($scopeLabel)." -ForegroundColor Green
} else {
    Write-Host "`n[1/6] Skipping Fonts Setup." -ForegroundColor DarkCyan
}

# 2. Oh My Posh Prompt, 17-Theme Engine, CLI Tool Configs & WindowsSettings Module Setup
if (-not $SkipPosh) {
    Write-Host "`n[2/6] Setting up Oh My Posh, 17-Theme Engine, CLI Configs & WindowsSettings Module..." -ForegroundColor Yellow

    # Deploy Oh My Posh prompt theme (bin/theme.ps1 renders active palette colors below)
    $p10kSource = Join-Path $RootDir "config\powershell\p10k_single_line.omp.json"
    $p10kDest = Join-Path $HOME ".poshthemes\p10k_single_line.omp.json"
    if (-not (Test-Path $p10kDest) -or $DryRun) {
        Deploy-ConfigFile -Name "Oh My Posh theme" -SourcePath $p10kSource -DestinationPath $p10kDest -DryRun:$DryRun
    }

    # Compile Oh My Posh prompt hook into compiled cache
    $ompCacheDir = Join-Path $HOME ".cache\powershell"
    $ompInit = Join-Path $ompCacheDir "omp_init.ps1"
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would compile Oh My Posh prompt hook to $ompInit" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $ompCacheDir)) { New-Item -ItemType Directory -Force -Path $ompCacheDir | Out-Null }
            oh-my-posh init pwsh --config $p10kDest --print | Out-File -FilePath $ompInit -Encoding utf8 -Force
            Write-Host "==> Oh My Posh prompt cache compiled at $ompInit" -ForegroundColor Green
        }
    }

    # Deploy bat TrueColor syntax themes (17 palettes) and 37 custom syntaxes
    $batThemeSource = Join-Path $RootDir "config\bat\Solarized-Dark-TrueColor.tmTheme"
    $batThemesDirSource = Join-Path $RootDir "config\bat\themes"
    $batSyntaxesSource = Join-Path $RootDir "config\bat\syntaxes"
    $batConfigDir = Join-Path $env:APPDATA "bat"
    $batThemesDest = Join-Path $batConfigDir "themes"
    $batConfigFile = Join-Path $batConfigDir "config"
    $targetBatTheme = '--theme="Solarized-Dark-TrueColor"'

    Deploy-ConfigFile -Name "bat Solarized Dark theme" -SourcePath $batThemeSource -DestinationPath (Join-Path $batThemesDest "Solarized-Dark-TrueColor.tmTheme") -DryRun:$DryRun

    if (Test-Path $batThemesDirSource) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy 17 bat TrueColor themes to $batThemesDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $batThemesDest)) { New-Item -ItemType Directory -Force -Path $batThemesDest | Out-Null }
            Copy-Item -Path (Join-Path $batThemesDirSource "*.tmTheme") -Destination $batThemesDest -Force
            Write-Host "==> 17 bat TrueColor themes deployed to $batThemesDest" -ForegroundColor Green
        }
    }

    if (Test-Path $batSyntaxesSource) {
        $batSyntaxesDest = Join-Path $batConfigDir "syntaxes"
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy 37 bat syntaxes to $batSyntaxesDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $batSyntaxesDest)) { New-Item -ItemType Directory -Force -Path $batSyntaxesDest | Out-Null }
            Copy-Item -Path (Join-Path $batSyntaxesSource "*.sublime-syntax") -Destination $batSyntaxesDest -Force
            Write-Host "==> bat syntaxes deployed to $batSyntaxesDest" -ForegroundColor Green
        }
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would ensure --theme is configured in $batConfigFile and rebuild bat cache" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $batConfigDir)) { New-Item -ItemType Directory -Force -Path $batConfigDir | Out-Null }
        if (Test-Path $batConfigFile) {
            $existingBatConfig = Get-Content $batConfigFile -Raw
            if ($existingBatConfig -notmatch '--theme=') {
                Add-Content -Path $batConfigFile -Value "`n$targetBatTheme" -Encoding utf8
            }
        } else {
            $targetBatTheme | Set-Content -Path $batConfigFile -Encoding utf8
        }
        if (Get-Command bat -ErrorAction SilentlyContinue) {
            & bat cache --build | Out-Null
        }
    }

    # Deploy Git Delta, Tealdeer (tldr), Clangd, and btop4win Configurations
    $deltaSrc = Join-Path $RootDir "config\git\delta.gitconfig"
    $deltaDest = Join-Path $HOME ".config\windows-settings\delta-theme.gitconfig"
    if (-not (Test-Path $deltaDest) -or $DryRun) {
        Deploy-ConfigFile -Name "Git Delta theme config" -SourcePath $deltaSrc -DestinationPath $deltaDest -DryRun:$DryRun
    }
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $deltaInclude = '~/.config/windows-settings/delta-theme.gitconfig'
        $existingIncludes = @(git config --global --get-all include.path 2>$null)
        if ($existingIncludes -notcontains $deltaInclude) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would register git global include.path -> $deltaInclude" -ForegroundColor DarkCyan
            } else {
                git config --global --add include.path $deltaInclude
                $existingPager = git config --global --get core.pager 2>$null
                if (-not $existingPager -and (Get-Command delta -ErrorAction SilentlyContinue)) {
                    git config --global core.pager delta
                    git config --global interactive.diffFilter 'delta --color-only'
                }
            }
        }
    }

    $tealdeerSrc = Join-Path $RootDir "config\tealdeer\config.toml"
    if ($env:APPDATA) {
        $tealdeerDest = Join-Path $env:APPDATA "tealdeer\config.toml"
        if (-not (Test-Path $tealdeerDest) -or $DryRun) {
            Deploy-ConfigFile -Name "Tealdeer (tldr) config" -SourcePath $tealdeerSrc -DestinationPath $tealdeerDest -DryRun:$DryRun
        }
    }

    $clangdSrc = Join-Path $RootDir "config\clangd\config.yaml"
    if ($env:LOCALAPPDATA) {
        Deploy-ConfigFile -Name "Clangd config" -SourcePath $clangdSrc -DestinationPath (Join-Path $env:LOCALAPPDATA "clangd\config.yaml") -DryRun:$DryRun
    }

    $btopConfSrc = Join-Path $RootDir "config\btop\btop.conf"
    $btopThemesSrc = Join-Path $RootDir "config\btop\themes"
    $btopDestDir = Join-Path $HOME ".config\btop"
    $btopConfDest = Join-Path $btopDestDir "btop.conf"
    if (-not (Test-Path $btopConfDest) -or $DryRun) {
        Deploy-ConfigFile -Name "btop config" -SourcePath $btopConfSrc -DestinationPath $btopConfDest -DryRun:$DryRun
    }
    if (Test-Path $btopThemesSrc) {
        $btopThemesDest = Join-Path $btopDestDir "themes"
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy 17 btop themes to $btopThemesDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $btopThemesDest)) { New-Item -ItemType Directory -Force -Path $btopThemesDest | Out-Null }
            Copy-Item -Path (Join-Path $btopThemesSrc "*.theme") -Destination $btopThemesDest -Force
        }
    }

    # Deploy WindowsSettings PowerShell Module
    Write-Host "==> Deploying WindowsSettings PowerShell Module..." -ForegroundColor Cyan
    $moduleSource = Join-Path $RootDir "module"
    $userModulesDir = Join-Path $HOME "Documents\PowerShell\Modules"
    $moduleDest = Join-Path $userModulesDir "WindowsSettings"

    if (Test-Path $moduleSource) {
        if (-not (Test-Path $userModulesDir)) {
            if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $userModulesDir | Out-Null }
        }
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy WindowsSettings module to $moduleDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $moduleDest)) {
                New-Item -ItemType Directory -Force -Path $moduleDest | Out-Null
            } else {
                $legacyDirs = @('Public', 'Completions')
                foreach ($ld in $legacyDirs) {
                    $stalePath = Join-Path $moduleDest $ld
                    if (Test-Path $stalePath) {
                        Remove-Item -Recurse -Force -Path $stalePath -ErrorAction SilentlyContinue
                    }
                }
            }
            Copy-Item -Path (Join-Path $moduleSource "*") -Destination $moduleDest -Recurse -Force
            Write-Host "==> WindowsSettings module deployed to $moduleDest" -ForegroundColor Green
        }
    }

    # Deploy Zellij 0.46+ Configuration, IDE Layouts, Theme Seed & Antigravity OSC 7501 Hook
    $zellijSrcDir = Join-Path $RootDir "config\zellij"
    $zellijDestDir = if ($env:APPDATA) {
        Join-Path (Join-Path $env:APPDATA "Zellij") "config"
    } else {
        Join-Path $HOME ".config\zellij"
    }
    if (Test-Path -LiteralPath $zellijSrcDir) {
        Deploy-ZellijConfig -SourcePath (Join-Path $zellijSrcDir "config.kdl") -DestinationPath (Join-Path $zellijDestDir "config.kdl") -DryRun:$DryRun
        Deploy-ConfigFile -Name "Zellij 3-pane IDE layout" -SourcePath (Join-Path $zellijSrcDir "layouts\ide-3pane.kdl") -DestinationPath (Join-Path $zellijDestDir "layouts\ide-3pane.kdl") -DryRun:$DryRun
        Deploy-ConfigFile -Name "Zellij 2-pane IDE layout" -SourcePath (Join-Path $zellijSrcDir "layouts\ide-2pane.kdl") -DestinationPath (Join-Path $zellijDestDir "layouts\ide-2pane.kdl") -DryRun:$DryRun
        $zellijThemeSeedDst = Join-Path $zellijDestDir "themes\windows-settings.kdl"
        if (-not (Test-Path -LiteralPath $zellijThemeSeedDst) -or $DryRun) {
            Deploy-ConfigFile -Name "Zellij theme seed" -SourcePath (Join-Path $zellijSrcDir "themes\windows-settings.kdl") -DestinationPath $zellijThemeSeedDst -DryRun:$DryRun
        }
    }
    Sync-AntigravityHooksJson -DryRun:$DryRun

    # Apply Active Color Theme via bin/theme.ps1
    $themeScript = Join-Path $RootDir "bin\theme.ps1"
    if (Test-Path $themeScript) {
        $savedThemeFile = Join-Path $HOME ".config\windows-settings\theme"
        $effectiveTheme = if ($Theme -and $Theme.Trim()) {
            $Theme.Trim().ToLowerInvariant()
        } elseif (Test-Path $savedThemeFile) {
            (Get-Content $savedThemeFile -Raw).Trim().ToLowerInvariant()
        } else {
            'solarized-dark'
        }
        if (-not $effectiveTheme) { $effectiveTheme = 'solarized-dark' }

        if ($DryRun) {
            if ($effectiveTheme -eq 'holiday') {
                & $themeScript --dry-run --holiday --no-live | Out-Host
            } else {
                & $themeScript --dry-run --set $effectiveTheme --no-live | Out-Host
            }
        } else {
            $themeArgs = if ($effectiveTheme -eq 'holiday') { @('--holiday') } else { @('--set', $effectiveTheme) }
            if ([Console]::IsOutputRedirected -or $env:WS_TEST_MODE -eq '1') {
                $themeArgs += '--no-live'
            }
            & $themeScript @themeArgs | Out-Host
        }
    }

    # Configure PowerShell Profile ($PROFILE)
    Write-Host "==> Configuring PowerShell profile at $PROFILE..." -ForegroundColor Cyan
    $profileDir = Split-Path -Parent $PROFILE
    if (-not (Test-Path $profileDir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null }
    }

    $targetProfileContent = @'
# =============================================================
# PowerShell Profile - windows-settings
# =============================================================

Import-Module WindowsSettings -DisableNameChecking -ErrorAction SilentlyContinue
'@

    if (Test-Path $PROFILE) {
        $currentContent = Get-Content $PROFILE -Raw
        $hasModule = ($currentContent -match 'Import-Module\s+WindowsSettings')

        if (-not $hasModule) {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $backupProfile = "$PROFILE.bak_$timestamp"
            if ($DryRun) {
                Write-Host "  [DryRun] Would backup $PROFILE to $backupProfile" -ForegroundColor DarkCyan
                Write-Host "  [DryRun] Would append WindowsSettings module import to $PROFILE" -ForegroundColor DarkCyan
            } else {
                Write-Host "Backing up existing profile to $backupProfile..." -ForegroundColor Yellow
                Copy-Item -Path $PROFILE -Destination $backupProfile -Force
                $appendContent = if ([string]::IsNullOrWhiteSpace($currentContent)) {
                    $targetProfileContent
                } else {
                    "`n`n" + $targetProfileContent
                }
                [System.IO.File]::AppendAllText($PROFILE, $appendContent, [System.Text.Encoding]::UTF8)
                Write-Host "==> PowerShell profile updated successfully!" -ForegroundColor Green
            }
        } else {
            Write-Host "==> PowerShell profile is already up to date." -ForegroundColor Green
        }
    } else {
        if ($DryRun) {
            Write-Host "  [DryRun] Would create new PowerShell profile at $PROFILE" -ForegroundColor DarkCyan
        } else {
            Write-Host "Creating new PowerShell profile at $PROFILE..." -ForegroundColor Cyan
            [System.IO.File]::WriteAllText($PROFILE, $targetProfileContent, [System.Text.Encoding]::UTF8)
            Write-Host "==> PowerShell profile created successfully!" -ForegroundColor Green
        }
    }

    # Set COLORTERM=truecolor in User Environment for 24-bit TrueColor
    $userColorTerm = [Environment]::GetEnvironmentVariable('COLORTERM', 'User')
    if ($userColorTerm -ne 'truecolor') {
        if ($DryRun) {
            Write-Host "  [DryRun] Would set User environment variable COLORTERM=truecolor" -ForegroundColor DarkCyan
        } else {
            [Environment]::SetEnvironmentVariable('COLORTERM', 'truecolor', 'User')
            $env:COLORTERM = 'truecolor'
        }
    }

    # Configure Windows Command Prompt (cmd.exe) AutoRun & Doskey
    if (-not $SkipCMD) {
        Write-Host "==> Setting up Windows Command Prompt (cmd.exe) AutoRun & Doskey..." -ForegroundColor Cyan
        $cmdSource = Join-Path $RootDir "config\cmd\autorun.cmd"
        $cmdDest = Join-Path $env:LOCALAPPDATA "cmd\autorun.cmd"
        $cmdAltDest = Join-Path $HOME ".config\cmd\autorun.cmd"

        Deploy-ConfigFile -Name "CMD AutoRun script" `
            -SourcePath $cmdSource `
            -DestinationPath $cmdDest `
            -AltDestinations @($cmdAltDest) `
            -DryRun:$DryRun

        # Enable VirtualTerminalLevel in Console for ANSI escape rendering in conhost
        $consoleKey = "HKCU:\Console"
        if (-not (Test-Path $consoleKey)) {
            if (-not $DryRun) { New-Item -Path $consoleKey -Force | Out-Null }
        }
        $vtProp = Get-ItemProperty -Path $consoleKey -Name "VirtualTerminalLevel" -ErrorAction SilentlyContinue
        if (-not $vtProp -or $vtProp.VirtualTerminalLevel -ne 1) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would set HKCU:\Console\VirtualTerminalLevel = 1 (DWORD)" -ForegroundColor DarkCyan
            } else {
                Set-ItemProperty -Path $consoleKey -Name "VirtualTerminalLevel" -Value 1 -Type DWord -Force
                Write-Host "==> Console VirtualTerminalLevel (ANSI) enabled." -ForegroundColor Green
            }
        }

        # Configure AutoRun in Command Processor registry key
        $cmdProcessorKey = "HKCU:\Software\Microsoft\Command Processor"
        $autoRunTarget = 'if exist "%LOCALAPPDATA%\cmd\autorun.cmd" call "%LOCALAPPDATA%\cmd\autorun.cmd"'

        if (-not (Test-Path $cmdProcessorKey)) {
            if (-not $DryRun) { New-Item -Path $cmdProcessorKey -Force | Out-Null }
        }

        $apProp = Get-ItemProperty -Path $cmdProcessorKey -Name "AutoRun" -ErrorAction SilentlyContinue
        $existingAutoRun = if ($apProp) { $apProp.AutoRun } else { $null }

        if (-not $existingAutoRun -or $existingAutoRun -notlike "*autorun.cmd*") {
            if ($DryRun) {
                Write-Host "  [DryRun] Would configure CMD AutoRun in $cmdProcessorKey" -ForegroundColor DarkCyan
            } else {
                $newAutoRun = if ([string]::IsNullOrWhiteSpace($existingAutoRun)) {
                    $autoRunTarget
                } else {
                    "$existingAutoRun & $autoRunTarget"
                }
                Set-ItemProperty -Path $cmdProcessorKey -Name "AutoRun" -Value $newAutoRun -Type ExpandString -Force
                Write-Host "==> CMD AutoRun configured in registry." -ForegroundColor Green
            }
        } else {
            Write-Host "==> CMD AutoRun is already configured in registry." -ForegroundColor Green
        }
    }
} else {
    Write-Host "`n[2/6] Skipping Shell & Prompt Setup." -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# 3. CLI Tab Completions Setup
# -------------------------------------------------------------
if (-not $SkipCompletions) {
    Write-Host "`n[3/6] Setting up CLI Completions..." -ForegroundColor Yellow
    $cacheDir = Join-Path $HOME '.cache\powershell'
    if (-not $DryRun -and -not (Test-Path $cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }

    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $ghCache = Join-Path $cacheDir 'gh_completion.ps1'
        if ($DryRun) {
            Write-Host "  [DryRun] Would cache and register GitHub CLI completions ($ghCache)" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $ghCache) -or (Get-Item $ghCache).Length -eq 0) {
                gh completion -s powershell | Out-File -FilePath $ghCache -Encoding utf8 -Force
            }
            if ((Test-Path $ghCache) -and (Get-Item $ghCache).Length -gt 0) {
                . $ghCache
            }
        }
    }
} else {
    Write-Host "`n[3/6] Skipping CLI Completions." -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# 4. Windows Terminal Setup (Zero-Touch JSON Fragment Deployment)
# -------------------------------------------------------------
if (-not $SkipTerminal) {
    Write-Host "`n[4/6] Setting up Windows Terminal (JSON Fragments & Settings)..." -ForegroundColor Yellow
    $fragmentSource = Join-Path $RootDir "config\terminal\windows-settings.json"
    $primaryDest = Join-Path $env:LOCALAPPDATA "Microsoft\Windows Terminal\Fragments\WindowsSettings\windows-settings.json"
    $altDests = @(
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings\windows-settings.json"),
        (Join-Path $env:LOCALAPPDATA "Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings\windows-settings.json")
    )

    Deploy-ConfigFile -Name "Windows Terminal JSON Fragment" -SourcePath $fragmentSource -DestinationPath $primaryDest -AltDestinations $altDests -DryRun:$DryRun
} else {
    Write-Host "`n[4/6] Skipping Windows Terminal Setup." -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# 5. Neovim & Vim Setup (43 Tree-sitter Queries, lazy-lock, _vimrc)
# -------------------------------------------------------------
if (-not $SkipVim) {
    Write-Host "`n[5/6] Setting up Neovim & Vim configuration..." -ForegroundColor Yellow

    $nvimSourceDir = Join-Path $RootDir "config\nvim"
    $nvimDestDir = Join-Path $env:LOCALAPPDATA "nvim"
    $nvimSource = Join-Path $nvimSourceDir "init.lua"
    $nvimDest = Join-Path $nvimDestDir "init.lua"
    Deploy-ConfigFile -Name "Neovim configuration" -SourcePath $nvimSource -DestinationPath $nvimDest -DryRun:$DryRun

    $staleMdInline = Join-Path $nvimDestDir "after\queries\markdown_inline"
    if (-not $DryRun -and (Test-Path $staleMdInline)) {
        Remove-Item -Recurse -Force -Path $staleMdInline -ErrorAction SilentlyContinue
    }

    $nvimSubDirs = @('queries', 'after', 'ftplugin')
    foreach ($sd in $nvimSubDirs) {
        $srcPath = Join-Path $nvimSourceDir $sd
        $dstPath = Join-Path $nvimDestDir $sd
        if (Test-Path $srcPath) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would deploy Neovim $sd to $dstPath" -ForegroundColor DarkCyan
            } else {
                if (-not (Test-Path $dstPath)) { New-Item -ItemType Directory -Force -Path $dstPath | Out-Null }
                Copy-Item -Path (Join-Path $srcPath "*") -Destination $dstPath -Recurse -Force
                Write-Host "==> Neovim $sd deployed to $dstPath" -ForegroundColor Green
            }
        }
    }

    $lockSrc = Join-Path $nvimSourceDir "lazy-lock.json"
    if (Test-Path $lockSrc) {
        Deploy-ConfigFile -Name "Neovim lazy-lock" -SourcePath $lockSrc -DestinationPath (Join-Path $nvimDestDir "lazy-lock.json") -DryRun:$DryRun
    }

    # Legacy Vim (_vimrc)
    $vimrcSource = Join-Path $RootDir "config\vim\_vimrc"
    Deploy-ConfigFile -Name "Vim configuration" -SourcePath $vimrcSource -DestinationPath (Join-Path $HOME "_vimrc") -AltDestinations @((Join-Path $HOME ".vimrc")) -DryRun:$DryRun
} else {
    Write-Host "`n[5/6] Skipping Editor Setup." -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# 6. Add bin and toolchain shims to User PATH
# -------------------------------------------------------------
if (-not $SkipBin) {
    $binDir = Join-Path $RootDir "bin"
    if (Test-Path $binDir) {
        Write-Host "`n[6/6] Checking User PATH for utility scripts ($binDir)..." -ForegroundColor Yellow
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathParts = if ($userPath) { $userPath -split ';' | Where-Object { $_ -and $_.Trim() } } else { @() }
        if ($pathParts -notcontains $binDir) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would add $binDir to User PATH" -ForegroundColor DarkCyan
            } else {
                Write-Host "Adding $binDir to User PATH..." -ForegroundColor Cyan
                $newPath = ($pathParts + $binDir) -join ';'
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                $env:Path = "$env:Path;$binDir"
                Write-Host "User PATH updated successfully." -ForegroundColor Green
            }
        } else {
            Write-Host "  $binDir is already in User PATH." -ForegroundColor Green
        }
    }

    # Ensure mise.toml is deployed even if package install was skipped
    $miseConfig = Join-Path $RootDir "mise.toml"
    Deploy-ConfigFile -Name "Global Mise configuration" -SourcePath $miseConfig -DestinationPath (Join-Path $HOME ".config\mise\config.toml") -DryRun:$DryRun

    $miseShims = Join-Path $env:LOCALAPPDATA "mise\shims"
    if (Test-Path $miseShims) {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathParts = if ($userPath) { $userPath -split ';' | Where-Object { $_ -and $_.Trim() } } else { @() }
        if ($pathParts -notcontains $miseShims) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would add $miseShims to User PATH" -ForegroundColor DarkCyan
            } else {
                $newPath = ($pathParts + $miseShims) -join ';'
                [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                $env:Path = "$miseShims;$env:Path"
            }
        }
    }

    # Ensure WinLibs GCC bin is registered in User PATH if present
    $winlibsDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (Test-Path $winlibsDir) {
        $winlibsPackages = Get-ChildItem -Path $winlibsDir -Filter "BrechtSanders.WinLibs*" -Directory -ErrorAction SilentlyContinue
        if ($winlibsPackages) {
            $winlibsBin = Join-Path $winlibsPackages[0].FullName "mingw64\bin"
            if (Test-Path $winlibsBin) {
                $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
                $pathParts = if ($userPath) { $userPath -split ';' | Where-Object { $_ -and $_.Trim() } } else { @() }
                if ($pathParts -notcontains $winlibsBin) {
                    if ($DryRun) {
                        Write-Host "  [DryRun] Would add $winlibsBin to User PATH" -ForegroundColor DarkCyan
                    } else {
                        $newPath = ($pathParts + $winlibsBin) -join ';'
                        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
                        $env:Path = "$winlibsBin;$env:Path"
                    }
                }
            }
        }
    }
} else {
    Write-Host "`n[6/6] Skipping User PATH configuration." -ForegroundColor DarkCyan
}

if (-not $DryRun -and -not $SkipPosh -and -not $SystemOnly -and $env:WS_TEST_MODE -ne '1') {
    try {
        Import-Module WindowsSettings -Force -Global -DisableNameChecking -ErrorAction SilentlyContinue
    } catch {
        $null = $_
    }
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " Dry run complete! No changes were made to system.   " -ForegroundColor Magenta
} else {
    Write-Host " Workstation configuration completed successfully!   " -ForegroundColor Green
}
Write-Host "=====================================================" -ForegroundColor Cyan
