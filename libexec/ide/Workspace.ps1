# ==============================================================================
# Workspace.ps1 - Supervised pane init, role routing, workspace launch, refresh & quit
# ==============================================================================

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

function Invoke-ToggleMainPane([string]$SessionArg = '') {
    if (-not $env:ZELLIJ -and -not $SessionArg) {
        exit 0
    }
    $sess = Resolve-TargetSession $SessionArg
    if (Test-WasmBarDeployed) {
        if (Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload 'focus:ai') {
            exit 0
        }
    }
    $curId = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
    $aiId = Get-RolePaneId -SessionName $sess -Role 'ai'
    if ($curId -and $aiId -and $curId -eq $aiId) {
        [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
    } else {
        [void](Select-IdeRolePane -SessionName $sess -Role 'ai' -EnsureOnly $false)
    }
    exit 0
}

function Invoke-FocusRole([string]$Role, [string]$SessionArg = '') {
    if (-not $env:ZELLIJ -and -not $SessionArg) {
        exit 0
    }
    $sess = Resolve-TargetSession $SessionArg
    [void](Select-IdeRolePane -SessionName $sess -Role $Role -EnsureOnly $false)
    exit 0
}

function Invoke-ToggleRole([string]$Role, [string]$SessionArg = '') {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { exit 0 }
    $roleSpec = ConvertTo-CanonicalIdeRole $Role
    $sess = Resolve-TargetSession $SessionArg
    [void](Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload "toggle:$($roleSpec.Pipe)")
    exit 0
}

function Invoke-SwapPane([string]$Direction, [string]$SessionArg = '') {
    $dir = if ($Direction) { $Direction.Trim().ToLowerInvariant() } else { '' }
    if ($dir -notin @('left', 'down', 'up', 'right')) {
        [Console]::Error.WriteLine("Error: Invalid swap direction '$Direction'. Expected: left, down, up, or right.")
        exit 1
    }
    $sess = Resolve-TargetSession $SessionArg
    [void](Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('move-pane', $dir))
    exit 0
}

function Invoke-SupervisedPaneProcess([string]$ExecutablePath, [string[]]$ArgumentList = @(), [string]$WorkingDir = '') {
    $pwshBin = Get-CurrentPwshExecutable
    $ext = [System.IO.Path]::GetExtension($ExecutablePath).ToLowerInvariant()
    $launchExe = $ExecutablePath
    $launchArgs = [System.Collections.Generic.List[string]]::new()

    if ($ext -eq '.ps1') {
        $launchExe = $pwshBin
        foreach ($pa in @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ExecutablePath)) {
            $launchArgs.Add($pa)
        }
    } elseif ($ext -in @('.cmd', '.bat')) {
        $launchExe = 'cmd.exe'
        foreach ($ca in @('/d', '/c', $ExecutablePath)) {
            $launchArgs.Add($ca)
        }
    }
    foreach ($extra in $ArgumentList) {
        $launchArgs.Add([string]$extra)
    }

    $spParams = @{
        FilePath     = $launchExe
        NoNewWindow  = $true
        PassThru     = $true
    }
    if ($launchArgs.Count -gt 0) {
        $spParams['ArgumentList'] = $launchArgs.ToArray()
    }
    if ($WorkingDir -and [System.IO.Directory]::Exists($WorkingDir)) {
        $spParams['WorkingDirectory'] = $WorkingDir
    }
    return (Start-Process @spParams)
}

function Invoke-ZellijPaneRename([string]$PaneId, [string]$Title) {
    if (-not $env:ZELLIJ -or -not $PaneId -or -not $Title) { return }
    [void](Invoke-ZellijSessionAction -SessionName '' -ActionArgs @('rename-pane', '--pane-id', $PaneId, $Title))
}

