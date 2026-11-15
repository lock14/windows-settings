<#
.SYNOPSIS
    Cross-Platform Hybrid Terminal IDE & Agent Session Manager (Zellij 0.46+ + Neovim RPC + AI).
.DESCRIPTION
    Windows & cross-platform counterpart to home-settings/bin/ide powered by Zellij 0.46+ (with
    Windows Terminal wt.exe fallback). Provides persistent multi-repo AI agent sessions, native
    OSC 7501 Attention Inbox & live session previews (Alt+s / Alt+Shift+S), opt-in 1-hop GPU
    desktop window + OS System Tray & notifications (--desktop), Neovim Named Pipe RPC
    (\\.\pipe\nvim-ide-<session>), direct bracketed-paste context dispatch (--send), synchronized
    directory diving (icd / :IdeCd), and unsaved-buffer protected workspace exit (:Q / qide / quit).
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

$script:UsageText = @"
Usage: ide [OPTIONS] [DIRECTORY]

Launch or manage a Zellij + Neovim RPC + AI Agent IDE workspace session.

Options:
  --3pane                  Launch default 3-pane Inverted-T layout (Top-Left AI, Top-Right Editor, Bottom Shell)
  --2pane                  Launch 2-pane side-by-side layout (Left AI, Right Editor)
  -d, --detach             Start or ensure the workspace session runs detached in the background
  --desktop                Open in Zellij's 1-hop GPU desktop terminal (with System Tray & OS notifications)
  --new-window             Open workspace in a new Windows Terminal window
  --backend <zellij|wt>    Select multiplexer backend: zellij (default) or wt (split-pane fallback)
  --ai, --agent <CLI>      Select AI CLI agent: agy (default), claude, or codex (overrides `$env:IDE_AI_CLI)
  -s, --sessions           Open Zellij Session Manager + Attention Inbox (or fzf session switcher outside Zellij)
  --next-attention         Jump directly to the next agent pane needing attention across all sessions
  --toggle                 Bounce focus between Editor and AI Agent panes
  --focus-role <ROLE>      Focus pane role (ai, editor, or term), bouncing back if already focused
  -n, --dry-run            Preview workspace session metadata and launch command without mutating state
  --open <FILE> [LINE]     Open <FILE> in the IDE Editor pane via Named Pipe RPC
  --preview <FILE> [LINE]  Preview <FILE> in the IDE Editor pane via Named Pipe RPC
  --open-or-edit <FILE> [LINE] Open <FILE> in IDE Editor via RPC if live, else launch local Neovim
  cd, --cd [DIR]           Dive into <DIR> (or --reset / ~ for initial root) across Editor and session state
  --send [OPTS] [SESSION]  Inject context (--stdin, --ref <PATH>[:L1[-L2]], --text <TEXT>, --no-focus, --switch)
                           directly into target session's AI Agent prompt via bracketed paste
  --agent-state <STATE> [--message <TEXT>] [SESSION]
                           Emit OSC 7501 status & record state: running, approval, quota, done, error, or idle
  --agy-hook <EVENT>       Internal Antigravity CLI hook adapter (PreInvocation, Stop, SessionStart)
  --ack-ai [SESSION...]    Acknowledge AI attention across one or more IDE sessions
  --open-pr [SESSION]      Open cached or active GitHub/GitLab Pull Request URL in browser
  --monitor, --top         Toggle interactive system monitor (btop4win -> btop -> btm -> ntop -> built-in TUI)
  --keys, --help-keys      Display the TrueColor IDE workspace & editor keybinding cheatsheet
  refresh, -r, --refresh [NAME]
                           Refresh active color theme across live IDE Neovim servers & Zellij config
  quit, -q, --quit [NAME...]
                           Safely quit IDE session(s) NAME (verifies zero unsaved Neovim buffers first)
  -f, --force              Force-quit when used with --quit (discards unsaved Neovim buffers)
  kill, --kill [NAME...]   Force-quit IDE session(s) NAME without the unsaved-buffer check
  -l, --list [--plain]     List IDE workspace sessions with status, layout, AI CLI, branch, and directory
  -h, --help               Show this help message and exit

Environment Variables:
  IDE_AI_CLI               AI CLI tool for the AI Agent pane: agy (default), claude, or codex
  IDE_DESKTOP              Set to '1' to default 'ide' to Zellij's GPU desktop window (--desktop)
  IDE_BACKEND              Multiplexer backend override: zellij (default) or wt
  IDE_BROWSER              Optional browser executable for opening http(s):// links
  IDE_SESSION              Current IDE workspace session slug (set automatically inside IDE panes)
  NVIM_IDE_SOCKET          Current Neovim Named Pipe path (\\.\pipe\nvim-ide-<session>)
"@

function Write-TextUtf8NoBom([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-IdeStateDir {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cacheBase = Join-Path (Join-Path $userHome '.cache') 'windows-settings'
    return (Join-Path $cacheBase 'ide')
}

function Get-SanitizedToken([string]$Raw) {
    if (-not $Raw) { return 'workspace' }
    $cleaned = [regex]::Replace($Raw, '[.: ]', '-')
    $cleaned = [regex]::Replace($cleaned, '[^A-Za-z0-9_-]', '').TrimStart('-')
    if (-not $cleaned) { return 'workspace' }
    return $cleaned
}

function Get-SanitizedSessionName([string]$TargetDir) {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cfgBase = if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        $env:XDG_CONFIG_HOME.Trim()
    } else {
        Join-Path $userHome '.config'
    }
    $hookPath = if ($env:IDE_LINK_RULES -and $env:IDE_LINK_RULES.Trim()) {
        $env:IDE_LINK_RULES.Trim()
    } else {
        Join-Path (Join-Path $cfgBase 'ide') 'links.ps1'
    }
    if (Test-Path -LiteralPath $hookPath -PathType Leaf) {
        try {
            $customName = & {
                . $hookPath
                if (Get-Command Get-IdeSessionName -ErrorAction SilentlyContinue) {
                    Get-IdeSessionName $TargetDir
                }
            }
            if ($customName -and "$customName".Trim()) {
                return (Get-SanitizedToken "$customName".Trim())
            }
        } catch {
            Write-Verbose "IDE session naming hook skipped: $_"
        }
    }
    $trimmed = if ($TargetDir) { $TargetDir.TrimEnd('\', '/') } else { '' }
    $leaf = if ($trimmed) { Split-Path -Leaf $trimmed } else { Split-Path -Leaf (Get-Location).ProviderPath }
    return (Get-SanitizedToken $leaf)
}

function Get-SessionPipePath([string]$SessionName) {
    return "\\.\pipe\nvim-ide-$SessionName"
}

function Get-SessionStatePath([string]$SessionName) {
    return (Join-Path (Get-IdeStateDir) "$SessionName.json")
}

function Get-RoleSidecarPath([string]$SessionName, [string]$Role) {
    return (Join-Path (Get-IdeStateDir) "$SessionName.pane-$Role")
}

function ConvertTo-ZellijPaneId([string]$RawId) {
    if (-not $RawId -or -not $RawId.Trim()) { return '' }
    $trimmed = $RawId.Trim()
    if ($trimmed -match '^[0-9]+$') {
        return "terminal_$trimmed"
    }
    return $trimmed
}

function Save-RolePaneId([string]$SessionName, [string]$Role, [string]$PaneId) {
    $norm = ConvertTo-ZellijPaneId $PaneId
    if (-not $norm) { return }
    Write-TextUtf8NoBom -Path (Get-RoleSidecarPath -SessionName $SessionName -Role $Role) -Content "$norm`n"
}

function Get-RolePaneId([string]$SessionName, [string]$Role) {
    $p = Get-RoleSidecarPath -SessionName $SessionName -Role $Role
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
    try {
        return (ConvertTo-ZellijPaneId (Get-Content -LiteralPath $p -Raw))
    } catch {
        return ''
    }
}

function Resolve-ZellijExecutable {
    $cmd = Get-Command zellij.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        $cmd = Get-Command zellij -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($cmd) {
        $src = $cmd.Source
        if ($src -match '(?i)[\\/]mise[\\/]shims[\\/]') {
            $miseRoot = Split-Path -Parent (Split-Path -Parent $src)
            $installsDir = Join-Path (Join-Path $miseRoot 'installs') 'zellij'
            if (Test-Path -LiteralPath $installsDir -PathType Container) {
                $realExe = Get-ChildItem -LiteralPath $installsDir -Filter 'zellij.exe' -Recurse -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1
                if ($realExe) { return $realExe.FullName }
            }
        }
        return $src
    }
    if ($env:LOCALAPPDATA) {
        $miseInstalls = Join-Path $env:LOCALAPPDATA 'mise\installs\zellij'
        if (Test-Path -LiteralPath $miseInstalls -PathType Container) {
            $realExe = Get-ChildItem -LiteralPath $miseInstalls -Filter 'zellij.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($realExe) { return $realExe.FullName }
        }
    }
    return ''
}

function Get-ZellijConfigDir {
    if ($env:ZELLIJ_CONFIG_DIR -and (Test-Path -LiteralPath $env:ZELLIJ_CONFIG_DIR.Trim() -PathType Container)) {
        return $env:ZELLIJ_CONFIG_DIR.Trim()
    }
    if ($env:APPDATA) {
        $appDataCfg = Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
        if (Test-Path -LiteralPath (Join-Path $appDataCfg 'config.kdl') -PathType Leaf) {
            return $appDataCfg
        }
    }
    $repoCfg = Join-Path (Join-Path $RepoDir 'config') 'zellij'
    if (Test-Path -LiteralPath (Join-Path $repoCfg 'config.kdl') -PathType Leaf) {
        return $repoCfg
    }
    if ($env:APPDATA) {
        return (Join-Path (Join-Path $env:APPDATA 'Zellij') 'config')
    }
    return (Join-Path (Join-Path $HOME '.config') 'zellij')
}

function Get-LiveZellijSessionMap {
    $map = @{}
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { return $map }
    try {
        $lines = @(& $zellijBin list-sessions -n 2>$null)
        if ($LASTEXITCODE -eq 0 -and $lines.Count -gt 0) {
            foreach ($ln in $lines) {
                $s = "$ln".Trim()
                if (-not $s -or $s -match '^No active zellij sessions') { continue }
                if ($s -match '^(\S+)\s*(.*)$') {
                    $name = $Matches[1]
                    $rest = $Matches[2]
                    $map[$name] = if ($rest -match 'EXITED') { 'exited' } else { 'live' }
                }
            }
        }
    } catch {
        Write-Verbose "Zellij session scan skipped: $_"
    }
    return $map
}

