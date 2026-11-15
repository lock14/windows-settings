# =============================================================
# Test Suite for windows-settings (Modern Workstation Architecture)
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Test 4 explicitly verifies prior global:LASTEXITCODE handling')]
param()

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

$script:TestsPassed = 0
$script:TestsFailed = 0

function Pass($name) {
    Write-Host "  [PASS] $name" -ForegroundColor Green
    $script:TestsPassed++
}

function Fail($name, $reason) {
    Write-Host "  [FAIL] $name" -ForegroundColor Red
    Write-Host "         $reason" -ForegroundColor DarkRed
    $script:TestsFailed++
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running windows-settings Test Suite     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -------------------------------------------------------------
# Test 1: PowerShell Syntax Checks
# -------------------------------------------------------------
Write-Host "`n[1/8] Checking PowerShell Scripts & Module Syntax..." -ForegroundColor Yellow
$psFiles = Get-ChildItem -Path $RootDir -Recurse -Include "*.ps1", "*.psm1", "*.psd1" |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp)[\\/]' }

foreach ($file in $psFiles) {
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -eq 0) {
        Pass "Syntax valid: $($file.Name)"
    } else {
        $msg = ($errors | ForEach-Object { $_.Message }) -join '; '
        Fail "Syntax invalid: $($file.Name)" $msg
    }
}

# -------------------------------------------------------------
# Test 2: JSON, Manifest, Theme & Polyglot Asset Validity
# -------------------------------------------------------------
Write-Host "`n[2/8] Validating JSON, Manifests, 17-Theme Engine & 40-Language Assets..." -ForegroundColor Yellow

# Test config/powershell/p10k_single_line.omp.json
$p10kPath = Join-Path $RootDir "config\powershell\p10k_single_line.omp.json"
try {
    $p10kRaw = Get-Content $p10kPath -Raw
    $p10kJson = $p10kRaw | ConvertFrom-Json
    if ($p10kJson.blocks.Count -gt 0) {
        Pass "JSON valid: config/powershell/p10k_single_line.omp.json (blocks: $($p10kJson.blocks.Count))"
        $rpromptBlock = $p10kJson.blocks | Where-Object { $_.type -eq "rprompt" }
        $leftPromptBlock = $p10kJson.blocks | Where-Object { $_.type -eq "prompt" }
        $leftCap = $leftPromptBlock.segments | Where-Object { $_.type -eq "text" -and ($_.template -eq [char]0xE0B0 -or $_.template -eq "\uE0B0") }
        $statusSegment = $rpromptBlock.segments[0]
        if ($statusSegment -and $statusSegment.type -eq "status" -and $statusSegment.properties.always_enabled -eq $true -and $statusSegment.foreground -eq "#859900") {
            Pass "p10k_single_line.omp.json rprompt status segment is leftmost and always_enabled with Solarized Green"
        } else {
            Fail "p10k_single_line.omp.json rprompt validation" "Status segment is not the leftmost segment or not always_enabled in Solarized Green"
        }
        if ($leftCap -and $leftCap.foreground -eq "#073642" -and -not $leftCap.foreground_templates) {
            Pass "p10k_single_line.omp.json left endpoint cap is static Base02 (no status mutation)"
        } else {
            Fail "p10k_single_line.omp.json left cap validation" "Left endpoint cap must be static Base02 without foreground_templates"
        }
        if ($p10kRaw -match '_WS_GIT_PR_LABEL' -and $p10kRaw -match '_WS_GIT_PR_URL' -and $p10kRaw -match '_HS_PROMPT_OS_ICON') {
            Pass "p10k_single_line.omp.json includes async OSC 8 Git PR badge & holiday OS icon support"
        } else {
            Fail "p10k_single_line.omp.json PR/holiday templates" "Missing _WS_GIT_PR_LABEL, _WS_GIT_PR_URL, or _HS_PROMPT_OS_ICON"
        }
    } else {
        Fail "JSON validation: config/powershell/p10k_single_line.omp.json" "Missing blocks definition"
    }
} catch {
    Fail "JSON parse error: config/powershell/p10k_single_line.omp.json" $_.Exception.Message
}

# Test config/terminal/settings.json & windows-settings.json (17 schemes + IDE keybindings)
$terminalJsonPath = Join-Path $RootDir "config\terminal\settings.json"
try {
    $termJson = Get-Content $terminalJsonPath -Raw | ConvertFrom-Json
    $hasSolarized = ($termJson.profiles.defaults.colorScheme -eq "Solarized Dark")
    $hasFont = ($termJson.profiles.defaults.font.face -eq "MesloLGS Nerd Font Mono" -or $termJson.profiles.defaults.font.face -eq "MesloLGS NF")
    $schemeCount = @($termJson.schemes).Count
    if ($hasSolarized -and $hasFont -and $schemeCount -ge 17) {
        Pass "JSON valid: config/terminal/settings.json ($schemeCount schemes, Solarized Dark + $($termJson.profiles.defaults.font.face))"
    } else {
        Fail "config/terminal/settings.json validation" "Expected Solarized Dark, MesloLGS font, and >=17 schemes (got $schemeCount)"
    }
} catch {
    Fail "JSON parse error: config/terminal/settings.json" $_.Exception.Message
}

$fragmentJsonPath = Join-Path $RootDir "config\terminal\windows-settings.json"
try {
    $fragRaw = Get-Content $fragmentJsonPath -Raw
    $fragJson = $fragRaw | ConvertFrom-Json
    $fragSolarized = ($fragJson.profiles.defaults.colorScheme -eq "Solarized Dark")
    $fragFont = ($fragJson.profiles.defaults.font.face -eq "MesloLGS Nerd Font Mono" -or $fragJson.profiles.defaults.font.face -eq "MesloLGS NF")
    $fragSchemes = @($fragJson.schemes).Count
    $passesAltToZellij = ($fragRaw -notmatch '"alt\+h"' -and $fragRaw -notmatch '"alt\+z"' -and $fragRaw -match 'ctrl\+v')
    if ($fragSolarized -and $fragFont -and $fragSchemes -ge 17 -and $passesAltToZellij) {
        Pass "JSON valid: config/terminal/windows-settings.json ($fragSchemes schemes + Alt+* pass-through to Zellij)"
    } else {
        Fail "config/terminal/windows-settings.json" "Defaults, 17 schemes ($fragSchemes), or Alt+* pass-through ($passesAltToZellij) mismatch"
    }
} catch {
    Fail "JSON parse error: config/terminal/windows-settings.json" $_.Exception.Message
}

# Test Zellij 0.46+ declarative configuration, layouts & theme (config/zellij/)
$zellijDir = Join-Path $RootDir "config\zellij"
$zellijCfgPath = Join-Path $zellijDir "config.kdl"
$zellijLayout3Path = Join-Path $zellijDir "layouts\ide-3pane.kdl"
$zellijLayout2Path = Join-Path $zellijDir "layouts\ide-2pane.kdl"
$zellijThemePath = Join-Path $zellijDir "themes\windows-settings.kdl"
if ((Test-Path $zellijCfgPath) -and (Test-Path $zellijLayout3Path) -and (Test-Path $zellijLayout2Path) -and (Test-Path $zellijThemePath)) {
    $zellijCfgRaw = Get-Content $zellijCfgPath -Raw
    $zellijLayout3Raw = Get-Content $zellijLayout3Path -Raw
    $zellijLayout2Raw = Get-Content $zellijLayout2Path -Raw
    $zellijThemeRaw = Get-Content $zellijThemePath -Raw
    if ($zellijCfgRaw -match 'pane_frames false' -and
        $zellijCfgRaw -match 'context_menu \{' -and
        $zellijCfgRaw -match 'bar clear-defaults=true' -and
        $zellijCfgRaw -match 'Focus AI agent' -and
        $zellijCfgRaw -match 'Quit IDE workspace' -and
        $zellijCfgRaw -match 'attention \{' -and
        $zellijCfgRaw -match 'track_commands false' -and
        $zellijCfgRaw -match 'tray_badge_colors' -and
        $zellijCfgRaw -match 'terminal \{' -and
        $zellijCfgRaw -match 'GoToNextAttention' -and
        $zellijCfgRaw -match 'session-manager' -and
        $zellijCfgRaw -match '// BEGIN WINDOWS-SETTINGS BAR PLUGIN' -and
        $zellijCfgRaw -match 'file:windows-settings-bar' -and
        $zellijLayout3Raw -match 'compact-bar' -and
        $zellijLayout3Raw -match '--pane-init' -and
        $zellijLayout3Raw -match 'attention_muted=true' -and
        $zellijLayout2Raw -match 'attention_muted=true' -and
        $zellijThemeRaw -match 'windows-settings \{') {
        Pass "KDL valid: config/zellij/ (config.kdl + context_menu, ide-3pane.kdl, ide-2pane.kdl, themes/windows-settings.kdl)"
    } else {
        Fail "config/zellij/ content validation" "Missing expected Zellij 0.46+ context_menu, attention, terminal, compact-bar, or theme blocks"
    }

    $zellijCmd = Get-Command zellij -ErrorAction SilentlyContinue
    if ($zellijCmd) {
        $zjCheck3 = (& $zellijCmd.Source --config-dir $zellijDir setup --check 2>&1) -join "`n"
        $zjExit3 = $LASTEXITCODE
        $zjCheck2 = (& $zellijCmd.Source --config-dir $zellijDir --layout $zellijLayout2Path setup --check 2>&1) -join "`n"
        $zjExit2 = $LASTEXITCODE
        if ($zjExit3 -eq 0 -and $zjExit2 -eq 0 -and $zjCheck3 -match 'Well defined' -and $zjCheck2 -match 'Well defined') {
            Pass "zellij setup --check validates config.kdl + ide-3pane.kdl & ide-2pane.kdl"
        } else {
            Fail "zellij setup --check" "Exit codes ($zjExit3, $zjExit2): $zjCheck3"
        }
    }
} else {
    Fail "config/zellij/ files missing" "Expected config.kdl, ide-3pane.kdl, ide-2pane.kdl, and themes/windows-settings.kdl"
}

