<#
.SYNOPSIS
    Cross-Platform Hybrid Terminal IDE and Agent Session Manager (Zellij 0.46+, Neovim RPC, and AI).
.DESCRIPTION
    Windows and cross-platform counterpart to home-settings powered by Zellij 0.46+ (with Windows
    Terminal wt.exe fallback). Provides persistent multi-repo AI agent sessions, native OSC 7501
    Attention Inbox and live session previews, opt-in standalone 1-hop GPU desktop windows, direct
    .NET Named Pipe MsgPack-RPC to Neovim, sanitized bracketed-paste prompt dispatch, synchronized
    directory diving, and unsaved-buffer protected workspace exit.

    Internal domain logic is modularized under libexec\ide\*.ps1 and dot-sourced on demand:
      - Core.ps1      : Paths, session state, binary resolution, Zellij pipes, and 4-tier palette
      - Hooks.ps1     : User workspace, link, notification, and VCS hooks (links.ps1)
      - Launcher.ps1  : Interactive workspace creator (new), directory picker (dir), and agent switcher
      - Rpc.ps1       : Direct .NET Named Pipe MsgPack-RPC, file opener, cd, and AI prompt send
      - Attention.ps1 : OSC 7501 status writer and cache, agy-hook, state, and ack
      - Fleet.ps1     : Fast Git and PR metadata, urgency-ranked fleet table, preview, and switcher
      - Modals.ps1    : Floating modal coordinator, 2-tier keybinding cheatsheet, and system monitor
      - Workspace.ps1 : Supervised pane init, role routing, workspace launch, refresh, and teardown
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libIdeDir = Join-Path (Join-Path (Split-Path -Parent $ScriptDir) 'libexec') 'ide'

$script:UsageText = @"
Usage:
  ide [OPTIONS] [DIR | SESSION]
  ide <COMMAND> [ARGS...]

Launch or attach to an IDE workspace session, or manage the active AI agent fleet.

Launch Options:
  --2pane                  Use 2-pane side-by-side layout (AI Agent left, Editor right)
  --agent <CLI>            Select AI CLI agent: agy (default), claude, or codex
  -d, --detach             Start workspace session detached in the background
  --desktop                Open in a standalone Zellij 1-hop GPU desktop window
  --new-window             Open workspace in a new Windows Terminal window
  --backend <zellij|wt>    Select multiplexer backend: zellij (default) or wt
  --dry-run, -DryRun       Preview workspace metadata and launch command without mutating state
  -h, --help [COMMAND]     Show general help or detailed help for a subcommand

Commands:
  list      List IDE sessions in urgency order (table, --plain, or 19-key --json)
  switch    Open the interactive IDE Fleet Switcher or switch to SESSION (alias: -s)
  new       Create a new workspace directory and launch IDE (alias: -n)
  dir       Pick a project directory with zoxide and fzf to launch IDE (alias: -o, open-dir)
  agent     Switch or restart the AI CLI agent in a session without closing Editor or Shell
  next      Jump to the oldest IDE session awaiting AI attention
  cd        Change the active working directory across Editor, Shell, and session state
  refresh   Re-apply active theme, reload top bar, refresh Editor buffers, and heal CWDs
  quit      Safely close one or more IDE sessions after checking unsaved Neovim buffers
  open      Open a file (and optional line number) in the session Editor via Named Pipe RPC
  send      Paste text, stdin, or a file reference into the session AI Agent prompt
  state     Record AI agent lifecycle state and emit OSC 7501 notification sequences
  ack       Acknowledge unseen AI attention badges for one or more sessions
  pr        Open the pull request or merge request URL for a session in the browser
  keys      Display the responsive 2-tier IDE keybinding cheatsheet
  monitor   Open the system resource monitor

Environment Variables:
  IDE_AI_CLI               Default AI CLI tool: agy, claude, or codex
  IDE_WORKSPACE_PARENT     Parent directory for new workspaces (default: user home directory)
  IDE_WORKSPACE_DIRS       Semicolon-separated list of workspace root directories
  IDE_LINK_RULES           Optional path to custom PowerShell workspace hooks script (links.ps1)
  IDE_DESKTOP              Set to 1 to launch standalone Zellij GPU desktop windows by default
  IDE_BACKEND              Multiplexer backend override: zellij or wt
"@

