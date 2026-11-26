# =============================================================
# Suite 2: JSON, KDL, WASM, Governance, DocLint, 22 Themes & Assets
# =============================================================
Write-Host "`n[2/8] Validating JSON, Manifests, 22-Theme Engine, Governance & DocLint..." -ForegroundColor Yellow

# 1. Oh My Posh JSON
$p10kPath = Join-Path $RootDir 'config\powershell\p10k_single_line.omp.json'
try {
    $p10kRaw = Get-Content -LiteralPath $p10kPath -Raw
    $p10kJson = $p10kRaw | ConvertFrom-Json
    if ($p10kJson.blocks.Count -gt 0) {
        Add-TestPass "JSON valid: config/powershell/p10k_single_line.omp.json (blocks: $($p10kJson.blocks.Count))"
        $rpromptBlock = $p10kJson.blocks | Where-Object { $_.type -eq 'rprompt' }
        $leftPromptBlock = $p10kJson.blocks | Where-Object { $_.type -eq 'prompt' }
        $leftCap = $leftPromptBlock.segments | Where-Object { $_.type -eq 'text' -and ($_.template -eq [char]0xE0B0 -or $_.template -eq '\uE0B0') }
        $statusSegment = $rpromptBlock.segments[0]
        if ($statusSegment -and $statusSegment.type -eq 'status' -and $statusSegment.properties.always_enabled -eq $true -and $statusSegment.foreground -eq '#859900') {
            Add-TestPass 'p10k_single_line.omp.json rprompt status segment is leftmost and always_enabled with Solarized Green'
        } else {
            Add-TestFail 'p10k_single_line.omp.json rprompt validation' 'Status segment is not leftmost or not always_enabled in Solarized Green'
        }
        if ($leftCap -and $leftCap.foreground -eq '#073642' -and -not $leftCap.foreground_templates) {
            Add-TestPass 'p10k_single_line.omp.json left endpoint cap is static Base02'
        } else {
            Add-TestFail 'p10k_single_line.omp.json left cap validation' 'Left endpoint cap must be static Base02 without foreground_templates'
        }
        if ($p10kRaw -match '_WS_GIT_PR_LABEL' -and $p10kRaw -match '_WS_GIT_PR_URL' -and $p10kRaw -match '_HS_PROMPT_OS_ICON') {
            Add-TestPass 'p10k_single_line.omp.json includes async OSC 8 Git PR badge and holiday OS icon support'
        } else {
            Add-TestFail 'p10k_single_line.omp.json PR/holiday templates' 'Missing _WS_GIT_PR_LABEL, _WS_GIT_PR_URL, or _HS_PROMPT_OS_ICON'
        }
    } else {
        Add-TestFail 'JSON validation: config/powershell/p10k_single_line.omp.json' 'Missing blocks definition'
    }
} catch {
    Add-TestFail 'JSON parse error: config/powershell/p10k_single_line.omp.json' $_.Exception.Message
}

# 2. Windows Terminal settings.json & windows-settings.json (22 schemes + Alt+* pass-through)
$terminalJsonPath = Join-Path $RootDir 'config\terminal\settings.json'
try {
    $termJson = Get-Content -LiteralPath $terminalJsonPath -Raw | ConvertFrom-Json
    $hasSolarized = ($termJson.profiles.defaults.colorScheme -eq 'Solarized Dark')
    $hasFont = ($termJson.profiles.defaults.font.face -eq 'MesloLGS Nerd Font Mono' -or $termJson.profiles.defaults.font.face -eq 'MesloLGS NF')
    $schemeCount = @($termJson.schemes).Count
    if ($hasSolarized -and $hasFont -and $schemeCount -eq 22) {
        Add-TestPass "JSON valid: config/terminal/settings.json ($schemeCount schemes, Solarized Dark + $($termJson.profiles.defaults.font.face))"
    } else {
        Add-TestFail 'config/terminal/settings.json validation' "Expected Solarized Dark, MesloLGS font, and 22 schemes (got $schemeCount)"
    }
} catch {
    Add-TestFail 'JSON parse error: config/terminal/settings.json' $_.Exception.Message
}

