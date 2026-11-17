# ==============================================================================
# Modals.ps1 - Floating Zellij modals, TrueColor cheatsheet & TUI system monitor
# ==============================================================================

function Enter-ZellijFloatingModal([string]$ModalName, [string]$X = '5%', [string]$Y = '5%', [string]$Width = '90%', [string]$Height = '90%') {
    if (-not $env:ZELLIJ) { return '' }
    $zellijBin = Resolve-ZellijExecutable
    $rawSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME } elseif ($env:IDE_SESSION) { $env:IDE_SESSION } else { 'default' }
    $sess = Get-SanitizedToken $rawSess
    $curPaneId = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
    $modalFile = Join-Path (Get-IdeStateDir) ("modal-{0}-{1}.json" -f $ModalName, $sess)

    if (Test-Path -LiteralPath $modalFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $modalFile -Raw | ConvertFrom-Json
            $oldPid = if ($saved -and $saved.pid) { [int]$saved.pid } else { 0 }
            $oldPaneId = if ($saved -and $saved.paneId) { "$($saved.paneId)".Trim() } else { '' }
            if ($oldPid -gt 0 -and $oldPid -ne $PID) {
                $alive = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
                if ($alive) {
                    Remove-Item -LiteralPath $modalFile -Force -ErrorAction SilentlyContinue
                    if ($zellijBin -and $oldPaneId) {
                        & $zellijBin action close-pane --pane-id $oldPaneId *> $null
                    }
                    try {
                        Get-CimInstance Win32_Process -Filter "ParentProcessId = $oldPid" -ErrorAction SilentlyContinue | ForEach-Object {
                            Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
                        }
                    } catch {
                        Write-Verbose "Child process cleanup skipped: $_"
                    }
                    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                    exit 0
                }
            }
        } catch {
            Write-Verbose "Stale modal state ignored: $_"
        }
    }

    if ($env:IDE_MODAL_SIZED -ne '1' -and $zellijBin -and $curPaneId) {
        & $zellijBin action change-floating-pane-coordinates --pane-id $curPaneId --x $X --y $Y --width $Width --height $Height *> $null
    }
    $payload = @{ pid = $PID; paneId = $curPaneId } | ConvertTo-Json -Compress
    Write-TextUtf8NoBom -Path $modalFile -Content $payload
    return $modalFile
}

function Exit-ZellijFloatingModal([string]$ModalFile) {
    if (-not $ModalFile -or -not (Test-Path -LiteralPath $ModalFile -PathType Leaf)) { return }
    try {
        $saved = Get-Content -LiteralPath $ModalFile -Raw | ConvertFrom-Json
        if ($saved -and ([int]$saved.pid) -eq $PID) {
            Remove-Item -LiteralPath $ModalFile -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Remove-Item -LiteralPath $ModalFile -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-ToggleZellijModal([string]$ModalName) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $env:ZELLIJ -or -not $zellijBin) {
        if ($ModalName -eq 'keys') { Show-IdeKeysCheatsheet; exit 0 }
        if ($ModalName -eq 'sessions') { Invoke-SessionSwitcher; exit 0 }
        Invoke-SystemMonitor
    }

    $canUseBatchFastToggle = ($ModalName -in @('sessions', 'keys')) -or ($ModalName -eq 'monitor' -and $env:IDE_FORCE_BUILTIN_MONITOR -ne '1')
    if ($canUseBatchFastToggle) {
        $ideCmd = Get-IdeBatchScriptPath
        if (Test-Path -LiteralPath $ideCmd -PathType Leaf) {
            & cmd.exe /d /c $ideCmd "--toggle-$ModalName" *> $null
            exit 0
        }
    }

    $rawSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME } elseif ($env:IDE_SESSION) { $env:IDE_SESSION } else { 'default' }
    $sess = Get-SanitizedToken $rawSess
    $modalFile = Join-Path (Get-IdeStateDir) ("modal-{0}-{1}.json" -f $ModalName, $sess)

    if (Test-Path -LiteralPath $modalFile -PathType Leaf) {
        try {
            $saved = Get-Content -LiteralPath $modalFile -Raw | ConvertFrom-Json
            $oldPid = if ($saved -and $saved.pid) { [int]$saved.pid } else { 0 }
            $oldPaneId = if ($saved -and $saved.paneId) { "$($saved.paneId)".Trim() } else { '' }
            if ($oldPid -gt 0) {
                $alive = Get-Process -Id $oldPid -ErrorAction SilentlyContinue
                if ($alive) {
                    Remove-Item -LiteralPath $modalFile -Force -ErrorAction SilentlyContinue
                    if ($oldPaneId) {
                        & $zellijBin action close-pane --pane-id $oldPaneId *> $null
                    }
                    Stop-Process -Id $oldPid -Force -ErrorAction SilentlyContinue
                    exit 0
                }
            }
        } catch {
            Write-Verbose "Stale modal state ignored: $_"
        }
        Remove-Item -LiteralPath $modalFile -Force -ErrorAction SilentlyContinue
    }

    $pwshBin = Get-CurrentPwshExecutable
    $entryScript = Get-IdeEntryScriptPath
    $env:IDE_MODAL_SIZED = '1'
    if ($ModalName -eq 'keys') {
        & $zellijBin action new-pane --floating --close-on-exit -x 6% -y 10% --width 88% --height 80% --name 'Keybindings' -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $entryScript --keys *> $null
    } elseif ($ModalName -eq 'sessions') {
        $env:IDE_SESSIONS_MODAL = '1'
        & $zellijBin action new-pane --floating --close-on-exit -x 5% -y 8% --width 90% --height 84% --name 'IDE Fleet Switcher' -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $entryScript --sessions *> $null
    } else {
        & $zellijBin action new-pane --floating --close-on-exit -x 5% -y 5% --width 90% --height 90% --name 'System Monitor' -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $entryScript --monitor *> $null
    }
    exit 0
}

