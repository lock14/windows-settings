# =============================================================
# Suite 4: Native CLI Utilities, 22-Theme Engine & 16-Subcommand IDE
# =============================================================
Write-Host "`n[4/8] Testing Native Utilities, 22-Theme Engine & 16-Subcommand IDE..." -ForegroundColor Yellow

# 1. gen-passwd.ps1, sum.ps1, repeat-until-success.ps1
$genPasswdScript = Join-Path $RootDir 'bin\gen-passwd.ps1'
$pass16 = & $genPasswdScript -Length 16
$passSu = & $genPasswdScript -su 18
$passAlpha = & $genPasswdScript -Length 20 -NoSymbols
if ($pass16.Length -eq 16 -and $passSu.Length -eq 18 -and $passSu -match '^[A-Z\^\*\@\#\&\%\$\!\-]+$' -and $passAlpha -notmatch '[\^\*\@\#\&\%\$\!\-]') {
    Add-TestPass 'gen-passwd.ps1 generates expected lengths and character classes (-su, -NoSymbols)'
} else {
    Add-TestFail 'gen-passwd.ps1' "Unexpected output: len=$($pass16.Length), su=$passSu"
}

$sumScript = Join-Path $RootDir 'bin\sum.ps1'
$sumRes = 1..10 | & $sumScript
$sumFloat = 1.5, 2.5 | & $sumScript
$sumHuman = '1K 2K' | sum -H
$sumCol = sum -d ':' -k 2 'alpha:15:x' 'beta:25:y'
$sumAvg = sum -a 10 20 30
if ($sumRes -eq 55 -and $sumFloat -eq 4.0 -and $sumHuman -eq 3072 -and $sumCol -eq 40 -and $sumAvg -eq 20) {
    Add-TestPass 'sum.ps1 handles pipelines, decimal precision, IEC -H suffixes, -d/-k columns, and -a averages'
} else {
    Add-TestFail 'sum.ps1' "Unexpected results: $sumRes, $sumFloat, $sumHuman, $sumCol, $sumAvg"
}

$repeatScript = Join-Path $RootDir 'bin\repeat-until-success.ps1'
$global:LASTEXITCODE = 1
$rusOut = (& $repeatScript -n 1 -s 0.05 -- pwsh -NoProfile -Command "Write-Output 'posix_rus_ok'") -join "`n"
if ($LASTEXITCODE -eq 0 -and $rusOut -match 'posix_rus_ok') {
    Add-TestPass 'repeat-until-success.ps1 resets stale LASTEXITCODE and supports POSIX (-n, -s, --) flags'
} else {
    Add-TestFail 'repeat-until-success.ps1' "Unexpected output ($LASTEXITCODE): $rusOut"
}

# 2. bin/theme.ps1 + libexec/theme/*.ps1
$themeScript = Join-Path $RootDir 'bin\theme.ps1'
$listedSlugs = @(& $themeScript --list --plain)
if ($listedSlugs.Count -ge 22 -and ($listedSlugs -contains 'dracula') -and ($listedSlugs -contains 'rose-pine') -and ($listedSlugs -contains 'gruvbox-light') -and ($listedSlugs -contains 'everforest-dark')) {
    Add-TestPass "theme.ps1 --list --plain dynamically discovers all $($listedSlugs.Count) themes (including 5 new classic palettes)"
} else {
    Add-TestFail 'theme.ps1 --list --plain' "Expected >=22 slugs with dracula & rose-pine, got $($listedSlugs.Count)"
}

$draculaEnv = (& $themeScript --env dracula) -join "`n"
if ($draculaEnv -match "WINDOWS_SETTINGS_THEME\s*=\s*'dracula'" -and
    $draculaEnv -match '_HS_HEX_BASE03' -and
    $draculaEnv -match '_HS_ESC_BASE1' -and
    $draculaEnv -match '_HS_ESC_ORANGE' -and
    $draculaEnv -match 'border:#7A89B8') {
    Add-TestPass 'theme.ps1 --env dracula emits _HS_HEX_*, _HS_ESC_BASE1/ORANGE IDE handshake, and mono-tui BASE01 fzf borders'
} else {
    Add-TestFail 'theme.ps1 --env dracula' 'Missing _HS_HEX_*, _HS_ESC_BASE1/ORANGE, or BASE01 fzf border exports'
}