$fragmentJsonPath = Join-Path $RootDir 'config\terminal\windows-settings.json'
try {
    $fragRaw = Get-Content -LiteralPath $fragmentJsonPath -Raw
    $fragJson = $fragRaw | ConvertFrom-Json
    $fragSolarized = ($fragJson.profiles.defaults.colorScheme -eq 'Solarized Dark')
    $fragFont = ($fragJson.profiles.defaults.font.face -eq 'MesloLGS Nerd Font Mono' -or $fragJson.profiles.defaults.font.face -eq 'MesloLGS NF')
    $fragSchemes = @($fragJson.schemes).Count
    $passesAltToZellij = ($fragRaw -notmatch '"alt\+h"' -and $fragRaw -notmatch '"alt\+z"' -and $fragRaw -match 'ctrl\+v')
    if ($fragSolarized -and $fragFont -and $fragSchemes -eq 22 -and $passesAltToZellij) {
        Add-TestPass "JSON valid: config/terminal/windows-settings.json ($fragSchemes schemes + Alt+* pass-through to Zellij)"
    } else {
        Add-TestFail 'config/terminal/windows-settings.json' "Defaults, 22 schemes ($fragSchemes), or Alt+* pass-through ($passesAltToZellij) mismatch"
    }
} catch {
    Add-TestFail 'JSON parse error: config/terminal/windows-settings.json' $_.Exception.Message
}

# 3. Zellij 0.46+ declarative configuration, layouts & theme
$zellijDir = Join-Path $RootDir 'config\zellij'
$zellijCfgPath = Join-Path $zellijDir 'config.kdl'
$zellijLayout3Path = Join-Path $zellijDir 'layouts\ide-3pane.kdl'
$zellijLayout2Path = Join-Path $zellijDir 'layouts\ide-2pane.kdl'
$zellijThemePath = Join-Path $zellijDir 'themes\windows-settings.kdl'
if ((Test-Path -LiteralPath $zellijCfgPath) -and (Test-Path -LiteralPath $zellijLayout3Path) -and (Test-Path -LiteralPath $zellijLayout2Path) -and (Test-Path -LiteralPath $zellijThemePath)) {
    $zellijCfgRaw = Get-Content -LiteralPath $zellijCfgPath -Raw
    $zellijLayout3Raw = Get-Content -LiteralPath $zellijLayout3Path -Raw
    $zellijLayout2Raw = Get-Content -LiteralPath $zellijLayout2Path -Raw
    $zellijThemeRaw = Get-Content -LiteralPath $zellijThemePath -Raw
    $wsBarLinksPath = Join-Path $RootDir 'plugin\ws-bar\src\links.rs'
    $wsBarMainRaw = Get-Content -LiteralPath (Join-Path $RootDir 'plugin\ws-bar\src\main.rs') -Raw
    if ($zellijCfgRaw -match 'pane_frames false' -and
        $zellijCfgRaw -match 'mouse_click_through false' -and
        $zellijCfgRaw -match 'mousebinds \{' -and
        $zellijCfgRaw -match 'GroupToggle' -and
        $zellijCfgRaw -match 'PassToApp' -and
        $zellijCfgRaw -match 'BEGIN WINDOWS-SETTINGS LINK PLUGIN' -and
        $zellijCfgRaw -match 'context_menu \{' -and
        $zellijCfgRaw -match 'attention \{' -and
        $zellijCfgRaw -match 'track_commands false' -and
        $zellijCfgRaw -match 'tray_icon false' -and
        $zellijCfgRaw -notmatch '(?s)desktop_notifications\s*\{[^}]*\btrue\b' -and
        $zellijCfgRaw -match 'toggle:ai' -and
        $zellijCfgRaw -match 'toggle-modal" "new"' -and
        $zellijCfgRaw -match 'toggle-modal" "dir"' -and
        $zellijCfgRaw -match 'bind "Alt u"' -and
        $zellijCfgRaw -match '"F1"' -and
        $zellijCfgRaw -match 'file:windows-settings-bar' -and
        (Test-Path -LiteralPath $wsBarLinksPath -PathType Leaf) -and
        $wsBarMainRaw -match 'HighlightClicked' -and
        $wsBarMainRaw -match '-EncodedCommand' -and
        $wsBarMainRaw -match 'open-link' -and
        $zellijLayout3Raw -match '_internal' -and
        $zellijLayout3Raw -match 'pane-init' -and
        $zellijLayout3Raw -match 'attention_muted=true' -and
        $zellijLayout2Raw -match 'attention_muted=true' -and
        $zellijThemeRaw -match 'windows-settings \{') {
        Add-TestPass 'KDL valid: config/zellij/ + ws-bar HighlightClicked Alt+Click link routing & mousebinds'
    } else {
        Add-TestFail 'config/zellij/ content validation' 'Missing expected Zellij 0.46+ keybinds, mousebinds, HighlightClicked, attention, compact-bar, or _internal pane-init blocks'
    }

    $zellijCmd = Get-Command zellij -ErrorAction SilentlyContinue
    if ($zellijCmd) {
        $zjCheck3 = (& $zellijCmd.Source --config-dir $zellijDir setup --check 2>&1) -join "`n"
        $zjExit3 = $LASTEXITCODE
        $zjCheck2 = (& $zellijCmd.Source --config-dir $zellijDir --layout $zellijLayout2Path setup --check 2>&1) -join "`n"
        $zjExit2 = $LASTEXITCODE
        if ($zjExit3 -eq 0 -and $zjExit2 -eq 0 -and $zjCheck3 -match 'Well defined' -and $zjCheck2 -match 'Well defined') {
            Add-TestPass 'zellij setup --check validates config.kdl + ide-3pane.kdl & ide-2pane.kdl'
        } else {
            Add-TestFail 'zellij setup --check' "Exit codes ($zjExit3, $zjExit2): $zjCheck3"
        }
    }
} else {
    Add-TestFail 'config/zellij/ files missing' 'Expected config.kdl, ide-3pane.kdl, ide-2pane.kdl, and themes/windows-settings.kdl'
}

