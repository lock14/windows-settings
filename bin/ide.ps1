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
  --toggle                 Bounce focus between Editor and AI Agent panes (unparking if hidden)
  --focus-role <ROLE>      Focus pane role (ai, editor, or term), unparking or bouncing back if focused
  --toggle-editor          Hide or restore the Text Editor pane without stopping Neovim (Alt+Shift+E)
  --toggle-term            Hide or restore the Interactive Shell pane without stopping processes (Alt+Shift+T)
  --toggle-ai              Hide or restore the AI Agent pane without stopping the agent
  --swap <DIR>             Swap/move the focused pane in <DIR> (left, down, up, or right)
  -n, --dry-run            Preview workspace session metadata and launch command without mutating state
  --open <FILE> [LINE]     Open <FILE> in the IDE Editor pane via Named Pipe RPC
  --preview <FILE> [LINE]  Preview <FILE> in the IDE Editor pane via Named Pipe RPC
  --open-or-edit <FILE> [LINE] Open <FILE> in IDE Editor via RPC if live, else launch local Neovim
  cd, --cd [DIR]           Dive into <DIR> (or --reset / ~ for initial root) across Editor and session state
  --send [OPTS] [SESSION]  Inject context (--stdin, --ref <PATH>[:L1[-L2]], --text <TEXT>, --no-focus, --switch)
                           directly into target session's AI Agent prompt via bracketed paste (preserves clipboard)
  --agent-state <STATE> [--message <TEXT>] [SESSION]
                           Emit OSC 7501 status & record state: running, approval, quota, done, or idle
  --agy-hook <EVENT>       Internal Antigravity CLI hook adapter (PreInvocation, Stop, SessionStart)
  --ack-ai [SESSION...]    Acknowledge AI attention across one or more IDE sessions
  --open-pr [SESSION]      Open cached or active GitHub, GitLab, Bitbucket, or Gitea PR/MR URL in browser
  --monitor, --top         Toggle interactive system monitor (btop4win -> btop -> btm -> ntop -> built-in TUI)
  --keys, --help-keys      Display the TrueColor IDE workspace & editor keybinding cheatsheet
  refresh, -r, --refresh [NAME]
                           Re-apply active color theme, rebuild cheatsheet cache, reload top bar, and heal Editor CWDs
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

function Get-ActiveThemeSlug {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cfgBase = if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        $env:XDG_CONFIG_HOME.Trim()
    } else {
        Join-Path $userHome '.config'
    }
    foreach ($sub in @('windows-settings', 'home-settings')) {
        $f = Join-Path (Join-Path $cfgBase $sub) 'theme'
        if ([System.IO.File]::Exists($f)) {
            $val = ([System.IO.File]::ReadAllText($f)).Trim()
            if ($val) { return $val }
        }
    }
    return 'solarized-dark'
}

function Test-WasmBarDeployed {
    if (-not $env:APPDATA) { return $false }
    $barWasm = Join-Path (Join-Path (Join-Path (Join-Path $env:APPDATA 'Zellij') 'data') 'plugins') 'windows-settings-bar.wasm'
    return [System.IO.File]::Exists($barWasm)
}

