<#
.SYNOPSIS
    Master setup engine for windows-settings.
    Automates package provisioning, fonts, Oh My Posh prompt, WindowsSettings module,
    CLI completions, utility PATH, Neovim, and Windows Terminal.

.DESCRIPTION
    Execution Modes:
      -Bootstrap             Full new machine bootstrap (winget packages, fonts, oh-my-posh, module, terminal, nvim)
      -DotfilesOnly          Configure user dotfiles, fonts, nvim, terminal, and shell module only (no package install)
      -SystemOnly            Provision winget packages and CLI tools only
      -UseDSC                Provision workstation packages using declarative WinGet DSC v3 manifest (configuration.dsc.yaml)
      -DryRun                Preview actions without modifying the system

    GUI Options:
      -WithGUI, -IncludeGUI  Install GUI desktop applications (VS Code, Windows Terminal, Docker Desktop via winget)

    Granular Skip Flags:
      -SkipPackages          Skip winget package installation
      -SkipFonts             Skip MesloLGS Nerd Font Mono installation
      -SkipPosh              Skip Oh My Posh & PowerShell module configuration
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
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) {
            if (-not $DryRun) {
                New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            }
        }

        if (Test-Path $dest) {
            $existingContent = Get-Content $dest -Raw
            $isDiff = ($existingContent.Trim() -ne $sourceContent.Trim())

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
                'sharkdp.fd', 'junegunn.fzf', 'jqlang.jq', 'jdx.mise', 'vim.vim'
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
            $linksDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
            $pkgDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
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
    Deploy-ConfigFile -Name "Global Mise configuration" -SourcePath $miseConfig -DestinationPath "$HOME\.config\mise\config.toml" -DryRun:$DryRun

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

# 2. Oh My Posh Prompt & WindowsSettings Module Setup
if (-not $SkipPosh) {
    Write-Host "`n[2/6] Setting up Oh My Posh Prompt & WindowsSettings PowerShell Module..." -ForegroundColor Yellow

    # Deploy Oh My Posh prompt theme
    $p10kSource = Join-Path $RootDir "config\powershell\p10k_single_line.omp.json"
    $p10kDest = "$HOME\.poshthemes\p10k_single_line.omp.json"
    Deploy-ConfigFile -Name "Oh My Posh theme" -SourcePath $p10kSource -DestinationPath $p10kDest -DryRun:$DryRun

    # Compile Oh My Posh prompt hook into compiled cache
    $ompCacheDir = "$HOME\.cache\powershell"
    $ompInit = "$ompCacheDir\omp_init.ps1"
    if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
        if ($DryRun) {
            Write-Host "  [DryRun] Would compile Oh My Posh prompt hook to $ompInit" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $ompCacheDir)) { New-Item -ItemType Directory -Force -Path $ompCacheDir | Out-Null }
            oh-my-posh init pwsh --config $p10kDest --print | Out-File -FilePath $ompInit -Encoding utf8 -Force
            Write-Host "==> Oh My Posh prompt cache compiled at $ompInit" -ForegroundColor Green
        }
    }

    # Deploy bat TrueColor syntax theme and custom syntaxes
    $batThemeSource = Join-Path $RootDir "config\bat\Solarized-Dark-TrueColor.tmTheme"
    $batSyntaxesSource = Join-Path $RootDir "config\bat\syntaxes"
    $batConfigDir = "$env:APPDATA\bat"
    $batConfigFile = Join-Path $batConfigDir "config"
    $targetBatTheme = '--theme="Solarized-Dark-TrueColor"'

    Deploy-ConfigFile -Name "bat theme" -SourcePath $batThemeSource -DestinationPath "$batConfigDir\themes\Solarized-Dark-TrueColor.tmTheme" -DryRun:$DryRun

    if (Test-Path $batSyntaxesSource) {
        $batSyntaxesDest = Join-Path $batConfigDir "syntaxes"
        if ($DryRun) {
            Write-Host "  [DryRun] Would deploy bat syntaxes to $batSyntaxesDest" -ForegroundColor DarkCyan
        } else {
            if (-not (Test-Path $batSyntaxesDest)) { New-Item -ItemType Directory -Force -Path $batSyntaxesDest | Out-Null }
            Copy-Item -Path "$batSyntaxesSource\*" -Destination $batSyntaxesDest -Force
            Write-Host "==> bat syntaxes deployed to $batSyntaxesDest" -ForegroundColor Green
        }
    }

    if ($DryRun) {
        Write-Host "  [DryRun] Would ensure $targetBatTheme is configured in $batConfigFile" -ForegroundColor DarkCyan
    } else {
        if (-not (Test-Path $batConfigDir)) { New-Item -ItemType Directory -Force -Path $batConfigDir | Out-Null }
        if (Test-Path $batConfigFile) {
            $existingBatConfig = Get-Content $batConfigFile -Raw
            if ($existingBatConfig -notmatch '--theme=') {
                Add-Content -Path $batConfigFile -Value "`n$targetBatTheme" -Encoding utf8
            } elseif ($existingBatConfig -notmatch [regex]::Escape($targetBatTheme)) {
                $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
                Copy-Item -Path $batConfigFile -Destination "$batConfigFile.bak_$timestamp" -Force
                $updatedConfig = $existingBatConfig -replace '--theme=\S+', $targetBatTheme
                [System.IO.File]::WriteAllText($batConfigFile, $updatedConfig, [System.Text.Encoding]::UTF8)
            }
        } else {
            $targetBatTheme | Set-Content -Path $batConfigFile -Encoding utf8
        }
        if (Get-Command bat -ErrorAction SilentlyContinue) {
            & bat cache --build | Out-Null
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
                # Clean up legacy subdirectories if migrating from v1
                $legacyDirs = @('Public', 'Completions')
                foreach ($ld in $legacyDirs) {
                    $stalePath = Join-Path $moduleDest $ld
                    if (Test-Path $stalePath) {
                        Remove-Item -Recurse -Force -Path $stalePath -ErrorAction SilentlyContinue
                    }
                }
            }
            Copy-Item -Path "$moduleSource\*" -Destination $moduleDest -Recurse -Force
            Write-Host "==> WindowsSettings module deployed to $moduleDest" -ForegroundColor Green
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
        $cmdDest = "$env:LOCALAPPDATA\cmd\autorun.cmd"
        $cmdAltDest = "$HOME\.config\cmd\autorun.cmd"

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
    $primaryDest = "$env:LOCALAPPDATA\Microsoft\Windows Terminal\Fragments\WindowsSettings\windows-settings.json"
    $altDests = @(
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings\windows-settings.json",
        "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\Fragments\WindowsSettings\windows-settings.json"
    )

    Deploy-ConfigFile -Name "Windows Terminal JSON Fragment" -SourcePath $fragmentSource -DestinationPath $primaryDest -AltDestinations $altDests -DryRun:$DryRun
} else {
    Write-Host "`n[4/6] Skipping Windows Terminal Setup." -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# 5. Neovim & Vim Setup
# -------------------------------------------------------------
if (-not $SkipVim) {
    Write-Host "`n[5/6] Setting up Neovim & Vim configuration..." -ForegroundColor Yellow

    # Modern Neovim (init.lua, queries, after/queries, ftplugin, lazy-lock.json)
    $nvimSourceDir = Join-Path $RootDir "config\nvim"
    $nvimDestDir = Join-Path $env:LOCALAPPDATA "nvim"
    $nvimSource = Join-Path $nvimSourceDir "init.lua"
    $nvimDest = Join-Path $nvimDestDir "init.lua"
    Deploy-ConfigFile -Name "Neovim configuration" -SourcePath $nvimSource -DestinationPath $nvimDest -DryRun:$DryRun

    $nvimSubDirs = @('queries', 'after', 'ftplugin')
    foreach ($sd in $nvimSubDirs) {
        $srcPath = Join-Path $nvimSourceDir $sd
        $dstPath = Join-Path $nvimDestDir $sd
        if (Test-Path $srcPath) {
            if ($DryRun) {
                Write-Host "  [DryRun] Would deploy Neovim $sd to $dstPath" -ForegroundColor DarkCyan
            } else {
                if (-not (Test-Path $dstPath)) { New-Item -ItemType Directory -Force -Path $dstPath | Out-Null }
                Copy-Item -Path "$srcPath\*" -Destination $dstPath -Recurse -Force
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
    Deploy-ConfigFile -Name "Vim configuration" -SourcePath $vimrcSource -DestinationPath "$HOME\_vimrc" -AltDestinations @("$HOME\.vimrc") -DryRun:$DryRun
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
    Deploy-ConfigFile -Name "Global Mise configuration" -SourcePath $miseConfig -DestinationPath "$HOME\.config\mise\config.toml" -DryRun:$DryRun

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
} else {
    Write-Host "`n[6/6] Skipping User PATH configuration." -ForegroundColor DarkCyan
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host " Dry run complete! No changes were made to system.   " -ForegroundColor Magenta
} else {
    Write-Host " Workstation configuration completed successfully!   " -ForegroundColor Green
}
Write-Host "=====================================================" -ForegroundColor Cyan
