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

function Get-GitPrCacheStatePath([string]$RepoRoot, [string]$Branch) {
    $prCacheDir = Join-Path (Join-Path (Get-UserHomeDir) '.cache') 'git-pr-prompt'
    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$RepoRoot|$Branch")
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
    $key = [System.BitConverter]::ToString($hashBytes, 0, 8).Replace('-', '').ToLowerInvariant()
    return (Join-Path $prCacheDir "$key.state")
}

function Get-FastGitSummary([string]$Workdir) {
    $empty = @{
        Root     = ''
        Branch   = ''
        PrBadge  = ''
        PrUrl    = ''
        ForgeUrl = ''
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
                return $empty
            }
            break
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    if (-not $repoRoot -or -not $gitDir) { return $empty }

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

    $prBadge = ''
    $prUrl = ''
    if ($branch -and $branch -notin @('main', 'master', 'trunk')) {
        $stateFile = Get-GitPrCacheStatePath -RepoRoot $repoRoot -Branch $branch
        if ([System.IO.File]::Exists($stateFile)) {
            try {
                $lines = [System.IO.File]::ReadAllLines($stateFile)
                if ($lines.Count -ge 2 -and $lines[0].Trim() -and $lines[1].Trim()) {
                    $prBadge = $lines[0].Trim()
                    $prUrl = $lines[1].Trim()
                }
            } catch {
                Write-Verbose "PR cache read skipped: $_"
            }
        }
    }

    $forgeUrl = ''
    $cfgFile = Join-Path $commonGitDir 'config'
    if ([System.IO.File]::Exists($cfgFile)) {
        try {
            $inOrigin = $false
            foreach ($cfgLine in [System.IO.File]::ReadLines($cfgFile)) {
                $trimmed = $cfgLine.Trim()
                if ($trimmed.StartsWith('[')) {
                    $inOrigin = ($trimmed -match '^\[remote\s+"origin"\]')
                    continue
                }
                if ($inOrigin -and $trimmed -match '^url\s*=\s*(.+)$') {
                    $forgeUrl = ConvertTo-ForgeHttpsBase $Matches[1].Trim()
                    break
                }
            }
        } catch {
            Write-Verbose "Git config origin parse skipped: $_"
        }
    }

    return @{
        Root     = $repoRoot
        Branch   = $branch
        PrBadge  = $prBadge
        PrUrl    = $prUrl
        ForgeUrl = $forgeUrl
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

    $git = Get-FastGitSummary $wdir
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

    $curSess = Get-CurrentZellijSessionToken
    if (-not $curSess -and $env:IDE_SESSION -and $env:IDE_SESSION.Trim()) {
        $curSess = Get-SanitizedToken $env:IDE_SESSION.Trim()
    }

    $userHome = Get-UserHomeDir
    $normHome = if ($userHome) { $userHome.TrimEnd('\', '/') } else { '' }
    $liveWorkdirCounts = @{}
    foreach ($k in $sessions.Keys) {
        $m = $sessions[$k]
        $zSt = $liveZellij[$k]
        $pUp = $livePipes.ContainsKey($k) -or (Test-IdePipeLive ([string]$m['pipe']))
        if ($zSt -eq 'live' -or $pUp) {
            $wd = if ($m['workdir']) { [string]$m['workdir'] } elseif ($m['root']) { [string]$m['root'] } else { '' }
            if ($wd) {
                $normWd = $wd.TrimEnd('\', '/').ToLowerInvariant()
                $liveWorkdirCounts[$normWd] = $(if ($liveWorkdirCounts.ContainsKey($normWd)) { $liveWorkdirCounts[$normWd] } else { 0 }) + 1
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
        $tier = 4
        $dispState = 'IDLE'
        $needsAttn = $false
        if ($status -ne 'live') {
            $tier = 4
            $dispState = $status.ToUpperInvariant()
        } elseif ($aiCli -eq 'shell') {
            $tier = 4
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
                'quota' {
                    $tier = 2
                    $dispState = 'QUOTA'
                }
                { $_ -in @('running', 'working') } {
                    $tier = 2
                    $dispState = 'WORKING'
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
        $shortPath = if (-not $wdir) {
            '-'
        } elseif ($normHome -and $wdir.StartsWith($normHome, [System.StringComparison]::OrdinalIgnoreCase)) {
            '~' + $wdir.Substring($normHome.Length)
        } else {
            $wdir
        }
        $hasWtWarn = $false
        if ($status -eq 'live' -and $wdir) {
            $normWd = $wdir.TrimEnd('\', '/').ToLowerInvariant()
            if ($liveWorkdirCounts[$normWd] -gt 1) {
                $hasWtWarn = $true
            }
        }

        $branchLabel = '-'
        if ($IncludeGit -and $wdir) {
            $git = Get-FastGitSummary $wdir
            if ($git.Branch) {
                $branchLabel = "$($git.Branch)$($git.PrBadge)"
            }
        }

        $entries.Add(@{
            Session     = $k
            Status      = $status
            Layout      = if ($m['layout']) { [string]$m['layout'] } else { '3pane' }
            AiCli       = $aiCli
            State       = $dispState
            StateLabel  = $stateLabel
            NeedsAttn   = $needsAttn
            Tier        = $tier
            SortTs      = if ($attnTs -gt 0) { $attnTs } else { $stateTs }
            BranchLabel = $branchLabel
            Workdir     = if ($wdir) { $wdir } else { '-' }
            ShortPath   = $shortPath
            HasPeerWarn = $hasWtWarn
            IsCurrent   = ($curSess -and [string]::Equals($k, $curSess, [System.StringComparison]::OrdinalIgnoreCase))
            Message     = if ($m['agent_message']) { [string]$m['agent_message'] } else { '' }
        })
    }

    return @($entries | Sort-Object `
        @{ Expression = { $_.Tier }; Ascending = $true }, `
        @{ Expression = { $_.SortTs }; Ascending = $true }, `
        @{ Expression = { $_.Session }; Ascending = $true })
}

function Measure-FleetColumnWidth([object[]]$Fleet) {
    $sessW = 7
    $cliW = 5
    $stateW = 5
    $gitW = 6
    foreach ($e in $Fleet) {
        if ($e.Session.Length -gt $sessW) { $sessW = [Math]::Min(28, $e.Session.Length) }
        if ($e.AiCli.Length -gt $cliW) { $cliW = [Math]::Min(12, $e.AiCli.Length) }
        if ($e.StateLabel.Length -gt $stateW) { $stateW = [Math]::Min(16, $e.StateLabel.Length) }
        if ($e.BranchLabel.Length -gt $gitW) { $gitW = [Math]::Min(28, $e.BranchLabel.Length) }
    }
    return @{
        SessW  = $sessW
        CliW   = $cliW
        StateW = $stateW
        GitW   = $gitW
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
    $sPad = ([string]$Entry.Session).PadRight([int]$Widths.SessW)
    $cPad = ([string]$Entry.AiCli).PadRight([int]$Widths.CliW)
    $stPad = ([string]$Entry.StateLabel).PadRight([int]$Widths.StateW)
    $gPad = ([string]$Entry.BranchLabel).PadRight([int]$Widths.GitW)
    if ($UseColor) {
        $attnC = if ($Entry.State -eq 'DONE') { $Pal.E_GRN } elseif ($Entry.State -eq 'ERROR') { $Pal.E_RED } else { $Pal.E_ORG }
        $marker = if ($Entry.IsCurrent) {
            "$($Pal.E_CYN)`u{25B8}$($Pal.E_RST)"
        } elseif ($Entry.NeedsAttn) {
            "${attnC}`u{F009A}$($Pal.E_RST)"
        } else {
            ' '
        }
        $cSess = if ($Entry.IsCurrent) { $Pal.E_B1 } elseif ($Entry.NeedsAttn) { $attnC } elseif ($Entry.Status -ne 'live') { $Pal.E_B01 } else { $Pal.E_BLU }
        $cState = switch ($Entry.State) {
            'ATTN'    { $Pal.E_ORG }
            'ERROR'   { $Pal.E_RED }
            'DONE'    { $Pal.E_GRN }
            'QUOTA'   { $Pal.E_YLW }
            'WORKING' { $Pal.E_BLU }
            'IDLE'    { $Pal.E_CYN }
            default   { $Pal.E_B01 }
        }
        $cGit = if ($Entry.BranchLabel -eq '-') { $Pal.E_B01 } elseif ($Entry.BranchLabel -match '[@!][0-9]+$') { $Pal.E_CYN } else { $Pal.E_GRN }
        $wtSfx = if ($Entry.HasPeerWarn) { " $($Pal.E_YLW)!$($Pal.E_RST)" } else { '' }
        return "$marker ${cSess}${sPad}$($Pal.E_RST)  $($Pal.E_B0)${cPad}$($Pal.E_RST)  ${cState}${stPad}$($Pal.E_RST)  ${cGit}${gPad}$($Pal.E_RST)  $($Pal.E_B0)$($Entry.ShortPath)$($Pal.E_RST)${wtSfx}"
    }
    $plainMarker = if ($Entry.IsCurrent) { '*' } elseif ($Entry.NeedsAttn) { '!' } else { ' ' }
    $plainSfx = if ($Entry.HasPeerWarn) { ' !' } else { '' }
    return "$plainMarker $sPad  $cPad  $stPad  $gPad  $($Entry.ShortPath)$plainSfx"
}

function Format-FzfSessionRowList([object[]]$Fleet = $null, [hashtable]$Widths = $null) {
    $resolvedFleet = if ($null -ne $Fleet) { $Fleet } else { Get-ClassifiedIdeFleet -IncludeGit $true }
    if ($resolvedFleet.Count -eq 0) { return @() }
    $pal = Get-ActivePaletteMap
    $w = if ($Widths) { $Widths } else { Measure-FleetColumnWidth $resolvedFleet }
    $rows = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $resolvedFleet) {
        $line = Format-FleetTableLine -Entry $e -Pal $pal -Widths $w -UseColor $true
        $rows.Add("$($e.Session)`t$line")
    }
    return $rows.ToArray()
}

function Show-IdeSessionPreview([string]$TargetArg) {
    $sess = Resolve-TargetSession $TargetArg
    $meta = Read-SessionState $sess
    $liveZellij = Get-LiveZellijSessionMap
    $pal = Get-ActivePaletteMap
    $isLive = ($liveZellij[$sess] -eq 'live')
    $isCurrent = ($isLive -and (Test-IsCurrentZellijSession $sess))

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
    $rawSt = if ($meta -and $meta['agent_state']) { ([string]$meta['agent_state']).ToUpperInvariant() } else { 'IDLE' }
    if ($rawSt -eq 'RUNNING') { $rawSt = 'WORKING' }
    if ($rawSt -eq 'APPROVAL') { $rawSt = 'ATTN' }
    $cSt = switch ($rawSt) {
        'ATTN'    { $pal.E_ORG }
        'QUOTA'   { $pal.E_YLW }
        'ERROR'   { $pal.E_RED }
        'DONE'    { $pal.E_GRN }
        'WORKING' { $pal.E_BLU }
        default   { $pal.E_CYN }
    }
    $agentMsg = if ($meta -and $meta['agent_message']) { [string]$meta['agent_message'] } else { '' }
    $git = if ($workDir) { Get-FastGitSummary $workDir } else { @{ Branch = ''; PrBadge = ''; PrUrl = '' } }

    $cols = 64
    $parsedCols = 0
    if ($env:FZF_PREVIEW_COLUMNS -and [int]::TryParse($env:FZF_PREVIEW_COLUMNS.Trim(), [ref]$parsedCols)) {
        $cols = [Math]::Max(36, $parsedCols - 2)
    }
    $previewRows = 28
    $parsedRows = 0
    if ($env:FZF_PREVIEW_LINES -and [int]::TryParse($env:FZF_PREVIEW_LINES.Trim(), [ref]$parsedRows)) {
        $previewRows = [Math]::Max(12, $parsedRows)
    }

    $dotSep = "`u{00B7}"
    $ruleCh = "`u{2500}"
    $headerLines = [System.Collections.Generic.List[string]]::new()
    $headerLines.Add(" $($pal.E_BLU)`u{EBC8} $sess$($pal.E_RST)  $statusTag  $($pal.E_B01)$dotSep$($pal.E_RST)  $($pal.E_B0)$layout$($pal.E_RST)  $($pal.E_B01)$dotSep$($pal.E_RST)  $($pal.E_YLW)$aiCli$($pal.E_RST) (${cSt}${rawSt}$($pal.E_RST))")
    if ($workDir) {
        $divNote = if ($initRoot -and -not [string]::Equals($initRoot.TrimEnd('\', '/'), $workDir.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
            " $($pal.E_B01)(root: $initRoot)$($pal.E_RST)"
        } else {
            ''
        }
        $headerLines.Add(" $($pal.E_B01)Dir   :$($pal.E_RST) $($pal.E_B0)$workDir$($pal.E_RST)$divNote")
    }
    if ($git.Branch) {
        $prInfo = if ($git.PrBadge) { "  $($pal.E_CYN)$($git.PrBadge)$($pal.E_RST)" } else { '' }
        $prLink = if ($git.PrUrl) { " $($pal.E_B01)($($git.PrUrl))$($pal.E_RST)" } else { '' }
        $headerLines.Add(" $($pal.E_B01)Branch:$($pal.E_RST) $($pal.E_GRN)$($git.Branch)$($pal.E_RST)${prInfo}${prLink}")
    }
    if ($agentMsg) {
        $headerLines.Add(" $($pal.E_B01)Note  :$($pal.E_RST) $($pal.E_B0)$agentMsg$($pal.E_RST)")
    }
    $headerLines.Add(" $($pal.E_B01)$($ruleCh * [Math]::Max(20, $cols))$($pal.E_RST)")

    foreach ($hl in $headerLines) {
        Write-Output $hl
    }

    $availBodyRows = [Math]::Max(6, $previewRows - $headerLines.Count - 1)
    if ($isLive) {
        $zellijBin = Resolve-ZellijExecutable
        $aiPane = Get-RolePaneId -SessionName $sess -Role 'ai'
        if (-not $aiPane) { $aiPane = 'terminal_0' }
        if ($zellijBin) {
            try {
                $psi = [System.Diagnostics.ProcessStartInfo]::new($zellijBin)
                if (-not $isCurrent) {
                    $psi.ArgumentList.Add('--session')
                    $psi.ArgumentList.Add($sess)
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
                    if (-not $proc.WaitForExit(1500)) {
                        try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out dump-screen terminated' }
                    } elseif ($dumpRaw) {
                        $rawLines = @($dumpRaw -split "`r?`n")
                        $lastNonBlank = $rawLines.Count - 1
                        while ($lastNonBlank -ge 0) {
                            $stripped = [regex]::Replace($rawLines[$lastNonBlank], "\x1b\[[0-9;?]*[ -/]*[@-~]", '').Trim()
                            if ($stripped.Length -gt 0) { break }
                            $lastNonBlank--
                        }
                        if ($lastNonBlank -ge 0) {
                            $trimmed = $rawLines[0..$lastNonBlank]
                            $startIdx = [Math]::Max(0, $trimmed.Count - $availBodyRows)
                            foreach ($dl in $trimmed[$startIdx..($trimmed.Count - 1)]) {
                                Write-Output $dl
                            }
                            return
                        }
                    }
                }
            } catch {
                Write-Verbose "Live pane dump skipped: $_"
            }
        }
        Write-Output " $($pal.E_B01)(Live AI pane buffer is empty)$($pal.E_RST)"
        return
    }

    if ($workDir -and [System.IO.Directory]::Exists($workDir)) {
        $gitBin = Get-Command git.exe, git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($gitBin -and $git.Branch) {
            Write-Output " $($pal.E_B01)Recent commits (press Enter to launch workspace):$($pal.E_RST)"
            $logLines = @(& $gitBin.Source -C $workDir log -n ([Math]::Max(4, $availBodyRows - 2)) --color=always '--pretty=format: %C(yellow)%h%Creset %s %C(cyan)(%cr)%Creset' 2>$null)
            foreach ($ll in $logLines) { Write-Output $ll }
            return
        }
        Write-Output " $($pal.E_B01)Workspace files (press Enter to launch workspace):$($pal.E_RST)"
        Get-ChildItem -LiteralPath $workDir -Force -ErrorAction SilentlyContinue |
            Select-Object -First ([Math]::Max(4, $availBodyRows - 2)) |
            ForEach-Object {
                $prefix = if ($_.PSIsContainer) { "$($pal.E_BLU)`u{F024B} " } else { "$($pal.E_B0)  " }
                Write-Output " ${prefix}$($_.Name)$($pal.E_RST)"
            }
    }
}

function Format-FzfPaletteOption([hashtable]$Pal) {
    return "--color=bg+:$($Pal.BASE02),bg:$($Pal.BASE03),spinner:$($Pal.GREEN),hl:$($Pal.BASE01),fg:$($Pal.BASE0),header:$($Pal.BASE01),info:$($Pal.YELLOW),pointer:$($Pal.GREEN),marker:$($Pal.GREEN),fg+:$($Pal.BASE1),prompt:$($Pal.YELLOW),hl+:$($Pal.BLUE),label:$($Pal.BASE01)"
}

function Invoke-ZoxideNewWorkspacePicker([hashtable]$Pal, [string]$FzfPath, [string]$HeightArg) {
    $zoxCmd = Get-Command zoxide -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $zoxCmd) { return }
    $dirs = @(& $zoxCmd.Source query -l 2>$null)
    if ($dirs.Count -eq 0) { return }
    $fzfColors = Format-FzfPaletteOption $Pal
    $pickedDir = ($dirs | & $FzfPath --layout=reverse $HeightArg --border=rounded '--prompt=New IDE Dir > ' '--border-label= Enter: launch IDE workspace | Esc: cancel ' --border-label-pos=bottom $fzfColors | Out-String).Trim()
    if ($LASTEXITCODE -eq 0 -and $pickedDir -and (Test-Path -LiteralPath $pickedDir -PathType Container)) {
        $pwshExe = Get-CurrentPwshExecutable
        $entryScript = Get-IdeEntryScriptPath
        & $pwshExe -NoProfile -ExecutionPolicy Bypass -File $entryScript $pickedDir
        exit $LASTEXITCODE
    }
}

function Invoke-SessionSwitcher {
    $zellijBin = Resolve-ZellijExecutable
    if ($zellijBin -and $env:ZELLIJ -and $env:IDE_NATIVE_ZELLIJ_SESSIONS -eq '1') {
        & $zellijBin action launch-or-focus-plugin --floating --move-to-focused-tab 'zellij:session-manager' *> $null
        exit 0
    }
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($zellijBin -and $fzfCmd -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
        $pal = Get-ActivePaletteMap
        $heightArg = if ($env:IDE_SESSIONS_MODAL -eq '1') { '--height=100%' } else { '--height=75%' }
        $fleet = Get-ClassifiedIdeFleet -IncludeGit $true
        if ($fleet.Count -eq 0) {
            Invoke-ZoxideNewWorkspacePicker -Pal $pal -FzfPath $fzfCmd.Source -HeightArg $heightArg
            exit 0
        }
        $widths = Measure-FleetColumnWidth $fleet
        $rows = Format-FzfSessionRowList -Fleet $fleet -Widths $widths
        $hdrLine = Format-FleetTableHeader $widths

        $pwshExe = Get-CurrentPwshExecutable
        $entryQuoted = "`"$(Get-IdeEntryScriptPath)`""
        $pwshQuoted = "`"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File $entryQuoted"
        $reloadCmd = "$pwshQuoted --sessions-lines"
        $previewCmd = "$pwshQuoted --session-preview {1}"
        $fzfColors = Format-FzfPaletteOption $pal

        $rawOut = @($rows | & $fzfCmd.Source `
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
            '--border-label= Enter: switch | C-a/e/t: role | C-n: new | C-o: PR | C-y: ack | C-x: quit | C-r: reload ' `
            --border-label-pos=bottom `
            "--preview=$previewCmd" `
            --preview-window=right:52%:wrap:border-left `
            --expect=ctrl-a,ctrl-e,ctrl-t,ctrl-n,alt-n `
            "--bind=ctrl-r:reload($reloadCmd)" `
            "--bind=ctrl-y:execute-silent($pwshQuoted --ack-ai {+1})+reload($reloadCmd)" `
            "--bind=ctrl-o:execute-silent($pwshQuoted --open-pr {1})" `
            "--bind=ctrl-x:execute-silent($pwshQuoted --quit {+1})+reload($reloadCmd)" `
            $fzfColors)

        if ($LASTEXITCODE -ne 0 -or $rawOut.Count -eq 0) {
            exit 0
        }
        $keyPressed = "$($rawOut[0])".Trim()
        if ($keyPressed -in @('ctrl-n', 'alt-n')) {
            Invoke-ZoxideNewWorkspacePicker -Pal $pal -FzfPath $fzfCmd.Source -HeightArg $heightArg
            exit 0
        }

        $selLine = if ($rawOut.Count -ge 2) { "$($rawOut[1])" } else { '' }
        $chosen = ($selLine -split "`t")[0].Trim()
        if ($chosen) {
            $focusRole = switch ($keyPressed) {
                'ctrl-a' { 'ai' }
                'ctrl-e' { 'editor' }
                'ctrl-t' { 'shell' }
                default  { '' }
            }
            if (Test-IsCurrentZellijSession $chosen) {
                if ($focusRole) {
                    [void](Select-IdeRolePane -SessionName $chosen -Role $focusRole -EnsureOnly $true)
                }
                exit 0
            }

            $env:ZELLIJ_CONFIG_DIR = Get-ZellijConfigDir
            $meta = Read-SessionState $chosen
            $wdir = if ($meta -and $meta['workdir'] -and (Test-Path -LiteralPath $meta['workdir'])) { [string]$meta['workdir'] } else { (Get-Location).ProviderPath }
            $lay = if ($meta -and $meta['layout'] -eq '2pane') { 'ide-2pane' } else { 'ide-3pane' }
            $liveZellij = Get-LiveZellijSessionMap
            if ($focusRole -and $liveZellij[$chosen] -eq 'live') {
                [void](Select-IdeRolePane -SessionName $chosen -Role $focusRole -EnsureOnly $true)
            }
            if ($env:ZELLIJ) {
                & $zellijBin action switch-session --layout $lay --cwd $wdir $chosen
            } else {
                & $zellijBin attach --create $chosen options --default-layout $lay --default-cwd $wdir
            }
            exit $LASTEXITCODE
        }
        exit 0
    }
    Show-IdeSessionList -Plain $false
    exit 0
}

function Invoke-NextAttention {
    $zBin = Resolve-ZellijExecutable
    if (-not $zBin) { exit 0 }
    if ($env:ZELLIJ) {
        & $zBin action go-to-next-attention *> $null
        exit 0
    }
    $fleet = Get-ClassifiedIdeFleet -IncludeGit $false
    $topAttn = $fleet | Where-Object { $_.Status -eq 'live' -and $_.NeedsAttn } | Select-Object -First 1
    if ($topAttn) {
        $env:ZELLIJ_CONFIG_DIR = Get-ZellijConfigDir
        [void](Select-IdeRolePane -SessionName $topAttn.Session -Role 'ai' -EnsureOnly $true)
        & $zBin attach $topAttn.Session
        exit $LASTEXITCODE
    }
    Invoke-SessionSwitcher
}

function Show-IdeSessionList([bool]$Plain) {
    $fleet = Get-ClassifiedIdeFleet -IncludeGit (-not $Plain)
    if ($Plain) {
        foreach ($e in $fleet) {
            Write-Output $e.Session
        }
        return
    }

    if ($fleet.Count -eq 0) {
        Write-Output 'No IDE workspace sessions found.'
        return
    }

    $useColor = (-not [Console]::IsOutputRedirected) -and (-not $env:NO_COLOR)
    $pal = Get-ActivePaletteMap
    $widths = Measure-FleetColumnWidth $fleet
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