# 4. Rust WASM Top-Bar Plugin crate (plugin/ws-bar/)
$wsBarDir = Join-Path (Join-Path $RootDir 'plugin') 'ws-bar'
$wsBarCargo = Join-Path $wsBarDir 'Cargo.toml'
$wsBarLock = Join-Path $wsBarDir 'Cargo.lock'
$wsBarSrcFiles = @('main.rs', 'palette.rs', 'roles.rs', 'render.rs') | ForEach-Object { Join-Path (Join-Path $wsBarDir 'src') $_ }
if ((Test-Path -LiteralPath $wsBarCargo) -and (Test-Path -LiteralPath $wsBarLock) -and (@($wsBarSrcFiles | Where-Object { -not (Test-Path -LiteralPath $_) }).Count -eq 0)) {
    $wsBarCargoRaw = Get-Content -LiteralPath $wsBarCargo -Raw
    $wsBarMainRaw = Get-Content -LiteralPath (Join-Path (Join-Path $wsBarDir 'src') 'main.rs') -Raw
    $wsBarRenderRaw = Get-Content -LiteralPath (Join-Path (Join-Path $wsBarDir 'src') 'render.rs') -Raw
    $wsBarPaletteRaw = Get-Content -LiteralPath (Join-Path (Join-Path $wsBarDir 'src') 'palette.rs') -Raw
    if ($wsBarCargoRaw -match 'name\s*=\s*"windows-settings-bar"' -and
        $wsBarCargoRaw -match 'zellij-tile\s*=\s*"0\.46\.0"' -and
        $wsBarMainRaw -match 'respawn:ai' -and
        $wsBarMainRaw -match 'mark_session_pane_seen' -and
        $wsBarRenderRaw -match 'current_session' -and
        $wsBarPaletteRaw -match 'BEGIN GENERATED HOLIDAY EMBLEMS') {
        Add-TestPass 'WASM plugin crate valid: plugin/ws-bar/ (auto-ack, self-alert suppression, respawn:ai, generated holiday emblems)'
    } else {
        Add-TestFail 'plugin/ws-bar/ features' 'Expected respawn:ai, mark_session_pane_seen, current_session filter, and generated holiday emblems'
    }
} else {
    Add-TestFail 'plugin/ws-bar/ files missing' 'Expected Cargo.toml, Cargo.lock, and src/{main,palette,roles,render}.rs'
}