function Get-LiveIdePipeMap {
    $map = @{}
    try {
        foreach ($p in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
            if ($p -match '(?i)^\\\\\.\\pipe\\nvim-ide-(.+)$') {
                $map[$Matches[1]] = $p
            }
        }
    } catch {
        Write-Verbose "Named pipe scan skipped: $_"
    }
    return $map
}

function Test-IdePipeLive([string]$PipePath) {
    if (-not $PipePath) { return $false }
    try {
        if ([System.IO.File]::Exists($PipePath)) {
            return $true
        }
    } catch {
        Write-Verbose "Direct pipe existence check skipped: $_"
    }
    try {
        foreach ($p in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
            if ([string]::Equals($p, $PipePath, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    } catch {
        Write-Verbose "Pipe liveness check skipped: $_"
    }
    return $false
}

function Read-SessionState([string]$SessionName) {
    $metaPath = Get-SessionStatePath $SessionName
    if (-not (Test-Path -LiteralPath $metaPath -PathType Leaf)) {
        return $null
    }
    try {
        $raw = Get-Content -LiteralPath $metaPath -Raw
        $obj = $raw | ConvertFrom-Json
        $agentState = if ($obj.agent_state) { [string]$obj.agent_state } else { 'idle' }
        $sidecarStatePath = Join-Path (Get-IdeStateDir) "$SessionName.state"
        if ([System.IO.File]::Exists($sidecarStatePath)) {
            $sidecarTicks = [System.IO.File]::GetLastWriteTimeUtc($sidecarStatePath).Ticks
            $metaTicks = [System.IO.File]::GetLastWriteTimeUtc($metaPath).Ticks
            if ($sidecarTicks -ge $metaTicks) {
                $fastState = [System.IO.File]::ReadAllText($sidecarStatePath).Trim()
                if ($fastState) { $agentState = $fastState }
            }
        }
        $ht = [ordered]@{
            session       = if ($obj.session) { [string]$obj.session } else { $SessionName }
            root          = if ($obj.root) { [string]$obj.root } else { '' }
            workdir       = if ($obj.workdir) { [string]$obj.workdir } else { '' }
            pipe          = if ($obj.pipe) { [string]$obj.pipe } else { (Get-SessionPipePath $SessionName) }
            layout        = if ($obj.layout) { [string]$obj.layout } else { '3pane' }
            backend       = if ($obj.backend) { [string]$obj.backend } else { 'zellij' }
            ai_cli        = if ($obj.ai_cli) { [string]$obj.ai_cli } else { 'agy' }
            agent_state   = $agentState
            agent_message = if ($obj.agent_message) { [string]$obj.agent_message } else { '' }
            created_at    = if ($obj.created_at) { [string]$obj.created_at } else { '' }
            updated_at    = if ($obj.updated_at) { [string]$obj.updated_at } else { '' }
        }
        return $ht
    } catch {
        return $null
    }
}

function Save-SessionState([System.Collections.IDictionary]$Meta) {
    $SessionName = [string]$Meta['session']
    $Meta['updated_at'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if (-not $Meta['created_at']) {
        $Meta['created_at'] = $Meta['updated_at']
    }
    $json = ($Meta | ConvertTo-Json -Depth 6) + "`n"
    Write-TextUtf8NoBom -Path (Get-SessionStatePath $SessionName) -Content $json
    $sidecarStatePath = Join-Path (Get-IdeStateDir) "$SessionName.state"
    if ([System.IO.File]::Exists($sidecarStatePath)) {
        Remove-Item -LiteralPath $sidecarStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-TargetSession([string]$ArgValue = '') {
    if ($ArgValue -and $ArgValue.Trim()) {
        $candidate = $ArgValue.Trim()
        $existingMeta = Read-SessionState $candidate
        if ($existingMeta) { return $candidate }
        if (Test-Path -LiteralPath $candidate -PathType Container) {
            $fullDir = (Resolve-Path -LiteralPath $candidate).ProviderPath
            return (Get-SanitizedSessionName $fullDir)
        }
        return (Get-SanitizedToken $candidate)
    }
    if ($env:ZELLIJ_SESSION_NAME -and $env:ZELLIJ_SESSION_NAME.Trim()) {
        return (Get-SanitizedToken $env:ZELLIJ_SESSION_NAME.Trim())
    }
    if ($env:IDE_SESSION -and $env:IDE_SESSION.Trim()) {
        return (Get-SanitizedToken $env:IDE_SESSION.Trim())
    }
    return (Get-SanitizedSessionName (Get-Location).ProviderPath)
}

function Resolve-NvimExecutable {
    $cmd = Get-Command nvim.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) {
        $cmd = Get-Command nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ($cmd) {
        $src = $cmd.Source
        if ($src -match '(?i)[\\/]mise[\\/]shims[\\/]') {
            $miseRoot = Split-Path -Parent (Split-Path -Parent $src)
            $installsDir = Join-Path (Join-Path $miseRoot 'installs') 'neovim'
            if (Test-Path -LiteralPath $installsDir -PathType Container) {
                $realExe = Get-ChildItem -LiteralPath $installsDir -Filter 'nvim.exe' -Recurse -File -ErrorAction SilentlyContinue |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1
                if ($realExe) { return $realExe.FullName }
            }
        }
        return $src
    }
    return ''
}

function Resolve-AiExecutable([string]$RequestedCli) {
    $cli = if ($RequestedCli -and $RequestedCli.Trim()) { $RequestedCli.Trim() } else { 'agy' }
    if ($cli.ToLowerInvariant() -in @('none', 'shell', 'pwsh')) {
        return @{
            Name = 'shell'
            Path = ''
        }
    }
    if ($cli -eq 'openai') { $cli = 'codex' }

    $candidates = [System.Collections.Generic.List[string]]::new()
    $candidates.Add($cli)
    foreach ($fb in @('agy', 'claude', 'codex')) {
        if (-not $candidates.Contains($fb)) {
            $candidates.Add($fb)
        }
    }
    foreach ($cand in $candidates) {
        $hit = Get-Command $cand -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($hit) {
            return @{
                Name = $cand
                Path = $hit.Source
            }
        }
    }
    return @{
        Name = $cli
        Path = ''
    }
}

function Write-Osc7501Status([string]$StatusPayload) {
    if (-not $StatusPayload) { return }
    $esc = [char]27
    $seq = "${esc}]7501;${StatusPayload}${esc}\"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($seq)
    try {
        $fs = [System.IO.FileStream]::new(
            '\\.\CONOUT$',
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )
        try {
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush()
        } finally {
            $fs.Dispose()
        }
    } catch {
        Write-Verbose "OSC 7501 CONOUT write skipped: $_"
    }
}

function Format-Osc7501Spec([string]$StateName, [string]$Message = '', [string]$AppName = '') {
    $spec = switch ($StateName.ToLowerInvariant()) {
        'running'  { 'state=working' }
        'working'  { 'state=working' }
        'approval' { 'state=blocked:kind=permission' }
        'blocked'  { 'state=blocked:kind=permission' }
        'question' { 'state=blocked:kind=question' }
        'quota'    { 'state=blocked:kind=auth' }
        'done'     { 'state=done' }
        'error'    { 'state=error' }
        'failed'   { 'state=error' }
        default    { 'state=clear' }
    }
    if ($AppName) {
        $cleanApp = [regex]::Replace($AppName, '[^A-Za-z0-9._-]', '')
        if ($cleanApp) { $spec += ":app=$cleanApp" }
    }
    if ($Message -and $Message.Trim()) {
        $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Message.Trim()))
        $spec += ":msg=$b64"
    }
    return $spec
}

function Invoke-AgyHook([string]$HookEventArg) {
    $stdinRaw = ''
    if ($env:WS_HOOK_STDIN) {
        $stdinRaw = $env:WS_HOOK_STDIN
    } else {
        try {
            if ([Console]::IsInputRedirected) {
                $stdinRaw = [Console]::In.ReadToEnd()
            }
        } catch {
            $stdinRaw = ''
        }
    }

    $hookObj = $null
    if ($stdinRaw -and $stdinRaw.Trim()) {
        try {
            $hookObj = $stdinRaw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $hookObj = $null
        }
    }

    $eventName = if ($HookEventArg -and $HookEventArg.Trim()) {
        $HookEventArg.Trim()
    } elseif ($hookObj -and $hookObj.hookEventName) {
        [string]$hookObj.hookEventName
    } else {
        ''
    }

    $mappedState = 'idle'
    $oscSpec = 'state=clear:app=agy'
    $jsonReply = '{}'

    switch ($eventName) {
        'SessionStart' {
            $mappedState = 'idle'
            $oscSpec = 'state=idle:app=agy'
            $jsonReply = '{}'
        }
        'PreInvocation' {
            $mappedState = 'running'
            $oscSpec = 'state=working:app=agy'
            $jsonReply = '{}'
        }
        'Stop' {
            $termReason = if ($hookObj -and $hookObj.terminationReason) { [string]$hookObj.terminationReason } else { '' }
            $hasError = [bool]($hookObj -and $hookObj.error)
            if ($termReason -eq 'USER_CANCELED') {
                $mappedState = 'idle'
                $oscSpec = 'state=clear:app=agy'
            } elseif ($hasError -or ($termReason -match '(?i)ERROR|FAIL|ABORT')) {
                $mappedState = 'error'
                $oscSpec = 'state=error:app=agy'
            } else {
                $mappedState = 'done'
                $oscSpec = 'state=done:app=agy'
            }
            $jsonReply = '{"decision":"allow"}'
        }
        default {
            $oscSpec = ''
            $jsonReply = '{}'
        }
    }

    if ($oscSpec -and $env:WS_AGY_HOOK_NO_TTY -ne '1') {
        Write-Osc7501Status $oscSpec
    }

    if ($oscSpec -and ($env:IDE_SESSION -or $env:ZELLIJ_SESSION_NAME)) {
        try {
            $sess = Resolve-TargetSession ''
            $meta = Read-SessionState $sess
            if ($meta) {
                $meta['agent_state'] = $mappedState
                Save-SessionState $meta
            }
        } catch {
            Write-Verbose "Hook state update skipped: $_"
        }
    }

    Write-Output $jsonReply
    exit 0
}

function Invoke-NvimRemoteExpr([string]$PipePath, [string]$Expr, [int]$TimeoutMs = 2500) {
    $nvimBin = Resolve-NvimExecutable
    if (-not $nvimBin -or -not (Test-IdePipeLive $PipePath)) {
        return @{ Success = $false; Output = '' }
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $nvimBin
        $psi.ArgumentList.Add('--headless')
        $psi.ArgumentList.Add('--server')
        $psi.ArgumentList.Add($PipePath)
        $psi.ArgumentList.Add('--remote-expr')
        $psi.ArgumentList.Add($Expr)
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            return @{ Success = $false; Output = '' }
        }
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill() } catch { Write-Verbose 'Timed-out RPC client terminated' }
            return @{ Success = $false; Output = '' }
        }
        $stdout = $proc.StandardOutput.ReadToEnd().Trim()
        return @{
            Success = ($proc.ExitCode -eq 0)
            Output  = $stdout
        }
    } catch {
        return @{ Success = $false; Output = '' }
    }
}

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

function Invoke-ToggleZellijModal([string]$ModalName) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $env:ZELLIJ -or -not $zellijBin) {
        if ($ModalName -eq 'keys') { Show-IdeKeysCheatsheet; exit 0 }
        Invoke-SystemMonitor
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

    $pwshBin = (Get-Process -Id $PID).Path
    if (-not $pwshBin) { $pwshBin = 'pwsh.exe' }
    $env:IDE_MODAL_SIZED = '1'
    if ($ModalName -eq 'keys') {
        & $zellijBin action new-pane --floating --close-on-exit -x 6% -y 10% --width 88% --height 80% --name 'Keybindings' -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath --keys *> $null
    } else {
        & $zellijBin action new-pane --floating --close-on-exit -x 5% -y 5% --width 90% --height 90% --name 'System Monitor' -- $pwshBin -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath --monitor *> $null
    }
    exit 0
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

function Get-IdeKeysCheatsheetText {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $themeEnvPs1 = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'theme_env.ps1'
    if (Test-Path -LiteralPath $themeEnvPs1 -PathType Leaf) {
        try { . $themeEnvPs1 } catch { Write-Verbose "Theme env load skipped: $_" }
    }
    $esc = [char]27
    $cOrange = if ($env:_HS_ESC_ORANGE) { $env:_HS_ESC_ORANGE } else { "${esc}[38;2;203;75;22m" }
    $cBlue   = if ($env:_HS_ESC_BLUE)   { $env:_HS_ESC_BLUE }   else { "${esc}[38;2;38;139;210m" }
    $cCyan   = if ($env:_HS_ESC_CYAN)   { $env:_HS_ESC_CYAN }   else { "${esc}[38;2;42;161;152m" }
    $cBase0  = if ($env:_HS_ESC_BASE0)  { $env:_HS_ESC_BASE0 }  else { "${esc}[38;2;131;148;150m" }
    $cBase01 = if ($env:_HS_ESC_BASE01) { $env:_HS_ESC_BASE01 } else { "${esc}[38;2;88;110;117m" }
    $cReset  = "${esc}[0m"
    $rule    = '─' * 98

    $rowsPanes = @(
        @('Alt+h / j / k / l', 'Move focus between panes', 'Alt+s / Space s', 'Session Manager & Inbox'),
        @('Alt+a / e / t', 'Jump to AI / Editor / Shell', 'Alt+Shift+S', 'Jump to Next Attention'),
        @('Alt+; / Space a', 'Bounce last focused pane', 'Alt+[ / Alt+]', 'Prev / next IDE session'),
        @('Alt+z / Alt+f', 'Zoom 100% / Floating drawer', 'Ctrl+b d', 'Detach (agents keep running)'),
        @('Alt+Arrows', 'Resize active pane', 'ide -d [dir]', 'Spawn detached session'),
        @('Alt+Shift+H/J/K/L', 'Move / swap active pane', 'ide --desktop', '1-Hop GPU app + Tray icon'),
        @('Alt+? / Alt+m', 'Toggle keys / system monitor', ':Q / Alt+q / qide', 'Safe-quit IDE (checks saves)'),
        @('Right-click bar/pane', 'IDE workspace context menu', 'Ctrl+b b', 'Hide or show top bar')
    )
    $rowsEditor = @(
        @('Space ff', 'Find files by name', 'Mouse drag / 2x', 'Select text and auto-copy'),
        @('Space fg', 'Search text (live grep)', 'Alt+c', 'Copy & clear highlight'),
        @('Space gs', 'Review Git status', 'Alt+v', 'Paste from clipboard'),
        @('Space m', 'Toggle Markdown preview', 'Ctrl+Click', 'Open URL, #heading, or file'),
        @('H / L  (Normal)', 'Prev / next buffer', 'Alt+Click', 'Jump to LSP definition'),
        @('Ctrl+h / j / k / l', 'Move between Neovim splits', 'Mouse4/5 or C-o/i', 'Jump back or forward')
    )
    $rowsTree = @(
        @('Space e / Space E', 'Open mini.files tree', 'Space a  (Visual)', 'Paste selected ref into AI'),
        @('h/l or Left/Right', 'Parent dir / open item', 'Space il (Normal)', 'Paste current line ref to AI'),
        @('Enter  (in tree)', 'Open file or enter dir', 'Space id (Normal)', 'Paste buffer diagnostics'),
        @('=      (in tree)', 'Apply file edits', ':IdeSend[!] [ws]', 'Paste selection to session'),
        @('g? / q (in tree)', 'Tree help / close tree', ':Theme [slug]', 'Live-switch 17 color themes')
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('')
    $lines.Add(("  {0} IDE Workspace & Agent Fleet Keybindings (Zellij 0.46+ + Neovim){1}                [Any key / Alt+?]{2}" -f $cOrange, $cBase01, $cReset))
    $lines.Add(("  {0}{1}{2}" -f $cBase01, $rule, $cReset))
    $lines.Add(("  {0}{1,-51}{2}SESSIONS & ATTENTION INBOX{3}" -f $cBlue, 'PANES & ROLES (Zellij Layer 2)', $cBlue, $cReset))
    foreach ($r in $rowsPanes) {
        $lines.Add(("  {0}{1,-20}{2} {3,-28}  {4}{5,-18}{6} {7}{8}" -f $cCyan, $r[0], $cBase0, $r[1], $cCyan, $r[2], $cBase0, $r[3], $cReset))
    }
    $lines.Add('')
    $lines.Add(("  {0}{1,-51}{2}CLIPBOARD & LINKS{3}" -f $cBlue, 'EDITOR (Space = Leader)', $cBlue, $cReset))
    foreach ($r in $rowsEditor) {
        $lines.Add(("  {0}{1,-20}{2} {3,-28}  {4}{5,-18}{6} {7}{8}" -f $cCyan, $r[0], $cBase0, $r[1], $cCyan, $r[2], $cBase0, $r[3], $cReset))
    }
    $lines.Add('')
    $lines.Add(("  {0}{1,-51}{2}DIRECT AI PASTE & THEMES{3}" -f $cBlue, 'FILE TREE (mini.files)', $cBlue, $cReset))
    foreach ($r in $rowsTree) {
        $lines.Add(("  {0}{1,-20}{2} {3,-28}  {4}{5,-18}{6} {7}{8}" -f $cCyan, $r[0], $cBase0, $r[1], $cCyan, $r[2], $cBase0, $r[3], $cReset))
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

    # Pre-write raw OSC 7501 byte payloads so ide.cmd --agy-hook runs in pure cmd.exe (<5ms)
    $oscPayloads = @{
        'osc-agy-idle.bin'    = "${esc}]7501;state=idle:app=agy${esc}\"
        'osc-agy-working.bin' = "${esc}]7501;state=working:app=agy${esc}\"
        'osc-agy-done.bin'    = "${esc}]7501;state=done:app=agy${esc}\"
        'osc-agy-clear.bin'   = "${esc}]7501;state=clear:app=agy${esc}\"
        'osc-agy-error.bin'   = "${esc}]7501;state=error:app=agy${esc}\"
    }
    foreach ($kv in $oscPayloads.GetEnumerator()) {
        $oscPath = Join-Path $stateDir $kv.Key
        [System.IO.File]::WriteAllBytes($oscPath, [System.Text.Encoding]::ASCII.GetBytes($kv.Value))
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

    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
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

function Format-MonitorBar([double]$Percent, [int]$BarWidth, [string]$ColorGreen, [string]$ColorYellow, [string]$ColorRed, [string]$ColorDim, [string]$ColorReset) {
    $clamped = [Math]::Max(0.0, [Math]::Min(100.0, $Percent))
    $filled = [int][Math]::Round(($clamped / 100.0) * $BarWidth)
    $empty = [Math]::Max(0, $BarWidth - $filled)
    $accent = if ($clamped -ge 85.0) { $ColorRed } elseif ($clamped -ge 65.0) { $ColorYellow } else { $ColorGreen }
    $fillStr = ([string][char]0x2588) * $filled
    $emptyStr = ([string][char]0x2591) * $empty
    return ("{0}{1}{2}{3}{4}" -f $accent, $fillStr, $ColorDim, $emptyStr, $ColorReset)
}

function Show-BuiltinSystemMonitor {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $themeEnvPs1 = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'theme_env.ps1'
    if (Test-Path -LiteralPath $themeEnvPs1 -PathType Leaf) {
        try { . $themeEnvPs1 } catch { Write-Verbose "Theme env load skipped: $_" }
    }
    $esc = [char]27
    $cOrange = if ($env:_HS_ESC_ORANGE)  { $env:_HS_ESC_ORANGE }  else { "${esc}[38;2;203;75;22m" }
    $cBlue   = if ($env:_HS_ESC_BLUE)    { $env:_HS_ESC_BLUE }    else { "${esc}[38;2;38;139;210m" }
    $cCyan   = if ($env:_HS_ESC_CYAN)    { $env:_HS_ESC_CYAN }    else { "${esc}[38;2;42;161;152m" }
    $cGreen  = if ($env:_HS_ESC_GREEN)   { $env:_HS_ESC_GREEN }   else { "${esc}[38;2;133;153;0m" }
    $cYellow = if ($env:_HS_ESC_YELLOW)  { $env:_HS_ESC_YELLOW }  else { "${esc}[38;2;181;137;0m" }
    $cRed    = if ($env:_HS_ESC_RED)     { $env:_HS_ESC_RED }     else { "${esc}[38;2;220;50;47m" }
    $cMag    = if ($env:_HS_ESC_MAGENTA) { $env:_HS_ESC_MAGENTA } else { "${esc}[38;2;211;54;130m" }
    $cBase0  = if ($env:_HS_ESC_BASE0)   { $env:_HS_ESC_BASE0 }   else { "${esc}[38;2;131;148;150m" }
    $cBase01 = if ($env:_HS_ESC_BASE01)  { $env:_HS_ESC_BASE01 }  else { "${esc}[38;2;88;110;117m" }
    $cReset  = "${esc}[0m"
    $eol     = "${esc}[K"

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
            $rule = ([string][char]0x2500) * 78
            $cpuBar = Format-MonitorBar -Percent $cpuPct -BarWidth 28 -ColorGreen $cGreen -ColorYellow $cYellow -ColorRed $cRed -ColorDim $cBase01 -ColorReset $cReset
            $memBar = Format-MonitorBar -Percent $memPct -BarWidth 28 -ColorGreen $cGreen -ColorYellow $cYellow -ColorRed $cRed -ColorDim $cBase01 -ColorReset $cReset
            $dskBar = Format-MonitorBar -Percent $diskPct -BarWidth 28 -ColorGreen $cGreen -ColorYellow $cYellow -ColorRed $cRed -ColorDim $cBase01 -ColorReset $cReset
            $nowStr = (Get-Date).ToString('HH:mm:ss')

            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("")
            $lines.Add(("  {0}System Monitor{1}  ({2}){3}  [q / Esc / Alt+m to close]{4}" -f $cOrange, $cBase01, $nowStr, $cBase01, $cReset))
            $lines.Add(("  {0}{1}{2}" -f $cBase01, $rule, $cReset))
            $lines.Add(("  {0}CPU  {1} [{2}] {3}{4,5:N1}%{5}" -f $cBlue, $cReset, $cpuBar, $cMag, $cpuPct, $cReset))
            $lines.Add(("  {0}MEM  {1} [{2}] {3}{4,5:N1}%{5}  {6}({7:N1} / {8:N1} GiB){9}" -f $cBlue, $cReset, $memBar, $cMag, $memPct, $cReset, $cBase01, $memUsedGb, $memTotalGb, $cReset))
            $lines.Add(("  {0}DISK {1} [{2}] {3}{4,5:N1}%{5}  {6}({7}: {8:N1} / {9:N1} GiB){10}" -f $cBlue, $cReset, $dskBar, $cMag, $diskPct, $cReset, $cBase01, $diskName, $diskUsedGb, $diskTotalGb, $cReset))
            $lines.Add("")
            $lines.Add(("  {0}{1,-8} {2,-30} {3,12} {4,12} {5,10}{6}" -f $cBlue, 'PID', 'PROCESS', 'MEM (MiB)', 'CPU (s)', 'THREADS', $cReset))
            $lines.Add(("  {0}{1}{2}" -f $cBase01, $rule, $cReset))

            foreach ($p in $procs) {
                $pName = "$($p.ProcessName)"
                if ($pName.Length -gt 30) { $pName = $pName.Substring(0, 29) + [char]0x2026 }
                $wsMb = [Math]::Round($p.WorkingSet64 / 1MB, 1)
                $cpuSec = try { if ($null -ne $p.CPU) { [Math]::Round([double]$p.CPU, 1) } else { 0.0 } } catch { 0.0 }
                $thCount = try { $p.Threads.Count } catch { 0 }
                $lines.Add(("  {0}{1,-8}{2} {3,-30} {4}{5,12:N1}{6} {7,12:N1} {8,10}" -f $cCyan, $p.Id, $cBase0, $pName, $cMag, $wsMb, $cBase0, $cpuSec, $thCount))
            }
            $lines.Add("")
            $lines.Add(("  {0}Tip: install full graph monitor with 'winget install aristocratos.btop4win'{1}" -f $cBase01, $cReset))

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

function Invoke-FocusRole([string]$Role, [string]$SessionArg = '') {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin -or -not $env:ZELLIJ) {
        exit 0
    }
    $normRole = switch ($Role.ToLowerInvariant()) {
        'editor' { 'editor' }
        'nvim'   { 'editor' }
        'term'   { 'term' }
        'shell'  { 'term' }
        default  { 'ai' }
    }
    $sess = Resolve-TargetSession $SessionArg
    $targetId = Get-RolePaneId -SessionName $sess -Role $normRole
    $curId = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID

    if ($targetId) {
        if ($curId -and $curId -eq $targetId) {
            & $zellijBin action focus-last-pane *> $null
        } else {
            & $zellijBin action focus-pane-id $targetId *> $null
        }
        exit 0
    }

    switch ($normRole) {
        'ai' {
            & $zellijBin action move-focus up *> $null
            & $zellijBin action move-focus left *> $null
        }
        'editor' {
            & $zellijBin action move-focus up *> $null
            & $zellijBin action move-focus right *> $null
        }
        'term' {
            & $zellijBin action move-focus down *> $null
        }
    }
    exit 0
}

function Resolve-InitialEditorFile([string]$Directory) {
    if (-not $Directory -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return ''
    }
    foreach ($name in @('README.md', 'README.markdown', 'README.rst', 'README.txt', 'README')) {
        $candidate = Join-Path $Directory $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }
    return ''
}

function Invoke-PaneInit([string]$Role) {
    $normRole = switch ($Role.ToLowerInvariant()) {
        'editor' { 'editor' }
        'term'   { 'term' }
        default  { 'ai' }
    }
    $sess = Resolve-TargetSession ''
    $meta = Read-SessionState $sess
    $cwdNow = (Get-Location).ProviderPath
    $initRoot = if ($meta -and $meta['root']) { [string]$meta['root'] } elseif ($env:IDE_INITIAL_ROOT) { $env:IDE_INITIAL_ROOT } else { $cwdNow }
    $workDir = if ($meta -and $meta['workdir']) { [string]$meta['workdir'] } elseif ($env:IDE_WORKDIR) { $env:IDE_WORKDIR } else { $initRoot }
    $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
    $aiName = if ($meta -and $meta['ai_cli']) { [string]$meta['ai_cli'] } elseif ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }

    if ($env:ZELLIJ_PANE_ID) {
        Save-RolePaneId -SessionName $sess -Role $normRole -PaneId $env:ZELLIJ_PANE_ID
    }

    $env:IDE_SESSION = $sess
    $env:IDE_ROLE = $normRole
    $env:IDE_INITIAL_ROOT = $initRoot
    $env:IDE_WORKDIR = $workDir
    $env:NVIM_IDE_SOCKET = $pipePath
    $env:IDE_AI_CLI = $aiName

    if ($workDir -and (Test-Path -LiteralPath $workDir -PathType Container)) {
        Set-Location -LiteralPath $workDir
    }

    $pwshBin = (Get-Process -Id $PID).Path
    if (-not $pwshBin) { $pwshBin = 'pwsh.exe' }

    switch ($normRole) {
        'editor' {
            $Host.UI.RawUI.WindowTitle = "$sess [Editor]"
            if ($env:ZELLIJ -and $env:ZELLIJ_PANE_ID) {
                try {
                    $zBin = Resolve-ZellijExecutable
                    $edPid = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
                    if ($zBin -and $edPid) {
                        $rawId = [int]($edPid -replace '^terminal_', '')
                        $panesJson = (& $zBin action list-panes --all --json 2>$null) -join "`n"
                        if ($panesJson) {
                            $edEntry = ($panesJson | ConvertFrom-Json) |
                                Where-Object { -not $_.is_plugin -and $_.id -eq $rawId } |
                                Select-Object -First 1
                            if ($edEntry -and $null -eq $edEntry.attention.muted) {
                                & $zBin action mute-pane --pane-id $edPid *> $null
                            }
                        }
                    }
                } catch {
                    Write-Verbose "Editor pane mute check skipped: $_"
                }
            }
            $nvimBin = Resolve-NvimExecutable
            if ($nvimBin) {
                $initialFile = Resolve-InitialEditorFile $workDir
                if ($initialFile) {
                    & $nvimBin --listen $pipePath $initialFile
                } else {
                    & $nvimBin --listen $pipePath
                }
            } else {
                Write-Host "Neovim (nvim) not found on PATH; dropping to interactive shell." -ForegroundColor Yellow
            }
            & $pwshBin -NoLogo
            exit $LASTEXITCODE
        }
        'ai' {
            $aiInfo = Resolve-AiExecutable $aiName
            $Host.UI.RawUI.WindowTitle = "$sess [AI: $($aiInfo.Name)]"
            if ($aiInfo.Path) {
                & $aiInfo.Path
            } else {
                Write-Host "IDE session '$sess' ready (install '$($aiInfo.Name)' or set `$env:IDE_AI_CLI)." -ForegroundColor Cyan
            }
            & $pwshBin -NoLogo
            exit $LASTEXITCODE
        }
        default {
            $Host.UI.RawUI.WindowTitle = "$sess [Shell]"
            & $pwshBin -NoLogo
            exit $LASTEXITCODE
        }
    }
}

function Invoke-SessionSwitcher {
    $zellijBin = Resolve-ZellijExecutable
    if ($zellijBin -and $env:ZELLIJ) {
        & $zellijBin action launch-or-focus-plugin --floating --move-to-focused-tab 'zellij:session-manager' *> $null
        exit 0
    }
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zellijBin -and $fzfCmd -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $rows = @(Show-IdeSessionList -Plain $false | Where-Object { $_ -and $_ -notmatch '^(SESSION\s+|-{5,}|No IDE workspace)' })
        if ($rows.Count -eq 0) {
            Write-Output 'No IDE workspace sessions found.'
            exit 0
        }
        $selected = $rows | & $fzfCmd.Source --no-multi --reverse --height=60% --border=rounded '--prompt=IDE Session > ' '--header=Enter to attach/resurrect session, Esc to cancel'
        if ($LASTEXITCODE -eq 0 -and $selected) {
            $chosen = ($selected.Trim() -split '\s+')[0]
            if ($chosen) {
                $env:ZELLIJ_CONFIG_DIR = Get-ZellijConfigDir
                $meta = Read-SessionState $chosen
                $wdir = if ($meta -and $meta['workdir'] -and (Test-Path -LiteralPath $meta['workdir'])) { [string]$meta['workdir'] } else { (Get-Location).ProviderPath }
                $lay = if ($meta -and $meta['layout'] -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }
                & $zellijBin attach --create $chosen options --default-layout $lay --default-cwd $wdir
                exit $LASTEXITCODE
            }
        }
        exit 0
    }
    Show-IdeSessionList -Plain $false
    exit 0
}

function Split-FileAndLineSpec([string]$RawFile, [string]$ExplicitLine) {
    $filePart = $RawFile
    $lineNum = 0
    if ($ExplicitLine -and $ExplicitLine -match '^[0-9]+$') {
        $lineNum = [int]$ExplicitLine
    } elseif ($RawFile -match '^([A-Za-z]:[^:]+|[^:]+):([0-9]+)(?::[0-9]+)?$') {
        $candPath = $Matches[1]
        if (-not (Test-Path -LiteralPath $RawFile) -and (Test-Path -LiteralPath $candPath)) {
            $filePart = $candPath
            $lineNum = [int]$Matches[2]
        } elseif ($RawFile -notmatch '^[A-Za-z]:[\\/]?$' -and -not (Test-Path -LiteralPath $RawFile)) {
            $filePart = $candPath
            $lineNum = [int]$Matches[2]
        }
    }
    return @{
        File = $filePart
        Line = $lineNum
    }
}

function Invoke-OpenInIde([string]$RawFile, [string]$ExplicitLine, [bool]$FallbackLocalEdit, [bool]$FocusEditor) {
    if (-not $RawFile) {
        [Console]::Error.WriteLine('Error: --open requires a file path.')
        exit 1
    }
    $parsed = Split-FileAndLineSpec -RawFile $RawFile -ExplicitLine $ExplicitLine
    $targetPath = $parsed.File
    if (-not [System.IO.Path]::IsPathRooted($targetPath)) {
        $targetPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $targetPath))
    }
    $lineNum = [int]$parsed.Line

    $sess = Resolve-TargetSession ''
    $pipePath = ''
    if ($env:NVIM_IDE_SOCKET -and (Test-IdePipeLive $env:NVIM_IDE_SOCKET.Trim())) {
        $pipePath = $env:NVIM_IDE_SOCKET.Trim()
    } else {
        $meta = Read-SessionState $sess
        $candPipe = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        if (Test-IdePipeLive $candPipe) {
            $pipePath = $candPipe
        }
    }

    if ($pipePath) {
        $vimSinglePath = $targetPath.Replace("'", "''")
        $vimExpr = "luaeval('(function(p, l) vim.schedule(function() pcall(function() require(""mini.files"").close() end); vim.cmd(""silent! keepjumps edit "" .. vim.fn.fnameescape(p)); if l > 0 then pcall(vim.api.nvim_win_set_cursor, 0, {l, 0}); pcall(vim.cmd, ""silent! normal! zz"") end end); return ""OK"" end)(_A[1], _A[2])', ['$vimSinglePath', $lineNum])"
        $res = Invoke-NvimRemoteExpr -PipePath $pipePath -Expr $vimExpr
        if ($res.Success) {
            if ($FocusEditor -and $env:ZELLIJ) {
                $zellijBin = Resolve-ZellijExecutable
                $edPane = Get-RolePaneId -SessionName $sess -Role 'editor'
                if ($zellijBin -and $edPane) {
                    & $zellijBin action focus-pane-id $edPane *> $null
                }
            }
            exit 0
        }
    }

    if ($FallbackLocalEdit) {
        $nvimBin = Resolve-NvimExecutable
        if (-not $nvimBin) {
            [Console]::Error.WriteLine('Error: nvim is not installed.')
            exit 1
        }
        if ($lineNum -gt 0) {
            & $nvimBin "+$lineNum" $targetPath
        } else {
            & $nvimBin $targetPath
        }
        exit $LASTEXITCODE
    }

    [Console]::Error.WriteLine('Error: No active IDE Neovim server found for current workspace.')
    exit 1
}

function Invoke-IdeCd([string]$TargetArg) {
    $sess = Resolve-TargetSession ''
    $meta = Read-SessionState $sess
    $initRoot = if ($meta -and $meta['root']) {
        [string]$meta['root']
    } elseif ($env:IDE_INITIAL_ROOT -and $env:IDE_INITIAL_ROOT.Trim()) {
        $env:IDE_INITIAL_ROOT.Trim()
    } else {
        (Get-Location).ProviderPath
    }

    $resolved = ''
    if (-not $TargetArg -or $TargetArg -eq '--reset' -or $TargetArg -eq '~') {
        $resolved = $initRoot
    } elseif ([System.IO.Path]::IsPathRooted($TargetArg)) {
        $resolved = $TargetArg
    } else {
        $resolved = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $TargetArg))
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        [Console]::Error.WriteLine("Error: Directory not found: $resolved")
        exit 1
    }
    $resolved = (Resolve-Path -LiteralPath $resolved).ProviderPath

    if (-not $meta) {
        $meta = [ordered]@{
            session       = $sess
            root          = $initRoot
            workdir       = $resolved
            pipe          = Get-SessionPipePath $sess
            layout        = '3pane'
            backend       = if ($env:ZELLIJ) { 'zellij' } else { 'wt' }
            ai_cli        = if ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
            agent_state   = 'idle'
            agent_message = ''
            created_at    = ''
            updated_at    = ''
        }
    } else {
        $meta['workdir'] = $resolved
    }
    Save-SessionState $meta

    $pipePath = [string]$meta['pipe']
    if (Test-IdePipeLive $pipePath) {
        $vimSingleDir = $resolved.Replace("'", "''")
        [void](Invoke-NvimRemoteExpr -PipePath $pipePath -Expr "luaeval('(function(d) vim.schedule(function() pcall(vim.fn.chdir, d) end); return ""OK"" end)(_A)', '$vimSingleDir')")
    }

    Write-Output $resolved
}