function Invoke-ZellijPipe([string]$SessionName, [string]$PipeName, [string]$Payload, [int]$TimeoutMs = 1500) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin -or -not $Payload) { return $false }
    $curSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME.Trim() } else { '' }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $zellijBin
        if ($SessionName -and (-not $env:ZELLIJ -or -not [string]::Equals($SessionName, $curSess, [System.StringComparison]::OrdinalIgnoreCase))) {
            $psi.ArgumentList.Add('--session')
            $psi.ArgumentList.Add($SessionName)
        }
        $psi.ArgumentList.Add('pipe')
        $psi.ArgumentList.Add('--name')
        $psi.ArgumentList.Add($PipeName)
        $psi.ArgumentList.Add('--')
        $psi.ArgumentList.Add($Payload)
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) { return $false }
        try { $proc.StandardInput.Close() } catch { Write-Verbose 'zellij pipe stdin close skipped' }
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out zellij pipe terminated' }
            return $false
        }
        return ($proc.ExitCode -eq 0)
    } catch {
        return $false
    }
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
        $stateTs = if ($null -ne $obj.state_ts) { [long]$obj.state_ts } else { 0L }
        $attnTs = if ($null -ne $obj.attn_ts) { [long]$obj.attn_ts } else { 0L }
        $sidecarStatePath = Join-Path (Get-IdeStateDir) "$SessionName.state"
        if ([System.IO.File]::Exists($sidecarStatePath)) {
            $sidecarTime = [System.IO.File]::GetLastWriteTimeUtc($sidecarStatePath)
            $metaTicks = [System.IO.File]::GetLastWriteTimeUtc($metaPath).Ticks
            if ($sidecarTime.Ticks -ge $metaTicks) {
                $fastState = [System.IO.File]::ReadAllText($sidecarStatePath).Trim()
                if ($fastState) {
                    if ($fastState -ne $agentState) {
                        $stateTs = [DateTimeOffset]::new($sidecarTime).ToUnixTimeSeconds()
                        if ($fastState -in @('approval', 'done', 'error')) {
                            $attnTs = $stateTs
                        } else {
                            $attnTs = 0L
                        }
                    }
                    $agentState = $fastState
                }
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
            state_ts      = $stateTs
            attn_ts       = $attnTs
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
                $readTask = [Console]::In.ReadToEndAsync()
                if ($readTask.Wait(75)) {
                    $stdinRaw = $readTask.Result
                }
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
        @('Alt+a / e / t', 'Jump/bounce AI/Editor/Shell', 'Alt+Shift+S', 'Jump to Next Attention'),
        @('Alt+Shift+E / T', 'Hide/restore Editor / Shell', 'Alt+[ / Alt+]', 'Prev / next IDE session'),
        @('Alt+z / Alt+f', 'Zoom 100% / Floating drawer', 'Ctrl+b d', 'Detach (agents keep running)'),
        @('Alt+Arrows', 'Resize active pane', 'ide -d [dir]', 'Spawn detached session'),
        @('Alt+Shift+H/J/K/L', 'Move / swap active pane', 'ide --desktop', '1-Hop GPU app + Tray icon'),
        @('Alt+? / Alt+m', 'Toggle keys / system monitor', ':Q / Alt+q / qide', 'Safe-quit IDE (checks saves)'),
        @('Right-click bar/pane', 'IDE workspace context menu', 'Ctrl+b r / b', 'Refresh all / toggle top bar')
    )
    $rowsEditor = @(
        @('Space ff', 'Find files by name', 'Mouse drag / 2x', 'Select text and auto-copy'),
        @('Space fg', 'Search text (live grep)', 'Alt+c', 'Copy & clear highlight'),
        @('Space gs', 'Review Git status', 'Alt+v', 'Paste from clipboard'),
        @('Space m', 'Toggle Markdown preview', 'Ctrl+Click', 'Open URL, #heading, or file'),
        @('H / L  (Normal)', 'Prev / next buffer', 'Alt+Click', 'Jump to LSP definition'),
        @('Home   (Any mode)', 'Smart-Home (^ / col 1)', 'Mouse4/5 or C-o/i', 'Jump back or forward')
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
    if (-not $zellijBin -or (-not $env:ZELLIJ -and -not $SessionArg)) {
        exit 0
    }
    $normRole = switch ($Role.ToLowerInvariant()) {
        'editor' { 'editor' }
        'nvim'   { 'editor' }
        'term'   { 'term' }
        'shell'  { 'term' }
        default  { 'ai' }
    }
    $pipeRole = if ($normRole -eq 'term') { 'shell' } else { $normRole }
    $sess = Resolve-TargetSession $SessionArg
    if (Test-WasmBarDeployed) {
        if (Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload "focus:$pipeRole") {
            exit 0
        }
    }
    if (-not $env:ZELLIJ) { exit 0 }

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

function Invoke-ToggleRole([string]$Role, [string]$SessionArg = '') {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { exit 0 }
    $pipeRole = switch ($Role.ToLowerInvariant()) {
        'editor' { 'editor' }
        'nvim'   { 'editor' }
        'term'   { 'shell' }
        'shell'  { 'shell' }
        default  { 'ai' }
    }
    $sess = Resolve-TargetSession $SessionArg
    [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload "toggle:$pipeRole")
    exit 0
}

function Invoke-SwapPane([string]$Direction, [string]$SessionArg = '') {
    $dir = if ($Direction) { $Direction.Trim().ToLowerInvariant() } else { '' }
    if ($dir -notin @('left', 'down', 'up', 'right')) {
        [Console]::Error.WriteLine("Error: Invalid '--swap' direction '$Direction'. Expected: left, down, up, or right.")
        exit 1
    }
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { exit 0 }
    $sess = Resolve-TargetSession $SessionArg
    $curSess = if ($env:ZELLIJ_SESSION_NAME) { $env:ZELLIJ_SESSION_NAME.Trim() } else { '' }
    if ($env:ZELLIJ -and (-not $SessionArg -or [string]::Equals($sess, $curSess, [System.StringComparison]::OrdinalIgnoreCase))) {
        & $zellijBin action move-pane $dir *> $null
    } elseif ($sess) {
        & $zellijBin --session $sess action move-pane $dir *> $null
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
            $stateDir = Get-IdeStateDir
            $aiActivePath = Join-Path $stateDir "$sess.ai-active"
            $aiShellPath = Join-Path $stateDir "$sess.ai-shell"
            Remove-Item -LiteralPath $aiShellPath -Force -ErrorAction SilentlyContinue
            $Host.UI.RawUI.WindowTitle = "$sess [AI: $($aiInfo.Name)]"
            if ($aiInfo.Path) {
                Write-TextUtf8NoBom -Path $aiActivePath -Content "$PID`n"
                try {
                    & $aiInfo.Path
                } finally {
                    Remove-Item -LiteralPath $aiActivePath -Force -ErrorAction SilentlyContinue
                }
            } else {
                Write-Host "IDE session '$sess' ready (install '$($aiInfo.Name)' or set `$env:IDE_AI_CLI)." -ForegroundColor Cyan
            }
            Write-TextUtf8NoBom -Path $aiShellPath -Content "$PID`n"
            $Host.UI.RawUI.WindowTitle = "$sess [AI: shell]"
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

function ConvertTo-ForgeHttpsBase([string]$RemoteUrl) {
    if (-not $RemoteUrl) { return '' }
    $u = $RemoteUrl.Trim()
    if ($u -match '^https?://([^/]+)/(.+?)(?:\.git)?/?$') {
        $hostPart = $Matches[1] -replace '^[^@]+@', ''
        return "https://$hostPart/$($Matches[2])"
    }
    if ($u -match '^ssh://(?:[^@]+@)?([^:/]+)(?::[0-9]+)?/(.+?)(?:\.git)?/?$') {
        return "https://$($Matches[1])/$($Matches[2])"
    }
    if ($u -match '^(?:[^@]+@)?([A-Za-z0-9._-]+):([A-Za-z0-9._/-]+?)(?:\.git)?/?$' -and $Matches[1] -notmatch '^[A-Za-z]$') {
        return "https://$($Matches[1])/$($Matches[2])"
    }
    return ''
}

function Get-FastGitSummary([string]$Workdir) {
    $empty = @{
        Root     = ''
        Branch   = ''
        PrBadge  = ''
        PrUrl    = ''
        ForgeUrl = ''
    }
    if (-not $Workdir -or -not [System.IO.Directory]::Exists($Workdir)) {
        return $empty
    }
    $cur = $Workdir
    $repoRoot = ''
    $gitDir = ''
    $commonGitDir = ''
    while ($cur) {
        $dotGit = Join-Path $cur '.git'
        if ([System.IO.Directory]::Exists($dotGit)) {
            $repoRoot = $cur
            $gitDir = $dotGit
            $commonGitDir = $dotGit
            break
        }
        if ([System.IO.File]::Exists($dotGit)) {
            try {
                $firstLine = [System.IO.File]::ReadAllText($dotGit).Trim()
                if ($firstLine -match '^gitdir:\s*(.+)$') {
                    $resolvedGit = $Matches[1].Trim()
                    if (-not [System.IO.Path]::IsPathRooted($resolvedGit)) {
                        $resolvedGit = [System.IO.Path]::GetFullPath((Join-Path $cur $resolvedGit))
                    }
                    $repoRoot = $cur
                    $gitDir = $resolvedGit
                    $commonFile = Join-Path $resolvedGit 'commondir'
                    if ([System.IO.File]::Exists($commonFile)) {
                        $relCommon = [System.IO.File]::ReadAllText($commonFile).Trim()
                        $commonGitDir = if ([System.IO.Path]::IsPathRooted($relCommon)) {
                            $relCommon
                        } else {
                            [System.IO.Path]::GetFullPath((Join-Path $resolvedGit $relCommon))
                        }
                    } else {
                        $commonGitDir = $resolvedGit
                    }
                }
            } catch {
                return $empty
            }
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    if (-not $repoRoot -or -not $gitDir) { return $empty }

    $headFile = Join-Path $gitDir 'HEAD'
    if (-not [System.IO.File]::Exists($headFile)) { return $empty }
    $branch = ''
    try {
        $headRaw = [System.IO.File]::ReadAllText($headFile).Trim()
        if ($headRaw -match '^ref:\s*refs/heads/(.+)$') {
            $branch = $Matches[1].Trim()
        } elseif ($headRaw.Length -ge 7) {
            $branch = $headRaw.Substring(0, 7)
        }
    } catch {
        return $empty
    }

    $prBadge = ''
    $prUrl = ''
    if ($branch -and $branch -notin @('main', 'master', 'trunk')) {
        $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
        $prCacheDir = Join-Path (Join-Path $userHome '.cache') 'git-pr-prompt'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$repoRoot|$branch")
        $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
        $key = [System.BitConverter]::ToString($hashBytes, 0, 8).Replace('-', '').ToLowerInvariant()
        $stateFile = Join-Path $prCacheDir "$key.state"
        if ([System.IO.File]::Exists($stateFile)) {
            try {
                $lines = [System.IO.File]::ReadAllLines($stateFile)
                if ($lines.Count -ge 2 -and $lines[0].Trim() -and $lines[1].Trim()) {
                    $prBadge = $lines[0].Trim()
                    $prUrl = $lines[1].Trim()
                }
            } catch {
                Write-Verbose "PR cache read skipped: $_"
            }
        }
    }

    $forgeUrl = ''
    $cfgFile = Join-Path $commonGitDir 'config'
    if ([System.IO.File]::Exists($cfgFile)) {
        try {
            $inOrigin = $false
            foreach ($cfgLine in [System.IO.File]::ReadLines($cfgFile)) {
                $trimmed = $cfgLine.Trim()
                if ($trimmed.StartsWith('[')) {
                    $inOrigin = ($trimmed -match '^\[remote\s+"origin"\]')
                    continue
                }
                if ($inOrigin -and $trimmed -match '^url\s*=\s*(.+)$') {
                    $forgeUrl = ConvertTo-ForgeHttpsBase $Matches[1].Trim()
                    break
                }
            }
        } catch {
            Write-Verbose "Git config origin parse skipped: $_"
        }
    }

    return @{
        Root     = $repoRoot
        Branch   = $branch
        PrBadge  = $prBadge
        PrUrl    = $prUrl
        ForgeUrl = $forgeUrl
    }
}

function Format-ElapsedAge([long]$EpochSec) {
    if ($EpochSec -le 0) { return '' }
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $delta = $nowSec - $EpochSec
    if ($delta -lt 60) { return '' }
    if ($delta -lt 3600) { return "$([long]($delta / 60))m" }
    if ($delta -lt 86400) { return "$([long]($delta / 3600))h" }
    return "$([long]($delta / 86400))d"
}

function Get-ActivePaletteMap {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $themeEnvPs1 = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'theme_env.ps1'
    if ([System.IO.File]::Exists($themeEnvPs1)) {
        try { . $themeEnvPs1 } catch { Write-Verbose "Theme env load skipped: $_" }
    }
    $esc = [char]27
    return @{
        BASE03  = if ($env:_HS_HEX_BASE03)  { $env:_HS_HEX_BASE03 }  else { '#002B36' }
        BASE02  = if ($env:_HS_HEX_BASE02)  { $env:_HS_HEX_BASE02 }  else { '#073642' }
        BASE01  = if ($env:_HS_HEX_BASE01)  { $env:_HS_HEX_BASE01 }  else { '#586E75' }
        BASE0   = if ($env:_HS_HEX_BASE0)   { $env:_HS_HEX_BASE0 }   else { '#839496' }
        BASE1   = if ($env:_HS_HEX_BASE1)   { $env:_HS_HEX_BASE1 }   else { '#93A1A1' }
        YELLOW  = if ($env:_HS_HEX_YELLOW)  { $env:_HS_HEX_YELLOW }  else { '#B58900' }
        ORANGE  = if ($env:_HS_HEX_ORANGE)  { $env:_HS_HEX_ORANGE }  else { '#CB4B16' }
        RED     = if ($env:_HS_HEX_RED)     { $env:_HS_HEX_RED }     else { '#DC322F' }
        GREEN   = if ($env:_HS_HEX_GREEN)   { $env:_HS_HEX_GREEN }   else { '#859900' }
        BLUE    = if ($env:_HS_HEX_BLUE)    { $env:_HS_HEX_BLUE }    else { '#268BD2' }
        CYAN    = if ($env:_HS_HEX_CYAN)    { $env:_HS_HEX_CYAN }    else { '#2AA198' }
        E_B01   = if ($env:_HS_ESC_BASE01)  { $env:_HS_ESC_BASE01 }  else { "${esc}[38;2;88;110;117m" }
        E_B0    = if ($env:_HS_ESC_BASE0)   { $env:_HS_ESC_BASE0 }   else { "${esc}[38;2;131;148;150m" }
        E_B1    = if ($env:_HS_ESC_BASE1)   { $env:_HS_ESC_BASE1 }   else { "${esc}[38;2;147;161;161m" }
        E_YLW   = if ($env:_HS_ESC_YELLOW)  { $env:_HS_ESC_YELLOW }  else { "${esc}[38;2;181;137;0m" }
        E_ORG   = if ($env:_HS_ESC_ORANGE)  { $env:_HS_ESC_ORANGE }  else { "${esc}[38;2;203;75;22m" }
        E_RED   = if ($env:_HS_ESC_RED)     { $env:_HS_ESC_RED }     else { "${esc}[38;2;220;50;47m" }
        E_GRN   = if ($env:_HS_ESC_GREEN)   { $env:_HS_ESC_GREEN }   else { "${esc}[38;2;133;153;0m" }
        E_BLU   = if ($env:_HS_ESC_BLUE)    { $env:_HS_ESC_BLUE }    else { "${esc}[38;2;38;139;210m" }
        E_CYN   = if ($env:_HS_ESC_CYAN)    { $env:_HS_ESC_CYAN }    else { "${esc}[38;2;42;161;152m" }
        E_RST   = "${esc}[0m"
    }
}

function Get-ClassifiedIdeFleet([bool]$IncludeGit = $true) {
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
                state_ts      = 0L
                attn_ts       = 0L
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
                state_ts      = 0L
                attn_ts       = 0L
            }
        }
    }

    $curSess = if ($env:ZELLIJ_SESSION_NAME -and $env:ZELLIJ_SESSION_NAME.Trim()) {
        Get-SanitizedToken $env:ZELLIJ_SESSION_NAME.Trim()
    } elseif ($env:IDE_SESSION -and $env:IDE_SESSION.Trim()) {
        Get-SanitizedToken $env:IDE_SESSION.Trim()
    } else {
        ''
    }

    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $normHome = if ($userHome) { $userHome.TrimEnd('\', '/') } else { '' }
    $liveWorkdirCounts = @{}
    foreach ($k in $sessions.Keys) {
        $m = $sessions[$k]
        $zSt = $liveZellij[$k]
        $pUp = $livePipes.ContainsKey($k) -or (Test-IdePipeLive ([string]$m['pipe']))
        if ($zSt -eq 'live' -or $pUp) {
            $wd = if ($m['workdir']) { [string]$m['workdir'] } elseif ($m['root']) { [string]$m['root'] } else { '' }
            if ($wd) {
                $normWd = $wd.TrimEnd('\', '/').ToLowerInvariant()
                $liveWorkdirCounts[$normWd] = $(if ($liveWorkdirCounts.ContainsKey($normWd)) { $liveWorkdirCounts[$normWd] } else { 0 }) + 1
            }
        }
    }

    $entries = [System.Collections.Generic.List[hashtable]]::new()
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
        $rawState = ([string]$m['agent_state']).ToLowerInvariant()
        $aiCli = if ($m['ai_cli']) { [string]$m['ai_cli'] } else { 'agy' }
        $tier = 4
        $dispState = 'IDLE'
        $needsAttn = $false
        if ($status -ne 'live') {
            $tier = 4
            $dispState = $status.ToUpperInvariant()
        } elseif ($aiCli -eq 'shell') {
            $tier = 4
            $dispState = 'SHELL'
        } else {
            switch ($rawState) {
                { $_ -in @('approval', 'blocked', 'question', 'error', 'failed') } {
                    $tier = 0
                    $dispState = if ($_ -in @('error', 'failed')) { 'ERROR' } else { 'ATTN' }
                    $needsAttn = $true
                }
                'done' {
                    $tier = 1
                    $dispState = 'DONE'
                    $needsAttn = $true
                }
                'quota' {
                    $tier = 2
                    $dispState = 'QUOTA'
                }
                { $_ -in @('running', 'working') } {
                    $tier = 2
                    $dispState = 'WORKING'
                }
                default {
                    $tier = 3
                    $dispState = 'IDLE'
                }
            }
        }

        $stateTs = if ($null -ne $m['state_ts']) { [long]$m['state_ts'] } else { 0L }
        $attnTs = if ($null -ne $m['attn_ts']) { [long]$m['attn_ts'] } else { 0L }
        $age = if ($status -eq 'live' -and $dispState -in @('ATTN', 'ERROR', 'DONE', 'QUOTA', 'WORKING')) {
            Format-ElapsedAge $stateTs
        } else {
            ''
        }
        $stateLabel = if ($age) { "$dispState $age" } else { $dispState }

        $wdir = if ($m['workdir']) { [string]$m['workdir'] } elseif ($m['root']) { [string]$m['root'] } else { '' }
        $shortPath = if (-not $wdir) {
            '-'
        } elseif ($normHome -and $wdir.StartsWith($normHome, [System.StringComparison]::OrdinalIgnoreCase)) {
            '~' + $wdir.Substring($normHome.Length)
        } else {
            $wdir
        }
        $hasWtWarn = $false
        if ($status -eq 'live' -and $wdir) {
            $normWd = $wdir.TrimEnd('\', '/').ToLowerInvariant()
            if ($liveWorkdirCounts[$normWd] -gt 1) {
                $hasWtWarn = $true
            }
        }

        $branchLabel = '-'
        if ($IncludeGit -and $wdir) {
            $git = Get-FastGitSummary $wdir
            if ($git.Branch) {
                $branchLabel = "$($git.Branch)$($git.PrBadge)"
            }
        }

        $entries.Add(@{
            Session       = $k
            Status        = $status
            Layout        = if ($m['layout']) { [string]$m['layout'] } else { '3pane' }
            AiCli         = $aiCli
            State         = $dispState
            StateLabel    = $stateLabel
            NeedsAttn     = $needsAttn
            Tier          = $tier
            SortTs        = if ($attnTs -gt 0) { $attnTs } else { $stateTs }
            BranchLabel   = $branchLabel
            Workdir       = if ($wdir) { $wdir } else { '-' }
            ShortPath     = $shortPath
            HasPeerWarn   = $hasWtWarn
            IsCurrent     = ($curSess -and [string]::Equals($k, $curSess, [System.StringComparison]::OrdinalIgnoreCase))
            Message       = if ($m['agent_message']) { [string]$m['agent_message'] } else { '' }
        })
    }

    return @($entries | Sort-Object `
        @{ Expression = { $_.Tier }; Ascending = $true }, `
        @{ Expression = { $_.SortTs }; Ascending = $true }, `
        @{ Expression = { $_.Session }; Ascending = $true })
}

function Format-FleetTableLine([hashtable]$Entry, [hashtable]$Pal, [int]$SessW, [int]$CliW, [int]$StateW, [int]$GitW, [bool]$UseColor) {
    $sPad = ([string]$Entry.Session).PadRight($SessW)
    $cPad = ([string]$Entry.AiCli).PadRight($CliW)
    $stPad = ([string]$Entry.StateLabel).PadRight($StateW)
    $gPad = ([string]$Entry.BranchLabel).PadRight($GitW)
    if ($UseColor) {
        $attnC = if ($Entry.State -eq 'DONE') { $Pal.E_GRN } elseif ($Entry.State -eq 'ERROR') { $Pal.E_RED } else { $Pal.E_ORG }
        $marker = if ($Entry.IsCurrent) {
            "$($Pal.E_CYN)▸$($Pal.E_RST)"
        } elseif ($Entry.NeedsAttn) {
            "${attnC}󰂚$($Pal.E_RST)"
        } else {
            ' '
        }
        $cSess = if ($Entry.IsCurrent) { $Pal.E_B1 } elseif ($Entry.NeedsAttn) { $attnC } elseif ($Entry.Status -ne 'live') { $Pal.E_B01 } else { $Pal.E_BLU }
        $cState = switch ($Entry.State) {
            'ATTN'    { $Pal.E_ORG }
            'ERROR'   { $Pal.E_RED }
            'DONE'    { $Pal.E_GRN }
            'QUOTA'   { $Pal.E_YLW }
            'WORKING' { $Pal.E_BLU }
            'IDLE'    { $Pal.E_CYN }
            default   { $Pal.E_B01 }
        }
        $cGit = if ($Entry.BranchLabel -eq '-') { $Pal.E_B01 } elseif ($Entry.BranchLabel -match '[@!][0-9]+$') { $Pal.E_CYN } else { $Pal.E_GRN }
        $wtSfx = if ($Entry.HasPeerWarn) { " $($Pal.E_YLW)!$($Pal.E_RST)" } else { '' }
        return "$marker ${cSess}${sPad}$($Pal.E_RST)  $($Pal.E_B0)${cPad}$($Pal.E_RST)  ${cState}${stPad}$($Pal.E_RST)  ${cGit}${gPad}$($Pal.E_RST)  $($Pal.E_B0)$($Entry.ShortPath)$($Pal.E_RST)${wtSfx}"
    }
    $plainMarker = if ($Entry.IsCurrent) { '*' } elseif ($Entry.NeedsAttn) { '!' } else { ' ' }
    $plainSfx = if ($Entry.HasPeerWarn) { ' !' } else { '' }
    return "$plainMarker $sPad  $cPad  $stPad  $gPad  $($Entry.ShortPath)$plainSfx"
}

function Format-FzfSessionRowList {
    $fleet = Get-ClassifiedIdeFleet -IncludeGit $true
    if ($fleet.Count -eq 0) { return @() }
    $pal = Get-ActivePaletteMap
    $sessW = 7
    $cliW = 5
    $stateW = 5
    $gitW = 6
    foreach ($e in $fleet) {
        if ($e.Session.Length -gt $sessW) { $sessW = [Math]::Min(28, $e.Session.Length) }
        if ($e.AiCli.Length -gt $cliW) { $cliW = [Math]::Min(12, $e.AiCli.Length) }
        if ($e.StateLabel.Length -gt $stateW) { $stateW = [Math]::Min(16, $e.StateLabel.Length) }
        if ($e.BranchLabel.Length -gt $gitW) { $gitW = [Math]::Min(28, $e.BranchLabel.Length) }
    }
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $fleet) {
        $line = Format-FleetTableLine -Entry $e -Pal $pal -SessW $sessW -CliW $cliW -StateW $stateW -GitW $gitW -UseColor $true
        $rows.Add("$($e.Session)`t$line")
    }
    return $rows.ToArray()
}

function Invoke-SessionSwitcher {
    $zellijBin = Resolve-ZellijExecutable
    if ($zellijBin -and $env:ZELLIJ -and $env:IDE_FZF_SESSIONS -ne '1') {
        & $zellijBin action launch-or-focus-plugin --floating --move-to-focused-tab 'zellij:session-manager' *> $null
        exit 0
    }
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zellijBin -and $fzfCmd -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $rows = @(Format-FzfSessionRowList)
        if ($rows.Count -eq 0) {
            Write-Output 'No IDE workspace sessions found.'
            exit 0
        }
        $pal = Get-ActivePaletteMap
        $pwshExe = (Get-Process -Id $PID).Path
        if (-not $pwshExe) { $pwshExe = 'pwsh' }
        $selfQuoted = "`"$PSCommandPath`""
        $pwshQuoted = "`"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File $selfQuoted"
        $reloadCmd = "$pwshQuoted --sessions-lines"
        $fzfColors = "--color=bg+:$($pal.BASE02),bg:$($pal.BASE03),spinner:$($pal.GREEN),hl:$($pal.BASE01),fg:$($pal.BASE0),header:$($pal.BASE01),info:$($pal.YELLOW),pointer:$($pal.GREEN),marker:$($pal.GREEN),fg+:$($pal.BASE1),prompt:$($pal.YELLOW),hl+:$($pal.BLUE),label:$($pal.BASE01)"

        $rawOut = @($rows | & $fzfCmd.Source `
            --ansi `
            "--delimiter=`t" `
            --with-nth=2.. `
            --multi `
            --layout=reverse `
            --height=70% `
            --info=inline-right `
            '--prompt=IDE > ' `
            --border=rounded `
            '--border-label= Enter: attach | C-a/e/t: role | C-y: ack | C-o: PR | M-n: new | C-x: quit | C-r: reload ' `
            --border-label-pos=bottom `
            --expect=ctrl-a,ctrl-e,ctrl-t,alt-n `
            "--bind=ctrl-r:reload($reloadCmd)" `
            "--bind=ctrl-y:execute-silent($pwshQuoted --ack-ai {+1})+reload($reloadCmd)" `
            "--bind=ctrl-o:execute-silent($pwshQuoted --open-pr {1})" `
            "--bind=ctrl-x:execute-silent($pwshQuoted --quit {+1})+reload($reloadCmd)" `
            $fzfColors)

        if ($LASTEXITCODE -ne 0 -or $rawOut.Count -eq 0) {
            exit 0
        }
        $keyPressed = "$($rawOut[0])".Trim()
        if ($keyPressed -eq 'alt-n') {
            $zoxCmd = Get-Command zoxide -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($zoxCmd) {
                $dirs = @(& $zoxCmd.Source query -l 2>$null)
                if ($dirs.Count -gt 0) {
                    $pickedDir = ($dirs | & $fzfCmd.Source --layout=reverse --height=60% --border=rounded '--prompt=New IDE Dir > ' $fzfColors | Out-String).Trim()
                    if ($LASTEXITCODE -eq 0 -and $pickedDir -and (Test-Path -LiteralPath $pickedDir -PathType Container)) {
                        & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath $pickedDir
                        exit $LASTEXITCODE
                    }
                }
            }
            exit 0
        }

        $selLine = if ($rawOut.Count -ge 2) { "$($rawOut[1])" } else { '' }
        $chosen = ($selLine -split "`t")[0].Trim()
        if ($chosen) {
            $env:ZELLIJ_CONFIG_DIR = Get-ZellijConfigDir
            $meta = Read-SessionState $chosen
            $wdir = if ($meta -and $meta['workdir'] -and (Test-Path -LiteralPath $meta['workdir'])) { [string]$meta['workdir'] } else { (Get-Location).ProviderPath }
            $lay = if ($meta -and $meta['layout'] -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }
            $focusRole = switch ($keyPressed) {
                'ctrl-a' { 'ai' }
                'ctrl-e' { 'editor' }
                'ctrl-t' { 'shell' }
                default  { '' }
            }
            if ($focusRole) {
                [void](Invoke-ZellijPipe -SessionName $chosen -PipeName 'ws-ide-role' -Payload "ensure:$focusRole")
            }
            if ($env:ZELLIJ) {
                & $zellijBin action switch-session --layout $lay --cwd $wdir $chosen
            } else {
                & $zellijBin attach --create $chosen options --default-layout $lay --default-cwd $wdir
            }
            exit $LASTEXITCODE
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

    if ($env:ZELLIJ -or (Resolve-ZellijExecutable)) {
        [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-state' -Payload "root=$initRoot;workdir=$resolved")
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

function ConvertTo-SanitizedPasteText([string]$Text) {
    if (-not $Text) { return '' }
    $esc = [char]27
    $csi = [char]0x9B
    $markers = @(
        "${esc}[200~",
        "${esc}[201~",
        "${csi}200~",
        "${csi}201~"
    )
    $clean = $Text
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($m in $markers) {
            if ($clean.Contains($m)) {
                $clean = $clean.Replace($m, '')
                $changed = $true
            }
        }
    }
    return $clean
}

function Invoke-IdeSend([string[]]$SendArgs, [string]$PipedInput = '') {
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
        $payload = if ($PipedInput) { $PipedInput } elseif ([Console]::IsInputRedirected) { [Console]::In.ReadToEnd() } else { '' }
    } elseif ($mode -eq 'ref' -and $payload) {
        $payload = Format-RelativeFileRef -RawRef $payload -BaseDir $baseDir
    }

    $payload = ConvertTo-SanitizedPasteText $payload
    if (-not $payload) {
        exit 0
    }

    $stateDir = Get-IdeStateDir
    $stageFile = Join-Path $stateDir "$sess.send.txt"
    Write-TextUtf8NoBom -Path $stageFile -Content $payload

    if ($env:WS_IDE_COPY_CLIPBOARD -eq '1' -and $env:WS_IDE_SKIP_CLIPBOARD -ne '1') {
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
            $inSameSession = ($env:ZELLIJ -and [string]::Equals($curZellijSess, $sess, [System.StringComparison]::OrdinalIgnoreCase))

            $panesJson = try {
                if ($inSameSession) {
                    (& $zellijBin action list-panes --all --json 2>$null) -join "`n"
                } else {
                    (& $zellijBin --session $sess action list-panes --all --json 2>$null) -join "`n"
                }
            } catch {
                ''
            }

            $aiEntry = $null
            if ($panesJson) {
                try {
                    $allPanes = @($panesJson | ConvertFrom-Json)
                    $rawNum = 0
                    if (($aiPaneId -replace '^terminal_', '') -match '^[0-9]+$') {
                        $rawNum = [int]($aiPaneId -replace '^terminal_', '')
                        $aiEntry = $allPanes | Where-Object { -not $_.is_plugin -and $_.id -eq $rawNum } | Select-Object -First 1
                    }
                    if (-not $aiEntry) {
                        $aiEntry = $allPanes | Where-Object { -not $_.is_plugin -and "$($_.title)" -match '(?i)(^AI$|\bAI:|\bagy\b|\bclaude\b|\bcodex\b)' } | Select-Object -First 1
                    }
                    if ($aiEntry) {
                        $aiPaneId = "terminal_$($aiEntry.id)"
                    }
                } catch {
                    Write-Verbose "Pane JSON inspection skipped: $_"
                }
            }

            if ($aiEntry -and $aiEntry.exited -eq $true) {
                [Console]::Error.WriteLine("Error: AI pane in session '$sess' has exited; refusing to paste into dead pane.")
                exit 1
            }

            $aiShellMarker = Join-Path $stateDir "$sess.ai-shell"
            if ($env:IDE_ALLOW_SHELL_SEND -ne '1' -and (
                [System.IO.File]::Exists($aiShellMarker) -or
                ($meta -and $meta['ai_cli'] -eq 'shell') -or
                ($aiEntry -and "$($aiEntry.title)" -match '\[AI:\s*shell\]')
            )) {
                $hasLiveAgentProc = @(Get-Process -Name 'agy', 'claude', 'codex' -ErrorAction SilentlyContinue).Count -gt 0
                if (-not $hasLiveAgentProc) {
                    [Console]::Error.WriteLine("Error: No active AI agent running in session '$sess' (pane is at an interactive shell); start an agent or set IDE_ALLOW_SHELL_SEND=1.")
                    exit 1
                }
            }

            if ($aiEntry -and $aiEntry.is_suppressed -eq $true) {
                [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload 'toggle:ai')
            }

            if ($inSameSession) {
                & $zellijBin action paste --pane-id $aiPaneId -- $payload *> $null
                if (-not $noFocus) {
                    & $zellijBin action focus-pane-id $aiPaneId *> $null
                }
            } else {
                & $zellijBin --session $sess action paste --pane-id $aiPaneId -- $payload *> $null
                if ($switchSession) {
                    if ($env:ZELLIJ) {
                        & $zellijBin action switch-session --pane-id $aiPaneId $sess *> $null
                    } else {
                        & $zellijBin attach $sess
                    }
                }
            }
        }
    }
}

function Show-IdeSessionList([bool]$Plain) {
    $fleet = Get-ClassifiedIdeFleet -IncludeGit (-not $Plain)
    if ($Plain) {
        foreach ($e in $fleet) {
            Write-Output $e.Session
        }
        return
    }

    if ($fleet.Count -eq 0) {
        Write-Output 'No IDE workspace sessions found.'
        return
    }

    $useColor = (-not [Console]::IsOutputRedirected) -and (-not $env:NO_COLOR)
    $pal = Get-ActivePaletteMap
    $sessW = 7
    $cliW = 5
    $stateW = 5
    $gitW = 6
    foreach ($e in $fleet) {
        if ($e.Session.Length -gt $sessW) { $sessW = [Math]::Min(28, $e.Session.Length) }
        if ($e.AiCli.Length -gt $cliW) { $cliW = [Math]::Min(12, $e.AiCli.Length) }
        if ($e.StateLabel.Length -gt $stateW) { $stateW = [Math]::Min(16, $e.StateLabel.Length) }
        if ($e.BranchLabel.Length -gt $gitW) { $gitW = [Math]::Min(28, $e.BranchLabel.Length) }
    }

    $hdr = ('  {0}  {1}  {2}  {3}  WORKSPACE' -f 'SESSION'.PadRight($sessW), 'AGENT'.PadRight($cliW), 'STATE'.PadRight($stateW), 'BRANCH'.PadRight($gitW))
    if ($useColor) {
        Write-Output "$($pal.E_B01)${hdr}$($pal.E_RST)"
    } else {
        Write-Output $hdr
    }

    foreach ($e in $fleet) {
        Write-Output (Format-FleetTableLine -Entry $e -Pal $pal -SessW $sessW -CliW $cliW -StateW $stateW -GitW $gitW -UseColor $useColor)
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
            "$sess.ai-active",
            "$sess.ai-shell",
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

function Format-SanitizedAgentMessage([string]$RawMessage) {
    if (-not $RawMessage) { return '' }
    $esc = [char]27
    $bel = [char]7
    $clean = [regex]::Replace($RawMessage, "${esc}\][^\x07\x1b]*(?:${bel}|${esc}\\)", '')
    $clean = [regex]::Replace($clean, "${esc}\[[0-9;?]*[ -/]*[@-~]", '')
    $clean = [regex]::Replace($clean, '[\x00-\x1F\x7F]+', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean.Length -gt 160) {
        $clean = $clean.Substring(0, 159) + [char]0x2026
    }
    return $clean
}

function Invoke-AgentState([string[]]$StateArgs, [string]$PipedInput = '') {
    $stdinRaw = ''
    if ($env:WS_AGENT_STATE_STDIN) {
        $stdinRaw = $env:WS_AGENT_STATE_STDIN
    } elseif ($PipedInput) {
        $stdinRaw = $PipedInput
    } else {
        try {
            if ([Console]::IsInputRedirected) {
                $readTask = [Console]::In.ReadToEndAsync()
                if ($readTask.Wait(75)) {
                    $stdinRaw = $readTask.Result
                }
            }
        } catch {
            $stdinRaw = ''
        }
    }

    $rawState = if ($StateArgs.Count -gt 0) { [string]$StateArgs[0] } else { '' }
    $state = $rawState.Trim().ToLowerInvariant()
    if ($state -notin @('running', 'approval', 'quota', 'done', 'idle')) {
        [Console]::Error.WriteLine("Error: Invalid '--agent-state' value '$rawState'. Expected: running, approval, quota, done, or idle.")
        exit 1
    }

    $explicitMsg = ''
    $sessArg = ''
    $jsonPayloads = [System.Collections.Generic.List[string]]::new()
    if ($stdinRaw -and $stdinRaw.Trim()) {
        $jsonPayloads.Add($stdinRaw.Trim())
    }

    for ($idx = 1; $idx -lt $StateArgs.Count; $idx++) {
        $nx = [string]$StateArgs[$idx]
        if ($nx -eq '--message') {
            if ($idx + 1 -ge $StateArgs.Count) {
                [Console]::Error.WriteLine('Error: --message requires a text value.')
                exit 1
            }
            $explicitMsg = [string]$StateArgs[++$idx]
        } elseif ($nx.Trim().StartsWith('{') -and $nx.Trim().EndsWith('}')) {
            $jsonPayloads.Add($nx.Trim())
        } else {
            $sessArg = $nx
        }
    }

    $notifType = ''
    $jsonMsg = ''
    foreach ($jp in $jsonPayloads) {
        try {
            $obj = $jp | ConvertFrom-Json -ErrorAction Stop
            if (-not $notifType) {
                if ($obj.PSObject.Properties['notification_type'] -and $obj.notification_type) {
                    $notifType = "$($obj.notification_type)".Trim()
                } elseif ($obj.PSObject.Properties['type'] -and $obj.type) {
                    $notifType = "$($obj.type)".Trim()
                }
            }
            if (-not $jsonMsg) {
                foreach ($prop in @('message', 'last-assistant-message', 'last_assistant_message', 'summary', 'title')) {
                    if ($obj.PSObject.Properties[$prop] -and $obj.$prop) {
                        $cand = "$($obj.$prop)".Trim()
                        if ($cand) {
                            $jsonMsg = $cand
                            break
                        }
                    }
                }
            }
        } catch {
            Write-Verbose "Hook JSON parse skipped: $_"
        }
    }

    if ($notifType -eq 'idle_prompt') {
        exit 0
    }

    $rawMsg = if ($explicitMsg -and $explicitMsg.Trim()) { $explicitMsg.Trim() } else { $jsonMsg }
    $cleanMsg = Format-SanitizedAgentMessage $rawMsg
    $msgToPersist = if ($state -in @('approval', 'quota', 'done')) { $cleanMsg } else { '' }

    if ($env:WS_AGY_HOOK_NO_TTY -ne '1') {
        Write-Osc7501Status (Format-Osc7501Spec -StateName $state -Message $msgToPersist)
    }

    if (-not $sessArg -and -not $env:ZELLIJ_SESSION_NAME -and -not $env:IDE_SESSION) {
        exit 0
    }

    $sess = Resolve-TargetSession $sessArg
    $meta = Read-SessionState $sess
    if (-not $meta) {
        if ($sessArg) {
            [Console]::Error.WriteLine("Error: No active IDE session named '$sess'.")
            exit 1
        }
        exit 0
    }

    $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $prevState = ([string]$meta['agent_state']).ToLowerInvariant()
    $prevStateTs = if ($null -ne $meta['state_ts']) { [long]$meta['state_ts'] } else { 0L }
    $prevAttnTs = if ($null -ne $meta['attn_ts']) { [long]$meta['attn_ts'] } else { 0L }
    $prevMsg = if ($meta['agent_message']) { [string]$meta['agent_message'] } else { '' }

    $nextStateTs = if ($prevState -eq $state -and $prevStateTs -gt 0) { $prevStateTs } else { $nowEpoch }
    $nextAttnTs = if ($state -in @('approval', 'done')) {
        if ($prevState -eq $state -and $prevAttnTs -gt 0) { $prevAttnTs } else { $nowEpoch }
    } else {
        0L
    }
    if (-not $msgToPersist -and $state -in @('approval', 'quota', 'done') -and $prevState -eq $state) {
        $msgToPersist = $prevMsg
    }

    $meta['agent_state'] = $state
    $meta['agent_message'] = $msgToPersist
    $meta['state_ts'] = $nextStateTs
    $meta['attn_ts'] = $nextAttnTs
    Save-SessionState $meta
    exit 0
}

function Invoke-OpenSessionPr([string]$SessArg) {
    $sess = Resolve-TargetSession $SessArg
    $meta = Read-SessionState $sess
    $wdir = if ($meta -and $meta['workdir']) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root']) {
        [string]$meta['root']
    } elseif (-not $SessArg) {
        (Get-Location).ProviderPath
    } else {
        ''
    }
    if (-not $wdir -or -not (Test-Path -LiteralPath $wdir -PathType Container)) {
        [Console]::Error.WriteLine("Error: No active IDE session or workspace directory for '$sess'.")
        exit 1
    }

    $git = Get-FastGitSummary $wdir
    $prUrl = ''
    if ($git.PrUrl -and $git.PrUrl -match '^https?://\S+$') {
        $prUrl = $git.PrUrl
    }

    if (-not $prUrl) {
        $pushed = $false
        Push-Location -LiteralPath $wdir
        $pushed = $true
        try {
            $isGitLab = ($git.ForgeUrl -match '(?i)gitlab')
            $ghCmd = Get-Command gh -ErrorAction SilentlyContinue | Select-Object -First 1
            $glabCmd = Get-Command glab -ErrorAction SilentlyContinue | Select-Object -First 1
            $prLabel = ''

            if (-not $isGitLab -and $ghCmd) {
                $ghJson = (& $ghCmd.Source pr view --json number,url,state 2>$null) -join "`n"
                if ($LASTEXITCODE -eq 0 -and $ghJson) {
                    try {
                        $ghObj = $ghJson | ConvertFrom-Json
                        if ($ghObj.url -and "$($ghObj.url)" -match '^https?://\S+$') {
                            $prUrl = "$($ghObj.url)".Trim()
                            if ($ghObj.number) { $prLabel = "@$($ghObj.number)" }
                        }
                    } catch { Write-Verbose "gh JSON parse skipped: $_" }
                }
            }
            if (-not $prUrl -and $glabCmd) {
                $glJson = (& $glabCmd.Source mr view -F json 2>$null) -join "`n"
                if ($LASTEXITCODE -eq 0 -and $glJson) {
                    try {
                        $glObj = $glJson | ConvertFrom-Json
                        if ($glObj.web_url -and "$($glObj.web_url)" -match '^https?://\S+$') {
                            $prUrl = "$($glObj.web_url)".Trim()
                            if ($glObj.iid) { $prLabel = "!$($glObj.iid)" }
                        }
                    } catch { Write-Verbose "glab JSON parse skipped: $_" }
                }
            }

            if ($prUrl -and $prLabel -and $git.Root -and $git.Branch -and $git.Branch -notin @('main', 'master', 'trunk')) {
                try {
                    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
                    $prCacheDir = Join-Path (Join-Path $userHome '.cache') 'git-pr-prompt'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$($git.Root)|$($git.Branch)")
                    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
                    $key = [System.BitConverter]::ToString($hashBytes, 0, 8).Replace('-', '').ToLowerInvariant()
                    Write-TextUtf8NoBom -Path (Join-Path $prCacheDir "$key.state") -Content "$prLabel`n$prUrl`n"
                } catch {
                    Write-Verbose "PR cache write skipped: $_"
                }
            }
        } finally {
            if ($pushed) { Pop-Location }
        }
    }

    if (-not $prUrl) {
        [Console]::Error.WriteLine("No pull or merge request found for session '$sess'.")
        exit 1
    }

    if ($env:WS_IDE_DRY_OPEN_PR -eq '1') {
        Write-Output $prUrl
        exit 0
    }

    if ($env:IDE_BROWSER -and $env:IDE_BROWSER.Trim()) {
        Start-Process -FilePath $env:IDE_BROWSER.Trim() -ArgumentList $prUrl
    } else {
        Start-Process $prUrl
    }
    exit 0
}

function Invoke-IdeRefresh([string]$TargetArg, [bool]$IsDryRun) {
    $activeSlug = Get-ActiveThemeSlug
    if ($IsDryRun) {
        $scopeDesc = if ($TargetArg) { "session '$(Resolve-TargetSession $TargetArg)'" } else { 'all live IDE sessions' }
        Write-Output "[DRY-RUN] Would re-apply active theme '$activeSlug', rebuild keys-cheatsheet.ans, reload windows-settings-bar, and heal Editor CWDs across $scopeDesc."
        exit 0
    }

    $themePs1 = Join-Path $ScriptDir 'theme.ps1'
    if (Test-Path -LiteralPath $themePs1 -PathType Leaf) {
        & $themePs1 --set $activeSlug --no-live *> $null
    }
    Write-IdeKeysCheatsheetCache

    $zellijBin = Resolve-ZellijExecutable
    $liveZellij = Get-LiveZellijSessionMap
    $curZellijSess = if ($env:ZELLIJ_SESSION_NAME) { Get-SanitizedToken $env:ZELLIJ_SESSION_NAME.Trim() } else { '' }
    $targetSess = if ($TargetArg) { Resolve-TargetSession $TargetArg } else { '' }

    if ($zellijBin) {
        $wasmDeployed = Test-WasmBarDeployed
        $zTargets = if ($targetSess) {
            if ($liveZellij[$targetSess] -eq 'live') { @($targetSess) } else { @() }
        } else {
            @($liveZellij.Keys | Where-Object { $liveZellij[$_] -eq 'live' })
        }
        foreach ($zs in $zTargets) {
            if ($wasmDeployed) {
                if ($env:ZELLIJ -and [string]::Equals($zs, $curZellijSess, [System.StringComparison]::OrdinalIgnoreCase)) {
                    & $zellijBin action start-or-reload-plugin 'compact-bar' *> $null
                } else {
                    & $zellijBin --session $zs action start-or-reload-plugin 'compact-bar' *> $null
                }
            }
            $zMeta = Read-SessionState $zs
            $kvParts = [System.Collections.Generic.List[string]]::new()
            $kvParts.Add("theme=$activeSlug")
            if ($zMeta -and $zMeta['root']) { $kvParts.Add("root=$($zMeta['root'])") }
            if ($zMeta -and $zMeta['workdir']) { $kvParts.Add("workdir=$($zMeta['workdir'])") }
            [void](Invoke-ZellijPipe -SessionName $zs -PipeName 'ws-ide-state' -Payload ($kvParts -join ';'))
        }
    }

    $pipeTargets = [ordered]@{}
    if ($targetSess) {
        $p = Get-SessionPipePath $targetSess
        if (Test-IdePipeLive $p) { $pipeTargets[$targetSess] = $p }
    } else {
        $livePipes = Get-LiveIdePipeMap
        foreach ($kv in $livePipes.GetEnumerator()) {
            $pipeTargets[$kv.Key] = $kv.Value
        }
    }

    foreach ($sKey in $pipeTargets.Keys) {
        $pipe = $pipeTargets[$sKey]
        $sMeta = Read-SessionState $sKey
        $healDir = ''
        if ($sMeta -and $sMeta['workdir'] -and (Test-Path -LiteralPath $sMeta['workdir'] -PathType Container)) {
            $healDir = [string]$sMeta['workdir']
        } elseif ($sMeta -and $sMeta['root'] -and (Test-Path -LiteralPath $sMeta['root'] -PathType Container)) {
            $healDir = [string]$sMeta['root']
        }
        $vimDir = $healDir.Replace("'", "''")
        $expr = "luaeval('(function(d) vim.schedule(function() if d ~= """" and vim.fn.getcwd() ~= d then pcall(vim.fn.chdir, d) end; pcall(vim.cmd, ""silent! checktime""); if _G.apply_home_settings_theme then pcall(_G.apply_home_settings_theme) end end); return ""OK"" end)(_A)', '$vimDir')"
        [void](Invoke-NvimRemoteExpr -PipePath $pipe -Expr $expr)
    }
    exit 0
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
        '--sessions-lines' {
            foreach ($r in (Format-FzfSessionRowList)) {
                Write-Output $r
            }
            exit 0
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
        { $_ -in @('--toggle-ai', '--toggle-editor', '--toggle-term') } {
            $rName = $arg.Substring(9)
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-ToggleRole -Role $rName -SessionArg $optSess
        }
        '--swap' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: --swap requires a direction (left, down, up, or right).')
                exit 1
            }
            $swapDir = [string]$args[++$i]
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-SwapPane -Direction $swapDir -SessionArg $optSess
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
            $pipedText = ''
            if ($MyInvocation.ExpectingInput) {
                $inEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
                if ($null -ne $inEnum) {
                    $pipedArr = @($inEnum)
                    if ($pipedArr.Count -gt 0) { $pipedText = $pipedArr -join "`n" }
                }
            }
            Invoke-IdeSend -SendArgs $rem -PipedInput $pipedText
            exit 0
        }
        '--agy-hook' {
            $evName = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            Invoke-AgyHook -HookEventArg $evName
        }
        '--agent-state' {
            $remStateArgs = @()
            if ($i + 1 -lt $args.Count) {
                $remStateArgs = @($args[($i + 1)..($args.Count - 1)] | ForEach-Object { [string]$_ })
            }
            $pipedStateText = ''
            if ($MyInvocation.ExpectingInput) {
                $stateEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
                if ($null -ne $stateEnum) {
                    $pipedStateArr = @($stateEnum)
                    if ($pipedStateArr.Count -gt 0) { $pipedStateText = $pipedStateArr -join "`n" }
                }
            }
            Invoke-AgentState -StateArgs $remStateArgs -PipedInput $pipedStateText
        }
        '--ack-ai' {
            $ackTargets = @()
            while ($i + 1 -lt $args.Count) { $ackTargets += [string]$args[++$i] }
            if ($ackTargets.Count -eq 0) { $ackTargets = @(Resolve-TargetSession '') }
            $zBin = Resolve-ZellijExecutable
            if ($zBin -and $env:ZELLIJ) {
                & $zBin action mark-all-seen *> $null
            }
            $nowAck = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            foreach ($at in $ackTargets) {
                $s = Resolve-TargetSession $at
                $meta = Read-SessionState $s
                if ($meta) {
                    $curSt = ([string]$meta['agent_state']).ToLowerInvariant()
                    if ($curSt -eq 'done') {
                        $meta['agent_state'] = 'idle'
                        $meta['agent_message'] = ''
                        $meta['state_ts'] = $nowAck
                    }
                    $meta['attn_ts'] = 0L
                    Save-SessionState $meta
                }
            }
            exit 0
        }
        '--open-pr' {
            $sessArg = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            Invoke-OpenSessionPr -SessArg $sessArg
        }
        { $_ -in @('refresh', '-r', '--refresh') } {
            $action = 'refresh'
            if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) {
                $targetDirArg = [string]$args[++$i]
            }
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

if ($action -eq 'refresh') {
    Invoke-IdeRefresh -TargetArg $targetDirArg -IsDryRun $dryRun
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
    $env:WINDOWS_SETTINGS_THEME = Get-ActiveThemeSlug
    $env:IDE_SESSION = $sessionName
    $env:IDE_INITIAL_ROOT = $resolvedRoot
    $env:IDE_WORKDIR = $resolvedRoot
    $env:NVIM_IDE_SOCKET = $pipePath
    $env:IDE_AI_CLI = $aiInfo.Name

    $existingMeta = Read-SessionState $sessionName
    $nowInitTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
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
        state_ts      = if ($existingMeta -and $existingMeta['state_ts']) { [long]$existingMeta['state_ts'] } else { $nowInitTs }
        attn_ts       = if ($existingMeta -and $existingMeta['attn_ts']) { [long]$existingMeta['attn_ts'] } else { 0L }
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