function Invoke-PaneInit([string]$Role) {
    $roleSpec = ConvertTo-CanonicalIdeRole $Role
    $normRole = $roleSpec.Internal
    $sess = Resolve-TargetSession ''
    $meta = Read-SessionState $sess
    $cwdNow = (Get-Location).ProviderPath
    $initRoot = if ($meta -and $meta['root']) { [string]$meta['root'] } elseif ($env:IDE_INITIAL_ROOT) { $env:IDE_INITIAL_ROOT } else { $cwdNow }
    $workDir = if ($meta -and $meta['workdir']) { [string]$meta['workdir'] } elseif ($env:IDE_WORKDIR) { $env:IDE_WORKDIR } else { $initRoot }
    $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
    $aiName = if ($meta -and $meta['ai_cli']) { [string]$meta['ai_cli'] } elseif ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }

    $normPaneId = ''
    if ($env:ZELLIJ_PANE_ID) {
        $normPaneId = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
        Save-RolePaneId -SessionName $sess -Role $normRole -PaneId $normPaneId
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

    $pwshBin = Get-CurrentPwshExecutable

    switch ($normRole) {
        'editor' {
            $Host.UI.RawUI.WindowTitle = "$sess [Editor]"
            if ($env:ZELLIJ -and $normPaneId) {
                try {
                    $zBin = Resolve-ZellijExecutable
                    if ($zBin) {
                        $rawId = [int]($normPaneId -replace '^terminal_', '')
                        $panesJson = Invoke-ZellijSessionAction -SessionName '' -ActionArgs @('list-panes', '--all', '--json') -PassThru
                        if ($panesJson) {
                            $edEntry = ($panesJson | ConvertFrom-Json) |
                                Where-Object { -not $_.is_plugin -and $_.id -eq $rawId } |
                                Select-Object -First 1
                            if ($edEntry -and $null -eq $edEntry.attention.muted) {
                                & $zBin action mute-pane --pane-id $normPaneId *> $null
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
                Write-Host 'Neovim (nvim) not found on PATH; dropping to interactive shell.' -ForegroundColor Yellow
            }
            & $pwshBin -NoLogo
            exit $LASTEXITCODE
        }
        'ai' {
            $stateDir = Get-IdeStateDir
            $aiSupervisorPath = Join-Path $stateDir "$sess.ai-supervisor"
            $aiActivePath = Join-Path $stateDir "$sess.ai-active"
            $aiShellPath = Join-Path $stateDir "$sess.ai-shell"
            $aiSwitchPath = Join-Path $stateDir "$sess.ai-switch"

            Write-TextUtf8NoBom -Path $aiSupervisorPath -Content "$PID`n"
            $finalExitCode = 0
            try {
                while ($true) {
                    $freshMeta = Read-SessionState $sess
                    $sessionWorkdir = if ($freshMeta -and $freshMeta['workdir'] -and [System.IO.Directory]::Exists([string]$freshMeta['workdir'])) {
                        [string]$freshMeta['workdir']
                    } elseif ($freshMeta -and $freshMeta['root'] -and [System.IO.Directory]::Exists([string]$freshMeta['root'])) {
                        [string]$freshMeta['root']
                    } else {
                        $workDir
                    }
                    if ($freshMeta -and $freshMeta['ai_cli']) {
                        $aiName = [string]$freshMeta['ai_cli']
                    }

                    Remove-Item -LiteralPath $aiSwitchPath -Force -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath $aiShellPath -Force -ErrorAction SilentlyContinue

                    $aiInfo = Resolve-AiExecutable -RequestedCli $aiName -AllowFallback ($null -eq $freshMeta)
                    $env:IDE_AI_CLI = $aiInfo.Name
                    $env:IDE_WORKDIR = $sessionWorkdir
                    if ($sessionWorkdir -and [System.IO.Directory]::Exists($sessionWorkdir)) {
                        Set-Location -LiteralPath $sessionWorkdir
                    }

                    if ($aiInfo.Path) {
                        $Host.UI.RawUI.WindowTitle = "$sess [AI: $($aiInfo.Name)]"
                        Invoke-ZellijPaneRename -PaneId $normPaneId -Title "AI ($($aiInfo.Name))"
                        try {
                            $agentProc = Invoke-SupervisedPaneProcess -ExecutablePath $aiInfo.Path -WorkingDir $sessionWorkdir
                            if ($agentProc) {
                                Write-TextUtf8NoBom -Path $aiActivePath -Content "$($agentProc.Id)`n"
                                $agentProc.WaitForExit()
                            }
                        } catch {
                            Write-Host "Failed to launch '$($aiInfo.Name)': $($_.Exception.Message)" -ForegroundColor Red
                        } finally {
                            Remove-Item -LiteralPath $aiActivePath -Force -ErrorAction SilentlyContinue
                        }
                    } elseif ($aiInfo.Name -ne 'shell') {
                        Write-Host "IDE session '$sess' ready (install '$($aiInfo.Name)' or run 'ide agent <cli>')." -ForegroundColor Cyan
                    }

                    if ([System.IO.File]::Exists($aiSwitchPath)) {
                        $switched = try { [System.IO.File]::ReadAllText($aiSwitchPath).Trim() } catch { '' }
                        Remove-Item -LiteralPath $aiSwitchPath -Force -ErrorAction SilentlyContinue
                        if ($switched) { $aiName = $switched }
                        continue
                    }

                    $Host.UI.RawUI.WindowTitle = "$sess [AI: shell]"
                    Invoke-ZellijPaneRename -PaneId $normPaneId -Title 'AI (shell)'
                    $shellProc = $null
                    try {
                        $shellProc = Invoke-SupervisedPaneProcess -ExecutablePath $pwshBin -ArgumentList @('-NoLogo') -WorkingDir $sessionWorkdir
                        if ($shellProc) {
                            Write-TextUtf8NoBom -Path $aiShellPath -Content "$($shellProc.Id)`n"
                            $shellProc.WaitForExit()
                            $finalExitCode = $shellProc.ExitCode
                        }
                    } finally {
                        Remove-Item -LiteralPath $aiShellPath -Force -ErrorAction SilentlyContinue
                    }

                    if ([System.IO.File]::Exists($aiSwitchPath)) {
                        $switchedFromShell = try { [System.IO.File]::ReadAllText($aiSwitchPath).Trim() } catch { '' }
                        Remove-Item -LiteralPath $aiSwitchPath -Force -ErrorAction SilentlyContinue
                        if ($switchedFromShell) { $aiName = $switchedFromShell }
                        continue
                    }

                    break
                }
            } finally {
                Remove-Item -LiteralPath $aiSupervisorPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $aiActivePath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $aiShellPath -Force -ErrorAction SilentlyContinue
            }
            exit $finalExitCode
        }
        default {
            $Host.UI.RawUI.WindowTitle = "$sess [Shell]"
            & $pwshBin -NoLogo
            exit $LASTEXITCODE
        }
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
            "`$env:IDE_ROLE = 'ai'"
            $commonHeader
            "`$Host.UI.RawUI.WindowTitle = `"$escSess [AI: $escAiName]`""
            "& '$escAiPath'"
        ) -join "`n"
    } else {
        @(
            "`$env:IDE_ROLE = 'ai'"
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
        "`$env:IDE_ROLE = 'editor'"
        $commonHeader
        "`$Host.UI.RawUI.WindowTitle = `"$escSess [Editor]`""
        $nvimLaunchLine
    ) -join "`n"

    $termBody = @(
        "`$env:IDE_ROLE = 'term'"
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

function Invoke-ZellijWorkspaceLaunch(
    [string]$SessionName,
    [string]$ResolvedRoot,
    [string]$PipePath,
    [string]$Layout,
    [hashtable]$AiInfo,
    [bool]$AiFromFlag,
    [string]$NvimBin,
    [string]$ZellijBin,
    [bool]$Detach,
    [bool]$Desktop,
    [bool]$NewWindow,
    [bool]$IsDryRun
) {
    $zellijCfgDir = Get-ZellijConfigDir
    $zellijLayout = if ($Layout -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }

    $zellijPreviewCmd = if ($Detach) {
        "zellij attach --create-background $SessionName options --default-layout $zellijLayout --default-cwd `"$ResolvedRoot`""
    } elseif ($Desktop) {
        "zellij terminal --standalone --create --working-directory `"$ResolvedRoot`" $SessionName options --default-layout $zellijLayout"
    } elseif ($env:ZELLIJ -and -not $NewWindow) {
        "zellij action switch-session --layout $zellijLayout --cwd `"$ResolvedRoot`" $SessionName"
    } else {
        "zellij attach --create $SessionName options --default-layout $zellijLayout --default-cwd `"$ResolvedRoot`""
    }

    if ($IsDryRun) {
        $initialDoc = Resolve-InitialEditorFile $ResolvedRoot
        Write-Output "IDE Session : $SessionName"
        Write-Output "Backend     : zellij"
        Write-Output "Layout      : $Layout ($zellijLayout)"
        Write-Output "Workdir     : $ResolvedRoot"
        Write-Output "Named Pipe  : $PipePath"
        Write-Output "AI Agent    : $($AiInfo.Name)"
        Write-Output "Editor      : $NvimBin"
        if ($initialDoc) {
            Write-Output "Initial Doc : $initialDoc"
        }
        Write-Output "Config Dir  : $zellijCfgDir"
        Write-Output "Command     : $zellijPreviewCmd"
        exit 0
    }

    if (-not $ZellijBin) {
        [Console]::Error.WriteLine("Error: Zellij ('zellij') was not found on PATH. Run '.\setup.ps1 -Bootstrap' or 'mise install zellij@latest'.")
        exit 1
    }

    $binDir = Get-IdeBinDir
    $pathEntries = @($env:Path -split ';' | Where-Object { $_ -and $_.Trim() })
    if ($pathEntries -notcontains $binDir) {
        $env:Path = "$binDir;$env:Path"
    }
    $env:ZELLIJ_CONFIG_DIR = $zellijCfgDir
    $env:WINDOWS_SETTINGS_THEME = Get-ActiveThemeSlug

    $liveZellij = Get-LiveZellijSessionMap
    $existingMeta = Read-SessionState $SessionName
    $effAiName = if ($AiFromFlag -or -not ($existingMeta -and $existingMeta['ai_cli'])) {
        $AiInfo.Name
    } else {
        [string]$existingMeta['ai_cli']
    }

    $env:IDE_SESSION = $SessionName
    $env:IDE_INITIAL_ROOT = $ResolvedRoot
    $env:IDE_WORKDIR = $ResolvedRoot
    $env:NVIM_IDE_SOCKET = $PipePath
    $env:IDE_AI_CLI = $effAiName

    if ($AiFromFlag -and $liveZellij[$SessionName] -eq 'live' -and $existingMeta -and $existingMeta['ai_cli'] -ne $AiInfo.Name) {
        if (-not (Get-Command Invoke-IdeAgent -CommandType Function -ErrorAction SilentlyContinue)) {
            . (Join-Path (Get-IdeLibDir) 'Launcher.ps1')
        }
        Invoke-IdeAgent -CliArg $AiInfo.Name -SessionArg $SessionName
        $existingMeta = Read-SessionState $SessionName
    }

    $nowInitTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $metaObj = Build-IdeSessionRecord `
        -SessionName $SessionName `
        -Root $(if ($existingMeta -and $existingMeta['root']) { [string]$existingMeta['root'] } else { $ResolvedRoot }) `
        -Workdir $(if ($liveZellij[$SessionName] -eq 'live' -and $existingMeta -and $existingMeta['workdir']) { [string]$existingMeta['workdir'] } else { $ResolvedRoot }) `
        -PrevWorkdir $(if ($existingMeta -and $existingMeta['prev_workdir']) { [string]$existingMeta['prev_workdir'] } else { '' }) `
        -Pipe $PipePath `
        -Layout $Layout `
        -Backend 'zellij' `
        -AiCli $effAiName `
        -AgentState $(if ($existingMeta -and $existingMeta['agent_state']) { [string]$existingMeta['agent_state'] } else { 'idle' }) `
        -AgentMessage $(if ($existingMeta -and $existingMeta['agent_message']) { [string]$existingMeta['agent_message'] } else { '' }) `
        -StateTs $(if ($existingMeta -and $existingMeta['state_ts']) { [long]$existingMeta['state_ts'] } else { $nowInitTs }) `
        -AttnTs $(if ($existingMeta -and $existingMeta['attn_ts']) { [long]$existingMeta['attn_ts'] } else { 0L }) `
        -CreatedAt $(if ($existingMeta -and $existingMeta['created_at']) { [string]$existingMeta['created_at'] } else { '' })
    Save-SessionState $metaObj

    if ($liveZellij[$SessionName] -eq 'exited') {
        try { & $ZellijBin delete-session $SessionName *> $null } catch { Write-Verbose 'Cleared exited session stub' }
    }

    if ($Detach) {
        if ($liveZellij[$SessionName] -eq 'live') {
            Write-Output "IDE session '$SessionName' is already running in background."
            exit 0
        }
        Push-Location -LiteralPath $ResolvedRoot
        try {
            & $ZellijBin attach --create-background $SessionName options --default-layout $zellijLayout --default-cwd $ResolvedRoot
        } finally {
            Pop-Location
        }
        Write-Output "Started detached IDE session '$SessionName' ($Layout) in $ResolvedRoot"
        exit 0
    }

    if ($Desktop) {
        $zPsi = [System.Diagnostics.ProcessStartInfo]::new($ZellijBin)
        $zPsi.WorkingDirectory = $ResolvedRoot
        foreach ($a in @('terminal', '--standalone', '--create', '--working-directory', $ResolvedRoot, $SessionName, 'options', '--default-layout', $zellijLayout)) {
            $zPsi.ArgumentList.Add($a)
        }
        $zPsi.UseShellExecute = $false
        [void][System.Diagnostics.Process]::Start($zPsi)
        Write-Output "Opened standalone Zellij desktop IDE window for '$SessionName' ($Layout)"
        exit 0
    }

    if (Test-IsCurrentZellijSession $SessionName) {
        exit 0
    }

    if ($env:ZELLIJ -and -not $NewWindow) {
        & $ZellijBin action switch-session --layout $zellijLayout --cwd $ResolvedRoot $SessionName
        exit $LASTEXITCODE
    }

    if ($NewWindow) {
        $wtCmd = Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($wtCmd) {
            $wtPsi = [System.Diagnostics.ProcessStartInfo]::new($wtCmd.Source)
            foreach ($a in @('-w', 'new', 'new-tab', '--title', $SessionName, '-d', $ResolvedRoot, $ZellijBin, 'attach', '--create', $SessionName, 'options', '--default-layout', $zellijLayout, '--default-cwd', $ResolvedRoot)) {
                $wtPsi.ArgumentList.Add($a)
            }
            $wtPsi.UseShellExecute = $false
            [void][System.Diagnostics.Process]::Start($wtPsi)
            Write-Output "Launched IDE session '$SessionName' in new Windows Terminal window"
            exit 0
        }
    }

    Push-Location -LiteralPath $ResolvedRoot
    try {
        & $ZellijBin attach --create $SessionName options --default-layout $zellijLayout --default-cwd $ResolvedRoot
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Invoke-WtWorkspaceLaunch(
    [string]$SessionName,
    [string]$ResolvedRoot,
    [string]$PipePath,
    [string]$Layout,
    [hashtable]$AiInfo,
    [string]$NvimBin,
    [bool]$NewWindow,
    [bool]$IsDryRun
) {
    $pwshBin = Get-CurrentPwshExecutable
    $stateDir = Get-IdeStateDir
    $aiScriptPreview = Join-Path $stateDir "launch-$SessionName-ai.ps1"
    $edScriptPreview = Join-Path $stateDir "launch-$SessionName-editor.ps1"
    $tmScriptPreview = Join-Path $stateDir "launch-$SessionName-term.ps1"

    $wtArgList = [System.Collections.Generic.List[string]]::new()
    if ($NewWindow) {
        $wtArgList.AddRange([string[]]@('-w', 'new'))
    } elseif ($env:WT_SESSION) {
        $wtArgList.AddRange([string[]]@('-w', '0'))
    }

    $wtArgList.AddRange([string[]]@('new-tab', '--title', $SessionName, '-d', $ResolvedRoot, $pwshBin, '-NoLogo', '-NoExit', '-File', $aiScriptPreview))

    if ($Layout -eq '3pane') {
        $wtArgList.AddRange([string[]]@(';', 'split-pane', '-H', '-s', '0.25', '-d', $ResolvedRoot, $pwshBin, '-NoLogo', '-NoExit', '-File', $tmScriptPreview))
        $wtArgList.AddRange([string[]]@(';', 'move-focus', 'up'))
    }

    $wtArgList.AddRange([string[]]@(';', 'split-pane', '-V', '-s', '0.50', '-d', $ResolvedRoot, $pwshBin, '-NoLogo', '-File', $edScriptPreview))
    $wtArgList.AddRange([string[]]@(';', 'move-focus', 'left'))

    $formattedWtArgs = @($wtArgList | ForEach-Object {
        if ($_ -ne ';' -and $_ -match '\s') { "`"$($_.Replace('"', '\"'))`"" } else { $_ }
    })

    if ($IsDryRun) {
        $initialDoc = Resolve-InitialEditorFile $ResolvedRoot
        Write-Output "IDE Session : $SessionName"
        Write-Output "Backend     : wt"
        Write-Output "Layout      : $Layout"
        Write-Output "Workdir     : $ResolvedRoot"
        Write-Output "Named Pipe  : $PipePath"
        Write-Output "AI Agent    : $($AiInfo.Name)"
        Write-Output "Editor      : $NvimBin"
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
        -SessionName $SessionName `
        -InitialRoot $ResolvedRoot `
        -WorkDir $ResolvedRoot `
        -PipePath $PipePath `
        -AiCliName $AiInfo.Name `
        -AiCliPath $AiInfo.Path `
        -NvimPath $NvimBin)

    $nowInitTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $metaObj = Build-IdeSessionRecord `
        -SessionName $SessionName `
        -Root $ResolvedRoot `
        -Workdir $ResolvedRoot `
        -Pipe $PipePath `
        -Layout $Layout `
        -Backend 'wt' `
        -AiCli $AiInfo.Name `
        -StateTs $nowInitTs
    Save-SessionState $metaObj

    $wtPsi = [System.Diagnostics.ProcessStartInfo]::new($wtCmd.Source)
    $wtPsi.Arguments = ($formattedWtArgs -join ' ')
    $wtPsi.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($wtPsi)
    Write-Output "Launched IDE session '$SessionName' ($Layout) in $ResolvedRoot"
}

function Invoke-LaunchWorkspace(
    [string]$TargetDirArg = '',
    [string]$Layout = '3pane',
    [string]$RequestedBackend = '',
    [string]$RequestedAi = 'agy',
    [bool]$AiFromFlag = $false,
    [bool]$Detach = $false,
    [bool]$Desktop = $false,
    [bool]$NewWindow = $false,
    [bool]$IsDryRun = $false
) {
    if (-not (Get-Command Resolve-IdeWorkspaceTarget -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Hooks.ps1')
    }

    if ($AiFromFlag) {
        $checkedAi = Resolve-ValidatedAiCliName -RequestedCli $RequestedAi -FromFlag $true
        if (-not $checkedAi) {
            [Console]::Error.WriteLine("Error: Unknown or unavailable AI CLI '$RequestedAi'.")
            exit 1
        }
        $RequestedAi = $checkedAi
    }

    $explicitSessionName = ''
    $resolvedRoot = ''

    if (-not $TargetDirArg) {
        $resolvedRoot = (Get-Location).ProviderPath
    } else {
        $trimmedArg = $TargetDirArg.Trim()
        $isExplicitRelative = $trimmedArg -in @('.', '..') -or
            $trimmedArg.StartsWith('.\') -or $trimmedArg.StartsWith('./') -or
            $trimmedArg.StartsWith('..\') -or $trimmedArg.StartsWith('../') -or
            $trimmedArg.StartsWith('~')

        if ($env:IDE_WORKSPACE_RESOLVED -ne '1' -and
            -not $isExplicitRelative -and
            -not $trimmedArg.Contains('\') -and
            -not $trimmedArg.Contains('/')) {
            $localCand = Join-Path (Get-Location).ProviderPath $trimmedArg
            if (-not (Test-Path -LiteralPath $localCand -PathType Container)) {
                $liveZ = Get-LiveZellijSessionMap
                $liveP = Get-LiveIdePipeMap
                $sessMeta = Read-SessionState $trimmedArg
                if ($liveZ[$trimmedArg] -eq 'live' -or $liveP.ContainsKey($trimmedArg) -or $null -ne $sessMeta) {
                    $explicitSessionName = $trimmedArg
                    $resolvedRoot = if ($sessMeta -and $sessMeta['workdir'] -and (Test-Path -LiteralPath $sessMeta['workdir'] -PathType Container)) {
                        [string]$sessMeta['workdir']
                    } elseif ($sessMeta -and $sessMeta['root'] -and (Test-Path -LiteralPath $sessMeta['root'] -PathType Container)) {
                        [string]$sessMeta['root']
                    } else {
                        (Get-Location).ProviderPath
                    }
                    if (-not $Layout -and $sessMeta -and $sessMeta['layout']) {
                        $Layout = [string]$sessMeta['layout']
                    }
                }
            }
        }

        if (-not $resolvedRoot) {
            $fsCand = if ([System.IO.Path]::IsPathRooted($trimmedArg) -or $trimmedArg.StartsWith('~')) {
                Expand-IdeUserPath $trimmedArg
            } else {
                [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $trimmedArg))
            }
            if (Test-Path -LiteralPath $fsCand -PathType Container) {
                $resolvedRoot = (Resolve-Path -LiteralPath $fsCand).ProviderPath
            } elseif ($IsDryRun -and $env:IDE_WORKSPACE_RESOLVED -eq '1') {
                $resolvedRoot = $fsCand
            } else {
                $wsResolved = Resolve-IdeWorkspaceTarget $trimmedArg
                if ($wsResolved -and (Test-Path -LiteralPath $wsResolved -PathType Container)) {
                    $resolvedRoot = (Resolve-Path -LiteralPath $wsResolved).ProviderPath
                } else {
                    [Console]::Error.WriteLine("Error: Target directory or active session does not exist: $TargetDirArg")
                    exit 1
                }
            }
        }
    }

    $sessionName = if ($explicitSessionName) { $explicitSessionName } else { Get-SanitizedSessionName $resolvedRoot }
    $pipePath = Get-SessionPipePath $sessionName
    $aiInfo = Resolve-AiExecutable -RequestedCli $RequestedAi -AllowFallback (-not $AiFromFlag)
    $nvimBin = Resolve-NvimExecutable
    if (-not $nvimBin) { $nvimBin = 'nvim' }
    $zellijBin = Resolve-ZellijExecutable

    $effectiveBackend = if ($RequestedBackend -in @('zellij', 'wt')) {
        $RequestedBackend
    } elseif ($zellijBin) {
        'zellij'
    } else {
        'wt'
    }

    if ($effectiveBackend -eq 'zellij') {
        Invoke-ZellijWorkspaceLaunch `
            -SessionName $sessionName `
            -ResolvedRoot $resolvedRoot `
            -PipePath $pipePath `
            -Layout $Layout `
            -AiInfo $aiInfo `
            -AiFromFlag $AiFromFlag `
            -NvimBin $nvimBin `
            -ZellijBin $zellijBin `
            -Detach $Detach `
            -Desktop $Desktop `
            -NewWindow $NewWindow `
            -IsDryRun $IsDryRun
        return
    }

    Invoke-WtWorkspaceLaunch `
        -SessionName $sessionName `
        -ResolvedRoot $resolvedRoot `
        -PipePath $pipePath `
        -Layout $Layout `
        -AiInfo $aiInfo `
        -NvimBin $nvimBin `
        -NewWindow $NewWindow `
        -IsDryRun $IsDryRun
}

function Invoke-IdeRefresh([string]$TargetArg = '', [bool]$IsDryRun = $false) {
    $activeSlug = Get-ActiveThemeSlug
    if ($IsDryRun) {
        $scopeDesc = if ($TargetArg) { "session '$(Resolve-TargetSession $TargetArg)'" } else { 'all live IDE sessions' }
        Write-Output "[DRY-RUN] Would re-apply active theme '$activeSlug', rebuild keys-cheatsheet.ans, reload windows-settings-bar, and heal Editor CWDs across $scopeDesc."
        exit 0
    }

    $themePs1 = Join-Path (Get-IdeBinDir) 'theme.ps1'
    if (Test-Path -LiteralPath $themePs1 -PathType Leaf) {
        & $themePs1 --set $activeSlug --no-live *> $null
    }
    [void](Get-ActivePaletteMap -Reload)
    Write-IdeKeysCheatsheetCache

    $holidayIcon = if ($env:_HS_PROMPT_OS_ICON) { $env:_HS_PROMPT_OS_ICON } else { '' }
    $zellijBin = Resolve-ZellijExecutable
    $liveZellij = Get-LiveZellijSessionMap
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
                [void](Invoke-ZellijSessionAction -SessionName $zs -ActionArgs @('start-or-reload-plugin', 'compact-bar'))
            }
            $zMeta = Read-SessionState $zs
            $kvParts = [System.Collections.Generic.List[string]]::new()
            $kvParts.Add("theme=$activeSlug")
            if ($zMeta -and $zMeta['root']) { $kvParts.Add("root=$($zMeta['root'])") }
            if ($zMeta -and $zMeta['workdir']) { $kvParts.Add("workdir=$($zMeta['workdir'])") }
            $kvParts.Add("holiday_icon=$holidayIcon")
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

    $refreshLua = @'
local d = ...
vim.schedule(function()
    local uv = vim.uv or vim.loop
    if type(d) == "string" and d ~= "" and uv.fs_stat(d) then
        local no_cwd = (uv.fs_stat(vim.fn.getcwd()) == nil)
        if no_cwd or (vim.fn.haslocaldir() == 0 and vim.fn.haslocaldir(-1, 0) == 0 and vim.fn.getcwd() ~= d) then
            pcall(vim.fn.chdir, d)
        end
    end
    pcall(vim.cmd, "silent! checktime")
    if _G.apply_home_settings_theme then
        pcall(_G.apply_home_settings_theme)
    end
    pcall(function() require("solarized.images").refresh() end)
end)
return "OK"
'@

    foreach ($sKey in $pipeTargets.Keys) {
        $pipe = $pipeTargets[$sKey]
        $sMeta = Read-SessionState $sKey
        $healDir = ''
        if ($sMeta -and $sMeta['workdir'] -and (Test-Path -LiteralPath $sMeta['workdir'] -PathType Container)) {
            $healDir = [string]$sMeta['workdir']
        } elseif ($sMeta -and $sMeta['root'] -and (Test-Path -LiteralPath $sMeta['root'] -PathType Container)) {
            $healDir = [string]$sMeta['root']
        }
        [void](Invoke-NvimLua -PipePath $pipe -LuaCode $refreshLua -LuaArgs @($healDir))
    }
    exit 0
}

function Close-IdeSessionList([string[]]$TargetArgs, [bool]$Force = $false) {
    $targets = [System.Collections.Generic.List[string]]::new()
    if ($TargetArgs -and $TargetArgs.Count -gt 0) {
        foreach ($t in $TargetArgs) {
            if (-not $t) { continue }
            $resolved = Resolve-TargetSession $t
            if (-not $targets.Contains($resolved)) {
                $targets.Add($resolved)
            }
        }
    } else {
        $targets.Add((Resolve-TargetSession ''))
    }

    $zellijBin = Resolve-ZellijExecutable
    $curZellijSess = Get-CurrentZellijSessionToken
    $needsSessionScan = $false
    foreach ($t in $targets) {
        if (-not (Test-IsCurrentZellijSession $t)) {
            $needsSessionScan = $true
            break
        }
    }
    $liveZellij = if ($needsSessionScan) { Get-LiveZellijSessionMap } else { @{} }
    if ($curZellijSess) {
        $liveZellij[$curZellijSess] = 'live'
    }

    $alreadyScheduledQuit = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $quitCheckLua = 'if _G.try_ide_quit then return _G.try_ide_quit(false) end; if _G.count_ide_modified_buffers then return _G.count_ide_modified_buffers() end; return 0'

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
            $modRes = Invoke-NvimLua -PipePath $pipePath -LuaCode $quitCheckLua
            $modCount = 0
            if ($modRes.Success -and [int]::TryParse($modRes.Output, [ref]$modCount) -and $modCount -gt 0) {
                $errMsg = "E37: No write since last change in $modCount buffer(s) in session '$sess' (save in Neovim or use 'ide quit --force' / idek)."
                if ($meta) {
                    $meta['quit_error'] = "Unsaved changes in $modCount buffer(s)"
                    Save-SessionState $meta
                }
                if (Test-IsCurrentZellijSession $sess) {
                    [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
                }
                [Console]::Error.WriteLine($errMsg)
                exit 1
            }
            if ($meta -and $meta['quit_error']) {
                $meta['quit_error'] = ''
                Save-SessionState $meta
            }
            if ($modRes.Success -and $targets.Count -eq 1) {
                [void]$alreadyScheduledQuit.Add($sess)
            }
        }
    }

    $forceQuitLua = 'vim.schedule(function() vim.cmd("qa!") end); return "OK"'
    foreach ($sess in $targets) {
        $meta = Read-SessionState $sess
        $pipePath = if ($meta -and $meta['pipe']) { [string]$meta['pipe'] } else { Get-SessionPipePath $sess }
        if (-not $alreadyScheduledQuit.Contains($sess) -and (Test-IdePipeLive $pipePath)) {
            [void](Invoke-NvimLua -PipePath $pipePath -LuaCode $forceQuitLua)
        }
        if ($zellijBin -and $liveZellij.ContainsKey($sess)) {
            try {
                & $zellijBin delete-session --force $sess *> $null
            } catch {
                Write-Verbose "Zellij session delete skipped for ${sess}: $_"
            }
        }
        Clear-IdeSessionArtifactSet $sess
        Write-Output "Closed IDE session '$sess'."
    }
}