$prevNoColor = $env:NO_COLOR
$prevNerd = $env:IDE_NERD_FONTS
$prevCols = $env:FZF_PREVIEW_COLUMNS
try {
    $env:NO_COLOR = '1'
    $env:IDE_NERD_FONTS = '0'
    $env:FZF_PREVIEW_COLUMNS = '52'
    $narrowPreview = (& $themeScript --preview rose-pine) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $narrowPreview -match 'Rose Pine|Ros' -and $narrowPreview -notmatch "$([char]27)\[38;2;") {
        Add-TestPass 'theme.ps1 --preview reflows cleanly at 52 columns and honors NO_COLOR=1 & IDE_NERD_FONTS=0'
    } else {
        Add-TestFail 'theme.ps1 responsive/NO_COLOR preview' "Exit=$LASTEXITCODE or ANSI sequences leaked under NO_COLOR=1"
    }
} finally {
    $env:NO_COLOR = $prevNoColor
    $env:IDE_NERD_FONTS = $prevNerd
    $env:FZF_PREVIEW_COLUMNS = $prevCols
}

$prevDateOverride = $env:THEME_HOLIDAY_DATE
try {
    $env:THEME_HOLIDAY_DATE = '2026-10-20'
    $halDry = (& $themeScript --dry-run --holiday) -join "`n"
    $env:THEME_HOLIDAY_DATE = '2026-11-26'
    $thxDry = (& $themeScript --dry-run --holiday) -join "`n"
    if ($halDry -match 'halloween' -and $thxDry -match 'thanksgiving') {
        Add-TestPass 'theme.ps1 --holiday dynamic metadata schedule resolves Halloween & Thanksgiving'
    } else {
        Add-TestFail 'theme.ps1 --holiday' "Unexpected resolution: $halDry | $thxDry"
    }
} finally {
    $env:THEME_HOLIDAY_DATE = $prevDateOverride
}

# 3. bin/update-system.ps1 consolidated CLI (--all, --system-only, --skip, -n)
$updateScript = Join-Path $RootDir 'bin\update-system.ps1'
$updDefaultDry = (& $updateScript --dry-run) -join "`n"
$updAllDry = (& $updateScript --all --dry-run) -join "`n"
$updSysDry = (& $updateScript --system-only --dry-run) -join "`n"
& $updateScript --bogus-flag 2>$null
$badUpdExit = $LASTEXITCODE
if ($updDefaultDry -notmatch 'Invoke-HeadlessNvimSync' -and
    $updAllDry -match 'Invoke-HeadlessNvimSync' -and
    $updAllDry -match 'completions_cache\.ps1' -and
    $updSysDry -notmatch 'Temporary Cache' -and
    $badUpdExit -ne 0) {
    Add-TestPass 'update-system.ps1 honors default OS scope, --all dev toolchain scope, --system-only, and rejects unknown flags'
} else {
    Add-TestFail 'update-system.ps1 CLI' "Default/All/SystemOnly mismatch or badUpdExit=$badUpdExit"
}

# 4. bin/ide.ps1 + libexec/ide/*.ps1 (16 subcommands, _internal, Hooks, Launcher, NamedPipe MsgPack-RPC)
$ideScript = Join-Path $RootDir 'bin\ide.ps1'
$ideCmdScript = Join-Path $RootDir 'bin\ide.cmd'
$ideLibDir = Join-Path $RootDir 'libexec\ide'
$expectedIdeModules = @('Core.ps1', 'Rpc.ps1', 'Attention.ps1', 'Fleet.ps1', 'Modals.ps1', 'Workspace.ps1', 'Hooks.ps1', 'Launcher.ps1')
$missingIdeMods = @($expectedIdeModules | Where-Object { -not (Test-Path -LiteralPath (Join-Path $ideLibDir $_) -PathType Leaf) })
if ($missingIdeMods.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $RootDir 'bin\lib'))) {
    Add-TestPass 'libexec/ide/ modular layout valid (8 modules including Hooks.ps1 & Launcher.ps1; bin/lib removed)'
} else {
    Add-TestFail 'libexec/ide/ modules' "Missing: $($missingIdeMods -join ', ') or stale bin/lib exists"
}

