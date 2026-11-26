# ==============================================================================
# Fleet.ps1 - Fast Git/PR metadata, urgency-ranked fleet UI & fzf session modal
# ==============================================================================

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

function Format-ForgePrUrl([string]$ForgeBaseUrl, [string]$PrNumber) {
    if (-not $ForgeBaseUrl -or -not $PrNumber) { return '' }
    $num = $PrNumber.Trim().TrimStart('#', '@', '!')
    if ($num -notmatch '^[0-9]+$') { return '' }
    if ($ForgeBaseUrl -match '(?i)gitlab') {
        return "$ForgeBaseUrl/-/merge_requests/$num"
    }
    if ($ForgeBaseUrl -match '(?i)bitbucket') {
        return "$ForgeBaseUrl/pull-requests/$num"
    }
    if ($ForgeBaseUrl -match '(?i)(gitea|forgejo|codeberg)') {
        return "$ForgeBaseUrl/pulls/$num"
    }
    return "$ForgeBaseUrl/pull/$num"
}

function Get-GitPrCacheStatePath([string]$RepoRoot, [string]$Branch) {
    $prCacheDir = Join-Path (Join-Path (Get-UserHomeDir) '.cache') 'git-pr-prompt'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$RepoRoot|$Branch")
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $key = [System.BitConverter]::ToString($hashBytes, 0, 8).Replace('-', '').ToLowerInvariant()
    return (Join-Path $prCacheDir "$key.state")
}

function Get-GitStatusSnapshot([string]$Workdir, [string]$Branch, [string]$PrBadge) {
    $gitCmd = Get-Command git.exe, git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gitCmd) {
        return @{ Dirty = $false; Detail = "$Branch$PrBadge (clean)" }
    }
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new($gitCmd.Source)
        foreach ($ga in @('-C', $Workdir, '--no-optional-locks', 'status', '--porcelain=v1', '-b')) {
            $psi.ArgumentList.Add($ga)
        }
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        if (-not $proc) {
            return @{ Dirty = $false; Detail = "$Branch$PrBadge (clean)" }
        }
        try { $proc.StandardInput.Close() } catch { Write-Verbose 'git status stdin close skipped' }
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        if (-not $proc.WaitForExit(400)) {
            try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out git status terminated' }
            return @{ Dirty = $false; Detail = "$Branch$PrBadge" }
        }
        if ($proc.ExitCode -ne 0) {
            return @{ Dirty = $false; Detail = "$Branch$PrBadge" }
        }
        $rawOut = if ($outTask.Wait(150)) { $outTask.Result } else { '' }
        $lines = @($rawOut -split "`r?`n" | Where-Object { $_ -ne '' })
        $abNote = ''
        $staged = 0
        $modified = 0
        $untracked = 0
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            $ln = $lines[$idx]
            if ($idx -eq 0 -and $ln.StartsWith('## ')) {
                if ($ln -match '\[([^\]]+)\]\s*$') {
                    $abNote = " [$($Matches[1])]"
                }
                continue
            }
            if ($ln.Length -lt 2) { continue }
            $xy = $ln.Substring(0, 2)
            if ($xy -eq '??') {
                $untracked++
                continue
            }
            if ($xy[0] -notin @(' ', '?')) { $staged++ }
            if ($xy[1] -notin @(' ', '?')) { $modified++ }
        }
        $isDirty = (($staged + $modified + $untracked) -gt 0)
        if (-not $isDirty) {
            return @{ Dirty = $false; Detail = "$Branch$PrBadge$abNote (clean)" }
        }
        $parts = [System.Collections.Generic.List[string]]::new()
        if ($staged -gt 0) { $parts.Add("+$staged staged") }
        if ($modified -gt 0) { $parts.Add("~$modified modified") }
        if ($untracked -gt 0) { $parts.Add("?$untracked untracked") }
        return @{ Dirty = $true; Detail = "$Branch$PrBadge$abNote ($($parts -join ', '))" }
    } catch {
        return @{ Dirty = $false; Detail = "$Branch$PrBadge" }
    }
}

