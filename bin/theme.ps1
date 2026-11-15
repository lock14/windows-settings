<#
.SYNOPSIS
    Unified Multi-Theme Color Scheme Manager for windows-settings.
.DESCRIPTION
    Manages the 17 built-in TrueColor themes (9 classic palettes + 8 US Holiday editions)
    and custom user themes across Zellij, Windows Terminal, Neovim (live Named Pipe RPC), Vim,
    PowerShell 7 + PSReadLine, Oh My Posh, Command Prompt (autorun.cmd), bat, delta,
    btop4win, tealdeer, fzf, eza, jq, and GNU dircolors (LS_COLORS).
#>

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoDir = Split-Path -Parent $ScriptDir

$script:ManagedOrder = @(
    'solarized-dark',
    'solarized-light',
    'catppuccin-mocha',
    'catppuccin-latte',
    'gruvbox-dark',
    'tokyonight-night',
    'kanagawa-wave',
    'nord',
    'onedark',
    'new-years',
    'valentines',
    'st-patricks',
    'easter',
    'independence-day',
    'halloween',
    'thanksgiving',
    'christmas'
)

$script:CoreColorKeys = @(
    'BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3',
    'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN'
)

$script:AllColorKeys = $script:CoreColorKeys + @(
    'BASE04', 'MIX_GREEN', 'MIX_RED', 'MIX_YELLOW', 'MIX_BLUE', 'MIX_MAGENTA', 'MIX_BASE1'
)

$script:SolarizedDarkDefaults = @{
    THEME_ID          = 'solarized-dark'
    THEME_LABEL       = 'Solarized Dark'
    THEME_DESCRIPTION = 'Ethan Schoonover precision CIELAB dark palette'
    THEME_MODE        = 'dark'
    BAT_THEME_NAME    = 'Solarized-Dark-TrueColor'
    BTOP_THEME_NAME   = 'solarized_dark'
    GHOSTTY_THEME_NAME = 'Solarized Dark'
    BASE03            = '#002B36'
    BASE02            = '#073642'
    BASE04            = '#002731'
    BASE01            = '#586E75'
    BASE00            = '#657B83'
    BASE0             = '#839496'
    BASE1             = '#93A1A1'
    BASE2             = '#EEE8D5'
    BASE3             = '#FDF6E3'
    YELLOW            = '#B58900'
    ORANGE            = '#CB4B16'
    RED               = '#DC322F'
    MAGENTA           = '#D33682'
    VIOLET            = '#6C71C4'
    BLUE              = '#268BD2'
    CYAN              = '#2AA198'
    GREEN             = '#859900'
    MIX_GREEN         = '#274C25'
    MIX_RED           = '#422D33'
    MIX_YELLOW        = '#364725'
    MIX_BLUE          = '#0B4764'
    MIX_MAGENTA       = '#3E2E4C'
    MIX_BASE1         = '#2C4E56'
}

$script:SolarizedLightDefaults = @{
    THEME_ID          = 'solarized-light'
    THEME_LABEL       = 'Solarized Light'
    THEME_DESCRIPTION = 'Ethan Schoonover precision CIELAB light palette'
    THEME_MODE        = 'light'
    BAT_THEME_NAME    = 'Solarized-Light-TrueColor'
    BTOP_THEME_NAME   = 'solarized_light'
    GHOSTTY_THEME_NAME = 'Solarized Light'
    BASE03            = '#FDF6E3'
    BASE02            = '#EEE8D5'
    BASE04            = '#E6DFCA'
    BASE01            = '#93A1A1'
    BASE00            = '#839496'
    BASE0             = '#657B83'
    BASE1             = '#586E75'
    BASE2             = '#073642'
    BASE3             = '#002B36'
    YELLOW            = '#B58900'
    ORANGE            = '#CB4B16'
    RED               = '#DC322F'
    MAGENTA           = '#D33682'
    VIOLET            = '#6C71C4'
    BLUE              = '#268BD2'
    CYAN              = '#2AA198'
    GREEN             = '#859900'
    MIX_GREEN         = '#E5ECD0'
    MIX_RED           = '#F6D8D3'
    MIX_YELLOW        = '#F0E4C0'
    MIX_BLUE          = '#D8E6EE'
    MIX_MAGENTA       = '#F3D9E4'
    MIX_BASE1         = '#E4DEC8'
}

$script:HolidayMeta = @{
    'new-years'        = @{ Icon = '🥂'; Badge = "🥂 🎆 New Year's";   Banner = '🥂 🎆 🍾  HAPPY NEW YEAR — MIDNIGHT CHAMPAGNE & FIREWORKS  🍾 🎆 🥂' }
    'valentines'       = @{ Icon = '💘'; Badge = "💘 🌹 Valentine's";  Banner = "💘 🌹 💝  HAPPY VALENTINE'S DAY — VELVET ROSE & CHAMPAGNE  💝 🌹 💘" }
    'st-patricks'      = @{ Icon = '🍀'; Badge = "🍀 🪙 St. Patrick's"; Banner = "🍀 🪙 🍺  HAPPY ST. PATRICK'S DAY — SHAMROCK & POT OF GOLD  🍺 🪙 🍀" }
    'easter'           = @{ Icon = '🐣'; Badge = '🐣 🌷 Easter';       Banner = '🐣 🌷 🥚  HAPPY EASTER — SPRING MEADOW & PASTEL BLOSSOMS   🥚 🌷 🐣' }
    'independence-day' = @{ Icon = '🎆'; Badge = '🎆 🗽 4th of July';  Banner = '🎆 🗽 🦅  HAPPY 4TH OF JULY — STARS, STRIPES & FIREWORKS   🦅 🗽 🎆' }
    'halloween'        = @{ Icon = '🎃'; Badge = '🎃 👻 Halloween';    Banner = "🎃 👻 🦇  HAPPY HALLOWEEN — JACK-O'-LANTERN & ECTOPLASM    🦇 👻 🎃" }
    'thanksgiving'     = @{ Icon = '🦃'; Badge = '🦃 🍂 Thanksgiving'; Banner = '🦃 🍂 🥧  HAPPY THANKSGIVING — AUTUMN HARVEST & HEARTH     🥧 🍂 🦃' }
    'christmas'        = @{ Icon = '🎄'; Badge = '🎄 🎅 Christmas';    Banner = '🎄 🎅 🎁  MERRY CHRISTMAS — EVERGREEN, HOLLY & ORNAMENTS   🎁 🎅 🎄' }
}

$script:UsageText = @"
Usage: theme [OPTIONS] [THEME_NAME]

Switch or preview the universal TrueColor color scheme across Windows Terminal,
Neovim, Vim, PowerShell, Oh My Posh, CMD, bat, delta, btop4win, tealdeer, fzf,
eza, jq, and dircolors. When invoked with no arguments in an interactive
terminal, opens an fzf picker.

Managed Themes:
  solarized-dark     Solarized Dark (default)
  solarized-light    Solarized Light
  catppuccin-mocha   Catppuccin Mocha
  catppuccin-latte   Catppuccin Latte
  gruvbox-dark       Gruvbox Dark
  tokyonight-night   TokyoNight Night
  kanagawa-wave      Kanagawa Wave
  nord               Nord
  onedark            OneDark
  new-years          New Year's
  valentines         Valentine's Day
  st-patricks        St. Patrick's Day
  easter             Easter
  independence-day   Independence Day
  halloween          Halloween
  thanksgiving       Thanksgiving
  christmas          Christmas

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
  --path                 Print the user custom themes directory path
  --sync-assets          Regenerate static repository theme assets and re-sync active theme
  --no-live              Write theme state and configs without signalling running servers
  -n, --dry-run [NAME]   Show files and targets that would be updated without modifying state
  -h, --help             Show this help message and exit
"@

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
            (Join-Path $cfg 'themes'),
            (Join-Path (Join-Path $cfg 'windows-settings') 'themes'),
            (Join-Path (Join-Path $cfg 'home-settings') 'themes')
        )) {
        if (-not $dirs.Contains($sub)) {
            $dirs.Add($sub)
        }
    }
    return $dirs
}

function ConvertTo-TitleLabel([string]$Slug) {
    $parts = ($Slug -split '[-_]+') | Where-Object { $_ }
    return (($parts | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant() }) -join ' ')
}

function ConvertFrom-HexToRgb([string]$Hex) {
    $h = $Hex.TrimStart('#')
    return @(
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16)
    )
}

function Get-RgbSemi([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb $Hex
    return "$($rgb[0]);$($rgb[1]);$($rgb[2])"
}

function Get-RgbSpace([string]$Hex) {
    $rgb = ConvertFrom-HexToRgb $Hex
    return "$($rgb[0]) $($rgb[1]) $($rgb[2])"
}

function Merge-HexColor([string]$FgHex, [string]$BgHex, [double]$Alpha = 0.20) {
    $fg = ConvertFrom-HexToRgb $FgHex
    $bg = ConvertFrom-HexToRgb $BgHex
    $r = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[0] * $Alpha + $bg[0] * (1.0 - $Alpha))))
    $g = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[1] * $Alpha + $bg[1] * (1.0 - $Alpha))))
    $b = [Math]::Max(0, [Math]::Min(255, [int][Math]::Round($fg[2] * $Alpha + $bg[2] * (1.0 - $Alpha))))
    return ('#{0:X2}{1:X2}{2:X2}' -f $r, $g, $b)
}

function Get-EasterDate([int]$Year) {
    $a = $Year % 19
    $b = [Math]::Floor($Year / 100)
    $c = $Year % 100
    $d = [Math]::Floor($b / 4)
    $e = $b % 4
    $f = [Math]::Floor(($b + 8) / 25)
    $g = [Math]::Floor(($b - $f + 1) / 3)
    $h = (19 * $a + $b - $d - $g + 15) % 30
    $i = [Math]::Floor($c / 4)
    $k = $c % 4
    $lVal = (32 + 2 * $e + 2 * $i - $h - $k) % 7
    if ($lVal -lt 0) { $lVal += 7 }
    $m = [Math]::Floor(($a + 11 * $h + 22 * $lVal) / 451)
    $month = [int][Math]::Floor(($h + $lVal - 7 * $m + 114) / 31)
    $day = [int]((($h + $lVal - 7 * $m + 114) % 31) + 1)
    return [datetime]::new($Year, $month, $day)
}

function Get-ThanksgivingDate([int]$Year) {
    $nov1 = [datetime]::new($Year, 11, 1)
    # DayOfWeek: Sunday=0 .. Thursday=4 .. Saturday=6
    $offset = (4 - [int]$nov1.DayOfWeek + 7) % 7
    return [datetime]::new($Year, 11, 1 + $offset + 21)
}