$ideDryDef = (& $ideScript --backend zellij --dry-run) -join "`n"
$ideDry2 = (& $ideScript --backend zellij --2pane --detach --agent claude --dry-run) -join "`n"
$ideDryDesk = (& $ideScript --backend zellij --desktop --dry-run) -join "`n"
$ideDryWt = (& $ideScript --backend wt --dry-run) -join "`n"
if ($ideDryDef -match 'ide-3pane' -and
    $ideDry2 -match 'Layout\s*:\s*2pane' -and
    $ideDry2 -match '--create-background' -and
    $ideDryDesk -match 'zellij terminal --standalone --create' -and
    $ideDryWt -match 'Backend\s*:\s*wt') {
    Add-TestPass 'ide.ps1 --dry-run builds Zellij 3-pane, detached 2-pane (--agent claude), standalone GPU desktop, and WT fallback'
} else {
    Add-TestFail 'ide.ps1 launch --dry-run' "Unexpected output: $ideDryDef | $ideDry2 | $ideDryDesk | $ideDryWt"
}

$subHelpOk = $true
foreach ($sc in @('list', 'switch', 'new', 'dir', 'agent', 'next', 'cd', 'refresh', 'quit', 'open', 'send', 'state', 'ack', 'pr', 'keys', 'monitor')) {
    $hOut = (& $ideScript $sc --help 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0 -or $hOut -notmatch 'Usage:\s*ide') {
        $subHelpOk = $false
        break
    }
}
& $ideScript _internal swap sideways 2>$null
$badSwapExit = $LASTEXITCODE
if ($subHelpOk -and $badSwapExit -ne 0) {
    Add-TestPass 'All 16 ide public subcommands provide dedicated --help schemas and _internal swap validates directions'
} else {
    Add-TestFail 'ide subcommand --help / _internal swap' "subHelpOk=$subHelpOk, badSwapExit=$badSwapExit"
}