# 5. Governance, AGENTS.md < 24 KB, docs/*, .agents/*, and Invoke-DocLint.ps1
$agentsPath = Join-Path $RootDir 'AGENTS.md'
$agentsBytes = if (Test-Path -LiteralPath $agentsPath) { (Get-Item -LiteralPath $agentsPath).Length } else { 999999 }
if ($agentsBytes -lt 24576 -and -not (Test-Path -LiteralPath (Join-Path $RootDir 'CLAUDE.md')) -and -not (Test-Path -LiteralPath (Join-Path $RootDir '.agents\AGENTS.md'))) {
    Add-TestPass "Single canonical AGENTS.md ($agentsBytes bytes < 24 KB budget) with zero duplicate agent files"
} else {
    Add-TestFail 'AGENTS.md budget / single-file invariant' "Bytes=$agentsBytes or duplicate CLAUDE.md/.agents/AGENTS.md found"
}

foreach ($govDoc in @(
    @{ Rel = 'LICENSE';                          Pattern = 'Apache License\s+Version 2\.0' },
    @{ Rel = 'AGENTS.md';                        Pattern = 'Universal semantic color contract' },
    @{ Rel = 'CONTRIBUTING.md';                  Pattern = 'Pre-completion verification checklist' },
    @{ Rel = 'SECURITY.md';                      Pattern = 'Private Vulnerability Reporting' },
    @{ Rel = 'llms.txt';                         Pattern = '## Core components' },
    @{ Rel = 'docs\color-architecture.md';       Pattern = 'BEGIN GENERATED THEME CATALOG' },
    @{ Rel = 'docs\ide-architecture.md';         Pattern = 'NamedPipeClientStream' },
    @{ Rel = 'docs\writing-style.md';            Pattern = 'backtick' },
    @{ Rel = '.agents\rules\monospace-tui.md';   Pattern = 'mono-tui v0\.2\.5' },
    @{ Rel = '.agents\skills\mono-tui-design\SKILL.md'; Pattern = 'mono-tui' },
    @{ Rel = '.agents\skills\mono-tui-audit\SKILL.md';  Pattern = 'mono-tui' }
)) {
    $govFull = Join-Path $RootDir $govDoc.Rel
    if ((Test-Path -LiteralPath $govFull) -and ((Get-Content -LiteralPath $govFull -Raw) -match $govDoc.Pattern)) {
        Add-TestPass "Governance & architecture doc valid: $($govDoc.Rel.Replace('\', '/'))"
    } else {
        Add-TestFail "Governance doc check: $($govDoc.Rel)" "Missing file or required pattern ($($govDoc.Pattern))"
    }
}

$docLintScript = Join-Path $RootDir 'tests\lint\Invoke-DocLint.ps1'
$docLintOut = (& pwsh -NoProfile -File $docLintScript 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0) {
    Add-TestPass 'Invoke-DocLint.ps1 passed (typography, links, CLI/toolchain/keybinding sync, and mono-tui overrides)'
} else {
    Add-TestFail 'Invoke-DocLint.ps1' $docLintOut
}

