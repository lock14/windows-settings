# ==============================================================================
# Core.ps1 - Shared paths, session state, binary resolution, Zellij pipes & theme
# ==============================================================================

$script:IdeLibDir = $PSScriptRoot
$script:IdeBinDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:IdeRepoDir = Split-Path -Parent $script:IdeBinDir
$script:IdeEntryScript = Join-Path $script:IdeBinDir 'ide.ps1'
if (-not $script:IdeResolvedTools) {
    $script:IdeResolvedTools = @{}
}
$script:IdeCachedPalette = $null

function Get-IdeBinDir {
    return $script:IdeBinDir
}

function Get-IdeRepoDir {
    return $script:IdeRepoDir
}

function Get-IdeEntryScriptPath {
    return $script:IdeEntryScript
}

function Get-IdeBatchScriptPath {
    return (Join-Path $script:IdeBinDir 'ide.cmd')
}

function Get-CurrentPwshExecutable {
    $pwshPath = (Get-Process -Id $PID).Path
    if ($pwshPath) { return $pwshPath }
    return 'pwsh.exe'
}

function Write-TextUtf8NoBom([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Read-NonBlockingStdin([string]$EnvOverrideName = '', [string]$FallbackText = '', [int]$TimeoutMs = 75) {
    if ($EnvOverrideName) {
        $envVal = [Environment]::GetEnvironmentVariable($EnvOverrideName)
        if ($envVal) { return $envVal }
    }
    if ($FallbackText) { return $FallbackText }
    try {
        if ([Console]::IsInputRedirected) {
            $readTask = [Console]::In.ReadToEndAsync()
            if ($readTask.Wait($TimeoutMs)) {
                return $readTask.Result
            }
        }
    } catch {
        Write-Verbose "Non-blocking stdin read skipped: $_"
    }
    return ''
}

function Get-UserHomeDir {
    if ($HOME) { return $HOME }
    return $env:USERPROFILE
}

function Get-IdeStateDir {
    $cacheBase = Join-Path (Join-Path (Get-UserHomeDir) '.cache') 'windows-settings'
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
    $userHome = Get-UserHomeDir
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

function ConvertTo-CanonicalIdeRole([string]$Role) {
    $norm = if ($Role) { $Role.Trim().ToLowerInvariant() } else { 'ai' }
    switch ($norm) {
        { $_ -in @('editor', 'nvim') } {
            return @{ Internal = 'editor'; Pipe = 'editor' }
        }
        { $_ -in @('term', 'shell') } {
            return @{ Internal = 'term'; Pipe = 'shell' }
        }
        default {
            return @{ Internal = 'ai'; Pipe = 'ai' }
        }
    }
}

function Save-RolePaneId([string]$SessionName, [string]$Role, [string]$PaneId) {
    $norm = ConvertTo-ZellijPaneId $PaneId
    if (-not $norm) { return }
    $roleSpec = ConvertTo-CanonicalIdeRole $Role
    Write-TextUtf8NoBom -Path (Get-RoleSidecarPath -SessionName $SessionName -Role $roleSpec.Internal) -Content "$norm`n"
}

function Get-RolePaneId([string]$SessionName, [string]$Role) {
    $roleSpec = ConvertTo-CanonicalIdeRole $Role
    $p = Get-RoleSidecarPath -SessionName $SessionName -Role $roleSpec.Internal
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return '' }
    try {
        return (ConvertTo-ZellijPaneId (Get-Content -LiteralPath $p -Raw))
    } catch {
        return ''
    }
}

function Resolve-IdeToolBinary([string[]]$CandidateNames, [string]$MiseTool = '', [string]$BinaryFilter = '') {
    $cacheKey = "$($CandidateNames -join ',')|$MiseTool"
    if ($script:IdeResolvedTools.ContainsKey($cacheKey)) {
        return $script:IdeResolvedTools[$cacheKey]
    }

    $resolved = ''
    foreach ($name in $CandidateNames) {
        $cmd = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd -and $cmd.Source) {
            $src = $cmd.Source
            if ($MiseTool -and $BinaryFilter -and $src -match '(?i)[\\/]mise[\\/]shims[\\/]') {
                $miseRoot = Split-Path -Parent (Split-Path -Parent $src)
                $installsDir = Join-Path (Join-Path $miseRoot 'installs') $MiseTool
                if (Test-Path -LiteralPath $installsDir -PathType Container) {
                    $realExe = Get-ChildItem -LiteralPath $installsDir -Filter $BinaryFilter -Recurse -File -ErrorAction SilentlyContinue |
                        Sort-Object FullName -Descending |
                        Select-Object -First 1
                    if ($realExe) {
                        $resolved = $realExe.FullName
                        break
                    }
                }
            }
            $resolved = $src
            break
        }
    }

    if (-not $resolved -and $MiseTool -and $BinaryFilter -and $env:LOCALAPPDATA) {
        $miseInstalls = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'mise') 'installs') $MiseTool
        if (Test-Path -LiteralPath $miseInstalls -PathType Container) {
            $realExe = Get-ChildItem -LiteralPath $miseInstalls -Filter $BinaryFilter -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($realExe) { $resolved = $realExe.FullName }
        }
    }

    $script:IdeResolvedTools[$cacheKey] = $resolved
    return $resolved
}