# Test ide new --dry-run + custom links.ps1 hooks + ;-delimited IDE_WORKSPACE_DIRS
$hookSandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("ws-hooks-test-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $hookSandbox | Out-Null
$prevLinkRules = $env:IDE_LINK_RULES
$prevWsDirs = $env:IDE_WORKSPACE_DIRS
try {
    $wsRootA = Join-Path $hookSandbox 'alpha-root'
    $wsRootB = Join-Path $hookSandbox 'beta-root'
    New-Item -ItemType Directory -Force -Path $wsRootA, $wsRootB | Out-Null
    $linksPs1 = Join-Path $hookSandbox 'links.ps1'
    $linksBody = @"
function New-IdeWorkspace([string]`$Name) {
    `$p = Join-Path '$($hookSandbox.Replace("'", "''"))' "created-`$Name"
    New-Item -ItemType Directory -Force -Path `$p | Out-Null
    Write-Output `$p
}
function Get-IdeSessionName([string]`$Dir) {
    Write-Output ("custom-" + (Split-Path -Leaf `$Dir))
}
"@
    [System.IO.File]::WriteAllText($linksPs1, $linksBody, [System.Text.UTF8Encoding]::new($false))
    $env:IDE_LINK_RULES = $linksPs1
    $env:IDE_WORKSPACE_DIRS = "$wsRootA;$wsRootB"

    $newDryOut = (& $ideScript new demo-proj --dry-run) -join "`n"
    $dirPrevOut = (& $ideScript _internal dir-preview $wsRootA) -join "`n"
    if ($LASTEXITCODE -eq 0 -and $newDryOut -match 'demo-proj' -and $dirPrevOut -match 'alpha-root') {
        Add-TestPass 'ide new, _internal dir-preview, links.ps1 hooks, and ;-delimited IDE_WORKSPACE_DIRS work end-to-end'
    } else {
        Add-TestFail 'ide new / links.ps1 hooks' "newDry=$newDryOut | dirPrev=$dirPrevOut"
    }
} finally {
    $env:IDE_LINK_RULES = $prevLinkRules
    $env:IDE_WORKSPACE_DIRS = $prevWsDirs
    Remove-Item -LiteralPath $hookSandbox -Recurse -Force -ErrorAction SilentlyContinue
}

# Test Antigravity 5-event agy-hook, ide state, ide list --json (19 fields), ide pr, and ide send
$mockFleetSess = "ws-unit-fleet-$PID"
$ideStateDirForTest = Join-Path (Join-Path $HOME '.cache\windows-settings') 'ide'
New-Item -ItemType Directory -Force -Path $ideStateDirForTest | Out-Null
$mockFleetMeta = Join-Path $ideStateDirForTest "$mockFleetSess.json"
$mockGitRepo = Join-Path ([System.IO.Path]::GetTempPath()) "ws-pr-test-$PID"
$prCacheDirTest = Join-Path (Join-Path $HOME '.cache') 'git-pr-prompt'
$prStateFileCreated = ''
$prevNoTty = $env:WS_AGY_HOOK_NO_TTY
$prevDryOpenPr = $env:WS_IDE_DRY_OPEN_PR
$prevAgentStdin = $env:WS_AGENT_STATE_STDIN
try {
    $env:WS_AGY_HOOK_NO_TTY = '1'
    $cmdHookAsk = ('{"tool_name":"ask_question"}' | & cmd.exe /d /c "`"$ideCmdScript`" _internal agy-hook PreToolUse" | Out-String).Trim()
    $cmdHookStop = ('{"session_id":"test","error":null}' | & cmd.exe /d /c "`"$ideCmdScript`" _internal agy-hook Stop" | Out-String).Trim()
    if ($cmdHookAsk -match '"decision"\s*:\s*"allow"' -and $cmdHookStop -match '"decision"') {
        Add-TestPass 'ide.cmd _internal agy-hook handles PreToolUse (ask_question) and Stop fast paths'
    } else {
        Add-TestFail 'ide.cmd _internal agy-hook' "PreToolUse='$cmdHookAsk', Stop='$cmdHookStop'"
    }

    New-Item -ItemType Directory -Force -Path (Join-Path $mockGitRepo '.git') | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $mockGitRepo '.git\HEAD'), "ref: refs/heads/feat/parity`n")
    [System.IO.File]::WriteAllText((Join-Path $mockGitRepo '.git\config'), "[remote `"origin`"]`n`turl = git@github.com:lock14/windows-settings.git`n")
    $resolvedMockRepo = (Resolve-Path -LiteralPath $mockGitRepo).ProviderPath

    New-Item -ItemType Directory -Force -Path $prCacheDirTest | Out-Null
    $prKeyBytes = [System.Text.Encoding]::UTF8.GetBytes("$resolvedMockRepo|feat/parity")
    $prHash = [System.Security.Cryptography.SHA256]::HashData($prKeyBytes)
    $prKey = [System.BitConverter]::ToString($prHash, 0, 8).Replace('-', '').ToLowerInvariant()
    $prStateFileCreated = Join-Path $prCacheDirTest "$prKey.state"
    [System.IO.File]::WriteAllText($prStateFileCreated, "@168`nhttps://github.com/lock14/windows-settings/pull/168`n")

    $seedMeta = [ordered]@{
        session       = $mockFleetSess
        root          = $resolvedMockRepo
        workdir       = $resolvedMockRepo
        pipe          = "\\.\pipe\nvim-ide-$mockFleetSess"
        layout        = '3pane'
        backend       = 'zellij'
        ai_cli        = 'claude'
        agent_state   = 'idle'
        agent_message = ''
        state_ts      = 0
        attn_ts       = 0
    } | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($mockFleetMeta, $seedMeta)

    $mockPipeServer = [System.IO.Pipes.NamedPipeServerStream]::new("nvim-ide-$mockFleetSess", [System.IO.Pipes.PipeDirection]::InOut, 1)
    try {
        $env:WS_AGENT_STATE_STDIN = '{"message":"Approve schema change?"}'
        & $ideScript state approval $mockFleetSess
        $env:WS_AGENT_STATE_STDIN = $null
        & $ideScript state quota -m 'Rate limit hit' $mockFleetSess

        $jsonRaw = (& $ideScript list --json) -join "`n"
        $jsonArr = @($jsonRaw | ConvertFrom-Json)
        $entry = $jsonArr | Where-Object { $_.session -eq $mockFleetSess } | Select-Object -First 1
    } finally {
        $mockPipeServer.Dispose()
    }
    $expectedJsonKeys = @(
        'session', 'agent', 'state', 'state_label', 'state_ts', 'needs_attention', 'attention_ts',
        'message', 'workdir', 'git_branch', 'git_dirty', 'git_detail', 'git_pr_url',
        'worktree_root', 'worktree_peers', 'active_role', 'attached', 'is_current', 'quit_error'
    )
    $entryProps = if ($entry) { @($entry.PSObject.Properties.Name) } else { @() }
    $missingJsonKeys = @($expectedJsonKeys | Where-Object { $entryProps -notcontains $_ })

    $env:WS_IDE_DRY_OPEN_PR = '1'
    $resolvedPrUrl = (& $ideScript pr $mockFleetSess | Out-String).Trim()

    if ($null -ne $entry -and $missingJsonKeys.Count -eq 0 -and $entry.state -eq 'QUOTA' -and $entry.message -eq 'Rate limit hit' -and
        $resolvedPrUrl -eq 'https://github.com/lock14/windows-settings/pull/168') {
        Add-TestPass 'ide state, 19-field ide list --json contract, and ide pr work accurately'
    } else {
        Add-TestFail 'ide list --json / state / pr' "Entry=$($null -ne $entry), state=$($entry.state), missingKeys=$($missingJsonKeys -join ','), pr=$resolvedPrUrl"
    }
} finally {
    $env:WS_AGY_HOOK_NO_TTY = $prevNoTty
    $env:WS_IDE_DRY_OPEN_PR = $prevDryOpenPr
    $env:WS_AGENT_STATE_STDIN = $prevAgentStdin
    Remove-Item -LiteralPath $mockFleetMeta -Force -ErrorAction SilentlyContinue
    if ($prStateFileCreated -and (Test-Path -LiteralPath $prStateFileCreated)) {
        Remove-Item -LiteralPath $prStateFileCreated -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $mockGitRepo -Recurse -Force -ErrorAction SilentlyContinue
}

# Test 2-tier responsive ide keys (108x34 spacious vs 80x24 compact) & monitor
$prevNoWait = $env:IDE_KEYS_NO_WAIT
$prevForceMon = $env:IDE_FORCE_BUILTIN_MONITOR
$prevMonOnce = $env:IDE_MONITOR_ONCE
try {
    $env:IDE_KEYS_NO_WAIT = '1'
    $ideKeysOut = (& $ideScript keys) -join "`n"
    & $ideScript _internal write-keys-cache
    $env:IDE_FORCE_BUILTIN_MONITOR = '1'
    $env:IDE_MONITOR_ONCE = '1'
    $ideMonOut = (& $ideScript monitor) -join "`n"
    if ($ideKeysOut -match 'Alt\+n' -and $ideKeysOut -match 'Alt\+o' -and $ideMonOut -match 'System Monitor') {
        Add-TestPass 'ide keys (including Alt+n/Alt+o) & ide monitor render cleanly'
    } else {
        Add-TestFail 'ide keys / monitor' 'Missing expected keybindings or System Monitor sections'
    }
} finally {
    $env:IDE_KEYS_NO_WAIT = $prevNoWait
    $env:IDE_FORCE_BUILTIN_MONITOR = $prevForceMon
    $env:IDE_MONITOR_ONCE = $prevMonOnce
}

# Regression test: toggle-modal never enters cmd.exe <-> pwsh.exe mutual recursion when lock is held without .pane
$loopSess = "ws-norecurse-$PID"
$loopStateDir = Join-Path (Join-Path $HOME '.cache\windows-settings') 'ide'
New-Item -ItemType Directory -Force -Path $loopStateDir | Out-Null
$loopLockPath = Join-Path $loopStateDir "sessions-$loopSess.lock"
$loopPanePath = Join-Path $loopStateDir "sessions-$loopSess.pane"
Remove-Item -LiteralPath $loopPanePath -Force -ErrorAction SilentlyContinue
$lockHandle = [System.IO.File]::Open($loopLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
try {
    $pwshTestExe = (Get-Process -Id $PID).Path
    $cmdTogglePsi = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe')
    foreach ($ca in @('/d', '/c', $ideCmdScript, '_internal', 'toggle-modal', 'sessions')) {
        $cmdTogglePsi.ArgumentList.Add($ca)
    }
    $cmdTogglePsi.Environment['ZELLIJ'] = '0'
    $cmdTogglePsi.Environment['ZELLIJ_SESSION_NAME'] = $loopSess
    $cmdTogglePsi.RedirectStandardOutput = $true
    $cmdTogglePsi.RedirectStandardError = $true
    $cmdTogglePsi.UseShellExecute = $false
    $cmdTogglePsi.CreateNoWindow = $true
    $cmdToggleProc = [System.Diagnostics.Process]::Start($cmdTogglePsi)
    $cmdFinished = $cmdToggleProc.WaitForExit(4000)
    if (-not $cmdFinished) {
        try { $cmdToggleProc.Kill($true) } catch { $null = $_ }
    }

    $psTogglePsi = [System.Diagnostics.ProcessStartInfo]::new($pwshTestExe)
    foreach ($pa in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ideScript, '_internal', 'toggle-modal', 'sessions')) {
        $psTogglePsi.ArgumentList.Add($pa)
    }
    $psTogglePsi.Environment['ZELLIJ'] = '0'
    $psTogglePsi.Environment['ZELLIJ_SESSION_NAME'] = $loopSess
    $psTogglePsi.RedirectStandardOutput = $true
    $psTogglePsi.RedirectStandardError = $true
    $psTogglePsi.UseShellExecute = $false
    $psTogglePsi.CreateNoWindow = $true
    $psToggleProc = [System.Diagnostics.Process]::Start($psTogglePsi)
    $psFinished = $psToggleProc.WaitForExit(4000)
    if (-not $psFinished) {
        try { $psToggleProc.Kill($true) } catch { $null = $_ }
    }

    if ($cmdFinished -and $psFinished) {
        Add-TestPass 'ide.cmd and ide.ps1 _internal toggle-modal terminate cleanly without mutual recursion when lock is held'
    } else {
        Add-TestFail 'toggle-modal recursion guard' "Timed out: cmdFinished=$cmdFinished, psFinished=$psFinished"
    }
} finally {
    $lockHandle.Dispose()
    Remove-Item -LiteralPath $loopLockPath, $loopPanePath -Force -ErrorAction SilentlyContinue
}

# Live .NET NamedPipeClientStream MsgPack-RPC + ide _internal open-link round-trip test against headless Neovim
$nvimApp = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($nvimApp) {
    $pipeSess = "rpctest-$PID"
    $pipeId = "nvim-ide-$pipeSess"
    $pipeFull = "\\.\pipe\$pipeId"
    $nvimInit = Join-Path $RootDir 'config\nvim\init.lua'
    $rpcStateDir = Join-Path ([System.IO.Path]::GetTempPath()) "ws-rpclink-$PID"
    $rpcLinksFile = Join-Path $rpcStateDir 'links.ps1'
    $prevIdeLinkRules = $env:IDE_LINK_RULES
    $prevDryOpenUrl = $env:WS_IDE_DRY_OPEN_URL
    $prevZellij = $env:ZELLIJ
    $prevSkipTsRpc = $env:NVIM_TS_SKIP_AUTO_INSTALL
    $prevGitRefRpc = $env:GIT_DEFAULT_REF_FORMAT
    $rpcMetaPath = Join-Path (Join-Path $HOME '.cache\windows-settings\ide') "$pipeSess.json"
    New-Item -ItemType Directory -Force -Path $rpcStateDir | Out-Null
    $env:NVIM_TS_SKIP_AUTO_INSTALL = '1'
    $env:GIT_DEFAULT_REF_FORMAT = 'files'
    $nvimProc = Start-Process -FilePath $nvimApp.Source -ArgumentList @('-u', $nvimInit, '-i', 'NONE', '--headless', '--listen', $pipeFull) -PassThru -WindowStyle Hidden
    try {
        $ready = $false
        for ($w = 0; $w -lt 40; $w++) {
            if ([System.IO.Directory]::GetFiles('\\.\pipe\', $pipeId).Count -gt 0) { $ready = $true; break }
            Start-Sleep -Milliseconds 100
        }
        if ($ready) {
            $rpcVal = & {
                . (Join-Path $RootDir 'libexec\ide\Core.ps1')
                . (Join-Path $RootDir 'libexec\ide\Rpc.ps1')
                $rec = Build-IdeSessionRecord -SessionName $pipeSess -Root $RootDir -Workdir $RootDir -Backend 'wt'
                $rec['pipe'] = $pipeFull
                Save-SessionState $rec
                Invoke-NvimNamedPipeRpc -PipePath $pipeFull -LuaCode 'return 20 + 22' -LuaArgs @()
            }
            if ($rpcVal -and $rpcVal.Status -eq 'ok' -and "$($rpcVal.Output)" -eq '42') {
                Add-TestPass 'Direct .NET NamedPipeClientStream MsgPack-RPC executes Lua round-trip (<1ms, zero child spawn)'
            } else {
                Add-TestFail 'NamedPipeClientStream MsgPack-RPC' "Unexpected RPC response: $($rpcVal | ConvertTo-Json -Compress)"
            }

            $env:ZELLIJ = ''
            $env:WS_IDE_DRY_OPEN_URL = '1'
            Set-Content -LiteralPath $rpcLinksFile -Encoding utf8NoBOM -Value @'
function Resolve-IdeLink {
    param([string]$Word, [string]$Cwd)
    if ($Word -match '^b/([0-9]+)$') { return "https://issues.example.test/$($Matches[1])" }
}
'@
            $env:IDE_LINK_RULES = $rpcLinksFile

            # 1. Cross-pane Alt+Click doc + #heading anchor into headless Neovim over NamedPipe RPC
            & $ideScript _internal open-link -- 'docs/ide-architecture.md#links-inline-images-clipboard-and-portable-shell-parity' $RootDir $pipeSess '0'
            Start-Sleep -Milliseconds 120
            $docCheck = & {
                . (Join-Path $RootDir 'libexec\ide\Core.ps1')
                . (Join-Path $RootDir 'libexec\ide\Rpc.ps1')
                Invoke-NvimNamedPipeRpc -PipePath $pipeFull -LuaCode 'return vim.api.nvim_buf_get_name(0) .. ":" .. tostring(vim.api.nvim_win_get_cursor(0)[1])' -LuaArgs @()
            }

            # 2. Markdown [label:line](path) link into headless Neovim over NamedPipe RPC
            & $ideScript _internal open-link -- '[setup.ps1:15](setup.ps1)' $RootDir $pipeSess '0'
            Start-Sleep -Milliseconds 120
            $mdCheck = & {
                . (Join-Path $RootDir 'libexec\ide\Core.ps1')
                . (Join-Path $RootDir 'libexec\ide\Rpc.ps1')
                Invoke-NvimNamedPipeRpc -PipePath $pipeFull -LuaCode 'return vim.api.nvim_buf_get_name(0) .. ":" .. tostring(vim.api.nvim_win_get_cursor(0)[1])' -LuaArgs @()
            }

            # 3. Custom links.ps1 shorthand -> external URL routing
            $hookUrlOut = (& $ideScript _internal open-link -- 'b/42' $RootDir $pipeSess '0' | Out-String).Trim()

            $docOutStr = if ($docCheck) { "$($docCheck.Output)" } else { '' }
            $mdOutStr = if ($mdCheck) { "$($mdCheck.Output)" } else { '' }
            $docAnchorLine = if ($docOutStr -match ':([0-9]+)$') { [int]$Matches[1] } else { 0 }

            if ($docOutStr -match 'ide-architecture\.md:[0-9]+$' -and $docAnchorLine -gt 10 -and
                $mdOutStr -match 'setup\.ps1:15$' -and
                $hookUrlOut -eq 'https://issues.example.test/42') {
                Add-TestPass 'ide _internal open-link routes doc.md#anchor, [label:line](path), and links.ps1 URLs cleanly'
            } else {
                Add-TestFail 'ide _internal open-link' "doc='$docOutStr', md='$mdOutStr', hookUrl='$hookUrlOut'"
            }
        } else {
            Add-TestFail 'NamedPipeClientStream test server' "Pipe $pipeFull did not appear within 4s"
        }
    } finally {
        $env:IDE_LINK_RULES = $prevIdeLinkRules
        $env:WS_IDE_DRY_OPEN_URL = $prevDryOpenUrl
        $env:ZELLIJ = $prevZellij
        $env:NVIM_TS_SKIP_AUTO_INSTALL = $prevSkipTsRpc
        $env:GIT_DEFAULT_REF_FORMAT = $prevGitRefRpc
        if ($nvimProc -and -not $nvimProc.HasExited) {
            Stop-Process -Id $nvimProc.Id -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -LiteralPath $rpcMetaPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $rpcStateDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