function Format-RelativeFileRef([string]$RawRef, [string]$BaseDir) {
    $trimmed = $RawRef.Trim().TrimStart('@')
    $filePart = $trimmed
    $l1 = ''
    $l2 = ''

    if ($trimmed -match '^(?<file>[A-Za-z]:[^:#]+|[^:#]+)(?:[:#]L?(?<l1>[0-9]+)(?:-L?(?<l2>[0-9]+))?)?$') {
        $filePart = $Matches['file']
        if ($Matches['l1']) { $l1 = $Matches['l1'] }
        if ($Matches['l2']) { $l2 = $Matches['l2'] }
    }

    $relPath = $filePart
    if ($BaseDir -and [System.IO.Path]::IsPathRooted($filePart)) {
        try {
            $computed = [System.IO.Path]::GetRelativePath($BaseDir, $filePart)
            if ($computed -and -not $computed.StartsWith('..')) {
                $relPath = $computed
            }
        } catch {
            $relPath = $filePart
        }
    }
    $relPath = $relPath.Replace('\', '/')

    if ($l1 -and $l2 -and $l1 -ne $l2) {
        return "@${relPath}#L${l1}-L${l2} "
    }
    if ($l1) {
        return "@${relPath}#L${l1} "
    }
    return "@${relPath} "
}

function Invoke-IdeSend([string[]]$SendArgs) {
    $mode = ''
    $payload = ''
    $targetSessArg = ''
    $noFocus = $false
    $switchSession = $false

    for ($idx = 0; $idx -lt $SendArgs.Count; $idx++) {
        $a = $SendArgs[$idx]
        switch ($a) {
            '--stdin' {
                $mode = 'stdin'
            }
            '--ref' {
                $mode = 'ref'
                if ($idx + 1 -ge $SendArgs.Count) {
                    [Console]::Error.WriteLine('Error: --ref requires a path reference.')
                    exit 1
                }
                $payload = $SendArgs[++$idx]
            }
            '--text' {
                $mode = 'text'
                if ($idx + 1 -ge $SendArgs.Count) {
                    [Console]::Error.WriteLine('Error: --text requires a string.')
                    exit 1
                }
                $payload = $SendArgs[++$idx]
            }
            '--no-focus' {
                $noFocus = $true
            }
            '--switch' {
                $switchSession = $true
                $noFocus = $false
            }
            default {
                if (-not $mode -and -not $payload) {
                    $payload = $a
                } else {
                    $targetSessArg = $a
                }
            }
        }
    }

    $sess = Resolve-TargetSession $targetSessArg
    $meta = Read-SessionState $sess
    $baseDir = if ($meta -and $meta['workdir']) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root']) {
        [string]$meta['root']
    } else {
        (Get-Location).ProviderPath
    }

    if ($mode -eq 'stdin') {
        $payload = [Console]::In.ReadToEnd()
    } elseif ($mode -eq 'ref' -and $payload) {
        $payload = Format-RelativeFileRef -RawRef $payload -BaseDir $baseDir
    }

    if (-not $payload) {
        exit 0
    }

    $stageFile = Join-Path (Get-IdeStateDir) "$sess.send.txt"
    Write-TextUtf8NoBom -Path $stageFile -Content $payload

    if ($env:WS_IDE_SKIP_CLIPBOARD -ne '1') {
        try {
            Set-Clipboard -Value $payload -ErrorAction Stop
        } catch {
            Write-Verbose "Clipboard stage skipped in headless environment: $_"
        }
    }

    $zellijBin = Resolve-ZellijExecutable
    $aiPaneId = Get-RolePaneId -SessionName $sess -Role 'ai'
    if (-not $aiPaneId) { $aiPaneId = 'terminal_0' }

    if ($zellijBin) {
        $liveZellij = Get-LiveZellijSessionMap
        if ($liveZellij[$sess] -eq 'live') {
            $curZellijSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME.Trim() } else { '' }
            if ($env:ZELLIJ -and $curZellijSess -eq $sess) {
                & $zellijBin action paste -p $aiPaneId $payload *> $null
                if (-not $noFocus) {
                    & $zellijBin action focus-pane-id $aiPaneId *> $null
                }
            } else {
                & $zellijBin --session $sess action paste -p $aiPaneId $payload *> $null
                if ($switchSession -and $env:ZELLIJ) {
                    & $zellijBin action switch-session --pane-id $aiPaneId $sess *> $null
                }
            }
        }
    }
}

