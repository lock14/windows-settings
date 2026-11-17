# ==============================================================================
# Attention.ps1 - OSC 7501 status emission, Antigravity hooks & agent lifecycle
# ==============================================================================

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

function Write-Osc7501CacheSet([string]$StateDir = '') {
    $targetDir = if ($StateDir) { $StateDir } else { Get-IdeStateDir }
    if (-not (Test-Path -LiteralPath $targetDir -PathType Container)) {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
    }
    $esc = [char]27
    $oscPayloads = @{
        'osc-agy-idle.bin'    = "${esc}]7501;state=idle:app=agy${esc}\"
        'osc-agy-working.bin' = "${esc}]7501;state=working:app=agy${esc}\"
        'osc-agy-done.bin'    = "${esc}]7501;state=done:app=agy${esc}\"
        'osc-agy-clear.bin'   = "${esc}]7501;state=clear:app=agy${esc}\"
        'osc-agy-error.bin'   = "${esc}]7501;state=error:app=agy${esc}\"
    }
    foreach ($kv in $oscPayloads.GetEnumerator()) {
        $oscPath = Join-Path $targetDir $kv.Key
        [System.IO.File]::WriteAllBytes($oscPath, [System.Text.Encoding]::ASCII.GetBytes($kv.Value))
    }
}

function Invoke-AgyHook([string]$HookEventArg) {
    $stdinRaw = Read-NonBlockingStdin -EnvOverrideName 'WS_HOOK_STDIN'
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
        }
        'PreInvocation' {
            $mappedState = 'running'
            $oscSpec = 'state=working:app=agy'
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

function Format-SanitizedAgentMessage([string]$RawMessage) {
    if (-not $RawMessage) { return '' }
    $esc = [char]27
    $bel = [char]7
    $clean = [regex]::Replace($RawMessage, "${esc}\][^\x07\x1b]*(?:${bel}|${esc}\\)", '')
    $clean = [regex]::Replace($clean, "${esc}\[[0-9;?]*[ -/]*[@-~]", '')
    $clean = [regex]::Replace($clean, '[\x00-\x1F\x7F]+', ' ')
    $clean = [regex]::Replace($clean, '\s+', ' ').Trim()
    if ($clean.Length -gt 160) {
        $clean = $clean.Substring(0, 159) + "`u{2026}"
    }
    return $clean
}

function Invoke-AgentState([string[]]$StateArgs, [string]$PipedInput = '') {
    $stdinRaw = Read-NonBlockingStdin -EnvOverrideName 'WS_AGENT_STATE_STDIN' -FallbackText $PipedInput

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

function Invoke-AckAiAttention([string[]]$TargetArgs) {
    $ackTargets = if ($TargetArgs -and $TargetArgs.Count -gt 0) {
        $TargetArgs
    } else {
        @(Resolve-TargetSession '')
    }
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
