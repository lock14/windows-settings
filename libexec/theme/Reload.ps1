# ==============================================================================
# Reload.ps1 - SHA-256 asset materialization, bat cache & live RPC/OSC reloads
# ==============================================================================

function Test-FileByteEqual([string]$PathA, [string]$PathB) {
    if (-not [System.IO.File]::Exists($PathA) -or -not [System.IO.File]::Exists($PathB)) {
        return $false
    }
    $infoA = [System.IO.FileInfo]::new($PathA)
    $infoB = [System.IO.FileInfo]::new($PathB)
    if ($infoA.Length -ne $infoB.Length) {
        return $false
    }
    $hashA = [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($PathA))
    $hashB = [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($PathB))
    return [System.Linq.Enumerable]::SequenceEqual($hashA, $hashB)
}

function Write-TextIfChanged([string]$Path, [string]$Content) {
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $expectedBytes = $utf8NoBom.GetBytes($Content)
    if ([System.IO.File]::Exists($Path)) {
        $existingInfo = [System.IO.FileInfo]::new($Path)
        if ($existingInfo.Length -eq $expectedBytes.Length) {
            $hashExp = [System.Security.Cryptography.SHA256]::HashData($expectedBytes)
            $hashCur = [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path))
            if ([System.Linq.Enumerable]::SequenceEqual($hashExp, $hashCur)) {
                return $false
            }
        }
    }
    $parent = Split-Path -Parent $Path
    if ($parent -and -not [System.IO.Directory]::Exists($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    [System.IO.File]::WriteAllBytes($Path, $expectedBytes)
    return $true
}

function Sync-ZellijConfigThemeBlock([string]$ConfigPath, [System.Collections.IDictionary]$Theme) {
    if (-not $ConfigPath -or -not [System.IO.File]::Exists($ConfigPath)) { return }
    $raw = ([System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)).Replace("`r`n", "`n")
    $trayBlock = @"
    // BEGIN WINDOWS-SETTINGS TRAY COLORS
    tray_badge_colors {
        needs_you "$($Theme['ORANGE'])"
        failed "$($Theme['RED'])"
        done "$($Theme['GREEN'])"
        working "$($Theme['BLUE'])"
        quiet "$($Theme['BASE01'])"
        new_output "$($Theme['CYAN'])"
    }
    // END WINDOWS-SETTINGS TRAY COLORS
"@.Replace("`r`n", "`n")

    $termBlock = @"
    // BEGIN WINDOWS-SETTINGS TERMINAL THEME
    theme {
        foreground "$($Theme['BASE0'])"
        background "$($Theme['BASE03'])"
        cursor "$($Theme['BASE0'])"
        black "$($Theme['BASE02'])"
        red "$($Theme['RED'])"
        green "$($Theme['GREEN'])"
        yellow "$($Theme['YELLOW'])"
        blue "$($Theme['BLUE'])"
        magenta "$($Theme['MAGENTA'])"
        cyan "$($Theme['CYAN'])"
        white "$($Theme['BASE2'])"
        bright_black "$($Theme['BASE01'])"
        bright_red "$($Theme['ORANGE'])"
        bright_green "$($Theme['BASE01'])"
        bright_yellow "$($Theme['BASE00'])"
        bright_blue "$($Theme['BASE0'])"
        bright_magenta "$($Theme['VIOLET'])"
        bright_cyan "$($Theme['BASE1'])"
        bright_white "$($Theme['BASE3'])"
    }
    // END WINDOWS-SETTINGS TERMINAL THEME
"@.Replace("`r`n", "`n")

    $updated = [regex]::Replace($raw, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TRAY COLORS.*?// END WINDOWS-SETTINGS TRAY COLORS', $trayBlock)
    $updated = [regex]::Replace($updated, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TERMINAL THEME.*?// END WINDOWS-SETTINGS TERMINAL THEME', $termBlock)
    if ($updated -ne $raw) {
        Write-TextUtf8NoBom -Path $ConfigPath -Content $updated
    }
}

function ConvertTo-CleanTerminalJson([object]$Object, [int]$Depth = 16) {
    $rawJson = ($Object | ConvertTo-Json -Depth $Depth).Replace("`r`n", "`n")
    $unescapedPlus = $rawJson.Replace('\u002b', '+').Replace('\u002B', '+')
    return ($unescapedPlus.TrimEnd("`n") + "`n")
}

function Sync-WindowsTerminalTheme([System.Collections.IDictionary]$Theme, [string]$RepoDir) {
    if ($env:THEME_UPDATE_TERMINAL_PROFILE -eq '0' -or -not $env:LOCALAPPDATA) { return }

    # 1. Update deployed Windows Terminal Fragment
    $fragDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\WindowsSettings'
    $fragPath = Join-Path $fragDir 'windows-settings.json'
    $repoFragPath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'terminal') 'windows-settings.json'
    if ([System.IO.File]::Exists($repoFragPath)) {
        try {
            $fragObj = [System.IO.File]::ReadAllText($repoFragPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            $fragObj.profiles.defaults.colorScheme = $Theme['GHOSTTY_THEME_NAME']
            $fragObj.profiles.defaults.cursorColor = $Theme['BASE0']
            $schemeObj = [pscustomobject](ConvertTo-WindowsTerminalScheme -Theme $Theme)
            $updatedSchemes = [System.Collections.Generic.List[object]]::new()
            $replaced = $false
            foreach ($s in @($fragObj.schemes)) {
                if ($s.name -eq $Theme['GHOSTTY_THEME_NAME']) {
                    $updatedSchemes.Add($schemeObj)
                    $replaced = $true
                } else {
                    $updatedSchemes.Add($s)
                }
            }
            if (-not $replaced) {
                $updatedSchemes.Add($schemeObj)
            }
            $fragObj.schemes = $updatedSchemes.ToArray()
            [void](Write-TextIfChanged -Path $fragPath -Content (ConvertTo-CleanTerminalJson -Object $fragObj -Depth 10))
        } catch {
            Write-Verbose "Windows Terminal fragment update skipped: $_"
        }
    }

    # 2. Update active Windows Terminal settings.json if profiles.defaults exists
    $wtCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($wtPath in $wtCandidates) {
        if (-not [System.IO.File]::Exists($wtPath)) { continue }
        try {
            $wtObj = [System.IO.File]::ReadAllText($wtPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($wtObj.profiles -and $wtObj.profiles.defaults) {
                $wtObj.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue $Theme['GHOSTTY_THEME_NAME'] -Force
                $wtObj.profiles.defaults | Add-Member -NotePropertyName cursorColor -NotePropertyValue $Theme['BASE0'] -Force
                $schemesList = [System.Collections.Generic.List[object]]::new()
                if ($wtObj.schemes) {
                    foreach ($s in $wtObj.schemes) {
                        if ($s.name -ne $Theme['GHOSTTY_THEME_NAME']) {
                            $schemesList.Add($s)
                        }
                    }
                }
                $schemesList.Add([pscustomobject](ConvertTo-WindowsTerminalScheme -Theme $Theme))
                $wtObj | Add-Member -NotePropertyName schemes -NotePropertyValue $schemesList.ToArray() -Force
                [void](Write-TextIfChanged -Path $wtPath -Content (ConvertTo-CleanTerminalJson -Object $wtObj -Depth 16))
            }
        } catch {
            Write-Verbose "Windows Terminal settings.json update skipped for ${wtPath}: $_"
        }
    }
}

function Send-LiveOscSequence([System.Collections.IDictionary]$Theme) {
    $forceOsc = ($env:THEME_FORCE_OSC -eq '1')
    $isInteractive = (-not [Console]::IsOutputRedirected) -or $forceOsc
    if (-not $isInteractive -or $env:NO_COLOR) { return }
    $termLc = if ($env:TERM) { $env:TERM.Trim().ToLowerInvariant() } else { '' }
    if ($termLc -in @('dumb', 'linux')) { return }

    $esc = [char]27
    $bel = [char]7
    $ansiList = Get-AnsiPaletteHexList -Theme $Theme
    $sb = [System.Text.StringBuilder]::new(512)
    [void]$sb.Append("${esc}]10;$($Theme['BASE0'])${bel}")
    [void]$sb.Append("${esc}]11;$($Theme['BASE03'])${bel}")
    [void]$sb.Append("${esc}]12;$($Theme['BASE0'])${bel}")
    for ($idx = 0; $idx -lt $ansiList.Count; $idx++) {
        [void]$sb.Append("${esc}]4;${idx};$($ansiList[$idx])${bel}")
    }
    try {
        [Console]::Write($sb.ToString())
    } catch {
        Write-Verbose "OSC sequence write skipped: $_"
    }
}

function Send-LiveNeovimReload {
    if ($env:THEME_LIVE_NVIM -eq '0') { return }
    $nvimCmd = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nvimCmd) { return }
    $nvimExe = $nvimCmd.Source
    if ($nvimExe -match '(?i)[\\/]mise[\\/]shims[\\/]') {
        $miseRoot = Split-Path -Parent (Split-Path -Parent $nvimExe)
        $nvimInstDir = Join-Path (Join-Path $miseRoot 'installs') 'neovim'
        if ([System.IO.Directory]::Exists($nvimInstDir)) {
            $directHit = Get-ChildItem -LiteralPath $nvimInstDir -Filter 'nvim.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($directHit) { $nvimExe = $directHit.FullName }
        }
    }

    $skipPipe = if ($env:THEME_SKIP_NVIM_SOCKET) { $env:THEME_SKIP_NVIM_SOCKET.Trim() } else { '' }
    $pipes = [System.Collections.Generic.List[string]]::new()
    if ($env:THEME_NVIM_SOCKET_DIR -and $env:THEME_NVIM_SOCKET_DIR.Trim()) {
        $sockDir = $env:THEME_NVIM_SOCKET_DIR.Trim()
        if ([System.IO.Directory]::Exists($sockDir)) {
            foreach ($f in (Get-ChildItem -LiteralPath $sockDir -Recurse -File -ErrorAction SilentlyContinue)) {
                if (($f.Name -like '*.sock' -or $f.Name -like 'nvim.*.0') -and -not $pipes.Contains($f.FullName)) {
                    $pipes.Add($f.FullName)
                }
            }
        }
    } else {
        if ($env:NVIM_IDE_SOCKET -and $env:NVIM_IDE_SOCKET.Trim()) {
            $pipes.Add($env:NVIM_IDE_SOCKET.Trim())
        }
        try {
            foreach ($p in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
                if ($p -match '(?i)nvim' -and -not $pipes.Contains($p)) {
                    $pipes.Add($p)
                }
            }
        } catch {
            Write-Verbose "Named pipe scan skipped: $_"
        }
    }

    foreach ($pipe in $pipes) {
        if ($skipPipe -and $pipe -eq $skipPipe) { continue }
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $nvimExe
            $psi.ArgumentList.Add('--headless')
            $psi.ArgumentList.Add('--server')
            $psi.ArgumentList.Add($pipe)
            $psi.ArgumentList.Add('--remote-expr')
            $psi.ArgumentList.Add('v:lua.apply_home_settings_theme()')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($proc) {
                if (-not $proc.WaitForExit(2500)) {
                    try { $proc.Kill() } catch { Write-Verbose 'Kill timed-out nvim rpc skipped' }
                }
            }
        } catch {
            Write-Verbose "Neovim RPC reload skipped on ${pipe}: $_"
        }
    }
}

function Send-LiveZellijReload([System.Collections.IDictionary]$Theme) {
    if ($env:THEME_LIVE_ZELLIJ -eq '0') { return }
    $zellijCmd = Get-Command zellij.exe, zellij -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $zellijCmd) { return }
    $zellijExe = $zellijCmd.Source
    if ($zellijExe -match '(?i)[\\/]mise[\\/]shims[\\/]') {
        $miseRoot = Split-Path -Parent (Split-Path -Parent $zellijExe)
        $zellijInstDir = Join-Path (Join-Path $miseRoot 'installs') 'zellij'
        if ([System.IO.Directory]::Exists($zellijInstDir)) {
            $directHit = Get-ChildItem -LiteralPath $zellijInstDir -Filter 'zellij.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($directHit) { $zellijExe = $directHit.FullName }
        }
    }

    $sessions = [System.Collections.Generic.List[string]]::new()
    if ($env:ZELLIJ_SESSION_NAME -and $env:ZELLIJ_SESSION_NAME.Trim()) {
        $sessions.Add($env:ZELLIJ_SESSION_NAME.Trim())
    }
    try {
        $rawList = @(& $zellijExe list-sessions -n 2>$null)
        if ($LASTEXITCODE -eq 0 -and $rawList.Count -gt 0) {
            foreach ($ln in $rawList) {
                $s = "$ln".Trim()
                if (-not $s -or $s -match '^No active zellij sessions') { continue }
                if ($s -match '^(\S+)\s*(.*)$') {
                    $name = $Matches[1]
                    $rest = $Matches[2]
                    if ($rest -notmatch 'EXITED' -and -not $sessions.Contains($name)) {
                        $sessions.Add($name)
                    }
                }
            }
        }
    } catch {
        Write-Verbose "Zellij session scan skipped: $_"
    }

    $hmeta = Get-HolidayMeta -Theme $Theme
    $hIcon = if ($hmeta) { ([regex]::Replace($hmeta.Icon, '[;\r\n=]', '')).Trim() } else { '' }
    $hBadge = if ($hmeta) { ([regex]::Replace($hmeta.Badge, '[;\r\n=]', '')).Trim() } else { '' }
    $payload = "theme=$($Theme['THEME_ID']);holiday_icon=${hIcon};icon=${hIcon};holiday_badge=${hBadge}"

    foreach ($sess in $sessions) {
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $zellijExe
            $psi.ArgumentList.Add('--session')
            $psi.ArgumentList.Add($sess)
            $psi.ArgumentList.Add('pipe')
            $psi.ArgumentList.Add('--name')
            $psi.ArgumentList.Add('ws-ide-state')
            $psi.ArgumentList.Add('--')
            $psi.ArgumentList.Add($payload)
            $psi.RedirectStandardInput = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($proc) {
                try { $proc.StandardInput.Close() } catch { Write-Verbose 'zellij pipe stdin close skipped' }
                if (-not $proc.WaitForExit(1500)) {
                    try { $proc.Kill($true) } catch { Write-Verbose 'Kill timed-out zellij pipe skipped' }
                }
            }
        } catch {
            Write-Verbose "Zellij theme pipe skipped on ${sess}: $_"
        }
    }
}