function Show-IdeSessionList([bool]$Plain) {
    $stateDir = Get-IdeStateDir
    $livePipes = Get-LiveIdePipeMap
    $liveZellij = Get-LiveZellijSessionMap
    $sessions = [ordered]@{}

    if (Test-Path -LiteralPath $stateDir -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $stateDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($f in $files) {
            $sName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $meta = Read-SessionState $sName
            if ($meta) {
                $sessions[$sName] = $meta
            }
        }
    }
    foreach ($zName in ($liveZellij.Keys | Sort-Object)) {
        if (-not $sessions.Contains($zName)) {
            $sessions[$zName] = [ordered]@{
                session       = $zName
                root          = ''
                workdir       = ''
                pipe          = Get-SessionPipePath $zName
                layout        = '3pane'
                backend       = 'zellij'
                ai_cli        = if ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
                agent_state   = 'idle'
                agent_message = ''
            }
        }
    }
    foreach ($liveName in ($livePipes.Keys | Sort-Object)) {
        if (-not $sessions.Contains($liveName)) {
            $sessions[$liveName] = [ordered]@{
                session       = $liveName
                root          = ''
                workdir       = ''
                pipe          = $livePipes[$liveName]
                layout        = '3pane'
                backend       = 'wt'
                ai_cli        = if ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
                agent_state   = 'idle'
                agent_message = ''
            }
        }
    }

    if ($Plain) {
        foreach ($k in $sessions.Keys) {
            Write-Output $k
        }
        return
    }

    if ($sessions.Count -eq 0) {
        Write-Output 'No IDE workspace sessions found.'
        return
    }

    Write-Output ('{0,-22} {1,-8} {2,-7} {3,-8} {4,-10} {5,-18} {6}' -f 'SESSION', 'STATUS', 'LAYOUT', 'AI', 'STATE', 'BRANCH', 'WORKDIR')
    Write-Output ('-' * 105)
    foreach ($k in $sessions.Keys) {
        $m = $sessions[$k]
        $zStatus = $liveZellij[$k]
        $pipeUp = $livePipes.ContainsKey($k) -or (Test-IdePipeLive ([string]$m['pipe']))
        $status = if ($zStatus -eq 'live' -or $pipeUp) {
            'live'
        } elseif ($zStatus -eq 'exited') {
            'exited'
        } else {
            'saved'
        }
        $wdir = if ($m['workdir']) { [string]$m['workdir'] } elseif ($m['root']) { [string]$m['root'] } else { '-' }
        $branch = '-'
        if ($wdir -ne '-' -and (Test-Path -LiteralPath $wdir -PathType Container)) {
            $gitCmd = Get-Command git -ErrorAction SilentlyContinue
            if ($gitCmd) {
                try {
                    $b = & $gitCmd.Source -C $wdir symbolic-ref --quiet --short HEAD 2>$null
                    if ($LASTEXITCODE -eq 0 -and $b) { $branch = "$b".Trim() }
                } catch {
                    $branch = '-'
                }
            }
        }
        Write-Output ('{0,-22} {1,-8} {2,-7} {3,-8} {4,-10} {5,-18} {6}' -f $k, $status, $m['layout'], $m['ai_cli'], $m['agent_state'], $branch, $wdir)
    }
}

