# ==============================================================================
# Generators.ps1 - Theme artifact generators for shells, terminals & CLI tools
# ==============================================================================

function Build-FzfColorOptionString([System.Collections.IDictionary]$Theme, [bool]$IncludeLayout = $true) {
    if ($IncludeLayout) {
        return (
            "--color=bg+:$($Theme['BASE02']),bg:$($Theme['BASE03']),spinner:$($Theme['GREEN']),hl:$($Theme['BASE01']) " +
            "--color=fg:$($Theme['BASE0']),header:$($Theme['BASE01']),info:$($Theme['YELLOW']),pointer:$($Theme['GREEN']) " +
            "--color=marker:$($Theme['GREEN']),fg+:$($Theme['BASE1']),prompt:$($Theme['YELLOW']),hl+:$($Theme['BLUE']) " +
            "--color=border:$($Theme['BASE01']),separator:$($Theme['BASE01']),label:$($Theme['BASE01']),gutter:$($Theme['BASE03']) " +
            '--layout=reverse --border=rounded --info=inline'
        )
    }
    return (
        "--color=bg+:$($Theme['BASE02']),bg:$($Theme['BASE03']),spinner:$($Theme['GREEN'])," +
        "hl:$($Theme['BASE01']),fg:$($Theme['BASE0']),header:$($Theme['BASE01'])," +
        "border:$($Theme['BASE01']),separator:$($Theme['BASE01']),label:$($Theme['BASE01']),gutter:$($Theme['BASE03'])," +
        "info:$($Theme['YELLOW']),pointer:$($Theme['GREEN']),marker:$($Theme['GREEN'])," +
        "fg+:$($Theme['BASE1']),prompt:$($Theme['YELLOW']),hl+:$($Theme['BLUE'])"
    )
}

function Build-TrueColorLsColorString([System.Collections.IDictionary]$Theme, [string]$RepoDir = '') {
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $sgrMap = @{
        '30' = "38;2;$(Get-RgbSemi $Theme['BASE03'])"
        '31' = "38;2;$(Get-RgbSemi $Theme['RED'])"
        '32' = "38;2;$(Get-RgbSemi $Theme['GREEN'])"
        '33' = "38;2;$(Get-RgbSemi $Theme['YELLOW'])"
        '34' = "38;2;$(Get-RgbSemi $Theme['BLUE'])"
        '35' = "38;2;$(Get-RgbSemi $Theme['MAGENTA'])"
        '36' = "38;2;$(Get-RgbSemi $Theme['CYAN'])"
        '37' = "38;2;$(Get-RgbSemi $Theme['BASE2'])"
        '90' = "38;2;$(Get-RgbSemi $Theme['BASE01'])"
        '91' = "38;2;$(Get-RgbSemi $Theme['ORANGE'])"
        '92' = "38;2;$(Get-RgbSemi $Theme['BASE01'])"
        '93' = "38;2;$(Get-RgbSemi $Theme['BASE00'])"
        '94' = "38;2;$(Get-RgbSemi $Theme['BASE0'])"
        '95' = "38;2;$(Get-RgbSemi $Theme['VIOLET'])"
        '96' = "38;2;$(Get-RgbSemi $Theme['BASE1'])"
        '97' = "38;2;$(Get-RgbSemi $Theme['BASE3'])"
        '40' = "48;2;$(Get-RgbSemi $Theme['BASE02'])"
        '41' = "48;2;$(Get-RgbSemi $Theme['RED'])"
        '42' = "48;2;$(Get-RgbSemi $Theme['GREEN'])"
        '43' = "48;2;$(Get-RgbSemi $Theme['YELLOW'])"
        '44' = "48;2;$(Get-RgbSemi $Theme['BLUE'])"
        '45' = "48;2;$(Get-RgbSemi $Theme['MAGENTA'])"
        '46' = "48;2;$(Get-RgbSemi $Theme['CYAN'])"
        '47' = "48;2;$(Get-RgbSemi $Theme['BASE2'])"
    }
    $kwMap = @{
        NORMAL = 'no'; FILE = 'fi'; RESET = 'rs'; DIR = 'di'; OTHER_WRITABLE = 'ow'
        LINK = 'ln'; MULTIHARDLINK = 'mh'; FIFO = 'pi'; SOCK = 'so'; DOOR = 'do'
        BLK = 'bd'; CHR = 'cd'; ORPHAN = 'or'; MISSING = 'mi'; SETUID = 'su'
        SETGID = 'sg'; CAPABILITY = 'ca'; STICKY_OTHER_WRITABLE = 'tw'; STICKY = 'st'; EXEC = 'ex'
    }
    $base0Sgr = "38;2;$(Get-RgbSemi $Theme['BASE0'])"
    $dcFile = Join-Path (Join-Path (Join-Path $effRepo 'config') 'colors') 'LS_COLORS'
    $entries = [System.Collections.Generic.List[string]]::new()
    if ([System.IO.File]::Exists($dcFile)) {
        foreach ($rawLine in [System.IO.File]::ReadAllLines($dcFile, [System.Text.Encoding]::UTF8)) {
            $stripped = $rawLine.Trim()
            if (-not $stripped -or $stripped.StartsWith('#')) { continue }
            $line = ($stripped -split '\s+#', 2)[0].Trim()
            if (-not $line) { continue }
            $parts = $line -split '\s+', 2
            if ($parts.Count -ne 2 -or $parts[0] -eq 'TERM') { continue }
            $key = $parts[0]
            $code = $parts[1].Trim()
            $lsKey = if ($kwMap.ContainsKey($key)) { $kwMap[$key] } elseif ($key.StartsWith('.')) { "*$key" } else { $key }
            $lsVal = if ($code -eq '0') {
                '0'
            } elseif ($code -eq '00') {
                if ($key -in @('NORMAL', 'MULTIHARDLINK')) { '00' } else { $base0Sgr }
            } else {
                (($code -split ';') | ForEach-Object { if ($sgrMap.ContainsKey($_)) { $sgrMap[$_] } else { $_ } }) -join ';'
            }
            $entries.Add("${lsKey}=${lsVal}")
        }
    }
    if ($entries.Count -eq 0) {
        $entries.Add('rs=0')
        $entries.Add("di=$($sgrMap['34'])")
        $entries.Add("ln=$($sgrMap['36'])")
        $entries.Add('mh=00')
        $entries.Add("pi=$($sgrMap['33'])")
        $entries.Add("so=$($sgrMap['35'])")
        $entries.Add("do=$($sgrMap['35'])")
        $entries.Add("bd=$($sgrMap['35'])")
        $entries.Add("cd=$($sgrMap['35'])")
        $entries.Add("or=$($sgrMap['31'])")
        $entries.Add("mi=$($sgrMap['31'])")
        $entries.Add("ex=$($sgrMap['32'])")
        $entries.Add("fi=$base0Sgr")
    }
    return (($entries -join ':') + ':')
}

