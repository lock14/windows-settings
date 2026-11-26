# ==============================================================================
# Palette.ps1 - Schema, dynamic theme discovery, holiday calendar & color math
# ==============================================================================

$script:CoreColorKeys = @(
    'BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3',
    'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN'
)

$script:AllColorKeys = $script:CoreColorKeys + @(
    'BASE04', 'MIX_GREEN', 'MIX_RED', 'MIX_YELLOW', 'MIX_BLUE', 'MIX_MAGENTA', 'MIX_BASE1'
)

# Canonical 16-entry terminal ANSI palette mapping (indices 0 through 15).
# Index 8 is pinned to BASE01, index 9 (ANSI 91) to ORANGE, and index 13 (ANSI 95) to VIOLET.
$script:AnsiRoleOrder = @(
    'BASE02', 'RED', 'GREEN', 'YELLOW', 'BLUE', 'MAGENTA', 'CYAN', 'BASE2',
    'BASE01', 'ORANGE', 'BASE01', 'BASE00', 'BASE0', 'VIOLET', 'BASE1', 'BASE3'
)

$script:SolarizedDarkDefaults = @{
    THEME_ID           = 'solarized-dark'
    THEME_LABEL        = 'Solarized Dark'
    THEME_DESCRIPTION  = 'Ethan Schoonover precision CIELAB dark palette'
    THEME_MODE         = 'dark'
    THEME_CATEGORY     = 'classic'
    THEME_ORDER        = '10'
    BAT_THEME_NAME     = 'Solarized-Dark-TrueColor'
    BTOP_THEME_NAME    = 'solarized_dark'
    GHOSTTY_THEME_NAME = 'Solarized Dark'
    BASE03             = '#002B36'
    BASE02             = '#073642'
    BASE04             = '#002731'
    BASE01             = '#586E75'
    BASE00             = '#657B83'
    BASE0              = '#839496'
    BASE1              = '#93A1A1'
    BASE2              = '#EEE8D5'
    BASE3              = '#FDF6E3'
    YELLOW             = '#B58900'
    ORANGE             = '#CB4B16'
    RED                = '#DC322F'
    MAGENTA            = '#D33682'
    VIOLET             = '#6C71C4'
    BLUE               = '#268BD2'
    CYAN               = '#2AA198'
    GREEN              = '#859900'
    MIX_GREEN          = '#274C25'
    MIX_RED            = '#422D33'
    MIX_YELLOW         = '#364725'
    MIX_BLUE           = '#0B4764'
    MIX_MAGENTA        = '#3E2E4C'
    MIX_BASE1          = '#2C4E56'
}

$script:SolarizedLightDefaults = @{
    THEME_ID           = 'solarized-light'
    THEME_LABEL        = 'Solarized Light'
    THEME_DESCRIPTION  = 'Ethan Schoonover precision CIELAB light palette'
    THEME_MODE         = 'light'
    THEME_CATEGORY     = 'classic'
    THEME_ORDER        = '20'
    BAT_THEME_NAME     = 'Solarized-Light-TrueColor'
    BTOP_THEME_NAME    = 'solarized_light'
    GHOSTTY_THEME_NAME = 'Solarized Light'
    BASE03             = '#FDF6E3'
    BASE02             = '#EEE8D5'
    BASE04             = '#E6DFCA'
    BASE01             = '#93A1A1'
    BASE00             = '#839496'
    BASE0              = '#657B83'
    BASE1              = '#586E75'
    BASE2              = '#073642'
    BASE3              = '#002B36'
    YELLOW             = '#B58900'
    ORANGE             = '#CB4B16'
    RED                = '#DC322F'
    MAGENTA            = '#D33682'
    VIOLET             = '#6C71C4'
    BLUE               = '#268BD2'
    CYAN               = '#2AA198'
    GREEN              = '#859900'
    MIX_GREEN          = '#E5ECD0'
    MIX_RED            = '#F6D8D3'
    MIX_YELLOW         = '#F0E4C0'
    MIX_BLUE           = '#D8E6EE'
    MIX_MAGENTA        = '#F3D9E4'
    MIX_BASE1          = '#E4DEC8'
}

