# ==============================================================================
# Modals.ps1 - Floating Zellij modals, 2-tier cheatsheet & TUI system monitor
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
        & $zellijBin action change-floating-pane-coordinates --pane-id $curPaneId --x $X --y $Y --width $Width --height $Height --pinned true *> $null
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

function Get-IdeModalSpec([string]$ModalName) {
    return $(switch ($ModalName.ToLowerInvariant()) {
        'keys'     { @{ Name = 'keys';     Title = 'Keybindings';       X = '5%';  Y = '6%';  W = '90%'; H = '88%'; SubCmd = @('keys') } }
        'sessions' { @{ Name = 'sessions'; Title = 'IDE Fleet Switcher'; X = '5%';  Y = '8%';  W = '90%'; H = '84%'; SubCmd = @('switch') } }
        'new'      { @{ Name = 'new';      Title = 'New Workspace';     X = '15%'; Y = '20%'; W = '70%'; H = '48%'; SubCmd = @('new') } }
        'dir'      { @{ Name = 'dir';      Title = 'Open Directory';    X = '6%';  Y = '8%';  W = '88%'; H = '84%'; SubCmd = @('dir') } }
        'agent'    { @{ Name = 'agent';    Title = 'AI Agent';          X = '22%'; Y = '24%'; W = '56%'; H = '40%'; SubCmd = @('agent') } }
        default    { @{ Name = 'monitor';  Title = 'System Monitor';    X = '5%';  Y = '5%';  W = '90%'; H = '90%'; SubCmd = @('monitor') } }
    })
}

function Invoke-ToggleZellijModal([string]$ModalName) {
    $normName = if ($ModalName) { $ModalName.Trim().ToLowerInvariant() } else { '' }
    if ($normName -notin @('sessions', 'keys', 'monitor', 'new', 'dir', 'agent')) {
        [Console]::Error.WriteLine("Error: Unknown modal '$ModalName'. Expected: sessions, keys, monitor, new, dir, or agent.")
        exit 1
    }

    $zellijBin = Resolve-ZellijExecutable
    if (-not $env:ZELLIJ -or -not $zellijBin) {
        switch ($normName) {
            'keys'     { Show-IdeKeysCheatsheet; exit 0 }
            'sessions' { Invoke-SessionSwitcher; exit 0 }
            'new'      { Invoke-IdeNew; exit 0 }
            'dir'      { Invoke-IdeDir; exit 0 }
            'agent'    { Invoke-IdeAgent; exit 0 }
            default    { Invoke-SystemMonitor; exit 0 }
        }
    }

    $canUseBatchFastToggle = ($env:WS_IDE_TOGGLE_FROM_BATCH -ne '1') -and
        ($env:WS_IDE_TOGGLE_FROM_PWSH -ne '1') -and (
            ($normName -in @('sessions', 'keys', 'new', 'dir', 'agent')) -or
            ($normName -eq 'monitor' -and $env:IDE_FORCE_BUILTIN_MONITOR -ne '1')
        )
    if ($canUseBatchFastToggle) {
        $ideCmd = Get-IdeBatchScriptPath
        if (Test-Path -LiteralPath $ideCmd -PathType Leaf) {
            $prevFromPwsh = $env:WS_IDE_TOGGLE_FROM_PWSH
            $env:WS_IDE_TOGGLE_FROM_PWSH = '1'
            try {
                & cmd.exe /d /c $ideCmd '_internal' 'toggle-modal' $normName *> $null
                if ($LASTEXITCODE -eq 0) {
                    exit 0
                }
            } finally {
                $env:WS_IDE_TOGGLE_FROM_PWSH = $prevFromPwsh
            }
        }
    }

    $spec = Get-IdeModalSpec $normName
    $rawSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME } elseif ($env:IDE_SESSION) { $env:IDE_SESSION } else { 'default' }
    $sess = Get-SanitizedToken $rawSess
    $stateDir = Get-IdeStateDir
    $modalFile = Join-Path $stateDir ("modal-{0}-{1}.json" -f $normName, $sess)
    $lockFile = Join-Path $stateDir ("{0}-{1}.lock" -f $normName, $sess)
    $paneFile = Join-Path $stateDir ("{0}-{1}.pane" -f $normName, $sess)

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

    # If the batch fast-path lock file is actively held (e.g. .pane sidecar was deleted),
    # close the matching floating modal pane by title or .pane file rather than opening a duplicate.
    if (Test-Path -LiteralPath $lockFile -PathType Leaf) {
        $isLocked = $false
        try {
            $fsCheck = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $fsCheck.Dispose()
        } catch [System.IO.IOException] {
            $isLocked = $true
        } catch {
            $isLocked = $false
        }
        if ($isLocked) {
            $closedLocked = $false
            if (Test-Path -LiteralPath $paneFile -PathType Leaf) {
                $savedPane = (Get-Content -LiteralPath $paneFile -Raw -ErrorAction SilentlyContinue)
                if ($savedPane -and $savedPane.Trim()) {
                    & $zellijBin action close-pane --pane-id $savedPane.Trim() *> $null
                    $closedLocked = ($LASTEXITCODE -eq 0)
                }
            }
            if (-not $closedLocked) {
                try {
                    $panesJson = (& $zellijBin action list-panes --all --json 2>$null) -join "`n"
                    if ($panesJson) {
                        $floatingHit = @($panesJson | ConvertFrom-Json) |
                            Where-Object { -not $_.is_plugin -and $_.is_floating -and -not $_.exited -and $_.title -eq $spec.Title } |
                            Select-Object -First 1
                        if ($floatingHit) {
                            & $zellijBin action close-pane --pane-id "terminal_$($floatingHit.id)" *> $null
                        }
                    }
                } catch {
                    Write-Verbose "Floating modal scan skipped: $_"
                }
            }
            exit 0
        }
    }

    $pwshBin = Get-CurrentPwshExecutable
    $entryScript = Get-IdeEntryScriptPath
    $env:IDE_MODAL_SIZED = '1'
    $env:IDE_ORIGIN_SESSION = $sess
    if ($normName -eq 'sessions') {
        $env:IDE_SESSIONS_MODAL = '1'
    }
    $subArgs = @($spec.SubCmd)
    & $zellijBin run --floating --pinned true --close-on-exit -x $spec.X -y $spec.Y --width $spec.W --height $spec.H --name $spec.Title -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $entryScript @subArgs *> $null
    exit 0
}