function Get-HolidaySchedule([int]$Year) {
    return @(
        @{ Date = [datetime]::new($Year, 1, 1);   Slug = 'new-years' }
        @{ Date = [datetime]::new($Year, 2, 14);  Slug = 'valentines' }
        @{ Date = [datetime]::new($Year, 3, 17);  Slug = 'st-patricks' }
        @{ Date = (Get-EasterDate $Year);         Slug = 'easter' }
        @{ Date = [datetime]::new($Year, 7, 4);   Slug = 'independence-day' }
        @{ Date = [datetime]::new($Year, 10, 31); Slug = 'halloween' }
        @{ Date = (Get-ThanksgivingDate $Year);   Slug = 'thanksgiving' }
        @{ Date = [datetime]::new($Year, 12, 25); Slug = 'christmas' }
    )
}

function Resolve-NearestHolidaySlug {
    $today = [datetime]::Today
    if ($env:THEME_HOLIDAY_DATE -and $env:THEME_HOLIDAY_DATE.Trim()) {
        $override = $env:THEME_HOLIDAY_DATE.Trim()
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($override, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            throw "invalid THEME_HOLIDAY_DATE '$override' (expected YYYY-MM-DD)"
        }
        $today = $parsed
    }
    $candidates = (Get-HolidaySchedule $today.Year) + (Get-HolidaySchedule ($today.Year + 1))
    $upcoming = $candidates | Where-Object { $_.Date -ge $today } | Sort-Object { $_.Date }
    return ($upcoming | Select-Object -First 1).Slug
}

function Read-ThemeFile([string]$Path, [string]$DefaultSlug = '', [string]$Source = 'builtin') {
    $raw = @{}
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.Encoding]::UTF8)
    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $s = $lines[$idx].Trim()
        if (-not $s -or $s.StartsWith('#')) { continue }
        if ($s -match '^export[\s\t]+(.*)$') { $s = $Matches[1].Trim() }
        $eqIdx = $s.IndexOf('=')
        if ($eqIdx -lt 1) {
            throw "${Path}:$($idx + 1): invalid line (expected KEY=VALUE): $s"
        }
        $k = $s.Substring(0, $eqIdx).Trim()
        $v = $s.Substring($eqIdx + 1).Trim()
        if ($v.Length -ge 2 -and ($v[0] -eq '"' -or $v[0] -eq "'")) {
            $q = $v[0]
            $endIdx = $v.IndexOf($q, 1)
            if ($endIdx -gt 0) {
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

    $mode = if ($raw.ContainsKey('THEME_MODE')) { $raw['THEME_MODE'].Trim().ToLowerInvariant() } else { 'dark' }
    if ($mode -notin @('dark', 'light')) {
        throw "${Path}: invalid THEME_MODE '$mode' (expected 'dark' or 'light')"
    }

    $baseDefaults = if ($mode -eq 'light') { $script:SolarizedLightDefaults } else { $script:SolarizedDarkDefaults }
    $fallbackSlug = if ($DefaultSlug) { $DefaultSlug } else { [System.IO.Path]::GetFileNameWithoutExtension($Path).ToLowerInvariant() }
    $slug = $(if ($raw.ContainsKey('THEME_ID')) { $raw['THEME_ID'] } else { $fallbackSlug }).Trim().ToLowerInvariant().Replace('_', '-')
    $label = $(if ($raw.ContainsKey('THEME_LABEL')) { $raw['THEME_LABEL'] } else { ConvertTo-TitleLabel $slug }).Trim()
    $desc = $(if ($raw.ContainsKey('THEME_DESCRIPTION')) { $raw['THEME_DESCRIPTION'] } else { "Custom $mode color theme ($label)" }).Trim()

    $theme = @{
        THEME_ID          = $slug
        THEME_LABEL       = $label
        THEME_DESCRIPTION = $desc
        THEME_MODE        = $mode
        SOURCE            = $Source
        PATH              = $Path
    }

    foreach ($key in $script:CoreColorKeys) {
        $val = $(if ($raw.ContainsKey($key)) { $raw[$key] } else { $baseDefaults[$key] }).Trim().ToUpperInvariant()
        if ($val -notmatch '^#[0-9A-F]{6}$') {
            throw "${Path}: invalid hex color for ${key}: '$val' (expected #RRGGBB)"
        }
        $theme[$key] = $val
    }

    $b03 = $theme['BASE03']
    $b02 = $theme['BASE02']
    $computed = @{
        BASE04      = Merge-HexColor $b02 $b03 0.50
        MIX_GREEN   = Merge-HexColor $theme['GREEN'] $b03 0.18
        MIX_RED     = Merge-HexColor $theme['RED'] $b03 0.18
        MIX_YELLOW  = Merge-HexColor $theme['YELLOW'] $b03 0.20
        MIX_BLUE    = Merge-HexColor $theme['BLUE'] $b03 0.22
        MIX_MAGENTA = Merge-HexColor $theme['MAGENTA'] $b03 0.20
        MIX_BASE1   = Merge-HexColor $theme['BASE1'] $b03 0.16
    }
    foreach ($key in $computed.Keys) {
        $val = $(if ($raw.ContainsKey($key)) { $raw[$key] } else { $computed[$key] }).Trim().ToUpperInvariant()
        if ($val -notmatch '^#[0-9A-F]{6}$') {
            throw "${Path}: invalid hex color for ${key}: '$val' (expected #RRGGBB)"
        }
        $theme[$key] = $val
    }

    $pascalSlug = ((($slug -split '[-_]+') | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant() }) -join '-')
    $snakeSlug = ($slug -replace '[^a-z0-9]+', '_').Trim('_')
    $theme['BAT_THEME_NAME'] = $(if ($raw.ContainsKey('BAT_THEME_NAME')) { $raw['BAT_THEME_NAME'] } else { "${pascalSlug}-TrueColor" }).Trim()
    $theme['BTOP_THEME_NAME'] = $(if ($raw.ContainsKey('BTOP_THEME_NAME')) { $raw['BTOP_THEME_NAME'] } else { $snakeSlug }).Trim()
    $theme['GHOSTTY_THEME_NAME'] = $(if ($raw.ContainsKey('GHOSTTY_THEME_NAME')) { $raw['GHOSTTY_THEME_NAME'] } else { $label }).Trim()
    return $theme
}

function Get-DiscoveredThemeMap {
    $themes = @{}
    $managedDir = Join-Path (Join-Path $RepoDir 'config') 'themes'
    foreach ($slug in $script:ManagedOrder) {
        $p = Join-Path $managedDir "$slug.theme"
        if (Test-Path -LiteralPath $p) {
            $themes[$slug] = Read-ThemeFile -Path $p -DefaultSlug $slug -Source 'builtin'
        }
    }
    if (Test-Path -LiteralPath $managedDir) {
        Get-ChildItem -LiteralPath $managedDir -Filter '*.theme' -File | Sort-Object Name | ForEach-Object {
            $slug = $_.BaseName.ToLowerInvariant()
            if (-not $themes.ContainsKey($slug)) {
                $themes[$slug] = Read-ThemeFile -Path $_.FullName -DefaultSlug $slug -Source 'builtin'
            }
        }
    }
    foreach ($udir in (Get-UserThemeDirList)) {
        if (-not (Test-Path -LiteralPath $udir)) { continue }
        $cands = @(Get-ChildItem -LiteralPath $udir -File | Where-Object { $_.Extension -in @('.theme', '.conf') } | Sort-Object Name)
        foreach ($p in $cands) {
            if ($p.BaseName -eq 'active-theme') { continue }
            $t = Read-ThemeFile -Path $p.FullName -DefaultSlug $p.BaseName.ToLowerInvariant() -Source 'user'
            $themes[$t['THEME_ID']] = $t
        }
    }
    return $themes
}

function Get-CurrentThemeSlug([hashtable]$Themes) {
    $cfg = Get-XdgConfigHome
    foreach ($sf in @(
            (Join-Path (Join-Path $cfg 'windows-settings') 'theme'),
            (Join-Path (Join-Path $cfg 'home-settings') 'theme')
        )) {
        if (Test-Path -LiteralPath $sf) {
            $saved = (Get-Content -LiteralPath $sf -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($saved) {
                $norm = $saved.Trim().ToLowerInvariant().Replace('_', '-')
                if ($Themes.ContainsKey($norm)) { return $norm }
            }
        }
    }
    foreach ($ev in @($env:WINDOWS_SETTINGS_THEME, $env:HOME_SETTINGS_THEME)) {
        if ($ev -and $ev.Trim()) {
            $norm = $ev.Trim().ToLowerInvariant().Replace('_', '-')
            if ($Themes.ContainsKey($norm)) { return $norm }
        }
    }
    return 'solarized-dark'
}

function Resolve-SingleThemeFast([string]$RawSlug) {
    if (-not $RawSlug -or -not $RawSlug.Trim()) { return $null }
    $slug = $RawSlug.Trim().ToLowerInvariant().Replace('_', '-')
    $snake = $slug.Replace('-', '_')
    foreach ($udir in (Get-UserThemeDirList)) {
        if (-not [System.IO.Directory]::Exists($udir)) { continue }
        foreach ($candName in @("$slug.theme", "$snake.theme", "$slug.conf", "$snake.conf")) {
            $up = Join-Path $udir $candName
            if ([System.IO.File]::Exists($up)) {
                $t = Read-ThemeFile -Path $up -DefaultSlug $slug -Source 'user'
                if ($t['THEME_ID'] -eq $slug) { return $t }
            }
        }
    }
    $managedPath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'themes') "$slug.theme"
    if ([System.IO.File]::Exists($managedPath)) {
        return (Read-ThemeFile -Path $managedPath -DefaultSlug $slug -Source 'builtin')
    }
    $all = Get-DiscoveredThemeMap
    if ($all.ContainsKey($slug)) { return $all[$slug] }
    return $null
}

function Resolve-CurrentSlugFast {
    $cfg = Get-XdgConfigHome
    $managedDir = Join-Path (Join-Path $RepoDir 'config') 'themes'
    foreach ($sf in @(
            (Join-Path (Join-Path $cfg 'windows-settings') 'theme'),
            (Join-Path (Join-Path $cfg 'home-settings') 'theme')
        )) {
        if ([System.IO.File]::Exists($sf)) {
            $saved = (Get-Content -LiteralPath $sf -TotalCount 1 -ErrorAction SilentlyContinue)
            if ($saved) {
                $norm = $saved.Trim().ToLowerInvariant().Replace('_', '-')
                if ([System.IO.File]::Exists((Join-Path $managedDir "$norm.theme"))) { return $norm }
                if ($null -ne (Resolve-SingleThemeFast $norm)) { return $norm }
            }
        }
    }
    foreach ($ev in @($env:WINDOWS_SETTINGS_THEME, $env:HOME_SETTINGS_THEME)) {
        if ($ev -and $ev.Trim()) {
            $norm = $ev.Trim().ToLowerInvariant().Replace('_', '-')
            if ([System.IO.File]::Exists((Join-Path $managedDir "$norm.theme"))) { return $norm }
            if ($null -ne (Resolve-SingleThemeFast $norm)) { return $norm }
        }
    }
    return 'solarized-dark'
}

