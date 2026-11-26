# =============================================================
# CLI Tab Completions & Dynamic Argument Providers
# High-Speed In-Memory Registrations (<20ms total)
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'ArgumentCompleter signature requires 3 parameters')]
param()

# GitHub CLI (gh) - Cached on disk with binary-mtime invalidation on upgrades
$ghCache = Join-Path $HOME '.cache\powershell\gh_completion.ps1'
$ghBinTicks = if ($null -ne ${function:Get-WsBinaryTimestamp}) { Get-WsBinaryTimestamp 'gh.exe' } else { [long]0 }
$ghCacheValid = [System.IO.File]::Exists($ghCache) -and
    ([System.IO.FileInfo]::new($ghCache)).Length -gt 0 -and
    ($ghBinTicks -le 0 -or [System.IO.File]::GetLastWriteTimeUtc($ghCache).Ticks -ge $ghBinTicks)
if ($ghCacheValid) {
    . $ghCache
} elseif ($ghBinTicks -gt 0 -or (Get-Command gh -ErrorAction SilentlyContinue)) {
    $cacheDir = Join-Path $HOME '.cache\powershell'
    if (-not [System.IO.Directory]::Exists($cacheDir)) {
        New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    }
    gh completion -s powershell | Out-File -FilePath $ghCache -Encoding utf8 -Force
    if ([System.IO.File]::Exists($ghCache) -and ([System.IO.FileInfo]::new($ghCache)).Length -gt 0) {
        . $ghCache
    }
}