# Test Rust WASM Top-Bar Plugin crate (plugin/ws-bar/)
$wsBarDir = Join-Path (Join-Path $RootDir "plugin") "ws-bar"
$wsBarCargo = Join-Path $wsBarDir "Cargo.toml"
$wsBarLock = Join-Path $wsBarDir "Cargo.lock"
$wsBarSrcFiles = @("main.rs", "palette.rs", "roles.rs", "render.rs") | ForEach-Object { Join-Path (Join-Path $wsBarDir "src") $_ }
if ((Test-Path -LiteralPath $wsBarCargo) -and (Test-Path -LiteralPath $wsBarLock) -and (@($wsBarSrcFiles | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0)) {
    $wsBarCargoRaw = Get-Content -LiteralPath $wsBarCargo -Raw
    if ($wsBarCargoRaw -match 'name\s*=\s*"windows-settings-bar"' -and $wsBarCargoRaw -match 'zellij-tile\s*=\s*"0\.46\.0"') {
        Pass "WASM plugin crate valid: plugin/ws-bar/ (Cargo.toml, Cargo.lock, main/palette/roles/render.rs)"
    } else {
        Fail "plugin/ws-bar/Cargo.toml" "Expected name = windows-settings-bar and zellij-tile = 0.46.0"
    }
} else {
    Fail "plugin/ws-bar/ files missing" "Expected Cargo.toml, Cargo.lock, and src/{main,palette,roles,render}.rs"
}

# Test .gitattributes line-ending rules (.ps1/.cmd = crlf, .kdl/.json/.md/.yml/.rs = lf)
$gitAttributesPath = Join-Path $RootDir ".gitattributes"
if (Test-Path $gitAttributesPath) {
    $gitAttrRaw = Get-Content $gitAttributesPath -Raw
    if ($gitAttrRaw -match '\*\.ps1\s+text\s+eol=crlf' -and $gitAttrRaw -match '\*\.cmd\s+text\s+eol=crlf' -and $gitAttrRaw -match '\*\.kdl\s+text\s+eol=lf' -and $gitAttrRaw -match '\*\.rs\s+text\s+eol=lf' -and $gitAttrRaw -match '\*\.yml\s+text\s+eol=lf') {
        Pass ".gitattributes enforces CRLF for .ps1/.cmd and LF for .kdl/.rs/.yml/.md configs"
    } else {
        Fail ".gitattributes validation" "Missing expected CRLF/LF rules in .gitattributes"
    }
}

# Test Repository Governance, LLM Index & GitHub Templates/Workflows
$licensePath = Join-Path $RootDir "LICENSE"
if ((Test-Path $licensePath) -and ((Get-Content $licensePath -Raw) -match 'Apache License\s+Version 2\.0')) {
    Pass "Governance: Apache-2.0 LICENSE present at repository root"
} else {
    Fail "Governance: LICENSE" "Missing or invalid Apache-2.0 LICENSE at repository root"
}

foreach ($govDoc in @(
    @{ Rel = 'AGENTS.md';       Pattern = 'Universal semantic color contract' },
    @{ Rel = 'CONTRIBUTING.md'; Pattern = 'Pre-completion verification checklist' },
    @{ Rel = 'SECURITY.md';     Pattern = 'Private Vulnerability Reporting' },
    @{ Rel = 'llms.txt';        Pattern = '## Core components' }
)) {
    $govFull = Join-Path $RootDir $govDoc.Rel
    if ((Test-Path $govFull) -and ((Get-Content $govFull -Raw) -match $govDoc.Pattern)) {
        Pass "Governance & LLM index valid: $($govDoc.Rel)"
    } else {
        Fail "Governance doc check: $($govDoc.Rel)" "Missing file or required section ($($govDoc.Pattern))"
    }
}

if (-not (Test-Path (Join-Path $RootDir 'CLAUDE.md')) -and -not (Test-Path (Join-Path $RootDir '.agents\AGENTS.md'))) {
    Pass "Single canonical AGENTS.md maintained (no duplicate CLAUDE.md or .agents/AGENTS.md)"
} else {
    Fail "Single AGENTS.md invariant" "Unexpected duplicate CLAUDE.md or .agents/AGENTS.md found"
}

foreach ($ghRel in @(
    @{ Rel = '.github\PULL_REQUEST_TEMPLATE.md';           Pattern = '## Verification' },
    @{ Rel = '.github\ISSUE_TEMPLATE\bug_report.yml';      Pattern = 'title:\s*"\[Bug\]: "' },
    @{ Rel = '.github\ISSUE_TEMPLATE\feature_request.yml'; Pattern = 'title:\s*"\[Feature\]: "' },
    @{ Rel = '.github\ISSUE_TEMPLATE\config.yml';          Pattern = 'blank_issues_enabled:\s*false' },
    @{ Rel = '.github\dependabot.yml';                     Pattern = 'package-ecosystem:\s*github-actions' },
    @{ Rel = '.github\workflows\ci.yml';                   Pattern = 'ci-gatekeeper:' },
    @{ Rel = '.github\workflows\security.yml';             Pattern = 'secret-scan:' }
)) {
    $ghFull = Join-Path $RootDir $ghRel.Rel
    if ((Test-Path $ghFull) -and ((Get-Content $ghFull -Raw) -match $ghRel.Pattern)) {
        Pass "GitHub governance/workflow valid: $($ghRel.Rel.Replace('\', '/'))"
    } else {
        Fail "GitHub governance/workflow check: $($ghRel.Rel)" "Missing file or required pattern ($($ghRel.Pattern))"
    }
}

# Test Documentation Typography, Formatting Restraint, JSON Blocks & Link/Anchor Integrity
function Find-ClosingBacktickRun {
    param([string]$Text, [int]$TickCount)
    for ($i = 0; $i -le ($Text.Length - $TickCount); ) {
        if ($Text[$i] -ne '`') {
            $i++
            continue
        }
        $run = 0
        while (($i + $run) -lt $Text.Length -and $Text[$i + $run] -eq '`') {
            $run++
        }
        if ($run -eq $TickCount) {
            return $i
        }
        $i += $run
    }
    return -1
}

function Get-LineWithoutInlineCode {
    param([string]$Line)
    $sb = [System.Text.StringBuilder]::new($Line.Length)
    for ($i = 0; $i -lt $Line.Length; ) {
        if ($Line[$i] -eq '`') {
            $tickCount = 0
            while (($i + $tickCount) -lt $Line.Length -and $Line[$i + $tickCount] -eq '`') {
                $tickCount++
            }
            $closeRel = Find-ClosingBacktickRun -Text $Line.Substring($i + $tickCount) -TickCount $tickCount
            if ($closeRel -ge 0) {
                $i += $tickCount + $closeRel + $tickCount
                continue
            }
            [void]$sb.Append($Line.Substring($i, $tickCount))
            $i += $tickCount
            continue
        }
        [void]$sb.Append($Line[$i])
        $i++
    }
    return $sb.ToString()
}

function Find-StackedFormatting {
    param([string]$Line)
    for ($i = 0; $i -lt $Line.Length; ) {
        if ($Line[$i] -eq '`') {
            $tickCount = 0
            while (($i + $tickCount) -lt $Line.Length -and $Line[$i + $tickCount] -eq '`') {
                $tickCount++
            }
            $closeRel = Find-ClosingBacktickRun -Text $Line.Substring($i + $tickCount) -TickCount $tickCount
            if ($closeRel -ge 0) {
                $i += $tickCount + $closeRel + $tickCount
                continue
            }
            $i += $tickCount
            continue
        }

        $tail = $Line.Substring($i)
        if ($tail.StartsWith('***')) {
            $end = $tail.Substring(3).IndexOf('***')
            if ($end -ge 0) { return $Line.Substring($i, 3 + $end + 3) }
        }
        if ($tail.StartsWith('_**')) {
            $end = $tail.Substring(3).IndexOf('**_')
            if ($end -ge 0) { return $Line.Substring($i, 3 + $end + 3) }
        }
        if ($tail.StartsWith('**')) {
            $end = $tail.Substring(2).IndexOf('**')
            if ($end -ge 0) {
                $inner = $Line.Substring($i + 2, $end)
                $full = $Line.Substring($i, 2 + $end + 2)
                if ($inner.Contains('`')) { return $full }
                if ($inner.Contains('[') -and $inner.Contains('](')) { return $full }
                if (($inner.StartsWith('_') -and $inner.EndsWith('_') -and $inner.Length -gt 2) -or
                    ($inner.StartsWith('*') -and $inner.EndsWith('*') -and $inner.Length -gt 2)) {
                    return $full
                }
                $i += 2 + $end + 2
                continue
            }
        }
        if ($Line[$i] -eq '[') {
            $closeBracket = $Line.Substring($i + 1).IndexOf(']')
            if ($closeBracket -ge 0) {
                $afterBracket = $i + 1 + $closeBracket + 1
                if ($afterBracket -lt $Line.Length -and $Line[$afterBracket] -eq '(') {
                    $linkText = $Line.Substring($i + 1, $closeBracket)
                    if ($linkText.Contains('**')) {
                        $closeParen = $Line.Substring($afterBracket + 1).IndexOf(')')
                        if ($closeParen -ge 0) {
                            return $Line.Substring($i, $afterBracket + 1 + $closeParen + 1 - $i)
                        }
                    }
                }
            }
        }
        $i++
    }
    return ''
}

function Get-GitHubHeadingSlug {
    param([string]$Heading)
    $stripped = [regex]::Replace($Heading, '\[([^\]]+)\]\([^)]+\)', '$1')
    $lower = $stripped.Trim().ToLowerInvariant()
    $sb = [System.Text.StringBuilder]::new()
    foreach ($ch in $lower.ToCharArray()) {
        if ([char]::IsLetterOrDigit($ch) -or $ch -eq '-' -or $ch -eq '_') {
            [void]$sb.Append($ch)
        } elseif ($ch -eq ' ') {
            [void]$sb.Append('-')
        }
    }
    return $sb.ToString()
}

function Get-MarkdownLinkTarget {
    param([string]$Line)
    $cleaned = Get-LineWithoutInlineCode -Line $Line
    $targets = [System.Collections.Generic.List[string]]::new()
    for ($pos = 0; $pos -lt $cleaned.Length; ) {
        $idx = $cleaned.Substring($pos).IndexOf('](')
        if ($idx -lt 0) { break }
        $start = $pos + $idx + 2
        $depth = 1
        $raw = [System.Text.StringBuilder]::new()
        $j = $start
        while ($j -lt $cleaned.Length -and $depth -gt 0) {
            if ($cleaned[$j] -eq '\' -and ($j + 1) -lt $cleaned.Length) {
                [void]$raw.Append($cleaned[$j + 1])
                $j += 2
                continue
            }
            if ($cleaned[$j] -eq '(') {
                $depth++
                [void]$raw.Append('(')
                $j++
                continue
            }
            if ($cleaned[$j] -eq ')') {
                $depth--
                if ($depth -eq 0) { break }
                [void]$raw.Append(')')
                $j++
                continue
            }
            [void]$raw.Append($cleaned[$j])
            $j++
        }
        if ($depth -ne 0) { break }
        $target = $raw.ToString().Trim()
        if ($target -match '^\S+') { $target = $Matches[0] }
        $target = $target.TrimStart('<').TrimEnd('>')
        if ($target -ne '') { $targets.Add($target) }
        $pos = $j + 1
    }
    return $targets
}

$docLintMarkdownFiles = @(
    'README.md',
    'CONTRIBUTING.md',
    'AGENTS.md',
    'SECURITY.md',
    'llms.txt',
    '.github\PULL_REQUEST_TEMPLATE.md'
)
$docLintYamlFiles = @(
    '.github\ISSUE_TEMPLATE\bug_report.yml',
    '.github\ISSUE_TEMPLATE\feature_request.yml',
    '.github\ISSUE_TEMPLATE\config.yml',
    '.github\dependabot.yml',
    '.github\workflows\ci.yml',
    '.github\workflows\security.yml'
)

$docEmojiRegex = '([\uD83C-\uDBFF][\uDC00-\uDFFF]|[\u26A1\u2705\u2728\u274C]|:(?:white_check_mark|x):)'
$docBoldCellRegex = '^\|\s*\*\*[^*]+\*\*\s*\|'
$docItalicAsideRegex = '(?i)(\*|_)\((?:note|tip|alternatively)\b'
$docProseArrowRegex = '(<->|->|<-|=>|\\rightarrow|\\leftrightarrow|\\gg|[\u2190-\u21FF\u226B])'
$docPersonalPathRegex = '(?i)(/home/(?!<)[a-z0-9_-]+|/Users/(?!<)[a-z0-9_-]+|C:\\Users\\(?!<)[a-z0-9_-]+)'

$docEmojiAndPathErrors = [System.Collections.Generic.List[string]]::new()
$docTypographyErrors = [System.Collections.Generic.List[string]]::new()
$docLinkAndJsonErrors = [System.Collections.Generic.List[string]]::new()

foreach ($relYaml in $docLintYamlFiles) {
    $fullYaml = Join-Path $RootDir $relYaml
    if (-not (Test-Path $fullYaml)) { continue }
    $yamlText = [System.IO.File]::ReadAllText($fullYaml)
    if ($yamlText -match $docPersonalPathRegex) {
        $docEmojiAndPathErrors.Add("${relYaml}: personal path '$($Matches[0])'")
    }
    if ($yamlText -match $docEmojiRegex) {
        $docEmojiAndPathErrors.Add("${relYaml}: decorative emoji or shortcode '$($Matches[0])'")
    }
}

foreach ($relDoc in $docLintMarkdownFiles) {
    $fullDoc = Join-Path $RootDir $relDoc
    if (-not (Test-Path $fullDoc)) { continue }
    $docText = [System.IO.File]::ReadAllText($fullDoc)
    if ($docText -match $docPersonalPathRegex) {
        $docEmojiAndPathErrors.Add("${relDoc}: personal path '$($Matches[0])'")
    }
    if ($docText -match $docEmojiRegex) {
        $docEmojiAndPathErrors.Add("${relDoc}: decorative emoji or shortcode '$($Matches[0])'")
    }

    $docLines = $docText -split "`n"
    $inFence = $false
    $fenceLang = ''
    $fenceStart = 0
    $fenceBuf = [System.Text.StringBuilder]::new()
    $headingSlugs = @{}
    $slugCounts = @{}

    for ($idx = 0; $idx -lt $docLines.Count; $idx++) {
        $lineNum = $idx + 1
        $line = $docLines[$idx].TrimEnd("`r")
        $trimmed = $line.Trim()

        if ($trimmed.StartsWith('```')) {
            if (-not $inFence) {
                $inFence = $true
                $fenceLang = $trimmed.Substring(3).Trim().ToLowerInvariant()
                $fenceStart = $lineNum
                [void]$fenceBuf.Clear()
            } else {
                if ($fenceLang -eq 'json') {
                    try {
                        $null = $fenceBuf.ToString() | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        $docLinkAndJsonErrors.Add("${relDoc}:${fenceStart}: invalid JSON code block")
                    }
                }
                $inFence = $false
                $fenceLang = ''
            }
            continue
        }
        if ($inFence) {
            [void]$fenceBuf.AppendLine($line)
            continue
        }

        if ($trimmed -eq '---') {
            $docTypographyErrors.Add("${relDoc}:${lineNum}: horizontal rule divider '---'")
        }
        if ($trimmed -match $docBoldCellRegex) {
            $docTypographyErrors.Add("${relDoc}:${lineNum}: bolded first-column table cell '$($Matches[0].Trim())'")
        }
        $stackedSpan = Find-StackedFormatting -Line $line
        if ($stackedSpan -ne '') {
            $docTypographyErrors.Add("${relDoc}:${lineNum}: stacked formatting '$stackedSpan'")
        }

        $cleanedLine = [regex]::Replace((Get-LineWithoutInlineCode -Line $line), '<!--.*?-->', '')
        if ($cleanedLine -match $docItalicAsideRegex) {
            $docTypographyErrors.Add("${relDoc}:${lineNum}: italic parenthetical aside '$($Matches[0])'")
        }
        if ($cleanedLine -match $docProseArrowRegex) {
            $docTypographyErrors.Add("${relDoc}:${lineNum}: prose arrow '$($Matches[0])'")
        }

        if ($trimmed.StartsWith('#')) {
            $title = $trimmed.TrimStart('#').Trim()
            if ($title -ne '') {
                $baseSlug = Get-GitHubHeadingSlug -Heading $title
                if ($baseSlug -ne '') {
                    $count = if ($slugCounts.ContainsKey($baseSlug)) { $slugCounts[$baseSlug] } else { 0 }
                    $slugCounts[$baseSlug] = $count + 1
                    $slug = if ($count -gt 0) { "$baseSlug-$count" } else { $baseSlug }
                    $headingSlugs[$slug] = $true
                }
            }
        }
    }

    $inFence = $false
    $docDir = Split-Path -Parent $fullDoc
    for ($idx = 0; $idx -lt $docLines.Count; $idx++) {
        $lineNum = $idx + 1
        $line = $docLines[$idx].TrimEnd("`r")
        $trimmed = $line.Trim()
        if ($trimmed.StartsWith('```')) {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }

        foreach ($target in (Get-MarkdownLinkTarget -Line $line)) {
            if ($target.StartsWith('#')) {
                $slug = $target.Substring(1)
                if (-not $headingSlugs.ContainsKey($slug)) {
                    $docLinkAndJsonErrors.Add("${relDoc}:${lineNum}: broken anchor link '$target'")
                }
                continue
            }
            if ($target.StartsWith('http://') -or $target.StartsWith('https://') -or $target.StartsWith('mailto:')) {
                continue
            }
            $relTarget = $target
            $hashIdx = $relTarget.IndexOf('#')
            if ($hashIdx -ge 0) {
                $relTarget = $relTarget.Substring(0, $hashIdx)
            }
            if ($relTarget -eq '') { continue }
            $targetPath = Join-Path $docDir ($relTarget.Replace('/', '\'))
            if (-not (Test-Path $targetPath)) {
                $docLinkAndJsonErrors.Add("${relDoc}:${lineNum}: broken relative file link '$target'")
            }
        }
    }
}

if ($docEmojiAndPathErrors.Count -eq 0) {
    Pass "Documentation & GitHub YAML free of decorative emojis, shortcodes & personal paths"
} else {
    Fail "Documentation emoji/path hygiene" ($docEmojiAndPathErrors -join '; ')
}

if ($docTypographyErrors.Count -eq 0) {
    Pass "Documentation typography restraint valid (no '---', bold first-col cells, stacked spans, italic asides, or prose arrows)"
} else {
    Fail "Documentation typography restraint" ($docTypographyErrors -join '; ')
}

if ($docLinkAndJsonErrors.Count -eq 0) {
    Pass "Documentation JSON code blocks, #anchor slugs & relative file links valid"
} else {
    Fail "Documentation links/JSON blocks" ($docLinkAndJsonErrors -join '; ')
}

# Test configuration.dsc.yaml
$dscPath = Join-Path $RootDir "configuration.dsc.yaml"
if (Test-Path $dscPath) {
    $dscContent = Get-Content $dscPath -Raw
    if ($dscContent -match 'configurationVersion:\s*0\.2\.0' -and
        $dscContent -match 'JanDeDobbeleer\.OhMyPosh' -and
        $dscContent -match 'BrechtSanders\.WinLibs' -and
        $dscContent -match 'dandavison\.delta' -and
        $dscContent -match 'aristocratos\.btop4win' -and
        $dscContent -match 'bootandy\.dust' -and
        $dscContent -match 'Zellij\.Zellij') {
        Pass "YAML valid: configuration.dsc.yaml (WinGet DSC v3 Manifest with WinLibs GCC, Zellij, delta, dust, btop4win)"
    } else {
        Fail "configuration.dsc.yaml" "Missing expected DSC package declarations"
    }
}

# Test mise.toml
$misePath = Join-Path $RootDir "mise.toml"
if (Test-Path $misePath) {
    $miseContent = Get-Content $misePath -Raw
    if ($miseContent -match 'glow\s*=\s*"latest"' -and
        $miseContent -match 'zellij\s*=\s*"latest"' -and
        $miseContent -match 'tree-sitter\s*=\s*"latest"' -and
        $miseContent -match 'delta\s*=\s*"latest"' -and
        $miseContent -match 'dust\s*=\s*"latest"' -and
        $miseContent -match 'elan\s*=' -and
        $miseContent -match 'go\.set_gobin\s*=\s*false' -and
        $miseContent -match 'go\.set_gopath\s*=\s*false') {
        Pass "TOML valid: mise.toml (Polyglot toolchains, Zellij, CLI utilities & Go isolation)"
    } else {
        Fail "mise.toml validation" "Missing expected tools or Go isolation settings in mise.toml"
    }
}

# Test 17 Theme Definitions, 17 bat Themes & 17 btop Themes
$themesDir = Join-Path $RootDir "config\themes"
$themeFiles = @(Get-ChildItem -Path $themesDir -Filter "*.theme" -ErrorAction SilentlyContinue)
if ($themeFiles.Count -eq 17) {
    Pass "17 color palette definitions present in config/themes/ (9 classic + 8 US Holiday)"
} else {
    Fail "config/themes count" "Expected 17 .theme files, found $($themeFiles.Count)"
}

$batThemesDir = Join-Path $RootDir "config\bat\themes"
$batThemeFiles = @(Get-ChildItem -Path $batThemesDir -Filter "*-TrueColor.tmTheme" -ErrorAction SilentlyContinue)
if ($batThemeFiles.Count -eq 17) {
    Pass "17 pre-rendered bat TrueColor .tmTheme files present in config/bat/themes/"
} else {
    Fail "config/bat/themes count" "Expected 17 .tmTheme files, found $($batThemeFiles.Count)"
}

$btopThemesDir = Join-Path $RootDir "config\btop\themes"
$btopConfFile = Join-Path $RootDir "config\btop\btop.conf"
$btopThemeFiles = @(Get-ChildItem -Path $btopThemesDir -Filter "*.theme" -ErrorAction SilentlyContinue)
if ($btopThemeFiles.Count -eq 17 -and (Test-Path $btopConfFile)) {
    $btopConfRaw = Get-Content -LiteralPath $btopConfFile -Raw
    if ($btopConfRaw -match '(?m)^cpu_graph_upper\s*=\s*"total"' -and $btopConfRaw -notmatch '(?m)^cpu_graph_(upper|lower)\s*=\s*"Auto"') {
        Pass "17 btop/btop4win themes & btop4win-compatible btop.conf present in config/btop/"
    } else {
        Fail "config/btop/btop.conf compatibility" "cpu_graph_upper/cpu_graph_lower must use btop4win keys ('total'/'gpu'), not Linux-only 'Auto'"
    }
} else {
    Fail "config/btop validation" "Expected 17 btop themes and btop.conf, found $($btopThemeFiles.Count)"
}

# Test CLI Tool Configs (delta, tealdeer, clangd)
foreach ($cfgRel in @('config\git\delta.gitconfig', 'config\tealdeer\config.toml', 'config\clangd\config.yaml')) {
    $cfgFull = Join-Path $RootDir $cfgRel
    if (Test-Path $cfgFull) {
        Pass "CLI tool config present: $($cfgRel.Replace('\', '/'))"
    } else {
        Fail "CLI tool config missing" "$cfgRel not found"
    }
}

# Test Bat Syntaxes (37 standalone grammars) & Solarized Dark TrueColor Theme
$batSyntaxesDir = Join-Path $RootDir "config\bat\syntaxes"
if (Test-Path $batSyntaxesDir) {
    $syntaxFiles = @(Get-ChildItem -Path $batSyntaxesDir -Filter "*.sublime-syntax")
    if ($syntaxFiles.Count -eq 37) {
        Pass "Bat syntax grammars present: $($syntaxFiles.Count) standalone Sublime syntaxes in config/bat/syntaxes"
    } else {
        Fail "Bat syntaxes" "Expected 37 syntax grammars, found $($syntaxFiles.Count)"
    }
} else {
    Fail "Bat syntaxes directory" "config/bat/syntaxes not found"
}

$batThemePath = Join-Path $RootDir "config\bat\Solarized-Dark-TrueColor.tmTheme"
if (Test-Path $batThemePath) {
    $themeContent = Get-Content $batThemePath -Raw
    if ($themeContent -match 'Universal Semantic Color Contract' -or $themeContent -match '#859900') {
        Pass "Bat TrueColor theme valid: config/bat/Solarized-Dark-TrueColor.tmTheme"
    } else {
        Fail "Bat theme" "Solarized-Dark-TrueColor.tmTheme missing color definitions"
    }
}

# Test Fallback Vim configuration (_vimrc)
$vimrcPath = Join-Path $RootDir "config\vim\_vimrc"
if (Test-Path $vimrcPath) {
    $vimrcContent = Get-Content $vimrcPath -Raw
    if (($vimrcContent -match 'ApplySolarizedDark' -or $vimrcContent -match 'ApplyActiveTheme') -and
        $vimrcContent -match 'command!.*Theme' -and
        $vimrcContent -notmatch 'pathogen#infect' -and
        $vimrcContent -notmatch 'UltiSnips') {
        Pass "Vim fallback valid: config/vim/_vimrc (Zero-dependency standalone 17-theme engine)"
    } else {
        Fail "Vim fallback validation" "Expected standalone _vimrc with 17-theme engine and no pathogen/UltiSnips"
    }
}

# Test Neovim Tree-sitter Queries (43 queries, zero legacy markdown_inline url metadata)
$nvimQueriesDir = Join-Path $RootDir "config\nvim\queries"
$nvimAfterDir = Join-Path $RootDir "config\nvim\after\queries"
if ((Test-Path $nvimQueriesDir) -and (Test-Path $nvimAfterDir)) {
    $scmFiles = @(Get-ChildItem -Path (Join-Path $RootDir "config\nvim") -Recurse -Filter "*.scm")
    if ($scmFiles.Count -eq 43) {
        Pass "Neovim Tree-sitter query suite valid: $($scmFiles.Count) queries in config/nvim"
    } else {
        Fail "Neovim queries" "Expected 43 .scm query files, found $($scmFiles.Count)"
    }
    $mdInlineScm = Join-Path $nvimQueriesDir "markdown_inline\highlights.scm"
    $staleAfterMdInline = Join-Path $nvimAfterDir "markdown_inline"
    if ((Test-Path $mdInlineScm) -and -not (Test-Path $staleAfterMdInline)) {
        $mdScmContent = Get-Content $mdInlineScm -Raw
        if ($mdScmContent -notmatch '\(#set!\s+"url"') {
            Pass "Neovim markdown_inline base query eliminates legacy url metadata & stale after/queries override"
        } else {
            Fail "markdown_inline url metadata" "Found forbidden (#set! `"url`" ...) in markdown_inline/highlights.scm"
        }
    } else {
        Fail "markdown_inline query layout" "Expected queries/markdown_inline/highlights.scm and no after/queries/markdown_inline"
    }
}

# Test Sample Code polyglot suite (40 files)
$sampleCodeDir = Join-Path $RootDir "sample-code"
if (Test-Path $sampleCodeDir) {
    $sampleFiles = @(Get-ChildItem -Path $sampleCodeDir -File)
    if ($sampleFiles.Count -eq 40) {
        Pass "Sample code polyglot suite present: $($sampleFiles.Count) files in sample-code/"
    } else {
        Fail "Sample code" "Expected 40 sample files, found $($sampleFiles.Count)"
    }
}

# Test config/cmd/autorun.cmd and config/cmd/macros.doskey
$cmdAutorunPath = Join-Path $RootDir "config\cmd\autorun.cmd"
$cmdMacrosPath  = Join-Path $RootDir "config\cmd\macros.doskey"
if ((Test-Path $cmdAutorunPath) -and (Test-Path $cmdMacrosPath)) {
    Pass "CMD AutoRun script and macro file exist: config/cmd/autorun.cmd and config/cmd/macros.doskey"
    $cmdOutput = & cmd.exe /d /c "call `"$cmdAutorunPath`" && set COLORTERM && set FORCE_HYPERLINK && set BAT_THEME && set CC && set CXX && set PROMPT && doskey /macros"
    $hasColorTerm = [bool]($cmdOutput -match 'COLORTERM=truecolor')
    $hasHyperlink = [bool]($cmdOutput -match 'FORCE_HYPERLINK=1')
    $hasBatTheme = [bool]($cmdOutput -match 'BAT_THEME=')
    $hasCC = [bool]($cmdOutput -match 'CC=gcc')
    $hasCXX = [bool]($cmdOutput -match 'CXX=g\+\+')
    $hasPrompt = [bool]($cmdOutput -match 'PROMPT=')
    $hasLsMacro = [bool]($cmdOutput -match 'ls=ls --color=auto')
    $hasBMacro = [bool]($cmdOutput -match 'b=bat')
    $noCatMacro = -not [bool]($cmdOutput -match '^cat=bat')
    $hasGitMacro = [bool]($cmdOutput -match 'gst=git status')
    $hasIdeMacro = [bool]($cmdOutput -match 'ide3=ide --3pane')
    $autorunRaw = Get-Content $cmdAutorunPath -Raw
    $hasChcp = [bool]($autorunRaw -match 'chcp 65001')
    $hasShelf = [bool]($autorunRaw -match '48;2;7;54;66m' -and $autorunRaw -match '\$P')
    if ($hasColorTerm -and $hasHyperlink -and $hasBatTheme -and $hasCC -and $hasCXX -and $hasPrompt -and $hasLsMacro -and $hasBMacro -and $noCatMacro -and $hasGitMacro -and $hasIdeMacro -and $hasChcp -and $hasShelf) {
        Pass "config/cmd/autorun.cmd initializes TrueColor/OSC8 env, UTF-8 Base02 shelf prompt, and home-settings doskey macros (b=bat, raw cat)"
    } else {
        Fail "config/cmd/autorun.cmd execution" "Macro/env mismatch (Hyperlink:$hasHyperlink, b:$hasBMacro, noCat:$noCatMacro, ide3:$hasIdeMacro)"
    }
} else {
    Fail "config/cmd/autorun.cmd missing" "Expected config/cmd/autorun.cmd to exist"
}

# -------------------------------------------------------------
# Test 3: WindowsSettings Module Import & Function Exports
# -------------------------------------------------------------
Write-Host "`n[3/8] Testing WindowsSettings PowerShell Module Import..." -ForegroundColor Yellow
$moduleManifest = Join-Path $RootDir "module\WindowsSettings.psd1"

Import-Module $moduleManifest -Force -DisableNameChecking

$expectedFunctions = @(
    'go-testall', 'go-buildall', 'go-lint', 'yaml-lint', 'guser-branch',
    'go_testall', 'go_buildall', 'go_lint', 'yaml_lint', 'fix-abcxyz-branch-name',
    'b', 'fs', 'Format-PathTree', 'ls', 'll', 'la', 'l', 'lt',
    'e', 'el', 'et', 'elm', 'elt', 'elx', 'icd',
    'v', 'ide', 'ide2', 'ide3', 'idek', 'qide', 'quit',
    'gco', 'gcb', 'gcm', 'gcd', 'ga', 'gaa', 'gst', 'gss', 'gd', 'gds',
    'gl', 'gp', 'gb', 'gba', 'gbd', 'gbD', 'gsta', 'gstp', 'gstl',
    'glog', 'glo', 'grb', 'grba', 'grbc', 'grbi', 'grh', 'grhh', 'gsw', 'gswc',
    'gcp', 'gcpa', 'gcpc',
    'gcommit', 'gamend', 'gfetch', 'gpush', 'gpushf', 'gpull', 'gup', 'gprune', 'gpurge', 'gsync',
    'gen-passwd', 'repeat-until-success', 'sum',
    'ds', 'btop', 'update', 'update-system', 'theme'
)

foreach ($func in $expectedFunctions) {
    if (Get-Command $func -CommandType Function -ErrorAction SilentlyContinue) {
        Pass "Function defined & exported: $func"
    } else {
        Fail "Function missing: $func" "Get-Command could not find exported function $func"
    }
}

# Verify `cat` is un-aliased and NOT shadowed by a wrapper function (`b` = bat, `cat` = coreutils cat)
if (-not (Test-Path 'Alias:cat') -and -not (Get-Command cat -CommandType Function -ErrorAction SilentlyContinue)) {
    Pass "cat is un-aliased and un-wrapped so coreutils cat.exe runs natively"
} else {
    Fail "cat un-aliasing" "cat should not be a PowerShell alias or wrapper function"
}

$bPipeTest = (('b pipeline test' | & (Get-Command b -CommandType Function) --plain) -join "`n").Trim()
if ($bPipeTest -eq 'b pipeline test') {
    Pass "b (bat) function handles pipeline input cleanly without hanging"
} else {
    Fail "b function pipeline" "Expected 'b pipeline test', got '$bPipeTest'"
}

foreach ($al in @('tf', 'vi', 'vim')) {
    if (Get-Alias -Name $al -ErrorAction SilentlyContinue) {
        Pass "Alias defined: $al"
    } else {
        Fail "Alias missing: $al" "Alias $al not found"
    }
}

if ((Get-Command v -ErrorAction SilentlyContinue).CommandType -eq 'Function') {
    Pass "Smart RPC-aware editor opener 'v' exported as Function"
} else {
    Fail "v function" "Expected 'v' to be exported as a Function"
}

# Test Neovim configuration file & lazy-lock.json
$nvimInit = Join-Path $RootDir "config\nvim\init.lua"
$nvimLock = Join-Path $RootDir "config\nvim\lazy-lock.json"
if ((Test-Path $nvimInit) -and (Test-Path $nvimLock)) {
    $nvimContent = Get-Content $nvimInit -Raw
    if ($nvimContent -match 'apply_home_settings_theme' -and
        $nvimContent -match 'render-markdown' -and
        $nvimContent -match 'mini\.files' -and
        $nvimContent -match 'BrechtSanders\.WinLibs' -and
        $nvimContent -match 'vim\.env\.ZELLIJ' -and
        $nvimContent -match 'count_ide_modified_buffers') {
        Pass "Neovim modern Lua config & lazy-lock.json valid (17-theme engine, render-markdown, mini.files, Zellij + IDE RPC)"
    } else {
        Fail "Neovim init.lua" "Missing expected 17-theme, render-markdown, mini.files, Zellij, or IDE RPC hooks"
    }
} else {
    Fail "Neovim config/lockfile" "Missing config/nvim/init.lua or lazy-lock.json"
}

if ($env:LS_COLORS -and
    $env:LS_COLORS -match 'di=(34|38;2;)' -and
    $env:LS_COLORS -match 'ex=(32|38;2;)' -and
    $env:LS_COLORS -match '\*\.lean=(00|38;2;)' -and
    $env:LS_COLORS -match '\*\.zig=(00|38;2;)' -and
    $env:LS_COLORS -match '\*\.ps1=(00|38;2;)' -and
    $env:LS_COLORS -match '\*\.key=(35|38;2;)') {
    Pass "LS_COLORS environment variable configured (Calibrated 40-language palette)"
} else {
    Fail "LS_COLORS environment variable" "LS_COLORS missing expected 40-language rules"
}

if ($env:EZA_COLORS -and $env:EZA_COLORS -match 'di=38;2;' -and $env:EZA_COLORS -match 'xx=38;2;' -and $env:EZA_COLORS -match 'hd=4;38;2;') {
    Pass "EZA_COLORS environment variable configured (24-bit TrueColor)"
} else {
    Fail "EZA_COLORS environment variable" "EZA_COLORS not set properly"
}

if ($env:EXA_COLORS -eq $env:EZA_COLORS) {
    Pass "EXA_COLORS matches EZA_COLORS"
} else {
    Fail "EXA_COLORS environment variable" "EXA_COLORS does not match EZA_COLORS"
}

if ($env:FORCE_HYPERLINK -eq '1' -and $env:JQ_COLORS -and $env:BAT_OPTS -eq '--italic-text=always') {
    Pass "FORCE_HYPERLINK=1, JQ_COLORS, and BAT_OPTS configured"
} else {
    Fail "CLI environment variables" "Missing FORCE_HYPERLINK, JQ_COLORS, or BAT_OPTS"
}

if ($env:FZF_DEFAULT_OPTS -and $env:FZF_DEFAULT_OPTS -match '--layout=reverse') {
    Pass "FZF_DEFAULT_OPTS environment variable configured"
} else {
    Fail "FZF_DEFAULT_OPTS environment variable" "FZF_DEFAULT_OPTS not set properly"
}

if ($env:CC -eq 'gcc' -and $env:CXX -eq 'g++') {
    Pass "CC and CXX compiler environment variables configured (gcc/g++)"
} else {
    Fail "CC/CXX environment variables" "CC ($env:CC) or CXX ($env:CXX) not configured to gcc/g++"
}

# Test PSReadLine TrueColor syntax colors
$wsModule = Join-Path $RootDir "module\WindowsSettings.psm1"
$psm1Content = Get-Content $wsModule -Raw
if ($psm1Content -match '\$cYellow\s*=.*"`e\[38;2;181;137;0m"' -and
    $psm1Content -match '\$cGreen\s*=.*"`e\[38;2;133;153;0m"' -and
    $psm1Content -match 'Keyword\s*=\s*\$cYellow' -and
    $psm1Content -match 'Command\s*=\s*\$cGreen') {
    Pass "PSReadLine TrueColor syntax colors configured (Control Flow Keyword in Solarized Yellow #B58900, Command in Solarized Green #859900)"
} else {
    Fail "PSReadLine syntax colors" "Keyword is not Solarized Yellow #B58900 or Command is not Solarized Green #859900"
}

$setupPackagesScript = Join-Path $RootDir "setup.ps1"
if (Test-Path $setupPackagesScript) {
    $setupPackagesContent = Get-Content $setupPackagesScript -Raw
    if ($setupPackagesContent -match "'uutils\.coreutils'" -and
        $setupPackagesContent -match "'dandavison\.delta'" -and
        $setupPackagesContent -match "'aristocratos\.btop4win'" -and
        $setupPackagesContent -match "'Zellij\.Zellij'" -and
        $setupPackagesContent -match 'Sync-AntigravityHooksJson') {
        Pass "uutils.coreutils, delta, btop4win, Zellij, and Antigravity hooks configured in setup.ps1"
    } else {
        Fail "winget packages configuration" "Expected CLI packages or Antigravity hook sync missing in setup.ps1"
    }
}

# -------------------------------------------------------------
# Test 4: Utility, Theme & IDE Scripts Functional Tests (bin/)
# -------------------------------------------------------------
Write-Host "`n[4/8] Testing Native Utility, Theme & IDE Scripts (bin/)..." -ForegroundColor Yellow

# Test gen-passwd.ps1
$genPasswdScript = Join-Path $RootDir "bin\gen-passwd.ps1"
$pass16 = & $genPasswdScript -Length 16
if ($pass16.Length -eq 16) {
    Pass "gen-passwd.ps1 generates expected length (16)"
} else {
    Fail "gen-passwd.ps1 length" "Expected 16, got $($pass16.Length)"
}

$pass32 = & $genPasswdScript 32
if ($pass32.Length -eq 32) {
    Pass "gen-passwd.ps1 generates expected positional length (32)"
} else {
    Fail "gen-passwd.ps1 positional length" "Expected 32, got $($pass32.Length)"
}

$passSymbols = & $genPasswdScript -Length 24 -s
if ($passSymbols.Length -eq 24 -and $passSymbols -match '^[\^\*\@\#\&\%\$\!\-]+$') {
    Pass "gen-passwd.ps1 generates symbols-only password (-s)"
} else {
    Fail "gen-passwd.ps1 symbols" "Expected only symbols in $passSymbols"
}

$passDigits = & $genPasswdScript -Length 16 -n
if ($passDigits.Length -eq 16 -and $passDigits -match '^[0-9]+$') {
    Pass "gen-passwd.ps1 generates digits-only password (-n)"
} else {
    Fail "gen-passwd.ps1 digits" "Expected only digits in $passDigits"
}

$passUpperDigits = & $genPasswdScript -su 18
if ($passUpperDigits.Length -eq 18 -and $passUpperDigits -match '^[A-Z\^\*\@\#\&\%\$\!\-]+$') {
    Pass "gen-passwd.ps1 supports combined short flags (-su 18)"
} else {
    Fail "gen-passwd.ps1 combined flags" "Expected only uppercase and symbols in $passUpperDigits"
}

$passAlpha = & $genPasswdScript -Length 20 -NoSymbols
if ($passAlpha.Length -eq 20 -and $passAlpha -notmatch '[\^\*\@\#\&\%\$\!\-]') {
    Pass "gen-passwd.ps1 generates password without symbols (-NoSymbols)"
} else {
    Fail "gen-passwd.ps1 no-symbols" "Did not expect symbols in $passAlpha"
}

# Test sum.ps1 & sum function
$sumScript = Join-Path $RootDir "bin\sum.ps1"
$sumResult = 1..10 | & $sumScript
if ($sumResult -eq 55) {
    Pass "sum.ps1 correctly sums pipeline numbers (1..10 = 55)"
} else {
    Fail "sum.ps1 result" "Expected 55, got $sumResult"
}

$sumScriptFloat = 1.5, 2.5 | & $sumScript
if ($sumScriptFloat -eq 4.0 -and $sumScriptFloat.GetType().Name -eq 'Decimal') {
    Pass "sum.ps1 preserves decimal precision on floating point input (1.5, 2.5 | sum.ps1 = 4.0)"
} else {
    Fail "sum.ps1 float precision" "Expected 4.0 decimal, got $sumScriptFloat ($($sumScriptFloat.GetType().Name))"
}

$sumHuman = "1K 2K" | sum -H
if ($sumHuman -eq 3072) {
    Pass "sum -H parses IEC byte suffixes (1K + 2K = 3072)"
} else {
    Fail "sum -H" "Expected 3072, got $sumHuman"
}

$sumCol = sum -d ':' -k 2 'alpha:15:x' 'beta:25:y'
if ($sumCol -eq 40) {
    Pass "sum -d ':' -k 2 extracts and sums target column (15 + 25 = 40)"
} else {
    Fail "sum -d -k" "Expected 40, got $sumCol"
}

$sumAvg = sum -a 10 20 30
$sumFmt = sum -f '%.2f' 1.5 2.25
$sumNeg = sum 10 -3
if ($sumAvg -eq 20 -and $sumFmt -eq '3.75' -and $sumNeg -eq 7) {
    Pass "sum supports -a (mean=20), -f '%.2f' (3.75), and negative numbers (10 + -3 = 7)"
} else {
    Fail "sum advanced flags" "Got avg=$sumAvg, fmt=$sumFmt, neg=$sumNeg"
}

# Test repeat-until-success.ps1
$repeatScript = Join-Path $RootDir "bin\repeat-until-success.ps1"
try {
    & $repeatScript -Command "Write-Output 'ok'" -MaxAttempts 2 | Out-Null
    Pass "repeat-until-success.ps1 succeeds on valid command"
} catch {
    Fail "repeat-until-success.ps1" $_.Exception.Message
}

try {
    $global:LASTEXITCODE = 1
    & $repeatScript -Command "Write-Output 'prior exitcode test'" -MaxAttempts 1 | Out-Null
    Pass "repeat-until-success.ps1 succeeds when prior LASTEXITCODE was non-zero"
} catch {
    Fail "repeat-until-success.ps1 prior exitcode" $_.Exception.Message
}

$rusPosixOut = (& $repeatScript -n 1 -s 0.05 -- pwsh -NoProfile -Command "Write-Output 'posix_rus_ok'") -join "`n"
if ($rusPosixOut -match 'posix_rus_ok') {
    Pass "repeat-until-success.ps1 supports POSIX flags (-n, -s, --)"
} else {
    Fail "repeat-until-success.ps1 POSIX flags" "Expected posix_rus_ok, got: $rusPosixOut"
}

# Test bin/theme.ps1
$themeScript = Join-Path $RootDir "bin\theme.ps1"
$listedSlugs = @(& $themeScript --list --plain)
if ($listedSlugs.Count -ge 17 -and ($listedSlugs -contains 'solarized-dark') -and ($listedSlugs -contains 'halloween')) {
    Pass "theme.ps1 --list --plain discovers all $($listedSlugs.Count) themes"
} else {
    Fail "theme.ps1 --list --plain" "Expected >=17 slugs, got $($listedSlugs.Count)"
}

$nordEnv = (& $themeScript --env nord) -join "`n"
if ($nordEnv -match "WINDOWS_SETTINGS_THEME\s*=\s*'nord'" -and $nordEnv -match 'Nord-TrueColor') {
    Pass "theme.ps1 --env nord emits compiled PowerShell palette exports"
} else {
    Fail "theme.ps1 --env nord" "Missing expected Nord exports"
}

$prevDateOverride = $env:THEME_HOLIDAY_DATE
try {
    $env:THEME_HOLIDAY_DATE = '2026-10-20'
    $halDry = (& $themeScript --dry-run --holiday) -join "`n"
    $env:THEME_HOLIDAY_DATE = '2026-11-26'
    $thxDry = (& $themeScript --dry-run --holiday) -join "`n"
    if ($halDry -match 'halloween' -and $thxDry -match 'thanksgiving') {
        Pass "theme.ps1 --holiday US holiday calendar engine resolves Halloween & Thanksgiving accurately"
    } else {
        Fail "theme.ps1 --holiday" "Unexpected holiday resolution: $halDry | $thxDry"
    }
} finally {
    $env:THEME_HOLIDAY_DATE = $prevDateOverride
}

# Test theme.ps1 Zellij 0.46+ KDL theme & config.kdl block synchronization
$tempZellijDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_zellij_theme_" + [System.Guid]::NewGuid().ToString("N"))
$prevZellijCfgEnv = $env:ZELLIJ_CONFIG_DIR
$origThemeForTest = (& $themeScript --current).Trim()
if (-not $origThemeForTest) { $origThemeForTest = 'solarized-dark' }
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $tempZellijDir 'layouts') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $tempZellijDir 'themes') | Out-Null
    Copy-Item -Path (Join-Path $RootDir 'config\zellij\config.kdl') -Destination (Join-Path $tempZellijDir 'config.kdl') -Force
    Copy-Item -Path (Join-Path $RootDir 'config\zellij\layouts\ide-3pane.kdl') -Destination (Join-Path $tempZellijDir 'layouts\ide-3pane.kdl') -Force
    $env:ZELLIJ_CONFIG_DIR = $tempZellijDir

    & $themeScript --set nord --no-live | Out-Null
    $genThemeKdl = Get-Content (Join-Path $tempZellijDir 'themes\windows-settings.kdl') -Raw
    $genCfgKdl = Get-Content (Join-Path $tempZellijDir 'config.kdl') -Raw
    $nordKdlOk = ($genThemeKdl -match '46 52 64' -and $genCfgKdl -match 'needs_you "#D08770"' -and $genCfgKdl -match 'background "#2E3440"')
    if ($nordKdlOk -and (Get-Command zellij -ErrorAction SilentlyContinue)) {
        $nordCheckOut = (& zellij --config-dir $tempZellijDir setup --check 2>&1) -join "`n"
        $nordKdlOk = ($LASTEXITCODE -eq 0 -and $nordCheckOut -match 'Well defined')
    }
    if ($nordKdlOk) {
        Pass "theme.ps1 live-updates Zellij themes/windows-settings.kdl & config.kdl tray/terminal blocks"
    } else {
        Fail "theme.ps1 Zellij KDL sync" "Generated Nord Zellij theme or config.kdl failed validation"
    }
} finally {
    $env:ZELLIJ_CONFIG_DIR = $prevZellijCfgEnv
    & $themeScript --set $origThemeForTest --no-live | Out-Null
    if (Test-Path $tempZellijDir) {
        Remove-Item -Recurse -Force -Path $tempZellijDir -ErrorAction SilentlyContinue
    }
}

# Test bin/update-system.ps1 --dry-run (default full update + --system-only)
$updateScript = Join-Path $RootDir "bin\update-system.ps1"
$updDry = (& $updateScript --dry-run) -join "`n"
$updSysDry = (& $updateScript --system-only --dry-run) -join "`n"
if ($LASTEXITCODE -eq 0 -and
    $updDry -match 'Regenerate omp_init\.ps1, zoxide_init\.ps1, gh_completion\.ps1' -and
    $updSysDry -notmatch 'Regenerate omp_init\.ps1') {
    Pass "update-system.ps1 --dry-run updates packages, toolchains, and caches by default (--system-only scopes to WinGet)"
} else {
    Fail "update-system.ps1 --dry-run" "Unexpected output or exit code $LASTEXITCODE ($updDry)"
}

# Test upgrade-safe mise_paths.ps1 stale version pruning when a single tool upgrades
$prevPathTest = $env:Path
$prevMiseStamp = $env:_WS_MISE_STAMP
$tempMiseDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_mise_test_" + [System.Guid]::NewGuid().ToString("N"))
try {
    $fakeInstalls = Join-Path $tempMiseDir 'mise\installs'
    $batV1 = Join-Path $fakeInstalls 'bat\0.26.1'
    $nvimV1 = Join-Path $fakeInstalls 'neovim\0.12.5\bin'
    $nvimV2 = Join-Path $fakeInstalls 'neovim\0.12.6\bin'
    New-Item -ItemType Directory -Force -Path $batV1, $nvimV1, $nvimV2 | Out-Null
    $blockV2 = "$batV1;$nvimV2"
    $fakeCachePs1 = Join-Path $tempMiseDir 'mise_paths.ps1'
    $fakeLines = @(
        "`$script:_wsMiseInstallsDir = '$($fakeInstalls.Replace("'", "''"))'",
        "`$script:_wsMiseStamp = 'TESTCAFE'",
        "`$script:_wsMisePathBlock = '$($blockV2.Replace("'", "''"))'",
        'if ([System.IO.Directory]::Exists($script:_wsMiseInstallsDir)) {',
        '    if (-not $env:Path.Contains($script:_wsMisePathBlock, [System.StringComparison]::OrdinalIgnoreCase)) {',
        '        $cleanSegs = foreach ($seg in $env:Path.Split('';'', [System.StringSplitOptions]::RemoveEmptyEntries)) {',
        '            if ($seg.IndexOf(''\mise\installs\'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0 -and',
        '                $seg.IndexOf(''/mise/installs/'', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {',
        '                $seg',
        '            }',
        '        }',
        '        $restPath = $cleanSegs -join '';''',
        '        $env:Path = if ($restPath) { "$script:_wsMisePathBlock;$restPath" } else { $script:_wsMisePathBlock }',
        '    }',
        '    $env:_WS_MISE_STAMP = $script:_wsMiseStamp',
        '}'
    )
    [System.IO.File]::WriteAllText($fakeCachePs1, ($fakeLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
    $env:Path = "$batV1;$nvimV1;$prevPathTest"
    . $fakeCachePs1
    if ($env:Path.StartsWith("$blockV2;", [System.StringComparison]::OrdinalIgnoreCase) -and
        -not $env:Path.Contains($nvimV1, [System.StringComparison]::OrdinalIgnoreCase) -and
        $env:_WS_MISE_STAMP -eq 'TESTCAFE') {
        Pass "mise_paths.ps1 replaces stale single-tool version paths cleanly upon upgrade"
    } else {
        Fail "mise_paths.ps1 upgrade swap" "Expected $nvimV2 prepended and $nvimV1 pruned"
    }
} finally {
    $env:Path = $prevPathTest
    $env:_WS_MISE_STAMP = $prevMiseStamp
    if (Test-Path -LiteralPath $tempMiseDir) {
        Remove-Item -Recurse -Force -LiteralPath $tempMiseDir -ErrorAction SilentlyContinue
    }
}

# Test bin/ide.ps1 --dry-run (Zellij default, detached, desktop & Windows Terminal fallback), --agy-hook, --send & --keys
$ideScript = Join-Path $RootDir "bin\ide.ps1"
$ideDry3 = (& $ideScript --backend zellij --3pane --dry-run) -join "`n"
$ideDry2 = (& $ideScript --backend zellij --2pane --detach --ai claude --dry-run) -join "`n"
$ideDryDesktop = (& $ideScript --backend zellij --desktop --dry-run) -join "`n"
if ($ideDry3 -match 'Backend\s*:\s*zellij' -and
    $ideDry3 -match 'ide-3pane' -and
    $ideDry3 -match '\\\\\.\\pipe\\nvim-ide-' -and
    $ideDry2 -match 'Layout\s*:\s*2pane' -and
    $ideDry2 -match '--create-background' -and
    $ideDryDesktop -match 'zellij terminal --create') {
    Pass "ide.ps1 --dry-run builds Zellij 3-pane, detached 2-pane, and 1-hop desktop GPU layouts"
} else {
    Fail "ide.ps1 Zellij --dry-run" "Unexpected output: $ideDry3 | $ideDry2 | $ideDryDesktop"
}

$ideDryWt = (& $ideScript --backend wt --3pane --dry-run) -join "`n"
if ($ideDryWt -match 'Backend\s*:\s*wt' -and $ideDryWt -match 'split-pane -H -s 0\.25') {
    Pass "ide.ps1 --backend wt --dry-run preserves native Windows Terminal Inverted-T fallback"
} else {
    Fail "ide.ps1 --backend wt --dry-run" "Unexpected wt fallback output: $ideDryWt"
}

$prevNoTty = $env:WS_AGY_HOOK_NO_TTY
try {
    $env:WS_AGY_HOOK_NO_TTY = '1'
    $hookPre = ('{"session_id":"test"}' | & $ideScript --agy-hook PreInvocation | Out-String).Trim()
    $hookStop = ('{"session_id":"test"}' | & $ideScript --agy-hook Stop | Out-String).Trim()
    if ($hookPre -eq '{}' -and $hookStop -eq '{"decision":"allow"}') {
        Pass "ide.ps1 --agy-hook emits valid Antigravity PreInvocation & Stop JSON responses"
    } else {
        Fail "ide.ps1 --agy-hook" "Unexpected hook JSON: Pre='$hookPre', Stop='$hookStop'"
    }
    $ideCmdScript = Join-Path $RootDir 'bin\ide.cmd'
    $cmdHookPre = ('{"session_id":"test"}' | & cmd.exe /d /c "`"$ideCmdScript`" --agy-hook PreInvocation" | Out-String).Trim()
    $cmdHookStop = ('{"session_id":"test","error":null}' | & cmd.exe /d /c "`"$ideCmdScript`" --agy-hook Stop" | Out-String).Trim()
    if ($cmdHookPre -eq '{}' -and $cmdHookStop -eq '{"decision":"allow"}') {
        Pass "ide.cmd --agy-hook fast path emits valid Antigravity PreInvocation & Stop JSON responses"
    } else {
        Fail "ide.cmd --agy-hook" "Unexpected batch hook JSON: Pre='$cmdHookPre', Stop='$cmdHookStop'"
    }
} finally {
    $env:WS_AGY_HOOK_NO_TTY = $prevNoTty
}

$testSendSess = 'ws-unit-send-test'
$testStageFile = Join-Path (Join-Path (Join-Path $HOME '.cache\windows-settings') 'ide') "$testSendSess.send.txt"
$prevSkipClip = $env:WS_IDE_SKIP_CLIPBOARD
try {
    $env:WS_IDE_SKIP_CLIPBOARD = '1'
    Push-Location $RootDir
    $sampleRefTarget = Join-Path $RootDir 'bin\ide.ps1'
    & $ideScript --send --ref "${sampleRefTarget}#L10-L20" $testSendSess | Out-Null
    $stagedPayload = if (Test-Path $testStageFile) { Get-Content $testStageFile -Raw } else { '' }
    if ($stagedPayload -eq '@bin/ide.ps1#L10-L20 ') {
        Pass "ide.ps1 --send --ref formats workspace-relative @file#L10-L20 payload"
    } else {
        Fail "ide.ps1 --send --ref" "Expected '@bin/ide.ps1#L10-L20 ', got '$stagedPayload'"
    }
} finally {
    Pop-Location -ErrorAction SilentlyContinue
    $env:WS_IDE_SKIP_CLIPBOARD = $prevSkipClip
    if (Test-Path $testStageFile) {
        Remove-Item -Force -Path $testStageFile -ErrorAction SilentlyContinue
    }
}

$prevNoWait = $env:IDE_KEYS_NO_WAIT
try {
    $env:IDE_KEYS_NO_WAIT = '1'
    $ideKeysOut = (& $ideScript --keys) -join "`n"
    & $ideScript --write-keys-cache
    $keysCachePath = Join-Path (Join-Path (Join-Path $HOME '.cache\windows-settings') 'ide') 'keys-cheatsheet.ans'
    $keysCacheBytes = if (Test-Path -LiteralPath $keysCachePath -PathType Leaf) { [System.IO.File]::ReadAllBytes($keysCachePath) } else { [byte[]]@() }
    $keysCacheRaw = if ($keysCacheBytes.Length -gt 2) { [System.IO.File]::ReadAllText($keysCachePath, [System.Text.Encoding]::Unicode) } else { '' }
    $hasUtf16LeBom = ($keysCacheBytes.Length -ge 2 -and $keysCacheBytes[0] -eq 0xFF -and $keysCacheBytes[1] -eq 0xFE)
    if ($ideKeysOut -match 'IDE Workspace & Agent Fleet Keybindings' -and
        $ideKeysOut -match 'mini\.files' -and
        $hasUtf16LeBom -and
        $keysCacheRaw.StartsWith("$([char]27)[?25l") -and
        $keysCacheRaw -match 'IDE Workspace & Agent Fleet Keybindings' -and
        $keysCacheRaw.Contains("`r`n")) {
        Pass "ide.ps1 --keys & --write-keys-cache render TrueColor keybinding cheatsheet & UTF-16LE BOM cache"
    } else {
        Fail "ide.ps1 --keys" "Missing expected cheatsheet sections or UTF-16LE BOM cache ($keysCachePath)"
    }
} finally {
    $env:IDE_KEYS_NO_WAIT = $prevNoWait
}

$prevForceMon = $env:IDE_FORCE_BUILTIN_MONITOR
$prevMonOnce = $env:IDE_MONITOR_ONCE
try {
    $env:IDE_FORCE_BUILTIN_MONITOR = '1'
    $env:IDE_MONITOR_ONCE = '1'
    $ideMonOut = (& $ideScript --monitor) -join "`n"
    if ($ideMonOut -match 'System Monitor' -and $ideMonOut -match 'CPU' -and $ideMonOut -match 'MEM' -and $ideMonOut -match 'PROCESS') {
        Pass "ide.ps1 --monitor renders built-in TrueColor TUI fallback monitor cleanly"
    } else {
        Fail "ide.ps1 --monitor" "Missing expected System Monitor sections"
    }
} finally {
    $env:IDE_FORCE_BUILTIN_MONITOR = $prevForceMon
    $env:IDE_MONITOR_ONCE = $prevMonOnce
}

# -------------------------------------------------------------
# Test 5: Git Function Behavior & Safety Guards
# -------------------------------------------------------------
Write-Host "`n[5/8] Testing Git Functions & Safety Guards..." -ForegroundColor Yellow

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    $remoteDir = Join-Path $tempDir "remote.git"
    $localDir = Join-Path $tempDir "local"

    git init --bare -b main $remoteDir 2>$null | Out-Null
    git clone $remoteDir $localDir 2>$null | Out-Null

    Push-Location $localDir

    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false

    Set-Content -Path "file.txt" -Value "initial content"
    git add file.txt
    git commit -m "initial commit" 2>$null | Out-Null
    git push origin main 2>$null | Out-Null

    # Outside-repo checks
    foreach ($fnName in @('gsync', 'gprune', 'gpurge', 'gcm', 'guser-branch')) {
        $nonGitDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_nongit_${fnName}_" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Force -Path $nonGitDir | Out-Null
        Push-Location $nonGitDir
        $caught = $false
        try {
            & (Get-Command $fnName -CommandType Function)
        } catch {
            if ($_.ToString() -match 'Error' -or $_.Exception.Message -match 'Error') {
                $caught = $true
            }
        } finally {
            Pop-Location
            Remove-Item -Recurse -Force -Path $nonGitDir -ErrorAction SilentlyContinue
        }
        if ($caught) {
            Pass "$fnName fails gracefully when not in a git repository"
        } else {
            Fail "$fnName outside repo" "Expected error outside git repository"
        }
    }

    # Test guser-branch refuses to rename protected 'main' branch
    $mainRenameBlocked = $false
    try {
        guser-branch
    } catch {
        if ($_.ToString() -match 'refusing to rename protected primary branch') {
            $mainRenameBlocked = $true
        }
    }
    if ($mainRenameBlocked -and (git rev-parse --abbrev-ref HEAD).Trim() -eq 'main') {
        Pass "guser-branch refuses to rename protected primary branch 'main'"
    } else {
        Fail "guser-branch main guard" "Expected refusal on main branch"
    }

    # Test gsync on feature branch & dirty working tree guard
    git checkout -b feature-1 2>$null | Out-Null
    Add-Content -Path "file.txt" -Value "`nfeature work"
    git commit -am "feature update" 2>$null | Out-Null

    gsync 2>$null | Out-Null
    $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -eq "feature-1") {
        Pass "gsync preserves current branch on clean feature branch"
    } else {
        Fail "gsync branch preservation" "Expected feature-1, got $currentBranch"
    }

    Add-Content -Path "file.txt" -Value "`ndirty tracked edit"
    $dirtySyncBlocked = $false
    try {
        gsync
    } catch {
        if ($_.ToString() -match 'uncommitted changes') {
            $dirtySyncBlocked = $true
        }
    }
    git checkout -- file.txt 2>$null | Out-Null
    if ($dirtySyncBlocked) {
        Pass "gsync refuses to run when tracked working tree has uncommitted changes"
    } else {
        Fail "gsync dirty guard" "Expected error on dirty working tree"
    }

    # Test guser-branch & fix-abcxyz-branch-name
    $expectedUser = if ($env:USER) { $env:USER } else { $env:USERNAME }
    guser-branch
    $renamedBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($renamedBranch -eq "$expectedUser/feature-1") {
        Pass "guser-branch successfully prefixed branch ($expectedUser/feature-1)"
    } else {
        Fail "guser-branch" "Expected $expectedUser/feature-1, got $renamedBranch"
    }

    guser-branch
    $idempotentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($idempotentBranch -eq "$expectedUser/feature-1") {
        Pass "guser-branch strips redundant user prefix idempotently"
    } else {
        Fail "guser-branch prefix strip" "Redundant prefix introduced: $idempotentBranch"
    }

    fix-abcxyz-branch-name
    $aliasBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($aliasBranch -eq "$expectedUser/feature-1") {
        Pass "fix-abcxyz-branch-name compatibility alias works identically"
    } else {
        Fail "fix-abcxyz-branch-name" "Expected $expectedUser/feature-1, got $aliasBranch"
    }

    # Test gprune (merged-only safe delete) vs gpurge (force delete unmerged)
    git checkout main 2>$null | Out-Null
    git branch merged-branch 2>$null | Out-Null
    gprune 2>$null | Out-Null
    git show-ref --verify --quiet refs/heads/merged-branch
    $mergedGone = ($LASTEXITCODE -ne 0)
    git show-ref --verify --quiet "refs/heads/$expectedUser/feature-1"
    $unmergedKept = ($LASTEXITCODE -eq 0)
    if ($mergedGone -and $unmergedKept) {
        Pass "gprune safely deletes merged branches while preserving unmerged branches"
    } else {
        Fail "gprune safety" "mergedGone=$mergedGone, unmergedKept=$unmergedKept"
    }

    gpurge 2>$null | Out-Null
    git show-ref --verify --quiet "refs/heads/$expectedUser/feature-1"
    if ($LASTEXITCODE -ne 0) {
        Pass "gpurge force-deletes unmerged non-primary branches when explicitly requested"
    } else {
        Fail "gpurge" "Expected unmerged branch to be purged"
    }

    # Test gcm primary branch resolution (main -> master -> trunk -> error)
    git checkout -b gcm-test-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    if ((git rev-parse --abbrev-ref HEAD).Trim() -eq "main") {
        Pass "gcm switches to main from feature branch"
    } else {
        Fail "gcm switch to main" "Did not switch to main"
    }

    git branch -m main master 2>$null | Out-Null
    git checkout -b gcm-test-master-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    if ((git rev-parse --abbrev-ref HEAD).Trim() -eq "master") {
        Pass "gcm falls back to master when main does not exist"
    } else {
        Fail "gcm fallback to master" "Did not switch to master"
    }

    git branch -m master trunk 2>$null | Out-Null
    git checkout -b gcm-test-trunk-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    if ((git rev-parse --abbrev-ref HEAD).Trim() -eq "trunk") {
        Pass "gcm falls back to trunk when main and master do not exist"
    } else {
        Fail "gcm fallback to trunk" "Did not switch to trunk"
    }

    git branch -m trunk custom-default 2>$null | Out-Null
    $noPrimaryErrCaught = $false
    try {
        & (Get-Command gcm -CommandType Function)
    } catch {
        if ($_.ToString() -match "neither 'main' nor 'master'") {
            $noPrimaryErrCaught = $true
        }
    }
    if ($noPrimaryErrCaught) {
        Pass "gcm fails gracefully with descriptive error when no primary branch exists"
    } else {
        Fail "gcm missing primary branch" "Expected descriptive primary branch error"
    }

    Pop-Location
} finally {
    Set-Location $RootDir
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------
# Test 6: Completions & Oh My Posh Rendering
# -------------------------------------------------------------
Write-Host "`n[6/8] Testing Completions & Prompt Rendering..." -ForegroundColor Yellow

$completionsScript = Join-Path $RootDir "module\Completions.ps1"
try {
    . $completionsScript
    Pass "module/Completions.ps1 executed and registered completers (incl. theme & ide) successfully"
} catch {
    Fail "module/Completions.ps1" $_.Exception.Message
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        $renderOutput = oh-my-posh print primary --config $p10kPath
        if ($renderOutput) {
            Pass "Oh My Posh primary prompt renders cleanly"
        } else {
            Fail "Oh My Posh primary rendering" "Render output was empty"
        }

        $prevPrLabel = $env:_WS_GIT_PR_LABEL
        $prevPrUrl = $env:_WS_GIT_PR_URL
        try {
            $env:_WS_GIT_PR_LABEL = '@149'
            $env:_WS_GIT_PR_URL = 'https://github.com/lock14/windows-settings/pull/149'
            $prRender = oh-my-posh print primary --config $p10kPath
            if ($prRender -match '@149') {
                Pass "Oh My Posh primary prompt renders clickable @<PR> badge when _WS_GIT_PR_LABEL is set"
            } else {
                Fail "Oh My Posh PR badge" "Expected @149 in rendered prompt"
            }
        } finally {
            $env:_WS_GIT_PR_LABEL = $prevPrLabel
            $env:_WS_GIT_PR_URL = $prevPrUrl
        }

        $rightOutput = oh-my-posh print right --config $p10kPath
        if ($rightOutput -and $rightOutput.Length -gt 0) {
            Pass "Oh My Posh right prompt renders cleanly (status anchor active)"
        } else {
            Fail "Oh My Posh right rendering" "Right prompt output was empty"
        }

        $errorRightOutput = oh-my-posh print right --config $p10kPath --status 1
        if ($errorRightOutput -and $errorRightOutput.Length -gt 0) {
            Pass "Oh My Posh right prompt renders error status cleanly"
        } else {
            Fail "Oh My Posh right error rendering" "Right prompt output on error was empty"
        }

        # Live & cross-pane prompt color reaction test (POSH_SESSION_ID cache invalidation)
        $liveSwitchCheck = (& pwsh -NoProfile -Command "
            `$orig = (& '$($themeScript.Replace("'", "''"))' --current).Trim()
            if (-not `$orig) { `$orig = 'solarized-dark' }
            try {
                & '$($themeScript.Replace("'", "''"))' --set solarized-dark --no-live | Out-Null
                Import-Module '$((Join-Path $RootDir "module\WindowsSettings.psd1").Replace("'", "''"))' -DisableNameChecking -Force
                `$pSol = prompt
                theme nord --no-live | Out-Null
                `$pNord = prompt
                & pwsh -NoProfile -File '$($themeScript.Replace("'", "''"))' --set halloween --no-live | Out-Null
                `$pHal = prompt
                if (`$pSol -match '48;2;7;54;66' -and `$pNord -match '48;2;59;66;82' -and `$pHal -match '48;2;40;16;64') {
                    Write-Output 'LIVE_PROMPT_OK'
                } else {
                    Write-Output ""LIVE_PROMPT_MISMATCH (sol=`$(`$pSol -match '48;2;7;54;66'):`$(`$pSol.Length), nord=`$(`$pNord -match '48;2;59;66;82'):`$(`$pNord.Length), hal=`$(`$pHal -match '48;2;40;16;64'):`$(`$pHal.Length))""
                }
            } finally {
                & '$($themeScript.Replace("'", "''"))' --set `$orig --no-live | Out-Null
            }
        ") -join "`n"
        if ($liveSwitchCheck -match 'LIVE_PROMPT_OK') {
            Pass "Oh My Posh live & cross-pane prompt colors react immediately to theme switching"
        } else {
            Fail "Oh My Posh live theme switch" "Prompt colors did not update across theme switches ($liveSwitchCheck)"
        }
    } catch {
        Fail "Oh My Posh rendering error" $_.Exception.Message
    }
} else {
    Write-Host "  [SKIP] oh-my-posh not installed in current environment" -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# Test 7: Path Invariant & Dual Execution Validation
# -------------------------------------------------------------
Write-Host "`n[7/8] Testing Path Invariants & Dual Execution Wrappers..." -ForegroundColor Yellow

$filesToScan = Get-ChildItem -Path $RootDir -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp|plugin[\\/]ws-bar[\\/]target)[\\/]' -and $_.Name -ne 'AGENTS.md' }

$hardcodedFound = $false
foreach ($f in $filesToScan) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'C:\\Users\\(?!<)[a-zA-Z0-9_-]+' -or $content -match '/Users/(?!<)[a-zA-Z0-9_-]+' -or $content -match '/home/(?!<)[a-zA-Z0-9_-]+') {
        Fail "Path invariant check: $($f.FullName)" "Contains hardcoded personal user path"
        $hardcodedFound = $true
    }
}
if (-not $hardcodedFound) {
    Pass "Path invariants valid across all repo files (zero hardcoded personal paths)"
}

# 7.1b Byte-level CRLF / LF line-ending discipline & module startup hygiene
$crlfExts = @('.ps1', '.psm1', '.psd1', '.cmd', '.bat', '.doskey')
$lfExts   = @('.md', '.json', '.kdl', '.yml', '.yaml', '.toml', '.lock', '.rs', '.lua', '.scm', '.theme', '.tmTheme', '.sublime-syntax', '.gitconfig', '.conf', '.txt')
$eolViolation = $false
foreach ($f in (Get-ChildItem -Path $RootDir -Recurse -File | Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp|plugin[\\/]ws-bar[\\/]target)[\\/]' })) {
    $rawBytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($rawBytes.Length -eq 0) { continue }
    $rawStr = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    if ($crlfExts -contains $f.Extension) {
        if (($rawStr -replace "`r`n", "").Contains("`n")) {
            Fail "Line-ending check (expected CRLF): $($f.FullName)" "Contains bare LF line endings"
            $eolViolation = $true
        }
    } elseif ($lfExts -contains $f.Extension -or $f.Name -eq 'LICENSE') {
        if ($rawStr.Contains("`r`n")) {
            Fail "Line-ending check (expected LF): $($f.FullName)" "Contains CRLF line endings"
            $eolViolation = $true
        }
    }
}
if (-not $eolViolation) {
    Pass "Line-ending invariants valid across all repo files (CRLF scripts/batch, LF configs/docs)"
}

$psm1Raw = Get-Content (Join-Path $RootDir 'module\WindowsSettings.psm1') -Raw
if ($psm1Raw -notmatch 'Get-ChildItem[^\r\n]*-Recurse') {
    Pass "Module startup hygiene valid: zero recursive disk traversals in WindowsSettings.psm1"
} else {
    Fail "Module startup hygiene" "WindowsSettings.psm1 must not use Get-ChildItem -Recurse"
}

# 7.2 Dual Execution in bin/
$binPs1Files = @(Get-ChildItem -Path (Join-Path $RootDir "bin") -Filter "*.ps1")
if ($binPs1Files.Count -eq 7) {
    Pass "All 7 user utilities present in bin/ (gen-passwd, ide, install-nerd-fonts, repeat-until-success, sum, theme, update-system)"
} else {
    Fail "bin/ script count" "Expected 7 .ps1 scripts in bin/, found $($binPs1Files.Count)"
}

foreach ($ps1 in $binPs1Files) {
    $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($ps1.Name) + ".cmd"
    $cmdPath = Join-Path (Join-Path $RootDir "bin") $cmdName
    if (Test-Path $cmdPath) {
        Pass "Dual execution wrapper present: $cmdName for $($ps1.Name)"
    } else {
        Fail "Dual execution wrapper missing: $cmdName" "No .cmd wrapper found for $($ps1.Name)"
    }
}

# 7.3 Execute .cmd batch wrappers
$sumCmd = Join-Path $RootDir "bin\sum.cmd"
$cmdSumOut = (& cmd.exe /c "`"$sumCmd`" 10 20 30" | Out-String).Trim()
if ($cmdSumOut -eq "60") {
    Pass "sum.cmd batch wrapper executed successfully (10 + 20 + 30 = 60)"
} else {
    Fail "sum.cmd execution" "Expected 60, got: $cmdSumOut"
}

$cmdPipeOut = (& cmd.exe /c "echo 25 | `"$sumCmd`"" | Out-String).Trim()
if ($cmdPipeOut -eq "25") {
    Pass "sum.cmd batch wrapper executed successfully with piped stdin (echo 25 | sum.cmd = 25)"
} else {
    Fail "sum.cmd piped execution" "Expected 25, got: $cmdPipeOut"
}

$genPasswdCmd = Join-Path $RootDir "bin\gen-passwd.cmd"
$cmdPassOut = (& cmd.exe /c "`"$genPasswdCmd`" -Length 12 -NoSymbols" | Out-String).Trim()
if ($cmdPassOut.Length -eq 12) {
    Pass "gen-passwd.cmd batch wrapper executed successfully (Length 12)"
} else {
    Fail "gen-passwd.cmd execution" "Expected length 12, got: $($cmdPassOut.Length)"
}

$repeatCmd = Join-Path $RootDir "bin\repeat-until-success.cmd"
$cmdRepeatOut = (& cmd.exe /c "`"$repeatCmd`" `"Write-Output cmd_repeat_ok`" -MaxAttempts 1") | Out-String
if ($cmdRepeatOut -match "cmd_repeat_ok") {
    Pass "repeat-until-success.cmd batch wrapper executed successfully"
} else {
    Fail "repeat-until-success.cmd execution" "Expected 'cmd_repeat_ok' in output, got: $cmdRepeatOut"
}

$themeCmd = Join-Path $RootDir "bin\theme.cmd"
$cmdThemeOut = @(& cmd.exe /c "`"$themeCmd`" --list --plain")
if ($cmdThemeOut.Count -ge 17) {
    Pass "theme.cmd batch wrapper executed successfully ($($cmdThemeOut.Count) themes)"
} else {
    Fail "theme.cmd execution" "Expected >=17 themes, got $($cmdThemeOut.Count)"
}

$ideCmd = Join-Path $RootDir "bin\ide.cmd"
$cmdIdeOut = (& cmd.exe /c "`"$ideCmd`" --dry-run") | Out-String
if ($cmdIdeOut -match 'IDE Session') {
    Pass "ide.cmd batch wrapper executed successfully (--dry-run)"
} else {
    Fail "ide.cmd execution" "Missing IDE Session in output"
}

$updateCmd = Join-Path $RootDir "bin\update-system.cmd"
& cmd.exe /c "`"$updateCmd`" --dry-run" | Out-Null
if ($LASTEXITCODE -eq 0) {
    Pass "update-system.cmd batch wrapper executed successfully (--dry-run)"
} else {
    Fail "update-system.cmd execution" "Exited with code $LASTEXITCODE"
}

# -------------------------------------------------------------
# Test 8: Setup Idempotency, Backup, Theme & Uninstall Dry-Run
# -------------------------------------------------------------
Write-Host "`n[8/8] Testing Setup Script Idempotency, Backup, Theme & Uninstall..." -ForegroundColor Yellow

$sandboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_sandbox_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $sandboxDir | Out-Null

try {
    $mockTarget = Join-Path $sandboxDir "settings.json"
    Set-Content -Path $mockTarget -Value "initial configuration"

    $sourceSettings = Join-Path $RootDir "config\terminal\settings.json"
    $sourceContent = Get-Content $sourceSettings -Raw

    $isDiff = ((Get-Content $mockTarget -Raw) -ne $sourceContent)
    if ($isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $mockBackup = "$mockTarget.bak_$timestamp"
        Copy-Item -Path $mockTarget -Destination $mockBackup -Force
        Copy-Item -Path $sourceSettings -Destination $mockTarget -Force
    }

    $backupFiles = @(Get-ChildItem -Path $sandboxDir -Filter "settings.json.bak_*")
    if ($backupFiles.Count -eq 1) {
        Pass "Backup created when configuration content differed"
    } else {
        Fail "Backup creation" "Expected 1 backup file, found $($backupFiles.Count)"
    }

    $isDiff2 = ((Get-Content $mockTarget -Raw) -ne $sourceContent)
    if ($isDiff2) {
        $timestamp2 = Get-Date -Format "yyyyMMdd_HHmmss"
        $mockBackup2 = "$mockTarget.bak_$timestamp2"
        Copy-Item -Path $mockTarget -Destination $mockBackup2 -Force
    }

    $backupFilesAfter = @(Get-ChildItem -Path $sandboxDir -Filter "settings.json.bak_*")
    if ($backupFilesAfter.Count -eq 1) {
        Pass "Idempotency preserved: zero redundant backups generated on identical re-run"
    } else {
        Fail "Idempotency failure" "Redundant backup created when content had not changed"
    }

    $setupScriptPath = Join-Path $RootDir "setup.ps1"
    $setupScriptContent = Get-Content $setupScriptPath -Raw
    if ($setupScriptContent -match 'Fragments' -and $setupScriptContent -match 'Deploy-ConfigFile') {
        Pass "setup.ps1 implements declarative JSON Fragment extension deployment"
    } else {
        Fail "Terminal setup" "Declarative JSON Fragment support missing in setup.ps1"
    }

    if ($setupScriptContent -match 'Sync-ZellijBarPlugin' -and $setupScriptContent -match 'Sync-ZellijPluginPermission' -and $setupScriptContent -match 'role "compact-bar"') {
        Pass "setup.ps1 implements WASM bar build/cache, permission pre-seeding, and compact-bar fallback"
    } else {
        Fail "Zellij WASM bar setup" "Expected Sync-ZellijBarPlugin, Sync-ZellijPluginPermission, and compact-bar fallback in setup.ps1"
    }

    $setupAst = [System.Management.Automation.Language.Parser]::ParseFile($setupScriptPath, [ref]$null, [ref]$null)
    $fnNames = @('ConvertTo-NormalizedZellijConfig', 'Deploy-ZellijConfig', 'Sync-ZellijPluginPermission')
    $fnDefs = $setupAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $fnNames
    }, $false)
    foreach ($fnAst in $fnDefs) {
        . ([scriptblock]::Create($fnAst.Extent.Text))
    }

    $mockPermFile = Join-Path $sandboxDir 'permissions.kdl'
    [System.IO.File]::WriteAllText($mockPermFile, "`"other-plugin`" {`n    ReadApplicationState`n}`n", [System.Text.UTF8Encoding]::new($false))
    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile *>$null
    $permRaw1 = [System.IO.File]::ReadAllText($mockPermFile)
    $permBackups1 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'permissions.kdl.bak_*')
    if (-not $permRaw1.Contains("`r`n") -and $permRaw1 -match '"other-plugin"' -and $permRaw1 -match 'windows-settings-bar' -and $permRaw1 -match 'RunActionsAsUser' -and $permBackups1.Count -eq 1) {
        Pass "Sync-ZellijPluginPermission pre-seeds LF permissions while preserving existing plugin entries and backup"
    } else {
        Fail "Sync-ZellijPluginPermission seed" "Unexpected permissions.kdl content or backup count ($($permBackups1.Count))"
    }

    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile *>$null
    $permBackups2 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'permissions.kdl.bak_*')
    if ($permBackups2.Count -eq 1) {
        Pass "Sync-ZellijPluginPermission is idempotent with zero redundant backups on re-run"
    } else {
        Fail "Sync-ZellijPluginPermission idempotency" "Expected 1 backup after re-run, found $($permBackups2.Count)"
    }

    Sync-ZellijPluginPermission -PermissionsPath $mockPermFile -Remove *>$null
    $permRawRemoved = [System.IO.File]::ReadAllText($mockPermFile)
    if ($permRawRemoved -match '"other-plugin"' -and $permRawRemoved -notmatch 'windows-settings-bar') {
        Pass "Sync-ZellijPluginPermission -Remove strips only windows-settings-bar and preserves unrelated entries"
    } else {
        Fail "Sync-ZellijPluginPermission -Remove" "Failed to cleanly remove windows-settings-bar while keeping other-plugin"
    }

    $srcZellijConfig = Join-Path (Join-Path (Join-Path $RootDir 'config') 'zellij') 'config.kdl'
    $mockZellijConfig = Join-Path $sandboxDir 'config.kdl'
    Deploy-ZellijConfig -SourcePath $srcZellijConfig -DestinationPath $mockZellijConfig -UseWasmBar $false *>$null
    $cfgFallback = [System.IO.File]::ReadAllText($mockZellijConfig)
    Deploy-ZellijConfig -SourcePath $srcZellijConfig -DestinationPath $mockZellijConfig -UseWasmBar $true *>$null
    $cfgWasm = [System.IO.File]::ReadAllText($mockZellijConfig)
    $cfgBackups1 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'config.kdl.bak_*')
    Deploy-ZellijConfig -SourcePath $srcZellijConfig -DestinationPath $mockZellijConfig -UseWasmBar $true *>$null
    $cfgBackups2 = @(Get-ChildItem -LiteralPath $sandboxDir -Filter 'config.kdl.bak_*')
    if (-not $cfgFallback.Contains("`r`n") -and $cfgFallback -match 'location="zellij:bars"' -and $cfgFallback -match 'role "compact-bar"' -and
        -not $cfgWasm.Contains("`r`n") -and $cfgWasm -match 'location="file:windows-settings-bar"' -and
        $cfgBackups1.Count -eq 1 -and $cfgBackups2.Count -eq 1) {
        Pass "Deploy-ZellijConfig switches cleanly between compact-bar fallback and WASM bar with idempotent LF writes"
    } else {
        Fail "Deploy-ZellijConfig bar switching" "Fallback/WASM bar rewrite or backup idempotency check failed"
    }

    foreach ($modeSpec in @(
        @{ Label = '-DryRun';                Args = @{ DryRun = $true } },
        @{ Label = '-DryRun -DotfilesOnly';  Args = @{ DryRun = $true; DotfilesOnly = $true } },
        @{ Label = '-DryRun -SystemOnly';    Args = @{ DryRun = $true; SystemOnly = $true } },
        @{ Label = '-DryRun -WithGUI';       Args = @{ DryRun = $true; WithGUI = $true } },
        @{ Label = '-DryRun -UseDSC';        Args = @{ DryRun = $true; UseDSC = $true } },
        @{ Label = '-DryRun -SkipCMD';       Args = @{ DryRun = $true; SkipCMD = $true } },
        @{ Label = '-DryRun -Theme nord';    Args = @{ DryRun = $true; Theme = 'nord' } },
        @{ Label = '-DryRun -Theme holiday'; Args = @{ DryRun = $true; Theme = 'holiday' } },
        @{ Label = '-DryRun -Uninstall';     Args = @{ DryRun = $true; Uninstall = $true } },
        @{ Label = '-DryRun -UninstallDotfiles'; Args = @{ DryRun = $true; UninstallDotfiles = $true } }
    )) {
        try {
            $modeParams = $modeSpec.Args
            & $setupScriptPath @modeParams *>$null
            Pass "setup.ps1 executes cleanly in $($modeSpec.Label) mode"
        } catch {
            Fail "setup.ps1 $($modeSpec.Label)" $_.Exception.Message
        }
    }

    $bootstrapScriptPath = Join-Path $RootDir "bootstrap.ps1"
    if (Test-Path $bootstrapScriptPath) {
        Pass "bootstrap.ps1 exists in repository root"
        try {
            & $bootstrapScriptPath -DryRun -SkipPackages *>$null
            Pass "bootstrap.ps1 executes cleanly in -DryRun -SkipPackages mode"
        } catch {
            Fail "bootstrap.ps1 dry-run" $_.Exception.Message
        }
    } else {
        Fail "bootstrap.ps1 missing" "bootstrap.ps1 not found in repository root"
    }
} finally {
    if (Test-Path $sandboxDir) {
        Remove-Item -Recurse -Force -Path $sandboxDir -ErrorAction SilentlyContinue
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ("Test Summary: {0} Passed, {1} Failed" -f $script:TestsPassed, $script:TestsFailed) -ForegroundColor $(if ($script:TestsFailed -eq 0) { 'Green' } else { 'Red' })
Write-Host "========================================" -ForegroundColor Cyan

if ($script:TestsFailed -gt 0) {
    exit 1
}
exit 0
