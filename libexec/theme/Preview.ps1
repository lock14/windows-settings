# ==============================================================================
# Preview.ps1 - ANSI width math, 4-tier color capability, preview cards & fzf
# ==============================================================================

$script:AnsiSgrPattern = [regex]::new('\x1b\[[0-9;]*m', [System.Text.RegularExpressions.RegexOptions]::Compiled)
$script:FzfLoadPosCache = @{}
$script:SwatchStripKeys = @(
    'BASE03', 'BASE0', 'GREEN', 'BLUE', 'YELLOW',
    'VIOLET', 'CYAN', 'MAGENTA', 'ORANGE', 'RED'
)

function Test-UseNerdFont {
    $nf = if ($env:IDE_NERD_FONTS) { $env:IDE_NERD_FONTS.Trim().ToLowerInvariant() } else { '' }
    if ($nf -in @('0', 'false', 'off', 'no', 'ascii')) { return $false }
    $asc = if ($env:IDE_ASCII) { $env:IDE_ASCII.Trim().ToLowerInvariant() } else { '' }
    if ($asc -in @('1', 'true', 'on', 'yes')) { return $false }
    $term = if ($env:TERM) { $env:TERM.Trim().ToLowerInvariant() } else { '' }
    if ($term -eq 'dumb') { return $false }
    return $true
}

function Get-PreviewColorTier {
    if ($env:NO_COLOR) { return 'nocolor' }
    $term = if ($env:TERM) { $env:TERM.Trim().ToLowerInvariant() } else { '' }
    if ($term -eq 'dumb') { return 'mono' }
    if ($term -eq 'linux') { return '16color' }
    $ct = if ($env:COLORTERM) { $env:COLORTERM.Trim().ToLowerInvariant() } else { '' }
    if ($ct -in @('16color', 'ansi', '4bit')) { return '16color' }
    if ($ct -in @('256color', '8bit')) { return '256color' }
    return 'truecolor'
}

