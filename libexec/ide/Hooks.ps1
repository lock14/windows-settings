# ==============================================================================
# Hooks.ps1 - Untracked user workspace/link/notification/VCS hooks (links.ps1)
# ==============================================================================

$script:IdeHookFileCache = @{}

function Get-IdeRulesPath {
    if ($env:IDE_LINK_RULES -and $env:IDE_LINK_RULES.Trim()) {
        return $env:IDE_LINK_RULES.Trim()
    }
    $userHome = Get-UserHomeDir
    $cfgBase = if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        $env:XDG_CONFIG_HOME.Trim()
    } else {
        Join-Path $userHome '.config'
    }
    $primary = Join-Path (Join-Path $cfgBase 'ide') 'links.ps1'
    if ([System.IO.File]::Exists($primary)) {
        return $primary
    }
    $alt = Join-Path (Join-Path (Join-Path $cfgBase 'windows-settings') 'ide') 'links.ps1'
    if ([System.IO.File]::Exists($alt)) {
        return $alt
    }
    return $primary
}

function Test-IdeHookDefined([string]$FnName) {
    if (-not $FnName) { return $false }
    $rulesPath = Get-IdeRulesPath
    if (-not $rulesPath -or -not [System.IO.File]::Exists($rulesPath)) {
        return $false
    }
    try {
        $mtime = [System.IO.File]::GetLastWriteTimeUtc($rulesPath).Ticks
        $cacheKey = "$rulesPath|$mtime"
        if (-not $script:IdeHookFileCache.ContainsKey($cacheKey)) {
            $script:IdeHookFileCache[$cacheKey] = [System.IO.File]::ReadAllText($rulesPath)
        }
        $raw = $script:IdeHookFileCache[$cacheKey]
        return ($raw -match "(?im)^\s*function\s+$([regex]::Escape($FnName))\b")
    } catch {
        return $false
    }
}

function Invoke-IdeHookFunction([string]$FnName, [string[]]$HookArgs = @(), [int]$TimeoutMs = 1000) {
    if (-not (Test-IdeHookDefined $FnName)) {
        return ''
    }
    $rulesPath = Get-IdeRulesPath
    $pwshBin = Get-CurrentPwshExecutable
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshBin)
        $runner = '. $env:WS_IDE_HOOK_SCRIPT; if (Get-Command $env:WS_IDE_HOOK_FN -CommandType Function -ErrorAction SilentlyContinue) { $cnt = [int]$env:WS_IDE_HOOK_ARGC; $hArgs = @(); for ($i = 0; $i -lt $cnt; $i++) { $hArgs += [Environment]::GetEnvironmentVariable("WS_IDE_HOOK_ARG_$i") }; & $env:WS_IDE_HOOK_FN @hArgs }'
        foreach ($item in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $runner)) {
            $psi.ArgumentList.Add($item)
        }
        $psi.Environment['WS_IDE_HOOK_SCRIPT'] = $rulesPath
        $psi.Environment['WS_IDE_HOOK_FN'] = $FnName
        $psi.Environment['WS_IDE_HOOK_ARGC'] = "$($HookArgs.Count)"
        for ($hIdx = 0; $hIdx -lt $HookArgs.Count; $hIdx++) {
            $psi.Environment["WS_IDE_HOOK_ARG_$hIdx"] = [string]$HookArgs[$hIdx]
        }
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) { return '' }
        try { $proc.StandardInput.Close() } catch { Write-Verbose 'Hook stdin close skipped' }
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutMs)) {
            try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out hook process terminated' }
            return ''
        }
        if ($proc.ExitCode -ne 0) { return '' }
        $stdout = if ($outTask.Wait(250)) { $outTask.Result } else { '' }
        return $(if ($stdout) { $stdout.Trim() } else { '' })
    } catch {
        return ''
    }
}