$script:SubcommandUsage = @{
    'list' = @"
Usage: ide list [--plain | --json]

List active and saved IDE workspace sessions ordered by attention urgency.

Options:
  --plain      Print one session name per line without headers or styling
  --json       Print a 19-key JSON array of fleet session records (prints [] when empty)
  -h, --help   Show help for 'ide list'
"@
    'switch' = @"
Usage: ide switch [--2pane] [--agent <CLI>] [-d | --detach] [SESSION]
Alias: ide -s

Open the interactive IDE Fleet Switcher with live AI pane previews, or attach to SESSION.
When no sessions exist on an interactive terminal, opens the directory picker automatically.

Options:
  --2pane          Use 2-pane side-by-side layout when creating or reviving a session
  --agent <CLI>    Select or switch AI CLI agent (agy, claude, or codex)
  -d, --detach     Ensure target session runs detached in the background
  -h, --help       Show help for 'ide switch'
"@
    'new' = @"
Usage: ide new [--2pane] [--agent <CLI>] [-d | --detach] [--dry-run] [NAME]
Alias: ide -n

Create a new workspace directory (via New-IdeWorkspace hook or under IDE_WORKSPACE_PARENT)
and launch or switch to its IDE session. Opens an interactive card when NAME is omitted.

Options:
  --2pane             Launch with 2-pane side-by-side layout
  --agent <CLI>       Select AI CLI agent (agy, claude, or codex)
  -d, --detach        Create and start session detached in the background
  --dry-run, -DryRun  Preview target directory and launch command without mutating state
  -h, --help          Show help for 'ide new'
"@
    'dir' = @"
Usage: ide dir [--2pane] [--agent <CLI>] [-d | --detach] [QUERY]
Aliases: ide -o, ide open-dir

Pick an existing project directory from zoxide history, configured workspace roots, and
home subdirectories using fzf with live VCS status and directory previews.

Options:
  --2pane          Launch selected directory with 2-pane side-by-side layout
  --agent <CLI>    Select AI CLI agent (agy, claude, or codex)
  -d, --detach     Start selected workspace detached in the background
  -h, --help       Show help for 'ide dir'
"@
    'agent' = @"
Usage: ide agent [<CLI> | restart] [SESSION]

Switch or restart the AI CLI agent inside SESSION in-place while keeping Editor and Shell
panes untouched. Opens a compact interactive selector card when CLI is omitted.

Arguments:
  <CLI> | restart  Target agent executable (agy, claude, codex) or 'restart'
  SESSION          Target IDE session name (defaults to current session)
"@
    'next' = @"
Usage: ide next [SESSION]

Jump directly to the oldest live IDE session waiting for AI approval or turn review.

Arguments:
  SESSION          Optional origin session name
"@
    'cd' = @"
Usage: ide cd [DIR | --reset | -] [SESSION]

Update the active workspace directory across session state, Neovim Editor, top bar, and
an idle Shell pane.

Arguments:
  DIR              Target directory path, '--reset' for initial root, or '-' for previous directory
  SESSION          Target IDE session name (defaults to current session)
"@
    'refresh' = @"
Usage: ide refresh [--dry-run] [SESSION]

Re-apply the active color theme, rebuild the cached keybinding cheatsheet, reload the
Zellij top bar plugin, refresh Neovim buffers and images, and heal drifted Editor CWDs.

Options:
  --dry-run, -DryRun  Preview refresh actions without mutating files or live sessions
  -h, --help          Show help for 'ide refresh'
"@
    'quit' = @"
Usage: ide quit [-f | --force] [SESSION...]

Safely close one or more IDE workspace sessions after verifying zero unsaved Neovim buffers
over Named Pipe RPC.

Options:
  -f, --force  Close immediately and discard unsaved Neovim buffer changes
  -h, --help   Show help for 'ide quit'
"@
    'open' = @"
Usage: ide open [-p | --preview] <FILE>[:LINE] [+LINE] [SESSION]

Open a file (and optional 1-based line number) in the session Editor pane via Named Pipe RPC,
relaunching Neovim automatically if the Editor pane is sitting at an idle shell.

Options:
  -p, --preview  Open file in Editor without moving pane focus away from caller
  -h, --help     Show help for 'ide open'
"@
    'send' = @"
Usage: ide send [--stdin | --ref <PATH>[:L1[-L2]] | --text <TEXT>] [--no-focus | --switch] [SESSION]

Sanitize and dispatch text or file references into the target session AI Agent pane via
bracketed paste without mutating the system clipboard.

Options:
  --stdin        Read prompt payload from standard input
  --ref <SPEC>   Format relative '@path#L1-L2 ' reference token for the AI prompt
  --text <TEXT>  Send literal text string
  --no-focus     Keep current pane focused when sending within the same session
  --switch       Switch client focus to the target session after pasting
  -h, --help     Show help for 'ide send'
"@
    'state' = @"
Usage: ide state <STATE> [-m | --message <TEXT>] [SESSION]

Update AI agent lifecycle state (running, approval, quota, done, or idle), emit OSC 7501
terminal attention sequences, and dispatch optional user notifications.

Options:
  -m, --message <TEXT>  Attach concise context note for approval, quota, or done states
  -h, --help            Show help for 'ide state'
"@
    'ack' = @"
Usage: ide ack [SESSION...]

Clear unseen AI attention badges and reset completed ('done') sessions back to 'idle'.

Arguments:
  SESSION...   One or more session names (defaults to current session)
"@
    'pr' = @"
Usage: ide pr [SESSION]

Open the cached or live pull request or merge request web URL for SESSION in the browser.

Arguments:
  SESSION      Target IDE session name (defaults to current session or working directory)
"@
    'keys' = @"
Usage: ide keys

Display the responsive TrueColor IDE keybinding cheatsheet (spacious 2-column layout on
wide terminals and compact 80x24 layout on small viewports).
"@
    'monitor' = @"
Usage: ide monitor

Open the interactive system resource monitor (prefers btop4win or btop when installed,
falling back to the built-in TrueColor process and memory monitor).
"@
}