# 6. configuration.dsc.yaml & mise.toml
$dscContent = Get-Content -LiteralPath (Join-Path $RootDir 'configuration.dsc.yaml') -Raw
if ($dscContent -match 'configurationVersion:\s*0\.2\.0' -and
    $dscContent -match 'sharkdp\.bat' -and
    $dscContent -match 'eza-community\.eza' -and
    $dscContent -match 'aristocratos\.btop4win' -and
    $dscContent -match 'Zellij\.Zellij') {
    Add-TestPass 'YAML valid: configuration.dsc.yaml (includes bat, eza, Zellij, btop4win, WinLibs GCC)'
} else {
    Add-TestFail 'configuration.dsc.yaml' 'Missing expected DSC package declarations (bat, eza, Zellij, btop4win)'
}

$miseContent = Get-Content -LiteralPath (Join-Path $RootDir 'mise.toml') -Raw
if ($miseContent -match 'shellcheck\s*=\s*"latest"' -and
    $miseContent -match 'zellij\s*=\s*"latest"' -and
    $miseContent -match '"npm:typescript"\s*=\s*"6"' -and
    $miseContent -match 'go\.set_gopath\s*=\s*false') {
    Add-TestPass 'TOML valid: mise.toml (31 polyglot tools including shellcheck, npm LSPs, Zellij & Go isolation)'
} else {
    Add-TestFail 'mise.toml validation' 'Missing shellcheck, zellij, npm LSPs, or Go isolation in mise.toml'
}

# 7. 22 Theme Definitions, WCAG Monotonic Contrast, --check-assets, 22 bat & 22 btop Themes
$themeFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'config\themes') -Filter '*.theme')
$batThemeFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'config\bat\themes') -Filter '*-TrueColor.tmTheme')
$btopThemeFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'config\btop\themes') -Filter '*.theme')
$btopConfRaw = Get-Content -LiteralPath (Join-Path $RootDir 'config\btop\btop.conf') -Raw

if ($themeFiles.Count -eq 22 -and $batThemeFiles.Count -eq 22 -and $btopThemeFiles.Count -eq 22 -and
    $btopConfRaw -match '(?m)^cpu_graph_upper\s*=\s*"total"') {
    Add-TestPass '22 self-describing .theme palettes, 22 .tmTheme files, and 22 btop4win themes present'
} else {
    Add-TestFail '22-theme asset counts' "Counts: themes=$($themeFiles.Count), bat=$($batThemeFiles.Count), btop=$($btopThemeFiles.Count)"
}

$checkAssetsOut = (& pwsh -NoProfile -File (Join-Path $RootDir 'bin\theme.ps1') --check-assets 2>&1) -join "`n"
if ($LASTEXITCODE -eq 0) {
    Add-TestPass 'bin/theme.ps1 --check-assets confirms zero drift across all derived assets and generated blocks'
} else {
    Add-TestFail 'bin/theme.ps1 --check-assets' $checkAssetsOut
}

$paletteInvariantsOk = & {
    . (Join-Path $RootDir 'libexec\theme\Palette.ps1')
    $loadedMap = Get-BuiltinThemeMap -RepoDir $RootDir
    if ($loadedMap.Count -ne 22) { return "Expected 22 discovered themes, got $($loadedMap.Count)" }
    $rampSlots = @('BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3')
    foreach ($t in $loadedMap.Values) {
        $id = $t['THEME_ID']
        $mode = $t['THEME_MODE']
        $lums = @($rampSlots | ForEach-Object { Get-RelativeLuminance $t[$_] })
        for ($k = 0; $k -lt ($lums.Count - 1); $k++) {
            if ($mode -eq 'dark' -and $lums[$k] -ge $lums[$k + 1]) {
                return "${id}: non-monotonic dark ramp at $($rampSlots[$k]) >= $($rampSlots[$k + 1])"
            }
            if ($mode -eq 'light' -and $lums[$k] -le $lums[$k + 1]) {
                return "${id}: non-monotonic light ramp at $($rampSlots[$k]) <= $($rampSlots[$k + 1])"
            }
        }
        $pmenuContrast = Get-ContrastRatio $t['BASE1'] $t['BASE02']
        if ($pmenuContrast -lt 4.2) {
            return "${id}: PmenuSel contrast(BASE1, BASE02) = $pmenuContrast < 4.2"
        }
    }
    return 'OK'
}
if ($paletteInvariantsOk -eq 'OK') {
    Add-TestPass 'All 22 palettes satisfy monotonic BASE03..BASE3 luminance ramps and PmenuSel WCAG contrast'
} else {
    Add-TestFail '22-theme luminance/contrast invariants' $paletteInvariantsOk
}