function Close-IdeSessionList([string[]]$TargetArgs, [bool]$Force) {
    $targets = [System.Collections.Generic.List[string]]::new()
    if ($TargetArgs -and $TargetArgs.Count -gt 0) {
        foreach ($t in $TargetArgs) {
            $resolved = Resolve-TargetSession $t
            if (-not $targets.Contains($resolved)) {
                $targets.Add($resolved)
            }
        }
    } else {
        $targets.Add((Resolve-TargetSession ''))
    }

    $zellijBin = Resolve-ZellijExecutable
    $curZellijSess = if ($env:ZELLIJ_SESSION_NAME) { Get-SanitizedToken $env:ZELLIJ_SESSION_NAME.Trim() } else { '' }
    $needsSessionScan = $false
    foreach ($t in $targets) {
        if (-not $curZellijSess -or -not [string]::Equals($t, $curZellijSess, [System.StringComparison]::OrdinalIgnoreCase)) {
            $needsSessionScan = $true
            break
        }
    }
    $liveZellij = if ($needsSessionScan) { Get-LiveZellijSessionMap } else { @{} }
    if ($curZellijSess) {
        $liveZellij[$curZellijSess] = 'live'
    }

    $alreadyScheduledQuit = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($sess in $targets) {
        $meta = Read-SessionState $sess
        $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        $pipeLive = Test-IdePipeLive $pipePath
        $zKnown = $liveZellij.ContainsKey($sess)
        if (-not $meta -and -not $pipeLive -and -not $zKnown) {
            [Console]::Error.WriteLine("No active IDE session named '$sess'.")
            exit 1
        }
        if ($pipeLive -and -not $Force) {
            $quitExpr = "luaeval('_G.try_ide_quit and _G.try_ide_quit(false) or (_G.count_ide_modified_buffers and _G.count_ide_modified_buffers() or 0)')"
            $modRes = Invoke-NvimRemoteExpr -PipePath $pipePath -Expr $quitExpr
            $modCount = 0
            if ($modRes.Success -and [int]::TryParse($modRes.Output, [ref]$modCount) -and $modCount -gt 0) {
                if ($zellijBin -and $curZellijSess -and [string]::Equals($sess, $curZellijSess, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $edPane = Get-RolePaneId -SessionName $sess -Role 'editor'
                    if ($edPane) {
                        & $zellijBin action focus-pane-id $edPane *> $null
                    }
                }
                [Console]::Error.WriteLine("E37: No write since last change in $modCount buffer(s) in session '$sess' (save in Neovim or use --force / idek).")
                exit 1
            }
            if ($modRes.Success -and $targets.Count -eq 1) {
                [void]$alreadyScheduledQuit.Add($sess)
            }
        }
    }

    foreach ($sess in $targets) {
        $meta = Read-SessionState $sess
        $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        if (-not $alreadyScheduledQuit.Contains($sess) -and (Test-IdePipeLive $pipePath)) {
            [void](Invoke-NvimRemoteExpr -PipePath $pipePath -Expr "luaeval('(function() vim.schedule(function() vim.cmd(""qa!"") end); return ""OK"" end)()')")
        }
        if ($zellijBin -and $liveZellij.ContainsKey($sess)) {
            try {
                & $zellijBin delete-session --force $sess *> $null
            } catch {
                Write-Verbose "Zellij session delete skipped for ${sess}: $_"
            }
        }
        $stateDir = Get-IdeStateDir
        foreach ($artifact in @(
            "$sess.json",
            "$sess.state",
            "$sess.send.txt",
            "$sess.pane-ai",
            "$sess.pane-editor",
            "$sess.pane-term",
            "launch-$sess-ai.ps1",
            "launch-$sess-editor.ps1",
            "launch-$sess-term.ps1"
        )) {
            $p = Join-Path $stateDir $artifact
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Output "Closed IDE session '$sess'."
    }
}

function Write-PaneLauncherSet(
    [string]$SessionName,
    [string]$InitialRoot,
    [string]$WorkDir,
    [string]$PipePath,
    [string]$AiCliName,
    [string]$AiCliPath,
    [string]$NvimPath
) {
    $stateDir = Get-IdeStateDir
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

    $escSess = $SessionName.Replace("'", "''")
    $escRoot = $InitialRoot.Replace("'", "''")
    $escWork = $WorkDir.Replace("'", "''")
    $escPipe = $PipePath.Replace("'", "''")
    $escAiName = $AiCliName.Replace("'", "''")
    $escAiPath = $AiCliPath.Replace("'", "''")
    $escNvim = $NvimPath.Replace("'", "''")

    $commonHeader = @(
        "`$env:IDE_SESSION = '$escSess'"
        "`$env:IDE_INITIAL_ROOT = '$escRoot'"
        "`$env:IDE_WORKDIR = '$escWork'"
        "`$env:NVIM_IDE_SOCKET = '$escPipe'"
        "`$env:IDE_AI_CLI = '$escAiName'"
        "if (Test-Path -LiteralPath `$env:IDE_WORKDIR) { Set-Location -LiteralPath `$env:IDE_WORKDIR }"
    ) -join "`n"

    $aiBody = if ($AiCliPath) {
        @(
            $commonHeader
            "`$Host.UI.RawUI.WindowTitle = `"$escSess [AI: $escAiName]`""
            "& '$escAiPath'"
        ) -join "`n"
    } else {
        @(
            $commonHeader
            "`$Host.UI.RawUI.WindowTitle = `"$escSess [AI]`""
            "Write-Host `"IDE session '$escSess' ready (install '$escAiName' or set `$env:IDE_AI_CLI).`" -ForegroundColor Cyan"
        ) -join "`n"
    }

    $initialFile = Resolve-InitialEditorFile $WorkDir
    $escInitFile = $initialFile.Replace("'", "''")
    $nvimLaunchLine = if ($initialFile) {
        "& '$escNvim' --listen `$env:NVIM_IDE_SOCKET '$escInitFile'"
    } else {
        "& '$escNvim' --listen `$env:NVIM_IDE_SOCKET"
    }

    $editorBody = @(
        $commonHeader
        "`$Host.UI.RawUI.WindowTitle = `"$escSess [Editor]`""
        $nvimLaunchLine
    ) -join "`n"

    $termBody = @(
        $commonHeader
        "`$Host.UI.RawUI.WindowTitle = `"$escSess [Shell]`""
    ) -join "`n"

    $aiScript = Join-Path $stateDir "launch-$SessionName-ai.ps1"
    $editorScript = Join-Path $stateDir "launch-$SessionName-editor.ps1"
    $termScript = Join-Path $stateDir "launch-$SessionName-term.ps1"

    Write-TextUtf8NoBom -Path $aiScript -Content ($aiBody + "`n")
    Write-TextUtf8NoBom -Path $editorScript -Content ($editorBody + "`n")
    Write-TextUtf8NoBom -Path $termScript -Content ($termBody + "`n")

    return @{
        Ai     = $aiScript
        Editor = $editorScript
        Term   = $termScript
    }
}

# ==============================================================================
# CLI Argument Dispatch
# ==============================================================================

$layout = '3pane'
$newWindow = $false
$detachFlag = $false
$desktopFlag = ($env:IDE_DESKTOP -eq '1')
$dryRun = $false
$forceFlag = $false
$plainFlag = $false
$requestedBackend = if ($env:IDE_BACKEND -and $env:IDE_BACKEND.Trim()) { $env:IDE_BACKEND.Trim().ToLowerInvariant() } else { '' }
$requestedAi = if ($env:IDE_AI_CLI -and $env:IDE_AI_CLI.Trim()) { $env:IDE_AI_CLI.Trim() } else { 'agy' }
$action = 'launch'
$actionArgs = [System.Collections.Generic.List[string]]::new()
$targetDirArg = ''

for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    switch ($arg) {
        { $_ -in @('-h', '--help', '-?') } {
            Write-Output $script:UsageText
            exit 0
        }
        { $_ -in @('--keys', '--help-keys') } {
            Show-IdeKeysCheatsheet
            exit 0
        }
        '--write-keys-cache' {
            Write-IdeKeysCheatsheetCache
            exit 0
        }
        '--toggle-keys' {
            Invoke-ToggleZellijModal -ModalName 'keys'
        }
        '--toggle-monitor' {
            Invoke-ToggleZellijModal -ModalName 'monitor'
        }
        { $_ -in @('--monitor', '--top', '--btop', 'top') } {
            Invoke-SystemMonitor
        }
        '--3pane' {
            $layout = '3pane'
        }
        '--2pane' {
            $layout = '2pane'
        }
        { $_ -in @('-d', '--detach') } {
            $detachFlag = $true
        }
        '--desktop' {
            $desktopFlag = $true
        }
        '--new-window' {
            $newWindow = $true
        }
        '--backend' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: --backend requires zellij or wt.')
                exit 1
            }
            $requestedBackend = ([string]$args[++$i]).Trim().ToLowerInvariant()
        }
        { $_ -in @('-s', '--sessions') } {
            Invoke-SessionSwitcher
        }
        '--next-attention' {
            $zBin = Resolve-ZellijExecutable
            if ($zBin) {
                if ($env:ZELLIJ) {
                    & $zBin action go-to-next-attention *> $null
                } else {
                    & $zBin terminal --inbox *> $null
                }
            }
            exit 0
        }
        '--pane-init' {
            $roleArg = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { 'ai' }
            Invoke-PaneInit -Role $roleArg
        }
        '--toggle' {
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-FocusRole -Role 'ai' -SessionArg $optSess
        }
        { $_ -in @('--show-ai', '--show-editor', '--show-term') } {
            $rName = $arg.Substring(7)
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-FocusRole -Role $rName -SessionArg $optSess
        }
        '--focus-role' {
            $rName = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { 'ai' }
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-FocusRole -Role $rName -SessionArg $optSess
        }
        { $_ -in @('-n', '--dry-run') } {
            $dryRun = $true
        }
        { $_ -in @('-f', '--force') } {
            $forceFlag = $true
        }
        '--plain' {
            $plainFlag = $true
        }
        { $_ -in @('--ai', '--agent') } {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine("Error: $arg requires a CLI name (agy, claude, or codex).")
                exit 1
            }
            $requestedAi = [string]$args[++$i]
        }
        { $_ -in @('--open', '--preview', '--open-or-edit') } {
            $fallbackEdit = ($arg -eq '--open-or-edit')
            $focusEd = ($arg -ne '--preview')
            $fileArg = ''
            $lineArg = ''
            if ($i + 1 -lt $args.Count -and ([string]$args[$i + 1]) -match '^\+([0-9]+)$' -and $i + 2 -lt $args.Count) {
                $lineArg = $Matches[1]
                $i++
                $fileArg = [string]$args[++$i]
            } else {
                $fileArg = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
                if ($i + 1 -lt $args.Count -and ([string]$args[$i + 1]) -match '^\+?([0-9]+)$') {
                    $lineArg = $Matches[1]
                    $i++
                }
            }
            Invoke-OpenInIde -RawFile $fileArg -ExplicitLine $lineArg -FallbackLocalEdit $fallbackEdit -FocusEditor $focusEd
        }
        { $_ -in @('cd', '--cd') } {
            $cdTarget = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            Invoke-IdeCd -TargetArg $cdTarget
            exit 0
        }
        '--send' {
            $rem = @()
            if ($i + 1 -lt $args.Count) {
                $rem = @($args[($i + 1)..($args.Count - 1)] | ForEach-Object { [string]$_ })
            }
            Invoke-IdeSend -SendArgs $rem
            exit 0
        }
        '--agy-hook' {
            $evName = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            Invoke-AgyHook -HookEventArg $evName
        }
        '--agent-state' {
            $st = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { 'idle' }
            $msg = ''
            $sessArg = ''
            while ($i + 1 -lt $args.Count) {
                $nx = [string]$args[++$i]
                if ($nx -eq '--message' -and $i + 1 -lt $args.Count) {
                    $msg = [string]$args[++$i]
                } else {
                    $sessArg = $nx
                }
            }
            Write-Osc7501Status (Format-Osc7501Spec -StateName $st -Message $msg)
            $sess = Resolve-TargetSession $sessArg
            $meta = Read-SessionState $sess
            if ($meta) {
                $meta['agent_state'] = $st
                $meta['agent_message'] = $msg
                Save-SessionState $meta
            }
            exit 0
        }
        '--ack-ai' {
            $ackTargets = @()
            while ($i + 1 -lt $args.Count) { $ackTargets += [string]$args[++$i] }
            if ($ackTargets.Count -eq 0) { $ackTargets = @(Resolve-TargetSession '') }
            $zBin = Resolve-ZellijExecutable
            if ($zBin -and $env:ZELLIJ) {
                & $zBin action mark-all-seen *> $null
            }
            foreach ($at in $ackTargets) {
                $s = Resolve-TargetSession $at
                $meta = Read-SessionState $s
                if ($meta) {
                    $meta['agent_state'] = 'idle'
                    $meta['agent_message'] = ''
                    Save-SessionState $meta
                }
            }
            exit 0
        }
        '--open-pr' {
            $sessArg = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            $sess = Resolve-TargetSession $sessArg
            $meta = Read-SessionState $sess
            $wdir = if ($meta -and $meta['workdir']) { [string]$meta['workdir'] } else { (Get-Location).ProviderPath }
            $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
            if (-not $ghCmd) {
                [Console]::Error.WriteLine('Error: GitHub CLI (gh) is required for --open-pr.')
                exit 1
            }
            $pushed = $false
            if ($wdir -and (Test-Path -LiteralPath $wdir -PathType Container)) {
                Push-Location -LiteralPath $wdir
                $pushed = $true
            }
            try {
                $prUrl = (& $ghCmd.Source pr view --json url -q .url 2>$null)
            } finally {
                if ($pushed) { Pop-Location }
            }
            if (-not $prUrl) {
                [Console]::Error.WriteLine('No pull request found for current branch.')
                exit 1
            }
            $urlStr = "$prUrl".Trim()
            if ($env:IDE_BROWSER -and $env:IDE_BROWSER.Trim()) {
                Start-Process -FilePath $env:IDE_BROWSER.Trim() -ArgumentList $urlStr
            } else {
                Start-Process $urlStr
            }
            exit 0
        }
        { $_ -in @('refresh', '-r', '--refresh') } {
            $targetArg = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            $themePs1 = Join-Path $ScriptDir 'theme.ps1'
            if (Test-Path -LiteralPath $themePs1 -PathType Leaf) {
                & $themePs1 --sync-assets *> $null
            }
            if ($env:ZELLIJ -and $env:APPDATA) {
                $barWasm = Join-Path (Join-Path (Join-Path (Join-Path $env:APPDATA 'Zellij') 'data') 'plugins') 'windows-settings-bar.wasm'
                if (Test-Path -LiteralPath $barWasm -PathType Leaf) {
                    $zellijBin = Resolve-ZellijExecutable
                    if ($zellijBin) {
                        & $zellijBin action start-or-reload-plugin 'file:windows-settings-bar' *> $null
                    }
                }
            }
            if ($targetArg) {
                $sess = Resolve-TargetSession $targetArg
                [void](Invoke-NvimRemoteExpr -PipePath (Get-SessionPipePath $sess) -Expr 'v:lua.apply_home_settings_theme()')
            } else {
                $live = Get-LiveIdePipeMap
                foreach ($p in $live.Values) {
                    [void](Invoke-NvimRemoteExpr -PipePath $p -Expr 'v:lua.apply_home_settings_theme()')
                }
            }
            exit 0
        }
        { $_ -in @('-l', '--list') } {
            $action = 'list'
        }
        { $_ -in @('quit', '-q', '--quit') } {
            $action = 'quit'
        }
        { $_ -in @('kill', '--kill') } {
            $action = 'kill'
        }
        default {
            if ($action -in @('quit', 'kill')) {
                $actionArgs.Add($arg)
            } elseif ($arg.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown option '$arg'. Run 'ide --help' for usage.")
                exit 1
            } elseif (-not $targetDirArg) {
                $targetDirArg = $arg
            } else {
                $actionArgs.Add($arg)
            }
        }
    }
}

if ($action -eq 'list') {
    Show-IdeSessionList -Plain $plainFlag
    exit 0
}

if ($action -eq 'quit') {
    Close-IdeSessionList -TargetArgs $actionArgs.ToArray() -Force $forceFlag
    exit 0
}

if ($action -eq 'kill') {
    Close-IdeSessionList -TargetArgs $actionArgs.ToArray() -Force $true
    exit 0
}

# ==============================================================================
# Launch Workspace Action
# ==============================================================================
$resolvedRoot = if ($targetDirArg) {
    if ([System.IO.Path]::IsPathRooted($targetDirArg)) {
        $targetDirArg
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $targetDirArg))
    }
} else {
    (Get-Location).ProviderPath
}

