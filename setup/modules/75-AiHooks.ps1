# =============================================================
# setup/modules/75-AiHooks.ps1 - 3-Agent AI Lifecycle Hooks
# Reconciles Antigravity (agy), Claude Code, and Codex CLI hooks
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'AI CLI hooks reconciliation module')]
param(
    [string]$RepoRoot = '',
    [string]$AgyHooksPath = '',
    [string]$ClaudeSettingsPath = '',
    [string]$CodexConfigPath = '',
    [switch]$Remove,
    [switch]$FunctionsOnly,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$libDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'lib'
if (-not (Get-Command Write-SetupStage -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Log.ps1')
}
if (-not (Get-Command Write-FileAtomicUtf8NoBom -CommandType Function -ErrorAction SilentlyContinue)) {
    . (Join-Path $libDir 'Deploy.ps1')
}

function ConvertTo-OrderedMap($InputObject) {
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($k in $InputObject.Keys) {
            $map[[string]$k] = ConvertTo-OrderedMap $InputObject[$k]
        }
        return $map
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        $map = [ordered]@{}
        foreach ($prop in $InputObject.PSObject.Properties) {
            $map[$prop.Name] = ConvertTo-OrderedMap $prop.Value
        }
        return $map
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $InputObject) {
            $list.Add((ConvertTo-OrderedMap $item))
        }
        return , $list.ToArray()
    }
    return $InputObject
}

function Read-JsonOrderedObject([string]$FilePath) {
    if (-not [System.IO.File]::Exists($FilePath)) {
        return [ordered]@{}
    }
    try {
        $raw = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8).Trim()
        if (-not $raw) { return [ordered]@{} }
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        if ($parsed -is [System.Collections.IEnumerable] -and -not ($parsed -is [string]) -and -not ($parsed -is [System.Collections.IDictionary])) {
            return $null
        }
        if ($parsed -is [System.Management.Automation.PSCustomObject] -or $parsed -is [System.Collections.IDictionary]) {
            return (ConvertTo-OrderedMap $parsed)
        }
        return $null
    } catch {
        return $null
    }
}

function Save-ReconciledHookFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string]$Content = '',
        [switch]$DeleteWhenEmpty,
        [switch]$DryRun
    )
    $exists = [System.IO.File]::Exists($FilePath)
    if ($DeleteWhenEmpty -and -not $Content) {
        if (-not $exists) { return }
        $backup = Get-TimestampedBackupPath $FilePath
        if ($DryRun) {
            Write-SetupDryRun "Would backup $FilePath to $backup and remove $Label"
            return
        }
        Copy-Item -LiteralPath $FilePath -Destination $backup -Force
        Remove-Item -LiteralPath $FilePath -Force -ErrorAction SilentlyContinue
        Write-Host "  Removed $Label at $FilePath" -ForegroundColor Green
        return
    }

    $normalizedLf = $Content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    if ($exists) {
        $existingRaw = [System.IO.File]::ReadAllText($FilePath, [System.Text.Encoding]::UTF8)
        if ($existingRaw -ceq $normalizedLf) {
            Write-SetupSuccess "$Label at $FilePath is already up to date."
            return
        }
        $backup = Get-TimestampedBackupPath $FilePath
        if ($DryRun) {
            Write-SetupDryRun "Would backup $FilePath to $backup"
            Write-SetupDryRun "Would update $Label in $FilePath"
            return
        }
        Copy-Item -LiteralPath $FilePath -Destination $backup -Force
        Write-FileAtomicUtf8NoBom -DestinationPath $FilePath -Content $normalizedLf
        Write-SetupSuccess "$Label updated in $FilePath"
    } else {
        if ($DryRun) {
            Write-SetupDryRun "Would configure $Label in $FilePath"
            return
        }
        Write-FileAtomicUtf8NoBom -DestinationPath $FilePath -Content $normalizedLf
        Write-SetupSuccess "$Label configured in $FilePath"
    }
}