function Get-DefaultThemeRepoDir {
    return (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}

function Get-XdgConfigHome {
    if ($env:XDG_CONFIG_HOME -and $env:XDG_CONFIG_HOME.Trim()) {
        return $env:XDG_CONFIG_HOME.Trim()
    }
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    return (Join-Path $userHome '.config')
}

function Get-UserThemeDirList {
    $dirs = [System.Collections.Generic.List[string]]::new()
    foreach ($ov in @($env:WINDOWS_SETTINGS_USER_THEMES_DIR, $env:HOME_SETTINGS_USER_THEMES_DIR)) {
        if ($ov -and $ov.Trim() -and -not $dirs.Contains($ov.Trim())) {
            $dirs.Add($ov.Trim())
        }
    }
    $cfg = Get-XdgConfigHome
    foreach ($sub in @(
            (Join-Path (Join-Path $cfg 'windows-settings') 'themes'),
            (Join-Path $cfg 'themes'),
            (Join-Path (Join-Path $cfg 'home-settings') 'themes')
        )) {
        if (-not $dirs.Contains($sub)) {
            $dirs.Add($sub)
        }
    }
    return $dirs
}

function Write-TextUtf8NoBom([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not [System.IO.Directory]::Exists($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function ConvertTo-TitleLabel([string]$Slug) {
    $parts = @($Slug -split '[-_]+' | Where-Object { $_ })
    if ($parts.Count -eq 0) { return 'Custom Theme' }
    $titled = foreach ($p in $parts) {
        if ($p.Length -eq 1) {
            $p.ToUpperInvariant()
        } else {
            $p.Substring(0, 1).ToUpperInvariant() + $p.Substring(1).ToLowerInvariant()
        }
    }
    return ($titled -join ' ')
}

function ConvertTo-AsciiGhosttyName([string]$Label) {
    if (-not $Label) { return 'Custom Theme' }
    $decomposed = $Label.Normalize([System.Text.NormalizationForm]::FormKD)
    $sb = [System.Text.StringBuilder]::new($decomposed.Length)
    foreach ($ch in $decomposed.ToCharArray()) {
        $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
        if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark -and [int]$ch -lt 128) {
            [void]$sb.Append($ch)
        }
    }
    $cleaned = [regex]::Replace($sb.ToString(), '[''".]+', '')
    $collapsed = [regex]::Replace($cleaned, '\s+', ' ').Trim()
    if ($collapsed) { return $collapsed }
    return 'Custom Theme'
}

function Get-ThemeSortRecord([System.Collections.IDictionary]$Theme) {
    $srcRank = if ($Theme['SOURCE'] -eq 'builtin') { 0 } else { 1 }
    $defaultCat = if ($srcRank -eq 0) { 'classic' } else { 'user' }
    $cat = if ($Theme.Contains('THEME_CATEGORY') -and $Theme['THEME_CATEGORY']) { [string]$Theme['THEME_CATEGORY'] } else { $defaultCat }
    $catRank = switch ($cat) {
        'classic' { 0 }
        'holiday' { 1 }
        default   { 2 }
    }
    $orderNum = 9999
    if ($Theme.Contains('THEME_ORDER') -and $Theme['THEME_ORDER']) {
        $parsedOrder = 9999
        if ([int]::TryParse([string]$Theme['THEME_ORDER'], [ref]$parsedOrder)) {
            $orderNum = $parsedOrder
        }
    }
    return [pscustomobject]@{
        Slug         = [string]$Theme['THEME_ID']
        SourceRank   = $srcRank
        CategoryRank = $catRank
        OrderNum     = $orderNum
    }
}

function Get-OrderedThemeSlugList([System.Collections.IDictionary]$Themes) {
    $ordered = [System.Collections.Generic.List[string]]::new()
    if ($null -eq $Themes -or $Themes.Count -eq 0) { return $ordered }
    $records = foreach ($key in $Themes.Keys) {
        Get-ThemeSortRecord -Theme $Themes[$key]
    }
    $sorted = $records | Sort-Object -Property SourceRank, CategoryRank, OrderNum, Slug
    foreach ($rec in $sorted) {
        $ordered.Add($rec.Slug)
    }
    return $ordered
}

function Get-HolidayMeta([System.Collections.IDictionary]$Theme) {
    if ($null -eq $Theme) { return $null }
    $icon = if ($Theme.Contains('HOLIDAY_ICON') -and $null -ne $Theme['HOLIDAY_ICON']) { ([string]$Theme['HOLIDAY_ICON']).Trim() } else { '' }
    if (-not $icon) { return $null }
    $label = [string]$Theme['THEME_LABEL']
    $badge = if ($Theme.Contains('HOLIDAY_BADGE') -and $null -ne $Theme['HOLIDAY_BADGE'] -and ([string]$Theme['HOLIDAY_BADGE']).Trim()) {
        ([string]$Theme['HOLIDAY_BADGE']).Trim()
    } else {
        "$icon $label"
    }
    $banner = if ($Theme.Contains('HOLIDAY_BANNER') -and $null -ne $Theme['HOLIDAY_BANNER'] -and ([string]$Theme['HOLIDAY_BANNER']).Trim()) {
        ([string]$Theme['HOLIDAY_BANNER']).Trim()
    } else {
        "$icon  $($label.ToUpperInvariant())  $icon"
    }
    return @{
        Icon   = $icon
        Badge  = $badge
        Banner = $banner
    }
}

function Get-EasterDate([int]$Year) {
    $a = $Year % 19
    $b = [int][Math]::Floor($Year / 100.0)
    $c = $Year % 100
    $d = [int][Math]::Floor($b / 4.0)
    $e = $b % 4
    $f = [int][Math]::Floor(($b + 8) / 25.0)
    $g = [int][Math]::Floor(($b - $f + 1) / 3.0)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [int][Math]::Floor($c / 4.0)
    $k = $c % 4
    $lVal = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    if ($lVal -lt 0) { $lVal += 7 }
    $m = [int][Math]::Floor(($a + 11 * $h + 22 * $lVal) / 451.0)
    $month = [int][Math]::Floor(($h + $lVal - 7 * $m + 114) / 31.0)
    $day = (($h + $lVal - 7 * $m + 114) % 31) + 1
    return [datetime]::new($Year, $month, $day)
}

function Get-ThanksgivingDate([int]$Year) {
    $nov1 = [datetime]::new($Year, 11, 1)
    # .NET DayOfWeek: Sunday=0 .. Thursday=4 .. Saturday=6
    $offset = (4 - [int]$nov1.DayOfWeek + 7) % 7
    return [datetime]::new($Year, 11, 1 + $offset + 21)
}

function Get-NthWeekdayDate([int]$Year, [int]$Month, [int]$Nth, [int]$Weekday) {
    if ($Month -lt 1 -or $Month -gt 12) {
        throw "Invalid month '$Month' in nth-weekday rule (expected 01..12)"
    }
    if ($Weekday -lt 0 -or $Weekday -gt 6) {
        throw "Invalid weekday '$Weekday' in nth-weekday rule (expected 0=Mon..6=Sun)"
    }
    # Map .theme DOW (0=Mon..6=Sun) to .NET DayOfWeek (0=Sun..6=Sat)
    $targetDotNetDow = ($Weekday + 1) % 7
    $daysInMonth = [datetime]::DaysInMonth($Year, $Month)
    if ($Nth -eq -1) {
        $lastDt = [datetime]::new($Year, $Month, $daysInMonth)
        $offset = ([int]$lastDt.DayOfWeek - $targetDotNetDow + 7) % 7
        return [datetime]::new($Year, $Month, $daysInMonth - $offset)
    }
    if ($Nth -lt 1 -or $Nth -gt 5) {
        throw "Invalid nth weekday occurrence '$Nth' (expected 1..5 or -1)"
    }
    $firstDt = [datetime]::new($Year, $Month, 1)
    $offset = ($targetDotNetDow - [int]$firstDt.DayOfWeek + 7) % 7
    $day = 1 + $offset + ($Nth - 1) * 7
    if ($day -gt $daysInMonth) {
        throw "Occurrence '$Nth' of weekday '$Weekday' does not exist in ${Year}-${Month}"
    }
    return [datetime]::new($Year, $Month, $day)
}

function Resolve-HolidayRuleDate([string]$Rule, [int]$Year) {
    $cleaned = $Rule.Trim().ToLowerInvariant()
    if ($cleaned -eq 'easter') {
        return (Get-EasterDate -Year $Year)
    }
    if ($cleaned -eq 'thanksgiving') {
        return (Get-ThanksgivingDate -Year $Year)
    }
    if ($cleaned -match '^(\d{2})-(\d{2})$') {
        $month = [int]$Matches[1]
        $day = [int]$Matches[2]
        if ($month -lt 1 -or $month -gt 12) {
            throw "Invalid HOLIDAY_DATE '$Rule' (month out of range)"
        }
        if ($month -eq 2 -and $day -eq 29 -and -not [datetime]::IsLeapYear($Year)) {
            $day = 28
        }
        if ($day -lt 1 -or $day -gt [datetime]::DaysInMonth($Year, $month)) {
            throw "Invalid HOLIDAY_DATE '$Rule' (day out of range)"
        }
        return [datetime]::new($Year, $month, $day)
    }
    if ($cleaned -match '^nth-weekday:(\d{2}):(-?\d+):([0-6])$') {
        return (Get-NthWeekdayDate -Year $Year -Month ([int]$Matches[1]) -Nth ([int]$Matches[2]) -Weekday ([int]$Matches[3]))
    }
    throw "Invalid HOLIDAY_DATE '$Rule' (expected MM-DD, easter, thanksgiving, or nth-weekday:MM:N:DOW)"
}

function Get-HolidayScheduleForYear([int]$Year, [System.Collections.IDictionary]$Themes = $null, [string]$RepoDir = '') {
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $activeThemes = if ($null -ne $Themes) { $Themes } else { Get-DiscoveredThemeMap -RepoDir $effRepo }
    $rawItems = [System.Collections.Generic.List[object]]::new()
    foreach ($slug in (Get-OrderedThemeSlugList -Themes $activeThemes)) {
        $t = $activeThemes[$slug]
        $rule = if ($t.Contains('HOLIDAY_DATE') -and $t['HOLIDAY_DATE']) { ([string]$t['HOLIDAY_DATE']).Trim() } else { '' }
        if ($rule) {
            $dt = Resolve-HolidayRuleDate -Rule $rule -Year $Year
            $rawItems.Add([pscustomobject]@{ Date = $dt; Slug = $slug })
        }
    }
    return @($rawItems | Sort-Object -Property Date, Slug)
}

function Resolve-NearestHolidaySlug([nullable[datetime]]$Today = $null, [System.Collections.IDictionary]$Themes = $null, [string]$RepoDir = '') {
    $effToday = [datetime]::Today
    if ($null -ne $Today) {
        $effToday = $Today.Value.Date
    } elseif ($env:THEME_HOLIDAY_DATE -and $env:THEME_HOLIDAY_DATE.Trim()) {
        $override = $env:THEME_HOLIDAY_DATE.Trim()
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($override, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            throw "invalid THEME_HOLIDAY_DATE '$override' (expected YYYY-MM-DD)"
        }
        $effToday = $parsed
    }
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $activeThemes = if ($null -ne $Themes) { $Themes } else { Get-DiscoveredThemeMap -RepoDir $effRepo }
    $candidates = @(Get-HolidayScheduleForYear -Year $effToday.Year -Themes $activeThemes -RepoDir $effRepo) +
        @(Get-HolidayScheduleForYear -Year ($effToday.Year + 1) -Themes $activeThemes -RepoDir $effRepo)
    if ($candidates.Count -eq 0) {
        return 'solarized-dark'
    }
    $upcoming = @($candidates | Where-Object { $_.Date -ge $effToday } | Sort-Object -Property Date, Slug)
    if ($upcoming.Count -gt 0) {
        return $upcoming[0].Slug
    }
    return $candidates[0].Slug
}

function ConvertFrom-HexToRgb([string]$Hex) {
    $h = $Hex.Trim().TrimStart('#')
    return @(
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16)
    )
}

function Get-RgbSemi([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb -Hex $Hex
    return "$($rgb[0]);$($rgb[1]);$($rgb[2])"
}

function Get-RgbSpace([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb -Hex $Hex
    return "$($rgb[0]) $($rgb[1]) $($rgb[2])"
}

function Merge-HexColor([string]$FgHex, [string]$BgHex, [double]$Alpha = 0.20) {
    $fg = ConvertFrom-HexToRgb -Hex $FgHex
    $bg = ConvertFrom-HexToRgb -Hex $BgHex
    $r = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[0] * $Alpha + $bg[0] * (1.0 - $Alpha), [MidpointRounding]::ToEven)))
    $g = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[1] * $Alpha + $bg[1] * (1.0 - $Alpha), [MidpointRounding]::ToEven)))
    $b = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[2] * $Alpha + $bg[2] * (1.0 - $Alpha), [MidpointRounding]::ToEven)))
    return ('#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

function Get-RelativeLuminance([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb -Hex $Hex
    $lin = @(0.0, 0.0, 0.0)
    for ($idx = 0; $idx -lt 3; $idx++) {
        $c = $rgb[$idx] / 255.0
        $lin[$idx] = if ($c -le 0.03928) { $c / 12.92 } else { [Math]::Pow(($c + 0.055) / 1.055, 2.4) }
    }
    return (0.2126 * $lin[0] + 0.7152 * $lin[1] + 0.0722 * $lin[2])
}

function Get-ContrastRatio([string]$HexA, [string]$HexB) {
    $lumA = Get-RelativeLuminance -Hex $HexA
    $lumB = Get-RelativeLuminance -Hex $HexB
    $hi = [Math]::Max($lumA, $lumB)
    $lo = [Math]::Min($lumA, $lumB)
    return (($hi + 0.05) / ($lo + 0.05))
}

function Get-RgbDistance([string]$HexA, [string]$HexB) {
    $c1 = ConvertFrom-HexToRgb -Hex $HexA
    $c2 = ConvertFrom-HexToRgb -Hex $HexB
    $rm = ($c1[0] + $c2[0]) / 2.0
    $dr = $c1[0] - $c2[0]
    $dg = $c1[1] - $c2[1]
    $db = $c1[2] - $c2[2]
    return [Math]::Sqrt((2.0 + $rm / 256.0) * $dr * $dr + 4.0 * $dg * $dg + (2.0 + (255.0 - $rm) / 256.0) * $db * $db)
}

function Get-HueDifference([string]$HexA, [string]$HexB) {
    $hues = @(0.0, 0.0)
    $pair = @($HexA, $HexB)
    for ($idx = 0; $idx -lt 2; $idx++) {
        $rgb = ConvertFrom-HexToRgb -Hex $pair[$idx]
        $r = $rgb[0] / 255.0
        $g = $rgb[1] / 255.0
        $b = $rgb[2] / 255.0
        $maxC = [Math]::Max($r, [Math]::Max($g, $b))
        $minC = [Math]::Min($r, [Math]::Min($g, $b))
        if ($maxC -eq $minC) {
            $hues[$idx] = 0.0
        } else {
            $span = $maxC - $minC
            $rc = ($maxC - $r) / $span
            $gc = ($maxC - $g) / $span
            $bc = ($maxC - $b) / $span
            if ($r -eq $maxC) {
                $hRaw = $bc - $gc
            } elseif ($g -eq $maxC) {
                $hRaw = 2.0 + $rc - $bc
            } else {
                $hRaw = 4.0 + $gc - $rc
            }
            $turn = ($hRaw / 6.0) % 1.0
            if ($turn -lt 0.0) { $turn += 1.0 }
            $hues[$idx] = $turn
        }
    }
    $diff = [Math]::Abs($hues[0] - $hues[1]) * 360.0
    return [Math]::Min($diff, 360.0 - $diff)
}

function Get-AnsiPaletteHexList([System.Collections.IDictionary]$Theme, [switch]$Lowercase) {
    $list = [System.Collections.Generic.List[string]]::new(16)
    foreach ($role in $script:AnsiRoleOrder) {
        $hex = [string]$Theme[$role]
        $list.Add($(if ($Lowercase) { $hex.ToLowerInvariant() } else { $hex.ToUpperInvariant() }))
    }
    return $list
}

function Read-ThemeKeyValueMap([string]$Path, [bool]$StrictLines = $true) {
    $raw = @{}
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $s = $lines[$idx].Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        if ($s -match '^export[\s\t]+(.*)$') { $s = $Matches[1].Trim() }
        if ($StrictLines) {
            $eqIdx = $s.IndexOf('=')
            if ($eqIdx -lt 1) {
                throw "${Path}:$($idx + 1): invalid line (expected KEY=VALUE): $s"
            }
            $k = $s.Substring(0, $eqIdx).Trim()
            $v = $s.Substring($eqIdx + 1).Trim()
        } else {
            if ($s -notmatch '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
                continue
            }
            $k = $Matches[1]
            $v = $Matches[2].Trim()
        }
        if ($v.Length -ge 2 -and ($v[0] -eq '"' -or $v[0] -eq "'")) {
            $q = $v[0]
            $endIdx = $v.IndexOf($q, 1)
            if ($endIdx -ge 1) {
                $rest = $v.Substring($endIdx + 1).Trim()
                if (-not $rest -or $rest.StartsWith('#')) {
                    $v = $v.Substring(1, $endIdx - 1)
                }
            }
        } else {
            $v = ($v -split '\s+#', 2)[0].Trim()
        }
        $raw[$k] = $v
    }
    return $raw
}

function ConvertTo-NormalizedTheme([hashtable]$Raw, [string]$OriginLabel, [string]$DefaultSlug, [string]$Source = 'builtin') {
    $mode = if ($Raw.ContainsKey('THEME_MODE')) { $Raw['THEME_MODE'].Trim().ToLowerInvariant() } else { 'dark' }
    if ($mode -notin @('dark', 'light')) {
        throw "${OriginLabel}: invalid THEME_MODE '$mode' (expected 'dark' or 'light')"
    }

    $baseDefaults = if ($mode -eq 'light') { $script:SolarizedLightDefaults } else { $script:SolarizedDarkDefaults }
    $slug = $(if ($Raw.ContainsKey('THEME_ID') -and $Raw['THEME_ID'].Trim()) { $Raw['THEME_ID'] } else { $DefaultSlug }).Trim().ToLowerInvariant().Replace('_', '-')
    $rawLabel = if ($Raw.ContainsKey('THEME_LABEL')) { $Raw['THEME_LABEL'].Trim() } else { '' }
    $label = if ($rawLabel) { $rawLabel } else { ConvertTo-TitleLabel -Slug $slug }
    $desc = $(if ($Raw.ContainsKey('THEME_DESCRIPTION') -and $Raw['THEME_DESCRIPTION'].Trim()) { $Raw['THEME_DESCRIPTION'] } else { "Custom $mode color theme ($label)" }).Trim()

    $holidayDate = if ($Raw.ContainsKey('HOLIDAY_DATE')) { $Raw['HOLIDAY_DATE'].Trim().ToLowerInvariant() } else { '' }
    if ($holidayDate) {
        $null = Resolve-HolidayRuleDate -Rule $holidayDate -Year 2026
    }

    $category = if ($Raw.ContainsKey('THEME_CATEGORY')) { $Raw['THEME_CATEGORY'].Trim().ToLowerInvariant() } else { '' }
    if (-not $category) {
        if ($holidayDate) {
            $category = 'holiday'
        } elseif ($Source -eq 'builtin') {
            $category = 'classic'
        } else {
            $category = 'user'
        }
    }
    if ($category -notin @('classic', 'holiday', 'user')) {
        throw "${OriginLabel}: invalid THEME_CATEGORY '$category' (expected 'classic', 'holiday', or 'user')"
    }

    $rawOrder = if ($Raw.ContainsKey('THEME_ORDER') -and $Raw['THEME_ORDER'].Trim()) { $Raw['THEME_ORDER'].Trim() } else { '9999' }
    $orderInt = 9999
    if (-not [int]::TryParse($rawOrder, [ref]$orderInt)) {
        throw "${OriginLabel}: invalid integer THEME_ORDER '$rawOrder'"
    }

    $theme = @{
        THEME_ID          = $slug
        THEME_LABEL       = $label
        THEME_DESCRIPTION = $desc
        THEME_MODE        = $mode
        THEME_CATEGORY    = $category
        THEME_ORDER       = [string]$orderInt
        HOLIDAY_DATE      = $holidayDate
        HOLIDAY_ICON      = $(if ($Raw.ContainsKey('HOLIDAY_ICON')) { $Raw['HOLIDAY_ICON'].Trim() } else { '' })
        HOLIDAY_BADGE     = $(if ($Raw.ContainsKey('HOLIDAY_BADGE')) { $Raw['HOLIDAY_BADGE'].Trim() } else { '' })
        HOLIDAY_BANNER    = $(if ($Raw.ContainsKey('HOLIDAY_BANNER')) { $Raw['HOLIDAY_BANNER'].Trim() } else { '' })
        SOURCE            = $Source
        PATH              = $OriginLabel
    }

    foreach ($key in $script:CoreColorKeys) {
        $val = $(if ($Raw.ContainsKey($key)) { $Raw[$key] } else { $baseDefaults[$key] }).Trim().ToUpperInvariant()
        if ($val -notmatch '^#[0-9A-F]{6}$') {
            throw "${OriginLabel}: invalid hex color for ${key}: '$val' (expected #RRGGBB)"
        }
        $theme[$key] = $val
    }

    $b03 = $theme['BASE03']
    $b02 = $theme['BASE02']
    $computed = @{
        BASE04      = Merge-HexColor -FgHex $b02 -BgHex $b03 -Alpha 0.50
        MIX_GREEN   = Merge-HexColor -FgHex $theme['GREEN'] -BgHex $b03 -Alpha 0.18
        MIX_RED     = Merge-HexColor -FgHex $theme['RED'] -BgHex $b03 -Alpha 0.18
        MIX_YELLOW  = Merge-HexColor -FgHex $theme['YELLOW'] -BgHex $b03 -Alpha 0.20
        MIX_BLUE    = Merge-HexColor -FgHex $theme['BLUE'] -BgHex $b03 -Alpha 0.22
        MIX_MAGENTA = Merge-HexColor -FgHex $theme['MAGENTA'] -BgHex $b03 -Alpha 0.20
        MIX_BASE1   = Merge-HexColor -FgHex $theme['BASE1'] -BgHex $b03 -Alpha 0.16
    }
    foreach ($key in $computed.Keys) {
        $val = $(if ($Raw.ContainsKey($key)) { $Raw[$key] } else { $computed[$key] }).Trim().ToUpperInvariant()
        if ($val -notmatch '^#[0-9A-F]{6}$') {
            throw "${OriginLabel}: invalid hex color for ${key}: '$val' (expected #RRGGBB)"
        }
        $theme[$key] = $val
    }

    $pascalParts = foreach ($part in ($slug -split '[-_]+' | Where-Object { $_ })) {
        if ($part.Length -eq 1) { $part.ToUpperInvariant() } else { $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1).ToLowerInvariant() }
    }
    $pascalSlug = $pascalParts -join '-'
    $snakeSlug = ($slug -replace '[^a-z0-9]+', '_').Trim('_')
    $theme['BAT_THEME_NAME'] = $(if ($Raw.ContainsKey('BAT_THEME_NAME') -and $Raw['BAT_THEME_NAME'].Trim()) { $Raw['BAT_THEME_NAME'] } else { "${pascalSlug}-TrueColor" }).Trim()
    $theme['BTOP_THEME_NAME'] = $(if ($Raw.ContainsKey('BTOP_THEME_NAME') -and $Raw['BTOP_THEME_NAME'].Trim()) { $Raw['BTOP_THEME_NAME'] } else { $snakeSlug }).Trim()
    $theme['GHOSTTY_THEME_NAME'] = $(if ($Raw.ContainsKey('GHOSTTY_THEME_NAME') -and $Raw['GHOSTTY_THEME_NAME'].Trim()) { $Raw['GHOSTTY_THEME_NAME'] } else { ConvertTo-AsciiGhosttyName -Label $label }).Trim()
    return $theme
}