function Resolve-ZellijExecutable {
    return (Resolve-IdeToolBinary -CandidateNames @('zellij.exe', 'zellij') -MiseTool 'zellij' -BinaryFilter 'zellij.exe')
}

function Resolve-NvimExecutable {
    return (Resolve-IdeToolBinary -CandidateNames @('nvim.exe', 'nvim') -MiseTool 'neovim' -BinaryFilter 'nvim.exe')
}

function Resolve-AiExecutable([string]$RequestedCli) {
    $cli = if ($RequestedCli -and $RequestedCli.Trim()) { $RequestedCli.Trim() } else { 'agy' }
    if ($cli.ToLowerInvariant() -in @('none', 'shell', 'pwsh')) {
        return @{ Name = 'shell'; Path = '' }
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
            return @{ Name = $cand; Path = $hit.Source }
        }
    }
    return @{ Name = $cli; Path = '' }
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
    $repoCfg = Join-Path (Join-Path $script:IdeRepoDir 'config') 'zellij'
    if (Test-Path -LiteralPath (Join-Path $repoCfg 'config.kdl') -PathType Leaf) {
        return $repoCfg
    }
    if ($env:APPDATA) {
        return (Join-Path (Join-Path $env:APPDATA 'Zellij') 'config')
    }
    return (Join-Path (Join-Path (Get-UserHomeDir) '.config') 'zellij')
}

function Get-CurrentZellijSessionToken {
    if ($env:ZELLIJ_SESSION_NAME -and $env:ZELLIJ_SESSION_NAME.Trim()) {
        return (Get-SanitizedToken $env:ZELLIJ_SESSION_NAME.Trim())
    }
    return ''
}

function Test-IsCurrentZellijSession([string]$SessionName) {
    if (-not $env:ZELLIJ -or -not $SessionName) { return $false }
    $curSess = Get-CurrentZellijSessionToken
    if (-not $curSess) { return $false }
    return [string]::Equals($SessionName, $curSess, [System.StringComparison]::OrdinalIgnoreCase)
}

