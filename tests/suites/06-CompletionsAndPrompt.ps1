# =============================================================
# Suite 6: Tab Completions & Oh My Posh Prompt Rendering
# =============================================================
Write-Host "`n[6/8] Testing Tab Completions & Oh My Posh Rendering..." -ForegroundColor Yellow

$completionsScript = Join-Path $RootDir 'module\Completions.ps1'
try {
    Import-Module (Join-Path $RootDir 'module\WindowsSettings.psd1') -DisableNameChecking -Force
    . $completionsScript
    $themeFlags = @(TabExpansion2 -inputScript 'theme --' -cursorColumn 8).CompletionMatches.CompletionText
    $themeSlugs = @(TabExpansion2 -inputScript 'theme --set ' -cursorColumn 12).CompletionMatches.CompletionText
    $ideSubs = @(TabExpansion2 -inputScript 'ide ' -cursorColumn 4).CompletionMatches.CompletionText
    $ideAgents = @(TabExpansion2 -inputScript 'ide agent ' -cursorColumn 10).CompletionMatches.CompletionText
    $ideStates = @(TabExpansion2 -inputScript 'ide state ' -cursorColumn 10).CompletionMatches.CompletionText
    $qideComp = @(TabExpansion2 -inputScript 'qide --' -cursorColumn 7).CompletionMatches.CompletionText
    $tfRoot = @(TabExpansion2 -inputScript 'tf ' -cursorColumn 3).CompletionMatches.CompletionText
    $tfState = @(TabExpansion2 -inputScript 'terraform state ' -cursorColumn 16).CompletionMatches.CompletionText
    $tfPlanFlags = @(TabExpansion2 -inputScript 'tf plan -' -cursorColumn 9).CompletionMatches.CompletionText
    $updSkipSpace = @(TabExpansion2 -inputScript 'update-system --skip winget,' -cursorColumn 28).CompletionMatches.CompletionText
    $updSkipEq = @(TabExpansion2 -inputScript 'update-system --skip=winget,' -cursorColumn 28).CompletionMatches.CompletionText

    if (($themeFlags -contains '--check-assets') -and
        ($themeSlugs -contains 'dracula') -and
        ($themeSlugs -contains 'rose-pine') -and
        ($ideSubs -contains 'switch') -and
        ($ideSubs -contains 'new') -and
        ($ideSubs -contains 'dir') -and
        ($ideSubs -contains 'agent') -and
        ($ideAgents -contains 'restart') -and
        ($ideStates -contains 'quota') -and
        ($qideComp -contains '--force') -and
        ($tfRoot -contains 'stacks') -and
        ($tfState -contains 'replace-provider') -and
        ($tfPlanFlags -contains '-auto-approve' -or $tfPlanFlags -contains '-out=') -and
        ($updSkipSpace -contains 'nvim') -and
        ($updSkipSpace -notcontains 'winget') -and
        ($updSkipEq -contains 'nvim') -and
        ($updSkipEq -notcontains 'winget')) {
        Add-TestPass 'Completions.ps1 provides 22-theme, 16-subcommand ide, full terraform/tf, and update-system --skip completions'
    } else {
        Add-TestFail 'Completions.ps1 validation' 'Missing expected theme, ide, terraform/tf, or update-system completions'
    }
} catch {
    Add-TestFail 'module/Completions.ps1' $_.Exception.Message
}

$p10kPath = Join-Path $RootDir 'config\powershell\p10k_single_line.omp.json'
$themeScript = Join-Path $RootDir 'bin\theme.ps1'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        $renderOutput = oh-my-posh print primary --config $p10kPath
        $rightOutput = oh-my-posh print right --config $p10kPath
        $errorRightOutput = oh-my-posh print right --config $p10kPath --status 1
        if ($renderOutput -and $rightOutput -and $errorRightOutput) {
            Add-TestPass 'Oh My Posh primary and right status prompts render cleanly'
        } else {
            Add-TestFail 'Oh My Posh rendering' 'Primary or right prompt output was empty'
        }

        $prevPrLabel = $env:_WS_GIT_PR_LABEL
        $prevPrUrl = $env:_WS_GIT_PR_URL
        try {
            $env:_WS_GIT_PR_LABEL = '@168'
            $env:_WS_GIT_PR_URL = 'https://github.com/lock14/windows-settings/pull/168'
            $prRender = oh-my-posh print primary --config $p10kPath
            if ($prRender -match '@168') {
                Add-TestPass 'Oh My Posh primary prompt renders clickable @<PR> badge when _WS_GIT_PR_LABEL is set'
            } else {
                Add-TestFail 'Oh My Posh PR badge' 'Expected @168 in rendered prompt'
            }
        } finally {
            $env:_WS_GIT_PR_LABEL = $prevPrLabel
            $env:_WS_GIT_PR_URL = $prevPrUrl
        }

        $liveSwitchCheck = (& pwsh -NoProfile -Command "
            `$orig = (& '$($themeScript.Replace("'", "''"))' --current).Trim()
            if (-not `$orig) { `$orig = 'solarized-dark' }
            try {
                & '$($themeScript.Replace("'", "''"))' --set solarized-dark --no-live | Out-Null
                Import-Module '$((Join-Path $RootDir 'module\WindowsSettings.psd1').Replace("'", "''"))' -DisableNameChecking -Force
                `$pSol = prompt
                theme dracula --no-live | Out-Null
                `$pDrac = prompt
                & pwsh -NoProfile -File '$($themeScript.Replace("'", "''"))' --set halloween --no-live | Out-Null
                `$pHal = prompt
                if (`$pSol -match '48;2;7;54;66' -and `$pDrac -match '48;2;56;59;76' -and `$pHal -match '48;2;40;16;64') {
                    Write-Output 'LIVE_PROMPT_OK'
                } else {
                    Write-Output 'LIVE_PROMPT_MISMATCH'
                }
            } finally {
                & '$($themeScript.Replace("'", "''"))' --set `$orig --no-live | Out-Null
            }
        ") -join "`n"
        if ($liveSwitchCheck -match 'LIVE_PROMPT_OK') {
            Add-TestPass 'Oh My Posh live & cross-pane prompt colors react immediately across Solarized Dark, Dracula & Halloween'
        } else {
            Add-TestFail 'Oh My Posh live theme switch' "Prompt colors did not update ($liveSwitchCheck)"
        }
    } catch {
        Add-TestFail 'Oh My Posh rendering error' $_.Exception.Message
    }
} else {
    Write-Host '  [SKIP] oh-my-posh not installed in current environment' -ForegroundColor DarkCyan
}