function Read-ThemeFile([string]$Path, [string]$DefaultSlug = '', [string]$Source = 'builtin') {
    $fallbackSlug = if ($DefaultSlug) { $DefaultSlug } else { [System.IO.Path]::GetFileNameWithoutExtension($Path).ToLowerInvariant() }
    $raw = Read-ThemeKeyValueMap -Path $Path -StrictLines $true
    return (ConvertTo-NormalizedTheme -Raw $raw -OriginLabel $Path -DefaultSlug $fallbackSlug -Source $Source)
}

function Get-BuiltinThemeMap([string]$RepoDir = '') {
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $rawBuiltin = @{}
    $managedDir = Join-Path (Join-Path $effRepo 'config') 'themes'
    if ([System.IO.Directory]::Exists($managedDir)) {
        $files = [System.IO.Directory]::GetFiles($managedDir, '*.theme')
        [Array]::Sort($files, [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($fp in $files) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($fp).ToLowerInvariant()
            $t = Read-ThemeFile -Path $fp -DefaultSlug $stem -Source 'builtin'
            $rawBuiltin[$t['THEME_ID']] = $t
        }
    }
    $orderedMap = [ordered]@{}
    foreach ($slug in (Get-OrderedThemeSlugList -Themes $rawBuiltin)) {
        $orderedMap[$slug] = $rawBuiltin[$slug]
    }
    return $orderedMap
}

function Get-DiscoveredThemeMap([string]$RepoDir = '') {
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $themes = @{}
    $builtin = Get-BuiltinThemeMap -RepoDir $effRepo
    foreach ($k in $builtin.Keys) {
        $themes[$k] = $builtin[$k]
    }
    foreach ($udir in (Get-UserThemeDirList)) {
        if (-not [System.IO.Directory]::Exists($udir)) { continue }
        $candFiles = [System.Collections.Generic.List[string]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($udir, '*.theme')) { $candFiles.Add($f) }
        foreach ($f in [System.IO.Directory]::GetFiles($udir, '*.conf')) { $candFiles.Add($f) }
        $sortedFiles = $candFiles.ToArray()
        [Array]::Sort($sortedFiles, [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($fp in $sortedFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($fp)
            if ($baseName -eq 'active-theme') { continue }
            $t = Read-ThemeFile -Path $fp -DefaultSlug $baseName.ToLowerInvariant() -Source 'user'
            $themes[$t['THEME_ID']] = $t
        }
    }
    $orderedMap = [ordered]@{}
    foreach ($slug in (Get-OrderedThemeSlugList -Themes $themes)) {
        $orderedMap[$slug] = $themes[$slug]
    }
    return $orderedMap
}

function Get-CurrentThemeSlug([System.Collections.IDictionary]$Themes) {
    $cfg = Get-XdgConfigHome
    foreach ($sf in @(
            (Join-Path (Join-Path $cfg 'windows-settings') 'theme'),
            (Join-Path (Join-Path $cfg 'home-settings') 'theme')
        )) {
        if ([System.IO.File]::Exists($sf)) {
            $saved = ([System.IO.File]::ReadAllText($sf, [System.Text.Encoding]::UTF8)).Trim()
            if ($saved) {
                $norm = ($saved -split '\r?\n', 2)[0].Trim().ToLowerInvariant().Replace('_', '-')
                if ($Themes.Contains($norm)) { return $norm }
            }
        }
    }
    foreach ($ev in @($env:WINDOWS_SETTINGS_THEME, $env:HOME_SETTINGS_THEME)) {
        if ($ev -and $ev.Trim()) {
            $norm = $ev.Trim().ToLowerInvariant().Replace('_', '-')
            if ($Themes.Contains($norm)) { return $norm }
        }
    }
    return 'solarized-dark'
}

function Resolve-SingleThemeFast([string]$RawSlug, [string]$RepoDir = '') {
    if (-not $RawSlug -or -not $RawSlug.Trim()) { return $null }
    $slug = $RawSlug.Trim().ToLowerInvariant().Replace('_', '-')
    if ($slug -notmatch '^[a-z0-9][a-z0-9_-]*$') { return $null }
    $snake = $slug.Replace('-', '_')
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $userDirs = Get-UserThemeDirList

    foreach ($udir in $userDirs) {
        if (-not [System.IO.Directory]::Exists($udir)) { continue }
        foreach ($candName in @("$slug.theme", "$snake.theme", "$slug.conf", "$snake.conf")) {
            $up = Join-Path $udir $candName
            if ([System.IO.File]::Exists($up)) {
                $t = Read-ThemeFile -Path $up -DefaultSlug $slug -Source 'user'
                if ($t['THEME_ID'] -eq $slug) { return $t }
            }
        }
    }

    foreach ($udir in $userDirs) {
        if (-not [System.IO.Directory]::Exists($udir)) { continue }
        $candFiles = [System.Collections.Generic.List[string]]::new()
        foreach ($f in [System.IO.Directory]::GetFiles($udir, '*.theme')) { $candFiles.Add($f) }
        foreach ($f in [System.IO.Directory]::GetFiles($udir, '*.conf')) { $candFiles.Add($f) }
        $sortedFiles = $candFiles.ToArray()
        [Array]::Sort($sortedFiles, [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($fp in $sortedFiles) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($fp)
            if ($stem -eq 'active-theme') { continue }
            $kv = Read-ThemeKeyValueMap -Path $fp -StrictLines $false
            $candId = $(if ($kv.ContainsKey('THEME_ID') -and $kv['THEME_ID'].Trim()) { $kv['THEME_ID'] } else { $stem }).Trim().ToLowerInvariant().Replace('_', '-')
            if ($candId -eq $slug) {
                return (Read-ThemeFile -Path $fp -DefaultSlug $stem.ToLowerInvariant() -Source 'user')
            }
        }
    }

    $managedDir = Join-Path (Join-Path $effRepo 'config') 'themes'
    $managedPath = Join-Path $managedDir "$slug.theme"
    if ([System.IO.File]::Exists($managedPath)) {
        return (Read-ThemeFile -Path $managedPath -DefaultSlug $slug -Source 'builtin')
    }
    if ([System.IO.Directory]::Exists($managedDir)) {
        foreach ($fp in [System.IO.Directory]::GetFiles($managedDir, '*.theme')) {
            $stem = [System.IO.Path]::GetFileNameWithoutExtension($fp).ToLowerInvariant()
            $kv = Read-ThemeKeyValueMap -Path $fp -StrictLines $false
            $candId = $(if ($kv.ContainsKey('THEME_ID') -and $kv['THEME_ID'].Trim()) { $kv['THEME_ID'] } else { $stem }).Trim().ToLowerInvariant().Replace('_', '-')
            if ($candId -eq $slug) {
                return (Read-ThemeFile -Path $fp -DefaultSlug $stem -Source 'builtin')
            }
        }
    }

    return $null
}

function Resolve-CurrentSlugFast([string]$RepoDir = '') {
    $effRepo = if ($RepoDir) { $RepoDir } else { Get-DefaultThemeRepoDir }
    $cfg = Get-XdgConfigHome
    $managedDir = Join-Path (Join-Path $effRepo 'config') 'themes'
    foreach ($sf in @(
            (Join-Path (Join-Path $cfg 'windows-settings') 'theme'),
            (Join-Path (Join-Path $cfg 'home-settings') 'theme')
        )) {
        if ([System.IO.File]::Exists($sf)) {
            $saved = ([System.IO.File]::ReadAllText($sf, [System.Text.Encoding]::UTF8)).Trim()
            if ($saved) {
                $norm = ($saved -split '\r?\n', 2)[0].Trim().ToLowerInvariant().Replace('_', '-')
                if ([System.IO.File]::Exists((Join-Path $managedDir "$norm.theme"))) { return $norm }
                if ($null -ne (Resolve-SingleThemeFast -RawSlug $norm -RepoDir $effRepo)) { return $norm }
            }
        }
    }
    foreach ($ev in @($env:WINDOWS_SETTINGS_THEME, $env:HOME_SETTINGS_THEME)) {
        if ($ev -and $ev.Trim()) {
            $norm = $ev.Trim().ToLowerInvariant().Replace('_', '-')
            if ([System.IO.File]::Exists((Join-Path $managedDir "$norm.theme"))) { return $norm }
            if ($null -ne (Resolve-SingleThemeFast -RawSlug $norm -RepoDir $effRepo)) { return $norm }
        }
    }
    return 'solarized-dark'
}

function Initialize-CustomUserTheme(
    [string]$NewName,
    [string]$BaseSlug,
    [System.Collections.IDictionary]$Themes,
    [bool]$Force = $false,
    [bool]$DryRun = $false
) {
    $slug = $NewName.Trim().ToLowerInvariant().Replace('_', '-')
    if ($slug -notmatch '^[a-z0-9][a-z0-9-]*$') {
        [Console]::Error.WriteLine("theme: invalid theme name '$NewName' (use lowercase letters, numbers, and hyphens)")
        $script:ThemeExitCode = 1
        return
    }
    $baseKey = $BaseSlug.Trim().ToLowerInvariant().Replace('_', '-')
    if (-not $Themes.Contains($baseKey)) {
        [Console]::Error.WriteLine("theme: unknown base theme '$BaseSlug'")
        $script:ThemeExitCode = 1
        return
    }
    $base = $Themes[$baseKey]
    $userDir = (Get-UserThemeDirList)[0]
    $targetPath = Join-Path $userDir "$slug.theme"
    if ([System.IO.File]::Exists($targetPath) -and -not $Force) {
        [Console]::Error.WriteLine("theme: custom theme file already exists: $targetPath (use --force to overwrite)")
        $script:ThemeExitCode = 1
        return
    }
    if ($DryRun) {
        Write-Output "[DRY-RUN] Would create custom user theme: $targetPath (from $($base['THEME_ID']))"
        $script:ThemeExitCode = 0
        return
    }

    $label = ConvertTo-TitleLabel -Slug $slug
    $pascalParts = foreach ($part in ($slug -split '-' | Where-Object { $_ })) {
        if ($part.Length -eq 1) { $part.ToUpperInvariant() } else { $part.Substring(0, 1).ToUpperInvariant() + $part.Substring(1) }
    }
    $pascalSlug = $pascalParts -join '-'
    $snakeSlug = $slug.Replace('-', '_')
    $ghosttyName = ConvertTo-AsciiGhosttyName -Label $label
    $content = @"
# Custom User Theme: $slug (based on $($base['THEME_ID']))
THEME_ID="$slug"
THEME_LABEL="$label"
THEME_DESCRIPTION="Custom $($base['THEME_MODE']) theme based on $($base['THEME_LABEL'])"
THEME_MODE="$($base['THEME_MODE'])"
BAT_THEME_NAME="${pascalSlug}-TrueColor"
BTOP_THEME_NAME="$snakeSlug"
GHOSTTY_THEME_NAME="$ghosttyName"

# Monotone Surface & Content Ramp
BASE03="$($base['BASE03'])"
BASE02="$($base['BASE02'])"
BASE04="$($base['BASE04'])"
BASE01="$($base['BASE01'])"
BASE00="$($base['BASE00'])"
BASE0="$($base['BASE0'])"
BASE1="$($base['BASE1'])"
BASE2="$($base['BASE2'])"
BASE3="$($base['BASE3'])"

# Semantic Accent Palette
YELLOW="$($base['YELLOW'])"
ORANGE="$($base['ORANGE'])"
RED="$($base['RED'])"
MAGENTA="$($base['MAGENTA'])"
VIOLET="$($base['VIOLET'])"
BLUE="$($base['BLUE'])"
CYAN="$($base['CYAN'])"
GREEN="$($base['GREEN'])"

# Diff & Search Surface Tints
MIX_GREEN="$($base['MIX_GREEN'])"
MIX_RED="$($base['MIX_RED'])"
MIX_YELLOW="$($base['MIX_YELLOW'])"
MIX_BLUE="$($base['MIX_BLUE'])"
MIX_MAGENTA="$($base['MIX_MAGENTA'])"
MIX_BASE1="$($base['MIX_BASE1'])"
"@
    $lfContent = $content.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    Write-TextUtf8NoBom -Path $targetPath -Content $lfContent
    Write-Output $targetPath
    $script:ThemeExitCode = 0
}

function Build-ThemeUsageText([string]$RootDir) {
    $builtin = @{}
    try {
        $builtin = Get-BuiltinThemeMap -RepoDir $RootDir
    } catch {
        $builtin = @{}
    }
    $slugs = @(Get-OrderedThemeSlugList -Themes $builtin)
    if ($slugs.Count -gt 0) {
        $maxLen = 16
        foreach ($s in $slugs) {
            if ($s.Length -gt $maxLen) { $maxLen = $s.Length }
        }
        $colW = [Math]::Max(18, $maxLen + 2)
        $rows = foreach ($s in $slugs) {
            $defSuffix = if ($s -eq 'solarized-dark') { ' (default)' } else { '' }
            "  {0,-$colW} {1}{2}" -f $s, $builtin[$s]['THEME_LABEL'], $defSuffix
        }
        $managedBlock = $rows -join "`n"
    } else {
        $managedBlock = '  solarized-dark     Solarized Dark (default)'
    }

    return @"
Usage: theme [OPTIONS] [THEME_NAME]

Switch or preview the universal TrueColor color scheme across Windows Terminal,
Zellij, Neovim, Vim, PowerShell, Oh My Posh, CMD, bat, delta, btop4win, tealdeer,
fzf, eza, jq, and dircolors. When invoked with no arguments in an interactive
terminal, opens an fzf picker.

Managed Themes:
$managedBlock

Options:
  -s, --set <NAME>       Apply theme <NAME> across all managed tools
  --holiday              Apply the nearest upcoming or active US Holiday theme
  -l, --list             List all managed and user-defined themes
  --plain                Print theme slugs only (one per line) when listing
  -c, --current          Print the currently active theme name
  -p, --preview [NAME]   Render a TrueColor palette and syntax preview for [NAME]
  --env [NAME]           Output PowerShell environment commands for [NAME]
  --create <NAME>        Create a custom user theme file in the user themes directory
  --from <BASE>          Base theme to copy when used with --create (default: solarized-dark)
  -f, --force            Overwrite existing custom theme file when used with --create
  --path [NAME]          Print the user custom themes directory (or path to [NAME])
  --sync-assets          Regenerate static repository theme assets and bounded blocks
  --check-assets         Verify all derived repository theme assets match .theme specs
  --no-live              Write theme state and configs without signalling running servers
  -n, --dry-run [NAME]   Show files and targets that would be updated without modifying state
  -h, --help             Show this help message and exit
"@
}

function Read-ThemeOptionValue([object[]]$ArgList, [int]$Index, [string]$DisplayOpt, [string]$Noun, [bool]$Optional = $false) {
    $cur = [string]$ArgList[$Index]
    if ($cur.StartsWith('--') -and $cur.Contains('=')) {
        $eqPos = $cur.IndexOf('=')
        $val = $cur.Substring($eqPos + 1)
        if (-not $val.Trim() -or $val.Trim().StartsWith('-')) {
            return @{ Value = $null; NextIndex = $Index; Error = "theme: option '$DisplayOpt' requires $Noun" }
        }
        return @{ Value = $val; NextIndex = $Index; Error = $null }
    }

    if ($Optional) {
        if ($Index + 1 -ge $ArgList.Count) {
            return @{ Value = $null; NextIndex = $Index; Error = $null }
        }
        $nextVal = [string]$ArgList[$Index + 1]
        if (-not $nextVal.Trim() -or $nextVal.StartsWith('-')) {
            return @{ Value = $null; NextIndex = $Index; Error = "theme: option '$cur' requires $Noun" }
        }
        return @{ Value = $nextVal; NextIndex = ($Index + 1); Error = $null }
    }

    if ($Index + 1 -ge $ArgList.Count) {
        return @{ Value = $null; NextIndex = $Index; Error = "theme: option '$cur' requires $Noun" }
    }
    $reqVal = [string]$ArgList[$Index + 1]
    if (-not $reqVal.Trim() -or $reqVal.StartsWith('-')) {
        return @{ Value = $null; NextIndex = $Index; Error = "theme: option '$cur' requires $Noun" }
    }
    return @{ Value = $reqVal; NextIndex = ($Index + 1); Error = $null }
}