function Write-TextUtf8NoBom([string]$Path, [string]$Content) {
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Build-TrueColorLsColorString([hashtable]$Theme) {
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
    $dcFile = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'colors') 'LS_COLORS'
    $entries = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $dcFile) {
        foreach ($rawLine in [System.IO.File]::ReadAllLines($dcFile)) {
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
        $entries.Add("ex=$($sgrMap['32'])")
        $entries.Add("fi=$base0Sgr")
    }
    return (($entries -join ':') + ':')
}

function Build-EzaColorString([hashtable]$Theme) {
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

function Build-ActiveThemeText([hashtable]$Theme) {
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

function Build-PowerShellThemeEnv([hashtable]$Theme) {
    $ezaStr = Build-EzaColorString $Theme
    $lsStr = Build-TrueColorLsColorString $Theme
    $magenta = Get-RgbSemi $Theme['MAGENTA']
    $cyan = Get-RgbSemi $Theme['CYAN']
    $base0 = Get-RgbSemi $Theme['BASE0']
    $green = Get-RgbSemi $Theme['GREEN']
    $yellow = Get-RgbSemi $Theme['YELLOW']
    $blue = Get-RgbSemi $Theme['BLUE']
    $red = Get-RgbSemi $Theme['RED']
    $base01 = Get-RgbSemi $Theme['BASE01']
    $base02 = Get-RgbSemi $Theme['BASE02']
    $base1 = Get-RgbSemi $Theme['BASE1']

    $fzfStr = "--color=bg+:$($Theme['BASE02']),bg:$($Theme['BASE03']),spinner:$($Theme['GREEN']),hl:$($Theme['BASE01']) --color=fg:$($Theme['BASE0']),header:$($Theme['BASE01']),info:$($Theme['YELLOW']),pointer:$($Theme['GREEN']) --color=marker:$($Theme['GREEN']),fg+:$($Theme['BASE1']),prompt:$($Theme['YELLOW']),hl+:$($Theme['BLUE']) --layout=reverse --border=rounded --info=inline"
    $jqStr = "38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${cyan}:38;2;${base0}:38;2;${base0}:38;2;${green}"
    $hmeta = $script:HolidayMeta[$Theme['THEME_ID']]
    $osIconStmt = if ($hmeta) { "`$env:_HS_PROMPT_OS_ICON = '$($hmeta.Icon)'" } else { 'Remove-Item Env:_HS_PROMPT_OS_ICON -ErrorAction SilentlyContinue' }

    return @"
# Generated by bin/theme.ps1 — Active Theme: $($Theme['THEME_ID'])
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
`$env:LESS_TERMCAP_mb = "``e[38;2;${red}m"
`$env:LESS_TERMCAP_md = "``e[1;38;2;${blue}m"
`$env:LESS_TERMCAP_me = "``e[0m"
`$env:LESS_TERMCAP_so = "``e[38;2;${base1};48;2;${base02}m"
`$env:LESS_TERMCAP_se = "``e[0m"
`$env:LESS_TERMCAP_us = "``e[4;38;2;${cyan}m"
`$env:LESS_TERMCAP_ue = "``e[0m"
`$env:_HS_ESC_BASE0 = "``e[38;2;${base0}m"
`$env:_HS_ESC_BASE01 = "``e[38;2;${base01}m"
`$env:_HS_ESC_BG_BASE02 = "``e[48;2;${base02}m"
`$env:_HS_ESC_GREEN = "``e[38;2;${green}m"
`$env:_HS_ESC_YELLOW = "``e[38;2;${yellow}m"
`$env:_HS_ESC_CYAN = "``e[38;2;${cyan}m"
`$env:_HS_ESC_MAGENTA = "``e[38;2;${magenta}m"
`$env:_HS_ESC_BLUE = "``e[38;2;${blue}m"
`$env:_HS_ESC_RED = "``e[38;2;${red}m"
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
}

function Build-CmdThemeEnv([hashtable]$Theme) {
    $ezaStr = Build-EzaColorString $Theme
    $lsStr = Build-TrueColorLsColorString $Theme
    $magenta = Get-RgbSemi $Theme['MAGENTA']
    $cyan = Get-RgbSemi $Theme['CYAN']
    $base0 = Get-RgbSemi $Theme['BASE0']
    $green = Get-RgbSemi $Theme['GREEN']
    $blue = Get-RgbSemi $Theme['BLUE']
    $base01 = Get-RgbSemi $Theme['BASE01']
    $base02 = Get-RgbSemi $Theme['BASE02']
    $fzfStr = "--color=bg+:$($Theme['BASE02']),bg:$($Theme['BASE03']),spinner:$($Theme['GREEN']),hl:$($Theme['BASE01']) --color=fg:$($Theme['BASE0']),header:$($Theme['BASE01']),info:$($Theme['YELLOW']),pointer:$($Theme['GREEN']) --color=marker:$($Theme['GREEN']),fg+:$($Theme['BASE1']),prompt:$($Theme['YELLOW']),hl+:$($Theme['BLUE']) --layout=reverse --border=rounded --info=inline"
    $jqStr = "38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${magenta}:38;2;${cyan}:38;2;${base0}:38;2;${base0}:38;2;${green}"
    $hmeta = $script:HolidayMeta[$Theme['THEME_ID']]
    $promptIcon = if ($hmeta) { $hmeta.Icon } else { '' }

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
prompt `$E[48;2;${base02}m`$E[38;2;${base0}m $promptIcon `$E[38;2;${base01}m`$E[38;2;${blue}m  `$P `$E[0m`$E[38;2;${base02}m`$E[0m`$S
"@
    return ([regex]::Replace($body, "`r?`n", "`r`n") + "`r`n")
}

function Build-DeltaGitConfig([hashtable]$Theme) {
    $lightVal = if ($Theme['THEME_MODE'] -eq 'light') { 'true' } else { 'false' }
    if ($Theme['THEME_ID'] -eq 'solarized-dark') {
        $plusBg = '#0d3834'
        $plusEmphBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $minusBg = '#2d222a'
        $minusEmphBg = $Theme['MIX_RED'].ToLowerInvariant()
    } elseif ($script:HolidayMeta.ContainsKey($Theme['THEME_ID'])) {
        $plusBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $plusSeed = if ($Theme['THEME_MODE'] -eq 'light') { '#009E3D' } else { '#2EE66B' }
        $plusEmphBg = (Merge-HexColor $plusSeed $Theme['MIX_GREEN'] 0.28).ToLowerInvariant()
        $minusBg = $Theme['MIX_RED'].ToLowerInvariant()
        $minusEmphBg = (Merge-HexColor $Theme['RED'] $Theme['MIX_RED'] 0.28).ToLowerInvariant()
    } else {
        $plusBg = $Theme['MIX_GREEN'].ToLowerInvariant()
        $plusEmphBg = (Merge-HexColor $Theme['GREEN'] $Theme['BASE03'] 0.30).ToLowerInvariant()
        $minusBg = $Theme['MIX_RED'].ToLowerInvariant()
        $minusEmphBg = (Merge-HexColor $Theme['RED'] $Theme['BASE03'] 0.30).ToLowerInvariant()
    }
    $mag = $Theme['MAGENTA'].ToLowerInvariant()
    $cyn = $Theme['CYAN'].ToLowerInvariant()
    $b01 = $Theme['BASE01'].ToLowerInvariant()
    $blu = $Theme['BLUE'].ToLowerInvariant()
    $grn = $Theme['GREEN'].ToLowerInvariant()
    $red = $Theme['RED'].ToLowerInvariant()

    return @"
# Git Delta configuration — $($Theme['THEME_LABEL']) TrueColor
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
}

function Build-TealdeerConfig([hashtable]$Theme) {
    $b0 = ConvertFrom-HexToRgb $Theme['BASE0']
    $gr = ConvertFrom-HexToRgb $Theme['GREEN']
    $cy = ConvertFrom-HexToRgb $Theme['CYAN']
    $bl = ConvertFrom-HexToRgb $Theme['BLUE']
    $mg = ConvertFrom-HexToRgb $Theme['MAGENTA']
    return @"
# tealdeer (tldr) configuration — $($Theme['THEME_LABEL']) TrueColor
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
}

function Build-BtopThemeText([hashtable]$Theme) {
    return @"
# $($Theme['THEME_LABEL']) TrueColor theme for btop / btop4win
theme[main_bg]="$($Theme['BASE03'].ToLowerInvariant())"
theme[main_fg]="$($Theme['BASE0'].ToLowerInvariant())"
theme[title]="$($Theme['BASE1'].ToLowerInvariant())"
theme[hi_fg]="$($Theme['YELLOW'].ToLowerInvariant())"
theme[selected_bg]="$($Theme['BASE02'].ToLowerInvariant())"
theme[selected_fg]="$($Theme['BASE1'].ToLowerInvariant())"
theme[inactive_fg]="$($Theme['BASE01'].ToLowerInvariant())"
theme[graph_text]="$($Theme['BASE00'].ToLowerInvariant())"
theme[meter_bg]="$($Theme['BASE02'].ToLowerInvariant())"
theme[proc_misc]="$($Theme['GREEN'].ToLowerInvariant())"
theme[cpu_box]="$($Theme['BASE01'].ToLowerInvariant())"
theme[mem_box]="$($Theme['BASE01'].ToLowerInvariant())"
theme[net_box]="$($Theme['BASE01'].ToLowerInvariant())"
theme[proc_box]="$($Theme['BASE01'].ToLowerInvariant())"
theme[div_line]="$($Theme['BASE01'].ToLowerInvariant())"
theme[temp_start]="$($Theme['GREEN'].ToLowerInvariant())"
theme[temp_mid]="$($Theme['YELLOW'].ToLowerInvariant())"
theme[temp_end]="$($Theme['RED'].ToLowerInvariant())"
theme[cpu_start]="$($Theme['GREEN'].ToLowerInvariant())"
theme[cpu_mid]="$($Theme['CYAN'].ToLowerInvariant())"
theme[cpu_end]="$($Theme['BLUE'].ToLowerInvariant())"
theme[free_start]="$($Theme['BASE01'].ToLowerInvariant())"
theme[free_mid]="$($Theme['BASE00'].ToLowerInvariant())"
theme[free_end]="$($Theme['BASE0'].ToLowerInvariant())"
theme[cached_start]="$($Theme['CYAN'].ToLowerInvariant())"
theme[cached_mid]="$($Theme['BLUE'].ToLowerInvariant())"
theme[cached_end]="$($Theme['VIOLET'].ToLowerInvariant())"
theme[available_start]="$($Theme['GREEN'].ToLowerInvariant())"
theme[available_mid]="$($Theme['CYAN'].ToLowerInvariant())"
theme[available_end]="$($Theme['BLUE'].ToLowerInvariant())"
theme[used_start]="$($Theme['YELLOW'].ToLowerInvariant())"
theme[used_mid]="$($Theme['ORANGE'].ToLowerInvariant())"
theme[used_end]="$($Theme['RED'].ToLowerInvariant())"
theme[download_start]="$($Theme['CYAN'].ToLowerInvariant())"
theme[download_mid]="$($Theme['BLUE'].ToLowerInvariant())"
theme[download_end]="$($Theme['VIOLET'].ToLowerInvariant())"
theme[upload_start]="$($Theme['GREEN'].ToLowerInvariant())"
theme[upload_mid]="$($Theme['YELLOW'].ToLowerInvariant())"
theme[upload_end]="$($Theme['ORANGE'].ToLowerInvariant())"
theme[process_start]="$($Theme['GREEN'].ToLowerInvariant())"
theme[process_mid]="$($Theme['YELLOW'].ToLowerInvariant())"
theme[process_end]="$($Theme['RED'].ToLowerInvariant())"
"@
}

function Build-ZellijThemeKdl([hashtable]$Theme) {
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
    $kdl = @"
// Auto-generated by windows-settings bin/theme.ps1 ($($Theme['THEME_LABEL']))
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
    return ($kdl.Replace("`r`n", "`n") + "`n")
}

function Sync-ZellijConfigThemeBlock([string]$ConfigPath, [hashtable]$Theme) {
    if (-not $ConfigPath -or -not (Test-Path -LiteralPath $ConfigPath)) { return }
    $raw = (Get-Content -LiteralPath $ConfigPath -Raw).Replace("`r`n", "`n")
    $trayBlock = @"
    // BEGIN WINDOWS-SETTINGS TRAY COLORS
    tray_badge_colors {
        needs_you "$($Theme['ORANGE'])"
        failed "$($Theme['RED'])"
        done "$($Theme['GREEN'])"
        working "$($Theme['BLUE'])"
        quiet "$($Theme['BASE01'])"
        new_output "$($Theme['CYAN'])"
    }
    // END WINDOWS-SETTINGS TRAY COLORS
"@.Replace("`r`n", "`n")

    $termBlock = @"
    // BEGIN WINDOWS-SETTINGS TERMINAL THEME
    theme {
        foreground "$($Theme['BASE0'])"
        background "$($Theme['BASE03'])"
        cursor "$($Theme['BASE0'])"
        black "$($Theme['BASE02'])"
        red "$($Theme['RED'])"
        green "$($Theme['GREEN'])"
        yellow "$($Theme['YELLOW'])"
        blue "$($Theme['BLUE'])"
        magenta "$($Theme['MAGENTA'])"
        cyan "$($Theme['CYAN'])"
        white "$($Theme['BASE2'])"
        bright_black "$($Theme['BASE01'])"
        bright_red "$($Theme['ORANGE'])"
        bright_green "$($Theme['BASE01'])"
        bright_yellow "$($Theme['BASE00'])"
        bright_blue "$($Theme['BASE0'])"
        bright_magenta "$($Theme['VIOLET'])"
        bright_cyan "$($Theme['BASE1'])"
        bright_white "$($Theme['BASE3'])"
    }
    // END WINDOWS-SETTINGS TERMINAL THEME
"@.Replace("`r`n", "`n")

    $updated = [regex]::Replace($raw, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TRAY COLORS.*?// END WINDOWS-SETTINGS TRAY COLORS', $trayBlock)
    $updated = [regex]::Replace($updated, '(?s)[ \t]*// BEGIN WINDOWS-SETTINGS TERMINAL THEME.*?// END WINDOWS-SETTINGS TERMINAL THEME', $termBlock)
    if ($updated -ne $raw) {
        Write-TextUtf8NoBom -Path $ConfigPath -Content $updated
    }
}

function Build-TmThemeText([string]$BaseTmThemeText, [hashtable]$Theme) {
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
    $out = $BaseTmThemeText
    foreach ($hex in $slotMap.Keys) {
        $out = [regex]::Replace($out, [regex]::Escape($hex), $slotMap[$hex], [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    foreach ($tok in $valMap.Keys) {
        $out = $out.Replace($tok, $valMap[$tok])
    }
    $out = $out.Replace('<string>Solarized-Dark-TrueColor</string>', "<string>$($Theme['BAT_THEME_NAME'])</string>")
    return $out
}

function Convert-SolarizedHexString([string]$InputText, [hashtable]$Theme, [bool]$Lowercase = $true) {
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

function ConvertTo-WindowsTerminalScheme([hashtable]$Theme) {
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

function Sync-WindowsTerminalTheme([hashtable]$Theme, [hashtable]$AllThemes) {
    $null = $AllThemes
    if ($env:THEME_UPDATE_TERMINAL_PROFILE -eq '0' -or -not $env:LOCALAPPDATA) { return }

    # 1. Update deployed Windows Terminal Fragment
    $fragDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\WindowsSettings'
    $fragPath = Join-Path $fragDir 'windows-settings.json'
    $repoFragPath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'terminal') 'windows-settings.json'
    if (Test-Path -LiteralPath $repoFragPath) {
        try {
            $fragObj = Get-Content -LiteralPath $repoFragPath -Raw | ConvertFrom-Json
            $fragObj.profiles.defaults.colorScheme = $Theme['GHOSTTY_THEME_NAME']
            $fragObj.profiles.defaults.cursorColor = $Theme['BASE0']
            if ($Theme['SOURCE'] -eq 'user') {
                $existingNames = @($fragObj.schemes | ForEach-Object { $_.name })
                if ($Theme['GHOSTTY_THEME_NAME'] -notin $existingNames) {
                    $fragObj.schemes = @($fragObj.schemes) + @([pscustomobject](ConvertTo-WindowsTerminalScheme $Theme))
                }
            }
            New-Item -ItemType Directory -Force -Path $fragDir | Out-Null
            Write-TextUtf8NoBom -Path $fragPath -Content (($fragObj | ConvertTo-Json -Depth 10) + "`n")
        } catch {
            Write-Verbose "Windows Terminal fragment update skipped: $_"
        }
    }

    # 2. If user's active Windows Terminal settings.json explicitly sets profiles.defaults.colorScheme,
    #    update it and ensure the scheme definition exists so Fragment precedence isn't shadowed.
    $wtCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    foreach ($wtPath in $wtCandidates) {
        if (-not (Test-Path -LiteralPath $wtPath)) { continue }
        try {
            $wtObj = Get-Content -LiteralPath $wtPath -Raw | ConvertFrom-Json
            if ($wtObj.profiles -and $wtObj.profiles.defaults) {
                $wtObj.profiles.defaults | Add-Member -NotePropertyName colorScheme -NotePropertyValue $Theme['GHOSTTY_THEME_NAME'] -Force
                $wtObj.profiles.defaults | Add-Member -NotePropertyName cursorColor -NotePropertyValue $Theme['BASE0'] -Force
                $schemesList = [System.Collections.Generic.List[object]]::new()
                if ($wtObj.schemes) {
                    foreach ($s in $wtObj.schemes) {
                        if ($s.name -ne $Theme['GHOSTTY_THEME_NAME']) {
                            $schemesList.Add($s)
                        }
                    }
                }
                $schemesList.Add([pscustomobject](ConvertTo-WindowsTerminalScheme $Theme))
                $wtObj | Add-Member -NotePropertyName schemes -NotePropertyValue $schemesList.ToArray() -Force
                Write-TextUtf8NoBom -Path $wtPath -Content (($wtObj | ConvertTo-Json -Depth 16) + "`n")
            }
        } catch {
            Write-Verbose "Windows Terminal settings.json update skipped for ${wtPath}: $_"
        }
    }
}

function Send-LiveOscSequence([hashtable]$Theme) {
    $forceOsc = ($env:THEME_FORCE_OSC -eq '1')
    $isInteractive = (-not [Console]::IsOutputRedirected) -or $forceOsc
    if (-not $isInteractive -or $env:NO_COLOR) { return }

    $esc = [char]27
    $bel = [char]7
    $slots = @(
        @(0, $Theme['BASE02']), @(1, $Theme['RED']),    @(2, $Theme['GREEN']),  @(3, $Theme['YELLOW']),
        @(4, $Theme['BLUE']),   @(5, $Theme['MAGENTA']), @(6, $Theme['CYAN']),   @(7, $Theme['BASE2']),
        @(8, $Theme['BASE01']), @(9, $Theme['ORANGE']), @(10, $Theme['BASE01']), @(11, $Theme['BASE00']),
        @(12, $Theme['BASE0']), @(13, $Theme['VIOLET']), @(14, $Theme['BASE1']), @(15, $Theme['BASE3'])
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append("${esc}]10;$($Theme['BASE0'])${bel}")
    [void]$sb.Append("${esc}]11;$($Theme['BASE03'])${bel}")
    [void]$sb.Append("${esc}]12;$($Theme['BASE0'])${bel}")
    foreach ($pair in $slots) {
        [void]$sb.Append("${esc}]4;$($pair[0]);$($pair[1])${bel}")
    }
    try {
        [Console]::Write($sb.ToString())
    } catch {
        Write-Verbose "OSC sequence write skipped: $_"
    }
}

function Send-LiveNeovimReload {
    if ($env:THEME_LIVE_NVIM -eq '0') { return }
    $nvimCmd = Get-Command nvim.exe, nvim -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $nvimCmd) { return }
    $nvimExe = $nvimCmd.Source
    if ($nvimExe -match '(?i)[\\/]mise[\\/]shims[\\/]') {
        $miseRoot = Split-Path -Parent (Split-Path -Parent $nvimExe)
        $nvimInstDir = Join-Path (Join-Path $miseRoot 'installs') 'neovim'
        if ([System.IO.Directory]::Exists($nvimInstDir)) {
            $directHit = Get-ChildItem -LiteralPath $nvimInstDir -Filter 'nvim.exe' -Recurse -File -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -First 1
            if ($directHit) { $nvimExe = $directHit.FullName }
        }
    }

    $skipPipe = if ($env:THEME_SKIP_NVIM_SOCKET) { $env:THEME_SKIP_NVIM_SOCKET.Trim() } else { '' }
    $pipes = [System.Collections.Generic.List[string]]::new()
    if ($env:NVIM_IDE_SOCKET -and $env:NVIM_IDE_SOCKET.Trim()) {
        $pipes.Add($env:NVIM_IDE_SOCKET.Trim())
    }
    try {
        foreach ($p in [System.IO.Directory]::GetFiles('\\.\pipe\')) {
            if ($p -match '(?i)nvim' -and -not $pipes.Contains($p)) {
                $pipes.Add($p)
            }
        }
    } catch {
        Write-Verbose "Named pipe scan skipped: $_"
    }

    foreach ($pipe in $pipes) {
        if ($skipPipe -and $pipe -eq $skipPipe) { continue }
        try {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $psi.FileName = $nvimExe
            $psi.ArgumentList.Add('--headless')
            $psi.ArgumentList.Add('--server')
            $psi.ArgumentList.Add($pipe)
            $psi.ArgumentList.Add('--remote-expr')
            $psi.ArgumentList.Add('v:lua.apply_home_settings_theme()')
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            if ($proc) {
                if (-not $proc.WaitForExit(2500)) {
                    try { $proc.Kill() } catch { Write-Verbose "Kill timed-out nvim rpc skipped" }
                }
            }
        } catch {
            Write-Verbose "Neovim RPC reload skipped on ${pipe}: $_"
        }
    }
}

function Invoke-ApplyTheme([hashtable]$Theme, [hashtable]$AllThemes, [bool]$DryRun = $false, [bool]$NoLive = $false) {
    $userHome = if ($HOME) { $HOME } else { $env:USERPROFILE }
    $cfgDir = Get-XdgConfigHome
    $hsStateDir = Join-Path $cfgDir 'home-settings'
    $wsStateDir = Join-Path $cfgDir 'windows-settings'
    $psCacheDir = Join-Path (Join-Path $userHome '.cache') 'powershell'
    $batConfigDir = if ($env:BAT_CONFIG_DIR) { $env:BAT_CONFIG_DIR } elseif ($env:APPDATA) { Join-Path $env:APPDATA 'bat' } else { Join-Path $cfgDir 'bat' }
    $batThemesDir = Join-Path $batConfigDir 'themes'
    $tealdeerDir = if ($env:APPDATA) { Join-Path $env:APPDATA 'tealdeer' } else { Join-Path $cfgDir 'tealdeer' }
    $zellijConfigDir = if ($env:ZELLIJ_CONFIG_DIR -and $env:ZELLIJ_CONFIG_DIR.Trim()) {
        $env:ZELLIJ_CONFIG_DIR.Trim()
    } elseif ($env:APPDATA) {
        Join-Path (Join-Path $env:APPDATA 'Zellij') 'config'
    } else {
        Join-Path $cfgDir 'zellij'
    }
    $zellijThemePath = Join-Path (Join-Path $zellijConfigDir 'themes') 'windows-settings.kdl'
    $ompDest = Join-Path (Join-Path $userHome '.poshthemes') 'p10k_single_line.omp.json'
    $cmdThemeEnv = if ($env:LOCALAPPDATA) { Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'theme_env.cmd' } else { Join-Path $wsStateDir 'theme_env.cmd' }

    if ($DryRun) {
        Write-Output "[DRY-RUN] Theme: $($Theme['THEME_LABEL']) ($($Theme['THEME_ID']), mode=$($Theme['THEME_MODE']), source=$($Theme['SOURCE']))"
        Write-Output "[DRY-RUN] Would write active state: $(Join-Path $wsStateDir 'theme') & $(Join-Path $hsStateDir 'theme')"
        Write-Output "[DRY-RUN] Would write active palette: $(Join-Path $hsStateDir 'active-theme.theme')"
        Write-Output "[DRY-RUN] Would write PowerShell cache: $(Join-Path $psCacheDir 'theme_env.ps1')"
        Write-Output "[DRY-RUN] Would write CMD theme hook: $cmdThemeEnv"
        Write-Output "[DRY-RUN] Would update Oh My Posh theme: $ompDest"
        Write-Output "[DRY-RUN] Would update Zellij theme: $zellijThemePath"
        Write-Output "[DRY-RUN] Would update Git delta config ($($Theme['BAT_THEME_NAME'])): $(Join-Path (Join-Path $cfgDir 'git') 'delta-theme.gitconfig')"
        Write-Output "[DRY-RUN] Would update tealdeer config: $(Join-Path $tealdeerDir 'config.toml')"
        Write-Output "[DRY-RUN] Would ensure bat theme: $(Join-Path $batThemesDir "$($Theme['BAT_THEME_NAME']).tmTheme")"
        Write-Output "[DRY-RUN] Would update Windows Terminal scheme ($($Theme['GHOSTTY_THEME_NAME'])) and broadcast Neovim RPC / OSC palette"
        return
    }

    $activeSnapshot = Build-ActiveThemeText $Theme
    foreach ($sdir in @($wsStateDir, $hsStateDir)) {
        Write-TextUtf8NoBom -Path (Join-Path $sdir 'theme') -Content "$($Theme['THEME_ID'])`n"
        Write-TextUtf8NoBom -Path (Join-Path $sdir 'active-theme.theme') -Content $activeSnapshot
    }

    $psEnvText = Build-PowerShellThemeEnv $Theme
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'theme-env.ps1') -Content $psEnvText
    Write-TextUtf8NoBom -Path (Join-Path $psCacheDir 'theme_env.ps1') -Content $psEnvText
    $ideScriptPath = Join-Path (Join-Path $RepoDir 'bin') 'ide.ps1'
    if (Test-Path -LiteralPath $ideScriptPath -PathType Leaf) {
        try {
            . (Join-Path $psCacheDir 'theme_env.ps1')
            & $ideScriptPath --write-keys-cache *> $null
        } catch {
            Write-Verbose "IDE cheatsheet cache refresh skipped: $_"
        }
    }

    $cmdEnvText = Build-CmdThemeEnv $Theme
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'theme_env.cmd') -Content $cmdEnvText
    Write-TextUtf8NoBom -Path $cmdThemeEnv -Content $cmdEnvText

    # Delta Git configuration
    $deltaText = Build-DeltaGitConfig $Theme
    $deltaThemePath = Join-Path (Join-Path $cfgDir 'git') 'delta-theme.gitconfig'
    Write-TextUtf8NoBom -Path $deltaThemePath -Content $deltaText
    Write-TextUtf8NoBom -Path (Join-Path $wsStateDir 'delta-theme.gitconfig') -Content $deltaText
    Write-TextUtf8NoBom -Path (Join-Path $hsStateDir 'delta-theme.gitconfig') -Content $deltaText

    # Tealdeer config
    Write-TextUtf8NoBom -Path (Join-Path $tealdeerDir 'config.toml') -Content (Build-TealdeerConfig $Theme)

    # Zellij 0.46+ UI component theme & desktop terminal palette blocks (hot-reloaded by running Zellij sessions)
    $zellijKdlText = Build-ZellijThemeKdl $Theme
    Write-TextUtf8NoBom -Path $zellijThemePath -Content $zellijKdlText
    Sync-ZellijConfigThemeBlock -ConfigPath (Join-Path $zellijConfigDir 'config.kdl') -Theme $Theme
    $xdgZellijDir = Join-Path $cfgDir 'zellij'
    if ($xdgZellijDir -ne $zellijConfigDir -and (Test-Path -LiteralPath $xdgZellijDir)) {
        Write-TextUtf8NoBom -Path (Join-Path (Join-Path $xdgZellijDir 'themes') 'windows-settings.kdl') -Content $zellijKdlText
        Sync-ZellijConfigThemeBlock -ConfigPath (Join-Path $xdgZellijDir 'config.kdl') -Theme $Theme
    }

    # btop / btop4win config & themes
    $btopXdgDir = Join-Path $cfgDir 'btop'
    $btopThemesDir = Join-Path $btopXdgDir 'themes'
    New-Item -ItemType Directory -Force -Path $btopThemesDir | Out-Null
    $repoBtopDir = Join-Path (Join-Path $RepoDir 'config') 'btop'
    $repoBtopConf = Join-Path $repoBtopDir 'btop.conf'
    $repoBtopThemesDir = Join-Path $repoBtopDir 'themes'
    if ([System.IO.Directory]::Exists($repoBtopThemesDir)) {
        foreach ($btFile in [System.IO.Directory]::GetFiles($repoBtopThemesDir, '*.theme')) {
            $btDst = Join-Path $btopThemesDir ([System.IO.Path]::GetFileName($btFile))
            if (-not [System.IO.File]::Exists($btDst) -or ([System.IO.FileInfo]::new($btDst)).Length -ne ([System.IO.FileInfo]::new($btFile)).Length) {
                Copy-Item -LiteralPath $btFile -Destination $btDst -Force
            }
        }
    }
    $targetBtopTheme = Join-Path $btopThemesDir "$($Theme['BTOP_THEME_NAME']).theme"
    if ($Theme['SOURCE'] -eq 'user' -or -not [System.IO.File]::Exists($targetBtopTheme)) {
        Write-TextUtf8NoBom -Path $targetBtopTheme -Content (Build-BtopThemeText $Theme)
    }
    if ([System.IO.File]::Exists($repoBtopConf)) {
        $rawBtop = Get-Content -LiteralPath $repoBtopConf -Raw
        $updatedBtop = [regex]::Replace($rawBtop, '(?m)^color_theme\s*=\s*"[^"]*"', "color_theme = `"$($Theme['BTOP_THEME_NAME'])`"")
        $updatedBtop = [regex]::Replace($updatedBtop, '(?m)^cpu_graph_upper\s*=\s*"Auto"', 'cpu_graph_upper = "total"')
        $updatedBtop = [regex]::Replace($updatedBtop, '(?m)^cpu_graph_lower\s*=\s*"Auto"', 'cpu_graph_lower = "gpu"')
        Write-TextUtf8NoBom -Path (Join-Path $btopXdgDir 'btop.conf') -Content $updatedBtop
        if ($env:LOCALAPPDATA) {
            $wingetPkgsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
            if ([System.IO.Directory]::Exists($wingetPkgsRoot)) {
                foreach ($wdirPath in [System.IO.Directory]::GetDirectories($wingetPkgsRoot, 'aristocratos.btop4win*')) {
                    $directB4w = Join-Path $wdirPath 'btop4win\btop4win.exe'
                    $b4wRoot = if ([System.IO.File]::Exists($directB4w)) {
                        Split-Path -Parent $directB4w
                    } else {
                        $exeHit = Get-ChildItem -LiteralPath $wdirPath -Filter 'btop4win.exe' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($exeHit) { $exeHit.DirectoryName } else { '' }
                    }
                    if ($b4wRoot) {
                        $b4wThemes = Join-Path $b4wRoot 'themes'
                        if (-not [System.IO.Directory]::Exists($b4wThemes)) {
                            New-Item -ItemType Directory -Force -Path $b4wThemes -ErrorAction SilentlyContinue | Out-Null
                        }
                        foreach ($srcBt in [System.IO.Directory]::GetFiles($btopThemesDir, '*.theme')) {
                            $dstBt = Join-Path $b4wThemes ([System.IO.Path]::GetFileName($srcBt))
                            if (-not [System.IO.File]::Exists($dstBt) -or ([System.IO.FileInfo]::new($dstBt)).Length -ne ([System.IO.FileInfo]::new($srcBt)).Length) {
                                Copy-Item -LiteralPath $srcBt -Destination $dstBt -Force -ErrorAction SilentlyContinue
                            }
                        }
                        Write-TextUtf8NoBom -Path (Join-Path $b4wRoot 'btop.conf') -Content $updatedBtop
                    }
                }
            }
        }
    }

    # Oh My Posh theme remap & compiled cache update (skip init rebuild when streaming cache already exists)
    $repoOmp = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'powershell') 'p10k_single_line.omp.json'
    if ([System.IO.File]::Exists($repoOmp)) {
        $rawOmp = Get-Content -LiteralPath $repoOmp -Raw
        $remappedOmp = Convert-SolarizedHexString -InputText $rawOmp -Theme $Theme -Lowercase $true
        Write-TextUtf8NoBom -Path $ompDest -Content $remappedOmp
        $ompInitPath = Join-Path $psCacheDir 'omp_init.ps1'
        $needOmpInit = -not [System.IO.File]::Exists($ompInitPath)
        if (-not $needOmpInit) {
            $cachedOmpText = [System.IO.File]::ReadAllText($ompInitPath)
            if ($cachedOmpText -notmatch 'Enable-PoshStreaming') {
                $needOmpInit = $true
            }
        }
        if ($needOmpInit) {
            $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
            if ($ompCmd) {
                try {
                    $ompInit = (& $ompCmd.Source init pwsh --config $ompDest --print) -join "`n"
                    if ($ompInit) {
                        Write-TextUtf8NoBom -Path $ompInitPath -Content $ompInit
                    }
                } catch {
                    Write-Verbose "Oh My Posh cache rebuild skipped: $_"
                }
            }
        }
    }

    # bat .tmTheme files & cache rebuild
    New-Item -ItemType Directory -Force -Path $batThemesDir | Out-Null
    $needBatRebuild = $false
    $repoBatThemes = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'bat') 'themes'
    if (Test-Path -LiteralPath $repoBatThemes) {
        foreach ($tm in (Get-ChildItem -LiteralPath $repoBatThemes -Filter '*.tmTheme' -File)) {
            $dstTm = Join-Path $batThemesDir $tm.Name
            if (-not (Test-Path -LiteralPath $dstTm)) {
                Copy-Item -LiteralPath $tm.FullName -Destination $dstTm -Force
                $needBatRebuild = $true
            }
        }
    }
    $targetTmFile = Join-Path $batThemesDir "$($Theme['BAT_THEME_NAME']).tmTheme"
    if ($Theme['SOURCE'] -eq 'user' -or -not (Test-Path -LiteralPath $targetTmFile)) {
        $baseTmPath = Join-Path (Join-Path $RepoDir 'config') 'bat\Solarized-Dark-TrueColor.tmTheme'
        if (Test-Path -LiteralPath $baseTmPath) {
            $baseTmRaw = Get-Content -LiteralPath $baseTmPath -Raw
            Write-TextUtf8NoBom -Path $targetTmFile -Content (Build-TmThemeText -BaseTmThemeText $baseTmRaw -Theme $Theme)
            $needBatRebuild = $true
        }
    }
    $batConfigFile = Join-Path $batConfigDir 'config'
    $targetBatThemeLine = "--theme=`"$($Theme['BAT_THEME_NAME'])`""
    if (Test-Path -LiteralPath $batConfigFile) {
        $existingBatCfg = Get-Content -LiteralPath $batConfigFile -Raw
        if ($existingBatCfg -notmatch '--theme=') {
            Write-TextUtf8NoBom -Path $batConfigFile -Content ($existingBatCfg.TrimEnd() + "`n$targetBatThemeLine`n")
        } elseif ($existingBatCfg -notmatch [regex]::Escape($targetBatThemeLine)) {
            $updatedBatCfg = [regex]::Replace($existingBatCfg, '--theme=\S+', $targetBatThemeLine)
            Write-TextUtf8NoBom -Path $batConfigFile -Content $updatedBatCfg
        }
    } else {
        Write-TextUtf8NoBom -Path $batConfigFile -Content "$targetBatThemeLine`n"
    }

    if ($needBatRebuild) {
        $batCmd = Get-Command bat -ErrorAction SilentlyContinue
        if ($batCmd) {
            try { & $batCmd.Source cache --build *> $null } catch { Write-Verbose "bat cache rebuild skipped" }
        }
    }

    # Synchronize in-process PowerShell session (env, PSReadLine & Oh My Posh session cache)
    $psEnvCacheFile = Join-Path $psCacheDir 'theme_env.ps1'
    if ([System.IO.File]::Exists($psEnvCacheFile)) {
        try { . $psEnvCacheFile } catch { Write-Verbose "In-process theme_env load skipped: $_" }
    }
    if (Get-Command Sync-PSReadLineThemePalette -ErrorAction SilentlyContinue) {
        try { Sync-PSReadLineThemePalette } catch { Write-Verbose "PSReadLine palette sync skipped: $_" }
    }
    if (Get-Command Sync-OhMyPoshPromptCache -ErrorAction SilentlyContinue) {
        try { Sync-OhMyPoshPromptCache } catch { Write-Verbose "Oh My Posh sync skipped: $_" }
    } else {
        if ([System.IO.File]::Exists($ompDest)) {
            $env:POSH_CONFIG = $ompDest
        }
        $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
        $streamState = Get-Variable -Name _ompStreamingState -Scope Global -ValueOnly -ErrorAction SilentlyContinue
        if ($null -ne $streamState) {
            try {
                if ($null -ne $streamState.StdIn) {
                    try {
                        $streamState.StdIn.WriteLine('{"command":"quit"}')
                        $streamState.StdIn.Write([char]0)
                        $streamState.StdIn.Flush()
                    } catch { $null = $_ }
                }
                if ($null -ne $streamState.ServeProcess -and -not $streamState.ServeProcess.HasExited) {
                    try { $streamState.ServeProcess.Kill() } catch { $null = $_ }
                }
                $streamState.ServeProcess = $null
                $streamState.FailureCount = 0
                $streamState.Prompt = ''
                $streamState.Transient = ''
                $streamState.Dirty = $false
                $streamState.State = 'NEW'
            } catch {
                $null = $_
            }
        }
    }

    if (-not $NoLive) {
        Sync-WindowsTerminalTheme -Theme $Theme -AllThemes $AllThemes
        Send-LiveOscSequence -Theme $Theme
        Send-LiveNeovimReload
    }

    Write-Output "Applied theme: $($Theme['THEME_LABEL']) ($($Theme['THEME_ID']))"
}

function Format-FgEsc([string]$Hex) {
    return "$([char]27)[38;2;$(Get-RgbSemi $Hex)m"
}

function Format-BgEsc([string]$Hex) {
    return "$([char]27)[48;2;$(Get-RgbSemi $Hex)m"
}

function Get-VisibleLength([string]$Text) {
    $plain = [regex]::Replace($Text, "\x1b\[[0-9;]*m", '')
    $total = 0
    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($plain)
    while ($enum.MoveNext()) {
        $el = $enum.GetTextElement()
        $cp = [char]::ConvertToUtf32($el, 0)
        if (($cp -ge 0x1F300 -and $cp -le 0x1FAFF) -or $el -eq '✨') {
            $total += 2
        } else {
            $total += 1
        }
    }
    return $total
}

function Format-PreviewLine([string]$Content, [string]$BgCode, [int]$Width, [int]$LeftPad = 2) {
    $rst = "$([char]27)[0m"
    $padL = ' ' * $LeftPad
    $prefix = "${BgCode}${padL}${Content}${BgCode}"
    $vlen = Get-VisibleLength $prefix
    $rem = [Math]::Max(0, $Width - $vlen)
    return "${prefix}$(' ' * $rem)${rst}"
}

function Show-ThemePreview([hashtable]$Theme) {
    $fzfCols = if ($env:FZF_PREVIEW_COLUMNS) { $env:FZF_PREVIEW_COLUMNS.Trim() } else { '' }
    $fzfLines = if ($env:FZF_PREVIEW_LINES) { $env:FZF_PREVIEW_LINES.Trim() } else { '' }
    $width = 94
    $parsedW = 0
    if ($fzfCols -and [int]::TryParse($fzfCols, [ref]$parsedW)) { $width = [Math]::Max(60, $parsedW) }
    $targetHeight = 0
    $parsedH = 0
    if ($fzfLines -and [int]::TryParse($fzfLines, [ref]$parsedH)) { $targetHeight = [Math]::Max(24, $parsedH) }

    $b03 = Format-BgEsc $Theme['BASE03']
    $b02 = Format-BgEsc $Theme['BASE02']
    $bGrn = Format-BgEsc $Theme['MIX_GREEN']
    $bRed = Format-BgEsc $Theme['MIX_RED']

    $cB01 = Format-FgEsc $Theme['BASE01']
    $cB00 = Format-FgEsc $Theme['BASE00']
    $cB0  = Format-FgEsc $Theme['BASE0']
    $cB1  = Format-FgEsc $Theme['BASE1']
    $cYlw = Format-FgEsc $Theme['YELLOW']
    $cOrg = Format-FgEsc $Theme['ORANGE']
    $cRed = Format-FgEsc $Theme['RED']
    $cMag = Format-FgEsc $Theme['MAGENTA']
    $cVio = Format-FgEsc $Theme['VIOLET']
    $cBlu = Format-FgEsc $Theme['BLUE']
    $cCyn = Format-FgEsc $Theme['CYAN']
    $cGrn = Format-FgEsc $Theme['GREEN']

    $hmeta = $script:HolidayMeta[$Theme['THEME_ID']]
    $sessionIcon = if ($hmeta) { $hmeta.Icon } else { '' }
    $promptIcon = if ($hmeta) { $hmeta.Icon } else { '' }
    $ruleWidth = [Math]::Max(40, [Math]::Min($width - 4, 88))
    $lines = [System.Collections.Generic.List[string]]::new()

    if ($hmeta) {
        $lines.Add((Format-PreviewLine "${cYlw}$($hmeta.Banner)" $b02 $width))
    }
    $lines.Add((Format-PreviewLine "${cOrg}$($Theme['THEME_LABEL']) ${cB01}($($Theme['THEME_ID']) | $($Theme['THEME_MODE']) | $($Theme['SOURCE']))" $b02 $width))
    $lines.Add((Format-PreviewLine "${cB0}$($Theme['THEME_DESCRIPTION'])" $b02 $width))
    $lines.Add((Format-PreviewLine "${cBlu}Monotone Surface & Content Ramp:" $b03 $width))

    $monoKeys = @('BASE03', 'BASE02', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3')
    $monoRow1 = ($monoKeys[0..3] | ForEach-Object { "$(Format-FgEsc $Theme[$_])██ ${cB0}$($_.ToLowerInvariant()):$($Theme[$_])" }) -join '  '
    $monoRow2 = ($monoKeys[4..7] | ForEach-Object { "$(Format-FgEsc $Theme[$_])██ ${cB0}$($_.ToLowerInvariant()):$($Theme[$_])" }) -join '  '
    $lines.Add((Format-PreviewLine $monoRow1 $b03 $width 4))
    $lines.Add((Format-PreviewLine $monoRow2 $b03 $width 4))

    $lines.Add((Format-PreviewLine "${cBlu}Semantic Accent Architecture:" $b03 $width))
    $roles = @(
        @('YELLOW', 'control flow'),      @('ORANGE', 'preprocessor / H1'),
        @('RED', 'errors / deletions'),   @('MAGENTA', 'constants / numbers'),
        @('VIOLET', 'imports / attrs'),   @('BLUE', 'function defs / H2'),
        @('CYAN', 'strings / escapes'),   @('GREEN', 'keywords / types')
    )
    for ($i = 0; $i -lt $roles.Count; $i += 2) {
        $k1 = $roles[$i][0];     $r1 = $roles[$i][1]
        $k2 = $roles[$i + 1][0]; $r2 = $roles[$i + 1][1]
        $col1 = "$(Format-FgEsc $Theme[$k1])██ ${cB1}$($k1.PadRight(7)) ${cB01}$($Theme[$k1]) ${cB0}($($r1.PadRight(18)))"
        $col2 = "$(Format-FgEsc $Theme[$k2])██ ${cB1}$($k2.PadRight(7)) ${cB01}$($Theme[$k2]) ${cB0}($r2)"
        $lines.Add((Format-PreviewLine "$col1   $col2" $b03 $width 4))
    }

    $lines.Add((Format-PreviewLine "${cB01}$('─' * $ruleWidth)" $b03 $width))
    $lines.Add((Format-PreviewLine "${cBlu}Converged Semantic Code Preview:" $b03 $width))
    $statusLine = "${cBlu}${sessionIcon} ide ${cB00} ${cCyn}▸ 󰚩 agy ${cB01}· ${cB0} Editor ${cB01}· ${cB0} Shell" + $(if ($hmeta) { "  ${cB00} ${cYlw}$($hmeta.Badge)" } else { '' })

    $lines.Add((Format-PreviewLine "${cB01}// $($Theme['THEME_LABEL']) — Universal Semantic Highlighting" $b03 $width 4))
    $lines.Add((Format-PreviewLine "${cOrg}#include ${cCyn}<stdio.h>" $b03 $width 4))
    $lines.Add((Format-PreviewLine "${cVio}import ${cVio}core::telemetry${cB0};" $b03 $width 4))
    $lines.Add((Format-PreviewLine "${cVio}#[derive(Clone)]" $b03 $width 4))
    $lines.Add((Format-PreviewLine "${cGrn}pub fn ${cBlu}classify_sample${cB0}(val: ${cGrn}i64${cB0}) -> ${cB0}Option<${cGrn}bool${cB0}> {" $b03 $width 4))
    $lines.Add((Format-PreviewLine "    ${cYlw}if ${cB0}val >= ${cMag}42 ${cB0}{" $b03 $width 4))
    $lines.Add((Format-PreviewLine "    ${cRed}-   ${cYlw}return ${cB0}Some(${cMag}false${cB0});" $bRed $width 4))
    $lines.Add((Format-PreviewLine "    ${cGrn}+   ${cYlw}return ${cB0}Some(${cMag}true${cB0});" $bGrn $width 4))
    $lines.Add((Format-PreviewLine "    ${cB0}}" $b03 $width 4))
    $lines.Add((Format-PreviewLine "    ${cB0}emit_log(${cCyn}`"status: %s\n`"${cB0});" $b03 $width 4))
    $lines.Add((Format-PreviewLine "    ${cYlw}return ${cMag}None${cB0};" $b03 $width 4))
    $lines.Add((Format-PreviewLine "${cB0}}" $b03 $width 4))
    $lines.Add((Format-PreviewLine $statusLine $b02 $width))
    $lines.Add((Format-PreviewLine "${cB0}${promptIcon} ${cB01} ${cBlu}~/windows-settings ${cB01} ${cGrn} main ✔ ${cGrn}❯ ${cGrn}theme ${cCyn}$($Theme['THEME_ID'])" $b03 $width))

    while ($targetHeight -gt 0 -and $lines.Count -lt $targetHeight) {
        $lines.Add((Format-PreviewLine '' $b03 $width))
    }
    Write-Output ($lines -join "`n")
}

function Format-SwatchStrip([hashtable]$Theme) {
    $rst = "$([char]27)[0m"
    $keys = @('BASE03', 'BASE0', 'GREEN', 'BLUE', 'YELLOW', 'VIOLET', 'CYAN', 'MAGENTA', 'ORANGE', 'RED')
    return (($keys | ForEach-Object { "$(Format-FgEsc $Theme[$_])██" }) -join '') + $rst
}

function Get-OrderedThemeSlugList([hashtable]$Themes) {
    $ordered = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $script:ManagedOrder) {
        if ($Themes.ContainsKey($s)) { $ordered.Add($s) }
    }
    foreach ($s in ($Themes.Keys | Sort-Object)) {
        if (-not $ordered.Contains($s)) { $ordered.Add($s) }
    }
    return $ordered
}

function Show-ThemeList([hashtable]$Themes, [string]$CurrentSlug, [bool]$Plain = $false) {
    $useColor = (-not [Console]::IsOutputRedirected) -and (-not $env:NO_COLOR)
    foreach ($slug in (Get-OrderedThemeSlugList $Themes)) {
        if ($Plain) {
            Write-Output $slug
            continue
        }
        $t = $Themes[$slug]
        $marker = if ($slug -eq $CurrentSlug) { '*' } else { ' ' }
        $hmeta = $script:HolidayMeta[$slug]
        $displayLabel = if ($hmeta) { "$($hmeta.Icon) $($t['THEME_LABEL'])" } else { $t['THEME_LABEL'] }
        if ($useColor) {
            $strip = Format-SwatchStrip $t
            Write-Output ("{0} {1,-18} {2,-5}  {3,-7}  {4}  {5} — {6}" -f $marker, $slug, $t['THEME_MODE'], $t['SOURCE'], $strip, $displayLabel, $t['THEME_DESCRIPTION'])
        } else {
            Write-Output ("{0} {1,-18} {2,-5}  {3,-7}  {4} — {5}" -f $marker, $slug, $t['THEME_MODE'], $t['SOURCE'], $displayLabel, $t['THEME_DESCRIPTION'])
        }
    }
}

function Initialize-CustomUserTheme([string]$NewName, [string]$BaseSlug, [hashtable]$Themes, [bool]$Force = $false) {
    $slug = $NewName.Trim().ToLowerInvariant().Replace('_', '-')
    if ($slug -notmatch '^[a-z0-9][a-z0-9-]*$') {
        [Console]::Error.WriteLine("theme: invalid theme name '$NewName' (use lowercase letters, numbers, and hyphens)")
        $script:ExitCode = 1
        return
    }
    $baseKey = $BaseSlug.Trim().ToLowerInvariant().Replace('_', '-')
    if (-not $Themes.ContainsKey($baseKey)) {
        [Console]::Error.WriteLine("theme: unknown base theme '$BaseSlug'")
        $script:ExitCode = 1
        return
    }
    $base = $Themes[$baseKey]
    $userDir = (Get-UserThemeDirList)[0]
    New-Item -ItemType Directory -Force -Path $userDir | Out-Null
    $targetPath = Join-Path $userDir "$slug.theme"
    if ((Test-Path -LiteralPath $targetPath) -and -not $Force) {
        [Console]::Error.WriteLine("theme: custom theme file already exists: $targetPath (use --force to overwrite)")
        $script:ExitCode = 1
        return
    }
    $label = ConvertTo-TitleLabel $slug
    $pascalSlug = ((($slug -split '-') | Where-Object { $_ } | ForEach-Object { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1) }) -join '-')
    $snakeSlug = $slug.Replace('-', '_')
    $content = @"
# Custom User Theme: $slug (based on $($base['THEME_ID']))
THEME_ID="$slug"
THEME_LABEL="$label"
THEME_DESCRIPTION="Custom $($base['THEME_MODE']) theme based on $($base['THEME_LABEL'])"
THEME_MODE="$($base['THEME_MODE'])"
BAT_THEME_NAME="${pascalSlug}-TrueColor"
BTOP_THEME_NAME="$snakeSlug"
GHOSTTY_THEME_NAME="$label"

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
    Write-TextUtf8NoBom -Path $targetPath -Content ($content + "`n")
    Write-Output $targetPath
}

function Invoke-FzfThemePicker([hashtable]$Themes, [string]$CurrentSlug, [bool]$DryRun = $false, [bool]$NoLive = $false) {
    $inWrapper = ($env:THEME_SHELL_WRAPPER -eq '1')
    $fzfCmd = Get-Command fzf -ErrorAction SilentlyContinue
    if (-not $fzfCmd) {
        Show-ThemeList -Themes $Themes -CurrentSlug $CurrentSlug
        if ($inWrapper) { $script:ExitCode = 130 }
        return
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($slug in (Get-OrderedThemeSlugList $Themes)) {
        $t = $Themes[$slug]
        $activeTag = if ($slug -eq $CurrentSlug) { '(active)' } else { '        ' }
        $strip = Format-SwatchStrip $t
        $hmeta = $script:HolidayMeta[$slug]
        $displayLabel = if ($hmeta) { "$($hmeta.Icon) $($t['THEME_LABEL'])" } else { $t['THEME_LABEL'] }
        $lines.Add(("{0,-18}  {1}  {2,-5}  {3,-7}  {4}  {5}" -f $slug, $activeTag, $t['THEME_MODE'], $t['SOURCE'], $strip, $displayLabel))
    }

    $cur = $Themes[$CurrentSlug]
    $fzfColors = "--color=bg+:$($cur['BASE02']),bg:$($cur['BASE03']),spinner:$($cur['GREEN']),hl:$($cur['BASE01']),fg:$($cur['BASE0']),header:$($cur['BASE01']),info:$($cur['YELLOW']),pointer:$($cur['GREEN']),marker:$($cur['GREEN']),fg+:$($cur['BASE1']),prompt:$($cur['YELLOW']),hl+:$($cur['BLUE'])"
    $selfPs1 = Join-Path $ScriptDir 'theme.ps1'
    $previewCmd = "pwsh -NoLogo -NoProfile -File `"$selfPs1`" --preview {1}"

    $selected = $lines | & $fzfCmd.Source `
        --ansi `
        --no-multi `
        --reverse `
        --no-scrollbar `
        --height=80% `
        --border=rounded `
        "--prompt=Theme > " `
        "--header=Select a color theme (Enter to apply, Esc to cancel)" `
        "--preview=$previewCmd" `
        --preview-window=right:60%:nowrap:noinfo `
        $fzfColors

    if ($LASTEXITCODE -ne 0 -or -not $selected) {
        if ($inWrapper) { $script:ExitCode = 130 }
        return
    }
    $tokens = ($selected.Trim() -split '\s+')
    $chosenSlug = $(if ($tokens[0] -eq '*' -and $tokens.Count -gt 1) { $tokens[1] } else { $tokens[0] }).Trim().ToLowerInvariant()
    if (-not $Themes.ContainsKey($chosenSlug)) {
        [Console]::Error.WriteLine("theme: unknown theme selected: $chosenSlug")
        $script:ExitCode = 1
        return
    }
    Invoke-ApplyTheme -Theme $Themes[$chosenSlug] -AllThemes $Themes -DryRun $DryRun -NoLive $NoLive
}

# =============================================================
# CLI Argument Parser (Supports POSIX --flags and PowerShell -Flags)
# =============================================================
$action = $null
$targetName = $null
$baseName = 'solarized-dark'
$force = $false
$dryRun = $false
$noLive = $false
$plain = $false
$endOfOpts = $false

:ArgLoop for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    if (-not $endOfOpts -and $arg -eq '--') {
        $endOfOpts = $true
        continue ArgLoop
    }
    if (-not $endOfOpts) {
        switch -Regex ($arg) {
            '^(-h|--help|-Help|-\?)$' {
                Write-Output $script:UsageText
                exit 0
            }
            '^(-l|--list|-List)$' {
                $action = 'list'
                continue ArgLoop
            }
            '^(--plain|-Plain)$' {
                $plain = $true
                if (-not $action) { $action = 'list' }
                continue ArgLoop
            }
            '^(-c|--current|-Current)$' {
                $action = 'current'
                continue ArgLoop
            }
            '^(--path|-Path)$' {
                $action = 'path'
                continue ArgLoop
            }
            '^(--sync-assets|-SyncAssets)$' {
                $action = 'sync-assets'
                continue ArgLoop
            }
            '^(-n|--dry-run|-DryRun)$' {
                $dryRun = $true
                continue ArgLoop
            }
            '^(--no-live|-NoLive)$' {
                $noLive = $true
                continue ArgLoop
            }
            '^(-f|--force|-Force)$' {
                $force = $true
                continue ArgLoop
            }
            '^(--holiday|-Holiday)$' {
                $action = 'set'
                try {
                    $targetName = Resolve-NearestHolidaySlug
                } catch {
                    [Console]::Error.WriteLine("theme: $($_.Exception.Message)")
                    exit 1
                }
                continue ArgLoop
            }
            '^(-s|--set|-Set)$' {
                if ($i + 1 -ge $args.Count -or -not ([string]$args[$i + 1]).Trim() -or ([string]$args[$i + 1]).StartsWith('-')) {
                    [Console]::Error.WriteLine("theme: option '$arg' requires a theme name")
                    exit 1
                }
                $action = 'set'
                $targetName = [string]$args[$i + 1]
                $i++
                continue ArgLoop
            }
            '^--set=(.*)$' {
                $val = $Matches[1]
                if (-not $val.Trim()) {
                    [Console]::Error.WriteLine("theme: option '--set' requires a theme name")
                    exit 1
                }
                $action = 'set'
                $targetName = $val
                continue ArgLoop
            }
            '^(-p|--preview|-Preview)$' {
                $action = 'preview'
                if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) {
                    $targetName = [string]$args[$i + 1]
                    $i++
                }
                continue ArgLoop
            }
            '^--preview=(.*)$' {
                $val = $Matches[1]
                if (-not $val.Trim()) {
                    [Console]::Error.WriteLine("theme: option '--preview' requires a theme name")
                    exit 1
                }
                $action = 'preview'
                $targetName = $val
                continue ArgLoop
            }
            '^(--env|-Env)$' {
                $action = 'env'
                if ($i + 1 -lt $args.Count -and -not ([string]$args[$i + 1]).StartsWith('-')) {
                    $targetName = [string]$args[$i + 1]
                    $i++
                }
                continue ArgLoop
            }
            '^--env=(.*)$' {
                $val = $Matches[1]
                if (-not $val.Trim()) {
                    [Console]::Error.WriteLine("theme: option '--env' requires a theme name")
                    exit 1
                }
                $action = 'env'
                $targetName = $val
                continue ArgLoop
            }
            '^(--create|-Create)$' {
                if ($i + 1 -ge $args.Count -or -not ([string]$args[$i + 1]).Trim() -or ([string]$args[$i + 1]).StartsWith('-')) {
                    [Console]::Error.WriteLine("theme: option '--create' requires a new theme name")
                    exit 1
                }
                $action = 'create'
                $targetName = [string]$args[$i + 1]
                $i++
                continue ArgLoop
            }
            '^--create=(.*)$' {
                $val = $Matches[1]
                if (-not $val.Trim()) {
                    [Console]::Error.WriteLine("theme: option '--create' requires a new theme name")
                    exit 1
                }
                $action = 'create'
                $targetName = $val
                continue ArgLoop
            }
            '^(--from|-From)$' {
                if ($i + 1 -ge $args.Count -or -not ([string]$args[$i + 1]).Trim() -or ([string]$args[$i + 1]).StartsWith('-')) {
                    [Console]::Error.WriteLine("theme: option '--from' requires a base theme name")
                    exit 1
                }
                $baseName = [string]$args[$i + 1]
                $i++
                continue ArgLoop
            }
            '^--from=(.*)$' {
                $val = $Matches[1]
                if (-not $val.Trim()) {
                    [Console]::Error.WriteLine("theme: option '--from' requires a base theme name")
                    exit 1
                }
                $baseName = $val
                continue ArgLoop
            }
            '^-.*$' {
                [Console]::Error.WriteLine("theme: unknown option '$arg' (try 'theme --help')")
                exit 1
            }
        }
    }

    if (-not $arg.Trim()) {
        [Console]::Error.WriteLine('theme: theme name must not be empty')
        exit 1
    }
    if ($null -ne $targetName) {
        [Console]::Error.WriteLine("theme: unexpected extra argument '$arg'")
        exit 1
    }
    $targetName = $arg
    if (-not $action) { $action = 'set' }
}

$script:ExitCode = 0

if ($action -eq 'path') {
    Write-Output (Get-UserThemeDirList)[0]
    exit 0
}
if ($action -eq 'current') {
    try {
        Write-Output (Resolve-CurrentSlugFast)
        exit 0
    } catch {
        [Console]::Error.WriteLine("theme: $($_.Exception.Message)")
        exit 1
    }
}
if ($action -in @('preview', 'env', 'set') -or ($dryRun -and $null -ne $targetName -and $action -notin @('list', 'create', 'sync-assets'))) {
    try {
        $rawTarget = if ($null -eq $targetName) { Resolve-CurrentSlugFast } else { $targetName }
        $singleTheme = Resolve-SingleThemeFast $rawTarget
    } catch {
        [Console]::Error.WriteLine("theme: $($_.Exception.Message)")
        exit 1
    }
    if ($null -eq $singleTheme) {
        [Console]::Error.WriteLine("theme: unknown theme '$rawTarget' (run 'theme --list' to see available themes)")
        exit 1
    }
    if ($action -eq 'preview') {
        Show-ThemePreview -Theme $singleTheme
        exit $script:ExitCode
    }
    if ($action -eq 'env') {
        Write-Output (Build-PowerShellThemeEnv -Theme $singleTheme)
        exit 0
    }
    Invoke-ApplyTheme -Theme $singleTheme -AllThemes @{} -DryRun $dryRun -NoLive $noLive
    exit $script:ExitCode
}

try {
    $themes = Get-DiscoveredThemeMap
} catch {
    [Console]::Error.WriteLine("theme: $($_.Exception.Message)")
    exit 1
}

$currentSlug = Get-CurrentThemeSlug -Themes $themes

if ($action -eq 'list') {
    Show-ThemeList -Themes $themes -CurrentSlug $currentSlug -Plain $plain
    exit $script:ExitCode
}
if ($action -eq 'sync-assets') {
    $repoZellijTheme = Join-Path (Join-Path (Join-Path (Join-Path $RepoDir 'config') 'zellij') 'themes') 'windows-settings.kdl'
    if ($dryRun) {
        Write-Output "[DRY-RUN] Would sync repository Zellij default theme: $repoZellijTheme"
        Invoke-ApplyTheme -Theme $themes[$currentSlug] -AllThemes $themes -DryRun $true -NoLive $true
        exit 0
    }
    if ($themes.ContainsKey('solarized-dark')) {
        Write-TextUtf8NoBom -Path $repoZellijTheme -Content (Build-ZellijThemeKdl $themes['solarized-dark'])
    }
    Invoke-ApplyTheme -Theme $themes[$currentSlug] -AllThemes $themes -DryRun $false -NoLive $true
    exit $script:ExitCode
}
if ($action -eq 'create') {
    Initialize-CustomUserTheme -NewName $targetName -BaseSlug $baseName -Themes $themes -Force $force
    exit $script:ExitCode
}
if ($dryRun -and $null -eq $targetName) {
    Invoke-ApplyTheme -Theme $themes[$currentSlug] -AllThemes $themes -DryRun $true -NoLive $noLive
    exit $script:ExitCode
}

if ((-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) -or $env:THEME_FORCE_FZF -eq '1') {
    Invoke-FzfThemePicker -Themes $themes -CurrentSlug $currentSlug -DryRun $dryRun -NoLive $noLive
    exit $script:ExitCode
}
Show-ThemeList -Themes $themes -CurrentSlug $currentSlug
exit $script:ExitCode