# Theme Engine (22 built-in palettes + lazy custom user themes + flags)
Register-ArgumentCompleter -Native -CommandName theme -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $cursorPosition
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $hasPartial = [bool]($wordToComplete -and $wordToComplete.Length -gt 0)
    $endIdx = if ($hasPartial) { $elements.Count - 2 } else { $elements.Count - 1 }
    $prevToken = if ($endIdx -ge 1) { "$($elements[$endIdx])".ToLowerInvariant() } else { '' }

    $themeFlags = @(
        '-s', '--set', '--holiday', '-l', '--list', '--plain', '-c', '--current',
        '-p', '--preview', '--env', '--create', '--from', '-f', '--force',
        '--path', '--sync-assets', '--check-assets', '--no-live',
        '-n', '--dry-run', '-h', '--help'
    )

    if ($prevToken -eq '--create' -and -not $wordToComplete.StartsWith('-')) {
        return
    }

    $eqMatch = $wordToComplete -match '^(--(?:set|preview|env|from|dry-run))=(.*)$'
    $eqPrefix = if ($eqMatch) { "$($Matches[1])=" } else { '' }
    $eqVal = if ($eqMatch) { $Matches[2] } else { '' }
    $wantsOnlyThemes = ($prevToken -in @('-s', '--set', '-p', '--preview', '--path', '--env', '--from', '-n', '--dry-run')) -and
        (-not $wordToComplete.StartsWith('-') -or $prevToken -in @('-s', '--set', '--from'))

    if (-not $eqMatch -and -not $wantsOnlyThemes -and $wordToComplete.StartsWith('-')) {
        return $themeFlags | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
    }

    $builtinThemes = @(
        # BEGIN GENERATED BUILTIN THEMES
        'solarized-dark', 'solarized-light', 'catppuccin-mocha', 'catppuccin-latte',
        'gruvbox-dark', 'gruvbox-light', 'rose-pine', 'rose-pine-dawn',
        'everforest-dark', 'tokyonight-night', 'kanagawa-wave', 'dracula',
        'nord', 'onedark', 'new-years', 'valentines',
        'st-patricks', 'easter', 'independence-day', 'halloween',
        'thanksgiving', 'christmas'
        # END GENERATED BUILTIN THEMES
    )
    $allThemes = [System.Collections.Generic.List[string]]::new()
    foreach ($bt in $builtinThemes) {
        if ($bt -and -not $allThemes.Contains("$bt")) { $allThemes.Add("$bt") }
    }

    $cfgHome = if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        $env:XDG_CONFIG_HOME.Trim()
    } else {
        Join-Path $HOME '.config'
    }
    foreach ($userDir in @(
        $env:WINDOWS_SETTINGS_USER_THEMES_DIR,
        $env:HOME_SETTINGS_USER_THEMES_DIR,
        (Join-Path $cfgHome 'themes'),
        (Join-Path (Join-Path $cfgHome 'windows-settings') 'themes'),
        (Join-Path (Join-Path $cfgHome 'home-settings') 'themes')
    )) {
        if ($userDir -and [System.IO.Directory]::Exists($userDir)) {
            foreach ($f in [System.IO.Directory]::GetFiles($userDir, '*.theme')) {
                $slug = [System.IO.Path]::GetFileNameWithoutExtension($f).ToLowerInvariant()
                if ($slug -and $slug -ne 'active-theme' -and -not $allThemes.Contains($slug)) {
                    $allThemes.Add($slug)
                }
            }
        }
    }

    if ($eqMatch) {
        return $allThemes | Where-Object { $_ -like "$eqVal*" } |
            ForEach-Object {
                $full = "${eqPrefix}$_"
                [System.Management.Automation.CompletionResult]::new($full, $_, 'ParameterValue', $_)
            }
    }

    if ($wantsOnlyThemes) {
        return $allThemes | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    $combined = [System.Collections.Generic.List[string]]::new()
    foreach ($t in $allThemes) { $combined.Add($t) }
    foreach ($fl in $themeFlags) { $combined.Add($fl) }
    $combined | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# IDE Workspace & Fleet Shortcuts (ide, ide2, ide3, quit, qide, idek)
Register-ArgumentCompleter -Native -CommandName ide, ide2, ide3, quit, qide, idek -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $cursorPosition
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $cmdName = if ($elements.Count -gt 0) { [System.IO.Path]::GetFileNameWithoutExtension($elements[0]).ToLowerInvariant() } else { 'ide' }
    $hasPartial = [bool]($wordToComplete -and $wordToComplete.Length -gt 0)
    $priorTokens = [System.Collections.Generic.List[string]]::new()
    $endIdx = if ($hasPartial) { $elements.Count - 2 } else { $elements.Count - 1 }
    for ($ti = 1; $ti -le $endIdx; $ti++) {
        $priorTokens.Add("$($elements[$ti])")
    }
    $prevToken = if ($priorTokens.Count -gt 0) { $priorTokens[$priorTokens.Count - 1] } else { '' }
    $prevLower = $prevToken.ToLowerInvariant()

    $ideSubcommands = @(
        'list', 'switch', 'new', 'dir', 'agent', 'next', 'cd', 'refresh',
        'quit', 'open', 'send', 'state', 'ack', 'pr', 'keys', 'monitor'
    )
    $rootOpts = @(
        '--2pane', '--3pane', '--agent', '--ai', '-d', '--detach', '--desktop',
        '--new-window', '--backend', '-s', '-n', '-o', '--dry-run', '-h', '--help'
    )
    $switchOpts = @('--2pane', '--agent', '-d', '--detach', '-h', '--help')
    $listOpts   = @('--plain', '--json', '-h', '--help')
    $quitOpts   = @('-f', '--force', '--dry-run', '-h', '--help')
    $openOpts   = @('-p', '--preview', '-h', '--help')
    $sendOpts   = @('--stdin', '--ref', '--text', '--no-focus', '--switch', '-h', '--help')
    $stateOpts  = @('-m', '--message', '-h', '--help')
    $cdOpts     = @('--reset', '-h', '--help')
    $helpOpts   = @('-h', '--help')
    $agents     = @('agy', 'claude', 'codex')
    $agentCmds  = @('restart', 'agy', 'claude', 'codex')
    $states     = @('running', 'approval', 'quota', 'done', 'idle')

    $getIdeSessionsLazy = {
        $sessList = [System.Collections.Generic.List[string]]::new()
        $ideStateDir = Join-Path $HOME '.cache\windows-settings\ide'
        if ([System.IO.Directory]::Exists($ideStateDir)) {
            foreach ($f in [System.IO.Directory]::GetFiles($ideStateDir, '*.json')) {
                $sName = [System.IO.Path]::GetFileNameWithoutExtension($f)
                if ($sName -and $sName -notlike 'modal-*' -and -not $sessList.Contains($sName)) {
                    $sessList.Add($sName)
                }
            }
        }
        if ($env:WS_COMPLETION_NO_SPAWN -ne '1') {
            $zellijApp = Get-Command zellij.exe, zellij -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($null -ne $zellijApp) {
                try {
                    foreach ($zs in (& $zellijApp.Source list-sessions --short --no-formatting 2>$null)) {
                        $cleanZs = "$zs".Trim()
                        if ($cleanZs -and -not $sessList.Contains($cleanZs)) { $sessList.Add($cleanZs) }
                    }
                } catch {
                    $null = $_
                }
            }
        }
        return , $sessList.ToArray()
    }

    $getIdeWorkspacesLazy = {
        $wsList = [System.Collections.Generic.List[string]]::new()
        if ($env:IDE_WORKSPACE_DIRS -and $env:IDE_WORKSPACE_DIRS.Trim()) {
            foreach ($entry in ($env:IDE_WORKSPACE_DIRS -split ';')) {
                $cleanDir = $entry.Trim()
                if (-not $cleanDir) { continue }
                if ($cleanDir -eq '~') { $cleanDir = $HOME }
                elseif ($cleanDir.StartsWith('~/') -or $cleanDir.StartsWith('~\')) {
                    $cleanDir = Join-Path $HOME $cleanDir.Substring(2)
                }
                if ([System.IO.Directory]::Exists($cleanDir)) {
                    $leaf = Split-Path -Leaf $cleanDir.TrimEnd('\', '/')
                    if ($leaf -and -not $wsList.Contains($leaf)) { $wsList.Add($leaf) }
                }
            }
        }
        return , $wsList.ToArray()
    }

    $completeFiles = {
        param([bool]$DirsOnly)
        $results = [System.Collections.Generic.List[string]]::new()
        try {
            $items = if ($DirsOnly) {
                Get-ChildItem -Directory -ErrorAction SilentlyContinue
            } else {
                Get-ChildItem -ErrorAction SilentlyContinue
            }
            foreach ($it in $items) {
                $results.Add($it.Name)
            }
        } catch {
            $null = $_
        }
        return , $results.ToArray()
    }

    # Inline --flag=value completions
    if ($wordToComplete -match '^(--(?:agent|ai))=(.*)$') {
        $pfx = "$($Matches[1])="
        $val = $Matches[2]
        return $agents | Where-Object { $_ -like "$val*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("${pfx}$_", $_, 'ParameterValue', $_) }
    }
    if ($wordToComplete -match '^--backend=(.*)$') {
        $val = $Matches[1]
        return @('zellij', 'wt') | Where-Object { $_ -like "$val*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("--backend=$_", $_, 'ParameterValue', $_) }
    }
    if ($wordToComplete -match '^--ref=(.*)$') {
        $val = $Matches[1]
        return (& $completeFiles $false) | Where-Object { $_ -like "$val*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("--ref=$_", $_, 'ParameterValue', $_) }
    }
    if ($wordToComplete -match '^--(text|message)=') {
        return
    }

    # Previous option value completions (0 subprocess spawns)
    switch ($prevLower) {
        { $_ -in @('--agent', '--ai') } {
            return $agents | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        '--backend' {
            return @('zellij', 'wt') | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        '--agent-state' {
            return $states | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        '--swap' {
            return @('left', 'down', 'up', 'right') | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        '--focus-role' {
            return @('ai', 'editor', 'shell') | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        '--ref' {
            return (& $completeFiles $false) | Where-Object { $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
        }
        { $_ -in @('--text', '-m', '--message') } {
            return
        }
    }

    # Direct quit shortcuts (`quit`, `qide`, `idek`)
    if ($cmdName -in @('quit', 'qide', 'idek')) {
        if ($wordToComplete.StartsWith('-')) {
            return $quitOpts | Where-Object { $_ -notin $priorTokens -and $_ -like "$wordToComplete*" } |
                ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
        }
        $sessions = & $getIdeSessionsLazy
        $unused = @($sessions | Where-Object { $_ -notin $priorTokens })
        $pool = if ($unused.Count -gt 0) { $unused } else { $sessions }
        return $pool | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # Scan prior tokens to identify active subcommand
    $subcmd = ''
    $subStartIdx = 0
    $hasLaunchPos = $false
    $endOpts = $false
    for ($idx = 0; $idx -lt $priorTokens.Count; $idx++) {
        $w = $priorTokens[$idx]
        $wLow = $w.ToLowerInvariant()
        if ($endOpts) {
            $hasLaunchPos = $true
            continue
        }
        if ($w -eq '--') {
            $endOpts = $true
            continue
        }
        if ($wLow -in @('--2pane', '--3pane', '-d', '--detach', '--desktop', '--new-window', '--dry-run', '-h', '--help') -or $wLow -match '^--(agent|ai|backend)=') {
            continue
        }
        if ($wLow -in @('--agent', '--ai', '--backend')) {
            $idx++
            continue
        }
        if (-not $hasLaunchPos) {
            if ($wLow -in @('-s', 'switch')) { $subcmd = 'switch'; $subStartIdx = $idx + 1; break }
            if ($wLow -in @('-n', 'new'))    { $subcmd = 'new';    $subStartIdx = $idx + 1; break }
            if ($wLow -in @('-o', 'dir', 'open-dir')) { $subcmd = 'dir'; $subStartIdx = $idx + 1; break }
            if ($cmdName -eq 'ide' -and $wLow -in $ideSubcommands) {
                $subcmd = $wLow
                $subStartIdx = $idx + 1
                break
            }
            if ($wLow -in @('--quit', '-q', '--kill', '-k')) { $subcmd = 'quit'; $subStartIdx = $idx + 1; break }
            if ($wLow -eq '--send')   { $subcmd = 'send'; $subStartIdx = $idx + 1; break }
            if ($wLow -eq '--cd')     { $subcmd = 'cd';   $subStartIdx = $idx + 1; break }
            if ($wLow -eq '--ack-ai') { $subcmd = 'ack';  $subStartIdx = $idx + 1; break }
        }
        $hasLaunchPos = $true
    }

    if ($subcmd) {
        $posArgs = [System.Collections.Generic.List[string]]::new()
        $pEnd = $false
        $hasSendPayload = $false
        $hasListFmt = $false
        for ($si = $subStartIdx; $si -lt $priorTokens.Count; $si++) {
            $sw = $priorTokens[$si]
            $swLow = $sw.ToLowerInvariant()
            if ($pEnd) {
                $posArgs.Add($sw)
                continue
            }
            if ($sw -eq '--') { $pEnd = $true; continue }
            if ($subcmd -eq 'list' -and $swLow -in @('--plain', '--json')) { $hasListFmt = $true; continue }
            if ($subcmd -in @('switch', 'new', 'dir') -and $swLow -in @('--agent', '--ai')) { $si++; continue }
            if ($subcmd -eq 'send' -and ($swLow -eq '--stdin' -or $swLow -match '^--(ref|text)=')) { $hasSendPayload = $true; continue }
            if ($subcmd -eq 'send' -and $swLow -in @('--ref', '--text')) {
                if ($si + 1 -lt $priorTokens.Count) { $hasSendPayload = $true; $si++ }
                continue
            }
            if ($subcmd -eq 'state' -and $swLow -in @('-m', '--message')) { $si++; continue }
            if ($subcmd -eq 'cd' -and $swLow -in @('--reset', '-')) { $posArgs.Add($sw); continue }
            if ($sw.StartsWith('-')) { continue }
            $posArgs.Add($sw)
            if ($subcmd -eq 'send' -and -not $hasSendPayload) { $hasSendPayload = $true }
        }

        switch ($subcmd) {
            { $_ -in @('keys', 'monitor') } {
                if ($wordToComplete.StartsWith('-')) {
                    return $helpOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                return
            }
            'list' {
                if (-not $hasListFmt -and $posArgs.Count -eq 0) {
                    return $listOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                return
            }
            { $_ -in @('new', 'dir') } {
                if ($wordToComplete.StartsWith('-')) {
                    return $switchOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                return
            }
            'agent' {
                if ($wordToComplete.StartsWith('-')) {
                    return $helpOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    return $agentCmds | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                if ($posArgs.Count -eq 1) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            'switch' {
                if ($wordToComplete.StartsWith('-')) {
                    return $switchOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            { $_ -in @('next', 'refresh', 'pr') } {
                if ($wordToComplete.StartsWith('-')) {
                    [string[]]$opts = @(if ($subcmd -eq 'refresh') { '--dry-run', '-h', '--help' } else { $helpOpts })
                    return $opts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            'cd' {
                if ($wordToComplete.StartsWith('-')) {
                    return $cdOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    $dirs = [System.Collections.Generic.List[string]]@('--reset')
                    foreach ($d in (& $completeFiles $true)) { $dirs.Add($d) }
                    return $dirs | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                if ($posArgs.Count -eq 1) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            'quit' {
                if ($wordToComplete.StartsWith('-')) {
                    return $quitOpts | Where-Object { $_ -notin $priorTokens -and $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                $sessions = & $getIdeSessionsLazy
                $unused = @($sessions | Where-Object { $_ -notin $posArgs })
                $pool = if ($unused.Count -gt 0) { $unused } else { $sessions }
                return $pool | Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
            'ack' {
                if ($wordToComplete.StartsWith('-')) {
                    return $helpOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                $sessions = & $getIdeSessionsLazy
                $unused = @($sessions | Where-Object { $_ -notin $posArgs })
                $pool = if ($unused.Count -gt 0) { $unused } else { $sessions }
                return $pool | Where-Object { $_ -like "$wordToComplete*" } |
                    ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
            }
            'open' {
                if ($wordToComplete.StartsWith('-') -and $posArgs.Count -eq 0) {
                    return $openOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    return (& $completeFiles $false) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                if ($posArgs.Count -eq 1 -or ($posArgs.Count -eq 2 -and $posArgs[1] -match '^\+?[0-9]+$')) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            'send' {
                if (-not $hasSendPayload -or $wordToComplete.StartsWith('-')) {
                    return $sendOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -le 1) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
            'state' {
                if ($wordToComplete.StartsWith('-')) {
                    return $stateOpts | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
                }
                if ($posArgs.Count -eq 0) {
                    return $states | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                if ($posArgs.Count -eq 1) {
                    return (& $getIdeSessionsLazy) | Where-Object { $_ -like "$wordToComplete*" } |
                        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
                }
                return
            }
        }
    }

    # Root flags (0 subprocess spawns)
    if ($wordToComplete.StartsWith('-') -and -not $endOpts) {
        return $rootOpts | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
    }

    if (-not $hasLaunchPos) {
        $candidates = [System.Collections.Generic.List[string]]::new()
        $isPathPrefix = $wordToComplete.Contains('/') -or $wordToComplete.Contains('\') -or $wordToComplete.StartsWith('.') -or $wordToComplete.StartsWith('~')
        if ($cmdName -eq 'ide' -and -not $endOpts -and -not $isPathPrefix) {
            foreach ($sc in $ideSubcommands) { $candidates.Add($sc) }
        }
        foreach ($s in (& $getIdeSessionsLazy)) {
            if (-not $candidates.Contains($s)) { $candidates.Add($s) }
        }
        if (-not $isPathPrefix) {
            foreach ($ws in (& $getIdeWorkspacesLazy)) {
                if (-not $candidates.Contains($ws)) { $candidates.Add($ws) }
            }
        }
        foreach ($dirName in (& $completeFiles $true)) {
            if (-not $candidates.Contains($dirName)) { $candidates.Add($dirName) }
        }
        return $candidates | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
}

# Unified Workstation Updater (update / update-system)
Register-ArgumentCompleter -Native -CommandName update, update-system -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $cursorPosition
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $hasPartial = [bool]($wordToComplete -and $wordToComplete.Length -gt 0)
    $endIdx = if ($hasPartial) { $elements.Count - 2 } else { $elements.Count - 1 }
    $prevToken = if ($endIdx -ge 1) { "$($elements[$endIdx])".ToLowerInvariant() } else { '' }
    $skipChoices = @('winget', 'mise', 'modules', 'nvim', 'cleanup')

    $lastElem = if ($elements.Count -ge 2) { "$($elements[$elements.Count - 1])".ToLowerInvariant() } else { '' }
    if ($wordToComplete -match '^--skip=([^,]*)$') {
        $partialVal = $Matches[1]
        return $skipChoices | Where-Object { $_ -like "$partialVal*" } |
            ForEach-Object {
                $full = "--skip=$_"
                [System.Management.Automation.CompletionResult]::new($full, $_, 'ParameterValue', $_)
            }
    }
    if ($lastElem -match '^--skip=(.*,.*)$' -and -not $wordToComplete.StartsWith('-')) {
        $rawList = $Matches[1]
        $lastComma = $rawList.LastIndexOf(',')
        $usedPrefix = if ($lastComma -ge 0) { $rawList.Substring(0, $lastComma) } else { '' }
        $used = @($usedPrefix -split ',' | Where-Object { $_ })
        return $skipChoices | Where-Object { $_ -notin $used -and $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    $isSkipTrailingComma = (-not $hasPartial) -and ($endIdx -ge 2) -and
        ("$($elements[$endIdx - 1])".ToLowerInvariant() -in @('--skip', '-skip')) -and
        $prevToken.EndsWith(',')
    if (($prevToken -in @('--skip', '-skip') -and -not $wordToComplete.StartsWith('-')) -or $isSkipTrailingComma) {
        $rawListToken = if ($isSkipTrailingComma) {
            $prevToken
        } elseif ($hasPartial -and $elements.Count -ge 3) {
            "$($elements[$elements.Count - 1])".ToLowerInvariant()
        } else {
            ''
        }
        $lastComma = $rawListToken.LastIndexOf(',')
        $usedPrefix = if ($lastComma -ge 0) { $rawListToken.Substring(0, $lastComma) } else { '' }
        $used = @($usedPrefix -split ',' | Where-Object { $_ })
        return $skipChoices | Where-Object { $_ -notin $used -and $_ -like "$wordToComplete*" } |
            ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
    }

    $flags = @(
        '--all', '--system-only', '--skip', '-i', '--interactive',
        '-n', '--dry-run', '-h', '--help'
    )
    $flags | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
}

# WinGet
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @(
        'install', 'show', 'source', 'search', 'list', 'upgrade',
        'uninstall', 'hash', 'validate', 'settings', 'features', 'export', 'import', 'pin', 'configure'
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Docker
Register-ArgumentCompleter -Native -CommandName docker -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @(
        'build', 'run', 'ps', 'exec', 'logs', 'stop', 'start', 'restart', 'rm', 'rmi',
        'pull', 'push', 'images', 'compose', 'volume', 'network', 'system'
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Kubectl
Register-ArgumentCompleter -Native -CommandName kubectl -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('get', 'describe', 'create', 'apply', 'delete', 'log', 'logs', 'exec', 'port-forward', 'top', 'cluster-info', 'config')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Helm
Register-ArgumentCompleter -Native -CommandName helm -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('install', 'upgrade', 'list', 'uninstall', 'status', 'repo', 'dependency', 'package', 'search', 'show', 'template', 'lint')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Terraform & tf Alias (Zero-Subprocess Flag, Subcommand, Enum & -chdir= Engine)
Register-ArgumentCompleter -Native -CommandName terraform, tf -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $cursorPosition
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.Extent.Text })
    $hasPartial = [bool]($wordToComplete -and $wordToComplete.Length -gt 0)
    $endIdx = if ($hasPartial) { $elements.Count - 2 } else { $elements.Count - 1 }
    $prevToken = if ($endIdx -ge 1) { "$($elements[$endIdx])" } else { '' }

    $tfRootSubcmds = @(
        'init', 'validate', 'plan', 'apply', 'destroy', 'fmt', 'providers', 'workspace',
        'state', 'output', 'import', 'show', 'taint', 'untaint', 'force-unlock', 'graph',
        'refresh', 'console', 'get', 'login', 'logout', 'test', 'metadata', 'modules',
        'query', 'stacks', 'version', '-help', '-version', '-chdir='
    )
    $tfNestedSubcmds = @{
        state     = @('identities', 'list', 'mv', 'pull', 'push', 'replace-provider', 'rm', 'show')
        workspace = @('delete', 'list', 'new', 'select', 'show')
        providers = @('lock', 'mirror', 'schema')
        metadata  = @('functions')
        stacks    = @('init', 'providers-lock', 'validate', 'create', 'list', 'version', 'fmt', 'configuration', 'deployment-group', 'deployment-run', 'deployment-step', 'diagnostics')
    }
    $tfSubcmdFlags = @{
        'init'                   = @('-backend=', '-backend-config=', '-cloud=', '-force-copy', '-from-module=', '-get=', '-help', '-ignore-remote-version', '-input=', '-json', '-lock=', '-lock-timeout=', '-lockfile=', '-migrate-state', '-no-color', '-plugin-dir=', '-reconfigure', '-test-directory=', '-upgrade', '-var', '-var-file=')
        'plan'                   = @('-compact-warnings', '-destroy', '-detailed-exitcode', '-generate-config-out=', '-help', '-input=', '-json', '-lock=', '-lock-timeout=', '-no-color', '-out=', '-parallelism=', '-refresh=', '-refresh-only', '-replace=', '-state=', '-target=', '-var', '-var-file=')
        'apply'                  = @('-auto-approve', '-backup=', '-compact-warnings', '-destroy', '-help', '-input=', '-json', '-lock=', '-lock-timeout=', '-no-color', '-parallelism=', '-refresh=', '-refresh-only', '-replace=', '-state=', '-state-out=', '-target=', '-var', '-var-file=')
        'destroy'                = @('-auto-approve', '-backup=', '-compact-warnings', '-help', '-input=', '-json', '-lock=', '-lock-timeout=', '-no-color', '-parallelism=', '-refresh=', '-refresh-only', '-replace=', '-state=', '-state-out=', '-target=', '-var', '-var-file=')
        'fmt'                    = @('-check', '-diff', '-help', '-list=', '-no-color', '-recursive', '-write=')
        'validate'               = @('-help', '-json', '-no-color', '-no-tests', '-query', '-test-directory=', '-var', '-var-file=')
        'output'                 = @('-help', '-json', '-no-color', '-raw', '-state=')
        'import'                 = @('-backup=', '-config=', '-help', '-ignore-remote-version', '-input=', '-lock=', '-lock-timeout=', '-no-color', '-state=', '-state-out=', '-var', '-var-file=')
        'refresh'                = @('-backup=', '-compact-warnings', '-help', '-input=', '-json', '-lock=', '-lock-timeout=', '-no-color', '-parallelism=', '-state=', '-state-out=', '-target=', '-var', '-var-file=')
        'show'                   = @('-help', '-json', '-no-color')
        'graph'                  = @('-draw-cycles', '-format=', '-help', '-module-depth=', '-plan=', '-type=', '-var', '-var-file=')
        'console'                = @('-help', '-plan', '-scope=', '-state=', '-var', '-var-file=')
        'get'                    = @('-help', '-json', '-no-color', '-test-directory=', '-update', '-var', '-var-file=')
        'test'                   = @('-cloud-run=', '-filter=', '-help', '-json', '-junit-xml=', '-no-color', '-parallelism=', '-test-directory=', '-var', '-var-file=', '-verbose')
        'taint'                  = @('-allow-missing', '-backup=', '-help', '-ignore-remote-version', '-lock=', '-lock-timeout=', '-state=', '-state-out=', '-var', '-var-file=')
        'untaint'                = @('-allow-missing', '-backup=', '-help', '-ignore-remote-version', '-lock=', '-lock-timeout=', '-state=', '-state-out=')
        'force-unlock'           = @('-force', '-help')
        'version'                = @('-help', '-json')
        'metadata functions'     = @('-help', '-json')
        'workspace list'         = @('-help', '-json')
        'providers schema'       = @('-help', '-json', '-no-color', '-var', '-var-file=')
        'query'                  = @('-generate-config-out=', '-help', '-json', '-no-color', '-var', '-var-file=')
        'modules'                = @('-help', '-json', '-var', '-var-file=')
        'providers'              = @('-help', '-test-directory=', '-var', '-var-file=')
        'providers lock'         = @('-enable-plugin-cache', '-fs-mirror=', '-help', '-net-mirror=', '-platform=', '-test-directory=', '-var', '-var-file=')
        'providers mirror'       = @('-help', '-lock-file=', '-platform=', '-var', '-var-file=')
        'state list'             = @('-help', '-id=', '-state=')
        'state identities'       = @('-help', '-id=', '-state=')
        'state mv'               = @('-backup=', '-backup-out=', '-dry-run', '-help', '-ignore-remote-version', '-lock=', '-lock-timeout=', '-state=', '-state-out=', '-var', '-var-file=')
        'state pull'             = @('-help', '-var', '-var-file=')
        'state push'             = @('-force', '-help', '-lock=', '-lock-timeout=', '-var', '-var-file=')
        'state replace-provider' = @('-auto-approve', '-backup=', '-help', '-ignore-remote-version', '-lock=', '-lock-timeout=', '-state=', '-var', '-var-file=')
        'state rm'               = @('-backup=', '-dry-run', '-help', '-ignore-remote-version', '-lock=', '-lock-timeout=', '-state=', '-var', '-var-file=')
        'state show'             = @('-help', '-json', '-state=')
        'workspace select'       = @('-help', '-or-create=')
        'workspace new'          = @('-help', '-lock=', '-lock-timeout=', '-state=')
        'workspace delete'       = @('-force', '-help', '-lock=', '-lock-timeout=')
        'stacks'                 = @('-chdir=', '-no-color=', '-plugin-cache-dir=', '-stacks-version', '-usage')
        'state'                  = @('-help')
        'workspace'              = @('-help')
        'workspace show'         = @('-help')
        'metadata'               = @('-help')
        'login'                  = @('-help')
        'logout'                 = @('-help')
    }

    $argTakingFlags = @(
        '-plugin-dir', '-plugin-cache-dir', '-from-module', '-test-directory', '-config', '-fs-mirror',
        '-var', '-var-file', '-out', '-state', '-state-out', '-backup', '-backup-out', '-backend-config',
        '-generate-config-out', '-filter', '-junit-xml', '-target', '-replace', '-parallelism',
        '-lock-timeout', '-lockfile', '-id', '-platform', '-net-mirror', '-cloud-run', '-module-depth',
        '-type', '-format', '-scope'
    )
    $dirValueFlags = @('-plugin-dir', '-plugin-cache-dir', '-from-module', '-test-directory', '-config', '-fs-mirror')
    $fileValueFlags = @('-var-file', '-out', '-state', '-state-out', '-backup', '-backup-out', '-backend-config', '-generate-config-out', '-filter', '-junit-xml')

    $subcmd = ''
    $subcmd2 = ''
    $chdirDir = ''
    $afterDoubleDash = $false

    for ($idx = 1; $idx -le $endIdx; $idx++) {
        $w = "$($elements[$idx])"
        if ($w -eq '--') {
            $afterDoubleDash = $true
            break
        }
        if ($w.StartsWith('-chdir=')) {
            $rawChdir = $w.Substring(7).Trim('"', "'")
            if ($rawChdir -eq '~') { $rawChdir = $HOME }
            elseif ($rawChdir.StartsWith('~/') -or $rawChdir.StartsWith('~\')) {
                $rawChdir = Join-Path $HOME $rawChdir.Substring(2)
            }
            $chdirDir = if ([System.IO.Path]::IsPathRooted($rawChdir)) {
                $rawChdir
            } else {
                Join-Path (Get-Location).ProviderPath $rawChdir
            }
            continue
        }
        if ($w -in $argTakingFlags) {
            $idx++
            continue
        }
        if ($w.StartsWith('-')) {
            continue
        }
        if (-not $subcmd) {
            $subcmd = $w
        } elseif (-not $subcmd2 -and $tfNestedSubcmds.ContainsKey($subcmd) -and ($tfNestedSubcmds[$subcmd] -contains $w)) {
            $subcmd2 = $w
        }
    }

    $resolveTfPaths = {
        param([string]$PartialVal, [bool]$DirsOnly, [bool]$UseChdir)
        $baseDir = if ($UseChdir -and $chdirDir -and [System.IO.Directory]::Exists($chdirDir) -and -not [System.IO.Path]::IsPathRooted($PartialVal) -and -not $PartialVal.StartsWith('~')) {
            $chdirDir
        } else {
            (Get-Location).ProviderPath
        }
        $cleanPartial = $PartialVal.Trim('"', "'")
        $subParent = Split-Path -Parent $cleanPartial
        $leafPat = Split-Path -Leaf $cleanPartial
        $scanDir = if ($subParent) {
            if ([System.IO.Path]::IsPathRooted($subParent)) { $subParent } else { Join-Path $baseDir $subParent }
        } else {
            $baseDir
        }
        $outList = [System.Collections.Generic.List[string]]::new()
        if ([System.IO.Directory]::Exists($scanDir)) {
            try {
                $entries = if ($DirsOnly) {
                    Get-ChildItem -LiteralPath $scanDir -Directory -ErrorAction SilentlyContinue
                } else {
                    Get-ChildItem -LiteralPath $scanDir -ErrorAction SilentlyContinue
                }
                foreach ($ent in $entries) {
                    if ($ent.Name -like "$leafPat*") {
                        $rel = if ($subParent) { Join-Path $subParent $ent.Name } else { $ent.Name }
                        $outList.Add($rel)
                    }
                }
            } catch {
                $null = $_
            }
        }
        return , $outList.ToArray()
    }

    if ($afterDoubleDash) {
        return (& $resolveTfPaths $wordToComplete $false $true) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # -chdir= and path-bearing -flag= completions
    if ($wordToComplete -match '^-chdir=(.*)$') {
        $pVal = $Matches[1]
        return (& $resolveTfPaths $pVal $true $false) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("-chdir=$_", $_, 'ParameterValue', $_) }
    }
    if ($wordToComplete -match '^(-(?:plugin-dir|plugin-cache-dir|from-module|test-directory|config|fs-mirror))=(.*)$') {
        $fName = $Matches[1]
        $pVal = $Matches[2]
        return (& $resolveTfPaths $pVal $true $true) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("${fName}=$_", $_, 'ParameterValue', $_) }
    }
    if ($wordToComplete -match '^(-(?:var-file|out|state|state-out|backup|backup-out|backend-config|generate-config-out|filter|junit-xml|plan))=(.*)$') {
        $fName = $Matches[1]
        $pVal = $Matches[2]
        return (& $resolveTfPaths $pVal $false $true) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("${fName}=$_", $_, 'ParameterValue', $_) }
    }

    if ($prevToken -in $dirValueFlags) {
        return (& $resolveTfPaths $wordToComplete $true $true) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
    if ($prevToken -in $fileValueFlags) {
        return (& $resolveTfPaths $wordToComplete $false $true) |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    # Enum -flag=<val> completions
    if ($wordToComplete -match '^(-[^=]+)=(.*)$') {
        $fName = $Matches[1]
        $fVal = $Matches[2]
        $enums = switch ($fName) {
            { $_ -in @('-backend', '-get', '-input', '-lock', '-lock-file', '-refresh', '-cloud', '-list', '-write', '-or-create') } {
                @('true', 'false')
            }
            '-no-color' {
                if ($subcmd -eq 'stacks') { @('true', 'false') } else { @() }
            }
            '-lockfile' {
                @('readonly')
            }
            '-type' {
                if ($subcmd -eq 'graph') { @('plan', 'plan-refresh-only', 'plan-destroy', 'apply') } else { @() }
            }
            '-format' {
                if ($subcmd -eq 'graph') { @('dot', 'mermaid') } else { @() }
            }
            default { @() }
        }
        return $enums | Where-Object { $_ -like "$fVal*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new("${fName}=$_", $_, 'ParameterValue', $_) }
    }

    # Flag completions
    if ($wordToComplete.StartsWith('-')) {
        $lookupKey = if ($subcmd2) { "$subcmd $subcmd2" } else { $subcmd }
        $flags = if (-not $subcmd) {
            @('-chdir=', '-help', '-version')
        } elseif ($tfSubcmdFlags.ContainsKey($lookupKey)) {
            $tfSubcmdFlags[$lookupKey]
        } elseif ($subcmd -eq 'stacks' -and $subcmd2) {
            @('-usage')
        } else {
            @('-help')
        }
        return $flags | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterName', $_) }
    }

    # Root and nested subcommand completions
    if (-not $subcmd) {
        return $tfRootSubcmds | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }
    if ($subcmd -and -not $subcmd2 -and $tfNestedSubcmds.ContainsKey($subcmd)) {
        return $tfNestedSubcmds[$subcmd] | Where-Object { $_ -like "$wordToComplete*" } |
            ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
    }

    return (& $resolveTfPaths $wordToComplete $false $true) |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# .NET CLI
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $wordToComplete
    dotnet complete --position $cursorPosition "$commandAst" |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}

# Mise CLI (static fallback when completions_cache.ps1 is not yet compiled)
Register-ArgumentCompleter -Native -CommandName mise -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $null = $commandAst; $null = $cursorPosition
    $commands = @('install', 'upgrade', 'prune', 'use', 'ls', 'current', 'run', 'env', 'exec', 'activate', 'bin-paths', 'settings', 'plugins')
    $commands | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