function Invoke-ZellijSessionAction([string]$SessionName, [string[]]$ActionArgs, [switch]$PassThru) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin -or -not $ActionArgs -or $ActionArgs.Count -eq 0) {
        return ''
    }
    if (-not $SessionName -or (Test-IsCurrentZellijSession $SessionName)) {
        if ($PassThru) {
            return ((& $zellijBin action @ActionArgs 2>$null) -join "`n")
        }
        & $zellijBin action @ActionArgs *> $null
        return ''
    }
    if ($PassThru) {
        return ((& $zellijBin --session $SessionName action @ActionArgs 2>$null) -join "`n")
    }
    & $zellijBin --session $SessionName action @ActionArgs *> $null
    return ''
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
        foreach ($p in [System.IO.Directory]::GetFiles('\\.\pipe\', 'nvim-ide-*')) {
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
    if ($PipePath -match '^\\\\\.\\pipe\\(.+)$') {
        $pipeLeaf = $Matches[1]
        try {
            if ([System.IO.Directory]::GetFiles('\\.\pipe\', $pipeLeaf).Count -gt 0) {
                return $true
            }
        } catch {
            Write-Verbose "Filtered pipe check skipped: $_"
        }
    }
    try {
        if ([System.IO.File]::Exists($PipePath)) { return $true }
    } catch {
        Write-Verbose "Direct pipe existence check skipped: $_"
    }
    return $false
}

function Test-WasmBarDeployed {
    if (-not $env:APPDATA) { return $false }
    $barWasm = Join-Path (Join-Path (Join-Path (Join-Path $env:APPDATA 'Zellij') 'data') 'plugins') 'windows-settings-bar.wasm'
    return [System.IO.File]::Exists($barWasm)
}

function Invoke-ZellijPipe([string]$SessionName, [string]$PipeName, [string]$Payload, [int]$TimeoutMs = 1500) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin -or -not $Payload) { return $false }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($zellijBin)
        if ($SessionName -and -not (Test-IsCurrentZellijSession $SessionName)) {
            $psi.ArgumentList.Add('--session')
            $psi.ArgumentList.Add($SessionName)
        }
        foreach ($argItem in @('pipe', '--name', $PipeName, '--', $Payload)) {
            $psi.ArgumentList.Add($argItem)
        }
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

function Select-IdeRolePane([string]$SessionName, [string]$Role, [bool]$EnsureOnly = $false) {
    $zellijBin = Resolve-ZellijExecutable
    if (-not $zellijBin) { return $false }
    $roleSpec = ConvertTo-CanonicalIdeRole $Role
    $verb = if ($EnsureOnly) { 'ensure' } else { 'focus' }

    if (Test-WasmBarDeployed) {
        if (Invoke-ZellijPipe -SessionName $SessionName -PipeName 'ws-ide-role' -Payload "${verb}:$($roleSpec.Pipe)") {
            return $true
        }
    }
    if (-not $env:ZELLIJ -or ($SessionName -and -not (Test-IsCurrentZellijSession $SessionName))) {
        return $false
    }

    $targetId = Get-RolePaneId -SessionName $SessionName -Role $roleSpec.Internal
    $curId = ConvertTo-ZellijPaneId $env:ZELLIJ_PANE_ID
    if ($targetId) {
        if (-not $EnsureOnly -and $curId -and $curId -eq $targetId) {
            & $zellijBin action focus-last-pane *> $null
        } else {
            & $zellijBin action focus-pane-id $targetId *> $null
        }
        return $true
    }

    switch ($roleSpec.Internal) {
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
    return $true
}

function Build-IdeSessionRecord(
    [string]$SessionName,
    [string]$Root = '',
    [string]$Workdir = '',
    [string]$Pipe = '',
    [string]$Layout = '3pane',
    [string]$Backend = 'zellij',
    [string]$AiCli = '',
    [string]$AgentState = 'idle',
    [string]$AgentMessage = '',
    [long]$StateTs = 0L,
    [long]$AttnTs = 0L,
    [string]$CreatedAt = '',
    [string]$UpdatedAt = ''
) {
    $resolvedPipe = if ($Pipe) { $Pipe } else { Get-SessionPipePath $SessionName }
    $resolvedAi = if ($AiCli) { $AiCli } elseif ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
    return [ordered]@{
        session       = $SessionName
        root          = $Root
        workdir       = $Workdir
        pipe          = $resolvedPipe
        layout        = if ($Layout) { $Layout } else { '3pane' }
        backend       = if ($Backend) { $Backend } else { 'zellij' }
        ai_cli        = $resolvedAi
        agent_state   = if ($AgentState) { $AgentState } else { 'idle' }
        agent_message = $AgentMessage
        state_ts      = $StateTs
        attn_ts       = $AttnTs
        created_at    = $CreatedAt
        updated_at    = $UpdatedAt
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
                        $attnTs = if ($fastState -in @('approval', 'done', 'error')) { $stateTs } else { 0L }
                    }
                    $agentState = $fastState
                }
            }
        }
        return (Build-IdeSessionRecord `
            -SessionName $(if ($obj.session) { [string]$obj.session } else { $SessionName }) `
            -Root $(if ($obj.root) { [string]$obj.root } else { '' }) `
            -Workdir $(if ($obj.workdir) { [string]$obj.workdir } else { '' }) `
            -Pipe $(if ($obj.pipe) { [string]$obj.pipe } else { '' }) `
            -Layout $(if ($obj.layout) { [string]$obj.layout } else { '3pane' }) `
            -Backend $(if ($obj.backend) { [string]$obj.backend } else { 'zellij' }) `
            -AiCli $(if ($obj.ai_cli) { [string]$obj.ai_cli } else { 'agy' }) `
            -AgentState $agentState `
            -AgentMessage $(if ($obj.agent_message) { [string]$obj.agent_message } else { '' }) `
            -StateTs $stateTs `
            -AttnTs $attnTs `
            -CreatedAt $(if ($obj.created_at) { [string]$obj.created_at } else { '' }) `
            -UpdatedAt $(if ($obj.updated_at) { [string]$obj.updated_at } else { '' }))
    } catch {
        return $null
    }
}

function Save-SessionState([System.Collections.IDictionary]$Meta) {
    $sessionName = [string]$Meta['session']
    $Meta['updated_at'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    if (-not $Meta['created_at']) {
        $Meta['created_at'] = $Meta['updated_at']
    }
    $json = ($Meta | ConvertTo-Json -Depth 6) + "`n"
    Write-TextUtf8NoBom -Path (Get-SessionStatePath $sessionName) -Content $json
    $sidecarStatePath = Join-Path (Get-IdeStateDir) "$sessionName.state"
    if ([System.IO.File]::Exists($sidecarStatePath)) {
        Remove-Item -LiteralPath $sidecarStatePath -Force -ErrorAction SilentlyContinue
    }
}

