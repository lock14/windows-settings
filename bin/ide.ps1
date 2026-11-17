<#
.SYNOPSIS
    Cross-Platform Hybrid Terminal IDE & Agent Session Manager (Zellij 0.46+ + Neovim RPC + AI).
.DESCRIPTION
    Windows & cross-platform counterpart to home-settings/bin/ide powered by Zellij 0.46+ (with
    Windows Terminal wt.exe fallback). Provides persistent multi-repo AI agent sessions, native
    OSC 7501 Attention Inbox & live session previews (Alt+s / Alt+Shift+S), opt-in standalone
    1-hop GPU desktop window (--desktop, no background tray daemon), Neovim Named Pipe RPC
    (\\.\pipe\nvim-ide-<session>), direct bracketed-paste context dispatch (--send), synchronized
    directory diving (icd / :IdeCd), and unsaved-buffer protected workspace exit (:Q / qide / quit).

    Internal domain logic is modularized under bin/lib/ide/*.ps1 and dot-sourced on demand:
      - Core.ps1      : Paths, session state/artifacts, tool & Mise shim resolvers, Zellij pipes, palette
      - Rpc.ps1       : Neovim Named Pipe RPC, multi-file opener, synchronized cd, sanitized --send
      - Attention.ps1 : OSC 7501 status writer & cache, --agy-hook, --agent-state, --ack-ai
      - Fleet.ps1     : Zero-fork Git/PR metadata, urgency-ranked fleet table, preview & fzf switcher
      - Modals.ps1    : Floating modal coordinator, TrueColor keybinding cheatsheet & system monitor
      - Workspace.ps1 : Pane init, role focus/toggle/swap, Zellij & wt.exe launch, refresh & teardown
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$IdeLibRoot = Join-Path (Join-Path $ScriptDir 'lib') 'ide'

$script:UsageText = @"
Usage: ide [OPTIONS] [DIRECTORY]

Launch or manage a Zellij + Neovim RPC + AI Agent IDE workspace session.

Options:
  --3pane                  Launch default 3-pane Inverted-T layout (Top-Left AI, Top-Right Editor, Bottom Shell)
  --2pane                  Launch 2-pane side-by-side layout (Left AI, Right Editor)
  -d, --detach             Start or ensure the workspace session runs detached in the background
  --desktop                Open in a standalone Zellij 1-hop GPU desktop window (no system tray or daemon)
  --new-window             Open workspace in a new Windows Terminal window
  --backend <zellij|wt>    Select multiplexer backend: zellij (default) or wt (split-pane fallback)
  --ai, --agent <CLI>      Select AI CLI agent: agy (default), claude, or codex (overrides `$env:IDE_AI_CLI)
  -s, --sessions           Open interactive IDE Fleet Switcher + live pane preview (Alt+s / Space s)
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

function ConvertFrom-PipelineInput([bool]$ExpectingInput, [object]$InputVar) {
    if (-not $ExpectingInput -or $null -eq $InputVar) { return '' }
    $arr = @($InputVar)
    if ($arr.Count -eq 0) { return '' }
    return ($arr -join "`n")
}

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
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
            Show-IdeKeysCheatsheet
            exit 0
        }
        '--write-keys-cache' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Attention.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
            Write-IdeKeysCheatsheetCache
            exit 0
        }
        '--toggle-keys' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
            Invoke-ToggleZellijModal -ModalName 'keys'
        }
        '--toggle-monitor' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
            Invoke-ToggleZellijModal -ModalName 'monitor'
        }
        '--toggle-sessions' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
            Invoke-ToggleZellijModal -ModalName 'sessions'
        }
        { $_ -in @('--monitor', '--top', '--btop', 'top') } {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Modals.ps1')
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
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
            Invoke-SessionSwitcher
        }
        '--session-preview' {
            $pSess = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
            Show-IdeSessionPreview -TargetArg $pSess
            exit 0
        }
        '--sessions-lines' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
            foreach ($r in (Format-FzfSessionRowList)) {
                Write-Output $r
            }
            exit 0
        }
        '--next-attention' {
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
            Invoke-NextAttention
        }
        '--pane-init' {
            $roleArg = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { 'ai' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
            Invoke-PaneInit -Role $roleArg
        }
        '--toggle' {
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
            Invoke-FocusRole -Role 'ai' -SessionArg $optSess
        }
        { $_ -in @('--show-ai', '--show-editor', '--show-term') } {
            $rName = $arg.Substring(7)
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
            Invoke-FocusRole -Role $rName -SessionArg $optSess
        }
        { $_ -in @('--toggle-ai', '--toggle-editor', '--toggle-term') } {
            $rName = $arg.Substring(9)
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
            Invoke-ToggleRole -Role $rName -SessionArg $optSess
        }
        '--swap' {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Error: --swap requires a direction (left, down, up, or right).')
                exit 1
            }
            $swapDir = [string]$args[++$i]
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
            Invoke-SwapPane -Direction $swapDir -SessionArg $optSess
        }
        '--focus-role' {
            $rName = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { 'ai' }
            $optSess = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Workspace.ps1')
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
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Rpc.ps1')
            Invoke-OpenInIde -RawFile $fileArg -ExplicitLine $lineArg -FallbackLocalEdit $fallbackEdit -FocusEditor $focusEd
        }
        { $_ -in @('cd', '--cd') } {
            $cdTarget = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Rpc.ps1')
            Invoke-IdeCd -TargetArg $cdTarget
            exit 0
        }
        '--send' {
            $rem = if ($i + 1 -lt $args.Count) { @($args[($i + 1)..($args.Count - 1)] | ForEach-Object { [string]$_ }) } else { @() }
            $inEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
            $pipedText = ConvertFrom-PipelineInput -ExpectingInput $MyInvocation.ExpectingInput -InputVar $inEnum
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Rpc.ps1')
            Invoke-IdeSend -SendArgs $rem -PipedInput $pipedText
            exit 0
        }
        '--agy-hook' {
            $evName = if ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Attention.ps1')
            Invoke-AgyHook -HookEventArg $evName
        }
        '--agent-state' {
            $remStateArgs = if ($i + 1 -lt $args.Count) { @($args[($i + 1)..($args.Count - 1)] | ForEach-Object { [string]$_ }) } else { @() }
            $stateEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
            $pipedStateText = ConvertFrom-PipelineInput -ExpectingInput $MyInvocation.ExpectingInput -InputVar $stateEnum
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Attention.ps1')
            Invoke-AgentState -StateArgs $remStateArgs -PipedInput $pipedStateText
        }
        '--ack-ai' {
            $ackTargets = @()
            while ($i + 1 -lt $args.Count) { $ackTargets += [string]$args[++$i] }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Attention.ps1')
            Invoke-AckAiAttention -TargetArgs $ackTargets
        }
        '--open-pr' {
            $sessArg = if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) { [string]$args[++$i] } else { '' }
            . (Join-Path $IdeLibRoot 'Core.ps1')
            . (Join-Path $IdeLibRoot 'Fleet.ps1')
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

. (Join-Path $IdeLibRoot 'Core.ps1')

switch ($action) {
    'refresh' {
        . (Join-Path $IdeLibRoot 'Rpc.ps1')
        . (Join-Path $IdeLibRoot 'Attention.ps1')
        . (Join-Path $IdeLibRoot 'Modals.ps1')
        . (Join-Path $IdeLibRoot 'Workspace.ps1')
        Invoke-IdeRefresh -TargetArg $targetDirArg -IsDryRun $dryRun
    }
    'list' {
        . (Join-Path $IdeLibRoot 'Fleet.ps1')
        Show-IdeSessionList -Plain $plainFlag
        exit 0
    }
    'quit' {
        . (Join-Path $IdeLibRoot 'Rpc.ps1')
        . (Join-Path $IdeLibRoot 'Workspace.ps1')
        Close-IdeSessionList -TargetArgs $actionArgs.ToArray() -Force $forceFlag
        exit 0
    }
    'kill' {
        . (Join-Path $IdeLibRoot 'Rpc.ps1')
        . (Join-Path $IdeLibRoot 'Workspace.ps1')
        Close-IdeSessionList -TargetArgs $actionArgs.ToArray() -Force $true
        exit 0
    }
    default {
        . (Join-Path $IdeLibRoot 'Workspace.ps1')
        Invoke-LaunchWorkspace `
            -TargetDirArg $targetDirArg `
            -Layout $layout `
            -RequestedBackend $requestedBackend `
            -RequestedAi $requestedAi `
            -Detach $detachFlag `
            -Desktop $desktopFlag `
            -NewWindow $newWindow `
            -IsDryRun $dryRun
    }
}