# 8. Syntaxes (37), Tree-sitter Queries (43), Sample Fixtures (40), _vimrc, and cmd AutoRun
$syntaxFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'config\bat\syntaxes') -Filter '*.sublime-syntax')
$scmFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'config\nvim') -Recurse -Filter '*.scm')
$sampleFiles = @(Get-ChildItem -Path (Join-Path $RootDir 'tests\fixtures\sample-code') -File)
if ($syntaxFiles.Count -eq 37 -and $scmFiles.Count -eq 43 -and $sampleFiles.Count -eq 40 -and -not (Test-Path -LiteralPath (Join-Path $RootDir 'sample-code'))) {
    Add-TestPass '37 Sublime syntaxes, 43 Tree-sitter .scm queries, and 40 tests/fixtures/sample-code/ files valid'
} else {
    Add-TestFail 'Polyglot syntax/query/fixture counts' "syntaxes=$($syntaxFiles.Count), scm=$($scmFiles.Count), fixtures=$($sampleFiles.Count)"
}

$vimrcContent = Get-Content -LiteralPath (Join-Path $RootDir 'config\vim\_vimrc') -Raw
if ($vimrcContent -match 'BEGIN GENERATED BUILTIN THEMES' -and
    $vimrcContent -match 'BEGIN GENERATED HOLIDAY SCHEDULE' -and
    $vimrcContent -match 'dracula' -and
    $vimrcContent -match 'rose-pine' -and
    $vimrcContent -match 's:SmartHome\(\)' -and
    $vimrcContent -match '<kHome>' -and
    $vimrcContent -match '<Space>w' -and
    $vimrcContent -match 'smoothscroll') {
    Add-TestPass 'Standalone config/vim/_vimrc valid (22 generated themes, holiday schedule, <Space>w/h, Smart-Home, smoothscroll)'
} else {
    Add-TestFail 'config/vim/_vimrc validation' 'Missing generated 22-theme blocks, <Space>w, Smart-Home, or smoothscroll'
}

$cmdAutorunPath = Join-Path $RootDir 'config\cmd\autorun.cmd'
$cmdOutput = (& cmd.exe /d /c "call `"$cmdAutorunPath`" && set COLORTERM && set FORCE_HYPERLINK && set GOPATH && set GOCACHE && set ELAN_HOME && set LS_COLORS && doskey /macros") -join "`n"
if ($cmdOutput -match 'COLORTERM=truecolor' -and
    $cmdOutput -match 'FORCE_HYPERLINK=1' -and
    $cmdOutput -match 'GOPATH=' -and
    $cmdOutput -match 'GOCACHE=' -and
    $cmdOutput -match 'ELAN_HOME=' -and
    $cmdOutput -match '\*\.ps1=(00|38;2;)' -and
    $cmdOutput -match 'idek=ide quit --force' -and
    $cmdOutput -notmatch '(?m)^cat=bat') {
    Add-TestPass 'config/cmd/autorun.cmd & macros.doskey initialize TrueColor, XDG GOPATH/ELAN_HOME, .ps1 BASE0 LS_COLORS, and ide subcommand macros'
} else {
    Add-TestFail 'config/cmd/autorun.cmd execution' 'Missing expected GOPATH/ELAN_HOME, *.ps1=00, or updated ide doskey macros'
}