function ConvertFrom-HexToXterm256Index([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb -Hex $Hex
    $rIdx = [int][Math]::Round(($rgb[0] / 255.0) * 5.0)
    $gIdx = [int][Math]::Round(($rgb[1] / 255.0) * 5.0)
    $bIdx = [int][Math]::Round(($rgb[2] / 255.0) * 5.0)
    return (16 + 36 * $rIdx + 6 * $gIdx + $bIdx)
}

function Format-FgEsc([string]$Hex, [string]$Tier = 'truecolor') {
    $esc = [char]27
    switch ($Tier) {
        'truecolor' { return "${esc}[38;2;$(Get-RgbSemi $Hex)m" }
        '256color'  { return "${esc}[38;5;$(ConvertFrom-HexToXterm256Index $Hex)m" }
        default     { return '' }
    }
}

function Format-BgEsc([string]$Hex, [string]$Tier = 'truecolor') {
    $esc = [char]27
    switch ($Tier) {
        'truecolor' { return "${esc}[48;2;$(Get-RgbSemi $Hex)m" }
        '256color'  { return "${esc}[48;5;$(ConvertFrom-HexToXterm256Index $Hex)m" }
        default     { return '' }
    }
}

function Get-CodePointCellWidth([int]$CodePoint) {
    if ($CodePoint -ge 0x20 -and $CodePoint -lt 0x7F) { return 1 }
    if ($CodePoint -lt 0x20 -or $CodePoint -eq 0x7F) { return 0 }
    if ($CodePoint -in @(0x200B, 0x200C, 0x200D, 0xFE0E, 0xFE0F, 0xFEFF)) { return 0 }
    # Nerd Font Private Use Areas (BMP PUA + Supplementary PUA-A/B): 1 cell
    if (($CodePoint -ge 0xE000 -and $CodePoint -le 0xF8FF) -or ($CodePoint -ge 0xF0000 -and $CodePoint -le 0x10FFFF)) {
        return 1
    }
    $cat = if ($CodePoint -le 0xFFFF) {
        [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory([char]$CodePoint)
    } else {
        [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory([char]::ConvertFromUtf32($CodePoint), 0)
    }
    if ($cat -in @(
            [System.Globalization.UnicodeCategory]::NonSpacingMark,
            [System.Globalization.UnicodeCategory]::SpacingCombiningMark,
            [System.Globalization.UnicodeCategory]::EnclosingMark,
            [System.Globalization.UnicodeCategory]::Format
        )) {
        return 0
    }
    if (($CodePoint -ge 0x1F300 -and $CodePoint -le 0x1FAFF) -or
        $CodePoint -in @(0x231A, 0x231B, 0x23F0, 0x23F3, 0x2614, 0x2615, 0x26A1, 0x2705, 0x2728, 0x274C, 0x2B50) -or
        ($CodePoint -ge 0x1100 -and $CodePoint -le 0x115F) -or
        ($CodePoint -ge 0x2E80 -and $CodePoint -le 0x303E) -or
        ($CodePoint -ge 0x3040 -and $CodePoint -le 0x33BF) -or
        ($CodePoint -ge 0x3400 -and $CodePoint -le 0x4DBF) -or
        ($CodePoint -ge 0x4E00 -and $CodePoint -le 0xA4CF) -or
        ($CodePoint -ge 0xAC00 -and $CodePoint -le 0xD7A3) -or
        ($CodePoint -ge 0xF900 -and $CodePoint -le 0xFAFF) -or
        ($CodePoint -ge 0xFE10 -and $CodePoint -le 0xFE6F) -or
        ($CodePoint -ge 0xFF01 -and $CodePoint -le 0xFF60) -or
        ($CodePoint -ge 0xFFE0 -and $CodePoint -le 0xFFE6) -or
        ($CodePoint -ge 0x20000 -and $CodePoint -le 0x3FFFD)) {
        return 2
    }
    return 1
}

function Get-VisibleLength([string]$Text) {
    if (-not $Text) { return 0 }
    $plain = $script:AnsiSgrPattern.Replace($Text, '').Replace("`t", '    ')
    $total = 0
    $len = $plain.Length
    for ($idx = 0; $idx -lt $len; $idx++) {
        $ch = $plain[$idx]
        if ([char]::IsHighSurrogate($ch) -and ($idx + 1) -lt $len -and [char]::IsLowSurrogate($plain[$idx + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $plain[$idx + 1])
            $idx++
        } else {
            $cp = [int]$ch
        }
        $total += (Get-CodePointCellWidth -CodePoint $cp)
    }
    return $total
}

function Limit-AnsiLine([string]$Text, [int]$MaxCols) {
    if ($MaxCols -le 0) { return '' }
    $ellipsis = [string][char]0x2026
    $expanded = if ($Text) { $Text.Replace("`t", '    ') } else { '' }
    if ((Get-VisibleLength -Text $expanded) -le $MaxCols) {
        return $expanded
    }
    if ($MaxCols -eq 1) { return $ellipsis }
    $limit = $MaxCols - 1
    $sb = [System.Text.StringBuilder]::new($expanded.Length)
    $vis = 0
    $idx = 0
    $len = $expanded.Length
    while ($idx -lt $len) {
        if ([int]$expanded[$idx] -eq 27) {
            $m = $script:AnsiSgrPattern.Match($expanded, $idx)
            if ($m.Success -and $m.Index -eq $idx) {
                [void]$sb.Append($m.Value)
                $idx += $m.Length
                continue
            }
        }
        $ch = $expanded[$idx]
        $step = 1
        if ([char]::IsHighSurrogate($ch) -and ($idx + 1) -lt $len -and [char]::IsLowSurrogate($expanded[$idx + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $expanded[$idx + 1])
            $step = 2
        } else {
            $cp = [int]$ch
        }
        $cw = Get-CodePointCellWidth -CodePoint $cp
        if (($vis + $cw) -gt $limit) { break }
        [void]$sb.Append($expanded, $idx, $step)
        $vis += $cw
        $idx += $step
    }
    [void]$sb.Append($ellipsis)
    return $sb.ToString()
}

function Format-PreviewLine([string]$Content, [string]$BgCode, [int]$Width, [int]$LeftPad = 2, [string]$ResetCode = '') {
    $effPad = [Math]::Min($LeftPad, [Math]::Max(0, $Width - 1))
    $clipped = Limit-AnsiLine -Text $Content -MaxCols ([Math]::Max(1, $Width - $effPad))
    $prefix = "${BgCode}$(' ' * $effPad)${clipped}${BgCode}"
    $rem = [Math]::Max(0, $Width - (Get-VisibleLength -Text $prefix))
    return "${prefix}$(' ' * $rem)${ResetCode}"
}

function Format-SwatchStrip([System.Collections.IDictionary]$Theme, [string]$Tier = 'truecolor') {
    $esc = [char]27
    $block = ([string][char]0x2588) * 2
    $sb = [System.Text.StringBuilder]::new(240)
    foreach ($k in $script:SwatchStripKeys) {
        [void]$sb.Append((Format-FgEsc -Hex $Theme[$k] -Tier $Tier))
        [void]$sb.Append($block)
    }
    [void]$sb.Append("${esc}[0m")
    return $sb.ToString()
}

function Get-InteractiveConsoleWidth([int]$Fallback = 120) {
    try {
        if (-not [Console]::IsOutputRedirected -and [Console]::WindowWidth -gt 0) {
            return [Console]::WindowWidth
        }
    } catch {
        $null = $_
    }
    return $Fallback
}

function Show-ThemePreview([System.Collections.IDictionary]$Theme) {
    $fzfCols = if ($env:FZF_PREVIEW_COLUMNS) { $env:FZF_PREVIEW_COLUMNS.Trim() } else { '' }
    $fzfLines = if ($env:FZF_PREVIEW_LINES) { $env:FZF_PREVIEW_LINES.Trim() } else { '' }
    $inFzf = [bool]($fzfCols -and $fzfLines)

    $width = 94
    $parsedW = 0
    if ($fzfCols -and [int]::TryParse($fzfCols, [ref]$parsedW)) {
        $width = [Math]::Max(44, $parsedW)
    } elseif (-not [Console]::IsOutputRedirected) {
        $width = [Math]::Max(44, [Math]::Min(94, (Get-InteractiveConsoleWidth -Fallback 94)))
    }
    $targetHeight = 0
    $parsedH = 0
    if ($fzfLines -and [int]::TryParse($fzfLines, [ref]$parsedH)) {
        $targetHeight = [Math]::Max(24, $parsedH)
    }

    $tier = Get-PreviewColorTier
    $useColor = ($tier -in @('truecolor', '256color'))
    $rst = if ($tier -in @('nocolor', 'mono')) { '' } else { "$([char]27)[0m" }
    $nfOk = Test-UseNerdFont

    $b03  = if ($useColor) { Format-BgEsc -Hex $Theme['BASE03'] -Tier $tier } else { '' }
    $b02  = if ($useColor) { Format-BgEsc -Hex $Theme['BASE02'] -Tier $tier } else { '' }
    $bGrn = if ($useColor) { Format-BgEsc -Hex $Theme['MIX_GREEN'] -Tier $tier } else { '' }
    $bRed = if ($useColor) { Format-BgEsc -Hex $Theme['MIX_RED'] -Tier $tier } else { '' }

    $cB01 = if ($useColor) { Format-FgEsc -Hex $Theme['BASE01'] -Tier $tier } else { '' }
    $cB00 = if ($useColor) { Format-FgEsc -Hex $Theme['BASE00'] -Tier $tier } else { '' }
    $cB0  = if ($useColor) { Format-FgEsc -Hex $Theme['BASE0'] -Tier $tier } else { '' }
    $cB1  = if ($useColor) { Format-FgEsc -Hex $Theme['BASE1'] -Tier $tier } else { '' }
    $cYlw = if ($useColor) { Format-FgEsc -Hex $Theme['YELLOW'] -Tier $tier } else { '' }
    $cOrg = if ($useColor) { Format-FgEsc -Hex $Theme['ORANGE'] -Tier $tier } else { '' }
    $cRed = if ($useColor) { Format-FgEsc -Hex $Theme['RED'] -Tier $tier } else { '' }
    $cMag = if ($useColor) { Format-FgEsc -Hex $Theme['MAGENTA'] -Tier $tier } else { '' }
    $cVio = if ($useColor) { Format-FgEsc -Hex $Theme['VIOLET'] -Tier $tier } else { '' }
    $cBlu = if ($useColor) { Format-FgEsc -Hex $Theme['BLUE'] -Tier $tier } else { '' }
    $cCyn = if ($useColor) { Format-FgEsc -Hex $Theme['CYAN'] -Tier $tier } else { '' }
    $cGrn = if ($useColor) { Format-FgEsc -Hex $Theme['GREEN'] -Tier $tier } else { '' }

    $hmeta = Get-HolidayMeta -Theme $Theme
    if ($hmeta -and $nfOk) {
        $sessionIcon = $hmeta.Icon
        $promptIcon = $hmeta.Icon
    } elseif ($nfOk) {
        $sessionIcon = [string][char]0xEBC8
        $promptIcon = [string][char]0xE62A
    } else {
        $sessionIcon = '*'
        $promptIcon = '$'
    }

    $sepR   = if ($nfOk) { [string][char]0xE0B1 } else { '>' }
    $sepL   = if ($nfOk) { [string][char]0xE0B3 } else { '|' }
    $aiIc   = if ($nfOk) { ([char]::ConvertFromUtf32(0xF06A9)) + ' ' } else { '' }
    $edIc   = if ($nfOk) { ([string][char]0xE6AE) + ' ' } else { '' }
    $shIc   = if ($nfOk) { ([string][char]0xF489) + ' ' } else { '' }
    $gitIc  = if ($nfOk) { ([string][char]0xF113) + ' ' } else { 'git:' }
    $chkIc  = if ($tier -ne 'mono') { [string][char]0x2714 } else { 'ok' }
    $prmIc  = if ($tier -ne 'mono') { [string][char]0x276F } else { '>' }
    $ruleCh = if ($tier -ne 'mono') { [string][char]0x2500 } else { '-' }
    $ptr    = if ($tier -ne 'mono') { [string][char]0x25B8 } else { '>' }
    $midDot = if ($tier -ne 'mono') { [string][char]0x00B7 } else { '|' }
    $emDash = if ($tier -ne 'mono') { [string][char]0x2014 } else { '--' }
    $swGlyph = if ($useColor) { ([string][char]0x2588) * 2 } else { '##' }

    $ruleWidth = [Math]::Max(20, [Math]::Min($width - 4, 88))
    $lines = [System.Collections.Generic.List[string]]::new()

    if ($hmeta -and $nfOk) {
        $lines.Add((Format-PreviewLine -Content "${cYlw}$($hmeta.Banner)" -BgCode $b02 -Width $width -LeftPad 2 -ResetCode $rst))
    }
    $lines.Add((Format-PreviewLine -Content "${cOrg}$($Theme['THEME_LABEL']) ${cB01}($($Theme['THEME_ID']) | $($Theme['THEME_MODE']) | $($Theme['SOURCE']))" -BgCode $b02 -Width $width -LeftPad 2 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cB0}$($Theme['THEME_DESCRIPTION'])" -BgCode $b02 -Width $width -LeftPad 2 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cBlu}Monotone Surface & Content Ramp:" -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))

    $monoKeys = @('BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3')
    $monoCells = foreach ($mk in $monoKeys) {
        $fgSw = if ($useColor) { Format-FgEsc -Hex $Theme[$mk] -Tier $tier } else { '' }
        "${fgSw}${swGlyph} ${cB0}$($mk.ToLowerInvariant()):$($Theme[$mk])"
    }
    if ($width -ge 82) {
        $lines.Add((Format-PreviewLine -Content ($monoCells[0..3] -join '  ') -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
        $lines.Add((Format-PreviewLine -Content ($monoCells[4..7] -join '  ') -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    } else {
        for ($idx = 0; $idx -lt $monoCells.Count; $idx += 2) {
            $lines.Add((Format-PreviewLine -Content ("$($monoCells[$idx])   $($monoCells[$idx + 1])") -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
        }
    }

    $lines.Add((Format-PreviewLine -Content "${cBlu}Semantic Accent Architecture:" -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))
    $roles = @(
        @('YELLOW',  'control flow'),
        @('ORANGE',  'preprocessor / H1'),
        @('RED',     'errors / deletions'),
        @('MAGENTA', 'constants / numbers'),
        @('VIOLET',  'imports / attributes'),
        @('BLUE',    'function defs / H2'),
        @('CYAN',    'strings / escapes'),
        @('GREEN',   'keywords / types')
    )
    if ($width -ge 84) {
        for ($i = 0; $i -lt $roles.Count; $i += 2) {
            $k1 = $roles[$i][0];     $r1 = $roles[$i][1]
            $k2 = $roles[$i + 1][0]; $r2 = $roles[$i + 1][1]
            $c1 = if ($useColor) { Format-FgEsc -Hex $Theme[$k1] -Tier $tier } else { '' }
            $c2 = if ($useColor) { Format-FgEsc -Hex $Theme[$k2] -Tier $tier } else { '' }
            $col1 = "${c1}${swGlyph} ${cB1}$($k1.PadRight(7)) ${cB01}$($Theme[$k1]) ${cB0}($($r1.PadRight(18)))"
            $col2 = "${c2}${swGlyph} ${cB1}$($k2.PadRight(7)) ${cB01}$($Theme[$k2]) ${cB0}($r2)"
            $lines.Add((Format-PreviewLine -Content "$col1   $col2" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
        }
    } elseif ($width -ge 60) {
        for ($i = 0; $i -lt $roles.Count; $i += 2) {
            $k1 = $roles[$i][0]
            $k2 = $roles[$i + 1][0]
            $c1 = if ($useColor) { Format-FgEsc -Hex $Theme[$k1] -Tier $tier } else { '' }
            $c2 = if ($useColor) { Format-FgEsc -Hex $Theme[$k2] -Tier $tier } else { '' }
            $col1 = "${c1}${swGlyph} ${cB1}$($k1.PadRight(7)) ${cB01}$($Theme[$k1])"
            $col2 = "${c2}${swGlyph} ${cB1}$($k2.PadRight(7)) ${cB01}$($Theme[$k2])"
            $lines.Add((Format-PreviewLine -Content "$col1   $col2" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
        }
    } else {
        foreach ($pair in $roles) {
            $kAcc = $pair[0]; $rAcc = $pair[1]
            $cAcc = if ($useColor) { Format-FgEsc -Hex $Theme[$kAcc] -Tier $tier } else { '' }
            $lines.Add((Format-PreviewLine -Content "${cAcc}${swGlyph} ${cB1}$($kAcc.PadRight(7)) ${cB01}$($Theme[$kAcc]) ${cB0}($rAcc)" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
        }
    }

    $lines.Add((Format-PreviewLine -Content "${cB01}$($ruleCh * $ruleWidth)" -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cBlu}Converged Semantic Code Preview:" -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))

    $hBadge = if ($hmeta -and $nfOk) { "  ${cB00}${sepL} ${cYlw}$($hmeta.Badge)" } else { '' }
    $statusPreviewLine = if ($width -lt 88) {
        "${cBlu}${sessionIcon} ide ${cB00}${sepR} ${cCyn}${ptr} ${aiIc}agy ${cB01}${midDot} ${cB0}${edIc}Editor ${cB01}${midDot} ${cB0}${shIc}Shell" +
            $(if ($width -ge 64) { $hBadge } else { '' })
    } else {
        "${cBlu}${sessionIcon} ide ${cB00}${sepR} ${cCyn}${ptr} ${aiIc}agy ${cB1}(Alt+a) ${cB01}${midDot} ${cB0}${edIc}Editor (Alt+e) ${cB01}${midDot} ${cB0}${shIc}Shell (Alt+t)${hBadge}"
    }

    $lines.Add((Format-PreviewLine -Content "${cB01}// $($Theme['THEME_LABEL']) $emDash 6-Pillar Semantic Highlighting" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cOrg}#include ${cCyn}<stdio.h>" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cVio}import ${cVio}core::telemetry${cB0};" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cVio}#[derive(Clone)]" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cGrn}pub fn ${cBlu}classify_sample${cB0}(val: ${cGrn}i64${cB0}) -> ${cB0}Option<${cGrn}bool${cB0}> {" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cYlw}if ${cB0}val >= ${cMag}42 ${cB0}{" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cRed}-   ${cYlw}return ${cB0}Some(${cMag}false${cB0});" -BgCode $bRed -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cGrn}+   ${cYlw}return ${cB0}Some(${cMag}true${cB0});" -BgCode $bGrn -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cB0}}" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cB0}emit_log(${cCyn}`"status: %s\n`"${cB0});" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "    ${cYlw}return ${cMag}None${cB0};" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cB0}}" -BgCode $b03 -Width $width -LeftPad 4 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content $statusPreviewLine -BgCode $b02 -Width $width -LeftPad 2 -ResetCode $rst))
    $lines.Add((Format-PreviewLine -Content "${cB0}${promptIcon} ${cB01}${sepR} ${cBlu}~/windows-settings ${cB01}${sepR} ${cGrn}${gitIc}main ${chkIc} ${cGrn}${prmIc} ${cGrn}theme ${cCyn}$($Theme['THEME_ID'])" -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))

    while ($inFzf -and $targetHeight -gt $lines.Count) {
        $lines.Add((Format-PreviewLine -Content '' -BgCode $b03 -Width $width -LeftPad 2 -ResetCode $rst))
    }

    Write-Output ($lines -join "`n")
    $script:ThemeExitCode = 0
}

function Show-ThemeList([System.Collections.IDictionary]$Themes, [string]$CurrentSlug, [bool]$Plain = $false) {
    $ordered = Get-OrderedThemeSlugList -Themes $Themes
    if ($Plain) {
        foreach ($slug in $ordered) {
            Write-Output $slug
        }
        $script:ThemeExitCode = 0
        return
    }

    $tier = Get-PreviewColorTier
    $isTty = -not [Console]::IsOutputRedirected
    $useColor = $isTty -and ($tier -in @('truecolor', '256color'))
    $nfOk = Test-UseNerdFont

    $ttyCols = 0
    $rawListCols = if ($env:THEME_LIST_COLUMNS) { $env:THEME_LIST_COLUMNS.Trim() } else { '' }
    $parsedCols = 0
    if ($rawListCols -and [int]::TryParse($rawListCols, [ref]$parsedCols) -and $parsedCols -gt 0) {
        $ttyCols = $parsedCols
    } elseif ($isTty) {
        $ttyCols = Get-InteractiveConsoleWidth -Fallback 120
    }

    $emDash = if ($tier -ne 'mono') { [string][char]0x2014 } else { '--' }
    foreach ($slug in $ordered) {
        $t = $Themes[$slug]
        $marker = if ($slug -eq $CurrentSlug) { '*' } else { ' ' }
        $hmeta = Get-HolidayMeta -Theme $t
        $displayLabel = if ($hmeta -and $nfOk) { "$($hmeta.Icon) $($t['THEME_LABEL'])" } else { $t['THEME_LABEL'] }
        $tailText = "$displayLabel $emDash $($t['THEME_DESCRIPTION'])"
        $showStrip = $useColor -and ($ttyCols -eq 0 -or $ttyCols -ge 68)
        $prefixW = 2 + 18 + 1 + 5 + 2 + 7 + 2 + $(if ($showStrip) { 22 } else { 0 })
        if ($ttyCols -gt 0) {
            $remW = [Math]::Max(8, $ttyCols - $prefixW)
            $tailText = Limit-AnsiLine -Text $tailText -MaxCols $remW
        }
        if ($showStrip) {
            $strip = Format-SwatchStrip -Theme $t -Tier $tier
            Write-Output ('{0} {1,-18} {2,-5}  {3,-7}  {4}  {5}' -f $marker, $slug, $t['THEME_MODE'], $t['SOURCE'], $strip, $tailText)
        } else {
            Write-Output ('{0} {1,-18} {2,-5}  {3,-7}  {4}' -f $marker, $slug, $t['THEME_MODE'], $t['SOURCE'], $tailText)
        }
    }
    $script:ThemeExitCode = 0
}

function Test-FzfLoadPosSupport([string]$FzfBin) {
    $ov = if ($env:THEME_FZF_POS) { $env:THEME_FZF_POS.Trim().ToLowerInvariant() } else { '' }
    if ($ov -in @('1', 'true', 'yes', 'on')) { return $true }
    if ($ov -in @('0', 'false', 'no', 'off')) { return $false }
    if ($script:FzfLoadPosCache.ContainsKey($FzfBin)) {
        return $script:FzfLoadPosCache[$FzfBin]
    }
    $supported = $false
    try {
        if ([System.IO.File]::Exists($FzfBin) -and ([System.IO.FileInfo]::new($FzfBin)).Length -gt 65536) {
            $verOut = (& $FzfBin --version 2>$null | Select-Object -First 1)
            if ("$verOut" -match '^\s*(\d+)\.(\d+)') {
                $major = [int]$Matches[1]
                $minor = [int]$Matches[2]
                $supported = ($major -gt 0) -or ($minor -ge 36)
            }
        }
    } catch {
        $supported = $false
    }
    $script:FzfLoadPosCache[$FzfBin] = $supported
    return $supported
}

function Invoke-FzfThemePicker(
    [System.Collections.IDictionary]$Themes,
    [string]$CurrentSlug,
    [string]$RepoDir,
    [bool]$DryRun = $false,
    [bool]$NoLive = $false
) {
    $inWrapper = ($env:THEME_SHELL_WRAPPER -eq '1')
    $fzfCmd = Get-Command fzf.exe, fzf -CommandType Application, ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $fzfCmd) {
        Show-ThemeList -Themes $Themes -CurrentSlug $CurrentSlug -Plain $false
        if ($inWrapper -and $script:ThemeExitCode -eq 0) { $script:ThemeExitCode = 130 }
        return
    }
    $fzfBin = $fzfCmd.Source

    $termCols = 120
    $rawCols = if ($env:COLUMNS) { $env:COLUMNS.Trim() } else { '' }
    $parsedCols = 0
    if ($rawCols -and [int]::TryParse($rawCols, [ref]$parsedCols) -and $parsedCols -gt 0) {
        $termCols = $parsedCols
    } else {
        $termCols = Get-InteractiveConsoleWidth -Fallback 120
    }

    $tier = Get-PreviewColorTier
    $useColor = ($tier -in @('truecolor', '256color'))
    $nfOk = Test-UseNerdFont

    $ordered = @(Get-OrderedThemeSlugList -Themes $Themes)
    $activePos = 1
    $lines = [System.Collections.Generic.List[string]]::new($ordered.Count)
    for ($idx = 0; $idx -lt $ordered.Count; $idx++) {
        $slug = $ordered[$idx]
        if ($slug -eq $CurrentSlug) {
            $activePos = $idx + 1
        }
        $t = $Themes[$slug]
        $activeTag = if ($slug -eq $CurrentSlug) { '(active)' } else { '        ' }
        $hmeta = Get-HolidayMeta -Theme $t
        $displayLabel = if ($hmeta -and $nfOk) { "$($hmeta.Icon) $($t['THEME_LABEL'])" } else { $t['THEME_LABEL'] }
        if ($useColor) {
            $strip = Format-SwatchStrip -Theme $t -Tier $tier
            if ($termCols -lt 76) {
                $lines.Add(('{0,-18}  {1}  {2}  {3}' -f $slug, $activeTag, $strip, $displayLabel))
            } else {
                $lines.Add(('{0,-18}  {1}  {2,-5}  {3,-7}  {4}  {5}' -f $slug, $activeTag, $t['THEME_MODE'], $t['SOURCE'], $strip, $displayLabel))
            }
        } elseif ($termCols -lt 76) {
            $lines.Add(('{0,-18}  {1}  {2}' -f $slug, $activeTag, $displayLabel))
        } else {
            $lines.Add(('{0,-18}  {1}  {2,-5}  {3,-7}  {4}' -f $slug, $activeTag, $t['THEME_MODE'], $t['SOURCE'], $displayLabel))
        }
    }

    if ($termCols -lt 90) {
        $heightArg = '--height=95%'
        $previewWin = '--preview-window=down:58%:nowrap:noinfo'
    } elseif ($termCols -lt 110) {
        $heightArg = '--height=90%'
        $previewWin = '--preview-window=right:56%:nowrap:noinfo'
    } else {
        $heightArg = '--height=80%'
        $previewWin = '--preview-window=right:60%:nowrap:noinfo'
    }

    $sep = if ($tier -eq 'mono') { '|' } else { [string][char]0x00B7 }
    $headerArg = if ($termCols -lt 68) {
        "--header=Enter: apply $sep Esc: cancel"
    } else {
        "--header=Select a color theme (Enter: apply $sep Esc: cancel)"
    }

    $fzfColorArg = switch ($tier) {
        'nocolor'  { '--no-color' }
        'mono'     { '--color=bw' }
        '256color' { '--color=256' }
        '16color'  { '--color=16' }
        default    { Build-FzfColorOptionString -Theme $Themes[$CurrentSlug] -IncludeLayout $false }
    }

    $pwshBin = try {
        $curProcPath = (Get-Process -Id $PID).Path
        if ($curProcPath) { $curProcPath } else { 'pwsh' }
    } catch {
        'pwsh'
    }
    $selfPs1 = Join-Path (Join-Path $RepoDir 'bin') 'theme.ps1'
    $previewCmd = "`"$pwshBin`" -NoLogo -NoProfile -File `"$selfPs1`" --preview {1}"

    $fzfArgs = [System.Collections.Generic.List[string]]@(
        '--ansi',
        '--no-multi',
        '--reverse',
        '--no-scrollbar',
        $heightArg,
        '--border=rounded',
        '--prompt=Theme > ',
        $headerArg,
        "--preview=$previewCmd",
        $previewWin,
        $fzfColorArg
    )
    if ($activePos -gt 1 -and (Test-FzfLoadPosSupport -FzfBin $fzfBin)) {
        $fzfArgs.Add("--bind=load:pos($activePos)")
    }

    $selected = $lines | & $fzfBin @fzfArgs
    if ($LASTEXITCODE -ne 0 -or -not $selected) {
        $script:ThemeExitCode = if ($inWrapper) { 130 } else { 0 }
        return
    }
    $selectedLine = (@($selected) | Select-Object -First 1)
    if (-not $selectedLine -or -not "$selectedLine".Trim()) {
        $script:ThemeExitCode = if ($inWrapper) { 130 } else { 0 }
        return
    }
    $tokens = ("$selectedLine".Trim() -split '\s+')
    $chosenSlug = $(if ($tokens[0] -eq '*' -and $tokens.Count -gt 1) { $tokens[1] } else { $tokens[0] }).Trim().ToLowerInvariant()
    if (-not $Themes.Contains($chosenSlug)) {
        [Console]::Error.WriteLine("theme: unknown theme selected: $chosenSlug")
        $script:ThemeExitCode = 1
        return
    }
    Invoke-ApplyTheme -Theme $Themes[$chosenSlug] -RepoDir $RepoDir -DryRun $DryRun -NoLive $NoLive
}