function Get-IdeWorkspaceParent {
    if ($env:IDE_WORKSPACE_PARENT -and $env:IDE_WORKSPACE_PARENT.Trim()) {
        $raw = $env:IDE_WORKSPACE_PARENT.Trim()
        if ($raw -eq '~') { return (Get-UserHomeDir) }
        if ($raw.StartsWith('~\') -or $raw.StartsWith('~/')) {
            $raw = Join-Path (Get-UserHomeDir) $raw.Substring(2)
        }
        return [System.IO.Path]::GetFullPath($raw)
    }
    return [System.IO.Path]::GetFullPath((Get-UserHomeDir))
}

function Expand-IdeUserPath([string]$RawPath) {
    if (-not $RawPath -or -not $RawPath.Trim()) { return '' }
    $s = $RawPath.Trim()
    if ($s -eq '~') { return [System.IO.Path]::GetFullPath((Get-UserHomeDir)) }
    if ($s.StartsWith('~\') -or $s.StartsWith('~/')) {
        return [System.IO.Path]::GetFullPath((Join-Path (Get-UserHomeDir) $s.Substring(2)))
    }
    return [System.IO.Path]::GetFullPath($s)
}

function Get-ChildDirectoryNameSet([string]$ParentDir, [hashtable]$Cache) {
    if (-not $ParentDir) { return $null }
    $normKey = $ParentDir.TrimEnd('\', '/').ToLowerInvariant()
    if ($null -ne $Cache -and $Cache.ContainsKey($normKey)) {
        return $Cache[$normKey]
    }
    $set = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        if ([System.IO.Directory]::Exists($ParentDir)) {
            foreach ($dirPath in [System.IO.Directory]::EnumerateDirectories($ParentDir)) {
                $leaf = [System.IO.Path]::GetFileName($dirPath.TrimEnd('\', '/'))
                if ($leaf) { [void]$set.Add($leaf) }
            }
        }
    } catch {
        Write-Verbose "Directory enumeration skipped for ${ParentDir}: $_"
    }
    if ($null -ne $Cache) {
        $Cache[$normKey] = $set
    }
    return $set
}

function Get-ConfiguredIdeWorkspaceRootSet([hashtable]$ParentCache = $null, [bool]$IncludeHook = $true) {
    $cache = if ($null -ne $ParentCache) { $ParentCache } else { @{} }
    $rawCandidates = [System.Collections.Generic.List[string]]::new()
    if ($IncludeHook) {
        $hookOut = Invoke-IdeHookFunction -FnName 'Get-IdeWorkspaceDirs' -TimeoutMs 1000
        if ($hookOut) {
            foreach ($ln in ($hookOut -split "`r?`n")) {
                if ($ln -and $ln.Trim()) { $rawCandidates.Add($ln.Trim()) }
            }
        }
    }
    if ($env:IDE_WORKSPACE_DIRS -and $env:IDE_WORKSPACE_DIRS.Trim()) {
        # Split strictly on PathSeparator (;) and newlines; NEVER split on ':' because of Windows drive letters (C:\).
        $sepChars = [char[]]@([System.IO.Path]::PathSeparator, "`r", "`n")
        foreach ($part in $env:IDE_WORKSPACE_DIRS.Split($sepChars, [System.StringSplitOptions]::RemoveEmptyEntries)) {
            if ($part.Trim()) { $rawCandidates.Add($part.Trim()) }
        }
    }

    $roots = [System.Collections.Generic.List[string]]::new()
    $seenRoots = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $managedParents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($raw in $rawCandidates) {
        try {
            $norm = (Expand-IdeUserPath $raw).TrimEnd('\', '/')
        } catch {
            continue
        }
        if (-not $norm -or $seenRoots.Contains($norm)) { continue }
        $parent = [System.IO.Path]::GetDirectoryName($norm)
        $leaf = [System.IO.Path]::GetFileName($norm)
        if ($parent -and $leaf -and $parent -ne $norm) {
            [void]$managedParents.Add($parent.TrimEnd('\', '/'))
            $childSet = Get-ChildDirectoryNameSet -ParentDir $parent -Cache $cache
            if ($null -eq $childSet -or -not $childSet.Contains($leaf)) {
                continue
            }
        } elseif (-not [System.IO.Directory]::Exists($norm)) {
            continue
        }
        [void]$seenRoots.Add($norm)
        $roots.Add($norm)
    }

    return @{
        Roots          = $roots.ToArray()
        ManagedParents = $managedParents
        ParentCache    = $cache
    }
}

function Resolve-IdeWorkspaceTarget([string]$RawTarget) {
    if (-not $RawTarget -or -not $RawTarget.Trim()) { return '' }
    $clean = $RawTarget.Trim()
    if ($clean -in @('.', '..') -or $clean.StartsWith('./') -or $clean.StartsWith('.\') -or $clean.StartsWith('../') -or $clean.StartsWith('..\')) {
        return ''
    }

    $hookResolved = Invoke-IdeHookFunction -FnName 'Resolve-IdeWorkspace' -HookArgs @($clean) -TimeoutMs 1000
    if ($hookResolved) {
        foreach ($ln in ($hookResolved -split "`r?`n")) {
            if ($ln -and $ln.Trim()) {
                $exp = Expand-IdeUserPath $ln.Trim()
                if ([System.IO.Directory]::Exists($exp)) {
                    return (Resolve-Path -LiteralPath $exp).ProviderPath
                }
                break
            }
        }
    }

    if ([System.IO.Path]::IsPathRooted($clean) -or $clean.StartsWith('~')) {
        return ''
    }
    $normRel = $clean.Replace('/', '\').TrimEnd('\')
    if (-not $normRel) { return '' }
    $segs = @($normRel -split '\\' | Where-Object { $_ -ne '' })
    if ($segs.Count -eq 0 -or $segs[0] -in @('.', '..') -or ($segs -contains '..')) {
        return ''
    }

    $head = $segs[0]
    $tail = if ($segs.Count -gt 1) { ($segs[1..($segs.Count - 1)] -join [System.IO.Path]::DirectorySeparatorChar) } else { '' }
    $wsInfo = Get-ConfiguredIdeWorkspaceRootSet
    foreach ($wsRoot in $wsInfo.Roots) {
        $wsLeaf = [System.IO.Path]::GetFileName($wsRoot.TrimEnd('\', '/'))
        if ([string]::Equals($wsLeaf, $head, [System.StringComparison]::OrdinalIgnoreCase)) {
            if (-not $tail) {
                $mountOut = Invoke-IdeHookFunction -FnName 'Resolve-IdeWorkspace' -HookArgs @($wsRoot) -TimeoutMs 1000
                if ($mountOut) {
                    $mFirst = @($mountOut -split "`r?`n" | Where-Object { $_ -and $_.Trim() }) | Select-Object -First 1
                    if ($mFirst) {
                        $mExp = Expand-IdeUserPath $mFirst.Trim()
                        if ([System.IO.Directory]::Exists($mExp)) {
                            return (Resolve-Path -LiteralPath $mExp).ProviderPath
                        }
                    }
                }
                return $wsRoot
            }
            $joined = Join-Path $wsRoot $tail
            if ([System.IO.Directory]::Exists($joined)) {
                return (Resolve-Path -LiteralPath $joined).ProviderPath
            }
            return ''
        }
    }
    return ''
}

function Get-IdeCustomSessionName([string]$TargetDir) {
    if (-not $TargetDir) { return '' }
    return (Invoke-IdeHookFunction -FnName 'Get-IdeSessionName' -HookArgs @($TargetDir) -TimeoutMs 1000)
}

function Invoke-IdeResolveLinkHook([string]$Word, [string]$Cwd) {
    if (-not $Word) { return '' }
    return (Invoke-IdeHookFunction -FnName 'Resolve-IdeLink' -HookArgs @($Word, $Cwd) -TimeoutMs 1000)
}

function Invoke-IdeVcsSummaryHook([string]$Workdir) {
    if (-not $Workdir) { return $null }
    $raw = Invoke-IdeHookFunction -FnName 'Get-IdeVcsSummary' -HookArgs @($Workdir) -TimeoutMs 400
    if (-not $raw) { return $null }
    $firstLine = @($raw -split "`r?`n" | Where-Object { $_ -and $_.Trim() }) | Select-Object -First 1
    if (-not $firstLine -or -not $firstLine.Contains('|')) { return $null }
    $parts = $firstLine.Split('|', 4)
    $branch = if ($parts[0].Trim()) { $parts[0].Trim() } else { '-' }
    $dirty = if ($parts.Count -gt 1) { $parts[1].Trim().ToLowerInvariant() -in @('1', 'true', 'yes', 'dirty', '*') } else { $false }
    $detail = if ($parts.Count -gt 2 -and $parts[2].Trim()) {
        $parts[2].Trim()
    } elseif ($dirty) {
        "$branch (modified)"
    } else {
        "$branch (clean)"
    }
    $prUrl = if ($parts.Count -gt 3 -and $parts[3].Trim() -match '^https?://\S+$') { $parts[3].Trim() } else { '' }
    return @{
        Branch = $branch
        Dirty  = $dirty
        Detail = $detail
        PrUrl  = $prUrl
    }
}

function Send-IdeAgentNotification(
    [string]$State,
    [string]$Session,
    [string]$Agent,
    [string]$Workdir,
    [string]$Message
) {
    $effCli = if ($Agent) { $Agent } else { 'agy' }
    $dot = "`u{00B7}"
    $title = if ($State -eq 'approval') { "IDE [$Session] $dot Approval needed" } else { "IDE [$Session] $dot Turn complete" }
    $body = if ($Message -and $Message.Trim()) {
        $Message.Trim()
    } elseif ($State -eq 'approval') {
        "$effCli is waiting for input in $Session"
    } else {
        "$effCli finished turn in $Session"
    }

    if (Test-IdeHookDefined 'Send-IdeNotification') {
        $rulesPath = Get-IdeRulesPath
        $pwshBin = Get-CurrentPwshExecutable
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshBin)
            $runner = '. $env:WS_IDE_HOOK_SCRIPT; if (Get-Command Send-IdeNotification -CommandType Function -ErrorAction SilentlyContinue) { Send-IdeNotification $env:WS_IDE_N_STATE $env:WS_IDE_N_SESS $env:WS_IDE_N_AGENT $env:WS_IDE_N_WORKDIR $env:WS_IDE_N_TITLE $env:WS_IDE_N_BODY }'
            foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $runner)) {
                $psi.ArgumentList.Add([string]$a)
            }
            $psi.Environment['WS_IDE_HOOK_SCRIPT'] = $rulesPath
            $psi.Environment['WS_IDE_N_STATE'] = $State
            $psi.Environment['WS_IDE_N_SESS'] = $Session
            $psi.Environment['WS_IDE_N_AGENT'] = $effCli
            $psi.Environment['WS_IDE_N_WORKDIR'] = $Workdir
            $psi.Environment['WS_IDE_N_TITLE'] = $title
            $psi.Environment['WS_IDE_N_BODY'] = $body
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            [void][System.Diagnostics.Process]::Start($psi)
        } catch {
            Write-Verbose "Notification hook dispatch skipped: $_"
        }
    }
}

function Get-IdeCreateTimeoutMillisecond([double]$OverrideSec = 0) {
    $sec = 120.0
    $parsed = 0.0
    if ($env:IDE_CREATE_TIMEOUT -and [double]::TryParse($env:IDE_CREATE_TIMEOUT.Trim(), [ref]$parsed) -and $parsed -gt 0) {
        $sec = $parsed
    } elseif ($OverrideSec -gt 0) {
        $sec = $OverrideSec
    }
    return [int][Math]::Round($sec * 1000.0)
}

function Invoke-CreateIdeWorkspaceDirectory(
    [string]$RawName,
    [double]$TimeoutSec = 0,
    [bool]$InteractiveTty = $false,
    [bool]$IsDryRun = $false
) {
    $clean = if ($RawName) { $RawName.Trim() } else { '' }
    if (-not $clean -or $clean -in @('.', '..', '/', '\', '~')) {
        return @{ Path = ''; Error = 'Invalid workspace name.' }
    }
    foreach ($ch in $clean.ToCharArray()) {
        if ([int]$ch -lt 32 -or [int]$ch -eq 127) {
            return @{ Path = ''; Error = 'Workspace name cannot contain control characters.' }
        }
    }
    $normSegs = @($clean.Replace('/', '\') -split '\\' | Where-Object { $_ -ne '' })
    if ($normSegs -contains '..') {
        return @{ Path = ''; Error = "Workspace name cannot contain '..' traversal segments." }
    }

    $parentDir = Get-IdeWorkspaceParent
    if ($IsDryRun) {
        if ([System.IO.Path]::IsPathRooted($clean) -or $clean.StartsWith('~\') -or $clean.StartsWith('~/') -or $clean.StartsWith('.\') -or $clean.StartsWith('./')) {
            return @{ Path = (Expand-IdeUserPath $clean); Error = '' }
        }
        return @{ Path = [System.IO.Path]::GetFullPath((Join-Path $parentDir ($normSegs -join [System.IO.Path]::DirectorySeparatorChar))); Error = '' }
    }

    if (Test-IdeHookDefined 'New-IdeWorkspace') {
        $rulesPath = Get-IdeRulesPath
        $pwshBin = Get-CurrentPwshExecutable
        $timeoutMs = Get-IdeCreateTimeoutMillisecond $TimeoutSec
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new($pwshBin)
            $runner = '. $env:WS_IDE_HOOK_SCRIPT; if (-not (Get-Command New-IdeWorkspace -CommandType Function -ErrorAction SilentlyContinue)) { exit 126 }; New-IdeWorkspace $env:WS_IDE_NEW_NAME'
            foreach ($a in @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $runner)) {
                $psi.ArgumentList.Add([string]$a)
            }
            $psi.Environment['WS_IDE_HOOK_SCRIPT'] = $rulesPath
            $psi.Environment['WS_IDE_NEW_NAME'] = $clean
            $psi.Environment['IDE_WORKSPACE_PARENT'] = $parentDir
            $psi.RedirectStandardInput = (-not $InteractiveTty)
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = (-not $InteractiveTty)
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = (-not $InteractiveTty)
            $proc = [System.Diagnostics.Process]::Start($psi)
            if (-not $proc) {
                return @{ Path = ''; Error = 'Failed to start New-IdeWorkspace hook.' }
            }
            if (-not $InteractiveTty) {
                try { $proc.StandardInput.Close() } catch { Write-Verbose 'Hook stdin close skipped' }
            }
            $outTask = $proc.StandardOutput.ReadToEndAsync()
            $errTask = if (-not $InteractiveTty) { $proc.StandardError.ReadToEndAsync() } else { $null }
            if (-not $proc.WaitForExit($timeoutMs)) {
                try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out New-IdeWorkspace terminated' }
                $secDisp = [Math]::Round($timeoutMs / 1000.0, 1)
                return @{ Path = ''; Error = "New-IdeWorkspace timed out after ${secDisp}s." }
            }
            if ($proc.ExitCode -ne 126) {
                $stdout = if ($outTask.Wait(250)) { $outTask.Result } else { '' }
                $stderr = if ($null -ne $errTask -and $errTask.Wait(250)) { $errTask.Result } else { '' }
                if ($proc.ExitCode -ne 0) {
                    $errLines = @($stderr -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                    $detail = if ($errLines.Count -gt 0) { $errLines[-1] } else { "New-IdeWorkspace exited with status $($proc.ExitCode)." }
                    return @{ Path = ''; Error = $detail }
                }
                $outLines = @($stdout -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                for ($k = $outLines.Count - 1; $k -ge 0; $k--) {
                    $candDir = Expand-IdeUserPath $outLines[$k]
                    if ([System.IO.Directory]::Exists($candDir)) {
                        return @{ Path = (Resolve-Path -LiteralPath $candDir).ProviderPath; Error = '' }
                    }
                }
                $resolvedWs = Resolve-IdeWorkspaceTarget $clean
                if ($resolvedWs -and [System.IO.Directory]::Exists($resolvedWs)) {
                    return @{ Path = (Resolve-Path -LiteralPath $resolvedWs).ProviderPath; Error = '' }
                }
                if ($outLines.Count -eq 0) {
                    $candDef = Join-Path $parentDir $clean
                    if ([System.IO.Directory]::Exists($candDef)) {
                        return @{ Path = (Resolve-Path -LiteralPath $candDef).ProviderPath; Error = '' }
                    }
                    return @{ Path = ''; Error = 'New-IdeWorkspace exited 0 without printing or creating a workspace directory.' }
                }
                return @{ Path = ''; Error = "New-IdeWorkspace returned non-existent directory '$($outLines[-1])'." }
            }
        } catch {
            return @{ Path = ''; Error = "Failed to execute New-IdeWorkspace: $($_.Exception.Message)" }
        }
    }

    if ([System.IO.Path]::IsPathRooted($clean) -or $clean.StartsWith('~\') -or $clean.StartsWith('~/') -or $clean.StartsWith('.\') -or $clean.StartsWith('./')) {
        $targetDir = Expand-IdeUserPath $clean
    } else {
        if ($normSegs.Count -eq 0 -or ($normSegs -contains '.') -or ($normSegs -contains '..')) {
            return @{ Path = ''; Error = "Workspace name cannot contain '.' or '..' path segments." }
        }
        $targetDir = [System.IO.Path]::GetFullPath((Join-Path $parentDir ($normSegs -join [System.IO.Path]::DirectorySeparatorChar)))
        $normParentPfx = $parentDir.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
        if ([string]::Equals($targetDir.TrimEnd('\', '/'), $parentDir.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase) -or
            -not $targetDir.StartsWith($normParentPfx, [System.StringComparison]::OrdinalIgnoreCase)) {
            return @{ Path = ''; Error = "Workspace '$clean' resolves outside '$parentDir'." }
        }
    }

    try {
        New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
        return @{ Path = (Resolve-Path -LiteralPath $targetDir).ProviderPath; Error = '' }
    } catch {
        return @{ Path = ''; Error = "Failed to create directory '${targetDir}': $($_.Exception.Message)" }
    }
}
