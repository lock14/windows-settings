# ==============================================================================
# Launcher.ps1 - Interactive workspace creator (new), directory picker (dir) & agent switcher
# ==============================================================================

function Get-IdeAgentCandidateList([string]$CurrentCli = '') {
    $list = [System.Collections.Generic.List[string]]::new()
    if ($CurrentCli -and $CurrentCli -ne 'shell' -and $CurrentCli -notin @('agy', 'claude', 'codex')) {
        $list.Add($CurrentCli)
    }
    foreach ($std in @('agy', 'claude', 'codex')) {
        if (-not $list.Contains($std)) {
            $list.Add($std)
        }
    }
    return ,$list.ToArray()
}

function Get-IdeNewCardPreview([string]$RawInputText) {
    $parentDir = Get-IdeWorkspaceParent
    $hasCreateHook = Test-IdeHookDefined 'New-IdeWorkspace'
    $trimmed = if ($RawInputText) { $RawInputText.Trim() } else { '' }
    if (-not $trimmed) {
        $defTarget = if ($hasCreateHook) {
            'New-IdeWorkspace <name>'
        } else {
            Join-Path (Format-IdeShortHome $parentDir) '<name>'
        }
        return @{
            Session = '(type a workspace name)'
            Target  = $defTarget
            Error   = ''
            IsEmpty = $true
        }
    }

    if ($trimmed -in @('.', '..', '/', '\', '~')) {
        return @{ Session = '-'; Target = '-'; Error = 'Invalid workspace name.'; IsEmpty = $false }
    }
    foreach ($ch in $trimmed.ToCharArray()) {
        if ([int]$ch -lt 32 -or [int]$ch -eq 127) {
            return @{ Session = '-'; Target = '-'; Error = 'Control characters are not allowed.'; IsEmpty = $false }
        }
    }
    $segs = @($trimmed.Replace('/', '\') -split '\\' | Where-Object { $_ -ne '' })
    if ($segs -contains '..') {
        return @{ Session = '-'; Target = '-'; Error = "Path traversal ('..') is not allowed."; IsEmpty = $false }
    }

    if ([System.IO.Path]::IsPathRooted($trimmed) -or $trimmed.StartsWith('~\') -or $trimmed.StartsWith('~/') -or $trimmed.StartsWith('.\') -or $trimmed.StartsWith('./')) {
        $candPath = try { Expand-IdeUserPath $trimmed } catch { '' }
    } else {
        $candPath = try { [System.IO.Path]::GetFullPath((Join-Path $parentDir ($segs -join [System.IO.Path]::DirectorySeparatorChar))) } catch { '' }
    }

    $leaf = if ($candPath) { Split-Path -Leaf $candPath.TrimEnd('\', '/') } else { $segs[-1] }
    $sessSlug = Get-SanitizedToken $leaf

    if ($hasCreateHook) {
        $targetDisp = "New-IdeWorkspace $trimmed"
    } elseif ($candPath) {
        $existsTag = if ([System.IO.Directory]::Exists($candPath)) { ' (exists)' } else { ' (mkdir)' }
        $targetDisp = (Format-IdeShortHome $candPath) + $existsTag
    } else {
        $targetDisp = $trimmed
    }

    return @{
        Session = $sessSlug
        Target  = $targetDisp
        Error   = ''
        IsEmpty = $false
    }
}

function Format-IdeBoxRow([string]$BodyContent, [int]$InnerWidth, [hashtable]$Pal) {
    $vBar = "`u{2502}"
    $padded = Format-IdePadVisible -Text $BodyContent -Width $InnerWidth
    return "$($Pal.E_B01)$vBar$($Pal.E_RST)$padded$($Pal.E_B01)$vBar$($Pal.E_RST)"
}

function Format-IdeBoxBorder([string]$LeftCorner, [string]$RightCorner, [string]$LabelText, [string]$LabelColor, [int]$InnerWidth, [hashtable]$Pal) {
    $hBar = "`u{2500}"
    if (-not $LabelText) {
        return "$($Pal.E_B01)$LeftCorner$($hBar * $InnerWidth)$RightCorner$($Pal.E_RST)"
    }
    $lblVis = Get-IdeVisibleWidth $LabelText
    if ($lblVis + 2 -ge $InnerWidth) {
        $clipped = Format-IdeTruncVisible -Text $LabelText -MaxWidth ([Math]::Max(1, $InnerWidth - 2))
        $lblVis = Get-IdeVisibleWidth $clipped
        $rem = [Math]::Max(0, $InnerWidth - $lblVis - 1)
        return "$($Pal.E_B01)$LeftCorner$hBar$($Pal.E_RST)$LabelColor$clipped$($Pal.E_RST)$($Pal.E_B01)$($hBar * $rem)$RightCorner$($Pal.E_RST)"
    }
    $rightBars = [Math]::Max(1, $InnerWidth - $lblVis - 2)
    return "$($Pal.E_B01)$LeftCorner$hBar$hBar$($Pal.E_RST)$LabelColor$LabelText$($Pal.E_RST)$($Pal.E_B01)$($hBar * $rightBars)$RightCorner$($Pal.E_RST)"
}

function Write-IdeNewCardFrame(
    [string]$BufferText,
    [int]$CursorPos,
    [string[]]$Agents,
    [int]$AgentIndex,
    [string]$CurrentLayout,
    [string]$ErrorMessage,
    [bool]$FromSwitcher,
    [hashtable]$LiveSessionMap
) {
    $pal = Get-ActivePaletteMap
    $esc = [char]27
    $sz = Get-IdeTerminalSize
    $cols = [Math]::Max(44, [int]$sz.Columns)
    $rows = [Math]::Max(13, [int]$sz.Rows)
    $cardW = [Math]::Min(74, $cols - 2)
    $innerW = $cardW - 2
    $cardH = 11
    $topRow = [Math]::Max(1, [int][Math]::Floor(($rows - $cardH) / 2) + 1)
    $leftCol = [Math]::Max(1, [int][Math]::Floor(($cols - $cardW) / 2) + 1)
    $leftPad = ' ' * ($leftCol - 1)

    $nf = Test-IdeNerdFont
    $ptr = if ($nf) { "`u{25B8}" } else { '*' }
    $dot = "`u{00B7}"

    $preview = Get-IdeNewCardPreview $BufferText
    $effErr = if ($ErrorMessage) { $ErrorMessage } else { $preview.Error }

    $promptPrefix = '  New IDE > '
    $promptPfxW = 12
    $fieldBudget = [Math]::Max(8, $innerW - $promptPfxW - 2)
    $viewStart = 0
    if ($CursorPos -ge $fieldBudget) {
        $viewStart = $CursorPos - $fieldBudget + 1
    }
    $sliceLen = [Math]::Min($fieldBudget, [Math]::Max(0, $BufferText.Length - $viewStart))
    $visSlice = if ($sliceLen -gt 0) { $BufferText.Substring($viewStart, $sliceLen) } else { '' }
    $promptBody = if (-not $BufferText) {
        "$($pal.E_YLW)$promptPrefix$($pal.E_B01)my-feature$($pal.E_RST)"
    } else {
        "$($pal.E_YLW)$promptPrefix$($pal.E_B1)$visSlice$($pal.E_RST)"
    }

    $agentPills = [System.Collections.Generic.List[string]]::new()
    for ($aIdx = 0; $aIdx -lt $Agents.Count; $aIdx++) {
        $aName = $Agents[$aIdx]
        if ($aIdx -eq $AgentIndex) {
            $agentPills.Add("$($pal.E_GRN)$ptr $aName$($pal.E_RST)")
        } else {
            $agentPills.Add("$($pal.E_B01)$aName$($pal.E_RST)")
        }
    }
    $agentJoined = $agentPills -join " $($pal.E_B01)$dot$($pal.E_RST) "
    $layDesc = if ($CurrentLayout -eq '2pane') { '2-pane side-by-side' } else { '3-pane inverted-T' }
    $optRow = "  $($pal.E_B01)Agent  :$($pal.E_RST) $agentJoined    $($pal.E_B01)Layout:$($pal.E_RST) $($pal.E_CYN)$layDesc$($pal.E_RST)"
    if ((Get-IdeVisibleWidth $optRow) -gt $innerW) {
        $shortLay = if ($CurrentLayout -eq '2pane') { '2-pane' } else { '3-pane' }
        $optRow = "  $($pal.E_B01)Agent:$($pal.E_RST) $agentJoined  $($pal.E_B01)Layout:$($pal.E_RST) $($pal.E_CYN)$shortLay$($pal.E_RST)"
    }

    $sessVal = $preview.Session
    $sessNote = ''
    if (-not $preview.IsEmpty -and $LiveSessionMap -and $LiveSessionMap[$sessVal] -eq 'live') {
        $sessNote = " $($pal.E_YLW)(active - Enter attaches)$($pal.E_RST)"
    }
    $sessColor = if ($preview.IsEmpty) { $pal.E_B01 } else { $pal.E_CYN }
    $sessValFit = Format-IdeTruncVisible -Text $sessVal -MaxWidth ([Math]::Max(8, $innerW - 14 - (Get-IdeVisibleWidth $sessNote)))
    $sessRow = "  $($pal.E_B01)Session:$($pal.E_RST) $sessColor$sessValFit$($pal.E_RST)$sessNote"

    $tgtFit = Format-IdeTruncVisible -Text $preview.Target -MaxWidth ([Math]::Max(8, $innerW - 13))
    $tgtColor = if ($preview.IsEmpty) { $pal.E_B01 } else { $pal.E_B0 }
    $tgtRow = "  $($pal.E_B01)Target :$($pal.E_RST) $tgtColor$tgtFit$($pal.E_RST)"

    $statusRow = if ($effErr) {
        $errFit = Format-IdeTruncVisible -Text $effErr -MaxWidth ([Math]::Max(8, $innerW - 4))
        "  $($pal.E_RED)$errFit$($pal.E_RST)"
    } else {
        ''
    }

    $escHint = if ($FromSwitcher) { 'Esc: back' } else { 'Esc: cancel' }
    $footerHints = @('Enter: create', 'Tab: agent', 'Alt+2: layout', 'Alt+o: open dir', $escHint)
    $footerLabel = Format-IdeCardFooter -Hints $footerHints -InnerWidth $innerW

    $cardLines = @(
        (Format-IdeBoxBorder -LeftCorner "`u{256D}" -RightCorner "`u{256E}" -LabelText ' New IDE Workspace ' -LabelColor $pal.E_BLU -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent $promptBody -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent $optRow -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent $sessRow -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent $tgtRow -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent $statusRow -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal),
        (Format-IdeBoxBorder -LeftCorner "`u{2570}" -RightCorner "`u{256F}" -LabelText $footerLabel -LabelColor $pal.E_B01 -InnerWidth $innerW -Pal $pal)
    )

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("${esc}[?25l${esc}[H")
    for ($r = 1; $r -lt $topRow; $r++) {
        [void]$sb.Append("${esc}[K`r`n")
    }
    foreach ($cl in $cardLines) {
        [void]$sb.Append($leftPad).Append($cl).Append("${esc}[K`r`n")
    }
    [void]$sb.Append("${esc}[J")
    $cursorRow = $topRow + 2
    $cursorCol = $leftCol + 1 + $promptPfxW + ($CursorPos - $viewStart)
    [void]$sb.Append("${esc}[${cursorRow};${cursorCol}H${esc}[?25h")
    [Console]::Write($sb.ToString())
}

function Step-WordBackward([string]$Text, [int]$Pos) {
    $p = [Math]::Min([Math]::Max(0, $Pos), $Text.Length)
    while ($p -gt 0 -and [char]::IsWhiteSpace($Text[$p - 1])) { $p-- }
    while ($p -gt 0 -and -not [char]::IsWhiteSpace($Text[$p - 1]) -and $Text[$p - 1] -notin @('/', '\', '-')) { $p-- }
    return $p
}

function Step-WordForward([string]$Text, [int]$Pos) {
    $len = $Text.Length
    $p = [Math]::Min([Math]::Max(0, $Pos), $len)
    while ($p -lt $len -and [char]::IsWhiteSpace($Text[$p])) { $p++ }
    while ($p -lt $len -and -not [char]::IsWhiteSpace($Text[$p]) -and $Text[$p] -notin @('/', '\', '-')) { $p++ }
    return $p
}

function Invoke-CompleteNewWorkspaceLaunch(
    [string]$RawName,
    [string]$Layout,
    [string]$SelectedAi,
    [bool]$AiExplicit,
    [bool]$Detach,
    [bool]$Desktop,
    [bool]$NewWindow,
    [string]$RequestedBackend,
    [bool]$IsDryRun,
    [bool]$InteractiveTty
) {
    $res = Invoke-CreateIdeWorkspaceDirectory -RawName $RawName -InteractiveTty $InteractiveTty -IsDryRun $IsDryRun
    if ($res.Error -or -not $res.Path) {
        return $res
    }
    $prevResolved = $env:IDE_WORKSPACE_RESOLVED
    $env:IDE_WORKSPACE_RESOLVED = '1'
    try {
        Invoke-LaunchWorkspace `
            -TargetDirArg $res.Path `
            -Layout $Layout `
            -RequestedBackend $RequestedBackend `
            -RequestedAi $SelectedAi `
            -AiFromFlag $AiExplicit `
            -Detach $Detach `
            -Desktop $Desktop `
            -NewWindow $NewWindow `
            -IsDryRun $IsDryRun
    } finally {
        $env:IDE_WORKSPACE_RESOLVED = $prevResolved
    }
    return $res
}

function Invoke-IdeNew(
    [string]$NameArg = '',
    [string]$Layout = '3pane',
    [string]$RequestedAi = 'agy',
    [bool]$AiFromFlag = $false,
    [bool]$Detach = $false,
    [bool]$Desktop = $false,
    [bool]$NewWindow = $false,
    [string]$RequestedBackend = '',
    [bool]$IsDryRun = $false
) {
    if (-not (Get-Command Invoke-CreateIdeWorkspaceDirectory -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Hooks.ps1')
    }
    if (-not (Get-Command Invoke-LaunchWorkspace -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Workspace.ps1')
    }

    $isTty = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    $curLayout = if ($Layout -eq '2pane') { '2pane' } else { '3pane' }
    $validatedAi = Resolve-ValidatedAiCliName -RequestedCli $RequestedAi -FromFlag $AiFromFlag
    if (-not $validatedAi) {
        [Console]::Error.WriteLine("Error: Unknown or missing AI agent '$RequestedAi'.")
        exit 1
    }
    $agents = Get-IdeAgentCandidateList $validatedAi
    $agentIdx = [Array]::IndexOf($agents, $validatedAi)
    if ($agentIdx -lt 0) { $agentIdx = 0 }
    $aiExplicit = $AiFromFlag

    if ($NameArg -and $NameArg.Trim()) {
        $directRes = Invoke-CompleteNewWorkspaceLaunch `
            -RawName $NameArg.Trim() `
            -Layout $curLayout `
            -SelectedAi $agents[$agentIdx] `
            -AiExplicit $aiExplicit `
            -Detach $Detach `
            -Desktop $Desktop `
            -NewWindow $NewWindow `
            -RequestedBackend $RequestedBackend `
            -IsDryRun $IsDryRun `
            -InteractiveTty $isTty
        if ($directRes.Error -or -not $directRes.Path) {
            [Console]::Error.WriteLine("Error: $($directRes.Error)")
            exit 1
        }
        exit 0
    }

    # Scripted keystroke replay hook for automated testing (WS_IDE_NEW_INPUT)
    if ($null -ne $env:WS_IDE_NEW_INPUT) {
        $rawKeys = [string]$env:WS_IDE_NEW_INPUT
        $buf = ''
        $pos = 0
        $k = 0
        while ($k -lt $rawKeys.Length) {
            $ch = $rawKeys[$k]
            if ([int]$ch -eq 27) {
                if ($k + 2 -lt $rawKeys.Length -and $rawKeys[$k + 1] -eq '[' -and $rawKeys[$k + 2] -eq 'Z') {
                    $agentIdx = ($agentIdx - 1 + $agents.Count) % $agents.Count
                    $aiExplicit = $true
                    $k += 3
                    continue
                }
                if ($k + 1 -lt $rawKeys.Length -and $rawKeys[$k + 1] -eq '2') {
                    $curLayout = if ($curLayout -eq '2pane') { '3pane' } else { '2pane' }
                    $k += 2
                    continue
                }
                if ($k + 1 -lt $rawKeys.Length -and ($rawKeys[$k + 1] -eq 'o' -or $rawKeys[$k + 1] -eq 'O')) {
                    $env:WS_IDE_NEW_INPUT = $null
                    Invoke-IdeDir -QueryArg $buf.Trim() -Layout $curLayout -RequestedAi $agents[$agentIdx] -AiFromFlag $aiExplicit -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -RequestedBackend $RequestedBackend -IsDryRun $IsDryRun
                    exit 0
                }
                exit 0
            }
            if ([int]$ch -eq 3) {
                exit 0
            }
            if ($ch -eq "`t") {
                $agentIdx = ($agentIdx + 1) % $agents.Count
                $aiExplicit = $true
                $k++
                continue
            }
            if ([int]$ch -in @(8, 127)) {
                if ($pos -gt 0) {
                    $buf = $buf.Remove($pos - 1, 1)
                    $pos--
                }
                $k++
                continue
            }
            if ([int]$ch -eq 21) {
                $buf = $buf.Substring($pos)
                $pos = 0
                $k++
                continue
            }
            if ([int]$ch -eq 23) {
                $nw = Step-WordBackward -Text $buf -Pos $pos
                if ($nw -lt $pos) {
                    $buf = $buf.Remove($nw, $pos - $nw)
                    $pos = $nw
                }
                $k++
                continue
            }
            if ($ch -in @("`r", "`n")) {
                break
            }
            if ([int]$ch -ge 32) {
                $buf = $buf.Insert($pos, [string]$ch)
                $pos++
            }
            $k++
        }
        if (-not $buf.Trim()) { exit 0 }
        $scriptedRes = Invoke-CompleteNewWorkspaceLaunch `
            -RawName $buf.Trim() `
            -Layout $curLayout `
            -SelectedAi $agents[$agentIdx] `
            -AiExplicit $aiExplicit `
            -Detach $Detach `
            -Desktop $Desktop `
            -NewWindow $NewWindow `
            -RequestedBackend $RequestedBackend `
            -IsDryRun $IsDryRun `
            -InteractiveTty $false
        if ($scriptedRes.Error -or -not $scriptedRes.Path) {
            [Console]::Error.WriteLine("Error: $($scriptedRes.Error)")
            exit 1
        }
        exit 0
    }

    if (-not $isTty) {
        if ([Console]::IsInputRedirected) {
            $pipedLine = [Console]::In.ReadLine()
            if (-not $pipedLine -or -not $pipedLine.Trim()) {
                exit 0
            }
            $pipeRes = Invoke-CompleteNewWorkspaceLaunch `
                -RawName $pipedLine.Trim() `
                -Layout $curLayout `
                -SelectedAi $agents[$agentIdx] `
                -AiExplicit $aiExplicit `
                -Detach $Detach `
                -Desktop $Desktop `
                -NewWindow $NewWindow `
                -RequestedBackend $RequestedBackend `
                -IsDryRun $IsDryRun `
                -InteractiveTty $false
            if ($pipeRes.Error -or -not $pipeRes.Path) {
                [Console]::Error.WriteLine("Error: $($pipeRes.Error)")
                exit 1
            }
            exit 0
        }
        [Console]::Error.WriteLine("Error: 'ide new' without a workspace name requires an interactive terminal.")
        exit 1
    }

    if (-not (Get-Command Enter-ZellijFloatingModal -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Modals.ps1')
    }
    $fromSwitcher = ($env:IDE_FROM_SWITCHER -eq '1')
    $modalFile = Enter-ZellijFloatingModal -ModalName 'new' -X '15%' -Y '20%' -Width '70%' -Height '48%'
    $liveSessions = Get-LiveZellijSessionMap
    $esc = [char]27
    $inAltScreen = $false
    $buf = ''
    $pos = 0
    $errMsg = ''
    $nextAction = 'none'
    $createdDir = ''

    try {
        [Console]::Write("${esc}[?1049h")
        $inAltScreen = $true
        while ($true) {
            Write-IdeNewCardFrame `
                -BufferText $buf `
                -CursorPos $pos `
                -Agents $agents `
                -AgentIndex $agentIdx `
                -CurrentLayout $curLayout `
                -ErrorMessage $errMsg `
                -FromSwitcher $fromSwitcher `
                -LiveSessionMap $liveSessions

            $ki = [Console]::ReadKey($true)
            $mods = $ki.Modifiers
            $hasAlt = (($mods -band [ConsoleModifiers]::Alt) -ne 0)
            $hasCtrl = (($mods -band [ConsoleModifiers]::Control) -ne 0)
            $hasShift = (($mods -band [ConsoleModifiers]::Shift) -ne 0)

            if ($ki.Key -eq [ConsoleKey]::Escape -or ($hasAlt -and $ki.Key -eq [ConsoleKey]::S)) {
                $nextAction = if ($fromSwitcher) { 'switcher' } else { 'cancel' }
                break
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::C) {
                $nextAction = 'cancel'
                break
            }
            if ($hasAlt -and $ki.Key -eq [ConsoleKey]::O) {
                $nextAction = 'dir'
                break
            }
            if ($hasAlt -and ($ki.Key -eq [ConsoleKey]::D2 -or $ki.KeyChar -eq '2')) {
                $curLayout = if ($curLayout -eq '2pane') { '3pane' } else { '2pane' }
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::Tab) {
                $step = if ($hasShift) { -1 } else { 1 }
                $agentIdx = ($agentIdx + $step + $agents.Count) % $agents.Count
                $aiExplicit = $true
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::Enter) {
                if (-not $buf.Trim()) {
                    $errMsg = 'Enter a workspace name or press Esc to cancel.'
                    continue
                }
                if (Test-IdeHookDefined 'New-IdeWorkspace') {
                    [Console]::Write("${esc}[?25h${esc}[?1049l")
                    $inAltScreen = $false
                }
                $createRes = Invoke-CreateIdeWorkspaceDirectory -RawName $buf.Trim() -InteractiveTty $true -IsDryRun $IsDryRun
                if ($createRes.Error -or -not $createRes.Path) {
                    if (-not $inAltScreen) {
                        [Console]::Write("${esc}[?1049h")
                        $inAltScreen = $true
                    }
                    $errMsg = $createRes.Error
                    continue
                }
                $createdDir = $createRes.Path
                $nextAction = 'launch'
                break
            }

            if ($ki.Key -eq [ConsoleKey]::LeftArrow) {
                $pos = if ($hasCtrl -or $hasAlt) { Step-WordBackward -Text $buf -Pos $pos } else { [Math]::Max(0, $pos - 1) }
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::RightArrow) {
                $pos = if ($hasCtrl -or $hasAlt) { Step-WordForward -Text $buf -Pos $pos } else { [Math]::Min($buf.Length, $pos + 1) }
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::Home -or ($hasCtrl -and $ki.Key -eq [ConsoleKey]::A)) {
                $pos = 0
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::End -or ($hasCtrl -and $ki.Key -eq [ConsoleKey]::E)) {
                $pos = $buf.Length
                continue
            }
            if ($hasAlt -and $ki.Key -eq [ConsoleKey]::B) {
                $pos = Step-WordBackward -Text $buf -Pos $pos
                continue
            }
            if ($hasAlt -and $ki.Key -eq [ConsoleKey]::F) {
                $pos = Step-WordForward -Text $buf -Pos $pos
                continue
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::B) {
                $pos = [Math]::Max(0, $pos - 1)
                continue
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::F) {
                $pos = [Math]::Min($buf.Length, $pos + 1)
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::Backspace) {
                if ($hasAlt -or $hasCtrl) {
                    $nw = Step-WordBackward -Text $buf -Pos $pos
                    if ($nw -lt $pos) {
                        $buf = $buf.Remove($nw, $pos - $nw)
                        $pos = $nw
                        $errMsg = ''
                    }
                } elseif ($pos -gt 0) {
                    $buf = $buf.Remove($pos - 1, 1)
                    $pos--
                    $errMsg = ''
                }
                continue
            }
            if ($ki.Key -eq [ConsoleKey]::Delete -or ($hasCtrl -and $ki.Key -eq [ConsoleKey]::D)) {
                if ($pos -lt $buf.Length) {
                    $buf = $buf.Remove($pos, 1)
                    $errMsg = ''
                }
                continue
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::W) {
                $nw = Step-WordBackward -Text $buf -Pos $pos
                if ($nw -lt $pos) {
                    $buf = $buf.Remove($nw, $pos - $nw)
                    $pos = $nw
                    $errMsg = ''
                }
                continue
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::U) {
                if ($pos -gt 0) {
                    $buf = $buf.Substring($pos)
                    $pos = 0
                    $errMsg = ''
                }
                continue
            }
            if ($hasCtrl -and $ki.Key -eq [ConsoleKey]::K) {
                if ($pos -lt $buf.Length) {
                    $buf = $buf.Substring(0, $pos)
                    $errMsg = ''
                }
                continue
            }
            if (-not $hasAlt -and -not $hasCtrl -and [int]$ki.KeyChar -ge 32 -and [int]$ki.KeyChar -ne 127) {
                $buf = $buf.Insert($pos, [string]$ki.KeyChar)
                $pos++
                $errMsg = ''
            }
        }
    } finally {
        if ($inAltScreen) {
            [Console]::Write("${esc}[?25h${esc}[?1049l")
        }
        Exit-ZellijFloatingModal -ModalFile $modalFile
    }

    switch ($nextAction) {
        'launch' {
            $prevResolved = $env:IDE_WORKSPACE_RESOLVED
            $env:IDE_WORKSPACE_RESOLVED = '1'
            try {
                Invoke-LaunchWorkspace `
                    -TargetDirArg $createdDir `
                    -Layout $curLayout `
                    -RequestedBackend $RequestedBackend `
                    -RequestedAi $agents[$agentIdx] `
                    -AiFromFlag $aiExplicit `
                    -Detach $Detach `
                    -Desktop $Desktop `
                    -NewWindow $NewWindow `
                    -IsDryRun $IsDryRun
            } finally {
                $env:IDE_WORKSPACE_RESOLVED = $prevResolved
            }
        }
        'dir' {
            Invoke-IdeDir `
                -QueryArg $buf.Trim() `
                -Layout $curLayout `
                -RequestedAi $agents[$agentIdx] `
                -AiFromFlag $aiExplicit `
                -Detach $Detach `
                -Desktop $Desktop `
                -NewWindow $NewWindow `
                -RequestedBackend $RequestedBackend `
                -IsDryRun $IsDryRun
        }
        'switcher' {
            $env:IDE_FROM_SWITCHER = $null
            if (-not (Get-Command Invoke-SessionSwitcher -CommandType Function -ErrorAction SilentlyContinue)) {
                . (Join-Path (Get-IdeLibDir) 'Fleet.ps1')
            }
            Invoke-SessionSwitcher -Layout $curLayout -RequestedAi $agents[$agentIdx] -AiFromFlag $aiExplicit -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -RequestedBackend $RequestedBackend
        }
    }
    exit 0
}

function Get-IdeLauncherDirectoryList {
    if (-not (Get-Command Get-ConfiguredIdeWorkspaceRootSet -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Hooks.ps1')
    }
    $parentCache = @{}
    $wsInfo = Get-ConfiguredIdeWorkspaceRootSet -ParentCache $parentCache -IncludeHook $true
    $wsRoots = @($wsInfo.Roots)
    $managedParents = $wsInfo.ManagedParents

    $results = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $zoxBin = Resolve-ZoxideExecutable
    if ($zoxBin) {
        $zLines = @(& $zoxBin query -l --all 2>$null)
        if ($LASTEXITCODE -ne 0 -or $zLines.Count -eq 0) {
            $zLines = @(& $zoxBin query -l 2>$null)
        }
        foreach ($zl in $zLines) {
            $raw = "$zl".Trim()
            if (-not $raw) { continue }
            $cand = try { (Expand-IdeUserPath $raw).TrimEnd('\', '/') } catch { '' }
            if (-not $cand) { continue }

            foreach ($wr in $wsRoots) {
                $wrPfx = $wr + [System.IO.Path]::DirectorySeparatorChar
                if ([string]::Equals($cand, $wr, [System.StringComparison]::OrdinalIgnoreCase) -or
                    $cand.StartsWith($wrPfx, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $cand = $wr
                    break
                }
            }
            if ($seen.Contains($cand)) { continue }

            $cParent = [System.IO.Path]::GetDirectoryName($cand)
            $cLeaf = [System.IO.Path]::GetFileName($cand)
            if ($cParent -and $managedParents.Contains($cParent.TrimEnd('\', '/'))) {
                $cSet = Get-ChildDirectoryNameSet -ParentDir $cParent -Cache $parentCache
                if ($null -eq $cSet -or -not $cSet.Contains($cLeaf)) {
                    continue
                }
            } elseif (-not [System.IO.Directory]::Exists($cand)) {
                continue
            }

            [void]$seen.Add($cand)
            $results.Add($cand)
        }
    }

    foreach ($wr in $wsRoots) {
        if (-not $seen.Contains($wr)) {
            [void]$seen.Add($wr)
            $results.Add($wr)
        }
    }

    $scanParents = [System.Collections.Generic.List[string]]::new()
    $wsParent = (Get-IdeWorkspaceParent).TrimEnd('\', '/')
    $homeDir = (Get-UserHomeDir).TrimEnd('\', '/')
    if ($wsParent) { $scanParents.Add($wsParent) }
    if ($homeDir -and -not [string]::Equals($homeDir, $wsParent, [System.StringComparison]::OrdinalIgnoreCase)) {
        $scanParents.Add($homeDir)
    }

    foreach ($sp in $scanParents) {
        $childNames = Get-ChildDirectoryNameSet -ParentDir $sp -Cache $parentCache
        if ($null -eq $childNames) { continue }
        foreach ($name in ($childNames | Sort-Object)) {
            if ($name.StartsWith('.')) { continue }
            $fullChild = (Join-Path $sp $name).TrimEnd('\', '/')
            if (-not $seen.Contains($fullChild)) {
                [void]$seen.Add($fullChild)
                $results.Add($fullChild)
            }
        }
    }

    return ,$results.ToArray()
}

function Show-IdeDirPreview([string]$RawDir, [string]$CurrentSession = '') {
    if (-not $RawDir -or -not $RawDir.Trim()) { return }
    if (-not (Get-Command Resolve-IdeWorkspaceTarget -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Hooks.ps1')
    }
    if (-not (Get-Command Get-FastGitSummary -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Fleet.ps1')
    }

    $pal = Get-ActivePaletteMap
    $nf = Test-IdeNerdFont
    $dot = "`u{00B7}"
    $ruleCh = "`u{2500}"
    $ell = "`u{2026}"

    $cleanRaw = $RawDir.Trim()
    $resolvedWs = Resolve-IdeWorkspaceTarget $cleanRaw
    $targetDir = if ($resolvedWs) { $resolvedWs } else { Expand-IdeUserPath $cleanRaw }

    $sess = Get-SanitizedSessionName $targetDir
    $meta = Read-SessionState $sess
    $liveZellij = Get-LiveZellijSessionMap
    $livePipes = Get-LiveIdePipeMap
    $isLive = ($liveZellij[$sess] -eq 'live') -or $livePipes.ContainsKey($sess)

    $statusBadge = if ($isLive) {
        $aiCli = if ($meta -and $meta['ai_cli']) { [string]$meta['ai_cli'] } else { 'agy' }
        $rawSt = if ($meta -and $meta['agent_state']) { ([string]$meta['agent_state']).ToUpperInvariant() } else { 'IDLE' }
        if ($rawSt -eq 'RUNNING') { $rawSt = 'WORKING' }
        if ($rawSt -eq 'APPROVAL') { $rawSt = 'ATTN' }
        $stCol = Get-IdeStateColor -State $rawSt -Pal $pal
        $curTag = if ($CurrentSession -and [string]::Equals($sess, $CurrentSession, [System.StringComparison]::OrdinalIgnoreCase)) { 'current, ' } else { '' }
        "$($pal.E_B01)(${curTag}active: $($pal.E_YLW)$aiCli$($pal.E_B01) $dot ${stCol}${rawSt}$($pal.E_B01))$($pal.E_RST)"
    } else {
        "$($pal.E_B01)(not running)$($pal.E_RST)"
    }

    $ico = if ($nf) { "`u{F024B} " } else { '' }
    Write-Output " $($pal.E_BLU)$ico$sess$($pal.E_RST)  $statusBadge"
    Write-Output " $($pal.E_B01)Path  :$($pal.E_RST) $($pal.E_B0)$(Format-IdeShortHome $cleanRaw)$($pal.E_RST)"
    if (-not [string]::Equals($cleanRaw.TrimEnd('\', '/'), $targetDir.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Output " $($pal.E_B01)Target:$($pal.E_RST) $($pal.E_CYN)$(Format-IdeShortHome $targetDir)$($pal.E_RST)"
    }

    if ([System.IO.Directory]::Exists($targetDir)) {
        $git = Get-FastGitSummary -Workdir $targetDir -IncludeStatus $true
        if ($git.Detail) {
            $vcsCol = if ($git.Dirty) { $pal.E_YLW } else { $pal.E_GRN }
            Write-Output " $($pal.E_B01)VCS   :$($pal.E_RST) ${vcsCol}$($git.Detail)$($pal.E_RST)"
        }
        Write-Output ''
        Write-Output " $($pal.E_B01)$ruleCh$ruleCh Contents $ruleCh$ruleCh$($pal.E_RST)"

        $dirEntries = [System.Collections.Generic.List[string]]::new()
        $fileEntries = [System.Collections.Generic.List[string]]::new()
        $totalCount = 0
        try {
            foreach ($fsEntry in [System.IO.Directory]::EnumerateFileSystemEntries($targetDir)) {
                $leaf = [System.IO.Path]::GetFileName($fsEntry)
                if (-not $leaf -or $leaf -eq '.git') { continue }
                $totalCount++
                if ($totalCount -le 240) {
                    if ([System.IO.Directory]::Exists($fsEntry)) {
                        $dirEntries.Add($leaf)
                    } else {
                        $fileEntries.Add($leaf)
                    }
                }
            }
        } catch {
            Write-Verbose "Preview directory scan skipped: $_"
        }

        foreach ($dn in ($dirEntries | Sort-Object)) {
            Write-Output "   $($pal.E_BLU)$dn/$($pal.E_RST)"
        }
        foreach ($fn in ($fileEntries | Sort-Object)) {
            Write-Output "   $($pal.E_B0)$fn$($pal.E_RST)"
        }
        if ($totalCount -eq 0) {
            Write-Output "   $($pal.E_B01)(empty directory)$($pal.E_RST)"
        } elseif ($totalCount -gt 240) {
            Write-Output "   $($pal.E_B01)$ell +$($totalCount - 240) more$($pal.E_RST)"
        }
    } else {
        Write-Output " $($pal.E_RED)(directory not available)$($pal.E_RST)"
    }
}

function Invoke-IdeDir(
    [string]$QueryArg = '',
    [string]$Layout = '3pane',
    [string]$RequestedAi = 'agy',
    [bool]$AiFromFlag = $false,
    [bool]$Detach = $false,
    [bool]$Desktop = $false,
    [bool]$NewWindow = $false,
    [string]$RequestedBackend = '',
    [bool]$IsDryRun = $false
) {
    if (-not (Get-Command Get-ConfiguredIdeWorkspaceRootSet -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Hooks.ps1')
    }
    if (-not (Get-Command Invoke-LaunchWorkspace -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Workspace.ps1')
    }
    if (-not (Get-Command Get-ClassifiedIdeFleet -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Fleet.ps1')
    }

    if ($env:WS_IDE_DIR_PICK -and $env:WS_IDE_DIR_PICK.Trim()) {
        $pickedTest = $env:WS_IDE_DIR_PICK.Trim()
        $resolvedTest = Resolve-IdeWorkspaceTarget $pickedTest
        $finalTest = if ($resolvedTest) { $resolvedTest } else { Expand-IdeUserPath $pickedTest }
        $prevRes = $env:IDE_WORKSPACE_RESOLVED
        $env:IDE_WORKSPACE_RESOLVED = '1'
        try {
            Invoke-LaunchWorkspace `
                -TargetDirArg $finalTest `
                -Layout $Layout `
                -RequestedBackend $RequestedBackend `
                -RequestedAi $RequestedAi `
                -AiFromFlag $AiFromFlag `
                -Detach $Detach `
                -Desktop $Desktop `
                -NewWindow $NewWindow `
                -IsDryRun $IsDryRun
        } finally {
            $env:IDE_WORKSPACE_RESOLVED = $prevRes
        }
        exit 0
    }

    $isTty = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
    if (-not $isTty) {
        [Console]::Error.WriteLine("Error: 'ide dir' requires an interactive terminal.")
        exit 1
    }

    $fzfBin = Resolve-FzfExecutable
    if (-not $fzfBin) {
        [Console]::Error.WriteLine("Error: 'fzf' is required for 'ide dir'. Run '.\setup.ps1 -Bootstrap' or 'mise install fzf@latest'.")
        exit 1
    }

    if (-not (Get-Command Enter-ZellijFloatingModal -CommandType Function -ErrorAction SilentlyContinue)) {
        . (Join-Path (Get-IdeLibDir) 'Modals.ps1')
    }

    $fromSwitcher = ($env:IDE_FROM_SWITCHER -eq '1')
    $modalFile = Enter-ZellijFloatingModal -ModalName 'dir' -X '6%' -Y '8%' -Width '88%' -Height '84%'
    $actionAfter = 'none'
    $chosenDir = ''

    try {
        $pal = Get-ActivePaletteMap
        $nf = Test-IdeNerdFont
        $ptr = if ($nf) { "`u{25B8}" } else { '*' }
        $dot = "`u{00B7}"
        $us = [char]0x1F

        $candidates = Get-IdeLauncherDirectoryList
        if ($candidates.Count -eq 0) {
            $candidates = @((Get-UserHomeDir))
        }

        $fleet = Get-ClassifiedIdeFleet -IncludeGit $false
        $fleetByWd = @{}
        $fleetBySess = @{}
        foreach ($fe in $fleet) {
            if ($fe.Status -eq 'live') {
                $fleetBySess[$fe.Session] = $fe
                if ($fe.RawWorkdir) {
                    $fleetByWd[$fe.RawWorkdir.TrimEnd('\', '/').ToLowerInvariant()] = $fe
                }
            }
        }

        $curSess = Resolve-TargetSession ''
        $fzfRows = [System.Collections.Generic.List[string]]::new()
        foreach ($cand in $candidates) {
            $shortDisp = Format-IdeShortHome $cand
            $normCand = $cand.TrimEnd('\', '/').ToLowerInvariant()
            $matchEntry = if ($fleetByWd.ContainsKey($normCand)) {
                $fleetByWd[$normCand]
            } else {
                $candSlug = Get-SanitizedToken (Split-Path -Leaf $cand)
                if ($fleetBySess.ContainsKey($candSlug) -and $fleetBySess[$candSlug].RawWorkdir -and
                    [string]::Equals($fleetBySess[$candSlug].RawWorkdir.TrimEnd('\', '/'), $cand.TrimEnd('\', '/'), [System.StringComparison]::OrdinalIgnoreCase)) {
                    $fleetBySess[$candSlug]
                } else {
                    $null
                }
            }

            if ($null -ne $matchEntry) {
                $stCol = Get-IdeStateColor -State $matchEntry.State -Pal $pal
                $lead = if ($matchEntry.IsCurrent) { "$($pal.E_CYN)$ptr$($pal.E_RST) " } else { '  ' }
                $badge = "  $($pal.E_B01)[$($pal.E_CYN)$($matchEntry.Session)$($pal.E_B01) $dot ${stCol}$($matchEntry.State)$($pal.E_B01)]$($pal.E_RST)"
                $fzfRows.Add("${cand}${us}${lead}$($pal.E_B1)$shortDisp$($pal.E_RST)$badge")
            } else {
                $fzfRows.Add("${cand}${us}  $($pal.E_B0)$shortDisp$($pal.E_RST)")
            }
        }

        $sz = Get-IdeTerminalSize
        $cols = [int]$sz.Columns
        $previewWin = if ($cols -lt 90) { 'down:45%:wrap:noinfo' } else { 'right:50%:wrap:noinfo' }
        $escHint = if ($fromSwitcher) { 'Esc: back to sessions' } else { 'Esc: cancel' }
        $footerLabel = Format-IdeCardFooter -Hints @('Enter: launch', 'Alt+n: new', $escHint) -InnerWidth ([Math]::Max(30, $cols - 6))
        $heightArg = if ($env:ZELLIJ) { '--height=100%' } else { '--height=80%' }

        $pwshExe = Get-CurrentPwshExecutable
        $entryQuoted = "`"$(Get-IdeEntryScriptPath)`""
        $pwshCmd = "`"$pwshExe`" -NoProfile -ExecutionPolicy Bypass -File $entryQuoted"
        $previewCmd = "$pwshCmd _internal dir-preview --session `"$curSess`" -- {1}"
        $fzfColors = Format-FzfPaletteOption $pal

        $fzfArgs = [System.Collections.Generic.List[string]]::new()
        foreach ($fa in @(
            '--ansi',
            "--delimiter=$us",
            '--with-nth=2..',
            '--layout=reverse',
            $heightArg,
            '--info=inline-right',
            '--prompt=Open IDE > ',
            '--border=rounded',
            "--border-label=$footerLabel",
            '--border-label-pos=bottom',
            "--preview=$previewCmd",
            "--preview-window=$previewWin",
            '--expect=alt-n',
            '--bind=alt-s:abort',
            $fzfColors
        )) {
            $fzfArgs.Add($fa)
        }
        if ($QueryArg) {
            $fzfArgs.Add("--query=$QueryArg")
        }

        $rawOut = @($fzfRows | & $fzfBin @fzfArgs)
        $fzfRc = $LASTEXITCODE

        if ($fzfRc -ne 0 -or $rawOut.Count -eq 0) {
            if ($fromSwitcher) { $actionAfter = 'switcher' }
        } else {
            $pressed = "$($rawOut[0])".Trim()
            if ($pressed -eq 'alt-n') {
                $actionAfter = 'new'
            } else {
                $selLine = if ($rawOut.Count -ge 2) { "$($rawOut[1])" } else { '' }
                $pickedRaw = ($selLine -split $us)[0].Trim()
                if ($pickedRaw) {
                    $chosenDir = $pickedRaw
                    $actionAfter = 'launch'
                }
            }
        }
    } finally {
        Exit-ZellijFloatingModal -ModalFile $modalFile
    }

    switch ($actionAfter) {
        'new' {
            Invoke-IdeNew `
                -Layout $Layout `
                -RequestedAi $RequestedAi `
                -AiFromFlag $AiFromFlag `
                -Detach $Detach `
                -Desktop $Desktop `
                -NewWindow $NewWindow `
                -RequestedBackend $RequestedBackend `
                -IsDryRun $IsDryRun
        }
        'switcher' {
            $env:IDE_FROM_SWITCHER = $null
            Invoke-SessionSwitcher -Layout $Layout -RequestedAi $RequestedAi -AiFromFlag $AiFromFlag -Detach $Detach -Desktop $Desktop -NewWindow $NewWindow -RequestedBackend $RequestedBackend
        }
        'launch' {
            $resolvedWs = Resolve-IdeWorkspaceTarget $chosenDir
            $finalDir = if ($resolvedWs) { $resolvedWs } else { Expand-IdeUserPath $chosenDir }
            $prevRes = $env:IDE_WORKSPACE_RESOLVED
            $env:IDE_WORKSPACE_RESOLVED = '1'
            try {
                Invoke-LaunchWorkspace `
                    -TargetDirArg $finalDir `
                    -Layout $Layout `
                    -RequestedBackend $RequestedBackend `
                    -RequestedAi $RequestedAi `
                    -AiFromFlag $AiFromFlag `
                    -Detach $Detach `
                    -Desktop $Desktop `
                    -NewWindow $NewWindow `
                    -IsDryRun $IsDryRun
            } finally {
                $env:IDE_WORKSPACE_RESOLVED = $prevRes
            }
        }
    }
    exit 0
}

function Read-PidFromMarkerFile([string]$MarkerPath) {
    if (-not [System.IO.File]::Exists($MarkerPath)) { return 0 }
    try {
        $raw = [System.IO.File]::ReadAllText($MarkerPath).Trim()
        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }
    } catch {
        Write-Verbose "PID marker parse skipped: $_"
    }
    return 0
}

function Test-ProcessAlive([int]$ProcessId) {
    if ($ProcessId -le 0) { return $false }
    return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

function Write-IdeAgentSelectorFrame(
    [string]$SessionName,
    [string]$CurrentCli,
    [string]$CurrentState,
    [hashtable[]]$Choices,
    [int]$SelectedIndex,
    [bool]$FromSwitcher
) {
    $pal = Get-ActivePaletteMap
    $esc = [char]27
    $sz = Get-IdeTerminalSize
    $cols = [Math]::Max(40, [int]$sz.Columns)
    $rows = [Math]::Max(12, [int]$sz.Rows)
    $cardW = [Math]::Min(62, $cols - 2)
    $innerW = $cardW - 2
    $cardH = $Choices.Count + 6
    $topRow = [Math]::Max(1, [int][Math]::Floor(($rows - $cardH) / 2) + 1)
    $leftPad = ' ' * [Math]::Max(0, [int][Math]::Floor(($cols - $cardW) / 2))

    $nf = Test-IdeNerdFont
    $ptr = if ($nf) { "`u{25B8}" } else { '>' }
    $dot = "`u{00B7}"
    $stCol = Get-IdeStateColor -State $CurrentState -Pal $pal

    $hdrTitle = " AI Agent $dot $SessionName "
    $statusLine = "  $($pal.E_B01)Current:$($pal.E_RST) $($pal.E_YLW)$CurrentCli$($pal.E_RST)   $($pal.E_B01)State:$($pal.E_RST) ${stCol}$CurrentState$($pal.E_RST)"

    $cardLines = [System.Collections.Generic.List[string]]::new()
    $cardLines.Add((Format-IdeBoxBorder -LeftCorner "`u{256D}" -RightCorner "`u{256E}" -LabelText $hdrTitle -LabelColor $pal.E_BLU -InnerWidth $innerW -Pal $pal))
    $cardLines.Add((Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal))
    $cardLines.Add((Format-IdeBoxRow -BodyContent $statusLine -InnerWidth $innerW -Pal $pal))
    $cardLines.Add((Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal))

    for ($idx = 0; $idx -lt $Choices.Count; $idx++) {
        $num = $idx + 1
        $lbl = [string]$Choices[$idx].Label
        $itemLine = if ($idx -eq $SelectedIndex) {
            "  $($pal.E_GRN)$ptr $num. $lbl$($pal.E_RST)"
        } else {
            "    $($pal.E_B01)$num.$($pal.E_RST) $($pal.E_B0)$lbl$($pal.E_RST)"
        }
        $cardLines.Add((Format-IdeBoxRow -BodyContent $itemLine -InnerWidth $innerW -Pal $pal))
    }

    $cardLines.Add((Format-IdeBoxRow -BodyContent '' -InnerWidth $innerW -Pal $pal))
    $escHint = if ($FromSwitcher) { 'Esc: back' } else { 'Esc: cancel' }
    $footerLbl = Format-IdeCardFooter -Hints @('Enter: apply', 'j k: move', "1-$($Choices.Count): pick", $escHint) -InnerWidth $innerW
    $cardLines.Add((Format-IdeBoxBorder -LeftCorner "`u{2570}" -RightCorner "`u{256F}" -LabelText $footerLbl -LabelColor $pal.E_B01 -InnerWidth $innerW -Pal $pal))

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("${esc}[?25l${esc}[H")
    for ($r = 1; $r -lt $topRow; $r++) {
        [void]$sb.Append("${esc}[K`r`n")
    }
    foreach ($cl in $cardLines) {
        [void]$sb.Append($leftPad).Append($cl).Append("${esc}[K`r`n")
    }
    [void]$sb.Append("${esc}[J")
    [Console]::Write($sb.ToString())
}

function Invoke-IdeAgent([string]$CliArg = '', [string]$SessionArg = '') {
    $sess = Resolve-TargetSession $SessionArg
    $meta = Read-SessionState $sess
    $liveZellij = Get-LiveZellijSessionMap
    $livePipes = Get-LiveIdePipeMap
    $isLiveZellij = ($liveZellij[$sess] -eq 'live')
    $existsAny = ($null -ne $meta) -or $isLiveZellij -or $livePipes.ContainsKey($sess)

    if (-not $existsAny) {
        [Console]::Error.WriteLine("Error: No active IDE session named '$sess'.")
        exit 1
    }

    $stateDir = Get-IdeStateDir
    $curCli = if ($meta -and $meta['ai_cli']) { [string]$meta['ai_cli'] } elseif ($env:IDE_AI_CLI) { $env:IDE_AI_CLI } else { 'agy' }
    $aiShellMarker = Join-Path $stateDir "$sess.ai-shell"
    $rawSt = if ([System.IO.File]::Exists($aiShellMarker)) {
        'SHELL'
    } elseif ($meta -and $meta['agent_state']) {
        ([string]$meta['agent_state']).ToUpperInvariant()
    } else {
        'IDLE'
    }
    if ($rawSt -eq 'RUNNING') { $rawSt = 'WORKING' }
    if ($rawSt -eq 'APPROVAL') { $rawSt = 'ATTN' }

    $chosenCli = ''
    $isRestart = $false
    $fromSwitcher = ($env:IDE_FROM_SWITCHER -eq '1')

    if ($CliArg -and $CliArg.Trim()) {
        $normReq = $CliArg.Trim()
        if ($normReq.ToLowerInvariant() -eq 'restart') {
            $chosenCli = if ($curCli -eq 'shell') { 'agy' } else { $curCli }
            $isRestart = $true
        } else {
            $validated = Resolve-ValidatedAiCliName -RequestedCli $normReq -FromFlag $true
            if (-not $validated) {
                [Console]::Error.WriteLine("Error: Unknown or unavailable AI CLI '$normReq'. Expected agy, claude, codex, restart, or an executable on PATH.")
                exit 1
            }
            $chosenCli = $validated
            $isRestart = [string]::Equals($chosenCli, $curCli, [System.StringComparison]::OrdinalIgnoreCase)
        }
    } else {
        $cands = Get-IdeAgentCandidateList $curCli
        $choices = [System.Collections.Generic.List[hashtable]]::new()
        $restartTarget = if ($curCli -eq 'shell') { 'agy' } else { $curCli }
        $choices.Add(@{ Label = "Restart $restartTarget"; Target = $restartTarget; IsRestart = $true })
        foreach ($c in $cands) {
            if (-not [string]::Equals($c, $restartTarget, [System.StringComparison]::OrdinalIgnoreCase)) {
                $choices.Add(@{ Label = "Switch to $c"; Target = $c; IsRestart = $false })
            }
        }
        $selIdx = if ($rawSt -eq 'QUOTA' -and $choices.Count -gt 1) { 1 } else { 0 }

        if ($null -ne $env:WS_IDE_AGENT_INPUT) {
            $inp = [string]$env:WS_IDE_AGENT_INPUT
            foreach ($ch in $inp.ToCharArray()) {
                if ([int]$ch -eq 27 -or $ch -in @('q', 'Q')) { exit 0 }
                if ($ch -in @('j', 'J', "`t")) { $selIdx = ($selIdx + 1) % $choices.Count; continue }
                if ($ch -in @('k', 'K')) { $selIdx = ($selIdx - 1 + $choices.Count) % $choices.Count; continue }
                if ($ch -ge '1' -and $ch -le '9') {
                    $numPick = [int][string]$ch - 1
                    if ($numPick -lt $choices.Count) {
                        $selIdx = $numPick
                        break
                    }
                }
                if ($ch -in @("`r", "`n")) { break }
            }
            $chosenCli = [string]$choices[$selIdx].Target
            $isRestart = [bool]$choices[$selIdx].IsRestart
        } else {
            $isTty = [Environment]::UserInteractive -and (-not [Console]::IsInputRedirected) -and (-not [Console]::IsOutputRedirected)
            if (-not $isTty) {
                if ([Console]::IsInputRedirected) {
                    $lineIn = [Console]::In.ReadLine()
                    if (-not $lineIn -or -not $lineIn.Trim()) { exit 0 }
                    Invoke-IdeAgent -CliArg $lineIn.Trim() -SessionArg $sess
                    return
                }
                [Console]::Error.WriteLine("Error: 'ide agent' without a CLI argument requires an interactive terminal.")
                exit 1
            }

            if (-not (Get-Command Enter-ZellijFloatingModal -CommandType Function -ErrorAction SilentlyContinue)) {
                . (Join-Path (Get-IdeLibDir) 'Modals.ps1')
            }
            $modalFile = Enter-ZellijFloatingModal -ModalName 'agent' -X '22%' -Y '24%' -Width '56%' -Height '40%'
            $esc = [char]27
            $cancelled = $false
            try {
                [Console]::Write("${esc}[?1049h")
                while ($true) {
                    Write-IdeAgentSelectorFrame `
                        -SessionName $sess `
                        -CurrentCli $curCli `
                        -CurrentState $rawSt `
                        -Choices $choices.ToArray() `
                        -SelectedIndex $selIdx `
                        -FromSwitcher $fromSwitcher

                    $ki = [Console]::ReadKey($true)
                    $hasAlt = (($ki.Modifiers -band [ConsoleModifiers]::Alt) -ne 0)
                    $hasShift = (($ki.Modifiers -band [ConsoleModifiers]::Shift) -ne 0)

                    if ($ki.Key -in @([ConsoleKey]::Escape, [ConsoleKey]::Q) -or ($hasAlt -and $ki.Key -eq [ConsoleKey]::S)) {
                        $cancelled = $true
                        break
                    }
                    if ($ki.Key -eq [ConsoleKey]::DownArrow -or $ki.KeyChar -in @('j', 'J')) {
                        $selIdx = ($selIdx + 1) % $choices.Count
                        continue
                    }
                    if ($ki.Key -eq [ConsoleKey]::UpArrow -or $ki.KeyChar -in @('k', 'K')) {
                        $selIdx = ($selIdx - 1 + $choices.Count) % $choices.Count
                        continue
                    }
                    if ($ki.Key -eq [ConsoleKey]::Tab) {
                        $step = if ($hasShift) { -1 } else { 1 }
                        $selIdx = ($selIdx + $step + $choices.Count) % $choices.Count
                        continue
                    }
                    if ($ki.KeyChar -ge '1' -and $ki.KeyChar -le '9') {
                        $nIdx = [int][string]$ki.KeyChar - 1
                        if ($nIdx -lt $choices.Count) {
                            $selIdx = $nIdx
                            break
                        }
                    }
                    if ($ki.Key -eq [ConsoleKey]::Enter) {
                        break
                    }
                }
            } finally {
                [Console]::Write("${esc}[?25h${esc}[?1049l")
                Exit-ZellijFloatingModal -ModalFile $modalFile
            }

            if ($cancelled) {
                if ($fromSwitcher) {
                    $env:IDE_FROM_SWITCHER = $null
                    if (-not (Get-Command Invoke-SessionSwitcher -CommandType Function -ErrorAction SilentlyContinue)) {
                        . (Join-Path (Get-IdeLibDir) 'Fleet.ps1')
                    }
                    Invoke-SessionSwitcher
                }
                exit 0
            }

            $chosenCli = [string]$choices[$selIdx].Target
            $isRestart = [bool]$choices[$selIdx].IsRestart
        }
    }

    $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if (-not $meta) {
        $meta = Build-IdeSessionRecord -SessionName $sess -AiCli $chosenCli -AgentState 'idle' -StateTs $nowEpoch
    } else {
        $meta['ai_cli'] = $chosenCli
        $meta['agent_state'] = 'idle'
        $meta['agent_message'] = ''
        $meta['state_ts'] = $nowEpoch
        $meta['attn_ts'] = 0L
    }
    Save-SessionState $meta

    if ($isLiveZellij) {
        $switchPath = Join-Path $stateDir "$sess.ai-switch"
        Write-TextUtf8NoBom -Path $switchPath -Content "$chosenCli`n"

        $supPid = Read-PidFromMarkerFile (Join-Path $stateDir "$sess.ai-supervisor")
        $activePid = Read-PidFromMarkerFile (Join-Path $stateDir "$sess.ai-active")
        $shellPid = Read-PidFromMarkerFile (Join-Path $stateDir "$sess.ai-shell")
        $supAlive = Test-ProcessAlive $supPid
        $childPid = if (Test-ProcessAlive $activePid) { $activePid } elseif (Test-ProcessAlive $shellPid) { $shellPid } else { 0 }

        if ($supAlive -and $childPid -gt 0 -and $childPid -ne $supPid) {
            & taskkill.exe /PID $childPid /T /F *> $null
        } elseif (-not $supAlive -and $childPid -eq 0) {
            Remove-Item -LiteralPath $switchPath -Force -ErrorAction SilentlyContinue
            $respawned = $false
            if (Test-WasmBarDeployed) {
                $respawned = Invoke-ZellijPipe -SessionName $sess -PipeName 'ws-ide-role' -Payload 'respawn:ai'
            }
            if (-not $respawned) {
                $aiPane = Get-RolePaneId -SessionName $sess -Role 'ai'
                if ($aiPane) {
                    $batchPath = Get-IdeBatchScriptPath
                    [void](Invoke-ZellijSessionAction -SessionName $sess -ActionArgs @('new-pane', '--in-place', '--close-replaced-pane', '--pane-id', $aiPane, '--', 'cmd.exe', '/d', '/c', $batchPath, '_internal', 'pane-init', 'ai'))
                }
            }
        }

        if ($env:ZELLIJ -and (Test-IsCurrentZellijSession $sess) -and -not $fromSwitcher) {
            [void](Select-IdeRolePane -SessionName $sess -Role 'ai' -EnsureOnly $true)
        }
    }

    if ($CliArg -and -not $fromSwitcher) {
        if ($isRestart) {
            Write-Output "Restarted AI agent ($chosenCli) in session '$sess'."
        } else {
            Write-Output "Switched AI agent in session '$sess' to $chosenCli."
        }
    }
}