function Sync-AntigravityHooksFile([string]$HooksPath, [switch]$Remove, [switch]$DryRun) {
    $data = Read-JsonOrderedObject $HooksPath
    if ($null -eq $data) {
        Write-SetupWarn "Skipping $HooksPath because existing file is not a valid JSON object."
        return
    }

    $legacyKey = 'windows-settings-ide'
    $hookKey = 'ide-state'

    if ($Remove) {
        if (-not [System.IO.File]::Exists($HooksPath)) { return }
        $hadManaged = $data.Contains($hookKey) -or $data.Contains($legacyKey)
        if (-not $hadManaged) { return }
        if ($data.Contains($hookKey)) { [void]$data.Remove($hookKey) }
        if ($data.Contains($legacyKey)) { [void]$data.Remove($legacyKey) }
        if ($data.Count -eq 0) {
            Save-ReconciledHookFile -Label 'Antigravity lifecycle hooks' -FilePath $HooksPath -DeleteWhenEmpty -DryRun:$DryRun
        } else {
            $jsonOut = ($data | ConvertTo-Json -Depth 12)
            Save-ReconciledHookFile -Label 'Antigravity lifecycle hooks' -FilePath $HooksPath -Content $jsonOut -DryRun:$DryRun
        }
        return
    }

    $desiredBlock = [ordered]@{
        SessionStart = @(
            [ordered]@{
                type    = 'command'
                command = 'ide.cmd _internal agy-hook SessionStart'
                timeout = 5
            }
        )
        PreInvocation = @(
            [ordered]@{
                type    = 'command'
                command = 'ide.cmd _internal agy-hook PreInvocation'
                timeout = 5
            }
        )
        PreToolUse = @(
            [ordered]@{
                matcher = 'ask_question'
                hooks   = @(
                    [ordered]@{
                        type    = 'command'
                        command = 'ide.cmd _internal agy-hook PreToolUse'
                        timeout = 5
                    }
                )
            }
        )
        PostToolUse = @(
            [ordered]@{
                matcher = 'ask_question'
                hooks   = @(
                    [ordered]@{
                        type    = 'command'
                        command = 'ide.cmd _internal agy-hook PostToolUse'
                        timeout = 5
                    }
                )
            }
        )
        Stop = @(
            [ordered]@{
                type    = 'command'
                command = 'ide.cmd _internal agy-hook Stop'
                timeout = 5
            }
        )
    }

    $hadLegacy = $data.Contains($legacyKey)
    if ($hadLegacy) {
        [void]$data.Remove($legacyKey)
    }

    $currentCompact = if (-not $hadLegacy -and $data.Contains($hookKey)) {
        ($data[$hookKey] | ConvertTo-Json -Depth 12 -Compress)
    } else {
        ''
    }
    $desiredCompact = ($desiredBlock | ConvertTo-Json -Depth 12 -Compress)
    if ([System.IO.File]::Exists($HooksPath) -and -not $hadLegacy -and $currentCompact -ceq $desiredCompact) {
        Write-SetupSuccess "Antigravity lifecycle hooks at $HooksPath are already up to date."
        return
    }

    $data[$hookKey] = $desiredBlock
    $jsonOut = ($data | ConvertTo-Json -Depth 12)
    Save-ReconciledHookFile -Label 'Antigravity lifecycle hooks' -FilePath $HooksPath -Content $jsonOut -DryRun:$DryRun
}

function Select-ClaudeUserHookGroup($Groups) {
    $kept = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $Groups) { return , $kept.ToArray() }
    $ideCmdRegex = '(?i)(?:^|[\s"&|(/\\])ide(?:\.cmd|\.ps1)?["'']?\s+(?:--agent-state|state)\b'

    $groupList = if ($Groups -is [System.Collections.IEnumerable] -and -not ($Groups -is [string]) -and -not ($Groups -is [System.Collections.IDictionary])) {
        @($Groups)
    } else {
        @($Groups)
    }

    foreach ($grp in $groupList) {
        if (-not ($grp -is [System.Collections.IDictionary])) { continue }
        if (-not $grp.Contains('hooks') -or $null -eq $grp['hooks']) {
            $kept.Add($grp)
            continue
        }
        $hooksArr = if ($grp['hooks'] -is [System.Collections.IEnumerable] -and -not ($grp['hooks'] -is [string]) -and -not ($grp['hooks'] -is [System.Collections.IDictionary])) {
            @($grp['hooks'])
        } else {
            @($grp['hooks'])
        }
        $remHooks = [System.Collections.Generic.List[object]]::new()
        foreach ($h in $hooksArr) {
            $isIdeHook = ($h -is [System.Collections.IDictionary]) -and
                $h.Contains('command') -and
                ($h['command'] -is [string]) -and
                ($h['command'] -match $ideCmdRegex)
            if (-not $isIdeHook) {
                $remHooks.Add($h)
            }
        }
        if ($remHooks.Count -gt 0) {
            $clonedGrp = [ordered]@{}
            foreach ($k in $grp.Keys) {
                $clonedGrp[$k] = $grp[$k]
            }
            $clonedGrp['hooks'] = , $remHooks.ToArray()
            $kept.Add($clonedGrp)
        }
    }
    return , $kept.ToArray()
}