function Build-EzaColorString([System.Collections.IDictionary]$Theme) {
    $blue = Get-RgbSemi $Theme['BLUE']
    $cyan = Get-RgbSemi $Theme['CYAN']
    $green = Get-RgbSemi $Theme['GREEN']
    $orange = Get-RgbSemi $Theme['ORANGE']
    $violet = Get-RgbSemi $Theme['VIOLET']
    $magenta = Get-RgbSemi $Theme['MAGENTA']
    $yellow = Get-RgbSemi $Theme['YELLOW']
    $red = Get-RgbSemi $Theme['RED']
    $base0 = Get-RgbSemi $Theme['BASE0']
    $base01 = Get-RgbSemi $Theme['BASE01']
    $base1 = Get-RgbSemi $Theme['BASE1']

    $parts = @(
        "di=38;2;$blue", "ex=38;2;$green", "fi=38;2;$base0", "pi=38;2;$yellow",
        "so=38;2;$magenta", "bd=38;2;$magenta", "cd=38;2;$magenta", "ln=38;2;$cyan",
        "or=38;2;$red", "xx=38;2;$base01", "da=38;2;$base0", "hd=4;38;2;$base1",
        "lp=38;2;$base0", "cc=38;2;$orange", "bO=38;2;$red", "in=38;2;$base01",
        "bl=38;2;$base01", "oc=38;2;$base0", "ur=38;2;$base0", "uw=38;2;$base0",
        "ux=38;2;$base0", "ue=38;2;$base0", "gr=38;2;$base0", "gw=38;2;$base0",
        "gx=38;2;$base0", "tr=38;2;$base0", "tw=38;2;$base0", "tx=38;2;$base0",
        "su=38;2;$base0", "sf=38;2;$base0", "xa=38;2;$base0", "sn=38;2;$base0",
        "nb=38;2;$base01", "nk=38;2;$base0", "nm=38;2;$yellow", "ng=38;2;$orange",
        "nt=38;2;$red", "sb=38;2;$base0", "ub=38;2;$base01", "uk=38;2;$base0",
        "um=38;2;$yellow", "ug=38;2;$orange", "ut=38;2;$red", "df=38;2;$base0",
        "ds=38;2;$base0", "uu=38;2;$base0", "uR=38;2;$red", "un=38;2;$base0",
        "gu=38;2;$base0", "gR=38;2;$red", "gn=38;2;$base0", "lc=38;2;$base0",
        "lm=38;2;$yellow", "ga=38;2;$green", "gm=38;2;$yellow", "gd=38;2;$red",
        "gv=38;2;$base0", "gt=38;2;$base0", "gi=38;2;$base01", "gc=38;2;$red",
        "Gm=38;2;$green", "Go=38;2;$blue", "Gc=38;2;$green", "Gd=38;2;$yellow",
        "sp=38;2;$orange", "mp=38;2;$blue", "im=38;2;$violet", "vi=38;2;$violet",
        "mu=38;2;$violet", "lo=38;2;$violet", "cr=38;2;$magenta", "do=38;2;$base0",
        "co=38;2;$orange", "tm=38;2;$base01", "cm=38;2;$base01", "bu=38;2;$green",
        "sc=38;2;$base0", "Sn=38;2;$base01", "Su=38;2;$base0", "Sr=38;2;$base0",
        "St=38;2;$base0", "Sl=38;2;$base0", "ff=38;2;$base0"
    )
    return ($parts -join ':')
}