function Get-IdeKeysCheatsheetText {
    $pal = Get-ActivePaletteMap
    $rule = "`u{2500}" * 98

    $sections = @(
        @{
            LeftHeader  = 'PANES & ROLES (Zellij Layer 2)'
            RightHeader = 'SESSIONS & ATTENTION INBOX'
            Rows        = @(
                @('Alt+h / j / k / l', 'Move focus between panes', 'Alt+s / Space s', 'IDE Fleet Switcher & Preview'),
                @('Alt+a / e / t', 'Jump/bounce AI/Editor/Shell', 'Alt+Shift+S', 'Jump to Next Attention'),
                @('Alt+Shift+E / T', 'Hide/restore Editor / Shell', 'Alt+[ / Alt+]', 'Prev / next IDE session'),
                @('Alt+z / Alt+f', 'Zoom 100% / Floating drawer', 'Ctrl+b d', 'Detach (agents keep running)'),
                @('Alt+Arrows', 'Resize active pane', 'ide -d [dir]', 'Spawn detached session'),
                @('Alt+Shift+H/J/K/L', 'Move / swap active pane', 'ide --desktop', 'Standalone 1-Hop GPU window'),
                @('Alt+? / Alt+m', 'Toggle keys / system monitor', ':Q / Alt+q / qide', 'Safe-quit IDE (checks saves)'),
                @('Right-click bar/pane', 'IDE workspace context menu', 'Ctrl+b r / b', 'Refresh all / toggle top bar')
            )
        },
        @{
            LeftHeader  = 'EDITOR (Space = Leader)'
            RightHeader = 'CLIPBOARD & LINKS'
            Rows        = @(
                @('Space ff', 'Find files by name', 'Mouse drag / 2x', 'Select text and auto-copy'),
                @('Space fg', 'Search text (live grep)', 'Alt+c', 'Copy & clear highlight'),
                @('Space gs', 'Review Git status', 'Alt+v', 'Paste from clipboard'),
                @('Space m', 'Toggle Markdown preview', 'Ctrl+Click', 'Open URL, #heading, or file'),
                @('H / L  (Normal)', 'Prev / next buffer', 'Alt+Click', 'Jump to LSP definition'),
                @('Home   (Any mode)', 'Smart-Home (^ / col 1)', 'Mouse4/5 or C-o/i', 'Jump back or forward')
            )
        },
        @{
            LeftHeader  = 'FILE TREE (mini.files)'
            RightHeader = 'DIRECT AI PASTE & THEMES'
            Rows        = @(
                @('Space e / Space E', 'Open mini.files tree', 'Space a  (Visual)', 'Paste selected ref into AI'),
                @('h/l or Left/Right', 'Parent dir / open item', 'Space il (Normal)', 'Paste current line ref to AI'),
                @('Enter  (in tree)', 'Open file or enter dir', 'Space id (Normal)', 'Paste buffer diagnostics'),
                @('=      (in tree)', 'Apply file edits', ':IdeSend[!] [ws]', 'Paste selection to session'),
                @('g? / q (in tree)', 'Tree help / close tree', ':Theme [slug]', 'Live-switch 17 color themes')
            )
        }
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add(("  {0}`u{EBC8} IDE Workspace & Agent Fleet Keybindings (Zellij 0.46+ + Neovim){1}                [Any key / Alt+?]{2}" -f $pal.E_ORG, $pal.E_B01, $pal.E_RST))
    $lines.Add(("  {0}{1}{2}" -f $pal.E_B01, $rule, $pal.E_RST))

    for ($sIdx = 0; $sIdx -lt $sections.Count; $sIdx++) {
        if ($sIdx -gt 0) { $lines.Add('') }
        $sec = $sections[$sIdx]
        $lines.Add(("  {0}{1,-51}{2}{3}{4}" -f $pal.E_BLU, $sec.LeftHeader, $pal.E_BLU, $sec.RightHeader, $pal.E_RST))
        foreach ($r in $sec.Rows) {
            $lines.Add(("  {0}{1,-20}{2} {3,-28}  {4}{5,-18}{6} {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
        }
    }
    return ,$lines.ToArray()
}

function Write-IdeKeysCheatsheetCache {
    $esc = [char]27
    $lines = Get-IdeKeysCheatsheetText
    $stateDir = Get-IdeStateDir
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    }
    $cachePath = Join-Path $stateDir 'keys-cheatsheet.ans'
    $payload = "${esc}[?25l" + ($lines -join "`r`n")
    # UTF-16LE with BOM lets cmd.exe's built-in `type` call WriteConsoleW directly
    # without spawning chcp.com or corrupting box-drawing and Nerd Font glyphs under OEM codepages.
    $utf16LeBom = [System.Text.UnicodeEncoding]::new($false, $true)
    [System.IO.File]::WriteAllText($cachePath, $payload, $utf16LeBom)

    if (Get-Command Write-Osc7501CacheSet -CommandType Function -ErrorAction SilentlyContinue) {
        Write-Osc7501CacheSet -StateDir $stateDir
    }
}

function Show-IdeKeysCheatsheet {
    $modalFile = ''
    if ($env:IDE_KEYS_NO_WAIT -ne '1') {
        $modalFile = Enter-ZellijFloatingModal -ModalName 'keys' -X '6%' -Y '10%' -Width '88%' -Height '80%'
    }
    try {
        foreach ($ln in (Get-IdeKeysCheatsheetText)) {
            Write-Output $ln
        }

        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and $env:IDE_KEYS_NO_WAIT -ne '1') {
            try {
                while ($true) {
                    $keyInfo = [Console]::ReadKey($true)
                    if ($keyInfo.Key -in @([ConsoleKey]::Q, [ConsoleKey]::Escape, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter)) {
                        break
                    }
                }
            } catch {
                Write-Verbose "Interactive key wait skipped: $_"
            }
        }
    } finally {
        Exit-ZellijFloatingModal -ModalFile $modalFile
    }
}

function Resolve-SystemMonitorExecutable {
    if ($env:IDE_FORCE_BUILTIN_MONITOR -eq '1') { return '' }

    if ($env:LOCALAPPDATA) {
        $wingetPkgs = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
        if (Test-Path -LiteralPath $wingetPkgs -PathType Container) {
            $b4wDirs = @(Get-ChildItem -LiteralPath $wingetPkgs -Directory -Filter 'aristocratos.btop4win*' -ErrorAction SilentlyContinue)
            foreach ($d in $b4wDirs) {
                $hit = Get-ChildItem -LiteralPath $d.FullName -Filter 'btop4win.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($hit) { return $hit.FullName }
            }
        }
    }

    foreach ($mon in @('btop4win.exe', 'btop4win', 'btop.exe', 'btm.exe', 'btm', 'ntop.exe', 'ntop')) {
        $cmd = Get-Command $mon -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source) {
            try {
                $item = Get-Item -LiteralPath $cmd.Source -Force -ErrorAction SilentlyContinue
                if ($item -and $item.Target) {
                    $tgt = @($item.Target)[0]
                    if ($tgt -and (Test-Path -LiteralPath $tgt -PathType Leaf)) {
                        return $tgt
                    }
                }
            } catch {
                Write-Verbose "Symlink resolution skipped: $_"
            }
            return $cmd.Source
        }
    }

    $userHome = Get-UserHomeDir
    foreach ($candidate in @(
        (Join-Path $userHome 'scoop\apps\btop\current\btop.exe'),
        (Join-Path $env:ProgramFiles 'btop4win\btop4win.exe')
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }
    return ''
}

function Format-MonitorBar([double]$Percent, [int]$BarWidth, [hashtable]$Pal) {
    $clamped = [Math]::Max(0.0, [Math]::Min(100.0, $Percent))
    $filled = [int][Math]::Round(($clamped / 100.0) * $BarWidth)
    $empty = [Math]::Max(0, $BarWidth - $filled)
    $accent = if ($clamped -ge 85.0) { $Pal.E_RED } elseif ($clamped -ge 65.0) { $Pal.E_YLW } else { $Pal.E_GRN }
    $fillStr = "`u{2588}" * $filled
    $emptyStr = "`u{2591}" * $empty
    return ("{0}{1}{2}{3}{4}" -f $accent, $fillStr, $Pal.E_B01, $emptyStr, $Pal.E_RST)
}

function Show-BuiltinSystemMonitor {
    $pal = Get-ActivePaletteMap
    $esc = [char]27
    $eol = "${esc}[K"
    $isSingleShot = ($env:IDE_MONITOR_ONCE -eq '1') -or (-not [Environment]::UserInteractive) -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected

    if (-not $isSingleShot) {
        [Console]::Write("${esc}[?1049h${esc}[?25l${esc}[2J")
    }
    try {
        while ($true) {
            $cpuPct = 0.0
            try {
                $cpus = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
                if ($cpus.Count -gt 0) {
                    $cpuPct = [double](($cpus | Measure-Object -Property LoadPercentage -Average).Average)
                }
            } catch { Write-Verbose "CPU query skipped: $_" }

            $memUsedGb = 0.0
            $memTotalGb = 1.0
            $memPct = 0.0
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
                if ($os -and $os.TotalVisibleMemorySize -gt 0) {
                    $memTotalGb = [Math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
                    $memFreeGb = [Math]::Round($os.FreePhysicalMemory / 1MB, 1)
                    $memUsedGb = [Math]::Round($memTotalGb - $memFreeGb, 1)
                    $memPct = (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) * 100.0) / $os.TotalVisibleMemorySize
                }
            } catch { Write-Verbose "Memory query skipped: $_" }

            $diskName = if ($env:SystemDrive) { $env:SystemDrive.TrimEnd(':') } else { 'C' }
            $diskUsedGb = 0.0
            $diskTotalGb = 1.0
            $diskPct = 0.0
            try {
                $drv = Get-PSDrive -Name $diskName -ErrorAction SilentlyContinue
                if ($drv -and ($drv.Used + $drv.Free) -gt 0) {
                    $totalBytes = [double]($drv.Used + $drv.Free)
                    $diskTotalGb = [Math]::Round($totalBytes / 1GB, 1)
                    $diskUsedGb = [Math]::Round($drv.Used / 1GB, 1)
                    $diskPct = ($drv.Used * 100.0) / $totalBytes
                }
            } catch { Write-Verbose "Disk query skipped: $_" }

            $procs = @(Get-Process -ErrorAction SilentlyContinue | Sort-Object WorkingSet64 -Descending | Select-Object -First 14)
            $rule = "`u{2500}" * 78
            $cpuBar = Format-MonitorBar -Percent $cpuPct -BarWidth 28 -Pal $pal
            $memBar = Format-MonitorBar -Percent $memPct -BarWidth 28 -Pal $pal
            $dskBar = Format-MonitorBar -Percent $diskPct -BarWidth 28 -Pal $pal
            $nowStr = (Get-Date).ToString('HH:mm:ss')

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add('')
            $lines.Add(("  {0}System Monitor{1}  ({2}){3}  [q / Esc / Alt+m to close]{4}" -f $pal.E_ORG, $pal.E_B01, $nowStr, $pal.E_B01, $pal.E_RST))
            $lines.Add(("  {0}{1}{2}" -f $pal.E_B01, $rule, $pal.E_RST))
            $lines.Add(("  {0}CPU  {1} [{2}] {3}{4,5:N1}%{5}" -f $pal.E_BLU, $pal.E_RST, $cpuBar, $pal.E_MAG, $cpuPct, $pal.E_RST))
            $lines.Add(("  {0}MEM  {1} [{2}] {3}{4,5:N1}%{5}  {6}({7:N1} / {8:N1} GiB){9}" -f $pal.E_BLU, $pal.E_RST, $memBar, $pal.E_MAG, $memPct, $pal.E_RST, $pal.E_B01, $memUsedGb, $memTotalGb, $pal.E_RST))
            $lines.Add(("  {0}DISK {1} [{2}] {3}{4,5:N1}%{5}  {6}({7}: {8:N1} / {9:N1} GiB){10}" -f $pal.E_BLU, $pal.E_RST, $dskBar, $pal.E_MAG, $diskPct, $pal.E_RST, $pal.E_B01, $diskName, $diskUsedGb, $diskTotalGb, $pal.E_RST))
            $lines.Add('')
            $lines.Add(("  {0}{1,-8} {2,-30} {3,12} {4,12} {5,10}{6}" -f $pal.E_BLU, 'PID', 'PROCESS', 'MEM (MiB)', 'CPU (s)', 'THREADS', $pal.E_RST))
            $lines.Add(("  {0}{1}{2}" -f $pal.E_B01, $rule, $pal.E_RST))

            foreach ($p in $procs) {
                $pName = "$($p.ProcessName)"
                if ($pName.Length -gt 30) { $pName = $pName.Substring(0, 29) + "`u{2026}" }
                $wsMb = [Math]::Round($p.WorkingSet64 / 1MB, 1)
                $cpuSec = try { if ($null -ne $p.CPU) { [Math]::Round([double]$p.CPU, 1) } else { 0.0 } } catch { 0.0 }
                $thCount = try { $p.Threads.Count } catch { 0 }
                $lines.Add(("  {0}{1,-8}{2} {3,-30} {4}{5,12:N1}{6} {7,12:N1} {8,10}" -f $pal.E_CYN, $p.Id, $pal.E_B0, $pName, $pal.E_MAG, $wsMb, $pal.E_B0, $cpuSec, $thCount))
            }
            $lines.Add('')
            $lines.Add(("  {0}Tip: install full graph monitor with 'winget install aristocratos.btop4win'{1}" -f $pal.E_B01, $pal.E_RST))

            if ($isSingleShot) {
                foreach ($ln in $lines) { Write-Output $ln }
                return
            }

            $frame = "${esc}[H" + (($lines | ForEach-Object { $_ + $eol }) -join "`r`n") + "${esc}[J"
            [Console]::Write($frame)

            for ($tick = 0; $tick -lt 20; $tick++) {
                if ([Console]::KeyAvailable) {
                    $keyInfo = [Console]::ReadKey($true)
                    if ($keyInfo.Key -in @([ConsoleKey]::Q, [ConsoleKey]::Escape, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter)) {
                        return
                    }
                }
                Start-Sleep -Milliseconds 75
            }
        }
    } finally {
        if (-not $isSingleShot) {
            [Console]::Write("${esc}[?25h${esc}[?1049l")
        }
    }
}

function Invoke-SystemMonitor {
    $modalFile = ''
    if ($env:IDE_MONITOR_ONCE -ne '1') {
        $modalFile = Enter-ZellijFloatingModal -ModalName 'monitor' -X '5%' -Y '5%' -Width '90%' -Height '90%'
    }
    try {
        $monExe = Resolve-SystemMonitorExecutable
        if ($monExe) {
            $monDir = Split-Path -Parent $monExe
            $pushed = $false
            if ($monExe -match '(?i)btop4win\.exe$' -and $monDir -and (Test-Path -LiteralPath $monDir -PathType Container)) {
                Push-Location -LiteralPath $monDir
                $pushed = $true
            }
            try {
                & $monExe
                $rc = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
            } finally {
                if ($pushed) { Pop-Location }
            }
            exit $rc
        }

        Show-BuiltinSystemMonitor
        exit 0
    } finally {
        Exit-ZellijFloatingModal -ModalFile $modalFile
    }
}