function Sync-ClaudeSettingsFile([string]$SettingsPath, [switch]$Remove, [switch]$DryRun) {
    $data = Read-JsonOrderedObject $SettingsPath
    if ($null -eq $data) {
        Write-SetupWarn "Skipping $SettingsPath because existing file is not a valid JSON object."
        return
    }

    if ($Remove) {
        if (-not [System.IO.File]::Exists($SettingsPath)) { return }
        if (-not $data.Contains('hooks') -or -not ($data['hooks'] -is [System.Collections.IDictionary])) { return }
        $origCompact = ($data | ConvertTo-Json -Depth 12 -Compress)
        $rawHooks = $data['hooks']
        $newHooks = [ordered]@{}
        foreach ($evName in $rawHooks.Keys) {
            $cleaned = Select-ClaudeUserHookGroup $rawHooks[$evName]
            if ($cleaned.Count -gt 0) {
                $newHooks[$evName] = , $cleaned
            }
        }
        if ($newHooks.Count -gt 0) {
            $data['hooks'] = $newHooks
        } else {
            [void]$data.Remove('hooks')
        }
        $nextCompact = ($data | ConvertTo-Json -Depth 12 -Compress)
        if ($origCompact -ceq $nextCompact) { return }
        if ($data.Count -eq 0) {
            Save-ReconciledHookFile -Label 'Claude Code lifecycle hooks' -FilePath $SettingsPath -DeleteWhenEmpty -DryRun:$DryRun
        } else {
            Save-ReconciledHookFile -Label 'Claude Code lifecycle hooks' -FilePath $SettingsPath -Content ($data | ConvertTo-Json -Depth 12) -DryRun:$DryRun
        }
        return
    }

    $eventSpecs = @(
        @{ Event = 'SessionStart';     Command = 'cmd.exe /d /c ide.cmd state idle' },
        @{ Event = 'UserPromptSubmit'; Command = 'cmd.exe /d /c ide.cmd state running' },
        @{ Event = 'PreToolUse';       Command = 'cmd.exe /d /c ide.cmd state running' },
        @{ Event = 'Notification';     Command = 'cmd.exe /d /c ide.cmd state approval' },
        @{ Event = 'Stop';             Command = 'cmd.exe /d /c ide.cmd state done' }
    )

    $origCompact = if ([System.IO.File]::Exists($SettingsPath)) { ($data | ConvertTo-Json -Depth 12 -Compress) } else { '' }
    $hooksMap = if ($data.Contains('hooks') -and ($data['hooks'] -is [System.Collections.IDictionary])) {
        $data['hooks']
    } else {
        [ordered]@{}
    }

    foreach ($spec in $eventSpecs) {
        $ev = $spec.Event
        $existingGroups = if ($hooksMap.Contains($ev)) { $hooksMap[$ev] } else { $null }
        $cleanedList = [System.Collections.Generic.List[object]]::new()
        foreach ($cg in (Select-ClaudeUserHookGroup $existingGroups)) {
            $cleanedList.Add($cg)
        }
        $managedGroup = [ordered]@{
            hooks = @(
                [ordered]@{
                    type    = 'command'
                    command = $spec.Command
                }
            )
        }
        $cleanedList.Add($managedGroup)
        $hooksMap[$ev] = , $cleanedList.ToArray()
    }
    $data['hooks'] = $hooksMap

    $nextCompact = ($data | ConvertTo-Json -Depth 12 -Compress)
    if ([System.IO.File]::Exists($SettingsPath) -and $origCompact -ceq $nextCompact) {
        Write-SetupSuccess "Claude Code lifecycle hooks at $SettingsPath are already up to date."
        return
    }

    Save-ReconciledHookFile -Label 'Claude Code lifecycle hooks' -FilePath $SettingsPath -Content ($data | ConvertTo-Json -Depth 12) -DryRun:$DryRun
}