function ConvertTo-CanonicalSubcommand([string]$Token) {
    if (-not $Token) { return '' }
    return $(switch ($Token) {
        '-s'       { 'switch' }
        '-n'       { 'new' }
        '-o'       { 'dir' }
        'open-dir' { 'dir' }
        default    { $Token }
    })
}

function Show-IdeHelpAndExit([string]$Topic = '') {
    if ($Topic) {
        $canon = ConvertTo-CanonicalSubcommand $Topic.Trim().ToLowerInvariant()
        if ($script:SubcommandUsage.ContainsKey($canon)) {
            Write-Output $script:SubcommandUsage[$canon]
            exit 0
        }
        [Console]::Error.WriteLine("Error: Unknown subcommand '$Topic'. Run 'ide --help' for usage.")
        exit 1
    }
    Write-Output $script:UsageText
    exit 0
}

function Test-HasHelpFlag([string[]]$ArgSlice) {
    foreach ($item in $ArgSlice) {
        if ($item -eq '--') { break }
        if ($item -in @('-h', '--help', '-?')) { return $true }
    }
    return $false
}

function ConvertFrom-PipelineInput([bool]$ExpectingInput, [object]$InputVar) {
    if (-not $ExpectingInput -or $null -eq $InputVar) { return '' }
    $arr = @($InputVar)
    if ($arr.Count -eq 0) { return '' }
    return ($arr -join "`n")
}

$publicCommands = @(
    'list', 'switch', '-s', 'new', '-n', 'dir', '-o', 'open-dir',
    'agent', 'next', 'cd', 'refresh', 'quit', 'open', 'send',
    'state', 'ack', 'pr', 'keys', 'monitor'
)

$rawArgs = @($args | ForEach-Object { [string]$_ })

if ($rawArgs.Count -ge 1 -and $rawArgs[0] -in @('-h', '--help', '-?')) {
    $helpTopic = if ($rawArgs.Count -ge 2 -and -not $rawArgs[1].StartsWith('-')) { $rawArgs[1] } else { '' }
    Show-IdeHelpAndExit $helpTopic
}

