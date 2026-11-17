# ==============================================================================
# Workspace.ps1 - Pane init, role routing, workspace launch, refresh & teardown
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
        [Console]::Error.WriteLine("Error: Invalid '--swap' direction '$Direction'. Expected: left, down, up, or right.")
        exit 1
    }
    $sess = Resolve-TargetSession $SessionArg
    [void](Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('move-pane', $dir))
    exit 0
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

    $pwshBin = Get-CurrentPwshExecutable

    switch ($normRole) {
        'editor' {
            $Host.UI.RawUI.WindowTitle = "$sess [Editor]"
            if ($env:ZELLIJ -and $env:ZELLIJ_PANE_ID) {
                try {
                    $zBin = Resolve-ZellijExecutable
                    $edPid = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
                    if ($zBin -and $edPid) {
                        $rawId = [int]($edPid -replace '^terminal_', '')
                        $panesJson = Invoke-ZellijSessionAction -SessionName '' -ActionArgs @('list-panes', '--all', '--json') -PassThru
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
                Write-Host 'Neovim (nvim) not found on PATH; dropping to interactive shell.' -ForegroundColor Yellow
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

function Invoke-ZellijWorkspaceLaunch(
    [string]$SessionName,
    [string]$ResolvedRoot,
    [string]$PipePath,
    [string]$Layout,
    [hashtable]$AiInfo,
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
    $env:IDE_SESSION = $SessionName
    $env:IDE_INITIAL_ROOT = $ResolvedRoot
    $env:IDE_WORKDIR = $ResolvedRoot
    $env:NVIM_IDE_SOCKET = $PipePath
    $env:IDE_AI_CLI = $AiInfo.Name

    $existingMeta = Read-SessionState $SessionName
    $nowInitTs = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $metaObj = Build-IdeSessionRecord `
        -SessionName $SessionName `
        -Root $(if ($existingMeta -and $existingMeta['root']) { [string]$existingMeta['root'] } else { $ResolvedRoot }) `
        -Workdir $ResolvedRoot `
        -Pipe $PipePath `
        -Layout $Layout `
        -Backend 'zellij' `
        -AiCli $AiInfo.Name `
        -AgentState $(if ($existingMeta -and $existingMeta['agent_state']) { [string]$existingMeta['agent_state'] } else { 'idle' }) `
        -AgentMessage $(if ($existingMeta -and $existingMeta['agent_message']) { [string]$existingMeta['agent_message'] } else { '' }) `
        -StateTs $(if ($existingMeta -and $existingMeta['state_ts']) { [long]$existingMeta['state_ts'] } else { $nowInitTs }) `
        -AttnTs $(if ($existingMeta -and $existingMeta['attn_ts']) { [long]$existingMeta['attn_ts'] } else { 0L }) `
        -CreatedAt $(if ($existingMeta -and $existingMeta['created_at']) { [string]$existingMeta['created_at'] } else { '' })
    Save-SessionState $metaObj

    $liveZellij = Get-LiveZellijSessionMap
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
    [string]$TargetDirArg,
    [string]$Layout,
    [string]$RequestedBackend,
    [string]$RequestedAi,
    [bool]$Detach,
    [bool]$Desktop,
    [bool]$NewWindow,
    [bool]$IsDryRun
) {
    $resolvedRoot = if ($TargetDirArg) {
        if ([System.IO.Path]::IsPathRooted($TargetDirArg)) {
            $TargetDirArg
        } else {
            [System.IO.Path]::GetFullPath((Join-Path (Get-Location).ProviderPath $TargetDirArg))
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
    $aiInfo = Resolve-AiExecutable $RequestedAi
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

function Invoke-IdeRefresh([string]$TargetArg, [bool]$IsDryRun) {
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
                if (Test-IsCurrentZellijSession $sess) {
                    [void](Select-IdeRolePane -SessionName $sess -Role 'editor' -EnsureOnly $true)
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
        Clear-IdeSessionArtifactSet $sess
        Write-Output "Closed IDE session '$sess'."
    }
}