function Clear-IdeSessionArtifactSet([string]$SessionName) {
    $stateDir = Get-IdeStateDir
    if (-not (Test-Path -LiteralPath $stateDir -PathType Container)) { return }
    $exactFiles = @(
        "$SessionName.json",
        "$SessionName.state",
        "$SessionName.send.txt",
        "$SessionName.quit-check",
        "$SessionName.ai-active",
        "$SessionName.ai-shell",
        "$SessionName.pane-ai",
        "$SessionName.pane-editor",
        "$SessionName.pane-term",
        "launch-$SessionName-ai.ps1",
        "launch-$SessionName-editor.ps1",
        "launch-$SessionName-term.ps1",
        "monitor-$SessionName.pane",
        "monitor-$SessionName.lock",
        "keys-$SessionName.pane",
        "keys-$SessionName.lock",
        "sessions-$SessionName.pane",
        "sessions-$SessionName.lock",
        "modal-monitor-$SessionName.json",
        "modal-keys-$SessionName.json",
        "modal-sessions-$SessionName.json"
    )
    foreach ($artifact in $exactFiles) {
        $p = Join-Path $stateDir $artifact
        if ([System.IO.File]::Exists($p)) {
            Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
        }
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
    $curZellij = Get-CurrentZellijSessionToken
    if ($curZellij) { return $curZellij }
    if ($env:IDE_SESSION -and $env:IDE_SESSION.Trim()) {
        return (Get-SanitizedToken $env:IDE_SESSION.Trim())
    }
    return (Get-SanitizedSessionName (Get-Location).ProviderPath)
}

function Get-ActiveThemeSlug {
    $userHome = Get-UserHomeDir
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

function Get-ActivePaletteMap([switch]$Reload) {
    if (-not $Reload -and $script:IdeCachedPalette) {
        return $script:IdeCachedPalette
    }
    $themeEnvPs1 = Join-Path (Join-Path (Join-Path (Get-UserHomeDir) '.cache') 'powershell') 'theme_env.ps1'
    if ([System.IO.File]::Exists($themeEnvPs1)) {
        try { . $themeEnvPs1 } catch { Write-Verbose "Theme env load skipped: $_" }
    }
    $esc = [char]27
    $script:IdeCachedPalette = @{
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
        MAGENTA = if ($env:_HS_HEX_MAGENTA) { $env:_HS_HEX_MAGENTA } else { '#D33682' }
        E_B01   = if ($env:_HS_ESC_BASE01)  { $env:_HS_ESC_BASE01 }  else { "${esc}[38;2;88;110;117m" }
        E_B0    = if ($env:_HS_ESC_BASE0)   { $env:_HS_ESC_BASE0 }   else { "${esc}[38;2;131;148;150m" }
        E_B1    = if ($env:_HS_ESC_BASE1)   { $env:_HS_ESC_BASE1 }   else { "${esc}[38;2;147;161;161m" }
        E_YLW   = if ($env:_HS_ESC_YELLOW)  { $env:_HS_ESC_YELLOW }  else { "${esc}[38;2;181;137;0m" }
        E_ORG   = if ($env:_HS_ESC_ORANGE)  { $env:_HS_ESC_ORANGE }  else { "${esc}[38;2;203;75;22m" }
        E_RED   = if ($env:_HS_ESC_RED)     { $env:_HS_ESC_RED }     else { "${esc}[38;2;220;50;47m" }
        E_GRN   = if ($env:_HS_ESC_GREEN)   { $env:_HS_ESC_GREEN }   else { "${esc}[38;2;133;153;0m" }
        E_BLU   = if ($env:_HS_ESC_BLUE)    { $env:_HS_ESC_BLUE }    else { "${esc}[38;2;38;139;210m" }
        E_CYN   = if ($env:_HS_ESC_CYAN)    { $env:_HS_ESC_CYAN }    else { "${esc}[38;2;42;161;152m" }
        E_MAG   = if ($env:_HS_ESC_MAGENTA) { $env:_HS_ESC_MAGENTA } else { "${esc}[38;2;211;54;130m" }
        E_RST   = "${esc}[0m"
    }
    return $script:IdeCachedPalette
}