# Handle private `_internal` namespace immediately
if ($rawArgs.Count -ge 1 -and $rawArgs[0] -eq '_internal') {
    if ($rawArgs.Count -lt 2) {
        [Console]::Error.WriteLine("Error: 'ide _internal' requires an operation name.")
        exit 1
    }
    $op = $rawArgs[1]
    [string[]]$opArgs = @(if ($rawArgs.Count -gt 2) { $rawArgs[2..($rawArgs.Count - 1)] })

    . (Join-Path $libIdeDir 'Core.ps1')

    switch ($op) {
        'pane-init' {
            $roleArg = if ($opArgs.Count -ge 1) { $opArgs[0] } else { 'ai' }
            . (Join-Path $libIdeDir 'Workspace.ps1')
            Invoke-PaneInit -Role $roleArg
        }
        'write-keys-cache' {
            . (Join-Path $libIdeDir 'Attention.ps1')
            . (Join-Path $libIdeDir 'Modals.ps1')
            Write-IdeKeysCheatsheetCache
            exit 0
        }
        'toggle-modal' {
            if ($opArgs.Count -lt 1) {
                [Console]::Error.WriteLine("Error: 'ide _internal toggle-modal' requires a modal name.")
                exit 1
            }
            $mName = $opArgs[0].ToLowerInvariant()
            if ($mName -in @('sessions', 'new', 'dir', 'agent')) {
                . (Join-Path $libIdeDir 'Fleet.ps1')
                . (Join-Path $libIdeDir 'Launcher.ps1')
            }
            . (Join-Path $libIdeDir 'Modals.ps1')
            Invoke-ToggleZellijModal -ModalName $mName
        }
        'sessions-lines' {
            . (Join-Path $libIdeDir 'Fleet.ps1')
            foreach ($r in (Format-FzfSessionRowList)) {
                Write-Output $r
            }
            exit 0
        }
        'session-preview' {
            $followFlag = $false
            $maxFrames = 0
            $sessTarget = ''
            for ($k = 0; $k -lt $opArgs.Count; $k++) {
                $oa = $opArgs[$k]
                if ($oa -eq '--follow') {
                    $followFlag = $true
                } elseif ($oa -eq '--max-frames' -and $k + 1 -lt $opArgs.Count) {
                    [void][int]::TryParse($opArgs[++$k], [ref]$maxFrames)
                } elseif (-not $sessTarget) {
                    $sessTarget = $oa
                }
            }
            . (Join-Path $libIdeDir 'Fleet.ps1')
            Show-IdeSessionPreview -TargetArg $sessTarget -Follow $followFlag -MaxFrames $maxFrames
            exit 0
        }
        'dir-preview' {
            $curSess = ''
            $dirTarget = ''
            $afterSep = $false
            for ($k = 0; $k -lt $opArgs.Count; $k++) {
                $oa = $opArgs[$k]
                if (-not $afterSep -and $oa -eq '--') {
                    $afterSep = $true
                    continue
                }
                if (-not $afterSep -and $oa -eq '--session' -and $k + 1 -lt $opArgs.Count) {
                    $curSess = $opArgs[++$k]
                    continue
                }
                if (-not $dirTarget) {
                    $dirTarget = $oa
                } elseif (-not $curSess) {
                    $curSess = $oa
                }
            }
            . (Join-Path $libIdeDir 'Hooks.ps1')
            . (Join-Path $libIdeDir 'Fleet.ps1')
            . (Join-Path $libIdeDir 'Launcher.ps1')
            Show-IdeDirPreview -RawDir $dirTarget -CurrentSession $curSess
            exit 0
        }
        'open-or-edit' {
            . (Join-Path $libIdeDir 'Rpc.ps1')
            $parsedBatch = ConvertFrom-EditorCliArgList -RawArgs $opArgs
            if ($parsedBatch.CanRouteRpc) {
                if (Send-IdeEditorBatch -FileTargets $parsedBatch.FileTargets -GlobalLine $parsedBatch.GlobalLine -ExCmds $parsedBatch.ExCmds -FocusEditor $true -BaseCwd $parsedBatch.BaseCwd) {
                    exit 0
                }
                if ($parsedBatch.FileTargets.Count -eq 1 -and $parsedBatch.ExCmds.Count -eq 0) {
                    $ft = $parsedBatch.FileTargets[0]
                    $lineStr = if ([int]$ft.line -gt 0) { "$([int]$ft.line)" } elseif ($parsedBatch.GlobalLine -gt 0) { "$($parsedBatch.GlobalLine)" } else { '' }
                    Invoke-IdeOpen -RawFile ([string]$ft.path) -ExplicitLine $lineStr -FallbackLocalEdit $true -FocusEditor $true
                }
            }
            $nvimBin = Resolve-NvimExecutable
            if (-not $nvimBin) {
                [Console]::Error.WriteLine('Error: nvim is not installed.')
                exit 1
            }
            & $nvimBin @opArgs
            exit $LASTEXITCODE
        }
        'open-link' {
            . (Join-Path $libIdeDir 'Hooks.ps1')
            . (Join-Path $libIdeDir 'Rpc.ps1')
            Invoke-IdeOpenLink -LinkArgs $opArgs
            exit 0
        }
        'agy-hook' {
            $evName = if ($opArgs.Count -ge 1) { $opArgs[0] } else { '' }
            . (Join-Path $libIdeDir 'Attention.ps1')
            Invoke-AgyHook -HookEventArg $evName
        }
        'toggle' {
            $optSess = if ($opArgs.Count -ge 1) { $opArgs[0] } else { '' }
            . (Join-Path $libIdeDir 'Workspace.ps1')
            Invoke-ToggleMainPane -SessionArg $optSess
        }
        'focus' {
            if ($opArgs.Count -lt 1) {
                [Console]::Error.WriteLine("Error: 'ide _internal focus' requires a role (ai, editor, or term).")
                exit 1
            }
            $optSess = if ($opArgs.Count -ge 2) { $opArgs[1] } else { '' }
            . (Join-Path $libIdeDir 'Workspace.ps1')
            Invoke-FocusRole -Role $opArgs[0] -SessionArg $optSess
        }
        'park' {
            if ($opArgs.Count -lt 1) {
                [Console]::Error.WriteLine("Error: 'ide _internal park' requires a role (ai, editor, or term).")
                exit 1
            }
            $optSess = if ($opArgs.Count -ge 2) { $opArgs[1] } else { '' }
            . (Join-Path $libIdeDir 'Workspace.ps1')
            Invoke-ToggleRole -Role $opArgs[0] -SessionArg $optSess
        }
        'swap' {
            if ($opArgs.Count -lt 1) {
                [Console]::Error.WriteLine("Error: 'ide _internal swap' requires a direction (left, down, up, or right).")
                exit 1
            }
            $optSess = if ($opArgs.Count -ge 2) { $opArgs[1] } else { '' }
            . (Join-Path $libIdeDir 'Workspace.ps1')
            Invoke-SwapPane -Direction $opArgs[0] -SessionArg $optSess
        }
        default {
            [Console]::Error.WriteLine("Error: Unknown internal operation '$op'.")
            exit 1
        }
    }
    exit 0
}