function Test-UseCompactKeysCheatsheet([bool]$ForceSpacious = $false) {
    if ($ForceSpacious) { return $false }
    $style = if ($env:IDE_KEYS_STYLE) { $env:IDE_KEYS_STYLE.Trim().ToLowerInvariant() } else { '' }
    if ($style -eq 'compact') { return $true }
    if ($style -in @('spacious', 'wide')) { return $false }
    $sz = Get-IdeTerminalSize
    if ($sz.Columns -gt 0 -and $sz.Columns -lt 104) { return $true }
    if ($sz.Rows -gt 0 -and $sz.Rows -lt 30) { return $true }
    return $false
}

function Get-IdeKeysCheatsheetText([switch]$ForceSpacious) {
    $pal = Get-ActivePaletteMap
    $nf = Test-IdeNerdFont
    $titleIco = if ($nf) { "`u{EBC8} " } else { '' }
    $ruleCh = "`u{2500}"
    $compact = Test-UseCompactKeysCheatsheet -ForceSpacious $ForceSpacious.IsPresent

    $lines = [System.Collections.Generic.List[string]]::new()

    if ($compact) {
        # Compact 80x24 tier (<=76 cols x 22 lines)
        $hdrPad = if ($nf) { '         ' } else { '           ' }
        $lines.Add((" {0}{1}IDE Workspace & Agent Fleet Keybindings{2}{3}[q / Esc / F1 to close]{4}" -f $pal.E_ORG, $titleIco, $pal.E_B01, $hdrPad, $pal.E_RST))
        $lines.Add((" {0}{1}{1} {2}PANES & LAYOUT {0}{3}  {1}{1} {2}SESSIONS & SWITCHER {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 19), ($ruleCh * 14), $pal.E_RST))
        $paneRows = @(
            @('Alt+a / e / t',     'Focus AI/Ed/Shell', 'Alt+s / Ctrl+b s',  'Switch IDE session'),
            @('Alt+h / j / k / l', 'Move pane focus',   'Alt+n / Alt+o',     'New WS / open dir'),
            @('Alt+Shift+H/J/K/L', 'Swap active pane',  'C-y/o/M-r (Alt+s)', 'Ack, PR, or agent'),
            @('Alt+Arrows',        'Resize pane',       'Alt+Shift+S',       'Jump to waiting AI'),
            @('Alt+Shift+A/E/T',   'Park AI/Ed/Shell',  'Alt+m / Ctrl+b m',  'Open sys monitor'),
            @('Alt+u / Ctrl+b v',  'Scrollback mode',   'Click top bar',     'Focus, Help, menu'),
            @('Alt+z / Alt+f',     'Zoom / float pane', 'v <f> / icd [dir]', 'Edit / workspace cd'),
            @('Ctrl+b b / r',      'Top bar / refresh', ':Q / Alt+q / M-Q',  'Quit / force-quit')
        )
        foreach ($r in $paneRows) {
            $lines.Add((" {0}{1,-17}{2} {3,-17}  {4}{5,-17}{6} {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
        }

        $lines.Add((" {0}{1}{1} {2}EDITOR (Space = Leader) {0}{3}  {1}{1} {2}CLIPBOARD, LINKS & HELP {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 10), ($ruleCh * 10), $pal.E_RST))
        $edRows = @(
            @('Space ff / fg',   'Find file / grep', 'Mouse drag / 2x',   'Select & copy text'),
            @('Space gs / t',    'Git status/Shell', 'Alt+c / Alt+v',     'Copy+clear / paste'),
            @('Space m',         'Markdown preview', 'Ctrl/Alt+Click',    'Open link / LSP def'),
            @('H / L  (Normal)', 'Prev/next buffer', 'Mouse4/5 or C-o/i', 'Jump back/forward'),
            @('Ctrl+h/j/k/l',    'Editor split nav', 'Alt+? / F1',        'This key cheatsheet')
        )
        foreach ($r in $edRows) {
            $lines.Add((" {0}{1,-17}{2} {3,-17}  {4}{5,-17}{6} {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
        }

        $lines.Add((" {0}{1}{1} {2}FILE TREE (mini.files) {0}{3}  {1}{1} {2}SEND TO AI & THEMES {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 11), ($ruleCh * 14), $pal.E_RST))
        $treeRows = @(
            @('Space e / Space E', 'Open mini.files',  'Space a / A (Vis)', 'Send/stage lines'),
            @('h/l or Left/Right', 'Parent / open',    'Space il / if',     'Send line / file'),
            @('Enter  (in tree)',  'Open file / dir',  'Space ia / id',     'Stage file / diags'),
            @('=      (in tree)',  'Apply file edits', ':IdeSend[!] [ws]',  'Stage to other WS'),
            @('g? / q (in tree)',  'Help / close tree', ':Theme [slug]',    'Switch 22+ themes')
        )
        foreach ($r in $treeRows) {
            $lines.Add((" {0}{1,-17}{2} {3,-17}  {4}{5,-17}{6} {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
        }
        return ,$lines.ToArray()
    }

    # Spacious 108x34 tier (<=104 cols x 28 lines)
    $hdrPadWide = if ($nf) { (' ' * 36) } else { (' ' * 38) }
    $lines.Add('')
    $lines.Add(("  {0}{1}IDE Workspace & Agent Fleet Keybindings{2}{3}[q / Esc / F1 to close]{4}" -f $pal.E_ORG, $titleIco, $pal.E_B01, $hdrPadWide, $pal.E_RST))
    $lines.Add('')
    $lines.Add(("  {0}{1}{1} {2}PANES & LAYOUT {0}{3}    {1}{1} {2}SESSIONS & SWITCHER {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 31), ($ruleCh * 26), $pal.E_RST))
    $widePaneRows = @(
        @('Alt+a / e / t',     'Focus AI, Editor, or Shell',   'Alt+s / Ctrl+b s',   'Open IDE Fleet Switcher'),
        @('Alt+h / j / k / l', 'Move focus between panes',     'Alt+n / Alt+o',      'New workspace or open dir'),
        @('Alt+Shift+H/J/K/L', 'Swap active pane',             'Alt+Shift+S',        'Jump to waiting AI session'),
        @('Alt+Arrows',        'Resize active pane',           'Ctrl+y / o (Alt+s)', 'Ack attention or open PR'),
        @('Alt+Shift+A/E/T',   'Hide or show AI/Editor/Shell', 'Alt+r     (Alt+s)',  'Switch or restart AI agent'),
        @('Alt+u / Ctrl+b v',  'Enter scrollback mode',        'Ctrl+x    (Alt+s)',  'Close selected workspace'),
        @('Alt+z / Alt+f',     'Zoom 100% or floating drawer', 'Alt+m / Ctrl+b m',   'Open system monitor modal'),
        @('Ctrl+b | / -',      'Split pane right or below',    'ide --desktop',      'Standalone 1-Hop GPU window'),
        @('Ctrl+b b / r',      'Toggle top bar or refresh',    'v <file> / icd',     'Edit file or workspace cd'),
        @('Right-click bar',   'IDE workspace context menu',   ':Q / Alt+q / M-Q',   'Quit or force-quit session')
    )
    foreach ($r in $widePaneRows) {
        $lines.Add(("  {0}{1,-19}{2}  {3,-28}    {4}{5,-19}{6}  {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
    }

    $lines.Add('')
    $lines.Add(("  {0}{1}{1} {2}EDITOR (Space = Leader) {0}{3}    {1}{1} {2}CLIPBOARD, LINKS & HELP {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 22), ($ruleCh * 22), $pal.E_RST))
    $wideEdRows = @(
        @('Space ff / fb',      'Find files or open buffers', 'Mouse drag / 2x',   'Select and copy text'),
        @('Space fg',           'Live grep across workspace', 'Alt+c / Alt+v',     'Copy selection or paste'),
        @('Space gs / cd',      'Git status or workspace cd', 'Ctrl / Alt+Click',  'Open link or LSP definition'),
        @('Space m',            'Toggle Markdown preview',    'Mouse4/5 or C-o/i', 'Jump back or forward'),
        @('H / L  (Normal)',    'Previous or next buffer',    'Click top bar',     'Switch role, WS, or menu'),
        @('Ctrl+h / j / k / l', 'Navigate Editor splits',     'Alt+? / F1 / Pfx+?', 'Open this keybinding guide')
    )
    foreach ($r in $wideEdRows) {
        $lines.Add(("  {0}{1,-19}{2}  {3,-28}    {4}{5,-19}{6}  {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
    }

    $lines.Add('')
    $lines.Add(("  {0}{1}{1} {2}FILE TREE (mini.files) {0}{3}    {1}{1} {2}SEND TO AI & THEMES {0}{4}{5}" -f $pal.E_B01, $ruleCh, $pal.E_BLU, ($ruleCh * 23), ($ruleCh * 26), $pal.E_RST))
    $wideTreeRows = @(
        @('Space e / Space E', 'Open tree (file or root)',  'Space a / A (Vis)', 'Send or stage lines to AI'),
        @('h/l or Left/Right', 'Parent dir or open entry',  'Space il / if',     'Send line or file ref'),
        @('Enter  (in tree)',  'Confirm and open entry',    'Space ia / id',     'Stage file or diagnostics'),
        @('=      (in tree)',  'Apply pending file edits',  ':IdeSend[!] [sess]', 'Stage range to target WS'),
        @('g? / q (in tree)',  'Tree help or close tree',   ':Theme [slug]',     'Live-switch color themes')
    )
    foreach ($r in $wideTreeRows) {
        $lines.Add(("  {0}{1,-19}{2}  {3,-28}    {4}{5,-19}{6}  {7}{8}" -f $pal.E_CYN, $r[0], $pal.E_B0, $r[1], $pal.E_CYN, $r[2], $pal.E_B0, $r[3], $pal.E_RST))
    }
    return ,$lines.ToArray()
}

function Write-IdeKeysCheatsheetCache {
    $esc = [char]27
    $lines = Get-IdeKeysCheatsheetText -ForceSpacious
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
        $modalFile = Enter-ZellijFloatingModal -ModalName 'keys' -X '5%' -Y '6%' -Width '90%' -Height '88%'
    }
    try {
        foreach ($ln in (Get-IdeKeysCheatsheetText)) {
            Write-Output $ln
        }

        if ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected -and $env:IDE_KEYS_NO_WAIT -ne '1') {
            try {
                while ($true) {
                    $keyInfo = [Console]::ReadKey($true)
                    if ($keyInfo.Key -in @([ConsoleKey]::F1, [ConsoleKey]::Q, [ConsoleKey]::Escape, [ConsoleKey]::Spacebar, [ConsoleKey]::Enter) -or
                        $keyInfo.KeyChar -eq '?') {
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