function Get-FastGitSummary([string]$Workdir, [bool]$IncludeStatus = $false) {
    $empty = @{
        Root         = ''
        WorktreeRoot = ''
        Branch       = ''
        PrBadge      = ''
        PrUrl        = ''
        ForgeUrl     = ''
        Dirty        = $false
        Detail       = ''
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
                $repoRoot = ''
            }
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }

    $canonRoot = if ($repoRoot) {
        try { (Resolve-Path -LiteralPath $repoRoot).ProviderPath } catch { $repoRoot }
    } else {
        ''
    }

    if (-not (Get-Command Invoke-IdeVcsSummaryHook -CommandType Function -ErrorAction SilentlyContinue)) {
        $hooksFile = Join-Path (Get-IdeLibDir) 'Hooks.ps1'
        if ([System.IO.File]::Exists($hooksFile)) { . $hooksFile }
    }
    if (Get-Command Invoke-IdeVcsSummaryHook -CommandType Function -ErrorAction SilentlyContinue) {
        $hookVcs = Invoke-IdeVcsSummaryHook -Workdir $Workdir
        if ($null -ne $hookVcs) {
            return @{
                Root         = $canonRoot
                WorktreeRoot = $canonRoot
                Branch       = [string]$hookVcs.Branch
                PrBadge      = ''
                PrUrl        = [string]$hookVcs.PrUrl
                ForgeUrl     = ''
                Dirty        = [bool]$hookVcs.Dirty
                Detail       = [string]$hookVcs.Detail
            }
        }
    }

    if (-not $canonRoot -or -not $gitDir) { return $empty }

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

    $forgeUrl = ''
    $cfgPrNum = ''
    $cfgPrUrl = ''
    $cfgFiles = [System.Collections.Generic.List[string]]::new()
    if ($commonGitDir) { $cfgFiles.Add((Join-Path $commonGitDir 'config')) }
    if ($gitDir -and -not [string]::Equals($gitDir, $commonGitDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $cfgFiles.Add((Join-Path $gitDir 'config'))
    }
    foreach ($cfgFile in $cfgFiles) {
        if (-not [System.IO.File]::Exists($cfgFile)) { continue }
        try {
            $section = ''
            foreach ($cfgLine in [System.IO.File]::ReadLines($cfgFile)) {
                $trimmed = $cfgLine.Trim()
                if (-not $trimmed -or $trimmed.StartsWith('#') -or $trimmed.StartsWith(';')) { continue }
                if ($trimmed.StartsWith('[')) {
                    $section = $trimmed
                    continue
                }
                if ($section -match '^\[remote\s+"origin"\]' -and $trimmed -match '^url\s*=\s*(.+)$') {
                    $forgeUrl = ConvertTo-ForgeHttpsBase $Matches[1].Trim()
                } elseif ($branch -and $section -eq "[branch `"$branch`"]") {
                    if ($trimmed -match '^prUrl\s*=\s*(https?://\S+)$') {
                        $cfgPrUrl = $Matches[1].Trim()
                    } elseif ($trimmed -match '^pr\s*=\s*#?([0-9]+)$') {
                        $cfgPrNum = $Matches[1]
                    } elseif ($trimmed -match '^merge\s*=\s*refs/(?:pull|merge-requests|pull-requests)/([0-9]+)/') {
                        if (-not $cfgPrNum) { $cfgPrNum = $Matches[1] }
                    }
                }
            }
        } catch {
            Write-Verbose "Git config parse skipped: $_"
        }
    }

    $prBadge = ''
    $prUrl = ''
    if ($branch -and $branch -notin @('main', 'master', 'trunk')) {
        $stateFile = Get-GitPrCacheStatePath -RepoRoot $canonRoot -Branch $branch
        if ([System.IO.File]::Exists($stateFile)) {
            try {
                $lines = [System.IO.File]::ReadAllLines($stateFile)
                if ($lines.Count -eq 1 -and $lines[0].Contains('|')) {
                    $pCols = $lines[0].Split('|')
                    if ($pCols.Count -ge 3 -and $pCols[0] -eq $branch -and $pCols[1] -and $pCols[2] -match '^https?://') {
                        $sym = if ($pCols[2] -match '(?i)gitlab') { '!' } else { '@' }
                        $prBadge = "$sym$($pCols[1].TrimStart('#', '@', '!'))"
                        $prUrl = $pCols[2].Trim()
                    }
                } elseif ($lines.Count -ge 2 -and $lines[0].Trim() -and $lines[1].Trim()) {
                    $prBadge = $lines[0].Trim()
                    $prUrl = $lines[1].Trim()
                }
            } catch {
                Write-Verbose "PR cache read skipped: $_"
            }
        }
        if (-not $prUrl -and ($cfgPrUrl -or $cfgPrNum)) {
            $sym = if (($cfgPrUrl -match '(?i)gitlab') -or ($forgeUrl -match '(?i)gitlab')) { '!' } else { '@' }
            if ($cfgPrNum) { $prBadge = "$sym$cfgPrNum" }
            $prUrl = if ($cfgPrUrl) { $cfgPrUrl } else { Format-ForgePrUrl -ForgeBaseUrl $forgeUrl -PrNumber $cfgPrNum }
        }
    }

    $dirty = $false
    $detail = "$branch$prBadge"
    if ($IncludeStatus -and $branch) {
        $snap = Get-GitStatusSnapshot -Workdir $Workdir -Branch $branch -PrBadge $prBadge
        $dirty = [bool]$snap.Dirty
        $detail = [string]$snap.Detail
    }

    return @{
        Root         = $canonRoot
        WorktreeRoot = $canonRoot
        Branch       = $branch
        PrBadge      = $prBadge
        PrUrl        = $prUrl
        ForgeUrl     = $forgeUrl
        Dirty        = $dirty
        Detail       = $detail
    }
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

    $git = Get-FastGitSummary -Workdir $wdir -IncludeStatus $false
    $prUrl = if ($git.PrUrl -and $git.PrUrl -match '^https?://\S+$') { $git.PrUrl } else { '' }

    if (-not $prUrl) {
        Push-Location -LiteralPath $wdir
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
                    $statePath = Get-GitPrCacheStatePath -RepoRoot $git.Root -Branch $git.Branch
                    Write-TextUtf8NoBom -Path $statePath -Content "$prLabel`n$prUrl`n"
                } catch {
                    Write-Verbose "PR cache write skipped: $_"
                }
            }
        } finally {
            Pop-Location
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

function Format-ElapsedAge([long]$EpochSec) {
    if ($EpochSec -le 0) { return '' }
    $nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $delta = $nowSec - $EpochSec
    if ($delta -lt 60) { return '' }
    if ($delta -lt 3600) { return "$([long]($delta / 60))m" }
    if ($delta -lt 86400) { return "$([long]($delta / 3600))h" }
    return "$([long]($delta / 86400))d"
}

function Get-ClassifiedIdeFleet([bool]$IncludeGit = $true) {
    $stateDir = Get-IdeStateDir
    $livePipes = Get-LiveIdePipeMap
    $liveZellij = Get-LiveZellijSessionMap
    $sessions = [ordered]@{}

    if (Test-Path -LiteralPath $stateDir -PathType Container) {
        $files = @(Get-ChildItem -LiteralPath $stateDir -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($f in $files) {
            if ($f.Name.StartsWith('modal-', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
            $sName = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
            $meta = Read-SessionState $sName
            if ($meta) {
                $sessions[$sName] = $meta
            }
        }
    }
    foreach ($zName in ($liveZellij.Keys | Sort-Object)) {
        if (-not $sessions.Contains($zName)) {
            $sessions[$zName] = Build-IdeSessionRecord -SessionName $zName -Backend 'zellij'
        }
    }
    foreach ($liveName in ($livePipes.Keys | Sort-Object)) {
        if (-not $sessions.Contains($liveName)) {
            $sessions[$liveName] = Build-IdeSessionRecord -SessionName $liveName -Pipe $livePipes[$liveName] -Backend 'wt'
        }
    }

    if ($sessions.Count -eq 0) {
        return @()
    }

    $curSess = if ($env:IDE_ORIGIN_SESSION -and $env:IDE_ORIGIN_SESSION.Trim()) {
        Get-SanitizedToken $env:IDE_ORIGIN_SESSION.Trim()
    } else {
        $cz = Get-CurrentZellijSessionToken
        if ($cz) { $cz } elseif ($env:IDE_SESSION -and $env:IDE_SESSION.Trim()) { Get-SanitizedToken $env:IDE_SESSION.Trim() } else { '' }
    }

    $gitCache = @{}
    if ($IncludeGit) {
        foreach ($k in $sessions.Keys) {
            $m = $sessions[$k]
            $wd = if ($m['workdir']) { [string]$m['workdir'] } elseif ($m['root']) { [string]$m['root'] } else { '' }
            if ($wd) {
                $normKey = $wd.TrimEnd('\', '/').ToLowerInvariant()
                if (-not $gitCache.ContainsKey($normKey)) {
                    $gitCache[$normKey] = Get-FastGitSummary -Workdir $wd -IncludeStatus $true
                }
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
        $aiShellFile = Join-Path $stateDir "$k.ai-shell"
        $atAiShell = ($status -eq 'live' -and [System.IO.File]::Exists($aiShellFile))

        $tier = 4
        $subTier = 0
        $dispState = 'IDLE'
        $needsAttn = $false
        if ($status -ne 'live') {
            $tier = 4
            $subTier = 2
            $dispState = $status.ToUpperInvariant()
        } elseif ($aiCli -eq 'shell' -or $atAiShell) {
            $tier = 4
            $subTier = 0
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
                { $_ -in @('running', 'working') } {
                    $tier = 2
                    $subTier = 0
                    $dispState = 'WORKING'
                }
                'quota' {
                    $tier = 2
                    $subTier = 1
                    $dispState = 'QUOTA'
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
        $shortPath = if ($wdir) { Format-IdeShortHome $wdir } else { '-' }
        $isCur = [bool]($curSess -and [string]::Equals($k, $curSess, [System.StringComparison]::OrdinalIgnoreCase))

        $gitBranch = ''
        $gitDirty = $false
        $gitDetail = ''
        $gitPrUrl = ''
        $wtRoot = ''
        $branchLabel = '-'
        if ($IncludeGit -and $wdir) {
            $git = $gitCache[$wdir.TrimEnd('\', '/').ToLowerInvariant()]
            if ($git) {
                $gitBranch = [string]$git.Branch
                $gitDirty = [bool]$git.Dirty
                $gitDetail = [string]$git.Detail
                $gitPrUrl = [string]$git.PrUrl
                $wtRoot = [string]$git.WorktreeRoot
                if ($gitBranch) {
                    $dirtyMark = if ($gitDirty) { '*' } else { '' }
                    $branchLabel = "$gitBranch$($git.PrBadge)$dirtyMark"
                }
            }
        }

        $activeRole = if ($status -ne 'live') {
            ''
        } elseif ($isCur -and $env:IDE_ROLE) {
            (ConvertTo-CanonicalIdeRole $env:IDE_ROLE).Pipe
        } else {
            'ai'
        }
        $isAttached = ($status -eq 'live' -and ($isCur -or ([string]$m['backend'] -eq 'wt' -and $pipeUp)))
        $quitErr = if ($m['quit_error']) { [string]$m['quit_error'] } else { '' }

        $primarySortTs = if ($tier -in @(0, 1)) {
            if ($attnTs -gt 0) { $attnTs } else { $stateTs }
        } else {
            -$stateTs
        }

        $entries.Add(@{
            Session       = $k
            Status        = $status
            Layout        = if ($m['layout']) { [string]$m['layout'] } else { '3pane' }
            AiCli         = $aiCli
            State         = $dispState
            StateLabel    = $stateLabel
            StateTs       = $stateTs
            NeedsAttn     = $needsAttn
            AttnTs        = $attnTs
            Tier          = $tier
            SubTier       = $subTier
            CurSort       = if ($isCur) { 0 } else { 1 }
            SortTs        = $primarySortTs
            BranchLabel   = $branchLabel
            GitBranch     = $gitBranch
            GitDirty      = $gitDirty
            GitDetail     = $gitDetail
            GitPrUrl      = $gitPrUrl
            WorktreeRoot  = $wtRoot
            WorktreePeers = [string[]]@()
            HasPeerWarn   = $false
            RawWorkdir    = $wdir
            Workdir       = if ($wdir) { $wdir } else { '-' }
            ShortPath     = $shortPath
            ActiveRole    = $activeRole
            Attached      = $isAttached
            IsCurrent     = $isCur
            Message       = if ($m['agent_message']) { [string]$m['agent_message'] } else { '' }
            QuitError     = $quitErr
        })
    }

    $sorted = @($entries | Sort-Object `
        @{ Expression = { $_.Tier }; Ascending = $true }, `
        @{ Expression = { $_.SubTier }; Ascending = $true }, `
        @{ Expression = { $_.CurSort }; Ascending = $true }, `
        @{ Expression = { $_.SortTs }; Ascending = $true }, `
        @{ Expression = { $_.Session }; Ascending = $true })

    if ($IncludeGit) {
        $byWorktree = @{}
        foreach ($e in $sorted) {
            if ($e.Status -ne 'live') { continue }
            $groupKey = if ($e.WorktreeRoot) {
                $e.WorktreeRoot.TrimEnd('\', '/').ToLowerInvariant()
            } elseif ($e.RawWorkdir) {
                $e.RawWorkdir.TrimEnd('\', '/').ToLowerInvariant()
            } else {
                ''
            }
            if ($groupKey) {
                if (-not $byWorktree.ContainsKey($groupKey)) {
                    $byWorktree[$groupKey] = [System.Collections.Generic.List[hashtable]]::new()
                }
                $byWorktree[$groupKey].Add($e)
            }
        }
        foreach ($peerGroup in $byWorktree.Values) {
            if ($peerGroup.Count -ge 2) {
                $anyWorking = ($null -ne ($peerGroup | Where-Object { $_.State -eq 'WORKING' } | Select-Object -First 1))
                if ($anyWorking) {
                    foreach ($pe in $peerGroup) {
                        $pe.WorktreePeers = [string[]]@($peerGroup | Where-Object { $_.Session -ne $pe.Session } | ForEach-Object { [string]$_.Session })
                        $pe.HasPeerWarn = $true
                    }
                }
            }
        }
    }

    return $sorted
}

function Measure-FleetColumnWidth([object[]]$Fleet, [int]$MaxTotalColumns = 0) {
    $sessW = 7
    $cliW = 5
    $stateW = 5
    $gitW = 6
    foreach ($e in $Fleet) {
        $sw = Get-IdeVisibleWidth ([string]$e.Session)
        $cw = Get-IdeVisibleWidth ([string]$e.AiCli)
        $stw = Get-IdeVisibleWidth ([string]$e.StateLabel)
        $gw = Get-IdeVisibleWidth ([string]$e.BranchLabel)
        if ($sw -gt $sessW) { $sessW = [Math]::Min(28, $sw) }
        if ($cw -gt $cliW) { $cliW = [Math]::Min(12, $cw) }
        if ($stw -gt $stateW) { $stateW = [Math]::Min(16, $stw) }
        if ($gw -gt $gitW) { $gitW = [Math]::Min(28, $gw) }
    }
    $pathMax = 0
    if ($MaxTotalColumns -gt 0) {
        $fixed = 2 + $sessW + 2 + $cliW + 2 + $stateW + 2 + $gitW + 2
        if ($fixed + 16 -gt $MaxTotalColumns) {
            $overflow = ($fixed + 16) - $MaxTotalColumns
            $shrinkGit = [Math]::Min($overflow, [Math]::Max(0, $gitW - 8))
            $gitW -= $shrinkGit
            $overflow -= $shrinkGit
            if ($overflow -gt 0) {
                $sessW = [Math]::Max(8, $sessW - $overflow)
            }
            $fixed = 2 + $sessW + 2 + $cliW + 2 + $stateW + 2 + $gitW + 2
        }
        $pathMax = [Math]::Max(12, $MaxTotalColumns - $fixed)
    }
    return @{
        SessW   = $sessW
        CliW    = $cliW
        StateW  = $stateW
        GitW    = $gitW
        PathMax = $pathMax
    }
}

function Format-FleetTableHeader([hashtable]$Widths) {
    return ('  {0}  {1}  {2}  {3}  WORKSPACE' -f `
        'SESSION'.PadRight([int]$Widths.SessW), `
        'AGENT'.PadRight([int]$Widths.CliW), `
        'STATE'.PadRight([int]$Widths.StateW), `
        'BRANCH'.PadRight([int]$Widths.GitW))
}

function Format-FleetTableLine([hashtable]$Entry, [hashtable]$Pal, [hashtable]$Widths, [bool]$UseColor) {
    $sRaw = Format-IdeTruncVisible -Text ([string]$Entry.Session) -MaxWidth ([int]$Widths.SessW)
    $cRaw = Format-IdeTruncVisible -Text ([string]$Entry.AiCli) -MaxWidth ([int]$Widths.CliW)
    $stRaw = Format-IdeTruncVisible -Text ([string]$Entry.StateLabel) -MaxWidth ([int]$Widths.StateW)
    $gRaw = Format-IdeTruncVisible -Text ([string]$Entry.BranchLabel) -MaxWidth ([int]$Widths.GitW)

    $sPad = Format-IdePadVisible -Text $sRaw -Width ([int]$Widths.SessW)
    $cPad = Format-IdePadVisible -Text $cRaw -Width ([int]$Widths.CliW)
    $stPad = Format-IdePadVisible -Text $stRaw -Width ([int]$Widths.StateW)
    $gPad = Format-IdePadVisible -Text $gRaw -Width ([int]$Widths.GitW)

    $pathDisp = [string]$Entry.ShortPath
    if ([int]$Widths.PathMax -gt 0) {
        $budget = [int]$Widths.PathMax - $(if ($Entry.HasPeerWarn) { 2 } else { 0 })
        $pathDisp = Format-IdeTruncVisible -Text $pathDisp -MaxWidth ([Math]::Max(6, $budget))
    }

    if ($UseColor) {
        $nf = Test-IdeNerdFont
        $curGlyph = if ($nf) { "`u{25B8}" } else { '*' }
        $attnGlyph = if ($nf) { "`u{F009A}" } else { '!' }
        $attnC = if ($Entry.State -eq 'DONE') { $Pal.E_GRN } elseif ($Entry.State -eq 'ERROR') { $Pal.E_RED } else { $Pal.E_ORG }
        $marker = if ($Entry.IsCurrent) {
            "$($Pal.E_CYN)$curGlyph$($Pal.E_RST)"
        } elseif ($Entry.NeedsAttn) {
            "${attnC}$attnGlyph$($Pal.E_RST)"
        } else {
            ' '
        }
        $cSess = if ($Entry.IsCurrent) { $Pal.E_B1 } elseif ($Entry.NeedsAttn) { $attnC } elseif ($Entry.Status -ne 'live') { $Pal.E_B01 } else { $Pal.E_BLU }
        $cState = Get-IdeStateColor -State $Entry.State -Pal $Pal
        $cGit = if ($Entry.BranchLabel -eq '-') {
            $Pal.E_B01
        } elseif ($Entry.GitDirty) {
            $Pal.E_YLW
        } elseif ($Entry.BranchLabel -match '[@!][0-9]+') {
            $Pal.E_CYN
        } else {
            $Pal.E_GRN
        }
        $wtSfx = if ($Entry.HasPeerWarn) { " $($Pal.E_YLW)!$($Pal.E_RST)" } else { '' }
        return "$marker ${cSess}${sPad}$($Pal.E_RST)  $($Pal.E_B0)${cPad}$($Pal.E_RST)  ${cState}${stPad}$($Pal.E_RST)  ${cGit}${gPad}$($Pal.E_RST)  $($Pal.E_B0)$pathDisp$($Pal.E_RST)${wtSfx}"
    }
    $plainMarker = if ($Entry.IsCurrent) { '*' } elseif ($Entry.NeedsAttn) { '!' } else { ' ' }
    $plainSfx = if ($Entry.HasPeerWarn) { ' !' } else { '' }
    return "$plainMarker $sPad  $cPad  $stPad  $gPad  $pathDisp$plainSfx"
}

function Format-FzfSessionRowList([object[]]$Fleet = $null, [hashtable]$Widths = $null) {
    $resolvedFleet = if ($null -ne $Fleet) { $Fleet } else { Get-ClassifiedIdeFleet -IncludeGit $true }
    if ($resolvedFleet.Count -eq 0) { return @() }
    $pal = Get-ActivePaletteMap
    $useColor = ($pal.TIER -ne 'nocolor')
    $w = if ($Widths) { $Widths } else { Measure-FleetColumnWidth $resolvedFleet }
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $resolvedFleet) {
        $line = Format-FleetTableLine -Entry $e -Pal $pal -Widths $w -UseColor $useColor
        $rows.Add("$($e.Session)`t$line")
    }
    return $rows.ToArray()
}

function Get-IdeWrappedPreviewRowCount([string]$Line, [int]$Columns) {
    if ($Columns -le 0) { return 1 }
    $vis = Get-IdeVisibleWidth $Line
    if ($vis -le 0) { return 1 }
    return [int][Math]::Ceiling([double]$vis / [double]$Columns)
}

function Get-IdeSgrCarryPrefix([string[]]$SkippedLines) {
    if (-not $SkippedLines -or $SkippedLines.Count -eq 0) { return '' }
    $esc = [char]27
    $sgrRe = [regex]::new("${esc}\[([0-9;:]*)m")
    $fg = ''
    $bg = ''
    $ulColor = ''
    $bold = ''
    $italic = ''
    $underline = ''
    $reverse = ''
    $strike = ''

    foreach ($ln in $SkippedLines) {
        if (-not $ln -or -not $ln.Contains($esc)) { continue }
        foreach ($m in $sgrRe.Matches($ln)) {
            $rawParams = $m.Groups[1].Value.Replace(':', ';')
            [string[]]$parts = @(if ($rawParams -eq '') { '0' } else { $rawParams.Split(';') })
            $pIdx = 0
            while ($pIdx -lt $parts.Count) {
                $code = 0
                if (-not [int]::TryParse($parts[$pIdx], [ref]$code)) { $pIdx++; continue }
                switch ($code) {
                    0 {
                        $fg = ''; $bg = ''; $ulColor = ''
                        $bold = ''; $italic = ''; $underline = ''; $reverse = ''; $strike = ''
                    }
                    1  { $bold = '1' }
                    2  { $bold = '2' }
                    22 { $bold = '' }
                    3  { $italic = '3' }
                    23 { $italic = '' }
                    4  { $underline = '4' }
                    24 { $underline = '' }
                    7  { $reverse = '7' }
                    27 { $reverse = '' }
                    9  { $strike = '9' }
                    29 { $strike = '' }
                    39 { $fg = '' }
                    49 { $bg = '' }
                    59 { $ulColor = '' }
                    { ($_ -ge 30 -and $_ -le 37) -or ($_ -ge 90 -and $_ -le 97) } { $fg = "$code" }
                    { ($_ -ge 40 -and $_ -le 47) -or ($_ -ge 100 -and $_ -le 107) } { $bg = "$code" }
                    { $_ -in @(38, 48, 58) } {
                        $mode = if ($pIdx + 1 -lt $parts.Count) { $parts[$pIdx + 1] } else { '' }
                        $seq = ''
                        if ($mode -eq '5' -and $pIdx + 2 -lt $parts.Count) {
                            $seq = "$code;5;$($parts[$pIdx + 2])"
                            $pIdx += 2
                        } elseif ($mode -eq '2' -and $pIdx + 4 -lt $parts.Count) {
                            $seq = "$code;2;$($parts[$pIdx + 2]);$($parts[$pIdx + 3]);$($parts[$pIdx + 4])"
                            $pIdx += 4
                        }
                        if ($seq) {
                            if ($code -eq 38) { $fg = $seq }
                            elseif ($code -eq 48) { $bg = $seq }
                            else { $ulColor = $seq }
                        }
                    }
                }
                $pIdx++
            }
        }
    }

    $active = @($bold, $italic, $underline, $reverse, $strike, $fg, $bg, $ulColor | Where-Object { $_ -ne '' })
    if ($active.Count -eq 0) { return '' }
    return "${esc}[$($active -join ';')m"
}

function Select-IdePreviewTail([string[]]$Lines, [int]$MaxRows, [int]$WrapColumns) {
    if (-not $Lines -or $Lines.Count -eq 0 -or $MaxRows -le 0) { return @() }
    $budget = $MaxRows
    $startIdx = $Lines.Count
    for ($idx = $Lines.Count - 1; $idx -ge 0; $idx--) {
        $cost = Get-IdeWrappedPreviewRowCount -Line $Lines[$idx] -Columns $WrapColumns
        if ($cost -gt $budget -and $startIdx -lt $Lines.Count) {
            break
        }
        $startIdx = $idx
        $budget -= $cost
        if ($budget -le 0) { break }
    }
    $tail = @($Lines[$startIdx..($Lines.Count - 1)])
    if ($startIdx -gt 0 -and $tail.Count -gt 0) {
        $carry = Get-IdeSgrCarryPrefix -SkippedLines $Lines[0..($startIdx - 1)]
        if ($carry) {
            $tail[0] = $carry + $tail[0]
        }
    }
    return ,$tail
}

function Get-IdeSessionPreviewFrame([string]$SessionName) {
    $meta = Read-SessionState $SessionName
    $liveZellij = Get-LiveZellijSessionMap
    $pal = Get-ActivePaletteMap
    $nf = Test-IdeNerdFont
    $isLive = ($liveZellij[$SessionName] -eq 'live')
    $isCurrent = ($isLive -and (Test-IsCurrentZellijSession $SessionName))

    $statusTag = if ($isCurrent) {
        "$($pal.E_CYN)LIVE (current)$($pal.E_RST)"
    } elseif ($isLive) {
        "$($pal.E_GRN)LIVE$($pal.E_RST)"
    } else {
        "$($pal.E_B01)SAVED (stopped)$($pal.E_RST)"
    }

    $workDir = if ($meta -and $meta['workdir']) { [string]$meta['workdir'] } elseif ($meta -and $meta['root']) { [string]$meta['root'] } else { '' }
    $initRoot = if ($meta -and $meta['root']) { [string]$meta['root'] } else { $workDir }
    $aiCli = if ($meta -and $meta['ai_cli']) { [string]$meta['ai_cli'] } else { 'agy' }
    $layout = if ($meta -and $meta['layout']) { [string]$meta['layout'] } else { '3pane' }

    $aiShellMarker = Join-Path (Get-IdeStateDir) "$SessionName.ai-shell"
    $rawSt = if ($isLive -and [System.IO.File]::Exists($aiShellMarker)) {
        'SHELL'
    } elseif ($meta -and $meta['agent_state']) {
        ([string]$meta['agent_state']).ToUpperInvariant()
    } else {
        'IDLE'
    }
    if ($rawSt -eq 'RUNNING') { $rawSt = 'WORKING' }
    if ($rawSt -eq 'APPROVAL') { $rawSt = 'ATTN' }
    $cSt = Get-IdeStateColor -State $rawSt -Pal $pal
    $agentMsg = if ($meta -and $meta['agent_message']) { [string]$meta['agent_message'] } else { '' }
    $quitErr = if ($meta -and $meta['quit_error']) { [string]$meta['quit_error'] } else { '' }
    $git = if ($workDir) { Get-FastGitSummary -Workdir $workDir -IncludeStatus $true } else { @{ Branch = ''; PrBadge = ''; PrUrl = ''; Detail = ''; Dirty = $false } }

    $cols = 64
    $parsedCols = 0
    if ($env:FZF_PREVIEW_COLUMNS -and [int]::TryParse($env:FZF_PREVIEW_COLUMNS.Trim(), [ref]$parsedCols) -and $parsedCols -gt 0) {
        $cols = [Math]::Max(36, $parsedCols - 2)
    }
    $previewRows = 28
    $parsedRows = 0
    if ($env:FZF_PREVIEW_LINES -and [int]::TryParse($env:FZF_PREVIEW_LINES.Trim(), [ref]$parsedRows) -and $parsedRows -gt 0) {
        $previewRows = [Math]::Max(10, $parsedRows)
    }

    $dotSep = "`u{00B7}"
    $ruleCh = "`u{2500}"
    $hdrIco = if ($nf) { "`u{EBC8} " } else { '' }
    $outLines = [System.Collections.Generic.List[string]]::new()
    $outLines.Add(" $($pal.E_BLU)$hdrIco$SessionName$($pal.E_RST)  $statusTag  $($pal.E_B01)$dotSep$($pal.E_RST)  $($pal.E_B0)$layout$($pal.E_RST)  $($pal.E_B01)$dotSep$($pal.E_RST)  $($pal.E_YLW)$aiCli$($pal.E_RST) (${cSt}${rawSt}$($pal.E_RST))")
    if ($workDir) {
        $divNote = if ($initRoot -and -not [string]::Equals($initRoot.TrimEnd('\', '/'), $workDir.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
            " $($pal.E_B01)(root: $(Format-IdeShortHome $initRoot))$($pal.E_RST)"
        } else {
            ''
        }
        $outLines.Add(" $($pal.E_B01)Dir   :$($pal.E_RST) $($pal.E_B0)$(Format-IdeShortHome $workDir)$($pal.E_RST)$divNote")
    }
    if ($git.Branch) {
        $gitCol = if ($git.Dirty) { $pal.E_YLW } else { $pal.E_GRN }
        $prLink = if ($git.PrUrl) { " $($pal.E_B01)($($git.PrUrl))$($pal.E_RST)" } else { '' }
        $dispVcs = if ($git.Detail) { $git.Detail } else { "$($git.Branch)$($git.PrBadge)" }
        $outLines.Add(" $($pal.E_B01)Branch:$($pal.E_RST) ${gitCol}$dispVcs$($pal.E_RST)$prLink")
    }
    if ($agentMsg) {
        $outLines.Add(" $($pal.E_B01)Note  :$($pal.E_RST) $($pal.E_B0)$agentMsg$($pal.E_RST)")
    }
    if ($quitErr) {
        $outLines.Add(" $($pal.E_RED)Guard : $quitErr$($pal.E_RST)")
    }
    $outLines.Add(" $($pal.E_B01)$($ruleCh * [Math]::Max(20, $cols))$($pal.E_RST)")

    $hdrWrapped = 0
    foreach ($hl in $outLines) {
        $hdrWrapped += Get-IdeWrappedPreviewRowCount -Line $hl -Columns $cols
    }
    $availBodyRows = [Math]::Max(4, $previewRows - $hdrWrapped - 1)

    if ($isLive) {
        $zellijBin = Resolve-ZellijExecutable
        $aiPane = Get-RolePaneId -SessionName $SessionName -Role 'ai'
        if (-not $aiPane) { $aiPane = 'terminal_0' }
        $capturedBody = $false
        if ($zellijBin) {
            try {
                $psi = [System.Diagnostics.ProcessStartInfo]::new($zellijBin)
                if (-not $isCurrent) {
                    $psi.ArgumentList.Add('--session')
                    $psi.ArgumentList.Add($SessionName)
                }
                foreach ($a in @('action', 'dump-screen', '--ansi', '--pane-id', $aiPane)) {
                    $psi.ArgumentList.Add($a)
                }
                $psi.RedirectStandardInput = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $proc = [System.Diagnostics.Process]::Start($psi)
                if ($proc) {
                    try { $proc.StandardInput.Close() } catch { Write-Verbose 'dump-screen stdin close skipped' }
                    $dumpRaw = $proc.StandardOutput.ReadToEnd()
                    if (-not $proc.WaitForExit(1200)) {
                        try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out dump-screen terminated' }
                    } elseif ($dumpRaw) {
                        $rawLines = @($dumpRaw -split "`r?`n")
                        $lastNonBlank = $rawLines.Count - 1
                        while ($lastNonBlank -ge 0) {
                            if ((Format-IdePlainText $rawLines[$lastNonBlank]).Trim().Length -gt 0) { break }
                            $lastNonBlank--
                        }
                        if ($lastNonBlank -ge 0) {
                            $trimmed = @($rawLines[0..$lastNonBlank])
                            $tail = Select-IdePreviewTail -Lines $trimmed -MaxRows $availBodyRows -WrapColumns $cols
                            foreach ($dl in $tail) {
                                $outLines.Add("$dl$($pal.E_RST)")
                            }
                            $capturedBody = $true
                        }
                    }
                }
            } catch {
                Write-Verbose "Live pane dump skipped: $_"
            }
        }
        if (-not $capturedBody) {
            $outLines.Add(" $($pal.E_B01)(Live AI pane buffer is empty)$($pal.E_RST)")
        }
    } elseif ($workDir -and [System.IO.Directory]::Exists($workDir)) {
        $gitBin = Get-Command git.exe, git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gitBin -and $git.Branch) {
            $outLines.Add(" $($pal.E_B01)Recent commits (press Enter to launch workspace):$($pal.E_RST)")
            $logLines = @(& $gitBin.Source -C $workDir log -n ([Math]::Max(4, $availBodyRows - 2)) --color=always '--pretty=format: %C(yellow)%h%Creset %s %C(cyan)(%cr)%Creset' 2>$null)
            foreach ($ll in $logLines) { $outLines.Add("$ll") }
        } else {
            $outLines.Add(" $($pal.E_B01)Workspace files (press Enter to launch workspace):$($pal.E_RST)")
            $dirIco = if ($nf) { "`u{F024B} " } else { '+ ' }
            Get-ChildItem -LiteralPath $workDir -Force -ErrorAction SilentlyContinue |
                Select-Object -First ([Math]::Max(4, $availBodyRows - 2)) |
                ForEach-Object {
                    $prefix = if ($_.PSIsContainer) { "$($pal.E_BLU)$dirIco" } else { "$($pal.E_B0)  " }
                    $outLines.Add(" ${prefix}$($_.Name)$($pal.E_RST)")
                }
        }
    }

    return @{
        State = $rawSt
        Live  = $isLive
        Text  = ($outLines -join "`n")
    }
}

function Show-IdeSessionPreview([string]$TargetArg, [bool]$Follow = $false, [int]$MaxFrames = 0) {
    $sess = Resolve-TargetSession $TargetArg
    if (-not $Follow -or (Test-IdeReduceMotion)) {
        $single = Get-IdeSessionPreviewFrame $sess
        Write-Output $single.Text
        return
    }

    $intervalSec = 0.25
    $parsedInt = 0.0
    if ($env:IDE_PREVIEW_INTERVAL -and [double]::TryParse($env:IDE_PREVIEW_INTERVAL.Trim(), [ref]$parsedInt)) {
        $intervalSec = [Math]::Max(0.1, [Math]::Min(2.0, $parsedInt))
    }
    $sleepMs = [int][Math]::Round($intervalSec * 1000.0)
    $whileWorkingOnly = ($env:IDE_PREVIEW_WHILE_WORKING -eq '1')
    $parentProc = try { (Get-Process -Id $PID -ErrorAction SilentlyContinue).Parent } catch { $null }
    $maxFollowTicks = 720
    $tickCount = 0
    $esc = [char]27
    $lastText = ''
    $renderedCount = 0

    while ($true) {
        if ($null -ne $parentProc) {
            try {
                if ($parentProc.HasExited) { return }
            } catch {
                return
            }
        }
        $snap = Get-IdeSessionPreviewFrame $sess
        if ($snap.Text -ne $lastText) {
            try {
                if ($renderedCount -gt 0) {
                    [Console]::Out.Write("${esc}[H${esc}[2J")
                }
                [Console]::Out.WriteLine($snap.Text)
                [Console]::Out.Flush()
            } catch {
                return
            }
            $lastText = $snap.Text
            $renderedCount++
        }
        if ($MaxFrames -gt 0 -and $renderedCount -ge $MaxFrames) {
            return
        }
        $tickCount++
        if ($tickCount -ge $maxFollowTicks) {
            return
        }
        if (-not $snap.Live -or ($whileWorkingOnly -and $snap.State -ne 'WORKING')) {
            return
        }
        Start-Sleep -Milliseconds $sleepMs
    }
}

function Switch-OrAttachIdeSession(
    [string]$TargetSession,
    [string]$FocusRole = '',
    [string]$LayoutOverride = '',
    [string]$RequestedAi = '',
    [bool]$AiFromFlag = $false,
    [bool]$Detach = $false,
    [bool]$Desktop = $false,
    [bool]$NewWindow = $false,
    [string]$RequestedBackend = ''
) {
    $zellijBin = Resolve-ZellijExecutable
    $meta = Read-SessionState $TargetSession
    $liveZellij = Get-LiveZellijSessionMap

    if ($AiFromFlag -and $RequestedAi) {
        if (-not (Get-Command Invoke-IdeAgent -CommandType Function -ErrorAction SilentlyContinue)) {
            . (Join-Path (Get-IdeLibDir) 'Launcher.ps1')
        }
        Invoke-IdeAgent -CliArg $RequestedAi -SessionArg $TargetSession
        $meta = Read-SessionState $TargetSession
    }

    if (Test-IsCurrentZellijSession $TargetSession) {
        if ($FocusRole) {
            [void](Select-IdeRolePane -SessionName $TargetSession -Role $FocusRole -EnsureOnly $true)
        }
        exit 0
    }

    if (-not $zellijBin -or $RequestedBackend -eq 'wt') {
        if (-not (Get-Command Invoke-LaunchWorkspace -CommandType Function -ErrorAction SilentlyContinue)) {
            . (Join-Path (Get-IdeLibDir) 'Workspace.ps1')
        }
        $wdir = if ($meta -and $meta['workdir']) { [string]$meta['workdir'] } else { (Get-Location).ProviderPath }
        $effLay = if ($LayoutOverride) { $LayoutOverride } elseif ($meta -and $meta['layout']) { [string]$meta['layout'] } else { '3pane' }
        Invoke-LaunchWorkspace -TargetDirArg $wdir -Layout $effLay -RequestedBackend $RequestedBackend -RequestedAi $RequestedAi -AiFromFlag $AiFromFlag -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -IsDryRun $false
        exit 0
    }

    $env:ZELLIJ_CONFIG_DIR = Get-ZellijConfigDir
    $wdir = if ($meta -and $meta['workdir'] -and (Test-Path -LiteralPath $meta['workdir'])) {
        [string]$meta['workdir']
    } elseif ($meta -and $meta['root'] -and (Test-Path -LiteralPath $meta['root'])) {
        [string]$meta['root']
    } else {
        (Get-Location).ProviderPath
    }
    $effLayout = if ($LayoutOverride) { $LayoutOverride } elseif ($meta -and $meta['layout']) { [string]$meta['layout'] } else { '3pane' }
    $layName = if ($effLayout -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }

    if ($liveZellij[$TargetSession] -eq 'exited') {
        try { & $zellijBin delete-session $TargetSession *> $null } catch { Write-Verbose 'Cleared exited session stub' }
    }
    if ($FocusRole -and $liveZellij[$TargetSession] -eq 'live') {
        [void](Select-IdeRolePane -SessionName $TargetSession -Role $FocusRole -EnsureOnly $true)
    }
    if ($Detach) {
        if ($liveZellij[$TargetSession] -ne 'live') {
            & $zellijBin attach --create-background $TargetSession options --default-layout $layName --default-cwd $wdir
        }
        exit 0
    }
    if ($Desktop) {
        $zPsi = [System.Diagnostics.ProcessStartInfo]::new($zellijBin)
        $zPsi.WorkingDirectory = $wdir
        foreach ($a in @('terminal', '--standalone', '--create', '--working-directory', $wdir, $TargetSession, 'options', '--default-layout', $layName)) {
            $zPsi.ArgumentList.Add($a)
        }
        $zPsi.UseShellExecute = $false
        [void][System.Diagnostics.Process]::Start($zPsi)
        exit 0
    }
    if ($env:ZELLIJ -and -not $NewWindow) {
        & $zellijBin action switch-session --layout $layName --cwd $wdir $TargetSession
    } else {
        & $zellijBin attach --create $TargetSession options --default-layout $layName --default-cwd $wdir
    }
    exit $LASTEXITCODE
}

function Invoke-SessionSwitcher(
    [string]$SessionArg = '',
    [string]$Layout = '',
    [string]$RequestedAi = 'agy',
    [bool]$AiFromFlag = $false,
    [bool]$Detach = $false,
    [bool]$Desktop = $false,
    [bool]$NewWindow = $false,
    [string]$RequestedBackend = ''
) {
    if ($SessionArg -and $SessionArg.Trim()) {
        $cand = $SessionArg.Trim()
        $liveZ = Get-LiveZellijSessionMap
        $liveP = Get-LiveIdePipeMap
        $metaDirect = Read-SessionState $cand
        if ($metaDirect -or $liveZ.ContainsKey($cand) -or $liveP.ContainsKey($cand)) {
            Switch-OrAttachIdeSession `
                -TargetSession $cand `
                -LayoutOverride $Layout `
                -RequestedAi $RequestedAi `
                -AiFromFlag $AiFromFlag `
                -Detach $Detach `
                -Desktop $Desktop `
                -NewWindow $NewWindow `
                -RequestedBackend $RequestedBackend
        }
        if (-not (Get-Command Invoke-LaunchWorkspace -CommandType Function -ErrorAction SilentlyContinue)) {
            . (Join-Path (Get-IdeLibDir) 'Workspace.ps1')
        }
        Invoke-LaunchWorkspace `
            -TargetDirArg $cand `
            -Layout $(if ($Layout) { $Layout } else { '3pane' }) `
            -RequestedBackend $RequestedBackend `
            -RequestedAi $RequestedAi `
            -AiFromFlag $AiFromFlag `
            -Detach $Detach `
            -Desktop $Desktop `
            -NewWindow $NewWindow `
            -IsDryRun $false
        exit 0
    }

    $zellijBin = Resolve-ZellijExecutable
    if ($zellijBin -and $env:ZELLIJ -and $env:IDE_NATIVE_ZELLIJ_SESSIONS -eq '1') {
        & $zellijBin action launch-or-focus-plugin --floating --move-to-focused-tab 'zellij:session-manager' *> $null
        exit 0
    }

    $fzfBin = Resolve-FzfExecutable
    $isTty = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)

    if ($fzfBin -and $isTty) {
        if (-not (Get-Command Invoke-IdeDir -CommandType Function -ErrorAction SilentlyContinue)) {
            . (Join-Path (Get-IdeLibDir) 'Launcher.ps1')
        }
        while ($true) {
            $pal = Get-ActivePaletteMap
            $fleet = Get-ClassifiedIdeFleet -IncludeGit $true
            if ($fleet.Count -eq 0) {
                $env:IDE_FROM_SWITCHER = $null
                Invoke-IdeDir `
                    -Layout $(if ($Layout) { $Layout } else { '3pane' }) `
                    -RequestedAi $RequestedAi `
                    -AiFromFlag $AiFromFlag `
                    -Detach $Detach `
                    -Desktop $Desktop `
                    -NewWindow $NewWindow `
                    -RequestedBackend $RequestedBackend
                exit 0
            }

            $sz = Get-IdeTerminalSize
            $cols = [int]$sz.Columns
            $previewWin = if ($cols -lt 90) { 'down:50%:wrap:noinfo' } else { 'right:56%:wrap:noinfo' }
            $listCols = if ($cols -lt 90) { [Math]::Max(36, $cols - 6) } else { [Math]::Max(36, [int][Math]::Floor($cols * 0.44) - 4) }

            $widths = Measure-FleetColumnWidth -Fleet $fleet -MaxTotalColumns $listCols
            $rows = Format-FzfSessionRowList -Fleet $fleet -Widths $widths
            $hdrLine = Format-FleetTableHeader $widths

            $footerHints = @(
                'Enter: switch',
                'Alt+n: new',
                'Alt+o: dir',
                'Alt+r: agent',
                'Ctrl+y: ack',
                'Ctrl+o: PR',
                'Ctrl+x: quit',
                'F1: keys'
            )
            $footerLabel = Format-IdeCardFooter -Hints $footerHints -InnerWidth ([Math]::Max(30, $cols - 6))
            $heightArg = if ($env:IDE_SESSIONS_MODAL -eq '1' -or $env:ZELLIJ) { '--height=100%' } else { '--height=80%' }

            $pwshExe = Get-CurrentPwshExecutable
            $entryQuoted = "`"$(Get-IdeEntryScriptPath)`""
            $pwshQuoted = "`"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File $entryQuoted"
            $reloadCmd = "$pwshQuoted _internal sessions-lines"
            $previewCmd = "$pwshQuoted _internal session-preview --follow {1}"
            $fzfColors = Format-FzfPaletteOption $pal

            $prevWhileWorking = $env:IDE_PREVIEW_WHILE_WORKING
            $env:IDE_PREVIEW_WHILE_WORKING = '1'
            try {
                $rawOut = @($rows | & $fzfBin `
                    --ansi `
                    "--delimiter=`t" `
                    --with-nth=2.. `
                    --multi `
                    --layout=reverse `
                    $heightArg `
                    "--header=$hdrLine" `
                    --info=inline-right `
                    '--prompt=IDE > ' `
                    --border=rounded `
                    "--border-label=$footerLabel" `
                    --border-label-pos=bottom `
                    "--preview=$previewCmd" `
                    "--preview-window=$previewWin" `
                    --expect=ctrl-a,ctrl-e,ctrl-t,alt-a,alt-e,alt-t,ctrl-n,alt-n,alt-o,alt-r `
                    '--bind=alt-s:abort' `
                    "--bind=ctrl-r:reload($reloadCmd),f5:reload($reloadCmd)" `
                    "--bind=ctrl-y:execute-silent($pwshQuoted ack {+1})+reload($reloadCmd)" `
                    "--bind=ctrl-o:execute-silent($pwshQuoted pr {1})" `
                    "--bind=ctrl-x:execute-silent($pwshQuoted quit {+1})+reload($reloadCmd)" `
                    "--bind=f1:execute($pwshQuoted keys),alt-?:execute($pwshQuoted keys)" `
                    $fzfColors)
                $fzfRc = $LASTEXITCODE
            } finally {
                $env:IDE_PREVIEW_WHILE_WORKING = $prevWhileWorking
            }

            if ($fzfRc -ne 0 -or $rawOut.Count -eq 0) {
                exit 0
            }

            $keyPressed = "$($rawOut[0])".Trim()
            $selLine = if ($rawOut.Count -ge 2) { "$($rawOut[1])" } else { '' }
            $chosen = ($selLine -split "`t")[0].Trim()
            $effLay = if ($Layout) { $Layout } else { '3pane' }

            if ($keyPressed -in @('ctrl-n', 'alt-n')) {
                $env:IDE_FROM_SWITCHER = '1'
                Invoke-IdeNew -Layout $effLay -RequestedAi $RequestedAi -AiFromFlag $AiFromFlag -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -RequestedBackend $RequestedBackend
                exit 0
            }
            if ($keyPressed -eq 'alt-o') {
                $env:IDE_FROM_SWITCHER = '1'
                Invoke-IdeDir -Layout $effLay -RequestedAi $RequestedAi -AiFromFlag $AiFromFlag -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -RequestedBackend $RequestedBackend
                exit 0
            }
            if ($keyPressed -eq 'alt-r') {
                if ($chosen) {
                    $env:IDE_FROM_SWITCHER = '1'
                    Invoke-IdeAgent -SessionArg $chosen
                    $env:IDE_FROM_SWITCHER = $null
                }
                continue
            }

            if ($chosen) {
                $focusRole = switch ($keyPressed) {
                    { $_ -in @('ctrl-a', 'alt-a') } { 'ai' }
                    { $_ -in @('ctrl-e', 'alt-e') } { 'editor' }
                    { $_ -in @('ctrl-t', 'alt-t') } { 'shell' }
                    default                         { '' }
                }
                Switch-OrAttachIdeSession `
                    -TargetSession $chosen `
                    -FocusRole $focusRole `
                    -LayoutOverride $Layout `
                    -RequestedAi $RequestedAi `
                    -AiFromFlag $AiFromFlag `
                    -Detach $Detach `
                    -Desktop $Desktop `
                    -NewWindow $NewWindow `
                    -RequestedBackend $RequestedBackend
            }
            exit 0
        }
    }

    Show-IdeSessionList -Plain $false -Json $false
    exit 0
}

function Invoke-NextAttention([string]$TargetArg = '') {
    $zBin = Resolve-ZellijExecutable
    $fleet = Get-ClassifiedIdeFleet -IncludeGit $false
    $originSess = if ($TargetArg) { Resolve-TargetSession $TargetArg } else { Get-CurrentZellijSessionToken }
    $topAttn = $fleet | Where-Object { $_.Status -eq 'live' -and $_.NeedsAttn -and $_.Session -ne $originSess } | Select-Object -First 1
    if (-not $topAttn) {
        $topAttn = $fleet | Where-Object { $_.Status -eq 'live' -and $_.NeedsAttn } | Select-Object -First 1
    }
    if ($topAttn -and $zBin) {
        Switch-OrAttachIdeSession -TargetSession $topAttn.Session -FocusRole 'ai'
    }
    if ($zBin -and $env:ZELLIJ) {
        & $zBin action go-to-next-attention *> $null
        exit 0
    }
    Write-Output 'No IDE agents waiting for attention.'
    exit 0
}

function Show-IdeSessionList([bool]$Plain = $false, [bool]$Json = $false) {
    if ($Plain) {
        $fleetPlain = Get-ClassifiedIdeFleet -IncludeGit $false
        foreach ($e in $fleetPlain) {
            Write-Output $e.Session
        }
        return
    }

    $fleet = Get-ClassifiedIdeFleet -IncludeGit $true
    if ($Json) {
        if ($fleet.Count -eq 0) {
            Write-Output '[]'
            return
        }
        $jsonItems = [System.Collections.Generic.List[object]]::new()
        foreach ($e in $fleet) {
            $jsonItems.Add([ordered]@{
                session         = [string]$e.Session
                agent           = [string]$e.AiCli
                state           = [string]$e.State
                state_label     = [string]$e.StateLabel
                state_ts        = [long]$e.StateTs
                needs_attention = [bool]$e.NeedsAttn
                attention_ts    = [long]$e.AttnTs
                message         = [string]$e.Message
                workdir         = [string]$e.RawWorkdir
                git_branch      = [string]$e.GitBranch
                git_dirty       = [bool]$e.GitDirty
                git_detail      = [string]$e.GitDetail
                git_pr_url      = [string]$e.GitPrUrl
                worktree_root   = [string]$e.WorktreeRoot
                worktree_peers  = [string[]]@($e.WorktreePeers)
                active_role     = [string]$e.ActiveRole
                attached        = [bool]$e.Attached
                is_current      = [bool]$e.IsCurrent
                quit_error      = [string]$e.QuitError
            })
        }
        Write-Output ($jsonItems.ToArray() | ConvertTo-Json -Depth 5 -AsArray)
        return
    }

    if ($fleet.Count -eq 0) {
        Write-Output 'No IDE workspace sessions found.'
        return
    }

    $pal = Get-ActivePaletteMap
    $useColor = (-not [Console]::IsOutputRedirected) -and ($pal.TIER -ne 'nocolor')

    $maxCols = 0
    $parsedListCols = 0
    if ($env:IDE_LIST_COLUMNS -and [int]::TryParse($env:IDE_LIST_COLUMNS.Trim(), [ref]$parsedListCols) -and $parsedListCols -gt 0) {
        $maxCols = $parsedListCols
    } elseif (-not [Console]::IsOutputRedirected) {
        $maxCols = [int](Get-IdeTerminalSize).Columns
    }

    $widths = Measure-FleetColumnWidth -Fleet $fleet -MaxTotalColumns $maxCols
    $hdr = Format-FleetTableHeader $widths
    if ($useColor) {
        Write-Output "$($pal.E_B01)${hdr}$($pal.E_RST)"
    } else {
        Write-Output $hdr
    }

    foreach ($e in $fleet) {
        Write-Output (Format-FleetTableLine -Entry $e -Pal $pal -Widths $widths -UseColor $useColor)
    }
}