# Parse leading launch options until a subcommand or positional target is encountered
$layout = '3pane'
$layoutExplicit = $false
$newWindow = $false
$detachFlag = $false
$desktopFlag = ($env:IDE_DESKTOP -eq '1')
$dryRun = $false
$requestedBackend = if ($env:IDE_BACKEND -and $env:IDE_BACKEND.Trim()) { $env:IDE_BACKEND.Trim().ToLowerInvariant() } else { '' }
$requestedAi = if ($env:IDE_AI_CLI -and $env:IDE_AI_CLI.Trim()) { $env:IDE_AI_CLI.Trim() } else { 'agy' }
$aiFromFlag = $false

$subCmd = ''
$subArgs = @()
$launchPositional = [System.Collections.Generic.List[string]]::new()
$endOfLaunchFlags = $false

for ($i = 0; $i -lt $rawArgs.Count; $i++) {
    $tok = $rawArgs[$i]
    if (-not $endOfLaunchFlags -and $launchPositional.Count -eq 0 -and $tok -in $publicCommands) {
        $subCmd = ConvertTo-CanonicalSubcommand $tok
        if ($i + 1 -lt $rawArgs.Count) {
            $subArgs = @($rawArgs[($i + 1)..($rawArgs.Count - 1)])
        }
        break
    }
    if (-not $endOfLaunchFlags) {
        switch ($tok) {
            '--' {
                $endOfLaunchFlags = $true
                continue
            }
            { $_ -in @('-h', '--help', '-?') } {
                $nextTopic = if ($i + 1 -lt $rawArgs.Count -and -not $rawArgs[$i + 1].StartsWith('-')) { $rawArgs[$i + 1] } else { '' }
                Show-IdeHelpAndExit $nextTopic
            }
            '--2pane' {
                $layout = '2pane'
                $layoutExplicit = $true
                continue
            }
            '--3pane' {
                $layout = '3pane'
                $layoutExplicit = $true
                continue
            }
            '--agent' {
                if ($i + 1 -ge $rawArgs.Count) {
                    [Console]::Error.WriteLine('Error: --agent requires a CLI name (agy, claude, or codex).')
                    exit 1
                }
                $requestedAi = $rawArgs[++$i]
                $aiFromFlag = $true
                continue
            }
            { $_.StartsWith('--agent=') } {
                $requestedAi = $tok.Substring(8)
                $aiFromFlag = $true
                continue
            }
            { $_ -in @('-d', '--detach') } {
                $detachFlag = $true
                continue
            }
            '--desktop' {
                $desktopFlag = $true
                continue
            }
            '--new-window' {
                $newWindow = $true
                continue
            }
            '--backend' {
                if ($i + 1 -ge $rawArgs.Count) {
                    [Console]::Error.WriteLine('Error: --backend requires zellij or wt.')
                    exit 1
                }
                $requestedBackend = $rawArgs[++$i].Trim().ToLowerInvariant()
                if ($requestedBackend -notin @('zellij', 'wt')) {
                    [Console]::Error.WriteLine("Error: Invalid --backend '$requestedBackend'. Expected zellij or wt.")
                    exit 1
                }
                continue
            }
            { $_.StartsWith('--backend=') } {
                $requestedBackend = $tok.Substring(10).Trim().ToLowerInvariant()
                if ($requestedBackend -notin @('zellij', 'wt')) {
                    [Console]::Error.WriteLine("Error: Invalid --backend '$requestedBackend'. Expected zellij or wt.")
                    exit 1
                }
                continue
            }
            { $_ -in @('--dry-run', '-DryRun') } {
                $dryRun = $true
                continue
            }
            default {
                if ($tok.StartsWith('-') -and $tok -ne '-') {
                    [Console]::Error.WriteLine("Error: Unknown option '$tok'. Run 'ide --help' for usage.")
                    exit 1
                }
                $launchPositional.Add($tok)
            }
        }
    } else {
        $launchPositional.Add($tok)
    }
}

. (Join-Path $libIdeDir 'Core.ps1')