function Sync-BatThemeCollection([System.Collections.IDictionary]$Theme, [string]$RepoDir, [string]$BatConfigDir) {
    $batThemesDir = Join-Path $BatConfigDir 'themes'
    New-Item -ItemType Directory -Force -Path $batThemesDir | Out-Null
    $needBatRebuild = $false

    $repoBatDir = Join-Path (Join-Path $RepoDir 'config') 'bat'
    $baseTmPath = Join-Path $repoBatDir 'Solarized-Dark-TrueColor.tmTheme'
    $repoBatThemes = Join-Path $repoBatDir 'themes'

    if ([System.IO.Directory]::Exists($repoBatThemes)) {
        foreach ($srcTm in [System.IO.Directory]::GetFiles($repoBatThemes, '*.tmTheme')) {
            $dstTm = Join-Path $batThemesDir ([System.IO.Path]::GetFileName($srcTm))
            if (-not (Test-FileByteEqual -PathA $srcTm -PathB $dstTm)) {
                Copy-Item -LiteralPath $srcTm -Destination $dstTm -Force
                $needBatRebuild = $true
            }
        }
    }

    $targetTmName = "$($Theme['BAT_THEME_NAME']).tmTheme"
    $targetTmFile = Join-Path $batThemesDir $targetTmName
    $repoTargetTm = Join-Path $repoBatThemes $targetTmName
    if ($Theme['SOURCE'] -eq 'user' -or -not [System.IO.File]::Exists($repoTargetTm)) {
        if ([System.IO.File]::Exists($baseTmPath)) {
            $baseTmRaw = [System.IO.File]::ReadAllText($baseTmPath, [System.Text.Encoding]::UTF8)
            $renderedTm = Build-TmThemeText -BaseTmThemeText $baseTmRaw -Theme $Theme
            Write-TextUtf8NoBom -Path $targetTmFile -Content $renderedTm
            $needBatRebuild = $true
        }
    }

    $batConfigFile = Join-Path $BatConfigDir 'config'
    $targetBatThemeLine = "--theme=`"$($Theme['BAT_THEME_NAME'])`""
    if ([System.IO.File]::Exists($batConfigFile)) {
        $existingBatCfg = [System.IO.File]::ReadAllText($batConfigFile, [System.Text.Encoding]::UTF8)
        if ($existingBatCfg -notmatch '--theme=') {
            Write-TextUtf8NoBom -Path $batConfigFile -Content ($existingBatCfg.TrimEnd() + "`n$targetBatThemeLine`n")
        } elseif ($existingBatCfg -notmatch [regex]::Escape($targetBatThemeLine)) {
            $updatedBatCfg = [regex]::Replace($existingBatCfg, '--theme=\S+', $targetBatThemeLine)
            Write-TextUtf8NoBom -Path $batConfigFile -Content $updatedBatCfg
        }
    } else {
        Write-TextUtf8NoBom -Path $batConfigFile -Content "$targetBatThemeLine`n"
    }

    if (-not $needBatRebuild) {
        $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
        $cacheCandidates = [System.Collections.Generic.List[string]]::new()
        if ($env:BAT_CACHE_PATH -and $env:BAT_CACHE_PATH.Trim()) {
            $cacheCandidates.Add((Join-Path $env:BAT_CACHE_PATH.Trim() 'themes.bin'))
        }
        if ($env:LOCALAPPDATA) {
            $cacheCandidates.Add((Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'bat') 'cache') 'themes.bin'))
        }
        if ($env:XDG_CACHE_HOME -and $env:XDG_CACHE_HOME.Trim()) {
            $cacheCandidates.Add((Join-Path (Join-Path $env:XDG_CACHE_HOME.Trim() 'bat') 'themes.bin'))
        }
        if ($userHome) {
            $cacheCandidates.Add((Join-Path (Join-Path (Join-Path $userHome '.cache') 'bat') 'themes.bin'))
        }
        $existingBins = @($cacheCandidates | Where-Object { [System.IO.File]::Exists($_) })
        if ($existingBins.Count -eq 0) {
            $needBatRebuild = $true
        } else {
            $cacheTicks = [System.IO.File]::GetLastWriteTimeUtc($existingBins[0]).Ticks
            foreach ($tmPath in [System.IO.Directory]::GetFiles($batThemesDir, '*.tmTheme')) {
                if ([System.IO.File]::GetLastWriteTimeUtc($tmPath).Ticks -gt $cacheTicks) {
                    $needBatRebuild = $true
                    break
                }
            }
        }
    }

    if ($needBatRebuild) {
        $batCmd = Get-Command bat.exe, bat -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($batCmd) {
            try { & $batCmd.Source cache --build *> $null } catch { Write-Verbose 'bat cache rebuild skipped' }
        }
    }
}