function Sync-CodexConfigFile([string]$ConfigPath, [string]$ResolvedRepoRoot, [switch]$Remove, [switch]$DryRun) {
    $idePs1Path = Join-Path (Join-Path $ResolvedRepoRoot 'bin') 'ide.ps1'
    $escapedIdePs1 = $idePs1Path.Replace('\', '\\')
    $canonicalLine = "notify = [`"pwsh.exe`", `"-NoLogo`", `"-NoProfile`", `"-NonInteractive`", `"-File`", `"$escapedIdePs1`", `"state`", `"done`"]"
    $ideNotifyRegex = '(?i)^\s*notify\s*=\s*\[[^\]]*ide(?:\.ps1|\.cmd)?["'']?\s*,\s*["''](?:--agent-state|state)["'']\s*,\s*["'']done["'']\s*\]\s*(?:#.*)?$'
    $anyNotifyRegex = '^\s*notify\s*='

    $exists = [System.IO.File]::Exists($ConfigPath)
    $existingText = if ($exists) { [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8) } else { '' }
    $lines = if ($existingText) { @($existingText.Replace("`r`n", "`n") -split "`n") } else { @() }
    if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
        $lines = if ($lines.Count -gt 1) { @($lines[0..($lines.Count - 2)]) } else { @() }
    }

    if ($Remove) {
        if (-not $exists) { return }
        $kept = [System.Collections.Generic.List[string]]::new()
        $removed = $false
        $inTop = $true
        foreach ($ln in $lines) {
            if ($ln.TrimStart().StartsWith('[')) { $inTop = $false }
            if ($inTop -and $ln -match $ideNotifyRegex) {
                $removed = $true
                continue
            }
            $kept.Add($ln)
        }
        if (-not $removed) { return }
        while ($kept.Count -gt 0 -and -not $kept[0].Trim()) {
            $kept.RemoveAt(0)
        }
        $hasContent = [bool]($kept | Where-Object { $_.Trim() } | Select-Object -First 1)
        if (-not $hasContent) {
            Save-ReconciledHookFile -Label 'Codex CLI notify hook' -FilePath $ConfigPath -DeleteWhenEmpty -DryRun:$DryRun
        } else {
            $body = ($kept -join "`n").TrimEnd()
            Save-ReconciledHookFile -Label 'Codex CLI notify hook' -FilePath $ConfigPath -Content $body -DryRun:$DryRun
        }
        return
    }

    $newLines = [System.Collections.Generic.List[string]]::new()
    $inTop = $true
    $sawCustomNotify = $false
    $replacedIdeNotify = $false
    $firstTableIdx = -1

    foreach ($ln in $lines) {
        if ($inTop -and $ln.TrimStart().StartsWith('[')) {
            $inTop = $false
            $firstTableIdx = $newLines.Count
        }
        if ($inTop -and $ln -match $ideNotifyRegex) {
            if (-not $replacedIdeNotify) {
                $newLines.Add($canonicalLine)
                $replacedIdeNotify = $true
            }
            continue
        }
        if ($inTop -and $ln -match $anyNotifyRegex) {
            $sawCustomNotify = $true
        }
        $newLines.Add($ln)
    }

    if (-not $sawCustomNotify -and -not $replacedIdeNotify) {
        if ($firstTableIdx -lt 0) {
            $newLines.Add($canonicalLine)
        } else {
            $newLines.Insert($firstTableIdx, '')
            $newLines.Insert($firstTableIdx, $canonicalLine)
        }
    }

    $rendered = ($newLines -join "`n").TrimEnd()
    Save-ReconciledHookFile -Label 'Codex CLI notify hook' -FilePath $ConfigPath -Content $rendered -DryRun:$DryRun
}

function Sync-AiCliHooks {
    param(
        [string]$RepoRoot = '',
        [string]$AgyHooksPath = '',
        [string]$ClaudeSettingsPath = '',
        [string]$CodexConfigPath = '',
        [switch]$Remove,
        [switch]$DryRun
    )
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $baseRepo = if ($RepoRoot) { $RepoRoot } else { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
    $resolvedRepo = if (Test-Path -LiteralPath $baseRepo -PathType Container) {
        (Resolve-Path -LiteralPath $baseRepo).ProviderPath
    } else {
        [System.IO.Path]::GetFullPath($baseRepo)
    }

    $targetAgy = if ($AgyHooksPath) { $AgyHooksPath } else { Join-Path (Join-Path (Join-Path $userHome '.gemini') 'config') 'hooks.json' }
    $targetClaude = if ($ClaudeSettingsPath) { $ClaudeSettingsPath } else { Join-Path (Join-Path $userHome '.claude') 'settings.json' }
    $targetCodex = if ($CodexConfigPath) { $CodexConfigPath } else { Join-Path (Join-Path $userHome '.codex') 'config.toml' }

    Sync-AntigravityHooksFile -HooksPath $targetAgy -Remove:$Remove -DryRun:$DryRun
    Sync-ClaudeSettingsFile -SettingsPath $targetClaude -Remove:$Remove -DryRun:$DryRun
    Sync-CodexConfigFile -ConfigPath $targetCodex -ResolvedRepoRoot $resolvedRepo -Remove:$Remove -DryRun:$DryRun
}

if ($FunctionsOnly) { return }

if (-not $Remove -and -not $AgyHooksPath -and -not $ClaudeSettingsPath -and -not $CodexConfigPath) {
    Write-SetupStage -Stage '75-AiHooks' -Message 'Configuring AI CLI lifecycle hooks (agy, claude, codex)...'
}

Sync-AiCliHooks -RepoRoot $RepoRoot `
    -AgyHooksPath $AgyHooksPath `
    -ClaudeSettingsPath $ClaudeSettingsPath `
    -CodexConfigPath $CodexConfigPath `
    -Remove:$Remove `
    -DryRun:$DryRun