if (-not $subCmd) {
    if ($launchPositional.Count -gt 1) {
        [Console]::Error.WriteLine("Error: Unexpected extra argument '$($launchPositional[1])'. Run 'ide --help' for usage.")
        exit 1
    }
    $targetArg = if ($launchPositional.Count -eq 1) { $launchPositional[0] } else { '' }
    . (Join-Path $libIdeDir 'Hooks.ps1')
    . (Join-Path $libIdeDir 'Workspace.ps1')
    Invoke-LaunchWorkspace `
        -TargetDirArg $targetArg `
        -Layout $layout `
        -RequestedBackend $requestedBackend `
        -RequestedAi $requestedAi `
        -AiFromFlag $aiFromFlag `
        -Detach $detachFlag `
        -Desktop $desktopFlag `
        -NewWindow $newWindow `
        -IsDryRun $dryRun
    exit 0
}

if (Test-HasHelpFlag $subArgs) {
    Show-IdeHelpAndExit $subCmd
}

switch ($subCmd) {
    'list' {
        $plainFlag = $false
        $jsonFlag = $false
        foreach ($sa in $subArgs) {
            switch ($sa) {
                '--plain' { $plainFlag = $true }
                '--json'  { $jsonFlag = $true }
                default {
                    [Console]::Error.WriteLine("Error: Unknown 'ide list' option '$sa'. Run 'ide list --help' for usage.")
                    exit 1
                }
            }
        }
        if ($plainFlag -and $jsonFlag) {
            [Console]::Error.WriteLine("Error: '--plain' and '--json' cannot be combined.")
            exit 1
        }
        . (Join-Path $libIdeDir 'Fleet.ps1')
        Show-IdeSessionList -Plain $plainFlag -Json $jsonFlag
        exit 0
    }
    { $_ -in @('switch', 'new', 'dir') } {
        $pos = [System.Collections.Generic.List[string]]::new()
        $subEnd = $false
        for ($k = 0; $k -lt $subArgs.Count; $k++) {
            $sa = $subArgs[$k]
            if (-not $subEnd -and $sa -eq '--') { $subEnd = $true; continue }
            if (-not $subEnd) {
                switch ($sa) {
                    '--2pane'      { $layout = '2pane'; $layoutExplicit = $true }
                    '--3pane'      { $layout = '3pane'; $layoutExplicit = $true }
                    '--desktop'    { $desktopFlag = $true }
                    '--new-window' { $newWindow = $true }
                    { $_ -in @('-d', '--detach') } { $detachFlag = $true }
                    { $_ -in @('--dry-run', '-DryRun') } {
                        if ($subCmd -eq 'switch') {
                            [Console]::Error.WriteLine("Error: Unknown 'ide switch' option '$sa'.")
                            exit 1
                        }
                        $dryRun = $true
                    }
                    '--agent' {
                        if ($k + 1 -ge $subArgs.Count) {
                            [Console]::Error.WriteLine('Error: --agent requires a CLI name.')
                            exit 1
                        }
                        $requestedAi = $subArgs[++$k]
                        $aiFromFlag = $true
                    }
                    { $_.StartsWith('--agent=') } {
                        $requestedAi = $sa.Substring(8)
                        $aiFromFlag = $true
                    }
                    '--backend' {
                        if ($k + 1 -ge $subArgs.Count) {
                            [Console]::Error.WriteLine('Error: --backend requires zellij or wt.')
                            exit 1
                        }
                        $requestedBackend = $subArgs[++$k].Trim().ToLowerInvariant()
                    }
                    { $_.StartsWith('--backend=') } {
                        $requestedBackend = $sa.Substring(10).Trim().ToLowerInvariant()
                    }
                    default {
                        if ($sa.StartsWith('-')) {
                            [Console]::Error.WriteLine("Error: Unknown 'ide $subCmd' option '$sa'. Run 'ide $subCmd --help' for usage.")
                            exit 1
                        }
                        $pos.Add($sa)
                    }
                }
            } else {
                $pos.Add($sa)
            }
        }
        if ($pos.Count -gt 1) {
            [Console]::Error.WriteLine("Error: Unexpected extra argument '$($pos[1])' for 'ide $subCmd'.")
            exit 1
        }
        $argVal = if ($pos.Count -eq 1) { $pos[0] } else { '' }
        . (Join-Path $libIdeDir 'Hooks.ps1')
        . (Join-Path $libIdeDir 'Fleet.ps1')
        . (Join-Path $libIdeDir 'Workspace.ps1')
        . (Join-Path $libIdeDir 'Launcher.ps1')
        if ($subCmd -eq 'switch') {
            $swLay = if ($layoutExplicit) { $layout } else { '' }
            Invoke-SessionSwitcher `
                -SessionArg $argVal `
                -Layout $swLay `
                -RequestedAi $requestedAi `
                -AiFromFlag $aiFromFlag `
                -Detach $detachFlag `
                -Desktop $desktopFlag `
                -NewWindow $newWindow `
                -RequestedBackend $requestedBackend
        } elseif ($subCmd -eq 'new') {
            Invoke-IdeNew `
                -NameArg $argVal `
                -Layout $layout `
                -RequestedAi $requestedAi `
                -AiFromFlag $aiFromFlag `
                -Detach $detachFlag `
                -Desktop $desktopFlag `
                -NewWindow $newWindow `
                -RequestedBackend $requestedBackend `
                -IsDryRun $dryRun
        } else {
            Invoke-IdeDir `
                -QueryArg $argVal `
                -Layout $layout `
                -RequestedAi $requestedAi `
                -AiFromFlag $aiFromFlag `
                -Detach $detachFlag `
                -Desktop $desktopFlag `
                -NewWindow $newWindow `
                -RequestedBackend $requestedBackend `
                -IsDryRun $dryRun
        }
        exit 0
    }
    'agent' {
        $pos = [System.Collections.Generic.List[string]]::new()
        $subEnd = $false
        foreach ($sa in $subArgs) {
            if (-not $subEnd -and $sa -eq '--') { $subEnd = $true; continue }
            if (-not $subEnd -and $sa.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown 'ide agent' option '$sa'. Run 'ide agent --help' for usage.")
                exit 1
            }
            $pos.Add($sa)
        }
        if ($pos.Count -gt 2) {
            [Console]::Error.WriteLine("Error: Unexpected extra argument '$($pos[2])' for 'ide agent'.")
            exit 1
        }
        $cliVal = if ($pos.Count -ge 1) { $pos[0] } else { '' }
        $sessVal = if ($pos.Count -ge 2) { $pos[1] } else { '' }
        . (Join-Path $libIdeDir 'Launcher.ps1')
        Invoke-IdeAgent -CliArg $cliVal -SessionArg $sessVal
        exit 0
    }
    'next' {
        if ($subArgs.Count -gt 1 -or ($subArgs.Count -eq 1 -and $subArgs[0].StartsWith('-'))) {
            [Console]::Error.WriteLine("Error: Invalid arguments for 'ide next'. Run 'ide next --help' for usage.")
            exit 1
        }
        $sessVal = if ($subArgs.Count -eq 1) { $subArgs[0] } else { '' }
        . (Join-Path $libIdeDir 'Fleet.ps1')
        Invoke-NextAttention -TargetArg $sessVal
        exit 0
    }
    'cd' {
        $dirVal = ''
        $sessVal = ''
        $subEnd = $false
        $pos = [System.Collections.Generic.List[string]]::new()
        foreach ($sa in $subArgs) {
            if (-not $subEnd -and $sa -eq '--') { $subEnd = $true; continue }
            if (-not $subEnd -and $sa -eq '--reset') {
                $pos.Add('--reset')
                continue
            }
            if (-not $subEnd -and $sa.StartsWith('-') -and $sa -ne '-') {
                [Console]::Error.WriteLine("Error: Unknown 'ide cd' option '$sa'. Run 'ide cd --help' for usage.")
                exit 1
            }
            $pos.Add($sa)
        }
        if ($pos.Count -gt 2) {
            [Console]::Error.WriteLine("Error: Unexpected extra argument '$($pos[2])' for 'ide cd'.")
            exit 1
        }
        if ($pos.Count -ge 1) { $dirVal = $pos[0] }
        if ($pos.Count -ge 2) { $sessVal = $pos[1] }
        . (Join-Path $libIdeDir 'Rpc.ps1')
        Invoke-IdeCd -TargetArg $dirVal -SessionArg $sessVal
        exit 0
    }
    'refresh' {
        $sessVal = ''
        foreach ($sa in $subArgs) {
            if ($sa -in @('--dry-run', '-DryRun')) {
                $dryRun = $true
            } elseif ($sa.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown 'ide refresh' option '$sa'. Run 'ide refresh --help' for usage.")
                exit 1
            } elseif (-not $sessVal) {
                $sessVal = $sa
            } else {
                [Console]::Error.WriteLine("Error: Unexpected extra argument '$sa' for 'ide refresh'.")
                exit 1
            }
        }
        . (Join-Path $libIdeDir 'Rpc.ps1')
        . (Join-Path $libIdeDir 'Attention.ps1')
        . (Join-Path $libIdeDir 'Modals.ps1')
        . (Join-Path $libIdeDir 'Workspace.ps1')
        Invoke-IdeRefresh -TargetArg $sessVal -IsDryRun $dryRun
        exit 0
    }
    'quit' {
        $forceQuit = $false
        $targets = [System.Collections.Generic.List[string]]::new()
        $subEnd = $false
        foreach ($sa in $subArgs) {
            if (-not $subEnd -and $sa -eq '--') { $subEnd = $true; continue }
            if (-not $subEnd -and $sa -in @('-f', '--force')) {
                $forceQuit = $true
                continue
            }
            if (-not $subEnd -and $sa.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown 'ide quit' option '$sa'. Run 'ide quit --help' for usage.")
                exit 1
            }
            $targets.Add($sa)
        }
        . (Join-Path $libIdeDir 'Rpc.ps1')
        . (Join-Path $libIdeDir 'Workspace.ps1')
        Close-IdeSessionList -TargetArgs $targets.ToArray() -Force $forceQuit
        exit 0
    }
    'open' {
        $previewFlag = $false
        $explicitLine = ''
        $pos = [System.Collections.Generic.List[string]]::new()
        $subEnd = $false
        foreach ($sa in $subArgs) {
            if (-not $subEnd -and $sa -eq '--') { $subEnd = $true; continue }
            if (-not $subEnd -and $sa -in @('-p', '--preview')) {
                $previewFlag = $true
                continue
            }
            if (-not $subEnd -and $sa -match '^\+([0-9]+)$') {
                $explicitLine = $Matches[1]
                continue
            }
            if (-not $subEnd -and $sa.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown 'ide open' option '$sa'. Run 'ide open --help' for usage.")
                exit 1
            }
            $pos.Add($sa)
        }
        if ($pos.Count -eq 0) {
            [Console]::Error.WriteLine("Error: 'ide open' requires a file path. Run 'ide open --help' for usage.")
            exit 1
        }
        if (-not $explicitLine -and $pos.Count -ge 2 -and $pos[1] -match '^[0-9]+$') {
            $explicitLine = $pos[1]
            $pos.RemoveAt(1)
        }
        if ($pos.Count -gt 2) {
            [Console]::Error.WriteLine("Error: Unexpected extra argument '$($pos[2])' for 'ide open'.")
            exit 1
        }
        $fileVal = $pos[0]
        $sessVal = if ($pos.Count -eq 2) { $pos[1] } else { '' }
        . (Join-Path $libIdeDir 'Rpc.ps1')
        Invoke-IdeOpen -RawFile $fileVal -ExplicitLine $explicitLine -FallbackLocalEdit $false -FocusEditor (-not $previewFlag) -SessionArg $sessVal
        exit 0
    }
    'send' {
        $inEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
        $pipedText = ConvertFrom-PipelineInput -ExpectingInput $MyInvocation.ExpectingInput -InputVar $inEnum
        . (Join-Path $libIdeDir 'Rpc.ps1')
        Invoke-IdeSend -SendArgs $subArgs -PipedInput $pipedText
        exit 0
    }
    'state' {
        $stateEnum = Get-Variable -Name 'input' -Scope Local -ValueOnly -ErrorAction SilentlyContinue
        $pipedStateText = ConvertFrom-PipelineInput -ExpectingInput $MyInvocation.ExpectingInput -InputVar $stateEnum
        . (Join-Path $libIdeDir 'Attention.ps1')
        Invoke-AgentState -StateArgs $subArgs -PipedInput $pipedStateText
        exit 0
    }
    'ack' {
        foreach ($sa in $subArgs) {
            if ($sa.StartsWith('-')) {
                [Console]::Error.WriteLine("Error: Unknown 'ide ack' option '$sa'. Run 'ide ack --help' for usage.")
                exit 1
            }
        }
        . (Join-Path $libIdeDir 'Attention.ps1')
        Invoke-AckAiAttention -TargetArgs $subArgs
        exit 0
    }
    'pr' {
        if ($subArgs.Count -gt 1 -or ($subArgs.Count -eq 1 -and $subArgs[0].StartsWith('-'))) {
            [Console]::Error.WriteLine("Error: Invalid arguments for 'ide pr'. Run 'ide pr --help' for usage.")
            exit 1
        }
        $sessVal = if ($subArgs.Count -eq 1) { $subArgs[0] } else { '' }
        . (Join-Path $libIdeDir 'Fleet.ps1')
        Invoke-OpenSessionPr -SessArg $sessVal
        exit 0
    }
    'keys' {
        if ($subArgs.Count -gt 0) {
            [Console]::Error.WriteLine("Error: Unknown 'ide keys' argument '$($subArgs[0])'. Run 'ide keys --help' for usage.")
            exit 1
        }
        . (Join-Path $libIdeDir 'Modals.ps1')
        Show-IdeKeysCheatsheet
        exit 0
    }
    'monitor' {
        if ($subArgs.Count -gt 0) {
            [Console]::Error.WriteLine("Error: Unknown 'ide monitor' argument '$($subArgs[0])'. Run 'ide monitor --help' for usage.")
            exit 1
        }
        . (Join-Path $libIdeDir 'Modals.ps1')
        Invoke-SystemMonitor
        exit 0
    }
}
