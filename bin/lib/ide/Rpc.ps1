# ==============================================================================
# Rpc.ps1 - Neovim Named Pipe RPC, multi-file opener, workspace cd & AI send
# ==============================================================================

function Invoke-NvimRemoteExpr([string]$PipePath, [string]$Expr, [int]$TimeoutMs = 2500, [string]$NvimExecutable = '') {
    $nvimBin = if ($NvimExecutable) { $NvimExecutable } else { Resolve-NvimExecutable }
    if (-not $nvimBin -or -not (Test-IdePipeLive $PipePath)) {
        return @{ Success = $false; Output = '' }
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($nvimBin)
        foreach ($argItem in @('--headless', '--server', $PipePath, '--remote-expr', $Expr)) {
            $psi.ArgumentList.Add($argItem)
        }
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

function Split-FileAndLineSpec([string]$RawFile, [string]$ExplicitLine = '') {
    $filePart = $RawFile
    $lineNum = 0
    if ($ExplicitLine -and $ExplicitLine -match '^[0-9]+$') {
        $lineNum = [int]$ExplicitLine
    } elseif ($RawFile -match '^([A-Za-z]:[^:]+|[^:]+):([0-9]+)(?::[0-9]+)?$' -and $RawFile -notmatch '^[A-Za-z]:[\\/]?$') {
        $candPath = $Matches[1]
        if (-not (Test-Path -LiteralPath $RawFile) -and ((Test-Path -LiteralPath $candPath) -or -not [System.IO.Path]::IsPathRooted($RawFile))) {
            $filePart = $candPath
            $lineNum = [int]$Matches[2]
        }
    }
    return @{
        File = $filePart
        Line = $lineNum
    }
}

function ConvertFrom-EditorCliArgList([object[]]$RawArgs, [string]$BaseCwd = '') {
    $cwdPath = if ($BaseCwd) { $BaseCwd } else { (Get-Location).ProviderPath }
    $afterDoubleDash = $false
    $canRouteRpc = $true
    $globalLine = 0
    $exCmds = [System.Collections.Generic.List[string]]::new()
    $fileTargets = [System.Collections.Generic.List[hashtable]]::new()

    for ($i = 0; $i -lt $RawArgs.Count; $i++) {
        $s = "$($RawArgs[$i])"
        if (-not $afterDoubleDash) {
            if ($s -eq '--') {
                $afterDoubleDash = $true
                continue
            }
            if ($s -eq '-c') {
                if ($i + 1 -ge $RawArgs.Count) {
                    $canRouteRpc = $false
                    break
                }
                $exCmds.Add("$($RawArgs[++$i])")
                continue
            }
            if ($s -match '^\+([0-9]+)$') {
                $globalLine = [int]$Matches[1]
                continue
            }
            if ($s -eq '+') {
                $exCmds.Add('$')
                continue
            }
            if ($s.StartsWith('+')) {
                $exCmds.Add($s.Substring(1))
                continue
            }
            if ($s.StartsWith('-')) {
                $canRouteRpc = $false
                break
            }
        }

        $parsed = Split-FileAndLineSpec -RawFile $s
        $fPath = $parsed.File
        if (-not [System.IO.Path]::IsPathRooted($fPath)) {
            $fPath = [System.IO.Path]::GetFullPath((Join-Path $cwdPath $fPath))
        }
        $fileTargets.Add(@{ path = $fPath; line = [int]$parsed.Line })
    }

    return @{
        CanRouteRpc = ($canRouteRpc -and $fileTargets.Count -ge 1)
        GlobalLine  = $globalLine
        ExCmds      = @($exCmds)
        FileTargets = @($fileTargets)
        BaseCwd     = $cwdPath
    }
}

function Send-IdeEditorBatch(
    [hashtable[]]$FileTargets,
    [int]$GlobalLine = 0,
    [string[]]$ExCmds = @(),
    [bool]$FocusEditor = $true,
    [string]$BaseCwd = '',
    [string]$NvimExecutable = ''
) {
    if (-not $FileTargets -or $FileTargets.Count -eq 0) { return $false }
    $sess = Resolve-TargetSession ''
    $meta = Read-SessionState $sess

    $pipePath = ''
    if ($env:NVIM_IDE_SOCKET -and (Test-IdePipeLive $env:NVIM_IDE_SOCKET.Trim())) {
        $pipePath = $env:NVIM_IDE_SOCKET.Trim()
    } else {
        $candPipe = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        if (Test-IdePipeLive $candPipe) {
            $pipePath = $candPipe
        }
    }
    if (-not $pipePath) { return $false }

    $cwdFallback = if ($BaseCwd) { $BaseCwd } else { (Get-Location).ProviderPath }
    $healDir = if ($env:IDE_WORKDIR -and [System.IO.Directory]::Exists($env:IDE_WORKDIR)) {
        $env:IDE_WORKDIR
    } elseif ($meta -and $meta['workdir'] -and [System.IO.Directory]::Exists([string]$meta['workdir'])) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root'] -and [System.IO.Directory]::Exists([string]$meta['root'])) {
        [string]$meta['root']
    } else {
        $cwdFallback
    }
    $syncCwd = [bool](($meta -and $meta['workdir']) -or $env:IDE_WORKDIR)

    $rpcPayload = @{
        workdir  = $healDir
        sync_cwd = $syncCwd
        files    = @($FileTargets)
        line     = $GlobalLine
        cmds     = @($ExCmds)
    } | ConvertTo-Json -Compress -Depth 4
    $vimJson = $rpcPayload.Replace("'", "''")
    $luaChunk = '(function(raw) vim.schedule(function() local ok, p = pcall(vim.json.decode, raw); if not ok or type(p) ~= "table" then return end; pcall(function() require("mini.files").close() end); local uv = vim.uv or vim.loop; if type(p.workdir) == "string" and p.workdir ~= "" and uv.fs_stat(p.workdir) then if uv.fs_stat(vim.fn.getcwd()) == nil or p.sync_cwd then pcall(vim.fn.chdir, p.workdir) end end; local gl = tonumber(p.line) or 0; for _, it in ipairs(p.files or {}) do if type(it.path) == "string" and it.path ~= "" then vim.cmd("silent! keepjumps edit " .. vim.fn.fnameescape(it.path)); local fl = tonumber(it.line) or 0; if fl > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { fl, 0 }) end end end; if gl > 0 then pcall(vim.api.nvim_win_set_cursor, 0, { gl, 0 }) end; for _, ex in ipairs(p.cmds or {}) do if type(ex) == "string" and ex ~= "" then pcall(vim.cmd, ex) end end; if gl > 0 or #(p.cmds or {}) > 0 then pcall(vim.cmd, "silent! normal! zz") end end); return "OK" end)(_A)'
    $rpcExpr = "luaeval('$($luaChunk.Replace("'", "''"))', '$vimJson')"

    $res = Invoke-NvimRemoteExpr -PipePath $pipePath -Expr $rpcExpr -NvimExecutable $NvimExecutable
    if (-not $res.Success -or $res.Output -notmatch 'OK') {
        return $false
    }
    if ($FocusEditor -and $env:ZELLIJ) {
        [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
    }
    return $true
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

    $batchTargets = @(@{ path = $targetPath; line = $lineNum })
    if (Send-IdeEditorBatch -FileTargets $batchTargets -GlobalLine $lineNum -FocusEditor $FocusEditor) {
        exit 0
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

    $resolved = if (-not $TargetArg -or $TargetArg -eq '--reset' -or $TargetArg -eq '~') {
        $initRoot
    } elseif ([System.IO.Path]::IsPathRooted($TargetArg)) {
        $TargetArg
    } else {
        [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $TargetArg))
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        [Console]::Error.WriteLine("Error: Directory not found: $resolved")
        exit 1
    }
    $resolved = (Resolve-Path -LiteralPath $resolved).ProviderPath

    if (-not $meta) {
        $meta = Build-IdeSessionRecord `
            -SessionName $sess `
            -Root $initRoot `
            -Workdir $resolved `
            -Backend $(if ($env:ZELLIJ) { 'zellij' } else { 'wt' })
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
    if (-not $payload) { exit 0 }

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
            $inSameSession = Test-IsCurrentZellijSession $sess
            $panesJson = try {
                Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('list-panes', '--all', '--json') -PassThru
            } catch {
                ''
            }

            $aiEntry = $null
            if ($panesJson) {
                try {
                    $allPanes = @($panesJson | ConvertFrom-Json)
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

            [void](Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('paste', '--pane-id', $aiPaneId, '--', $payload))
            if ($inSameSession) {
                if (-not $noFocus) {
                    & $zellijBin action focus-pane-id $aiPaneId *> $null
                }
            } elseif ($switchSession) {
                if ($env:ZELLIJ) {
                    & $zellijBin action switch-session --pane-id $aiPaneId $sess *> $null
                } else {
                    & $zellijBin attach $sess
                }
            }
        }
    }
}
