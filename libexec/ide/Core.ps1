# ==============================================================================
# Core.ps1 - Shared paths, session state, binary resolution, Zellij pipes & theme
# ==============================================================================

$script:IdeLibDir = $PSScriptRoot
$script:IdeRepoDir = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:IdeBinDir = Join-Path $script:IdeRepoDir 'bin'
$script:IdeEntryScript = Join-Path $script:IdeBinDir 'ide.ps1'
if (-not $script:IdeResolvedTools) {
    $script:IdeResolvedTools = @{}
}
$script:IdeCachedPalette = $null
$script:IdeCachedPaletteKey = ''

$script:DefaultSolarizedHex = @{
    BASE03  = '#002B36'
    BASE02  = '#073642'
    BASE01  = '#586E75'
    BASE00  = '#657B83'
    BASE0   = '#839496'
    BASE1   = '#93A1A1'
    BASE2   = '#EEE8D5'
    BASE3   = '#FDF6E3'
    YELLOW  = '#B58900'
    ORANGE  = '#CB4B16'
    RED     = '#DC322F'
    MAGENTA = '#D33682'
    VIOLET  = '#6C71C4'
    BLUE    = '#268BD2'
    CYAN    = '#2AA198'
    GREEN   = '#859900'
}

function Get-IdeLibDir {
    return $script:IdeLibDir
}

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
    if ($env:USERPROFILE -and $env:USERPROFILE.Trim()) { return $env:USERPROFILE.Trim() }
    return $HOME
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
    if (-not (Get-Command Get-IdeCustomSessionName -CommandType Function -ErrorAction SilentlyContinue)) {
        $hooksFile = Join-Path $script:IdeLibDir 'Hooks.ps1'
        if ([System.IO.File]::Exists($hooksFile)) {
            . $hooksFile
        }
    }
    if (Get-Command Get-IdeCustomSessionName -CommandType Function -ErrorAction SilentlyContinue) {
        $custom = Get-IdeCustomSessionName -TargetDir $TargetDir
        if ($custom -and $custom.Trim()) {
            return (Get-SanitizedToken $custom.Trim())
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

function Resolve-IdeToolBinary([string[]]$CandidateNames, [string]$MiseTool = '', [string]$BinaryFilter = '', [string]$EnvOverride = '') {
    if ($EnvOverride) {
        $ovrVal = [Environment]::GetEnvironmentVariable($EnvOverride)
        if ($ovrVal -and $ovrVal.Trim()) {
            $trimmedOvr = $ovrVal.Trim()
            if ([System.IO.File]::Exists($trimmedOvr)) {
                return $trimmedOvr
            }
            $ovrCmd = Get-Command $trimmedOvr -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ovrCmd -and $ovrCmd.Source) {
                return $ovrCmd.Source
            }
        }
    }

    $cacheKey = "$($CandidateNames -join ',')|$MiseTool|$($env:Path)"
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

function Resolve-FzfExecutable {
    return (Resolve-IdeToolBinary -CandidateNames @('fzf.exe', 'fzf') -MiseTool 'fzf' -BinaryFilter 'fzf.exe' -EnvOverride 'IDE_FZF_BIN')
}

function Resolve-ZoxideExecutable {
    return (Resolve-IdeToolBinary -CandidateNames @('zoxide.exe', 'zoxide') -MiseTool 'zoxide' -BinaryFilter 'zoxide.exe' -EnvOverride 'IDE_ZOXIDE_BIN')
}

function Resolve-ValidatedAiCliName([string]$RequestedCli, [bool]$FromFlag = $false) {
    $cli = if ($RequestedCli -and $RequestedCli.Trim()) { $RequestedCli.Trim() } else { 'agy' }
    if ($cli -eq 'openai') { $cli = 'codex' }
    if ($cli -in @('agy', 'claude', 'codex')) {
        return $cli
    }
    if (-not $FromFlag -and $cli.ToLowerInvariant() -in @('none', 'shell', 'pwsh')) {
        return 'shell'
    }
    if ([System.IO.File]::Exists($cli)) {
        return $cli
    }
    $found = Get-Command $cli -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found -and $found.Source) {
        return $cli
    }
    if (-not $FromFlag) {
        foreach ($fb in @('agy', 'claude', 'codex')) {
            $fbHit = Get-Command $fb -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($fbHit) { return $fb }
        }
        return 'agy'
    }
    return ''
}

function Resolve-AiExecutable([string]$RequestedCli, [bool]$AllowFallback = $true) {
    $cli = if ($RequestedCli -and $RequestedCli.Trim()) { $RequestedCli.Trim() } else { 'agy' }
    if ($cli.ToLowerInvariant() -in @('none', 'shell', 'pwsh')) {
        return @{ Name = 'shell'; Path = '' }
    }
    if ($cli -eq 'openai') { $cli = 'codex' }
    if ([System.IO.File]::Exists($cli)) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($cli)
        return @{ Name = $stem; Path = (Resolve-Path -LiteralPath $cli).ProviderPath }
    }

    $directHit = Get-Command $cli -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($directHit) {
        return @{ Name = $cli; Path = $directHit.Source }
    }
    if ($AllowFallback) {
        foreach ($fb in @('agy', 'claude', 'codex')) {
            if ($fb -eq $cli) { continue }
            $hit = Get-Command $fb -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) {
                return @{ Name = $fb; Path = $hit.Source }
            }
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
    [string]$PrevWorkdir = '',
    [string]$Pipe = '',
    [string]$Layout = '3pane',
    [string]$Backend = 'zellij',
    [string]$AiCli = '',
    [string]$AgentState = 'idle',
    [string]$AgentMessage = '',
    [long]$StateTs = 0L,
    [long]$AttnTs = 0L,
    [string]$QuitError = '',
    [string]$CreatedAt = '',
    [string]$UpdatedAt = ''
) {
    $resolvedPipe = if ($Pipe) { $Pipe } else { Get-SessionPipePath $SessionName }
    $resolvedAi = if ($AiCli) { $AiCli } elseif ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
    return [ordered]@{
        session       = $SessionName
        root          = $Root
        workdir       = $Workdir
        prev_workdir  = $PrevWorkdir
        pipe          = $resolvedPipe
        layout        = if ($Layout) { $Layout } else { '3pane' }
        backend       = if ($Backend) { $Backend } else { 'zellij' }
        ai_cli        = $resolvedAi
        agent_state   = if ($AgentState) { $AgentState } else { 'idle' }
        agent_message = $AgentMessage
        state_ts      = $StateTs
        attn_ts       = $AttnTs
        quit_error    = $QuitError
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
        $prevWd = if ($obj.PSObject.Properties['prev_workdir'] -and $obj.prev_workdir) { [string]$obj.prev_workdir } else { '' }
        $quitErr = if ($obj.PSObject.Properties['quit_error'] -and $obj.quit_error) { [string]$obj.quit_error } else { '' }
        return (Build-IdeSessionRecord `
            -SessionName $(if ($obj.session) { [string]$obj.session } else { $SessionName }) `
            -Root $(if ($obj.root) { [string]$obj.root } else { '' }) `
            -Workdir $(if ($obj.workdir) { [string]$obj.workdir } else { '' }) `
            -PrevWorkdir $prevWd `
            -Pipe $(if ($obj.pipe) { [string]$obj.pipe } else { '' }) `
            -Layout $(if ($obj.layout) { [string]$obj.layout } else { '3pane' }) `
            -Backend $(if ($obj.backend) { [string]$obj.backend } else { 'zellij' }) `
            -AiCli $(if ($obj.ai_cli) { [string]$obj.ai_cli } else { 'agy' }) `
            -AgentState $agentState `
            -AgentMessage $(if ($obj.agent_message) { [string]$obj.agent_message } else { '' }) `
            -StateTs $stateTs `
            -AttnTs $attnTs `
            -QuitError $quitErr `
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
        "$SessionName.ai-supervisor",
        "$SessionName.ai-switch",
        "$SessionName.pane-ai",
        "$SessionName.pane-editor",
        "$SessionName.pane-term",
        "launch-$SessionName-ai.ps1",
        "launch-$SessionName-editor.ps1",
        "launch-$SessionName-term.ps1"
    )
    foreach ($mName in @('monitor', 'keys', 'sessions', 'new', 'dir', 'agent')) {
        $exactFiles += "${mName}-${SessionName}.pane"
        $exactFiles += "${mName}-${SessionName}.lock"
        $exactFiles += "modal-${mName}-${SessionName}.json"
    }
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
    if ($env:IDE_ORIGIN_SESSION -and $env:IDE_ORIGIN_SESSION.Trim()) {
        return (Get-SanitizedToken $env:IDE_ORIGIN_SESSION.Trim())
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

function Get-IdeColorTier {
    if ($env:NO_COLOR) { return 'nocolor' }
    $term = if ($env:TERM) { $env:TERM.Trim().ToLowerInvariant() } else { '' }
    if ($term -eq 'dumb') { return 'mono' }
    $ct = if ($env:COLORTERM) { $env:COLORTERM.Trim().ToLowerInvariant() } else { '' }
    if ($ct -in @('truecolor', '24bit')) { return 'truecolor' }
    if ($ct -in @('256color', '8bit')) { return '256color' }
    if ($ct -in @('16color', 'ansi', '4bit')) { return '16color' }
    if (-not $term -or $term -in @('xterm-256color', 'tmux-256color', 'xterm-ghostty', 'xterm-kitty', 'wezterm', 'alacritty') -or $term.StartsWith('foot')) {
        return 'truecolor'
    }
    if ($term.Contains('256')) { return '256color' }
    return '16color'
}

function Test-IdeNerdFont {
    $nf = if ($env:IDE_NERD_FONTS) { $env:IDE_NERD_FONTS.Trim().ToLowerInvariant() } else { '' }
    if ($nf -in @('0', 'false', 'off', 'no', 'ascii')) { return $false }
    $asc = if ($env:IDE_ASCII) { $env:IDE_ASCII.Trim().ToLowerInvariant() } else { '' }
    if ($asc -in @('1', 'true', 'on', 'yes')) { return $false }
    $term = if ($env:TERM) { $env:TERM.Trim().ToLowerInvariant() } else { '' }
    if ($term -eq 'dumb') { return $false }
    return $true
}

function Test-IdeReduceMotion {
    foreach ($v in @($env:NO_MOTION, $env:REDUCE_MOTION)) {
        if ($v -and $v.Trim() -and $v.Trim().ToLowerInvariant() -notin @('0', 'false', 'off', 'no')) {
            return $true
        }
    }
    return $false
}

function ConvertFrom-RgbToAnsi256([int]$R, [int]$G, [int]$B) {
    $steps = @(0, 95, 135, 175, 215, 255)
    $bestIdx = @(0, 0, 0)
    $channels = @($R, $G, $B)
    for ($c = 0; $c -lt 3; $c++) {
        $bestD = 999
        for ($i = 0; $i -lt 6; $i++) {
            $d = [Math]::Abs($channels[$c] - $steps[$i])
            if ($d -lt $bestD) {
                $bestD = $d
                $bestIdx[$c] = $i
            }
        }
    }
    $cr = $steps[$bestIdx[0]]
    $cg = $steps[$bestIdx[1]]
    $cb = $steps[$bestIdx[2]]
    $cubeDist = (($R - $cr) * ($R - $cr)) + (($G - $cg) * ($G - $cg)) + (($B - $cb) * ($B - $cb))
    $cubeCode = 16 + (36 * $bestIdx[0]) + (6 * $bestIdx[1]) + $bestIdx[2]

    $avg = [int][Math]::Floor(($R + $G + $B) / 3.0)
    $grayStep = if ($avg -le 8) { 0 } elseif ($avg -ge 238) { 23 } else { [int][Math]::Round(($avg - 8) / 10.0) }
    $gv = 8 + (10 * $grayStep)
    $grayDist = (($R - $gv) * ($R - $gv)) + (($G - $gv) * ($G - $gv)) + (($B - $gv) * ($B - $gv))
    if ($grayDist -lt $cubeDist) {
        return (232 + $grayStep)
    }
    return $cubeCode
}

function ConvertFrom-HexToSgrFg([string]$HexCode, [string]$Tier = 'truecolor', [string]$RoleKey = '') {
    $esc = [char]27
    if ($Tier -eq 'nocolor') { return '' }
    if ($Tier -eq 'mono') {
        return $(switch ($RoleKey) {
            'BASE02'  { "${esc}[7m" }
            'BASE01'  { "${esc}[2m" }
            'BASE00'  { "${esc}[2m" }
            'BASE1'   { "${esc}[1m" }
            'BASE2'   { "${esc}[1m" }
            'BASE3'   { "${esc}[1m" }
            'YELLOW'  { "${esc}[1m" }
            'ORANGE'  { "${esc}[1m" }
            'RED'     { "${esc}[1;7m" }
            'MAGENTA' { "${esc}[4m" }
            'VIOLET'  { "${esc}[4m" }
            'BLUE'    { "${esc}[1m" }
            'CYAN'    { "${esc}[4m" }
            default   { '' }
        })
    }
    if ($Tier -eq '16color') {
        return $(switch ($RoleKey) {
            'BASE03'  { "${esc}[30m" }
            'BASE02'  { "${esc}[90m" }
            'BASE01'  { "${esc}[90m" }
            'BASE00'  { "${esc}[37m" }
            'BASE0'   { "${esc}[37m" }
            'BASE1'   { "${esc}[97m" }
            'BASE2'   { "${esc}[97m" }
            'BASE3'   { "${esc}[97m" }
            'YELLOW'  { "${esc}[33m" }
            'ORANGE'  { "${esc}[91m" }
            'RED'     { "${esc}[31m" }
            'MAGENTA' { "${esc}[35m" }
            'VIOLET'  { "${esc}[95m" }
            'BLUE'    { "${esc}[34m" }
            'CYAN'    { "${esc}[36m" }
            'GREEN'   { "${esc}[32m" }
            default   { '' }
        })
    }
    $clean = if ($HexCode) { $HexCode.Trim().TrimStart('#') } else { '' }
    if ($clean.Length -ne 6) { return '' }
    try {
        $r = [Convert]::ToInt32($clean.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($clean.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($clean.Substring(4, 2), 16)
    } catch {
        return ''
    }
    if ($Tier -eq '256color') {
        return "${esc}[38;5;$(ConvertFrom-RgbToAnsi256 -R $r -G $g -B $b)m"
    }
    return "${esc}[38;2;${r};${g};${b}m"
}

function Get-ActivePaletteMap([switch]$Reload) {
    $tier = Get-IdeColorTier
    $userHome = Get-UserHomeDir
    $cfgBase = if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        $env:XDG_CONFIG_HOME.Trim()
    } else {
        Join-Path $userHome '.config'
    }
    $activeThemeFile = Join-Path (Join-Path $cfgBase 'windows-settings') 'active-theme.theme'
    if (-not [System.IO.File]::Exists($activeThemeFile)) {
        $altFile = Join-Path (Join-Path $cfgBase 'home-settings') 'active-theme.theme'
        if ([System.IO.File]::Exists($altFile)) { $activeThemeFile = $altFile }
    }
    $mtimeTicks = if ([System.IO.File]::Exists($activeThemeFile)) {
        [System.IO.File]::GetLastWriteTimeUtc($activeThemeFile).Ticks
    } else {
        -1L
    }
    $cacheKey = "$activeThemeFile|$mtimeTicks|$tier"
    if (-not $Reload -and $null -ne $script:IdeCachedPalette -and $script:IdeCachedPaletteKey -eq $cacheKey) {
        return $script:IdeCachedPalette
    }

    $themeEnvPs1 = Join-Path (Join-Path (Join-Path $userHome '.cache') 'powershell') 'theme_env.ps1'
    if ([System.IO.File]::Exists($themeEnvPs1)) {
        try { . $themeEnvPs1 } catch { Write-Verbose "Theme env load skipped: $_" }
    }

    $hexMap = @{}
    foreach ($kv in $script:DefaultSolarizedHex.GetEnumerator()) {
        $hexMap[$kv.Key] = $kv.Value
    }
    if ($mtimeTicks -ge 0) {
        try {
            foreach ($rawLine in [System.IO.File]::ReadAllLines($activeThemeFile)) {
                $s = $rawLine.Trim()
                if ($s -match '^([A-Z0-9_]+)="?(#[0-9A-Fa-f]{6})"?$') {
                    $k = $Matches[1]
                    if ($hexMap.ContainsKey($k)) {
                        $hexMap[$k] = $Matches[2].ToUpperInvariant()
                    }
                }
            }
        } catch {
            Write-Verbose "Active theme parse skipped: $_"
        }
    }

    $esc = [char]27
    $script:IdeCachedPalette = @{
        TIER    = $tier
        BASE03  = $hexMap['BASE03']
        BASE02  = $hexMap['BASE02']
        BASE01  = $hexMap['BASE01']
        BASE00  = $hexMap['BASE00']
        BASE0   = $hexMap['BASE0']
        BASE1   = $hexMap['BASE1']
        YELLOW  = $hexMap['YELLOW']
        ORANGE  = $hexMap['ORANGE']
        RED     = $hexMap['RED']
        GREEN   = $hexMap['GREEN']
        BLUE    = $hexMap['BLUE']
        CYAN    = $hexMap['CYAN']
        MAGENTA = $hexMap['MAGENTA']
        VIOLET  = $hexMap['VIOLET']
        E_B03   = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE03']  -Tier $tier -RoleKey 'BASE03'
        E_B02   = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE02']  -Tier $tier -RoleKey 'BASE02'
        E_B01   = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE01']  -Tier $tier -RoleKey 'BASE01'
        E_B00   = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE00']  -Tier $tier -RoleKey 'BASE00'
        E_B0    = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE0']   -Tier $tier -RoleKey 'BASE0'
        E_B1    = ConvertFrom-HexToSgrFg -HexCode $hexMap['BASE1']   -Tier $tier -RoleKey 'BASE1'
        E_YLW   = ConvertFrom-HexToSgrFg -HexCode $hexMap['YELLOW']  -Tier $tier -RoleKey 'YELLOW'
        E_ORG   = ConvertFrom-HexToSgrFg -HexCode $hexMap['ORANGE']  -Tier $tier -RoleKey 'ORANGE'
        E_RED   = ConvertFrom-HexToSgrFg -HexCode $hexMap['RED']     -Tier $tier -RoleKey 'RED'
        E_GRN   = ConvertFrom-HexToSgrFg -HexCode $hexMap['GREEN']   -Tier $tier -RoleKey 'GREEN'
        E_BLU   = ConvertFrom-HexToSgrFg -HexCode $hexMap['BLUE']    -Tier $tier -RoleKey 'BLUE'
        E_CYN   = ConvertFrom-HexToSgrFg -HexCode $hexMap['CYAN']    -Tier $tier -RoleKey 'CYAN'
        E_MAG   = ConvertFrom-HexToSgrFg -HexCode $hexMap['MAGENTA'] -Tier $tier -RoleKey 'MAGENTA'
        E_VIO   = ConvertFrom-HexToSgrFg -HexCode $hexMap['VIOLET']  -Tier $tier -RoleKey 'VIOLET'
        E_RST   = if ($tier -eq 'nocolor') { '' } else { "${esc}[0m" }
    }
    $script:IdeCachedPaletteKey = $cacheKey
    return $script:IdeCachedPalette
}

function Get-IdeStateColor([string]$State, [hashtable]$Pal) {
    return $(switch ($State) {
        'ATTN'    { $Pal.E_ORG }
        'ERROR'   { $Pal.E_RED }
        'QUOTA'   { $Pal.E_YLW }
        'WORKING' { $Pal.E_CYN }
        'DONE'    { $Pal.E_GRN }
        'IDLE'    { $Pal.E_B0 }
        default   { $Pal.E_B01 }
    })
}

function Format-FzfPaletteOption([hashtable]$Pal) {
    $tier = if ($Pal.TIER) { [string]$Pal.TIER } else { Get-IdeColorTier }
    if ($tier -eq 'nocolor') { return '--no-color' }
    if ($tier -eq 'mono') { return '--color=bw' }
    if ($tier -eq '16color') { return '--color=16' }
    $spinHex = if (Test-IdeReduceMotion) { $Pal.BASE03 } else { $Pal.CYAN }
    return "--color=bg+:$($Pal.BASE02),bg:$($Pal.BASE03),preview-bg:$($Pal.BASE03),gutter:$($Pal.BASE03),spinner:$spinHex,hl:$($Pal.BASE01),fg:$($Pal.BASE0),header:$($Pal.BASE01),border:$($Pal.BASE01),separator:$($Pal.BASE01),label:$($Pal.BASE01),info:$($Pal.YELLOW),pointer:$($Pal.GREEN),marker:$($Pal.GREEN),fg+:$($Pal.BASE1),prompt:$($Pal.YELLOW),hl+:$($Pal.BLUE)"
}

function Get-IdeCharCellWidth([int]$CodePoint) {
    if ($CodePoint -lt 0x20 -or ($CodePoint -ge 0x7F -and $CodePoint -lt 0xA0)) { return 0 }
    if ($CodePoint -lt 0x7F) { return 1 }
    if (($CodePoint -ge 0xE000 -and $CodePoint -le 0xF8FF) -or ($CodePoint -ge 0xF0000 -and $CodePoint -le 0x10FFFF)) {
        return 1
    }
    if (($CodePoint -ge 0x0300 -and $CodePoint -le 0x036F) -or
        ($CodePoint -ge 0xFE00 -and $CodePoint -le 0xFE0F) -or
        $CodePoint -in @(0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF)) {
        return 0
    }
    if ($CodePoint -ge 0x1F300 -or
        ($CodePoint -ge 0x1100 -and $CodePoint -le 0x115F) -or
        ($CodePoint -ge 0x2E80 -and $CodePoint -le 0xA4CF) -or
        ($CodePoint -ge 0xAC00 -and $CodePoint -le 0xD7A3) -or
        ($CodePoint -ge 0xF900 -and $CodePoint -le 0xFAFF) -or
        ($CodePoint -ge 0xFE10 -and $CodePoint -le 0xFE6F) -or
        ($CodePoint -ge 0xFF00 -and $CodePoint -le 0xFF60) -or
        ($CodePoint -ge 0x20000 -and $CodePoint -le 0x3FFFD)) {
        return 2
    }
    return 1
}

function Format-IdePlainText([string]$Text) {
    if (-not $Text) { return '' }
    $esc = [char]27
    $bel = [char]7
    $csi = [char]0x9B
    $clean = [regex]::Replace($Text, "${esc}\][^\x07\x1b]*(?:${bel}|${esc}\\)", '')
    $clean = [regex]::Replace($clean, "(?:${esc}\[|${csi})[0-9;:?]*[ -/]*[@-~]", '')
    return $clean
}

function Get-IdeVisibleWidth([string]$Text) {
    if (-not $Text) { return 0 }
    $clean = Format-IdePlainText $Text
    $sum = 0
    foreach ($rune in $clean.EnumerateRunes()) {
        $sum += Get-IdeCharCellWidth $rune.Value
    }
    return $sum
}

function Format-IdePadVisible([string]$Text, [int]$Width) {
    $vis = Get-IdeVisibleWidth $Text
    $pad = [Math]::Max(0, $Width - $vis)
    return ($Text + (' ' * $pad))
}

function Format-IdeTruncVisible([string]$Text, [int]$MaxWidth, [string]$Suffix = "`u{2026}") {
    if ($MaxWidth -le 0) { return '' }
    if ((Get-IdeVisibleWidth $Text) -le $MaxWidth) { return $Text }
    $sfxW = Get-IdeVisibleWidth $Suffix
    $budget = [Math]::Max(0, $MaxWidth - $sfxW)
    $sb = [System.Text.StringBuilder]::new()
    $used = 0
    $clean = Format-IdePlainText $Text
    foreach ($rune in $clean.EnumerateRunes()) {
        $cw = Get-IdeCharCellWidth $rune.Value
        if ($used + $cw -gt $budget) { break }
        [void]$sb.Append($rune.ToString())
        $used += $cw
    }
    [void]$sb.Append($Suffix)
    return $sb.ToString()
}

function Format-IdeShortHome([string]$PathValue) {
    if (-not $PathValue) { return '-' }
    $userHome = Get-UserHomeDir
    $normHome = if ($userHome) { $userHome.TrimEnd('\', '/') } else { '' }
    if ($normHome) {
        if ([string]::Equals($PathValue.TrimEnd('\', '/'), $normHome, [System.StringComparison]::OrdinalIgnoreCase)) {
            return '~'
        }
        if ($PathValue.StartsWith($normHome + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
            $PathValue.StartsWith($normHome + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
            return ('~' + $PathValue.Substring($normHome.Length))
        }
    }
    return $PathValue
}

function Format-IdeCardFooter([string[]]$Hints, [int]$InnerWidth) {
    $sep = " `u{00B7} "
    $budget = [Math]::Max(10, $InnerWidth - 4)
    $chosen = [System.Collections.Generic.List[string]]::new()
    foreach ($h in $Hints) {
        $candList = @($chosen) + @($h)
        $candStr = ' ' + ($candList -join $sep) + ' '
        if ((Get-IdeVisibleWidth $candStr) -le $budget -or $chosen.Count -eq 0) {
            $chosen.Add($h)
        }
    }
    $out = ' ' + ($chosen -join $sep) + ' '
    if ((Get-IdeVisibleWidth $out) -gt $budget) {
        return (' ' + (Format-IdeTruncVisible ($chosen -join $sep) ([Math]::Max(1, $budget - 2))) + ' ')
    }
    return $out
}

function Get-IdeTerminalSize {
    $cols = 120
    $rows = 36
    $parsedC = 0
    $parsedR = 0
    if ($env:COLUMNS -and [int]::TryParse($env:COLUMNS.Trim(), [ref]$parsedC) -and $parsedC -gt 0) {
        $cols = $parsedC
    } else {
        try {
            if ([Console]::WindowWidth -gt 0) { $cols = [Console]::WindowWidth }
        } catch { Write-Verbose 'WindowWidth unavailable' }
    }
    if ($env:LINES -and [int]::TryParse($env:LINES.Trim(), [ref]$parsedR) -and $parsedR -gt 0) {
        $rows = $parsedR
    } else {
        try {
            if ([Console]::WindowHeight -gt 0) { $rows = [Console]::WindowHeight }
        } catch { Write-Verbose 'WindowHeight unavailable' }
    }
    return @{ Columns = $cols; Rows = $rows }
}