function Sync-BtopThemeCollection([System.Collections.IDictionary]$Theme, [string]$RepoDir, [string]$CfgDir) {
    $btopXdgDir = Join-Path $CfgDir 'btop'
    $btopThemesDir = Join-Path $btopXdgDir 'themes'
    New-Item -ItemType Directory -Force -Path $btopThemesDir | Out-Null

    $repoBtopDir = Join-Path (Join-Path $RepoDir 'config') 'btop'
    $repoBtopConf = Join-Path $repoBtopDir 'btop.conf'
    $repoBtopThemesDir = Join-Path $repoBtopDir 'themes'

    if ([System.IO.Directory]::Exists($repoBtopThemesDir)) {
        foreach ($btFile in [System.IO.Directory]::GetFiles($repoBtopThemesDir, '*.theme')) {
            $btDst = Join-Path $btopThemesDir ([System.IO.Path]::GetFileName($btFile))
            if (-not (Test-FileByteEqual -PathA $btFile -PathB $btDst)) {
                Copy-Item -LiteralPath $btFile -Destination $btDst -Force
            }
        }
    }

    $targetBtopFileName = "$($Theme['BTOP_THEME_NAME']).theme"
    $targetBtopTheme = Join-Path $btopThemesDir $targetBtopFileName
    $repoTargetBtop = Join-Path $repoBtopThemesDir $targetBtopFileName
    if ($Theme['SOURCE'] -eq 'user' -or -not [System.IO.File]::Exists($repoTargetBtop)) {
        Write-TextUtf8NoBom -Path $targetBtopTheme -Content (Build-BtopThemeText -Theme $Theme)
    }

    if ([System.IO.File]::Exists($repoBtopConf)) {
        $rawBtop = [System.IO.File]::ReadAllText($repoBtopConf, [System.Text.Encoding]::UTF8)
        $updatedBtop = [regex]::Replace($rawBtop, '(?m)^color_theme\s*=\s*"[^"]*"', "color_theme = `"$($Theme['BTOP_THEME_NAME'])`"")
        $updatedBtop = [regex]::Replace($updatedBtop, '(?m)^cpu_graph_upper\s*=\s*"Auto"', 'cpu_graph_upper = "total"')
        $updatedBtop = [regex]::Replace($updatedBtop, '(?m)^cpu_graph_lower\s*=\s*"Auto"', 'cpu_graph_lower = "gpu"')
        [void](Write-TextIfChanged -Path (Join-Path $btopXdgDir 'btop.conf') -Content $updatedBtop)

        if ($env:LOCALAPPDATA) {
            $wingetPkgsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            if ([System.IO.Directory]::Exists($wingetPkgsRoot)) {
                foreach ($wdirPath in [System.IO.Directory]::GetDirectories($wingetPkgsRoot, 'aristocratos.btop4win*')) {
                    $directB4w = Join-Path $wdirPath 'btop4win\btop4win.exe'
                    $b4wRoot = if ([System.IO.File]::Exists($directB4w)) {
                        Split-Path -Parent $directB4w
                    } else {
                        $exeHit = Get-ChildItem -LiteralPath $wdirPath -Filter 'btop4win.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exeHit) { $exeHit.DirectoryName } else { '' }
                    }
                    if ($b4wRoot) {
                        $b4wThemes = Join-Path $b4wRoot 'themes'
                        if (-not [System.IO.Directory]::Exists($b4wThemes)) {
                            New-Item -ItemType Directory -Force -Path $b4wThemes -ErrorAction SilentlyContinue | Out-Null
                        }
                        foreach ($srcBt in [System.IO.Directory]::GetFiles($btopThemesDir, '*.theme')) {
                            $dstBt = Join-Path $b4wThemes ([System.IO.Path]::GetFileName($srcBt))
                            $isCustomActive = ($Theme['SOURCE'] -eq 'user' -and [System.IO.Path]::GetFileName($srcBt) -eq $targetBtopFileName)
                            if ($isCustomActive -or -not (Test-FileByteEqual -PathA $srcBt -PathB $dstBt)) {
                                Copy-Item -LiteralPath $srcBt -Destination $dstBt -Force -ErrorAction SilentlyContinue
                            }
                        }
                        try {
                            [void](Write-TextIfChanged -Path (Join-Path $b4wRoot 'btop.conf') -Content $updatedBtop)
                        } catch {
                            Write-Verbose "btop4win conf update skipped: $_"
                        }
                    }
                }
            }
        }
    }
}

function Clear-StaleOhMyPoshSessionCache([string]$OmpConfigPath) {
    if (Get-Command Sync-OhMyPoshPromptCache -ErrorAction SilentlyContinue) {
        try { Sync-OhMyPoshPromptCache } catch { Write-Verbose "Oh My Posh sync skipped: $_" }
        return
    }
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $oldSessionId = $env:POSH_SESSION_ID
    if ($oldSessionId) {
        $ompDirs = [System.Collections.Generic.List[string]]::new()
        if ($env:LOCALAPPDATA) {
            $d1 = Join-Path $env:LOCALAPPDATA 'oh-my-posh'
            if ([System.IO.Directory]::Exists($d1)) { $ompDirs.Add($d1) }
            $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
            if ([System.IO.Directory]::Exists($pkgRoot)) {
                foreach ($pkgDir in [System.IO.Directory]::GetDirectories($pkgRoot, 'ohmyposh.cli_*')) {
                    $d2 = Join-Path $pkgDir 'LocalCache\Local\oh-my-posh'
                    if ([System.IO.Directory]::Exists($d2)) { $ompDirs.Add($d2) }
                }
            }
        }
        if ($userHome) {
            $d3 = Join-Path (Join-Path $userHome '.cache') 'oh-my-posh'
            if ([System.IO.Directory]::Exists($d3)) { $ompDirs.Add($d3) }
        }
        foreach ($cDir in $ompDirs) {
            $staleCache = Join-Path $cDir "pwsh.$oldSessionId.omp.cache"
            if ([System.IO.File]::Exists($staleCache)) {
                try { [System.IO.File]::Delete($staleCache) } catch { $null = $_ }
            }
        }
    }
    if ([System.IO.File]::Exists($OmpConfigPath)) {
        $env:POSH_CONFIG = $OmpConfigPath
    }
    $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
    $streamState = Get-Variable -Name _ompStreamingState -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $streamState) {
        try {
            if ($null -ne $streamState.StdIn) {
                try {
                    $streamState.StdIn.WriteLine('{"command":"quit"}')
                    $streamState.StdIn.Write([char]0)
                    $streamState.StdIn.Flush()
                    $streamState.StdIn.Close()
                } catch { $null = $_ }
            }
            if ($null -ne $streamState.ServeProcess -and -not $streamState.ServeProcess.HasExited) {
                try { $streamState.ServeProcess.Kill() } catch { $null = $_ }
            }
            $streamState.ServeProcess = $null
            $streamState.StdIn = $null
            $streamState.FailureCount = 0
            $streamState.CycleStarted = $false
            $streamState.Prompt = ''
            $streamState.Transient = ''
            $streamState.Dirty = $false
            $streamState.State = 'NEW'
        } catch {
            $null = $_
        }
    }
}

function Invoke-ApplyTheme(
    [System.Collections.IDictionary]$Theme,
    [string]$RepoDir,
    [bool]$DryRun = $false,
    [bool]$NoLive = $false
) {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cfgDir = Get-XdgConfigHome
    $hsStateDir = Join-Path $cfgDir 'home-settings'
    $wsStateDir = Join-Path $cfgDir 'windows-settings'
    $psCacheDir = Join-Path (Join-Path $userHome '.cache') 'powershell'
    $batConfigDir = if ($env:BAT_CONFIG_DIR -and $env:BAT_CONFIG_DIR.Trim()) {
        $env:BAT_CONFIG_DIR.Trim()
    } elseif ($env:APPDATA) {
        Join-Path $env:APPDATA 'bat'
    } else {
        Join-Path $cfgDir 'bat'
    }
    $batThemesDir = Join-Path $batConfigDir 'themes'
    $tealdeerDir = if ($env:APPDATA) { Join-Path $env:APPDATA 'tealdeer' } else { Join-Path $cfgDir 'tealdeer' }
    $zellijConfigDir = if ($env:ZELLIJ_CONFIG_DIR -and $env:ZELLIJ_CONFIG_DIR.Trim()) {
        $env:ZELLIJ_CONFIG_DIR.Trim()
    } elseif ($env:APPDATA) {
        Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
    } else {
        Join-Path $cfgDir 'zellij'
    }
    $zellijThemePath = Join-Path (Join-Path $zellijConfigDir 'themes') 'windows-settings.kdl'
    $ompDest = Join-Path (Join-Path $userHome '.poshthemes') 'p10k_single_line.omp.json'
    $cmdThemeEnv = if ($env:LOCALAPPDATA) { Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'theme_env.cmd' } else { Join-Path $wsStateDir 'theme_env.cmd' }

    if ($DryRun) {
        Write-Output "[DRY-RUN] Theme: $($Theme['THEME_LABEL']) ($($Theme['THEME_ID']), mode=$($Theme['THEME_MODE']), source=$($Theme['SOURCE']))"
        Write-Output "[DRY-RUN] Would write active state: $(Join-Path $wsStateDir 'theme') & $(Join-Path $hsStateDir 'theme')"
        Write-Output "[DRY-RUN] Would write active palette: $(Join-Path $wsStateDir 'active-theme.theme') & $(Join-Path $hsStateDir 'active-theme.theme')"
        Write-Output "[DRY-RUN] Would write PowerShell cache: $(Join-Path $psCacheDir 'theme_env.ps1')"
        Write-Output "[DRY-RUN] Would write CMD theme hook: $cmdThemeEnv"
        Write-Output "[DRY-RUN] Would update Oh My Posh theme: $ompDest"
        Write-Output "[DRY-RUN] Would update Zellij theme: $zellijThemePath"
        Write-Output "[DRY-RUN] Would update Git delta config ($($Theme['BAT_THEME_NAME'])): $(Join-Path (Join-Path $cfgDir 'git') 'delta-theme.gitconfig')"
        Write-Output "[DRY-RUN] Would update tealdeer config: $(Join-Path $tealdeerDir 'config.toml')"
        Write-Output "[DRY-RUN] Would ensure bat theme: $(Join-Path $batThemesDir "$($Theme['BAT_THEME_NAME']).tmTheme")"
        Write-Output "[DRY-RUN] Would update Windows Terminal scheme ($($Theme['GHOSTTY_THEME_NAME'])) and broadcast Neovim RPC / Zellij / OSC palette"
        $script:ThemeExitCode = 0
        return
    }

    $activeSnapshot = Build-ActiveThemeText -Theme $Theme
    foreach ($sdir in @($wsStateDir, $hsStateDir)) {
        Write-TextUtf8NoBom -Path (Join-Path $sdir 'theme') -Content "$($Theme['THEME_ID'])`n"
        Write-TextUtf8NoBom -Path (Join-Path $sdir 'active-theme.theme') -Content $activeSnapshot
    }

    $psEnvText = Build-PowerShellThemeEnv -Theme $Theme -RepoDir $RepoDir
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'theme-env.ps1') -Content $psEnvText
    Write-TextUtf8NoBom -Path (Join-Path $psCacheDir 'theme_env.ps1') -Content $psEnvText

    $ideScriptPath = Join-Path (Join-Path $RepoDir 'bin') 'ide.ps1'
    if ([System.IO.File]::Exists($ideScriptPath)) {
        try {
            . (Join-Path $psCacheDir 'theme_env.ps1')
            & $ideScriptPath _internal write-keys-cache *> $null
        } catch {
            Write-Verbose "IDE cheatsheet cache refresh skipped: $_"
        }
    }

    $cmdEnvText = Build-CmdThemeEnv -Theme $Theme -RepoDir $RepoDir
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'theme_env.cmd') -Content $cmdEnvText
    Write-TextUtf8NoBom -Path $cmdThemeEnv -Content $cmdEnvText

    $deltaText = Build-DeltaGitConfig -Theme $Theme
    Write-TextUtf8NoBom -Path (Join-Path (Join-Path $cfgDir 'git') 'delta-theme.gitconfig') -Content $deltaText
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'delta-theme.gitconfig') -Content $deltaText
    Write-TextUtf8NoBom -Path (Join-Path $hsStateDir 'delta-theme.gitconfig') -Content $deltaText

    Write-TextUtf8NoBom -Path (Join-Path $tealdeerDir 'config.toml') -Content (Build-TealdeerConfig -Theme $Theme)

    $zellijKdlText = Build-ZellijThemeKdl -Theme $Theme
    Write-TextUtf8NoBom -Path $zellijThemePath -Content $zellijKdlText
    Sync-ZellijConfigThemeBlock -ConfigPath (Join-Path $zellijConfigDir 'config.kdl') -Theme $Theme
    $xdgZellijDir = Join-Path $cfgDir 'zellij'
    if ($xdgZellijDir -ne $zellijConfigDir -and [System.IO.Directory]::Exists($xdgZellijDir)) {
        Write-TextUtf8NoBom -Path (Join-Path (Join-Path $xdgZellijDir 'themes') 'windows-settings.kdl') -Content $zellijKdlText
        Sync-ZellijConfigThemeBlock -ConfigPath (Join-Path $xdgZellijDir 'config.kdl') -Theme $Theme
    }

    Sync-BtopThemeCollection -Theme $Theme -RepoDir $RepoDir -CfgDir $cfgDir

    $repoOmp = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'powershell') 'p10k_single_line.omp.json'
    if ([System.IO.File]::Exists($repoOmp)) {
        $rawOmp = [System.IO.File]::ReadAllText($repoOmp, [System.Text.Encoding]::UTF8)
        $remappedOmp = Convert-SolarizedHexString -InputText $rawOmp -Theme $Theme -Lowercase $true
        Write-TextUtf8NoBom -Path $ompDest -Content $remappedOmp
        $ompInitPath = Join-Path $psCacheDir 'omp_init.ps1'
        $needOmpInit = -not [System.IO.File]::Exists($ompInitPath)
        if (-not $needOmpInit) {
            $cachedOmpText = [System.IO.File]::ReadAllText($ompInitPath, [System.Text.Encoding]::UTF8)
            if ($cachedOmpText -notmatch 'Enable-PoshStreaming') {
                $needOmpInit = $true
            }
        }
        if ($needOmpInit) {
            $ompCmd = Get-Command oh-my-posh.exe, oh-my-posh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ompCmd) {
                try {
                    $ompInit = (& $ompCmd.Source init pwsh --config $ompDest --print) -join "`r`n"
                    if ($ompInit) {
                        Write-TextUtf8NoBom -Path $ompInitPath -Content ($ompInit + "`r`n")
                    }
                } catch {
                    Write-Verbose "Oh My Posh cache rebuild skipped: $_"
                }
            }
        }
    }

    Sync-BatThemeCollection -Theme $Theme -RepoDir $RepoDir -BatConfigDir $batConfigDir

    $psEnvCacheFile = Join-Path $psCacheDir 'theme_env.ps1'
    if ([System.IO.File]::Exists($psEnvCacheFile)) {
        try { . $psEnvCacheFile } catch { Write-Verbose "In-process theme_env load skipped: $_" }
    }
    if (Get-Command Sync-PSReadLineThemePalette -ErrorAction SilentlyContinue) {
        try { Sync-PSReadLineThemePalette } catch { Write-Verbose "PSReadLine palette sync skipped: $_" }
    }
    Clear-StaleOhMyPoshSessionCache -OmpConfigPath $ompDest

    if (-not $NoLive) {
        Sync-WindowsTerminalTheme -Theme $Theme -RepoDir $RepoDir
        Send-LiveOscSequence -Theme $Theme
        Send-LiveNeovimReload
        Send-LiveZellijReload -Theme $Theme
    }

    Write-Output "Applied theme: $($Theme['THEME_LABEL']) ($($Theme['THEME_ID']))"
    $script:ThemeExitCode = 0
}