if (-not (Test-Path -LiteralPath $resolvedRoot -PathType Container)) {
    [Console]::Error.WriteLine("Error: Target directory does not exist: $resolvedRoot")
    exit 1
}
$resolvedRoot = (Resolve-Path -LiteralPath $resolvedRoot).ProviderPath

$sessionName = Get-SanitizedSessionName $resolvedRoot
$pipePath = Get-SessionPipePath $sessionName
$aiInfo = Resolve-AiExecutable $requestedAi
$nvimBin = Resolve-NvimExecutable
if (-not $nvimBin) { $nvimBin = 'nvim' }
$zellijBin = Resolve-ZellijExecutable

$effectiveBackend = if ($requestedBackend -in @('zellij', 'wt')) {
    $requestedBackend
} elseif ($zellijBin) {
    'zellij'
} else {
    'wt'
}

if ($effectiveBackend -eq 'zellij') {
    $zellijCfgDir = Get-ZellijConfigDir
    $zellijLayout = if ($layout -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }

    $zellijPreviewCmd = if ($detachFlag) {
        "zellij attach --create-background $sessionName options --default-layout $zellijLayout --default-cwd `"$resolvedRoot`""
    } elseif ($desktopFlag) {
        "zellij terminal --create --working-directory `"$resolvedRoot`" $sessionName options --default-layout $zellijLayout"
    } elseif ($env:ZELLIJ -and -not $newWindow) {
        "zellij action switch-session --layout $zellijLayout --cwd `"$resolvedRoot`" $sessionName"
    } else {
        "zellij attach --create $sessionName options --default-layout $zellijLayout --default-cwd `"$resolvedRoot`""
    }

    if ($dryRun) {
        $initialDoc = Resolve-InitialEditorFile $resolvedRoot
        Write-Output "IDE Session : $sessionName"
        Write-Output "Backend     : zellij"
        Write-Output "Layout      : $layout ($zellijLayout)"
        Write-Output "Workdir     : $resolvedRoot"
        Write-Output "Named Pipe  : $pipePath"
        Write-Output "AI Agent    : $($aiInfo.Name)"
        Write-Output "Editor      : $nvimBin"
        if ($initialDoc) {
            Write-Output "Initial Doc : $initialDoc"
        }
        Write-Output "Config Dir  : $zellijCfgDir"
        Write-Output "Command     : $zellijPreviewCmd"
        exit 0
    }

    if (-not $zellijBin) {
        [Console]::Error.WriteLine("Error: Zellij ('zellij') was not found on PATH. Run '.\setup.ps1 -Bootstrap' or 'mise install zellij@latest'.")
        exit 1
    }

    $pathEntries = @($env:Path -split ';' | Where-Object { $_ -and $_.Trim() })
    if ($pathEntries -notcontains $ScriptDir) {
        $env:Path = "$ScriptDir;$env:Path"
    }
    $env:ZELLIJ_CONFIG_DIR = $zellijCfgDir
    $env:IDE_SESSION = $sessionName
    $env:IDE_INITIAL_ROOT = $resolvedRoot
    $env:IDE_WORKDIR = $resolvedRoot
    $env:NVIM_IDE_SOCKET = $pipePath
    $env:IDE_AI_CLI = $aiInfo.Name

    $existingMeta = Read-SessionState $sessionName
    $metaObj = [ordered]@{
        session       = $sessionName
        root          = if ($existingMeta -and $existingMeta['root']) { [string]$existingMeta['root'] } else { $resolvedRoot }
        workdir       = $resolvedRoot
        pipe          = $pipePath
        layout        = $layout
        backend       = 'zellij'
        ai_cli        = $aiInfo.Name
        agent_state   = if ($existingMeta -and $existingMeta['agent_state']) { [string]$existingMeta['agent_state'] } else { 'idle' }
        agent_message = if ($existingMeta -and $existingMeta['agent_message']) { [string]$existingMeta['agent_message'] } else { '' }
        created_at    = if ($existingMeta -and $existingMeta['created_at']) { [string]$existingMeta['created_at'] } else { '' }
        updated_at    = ''
    }
    Save-SessionState $metaObj

    $liveZellij = Get-LiveZellijSessionMap
    if ($liveZellij[$sessionName] -eq 'exited') {
        try { & $zellijBin delete-session $sessionName *> $null } catch { Write-Verbose 'Cleared exited session stub' }
    }

    if ($detachFlag) {
        if ($liveZellij[$sessionName] -eq 'live') {
            Write-Output "IDE session '$sessionName' is already running in background."
            exit 0
        }
        Push-Location -LiteralPath $resolvedRoot
        try {
            & $zellijBin attach --create-background $sessionName options --default-layout $zellijLayout --default-cwd $resolvedRoot
        } finally {
            Pop-Location
        }
        Write-Output "Started detached IDE session '$sessionName' ($layout) in $resolvedRoot"
        exit 0
    }

    if ($desktopFlag) {
        $zPsi = [System.Diagnostics.ProcessStartInfo]::new()
        $zPsi.FileName = $zellijBin
        $zPsi.WorkingDirectory = $resolvedRoot
        foreach ($a in @('terminal', '--create', '--working-directory', $resolvedRoot, $sessionName, 'options', '--default-layout', $zellijLayout)) {
            $zPsi.ArgumentList.Add($a)
        }
        $zPsi.UseShellExecute = $false
        [void][System.Diagnostics.Process]::Start($zPsi)
        Write-Output "Opened Zellij desktop IDE window for '$sessionName' ($layout)"
        exit 0
    }

    if ($env:ZELLIJ -and -not $newWindow) {
        & $zellijBin action switch-session --layout $zellijLayout --cwd $resolvedRoot $sessionName
        exit $LASTEXITCODE
    }

    if ($newWindow) {
        $wtCmd = Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wtCmd) {
            $wtPsi = [System.Diagnostics.ProcessStartInfo]::new()
            $wtPsi.FileName = $wtCmd.Source
            foreach ($a in @('-w', 'new', 'new-tab', '--title', $sessionName, '-d', $resolvedRoot, $zellijBin, 'attach', '--create', $sessionName, 'options', '--default-layout', $zellijLayout, '--default-cwd', $resolvedRoot)) {
                $wtPsi.ArgumentList.Add($a)
            }
            $wtPsi.UseShellExecute = $false
            [void][System.Diagnostics.Process]::Start($wtPsi)
            Write-Output "Launched IDE session '$sessionName' in new Windows Terminal window"
            exit 0
        }
    }

    Push-Location -LiteralPath $resolvedRoot
    try {
        & $zellijBin attach --create $sessionName options --default-layout $zellijLayout --default-cwd $resolvedRoot
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

# Fallback: Windows Terminal (wt.exe) Split-Pane Backend
$pwshBin = (Get-Process -Id $PID).Path
if (-not $pwshBin) { $pwshBin = 'pwsh.exe' }

$stateDir = Get-IdeStateDir
$aiScriptPreview = Join-Path $stateDir "launch-$sessionName-ai.ps1"
$edScriptPreview = Join-Path $stateDir "launch-$sessionName-editor.ps1"
$tmScriptPreview = Join-Path $stateDir "launch-$sessionName-term.ps1"

$wtArgList = [System.Collections.Generic.List[string]]::new()
if ($newWindow) {
    $wtArgList.Add('-w')
    $wtArgList.Add('new')
} elseif ($env:WT_SESSION) {
    $wtArgList.Add('-w')
    $wtArgList.Add('0')
}

$wtArgList.Add('new-tab')
$wtArgList.Add('--title')
$wtArgList.Add($sessionName)
$wtArgList.Add('-d')
$wtArgList.Add($resolvedRoot)
$wtArgList.Add($pwshBin)
$wtArgList.Add('-NoLogo')
$wtArgList.Add('-NoExit')
$wtArgList.Add('-File')
$wtArgList.Add($aiScriptPreview)

if ($layout -eq '3pane') {
    $wtArgList.Add(';')
    $wtArgList.Add('split-pane')
    $wtArgList.Add('-H')
    $wtArgList.Add('-s')
    $wtArgList.Add('0.25')
    $wtArgList.Add('-d')
    $wtArgList.Add($resolvedRoot)
    $wtArgList.Add($pwshBin)
    $wtArgList.Add('-NoLogo')
    $wtArgList.Add('-NoExit')
    $wtArgList.Add('-File')
    $wtArgList.Add($tmScriptPreview)

    $wtArgList.Add(';')
    $wtArgList.Add('move-focus')
    $wtArgList.Add('up')

    $wtArgList.Add(';')
    $wtArgList.Add('split-pane')
    $wtArgList.Add('-V')
    $wtArgList.Add('-s')
    $wtArgList.Add('0.50')
    $wtArgList.Add('-d')
    $wtArgList.Add($resolvedRoot)
    $wtArgList.Add($pwshBin)
    $wtArgList.Add('-NoLogo')
    $wtArgList.Add('-File')
    $wtArgList.Add($edScriptPreview)

    $wtArgList.Add(';')
    $wtArgList.Add('move-focus')
    $wtArgList.Add('left')
} else {
    $wtArgList.Add(';')
    $wtArgList.Add('split-pane')
    $wtArgList.Add('-V')
    $wtArgList.Add('-s')
    $wtArgList.Add('0.50')
    $wtArgList.Add('-d')
    $wtArgList.Add($resolvedRoot)
    $wtArgList.Add($pwshBin)
    $wtArgList.Add('-NoLogo')
    $wtArgList.Add('-File')
    $wtArgList.Add($edScriptPreview)

    $wtArgList.Add(';')
    $wtArgList.Add('move-focus')
    $wtArgList.Add('left')
}

$formattedWtArgs = @($wtArgList | ForEach-Object {
    if ($_ -ne ';' -and $_ -match '\s') { "`"$($_.Replace('"', '\"'))`"" } else { $_ }
})

if ($dryRun) {
    $initialDoc = Resolve-InitialEditorFile $resolvedRoot
    Write-Output "IDE Session : $sessionName"
    Write-Output "Backend     : wt"
    Write-Output "Layout      : $layout"
    Write-Output "Workdir     : $resolvedRoot"
    Write-Output "Named Pipe  : $pipePath"
    Write-Output "AI Agent    : $($aiInfo.Name)"
    Write-Output "Editor      : $nvimBin"
    if ($initialDoc) {
        Write-Output "Initial Doc : $initialDoc"
    }
    Write-Output "WT Command  : wt.exe $($formattedWtArgs -join ' ')"
    exit 0
}

$wtCmd = Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $wtCmd) {
    [Console]::Error.WriteLine('Error: Neither Zellij (zellij) nor Windows Terminal (wt.exe) was found in PATH.')
    exit 1
}

[void](Write-PaneLauncherSet `
    -SessionName $sessionName `
    -InitialRoot $resolvedRoot `
    -WorkDir $resolvedRoot `
    -PipePath $pipePath `
    -AiCliName $aiInfo.Name `
    -AiCliPath $aiInfo.Path `
    -NvimPath $nvimBin)

$metaObj = [ordered]@{
    session       = $sessionName
    root          = $resolvedRoot
    workdir       = $resolvedRoot
    pipe          = $pipePath
    layout        = $layout
    backend       = 'wt'
    ai_cli        = $aiInfo.Name
    agent_state   = 'idle'
    agent_message = ''
    created_at    = ''
    updated_at    = ''
}
Save-SessionState $metaObj

$wtPsi = [System.Diagnostics.ProcessStartInfo]::new()
$wtPsi.FileName = $wtCmd.Source
$wtPsi.Arguments = ($formattedWtArgs -join ' ')
$wtPsi.UseShellExecute = $false
[void][System.Diagnostics.Process]::Start($wtPsi)
Write-Output "Launched IDE session '$sessionName' ($layout) in $resolvedRoot"