function Build-ActiveThemeText([System.Collections.IDictionary]$Theme) {
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Active Theme Snapshot: $($Theme['THEME_ID'])")
    $lines.Add("THEME_ID=`"$($Theme['THEME_ID'])`"")
    $lines.Add("THEME_LABEL=`"$($Theme['THEME_LABEL'])`"")
    $lines.Add("THEME_DESCRIPTION=`"$($Theme['THEME_DESCRIPTION'])`"")
    $lines.Add("THEME_MODE=`"$($Theme['THEME_MODE'])`"")
    $lines.Add("BAT_THEME_NAME=`"$($Theme['BAT_THEME_NAME'])`"")
    $lines.Add("BTOP_THEME_NAME=`"$($Theme['BTOP_THEME_NAME'])`"")
    $lines.Add("GHOSTTY_THEME_NAME=`"$($Theme['GHOSTTY_THEME_NAME'])`"")
    foreach ($k in $script:AllColorKeys) {
        $lines.Add("${k}=`"$($Theme[$k])`"")
    }
    return (($lines -join "`n") + "`n")
}

function Build-PowerShellThemeEnv([System.Collections.IDictionary]$Theme, [string]$RepoDir = '') {
    $ezaStr = Build-EzaColorString -Theme $Theme
    $lsStr = Build-TrueColorLsColorString -Theme $Theme -RepoDir $RepoDir
    $fzfStr = Build-FzfColorOptionString -Theme $Theme -IncludeLayout $true

    $base02 = Get-RgbSemi $Theme['BASE02']
    $base01 = Get-RgbSemi $Theme['BASE01']
    $base00 = Get-RgbSemi $Theme['BASE00']
    $base0  = Get-RgbSemi $Theme['BASE0']
    $base1  = Get-RgbSemi $Theme['BASE1']
    $yellow = Get-RgbSemi $Theme['YELLOW']
    $orange = Get-RgbSemi $Theme['ORANGE']
    $red    = Get-RgbSemi $Theme['RED']
    $magenta = Get-RgbSemi $Theme['MAGENTA']
    $violet = Get-RgbSemi $Theme['VIOLET']
    $blue   = Get-RgbSemi $Theme['BLUE']
    $cyan   = Get-RgbSemi $Theme['CYAN']
    $green  = Get-RgbSemi $Theme['GREEN']

    $jqStr = "38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${cyan}:38;2;${base0}:38;2;${base0}:38;2;${green}"
    $hmeta = Get-HolidayMeta -Theme $Theme
    $osIconStmt = if ($hmeta) {
        "`$env:_HS_PROMPT_OS_ICON = '$($hmeta.Icon.Replace("'", "''"))'"
    } else {
        'Remove-Item Env:_HS_PROMPT_OS_ICON -ErrorAction SilentlyContinue'
    }

    $hexLines = foreach ($slot in $script:CoreColorKeys) {
        "`$env:_HS_HEX_${slot} = '$($Theme[$slot])'"
    }
    $hexBlock = $hexLines -join "`r`n"

    $body = @"
# Generated by bin/theme.ps1 - Active Theme: $($Theme['THEME_ID'])
`$env:WINDOWS_SETTINGS_THEME = '$($Theme['THEME_ID'])'
`$env:HOME_SETTINGS_THEME = '$($Theme['THEME_ID'])'
`$env:HOME_SETTINGS_THEME_MODE = '$($Theme['THEME_MODE'])'
`$env:BAT_THEME = '$($Theme['BAT_THEME_NAME'])'
`$env:FZF_DEFAULT_OPTS = '$fzfStr'
`$env:_ZO_FZF_OPTS = `$env:FZF_DEFAULT_OPTS
`$env:EZA_COLORS = '$ezaStr'
`$env:EXA_COLORS = `$env:EZA_COLORS
`$env:JQ_COLORS = '$jqStr'
`$env:LS_COLORS = '$lsStr'
`$env:LESS = if (`$env:LESS) { `$env:LESS } else { '-R' }
`$env:GROFF_NO_SGR = '1'
$hexBlock
`$env:LESS_TERMCAP_mb = "``e[38;2;${red}m"
`$env:LESS_TERMCAP_md = "``e[1;38;2;${blue}m"
`$env:LESS_TERMCAP_me = "``e[0m"
`$env:LESS_TERMCAP_so = "``e[38;2;${base1};48;2;${base02}m"
`$env:LESS_TERMCAP_se = "``e[0m"
`$env:LESS_TERMCAP_us = "``e[4;38;2;${cyan}m"
`$env:LESS_TERMCAP_ue = "``e[0m"
`$env:_HS_ESC_BASE01 = "``e[38;2;${base01}m"
`$env:_HS_ESC_BASE00 = "``e[38;2;${base00}m"
`$env:_HS_ESC_BASE0 = "``e[38;2;${base0}m"
`$env:_HS_ESC_BASE1 = "``e[38;2;${base1}m"
`$env:_HS_ESC_BG_BASE02 = "``e[48;2;${base02}m"
`$env:_HS_ESC_YELLOW = "``e[38;2;${yellow}m"
`$env:_HS_ESC_ORANGE = "``e[38;2;${orange}m"
`$env:_HS_ESC_RED = "``e[38;2;${red}m"
`$env:_HS_ESC_MAGENTA = "``e[38;2;${magenta}m"
`$env:_HS_ESC_VIOLET = "``e[38;2;${violet}m"
`$env:_HS_ESC_BLUE = "``e[38;2;${blue}m"
`$env:_HS_ESC_CYAN = "``e[38;2;${cyan}m"
`$env:_HS_ESC_GREEN = "``e[38;2;${green}m"
$osIconStmt
`$env:_WS_LOADED_THEME = '$($Theme['THEME_ID'])'
if (`$Host.Name -eq 'ConsoleHost' -and (Get-Module -Name PSReadLine -ErrorAction SilentlyContinue)) {
    Set-PSReadLineOption -Colors @{
        Default                = "``e[38;2;${base0}m"
        Command                = "``e[38;2;${green}m"
        Parameter              = "``e[38;2;${base0}m"
        Operator               = "``e[38;2;${base0}m"
        Variable               = "``e[38;2;${base0}m"
        String                 = "``e[38;2;${cyan}m"
        Number                 = "``e[38;2;${magenta}m"
        Type                   = "``e[38;2;${green}m"
        Comment                = "``e[38;2;${base01}m"
        Keyword                = "``e[38;2;${yellow}m"
        Member                 = "``e[38;2;${base0}m"
        Emphasis               = "``e[38;2;${blue}m"
        Error                  = "``e[38;2;${red}m"
        Selection              = "``e[48;2;${base02}m"
        InlinePrediction       = "``e[38;2;${base01}m"
        ListPrediction         = "``e[38;2;${base01}m"
        ListPredictionSelected = "``e[48;2;${base02}m"
        ListPredictionTooltip  = "``e[38;2;${base01}m"
    }
}
"@
    return ([regex]::Replace($body.TrimEnd("`r", "`n"), "`r?`n", "`r`n") + "`r`n")
}

function Build-CmdThemeEnv([System.Collections.IDictionary]$Theme, [string]$RepoDir = '') {
    $ezaStr = Build-EzaColorString -Theme $Theme
    $lsStr = Build-TrueColorLsColorString -Theme $Theme -RepoDir $RepoDir
    $fzfStr = Build-FzfColorOptionString -Theme $Theme -IncludeLayout $true

    $magenta = Get-RgbSemi $Theme['MAGENTA']
    $cyan    = Get-RgbSemi $Theme['CYAN']
    $base0   = Get-RgbSemi $Theme['BASE0']
    $green   = Get-RgbSemi $Theme['GREEN']
    $blue    = Get-RgbSemi $Theme['BLUE']
    $base01  = Get-RgbSemi $Theme['BASE01']
    $base02  = Get-RgbSemi $Theme['BASE02']

    $jqStr = "38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${cyan}:38;2;${base0}:38;2;${base0}:38;2;${green}"
    $hmeta = Get-HolidayMeta -Theme $Theme
    $winGlyph    = [string][char]0xE62A
    $thinChevron = [string][char]0xE0B1
    $folderGlyph = [string][char]0xF07C
    $solidCap    = [string][char]0xE0B0
    $promptIcon  = if ($hmeta) { $hmeta.Icon } else { $winGlyph }

    $body = @"
@echo off
:: Generated by bin/theme.ps1 - Active Theme: $($Theme['THEME_ID'])
set "WINDOWS_SETTINGS_THEME=$($Theme['THEME_ID'])"
set "HOME_SETTINGS_THEME=$($Theme['THEME_ID'])"
set "HOME_SETTINGS_THEME_MODE=$($Theme['THEME_MODE'])"
set "BAT_THEME=$($Theme['BAT_THEME_NAME'])"
set "FZF_DEFAULT_OPTS=$fzfStr"
set "EZA_COLORS=$ezaStr"
set "EXA_COLORS=%EZA_COLORS%"
set "JQ_COLORS=$jqStr"
set "LS_COLORS=$lsStr"
prompt `$E[48;2;${base02}m`$E[38;2;${base0}m $promptIcon `$E[38;2;${base01}m${thinChevron}`$E[38;2;${blue}m $folderGlyph `$P `$E[0m`$E[38;2;${base02}m${solidCap}`$E[0m`$S
"@
    return ([regex]::Replace($body.TrimEnd("`r", "`n"), "`r?`n", "`r`n") + "`r`n")
}

function Build-DeltaGitConfig([System.Collections.IDictionary]$Theme) {
    $lightVal = if ($Theme['THEME_MODE'] -eq 'light') { 'true' } else { 'false' }
    if ($Theme['THEME_ID'] -eq 'solarized-dark') {
        $plusBg = '#0d3834'
        $plusEmphBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $minusBg = '#2d222a'
        $minusEmphBg = $Theme['MIX_RED'].ToLowerInvariant()
    } elseif ($Theme['THEME_CATEGORY'] -eq 'holiday') {
        $plusBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $plusSeed = if ($Theme['THEME_MODE'] -eq 'light') { '#009E3D' } else { '#2EE66B' }
        $plusEmphBg = (Merge-HexColor -FgHex $plusSeed -BgHex $Theme['MIX_GREEN'] -Alpha 0.28).ToLowerInvariant()
        $minusBg = $Theme['MIX_RED'].ToLowerInvariant()
        $minusEmphBg = (Merge-HexColor -FgHex $Theme['RED'] -BgHex $Theme['MIX_RED'] -Alpha 0.28).ToLowerInvariant()
    } else {
        $plusBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $plusEmphBg = (Merge-HexColor -FgHex $Theme['GREEN'] -BgHex $Theme['BASE03'] -Alpha 0.30).ToLowerInvariant()
        $minusBg = $Theme['MIX_RED'].ToLowerInvariant()
        $minusEmphBg = (Merge-HexColor -FgHex $Theme['RED'] -BgHex $Theme['BASE03'] -Alpha 0.30).ToLowerInvariant()
    }
    $mag = $Theme['MAGENTA'].ToLowerInvariant()
    $cyn = $Theme['CYAN'].ToLowerInvariant()
    $b01 = $Theme['BASE01'].ToLowerInvariant()
    $blu = $Theme['BLUE'].ToLowerInvariant()
    $grn = $Theme['GREEN'].ToLowerInvariant()
    $red = $Theme['RED'].ToLowerInvariant()
    $emDash = [string][char]0x2014

    $cfg = @"
# Git Delta configuration $emDash $($Theme['THEME_LABEL']) TrueColor
[core]
    pager = delta

[interactive]
    diffFilter = delta --color-only

[delta]
    navigate = true
    light = $lightVal
    syntax-theme = $($Theme['BAT_THEME_NAME'])
    line-numbers = true
    side-by-side = false
    commit-style = "$mag"
    file-style = "$cyn"
    file-decoration-style = "$b01" ul
    hunk-header-style = line-number syntax
    hunk-header-line-number-style = "$blu"
    hunk-header-decoration-style = "$b01" box
    plus-style = syntax "$plusBg"
    plus-emph-style = syntax "$plusEmphBg"
    plus-empty-line-marker-style = normal "$plusBg"
    minus-style = syntax "$minusBg"
    minus-emph-style = syntax "$minusEmphBg"
    minus-empty-line-marker-style = normal "$minusBg"
    line-numbers-plus-style = "$grn"
    line-numbers-minus-style = "$red"
    line-numbers-left-style = "$b01"
    line-numbers-right-style = "$b01"
    line-numbers-zero-style = "$b01"
    whitespace-error-style = "$red" reverse

[merge]
    conflictstyle = zdiff3

[diff]
    colorMoved = default
"@
    return ($cfg.Replace("`r`n", "`n").TrimEnd("`n") + "`n")
}

function Build-TealdeerConfig([System.Collections.IDictionary]$Theme) {
    $b0 = ConvertFrom-HexToRgb -Hex $Theme['BASE0']
    $gr = ConvertFrom-HexToRgb -Hex $Theme['GREEN']
    $cy = ConvertFrom-HexToRgb -Hex $Theme['CYAN']
    $bl = ConvertFrom-HexToRgb -Hex $Theme['BLUE']
    $mg = ConvertFrom-HexToRgb -Hex $Theme['MAGENTA']
    $emDash = [string][char]0x2014

    $cfg = @"
# tealdeer (tldr) configuration $emDash $($Theme['THEME_LABEL']) TrueColor
[display]
compact = false
use_pager = false

[style.description]
foreground = { rgb = { r = $($b0[0]), g = $($b0[1]), b = $($b0[2]) } }
bold = false
underline = false
italic = false

[style.command_name]
foreground = { rgb = { r = $($gr[0]), g = $($gr[1]), b = $($gr[2]) } }
bold = false
underline = false
italic = false

[style.example_text]
foreground = { rgb = { r = $($bl[0]), g = $($bl[1]), b = $($bl[2]) } }
bold = false
underline = false
italic = false

[style.example_code]
foreground = { rgb = { r = $($cy[0]), g = $($cy[1]), b = $($cy[2]) } }
bold = false
underline = false
italic = false

[style.example_variable]
foreground = { rgb = { r = $($mg[0]), g = $($mg[1]), b = $($mg[2]) } }
bold = false
underline = true
italic = false

[updates]
auto_update = true
auto_update_interval_hours = 720
"@
    return ($cfg.Replace("`r`n", "`n").TrimEnd("`n") + "`n")
}

function Build-BtopThemeText([System.Collections.IDictionary]$Theme) {
    $c = @{}
    foreach ($k in $script:AllColorKeys) {
        $c[$k] = ([string]$Theme[$k]).ToLowerInvariant()
    }
    $txt = @"
# $($Theme['THEME_LABEL']) TrueColor theme for btop
# Matches the 16-color semantic palette architecture

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="$($c['BASE03'])"

# Main text color
theme[main_fg]="$($c['BASE0'])"

# Title color for boxes
theme[title]="$($c['BASE1'])"

# Highlight color for keyboard shortcuts
theme[hi_fg]="$($c['YELLOW'])"

# Background color of selected item in processes box
theme[selected_bg]="$($c['BASE02'])"

# Foreground color of selected item in processes box
theme[selected_fg]="$($c['BASE1'])"

# Color of inactive/disabled text
theme[inactive_fg]="$($c['BASE01'])"

# Color of text appearing on top of graphs, such as uptime and current network graph scaling
theme[graph_text]="$($c['BASE00'])"

# Background color of the percentage meters
theme[meter_bg]="$($c['BASE02'])"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="$($c['GREEN'])"

# Cpu box outline color
theme[cpu_box]="$($c['BASE01'])"

# Memory/disks box outline color
theme[mem_box]="$($c['BASE01'])"

# Net up/down box outline color
theme[net_box]="$($c['BASE01'])"

# Processes box outline color
theme[proc_box]="$($c['BASE01'])"

# Box divider line and small boxes line color
theme[div_line]="$($c['BASE01'])"

# Temperature graph colors
theme[temp_start]="$($c['GREEN'])"
theme[temp_mid]="$($c['YELLOW'])"
theme[temp_end]="$($c['RED'])"

# CPU graph colors
theme[cpu_start]="$($c['GREEN'])"
theme[cpu_mid]="$($c['CYAN'])"
theme[cpu_end]="$($c['BLUE'])"

# Mem/Disk free meter
theme[free_start]="$($c['BASE01'])"
theme[free_mid]="$($c['BASE00'])"
theme[free_end]="$($c['BASE0'])"

# Mem/Disk cached meter
theme[cached_start]="$($c['CYAN'])"
theme[cached_mid]="$($c['BLUE'])"
theme[cached_end]="$($c['VIOLET'])"

# Mem/Disk available meter
theme[available_start]="$($c['GREEN'])"
theme[available_mid]="$($c['CYAN'])"
theme[available_end]="$($c['BLUE'])"

# Mem/Disk used meter
theme[used_start]="$($c['YELLOW'])"
theme[used_mid]="$($c['ORANGE'])"
theme[used_end]="$($c['RED'])"

# Download graph colors
theme[download_start]="$($c['CYAN'])"
theme[download_mid]="$($c['BLUE'])"
theme[download_end]="$($c['VIOLET'])"

# Upload graph colors
theme[upload_start]="$($c['GREEN'])"
theme[upload_mid]="$($c['YELLOW'])"
theme[upload_end]="$($c['ORANGE'])"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="$($c['GREEN'])"
theme[process_mid]="$($c['YELLOW'])"
theme[process_end]="$($c['RED'])"
"@
    return ($txt.Replace("`r`n", "`n").TrimEnd("`n") + "`n")
}

function Build-ZellijThemeKdl([System.Collections.IDictionary]$Theme) {
    $b03 = Get-RgbSpace $Theme['BASE03']
    $b02 = Get-RgbSpace $Theme['BASE02']
    $b01 = Get-RgbSpace $Theme['BASE01']
    $b00 = Get-RgbSpace $Theme['BASE00']
    $b0  = Get-RgbSpace $Theme['BASE0']
    $b1  = Get-RgbSpace $Theme['BASE1']
    $ylw = Get-RgbSpace $Theme['YELLOW']
    $org = Get-RgbSpace $Theme['ORANGE']
    $red = Get-RgbSpace $Theme['RED']
    $mag = Get-RgbSpace $Theme['MAGENTA']
    $vio = Get-RgbSpace $Theme['VIOLET']
    $blu = Get-RgbSpace $Theme['BLUE']
    $cyn = Get-RgbSpace $Theme['CYAN']
    $grn = Get-RgbSpace $Theme['GREEN']

    $headerLabel = if ($Theme['THEME_ID'] -eq 'solarized-dark') { 'Default: Solarized Dark' } else { $Theme['THEME_LABEL'] }
    $kdl = @"
// Auto-generated by windows-settings bin/theme.ps1 ($headerLabel)
// Universal Semantic Color Contract mapped to Zellij 0.46+ UI components.
themes {
    windows-settings {
        text_unselected {
            base $b0
            background $b02
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        text_selected {
            base $b1
            background $b02
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        ribbon_selected {
            base $b03
            background $grn
            emphasis_0 $red
            emphasis_1 $org
            emphasis_2 $mag
            emphasis_3 $blu
        }
        ribbon_unselected {
            base $b0
            background $b02
            emphasis_0 $red
            emphasis_1 $b1
            emphasis_2 $blu
            emphasis_3 $mag
        }
        table_title {
            base $grn
            background 0
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        table_cell_unselected {
            base $b0
            background $b03
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        table_cell_selected {
            base $b1
            background $b02
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        list_unselected {
            base $b0
            background $b03
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        list_selected {
            base $b1
            background $b02
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $grn
            emphasis_3 $mag
        }
        frame_unselected {
            base $b01
            background 0
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $mag
            emphasis_3 0
        }
        frame_selected {
            base $b01
            background 0
            emphasis_0 $org
            emphasis_1 $cyn
            emphasis_2 $mag
            emphasis_3 0
        }
        frame_highlight {
            base $ylw
            background 0
            emphasis_0 $mag
            emphasis_1 $org
            emphasis_2 $org
            emphasis_3 $org
        }
        exit_code_success {
            base $grn
            background 0
            emphasis_0 $cyn
            emphasis_1 $b03
            emphasis_2 $mag
            emphasis_3 $blu
        }
        exit_code_error {
            base $red
            background 0
            emphasis_0 $ylw
            emphasis_1 0
            emphasis_2 0
            emphasis_3 0
        }
        multiplayer_user_colors {
            player_1 $mag
            player_2 $blu
            player_3 $vio
            player_4 $ylw
            player_5 $cyn
            player_6 $org
            player_7 $red
            player_8 $grn
            player_9 $b00
            player_10 $b1
        }
    }
}
"@
    return ($kdl.Replace("`r`n", "`n").TrimEnd("`n") + "`n")
}

function Convert-SolarizedHexString([string]$InputText, [System.Collections.IDictionary]$Theme, [bool]$Lowercase = $true) {
    $slotMap = [ordered]@{
        '#002B36' = '__WS_B03__'
        '#073642' = '__WS_B02__'
        '#586E75' = '__WS_B01__'
        '#657B83' = '__WS_B00__'
        '#839496' = '__WS_B0__'
        '#93A1A1' = '__WS_B1__'
        '#EEE8D5' = '__WS_B2__'
        '#FDF6E3' = '__WS_B3__'
        '#B58900' = '__WS_YEL__'
        '#CB4B16' = '__WS_ORA__'
        '#DC322F' = '__WS_RED__'
        '#D33682' = '__WS_MAG__'
        '#6C71C4' = '__WS_VIO__'
        '#268BD2' = '__WS_BLU__'
        '#2AA198' = '__WS_CYA__'
        '#859900' = '__WS_GRN__'
    }
    $valMap = @{
        '__WS_B03__' = $Theme['BASE03']
        '__WS_B02__' = $Theme['BASE02']
        '__WS_B01__' = $Theme['BASE01']
        '__WS_B00__' = $Theme['BASE00']
        '__WS_B0__'  = $Theme['BASE0']
        '__WS_B1__'  = $Theme['BASE1']
        '__WS_B2__'  = $Theme['BASE2']
        '__WS_B3__'  = $Theme['BASE3']
        '__WS_YEL__' = $Theme['YELLOW']
        '__WS_ORA__' = $Theme['ORANGE']
        '__WS_RED__' = $Theme['RED']
        '__WS_MAG__' = $Theme['MAGENTA']
        '__WS_VIO__' = $Theme['VIOLET']
        '__WS_BLU__' = $Theme['BLUE']
        '__WS_CYA__' = $Theme['CYAN']
        '__WS_GRN__' = $Theme['GREEN']
    }
    $out = $InputText
    foreach ($hex in $slotMap.Keys) {
        $out = [regex]::Replace($out, [regex]::Escape($hex), $slotMap[$hex], [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($tok in $valMap.Keys) {
        $rep = if ($Lowercase) { $valMap[$tok].ToLowerInvariant() } else { $valMap[$tok].ToUpperInvariant() }
        $out = $out.Replace($tok, $rep)
    }
    return $out
}

function Build-TmThemeText([string]$BaseTmThemeText, [System.Collections.IDictionary]$Theme) {
    $normBase = $BaseTmThemeText.Replace("`r`n", "`n")
    $remapped = Convert-SolarizedHexString -InputText $normBase -Theme $Theme -Lowercase $false
    return $remapped.Replace('<string>Solarized-Dark-TrueColor</string>', "<string>$($Theme['BAT_THEME_NAME'])</string>")
}

function ConvertTo-WindowsTerminalScheme([System.Collections.IDictionary]$Theme) {
    return [ordered]@{
        name                = $Theme['GHOSTTY_THEME_NAME']
        background          = $Theme['BASE03']
        black               = $Theme['BASE02']
        blue                = $Theme['BLUE']
        brightBlack         = $Theme['BASE01']
        brightBlue          = $Theme['BASE0']
        brightCyan          = $Theme['BASE1']
        brightGreen         = $Theme['BASE01']
        brightPurple        = $Theme['VIOLET']
        brightRed           = $Theme['ORANGE']
        brightWhite         = $Theme['BASE3']
        brightYellow        = $Theme['BASE00']
        cursorColor         = $Theme['BASE0']
        cyan                = $Theme['CYAN']
        foreground          = $Theme['BASE0']
        green               = $Theme['GREEN']
        purple              = $Theme['MAGENTA']
        red                 = $Theme['RED']
        selectionBackground = $Theme['BASE02']
        white               = $Theme['BASE2']
        yellow              = $Theme['YELLOW']
    }
}
