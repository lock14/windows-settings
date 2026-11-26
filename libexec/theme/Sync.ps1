# ==============================================================================
# Sync.ps1 - Deterministic repository asset and bounded-block synchronizer
# ==============================================================================

$script:SpecColorKeys = @(
    'BASE03', 'BASE02', 'BASE04', 'BASE01', 'BASE00', 'BASE0', 'BASE1', 'BASE2', 'BASE3',
    'YELLOW', 'ORANGE', 'RED', 'MAGENTA', 'VIOLET', 'BLUE', 'CYAN', 'GREEN',
    'MIX_GREEN', 'MIX_RED', 'MIX_YELLOW', 'MIX_BLUE', 'MIX_MAGENTA', 'MIX_BASE1'
)

$script:SpecFieldOrder = @('THEME_LABEL', 'THEME_MODE', 'BAT_THEME_NAME') + $script:SpecColorKeys

function Join-ThemeSpecField([System.Collections.IDictionary]$Theme) {
    $vals = foreach ($k in $script:SpecFieldOrder) {
        [string]$Theme[$k]
    }
    return ($vals -join '|')
}

function Format-VimStringLiteral([string]$Text) {
    if (-not $Text.Contains("'")) {
        return "'$Text'"
    }
    $escaped = $Text.Replace('\', '\\').Replace('"', '\"')
    return "`"$escaped`""
}

function ConvertTo-RustUnicodeEscape([string]$Text) {
    if (-not $Text) { return '' }
    $sb = [System.Text.StringBuilder]::new($Text.Length * 6)
    $len = $Text.Length
    for ($idx = 0; $idx -lt $len; $idx++) {
        $ch = $Text[$idx]
        if ([char]::IsHighSurrogate($ch) -and ($idx + 1) -lt $len -and [char]::IsLowSurrogate($Text[$idx + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Text[$idx + 1])
            $idx++
        } else {
            $cp = [int]$ch
        }
        if ($cp -eq 0x5C) {
            [void]$sb.Append('\\')
        } elseif ($cp -eq 0x22) {
            [void]$sb.Append('\"')
        } elseif ($cp -ge 0x20 -and $cp -le 0x7E) {
            [void]$sb.Append([char]$cp)
        } else {
            [void]$sb.Append(('\u{{{0:X}}}' -f $cp))
        }
    }
    return $sb.ToString()
}

function ConvertTo-JsonEscapedString([string]$Text) {
    if ($null -eq $Text) { return '' }
    return $Text.Replace('\', '\\').Replace('"', '\"')
}

function Format-BacktickSlugList([string[]]$Slugs, [bool]$MarkDefault = $false) {
    $items = @(foreach ($s in $Slugs) {
        if ($MarkDefault -and $s -eq 'solarized-dark') {
            "``$s`` (default)"
        } else {
            "``$s``"
        }
    })
    if ($items.Count -eq 0) { return '' }
    if ($items.Count -eq 1) { return $items[0] }
    if ($items.Count -eq 2) { return "$($items[0]) and $($items[1])" }
    $head = $items[0..($items.Count - 2)] -join ', '
    return "$head, and $($items[$items.Count - 1])"
}

function ConvertTo-UpdatedBoundedBlock([string]$TextLf, [string]$BeginMarker, [string]$EndMarker, [string]$BodyLf) {
    $escBegin = [regex]::Escape($BeginMarker)
    $escEnd = [regex]::Escape($EndMarker)
    $pattern = [regex]::new("(?ms)(^[ \t]*${escBegin}\n).*?(^[ \t]*${escEnd}`$)")
    $match = $pattern.Match($TextLf)
    if (-not $match.Success) {
        throw "Missing bounded markers '$BeginMarker' .. '$EndMarker'"
    }
    $cleanBody = $BodyLf.Replace("`r`n", "`n").TrimEnd("`n") + "`n"
    $replacement = $match.Groups[1].Value + $cleanBody + $match.Groups[2].Value
    return ($TextLf.Substring(0, $match.Index) + $replacement + $TextLf.Substring($match.Index + $match.Length))
}

function Build-VimBuiltinThemeBlock([System.Collections.IDictionary]$Themes, [string[]]$Slugs) {
    $orderLines = [System.Collections.Generic.List[string]]::new()
    $orderLines.Add('let s:builtin_theme_order = [')
    $chunk = [System.Collections.Generic.List[string]]::new()
    for ($idx = 0; $idx -lt $Slugs.Count; $idx++) {
        $slug = $Slugs[$idx]
        $suffix = if ($idx + 1 -lt $Slugs.Count) { ',' } else { '' }
        $chunk.Add("'${slug}'${suffix}")
        if ($chunk.Count -eq 4 -or ($idx + 1) -eq $Slugs.Count) {
            $orderLines.Add('    \ ' + ($chunk -join ' '))
            $chunk.Clear()
        }
    }
    $orderLines.Add('    \ ]')

    $maxKeyLen = 18
    foreach ($s in $Slugs) {
        if (($s.Length + 3) -gt $maxKeyLen) { $maxKeyLen = $s.Length + 3 }
    }

    $dictLines = [System.Collections.Generic.List[string]]::new()
    $dictLines.Add('')
    $dictLines.Add('" Compact 26-field built-in palette table (1:1 with config/themes/*.theme for standalone servers):')
    $dictLines.Add('" LABEL|MODE|BAT_THEME|B03|B02|B04|B01|B00|B0|B1|B2|B3|YEL|ORA|RED|MAG|VIO|BLU|CYA|GRN|MGRN|MRED|MYEL|MBLU|MMAG|MB1')
    $dictLines.Add('let s:builtin_themes = {')
    for ($idx = 0; $idx -lt $Slugs.Count; $idx++) {
        $slug = $Slugs[$idx]
        $keyTok = "'${slug}':"
        $comma = if ($idx + 1 -lt $Slugs.Count) { ',' } else { '' }
        $valTok = Format-VimStringLiteral -Text (Join-ThemeSpecField -Theme $Themes[$slug])
        $dictLines.Add(("    \ {0,-$maxKeyLen} {1}{2}" -f $keyTok, $valTok, $comma))
    }
    $dictLines.Add('    \ }')

    return (($orderLines + $dictLines) -join "`n")
}

function ConvertTo-VimHolidayExpr([string]$Rule) {
    $cleaned = $Rule.Trim().ToLowerInvariant()
    if ($cleaned -eq 'easter') {
        return 'a:year * 10000 + l:em * 100 + l:ed'
    }
    if ($cleaned -eq 'thanksgiving') {
        return 'a:year * 10000 + 1100 + l:td'
    }
    if ($cleaned -match '^(\d{2})-(\d{2})$') {
        $mmdd = ([int]$Matches[1]) * 100 + ([int]$Matches[2])
        return "a:year * 10000 + $mmdd"
    }
    if ($cleaned -match '^nth-weekday:(\d{2}):(-?\d+):([0-6])$') {
        $mon = [int]$Matches[1]
        $nth = [int]$Matches[2]
        $dow = [int]$Matches[3]
        return "a:year * 10000 + $($mon * 100) + s:NthWeekdayOfMonth(a:year, $mon, $nth, $dow)"
    }
    throw "Unsupported holiday rule for Vim codegen: $Rule"
}

function Build-VimHolidayScheduleBlock([System.Collections.IDictionary]$Themes, [string[]]$Slugs) {
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($slug in $Slugs) {
        $rule = if ($Themes[$slug].Contains('HOLIDAY_DATE') -and $Themes[$slug]['HOLIDAY_DATE']) {
            ([string]$Themes[$slug]['HOLIDAY_DATE']).Trim()
        } else {
            ''
        }
        if ($rule) {
            $entries.Add(@{ Expr = (ConvertTo-VimHolidayExpr -Rule $rule); Slug = $slug })
        }
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('    return [')
    for ($idx = 0; $idx -lt $entries.Count; $idx++) {
        $comma = if ($idx + 1 -lt $entries.Count) { ',' } else { '' }
        $lines.Add("        \ [$($entries[$idx].Expr), '$($entries[$idx].Slug)']${comma}")
    }
    $lines.Add('        \ ]')
    return ($lines -join "`n")
}

function Build-PowerShellCompletionThemeBlock([string[]]$Slugs, [string]$SourceLf) {
    $indent = '        '
    if ($SourceLf -match '(?m)^([ \t]*)# BEGIN GENERATED BUILTIN THEMES$') {
        $indent = $Matches[1]
    }
    $trailingComma = $true
    if ($SourceLf -match '(?ms)^[ \t]*# END GENERATED BUILTIN THEMES\n(.*)$') {
        $afterLines = $Matches[1] -split "`n"
        foreach ($ln in $afterLines) {
            $tr = $ln.Trim()
            if (-not $tr -or $tr.StartsWith('#')) { continue }
            if ($tr.StartsWith(')') -or $tr.StartsWith('}')) {
                $trailingComma = $false
            }
            break
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $chunk = [System.Collections.Generic.List[string]]::new()
    for ($idx = 0; $idx -lt $Slugs.Count; $idx++) {
        $slug = $Slugs[$idx]
        $isLast = (($idx + 1) -eq $Slugs.Count)
        $suffix = if (-not $isLast -or $trailingComma) { ',' } else { '' }
        $chunk.Add("'${slug}'${suffix}")
        if ($chunk.Count -eq 4 -or $isLast) {
            $lines.Add($indent + ($chunk -join ' '))
            $chunk.Clear()
        }
    }
    return ($lines -join "`n")
}

function Build-RustHolidayEmblemBlock([System.Collections.IDictionary]$Themes, [string[]]$Slugs, [string]$SourceLf) {
    $indent = '        '
    if ($SourceLf -match '(?m)^([ \t]*)// BEGIN GENERATED HOLIDAY EMBLEMS$') {
        $indent = $Matches[1]
    }
    $returnsTuple = ($SourceLf -match 'fn\s+holiday_emblem\s*\([^)]*\)\s*->\s*Option<\(&''static\s+str,\s*&''static\s+str\)>')
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($slug in $Slugs) {
        $hmeta = Get-HolidayMeta -Theme $Themes[$slug]
        if ($null -eq $hmeta) { continue }
        $escIcon = ConvertTo-RustUnicodeEscape -Text $hmeta.Icon
        if ($returnsTuple) {
            $escBadge = ConvertTo-RustUnicodeEscape -Text $hmeta.Badge
            $lines.Add("${indent}`"${slug}`" => Some((`"${escIcon}`", `"${escBadge}`")),")
        } else {
            $lines.Add("${indent}`"${slug}`" => Some(`"${escIcon}`"),")
        }
    }
    return ($lines -join "`n")
}

function Build-ReadmeThemeCatalogBlock([string[]]$ClassicSlugs, [string[]]$HolidaySlugs) {
    $total = $ClassicSlugs.Count + $HolidaySlugs.Count
    $classicStr = Format-BacktickSlugList -Slugs $ClassicSlugs -MarkDefault $true
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("- **Built-in palettes ($total managed themes)**:")
    $lines.Add("  - **Classic developer palettes ($($ClassicSlugs.Count))**: ${classicStr}.")
    if ($HolidaySlugs.Count -gt 0) {
        $holidayStr = Format-BacktickSlugList -Slugs $HolidaySlugs -MarkDefault $false
        $lines.Add("  - **Major US Holiday palettes ($($HolidaySlugs.Count))**: ${holidayStr}.")
    }
    return ($lines -join "`n")
}

function Build-ColorArchCatalogBlock([string[]]$ClassicSlugs, [string[]]$HolidaySlugs) {
    $classicStr = Format-BacktickSlugList -Slugs $ClassicSlugs -MarkDefault $false
    $emDash = [string][char]0x2014
    $text = (
        "The $($ClassicSlugs.Count) classic daily-driver themes ($classicStr) preserve strict " +
        'physical hue-to-slot alignment and strictly monotonic `base03` through `base3` neutral ramps.'
    )
    if ($HolidaySlugs.Count -gt 0) {
        $holidayStr = Format-BacktickSlugList -Slugs $HolidaySlugs -MarkDefault $false
        $text += (
            " The $($HolidaySlugs.Count) US Holiday themes ($holidayStr) keep the same AST token " +
            "partitioning and pairwise semantic separation${emDash}guaranteeing ``GREEN`` valid commands, " +
            "``YELLOW`` control flow, and ``RED`` errors never collide and ``MIX_GREEN`` and ``MIX_RED`` " +
            "retain green versus red diff polarity${emDash}while intentionally remapping high-visibility " +
            "foreground slots and prompt or Zellij emblems to each holiday's signature colors."
        )
    }
    return $text
}

function Format-TerminalSchemesJsonBlock([System.Collections.IDictionary]$Themes, [string[]]$Slugs) {
    $sb = [System.Text.StringBuilder]::new(8192)
    [void]$sb.Append("  `"schemes`": [`n")
    for ($idx = 0; $idx -lt $Slugs.Count; $idx++) {
        $scheme = ConvertTo-WindowsTerminalScheme -Theme $Themes[$Slugs[$idx]]
        [void]$sb.Append("    {`n")
        $propNames = @($scheme.Keys)
        for ($kIdx = 0; $kIdx -lt $propNames.Count; $kIdx++) {
            $kName = $propNames[$kIdx]
            $kVal = ConvertTo-JsonEscapedString -Text ([string]$scheme[$kName])
            $comma = if ($kIdx + 1 -lt $propNames.Count) { ',' } else { '' }
            [void]$sb.Append("      `"${kName}`": `"${kVal}`"${comma}`n")
        }
        $objComma = if ($idx + 1 -lt $Slugs.Count) { ',' } else { '' }
        [void]$sb.Append("    }${objComma}`n")
    }
    [void]$sb.Append('  ]')
    return $sb.ToString()
}

function ConvertTo-UpdatedTerminalJsonText([string]$RawJsonText, [string]$SchemesJsonBlock) {
    $normLf = $RawJsonText.Replace("`r`n", "`n")
    $pattern = [regex]::new('(?m)^  "schemes": \[(?:\n[\s\S]*?\n  )?\]')
    if (-not $pattern.IsMatch($normLf)) {
        throw 'Missing top-level "schemes" array in Windows Terminal JSON file'
    }
    $updated = $pattern.Replace($normLf, $SchemesJsonBlock, 1)
    $updated = ($updated.TrimEnd("`n") + "`n")
    $null = $updated | ConvertFrom-Json -ErrorAction Stop
    return $updated
}

function Sync-ManagedRepoAsset([string]$RepoDir, [bool]$CheckOnly = $false, [bool]$StaticOnly = $false) {
    $drift = [System.Collections.Generic.List[string]]::new()
    $themes = Get-BuiltinThemeMap -RepoDir $RepoDir
    $slugs = @(Get-OrderedThemeSlugList -Themes $themes)
    $classicSlugs = @($slugs | Where-Object { $themes[$_]['THEME_CATEGORY'] -eq 'classic' })
    $holidaySlugs = @($slugs | Where-Object { $themes[$_]['THEME_CATEGORY'] -eq 'holiday' })

    $syncFileContent = {
        param([string]$TargetPath, [string]$ExpectedContent)
        $rel = [System.IO.Path]::GetRelativePath($RepoDir, $TargetPath).Replace('\', '/')
        $current = if ([System.IO.File]::Exists($TargetPath)) {
            [System.IO.File]::ReadAllText($TargetPath, [System.Text.Encoding]::UTF8)
        } else {
            $null
        }
        if ($null -eq $current -or -not [string]::Equals($current, $ExpectedContent, [System.StringComparison]::Ordinal)) {
            $drift.Add($rel)
            if (-not $CheckOnly) {
                Write-TextUtf8NoBom -Path $TargetPath -Content $ExpectedContent
            }
        }
    }

    $pruneOrphanFile = {
        param([string]$TargetPath)
        $rel = [System.IO.Path]::GetRelativePath($RepoDir, $TargetPath).Replace('\', '/')
        $drift.Add("$rel (orphaned)")
        if (-not $CheckOnly) {
            Remove-Item -LiteralPath $TargetPath -Force
        }
    }

    # 1. config/bat/themes/*-TrueColor.tmTheme (LF)
    $batBasePath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'bat') 'Solarized-Dark-TrueColor.tmTheme'
    $batThemesDir = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'bat') 'themes'
    if ([System.IO.File]::Exists($batBasePath)) {
        $baseTm = [System.IO.File]::ReadAllText($batBasePath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
        $expectedTmNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($slug in $slugs) {
            $t = $themes[$slug]
            $tmName = "$($t['BAT_THEME_NAME']).tmTheme"
            [void]$expectedTmNames.Add($tmName)
            $renderedTm = Build-TmThemeText -BaseTmThemeText $baseTm -Theme $t
            & $syncFileContent (Join-Path $batThemesDir $tmName) $renderedTm
        }
        if ([System.IO.Directory]::Exists($batThemesDir)) {
            $existingTms = [System.IO.Directory]::GetFiles($batThemesDir, '*.tmTheme')
            [Array]::Sort($existingTms, [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($existingTm in $existingTms) {
                $leaf = [System.IO.Path]::GetFileName($existingTm)
                if (-not $expectedTmNames.Contains($leaf)) {
                    & $pruneOrphanFile $existingTm
                }
            }
        }
    }

    # 2. config/btop/themes/*.theme (LF)
    $btopThemesDir = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'btop') 'themes'
    if ([System.IO.Directory]::Exists($btopThemesDir) -or -not $CheckOnly) {
        $expectedBtopNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        [void]$expectedBtopNames.Add('solarized_dark.theme')
        foreach ($slug in $slugs) {
            $t = $themes[$slug]
            $btopName = "$($t['BTOP_THEME_NAME']).theme"
            [void]$expectedBtopNames.Add($btopName)
            $btopTarget = Join-Path $btopThemesDir $btopName
            if ($slug -ne 'solarized-dark' -or -not [System.IO.File]::Exists($btopTarget)) {
                & $syncFileContent $btopTarget (Build-BtopThemeText -Theme $t)
            }
        }
        if ([System.IO.Directory]::Exists($btopThemesDir)) {
            $existingBts = [System.IO.Directory]::GetFiles($btopThemesDir, '*.theme')
            [Array]::Sort($existingBts, [System.StringComparer]::OrdinalIgnoreCase)
            foreach ($existingBt in $existingBts) {
                $leaf = [System.IO.Path]::GetFileName($existingBt)
                if (-not $expectedBtopNames.Contains($leaf)) {
                    & $pruneOrphanFile $existingBt
                }
            }
        }
    }

    # 3. config/terminal/windows-settings.json & config/terminal/settings.json (LF)
    $schemesBlock = Format-TerminalSchemesJsonBlock -Themes $themes -Slugs $slugs
    foreach ($termJsonRel in @('windows-settings.json', 'settings.json')) {
        $termJsonPath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'terminal') $termJsonRel
        if ([System.IO.File]::Exists($termJsonPath)) {
            $rawTermJson = [System.IO.File]::ReadAllText($termJsonPath, [System.Text.Encoding]::UTF8)
            $updatedTermJson = ConvertTo-UpdatedTerminalJsonText -RawJsonText $rawTermJson -SchemesJsonBlock $schemesBlock
            & $syncFileContent $termJsonPath $updatedTermJson
        }
    }

    # 4. config/zellij/themes/windows-settings.kdl (solarized-dark baseline, LF)
    $zellijKdlPath = Join-Path (Join-Path (Join-Path (Join-Path $RepoDir 'config') 'zellij') 'themes') 'windows-settings.kdl'
    if ($themes.Contains('solarized-dark') -and ([System.IO.Directory]::Exists((Split-Path -Parent $zellijKdlPath)) -or -not $CheckOnly)) {
        & $syncFileContent $zellijKdlPath (Build-ZellijThemeKdl -Theme $themes['solarized-dark'])
    }

    if ($StaticOnly) {
        return $drift
    }

    # 5a. config/vim/_vimrc bounded blocks (LF)
    $vimrcPath = Join-Path (Join-Path (Join-Path $RepoDir 'config') 'vim') '_vimrc'
    if ([System.IO.File]::Exists($vimrcPath)) {
        $vimrcRaw = [System.IO.File]::ReadAllText($vimrcPath, [System.Text.Encoding]::UTF8)
        $vimrcLf = $vimrcRaw.Replace("`r`n", "`n")
        if ($vimrcLf.Contains('" BEGIN GENERATED BUILTIN THEMES')) {
            $vimrcLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $vimrcLf `
                -BeginMarker '" BEGIN GENERATED BUILTIN THEMES' `
                -EndMarker '" END GENERATED BUILTIN THEMES' `
                -BodyLf (Build-VimBuiltinThemeBlock -Themes $themes -Slugs $slugs)
        }
        if ($vimrcLf.Contains('" BEGIN GENERATED HOLIDAY SCHEDULE')) {
            $vimrcLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $vimrcLf `
                -BeginMarker '" BEGIN GENERATED HOLIDAY SCHEDULE' `
                -EndMarker '" END GENERATED HOLIDAY SCHEDULE' `
                -BodyLf (Build-VimHolidayScheduleBlock -Themes $themes -Slugs $slugs)
        }
        & $syncFileContent $vimrcPath $vimrcLf
    }

    # 5b. module/Completions.ps1 bounded block (CRLF)
    $compPath = Join-Path (Join-Path $RepoDir 'module') 'Completions.ps1'
    if ([System.IO.File]::Exists($compPath)) {
        $compRaw = [System.IO.File]::ReadAllText($compPath, [System.Text.Encoding]::UTF8)
        $compLf = $compRaw.Replace("`r`n", "`n")
        if ($compLf.Contains('# BEGIN GENERATED BUILTIN THEMES')) {
            $compUpdatedLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $compLf `
                -BeginMarker '# BEGIN GENERATED BUILTIN THEMES' `
                -EndMarker '# END GENERATED BUILTIN THEMES' `
                -BodyLf (Build-PowerShellCompletionThemeBlock -Slugs $slugs -SourceLf $compLf)
            $compCrlf = $compUpdatedLf.Replace("`n", "`r`n")
            & $syncFileContent $compPath $compCrlf
        }
    }

    # 5c. plugin/ws-bar/src/palette.rs bounded block (LF)
    $paletteRsPath = Join-Path (Join-Path (Join-Path (Join-Path $RepoDir 'plugin') 'ws-bar') 'src') 'palette.rs'
    if ([System.IO.File]::Exists($paletteRsPath)) {
        $rsRaw = [System.IO.File]::ReadAllText($paletteRsPath, [System.Text.Encoding]::UTF8)
        $rsLf = $rsRaw.Replace("`r`n", "`n")
        if ($rsLf.Contains('// BEGIN GENERATED HOLIDAY EMBLEMS')) {
            $rsUpdatedLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $rsLf `
                -BeginMarker '// BEGIN GENERATED HOLIDAY EMBLEMS' `
                -EndMarker '// END GENERATED HOLIDAY EMBLEMS' `
                -BodyLf (Build-RustHolidayEmblemBlock -Themes $themes -Slugs $slugs -SourceLf $rsLf)
            & $syncFileContent $paletteRsPath $rsUpdatedLf
        }
    }

    # 5d. README.md & docs/color-architecture.md bounded blocks (LF)
    $readmePath = Join-Path $RepoDir 'README.md'
    if ([System.IO.File]::Exists($readmePath)) {
        $readmeLf = [System.IO.File]::ReadAllText($readmePath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
        if ($readmeLf.Contains('<!-- BEGIN GENERATED THEME CATALOG -->')) {
            $readmeUpdatedLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $readmeLf `
                -BeginMarker '<!-- BEGIN GENERATED THEME CATALOG -->' `
                -EndMarker '<!-- END GENERATED THEME CATALOG -->' `
                -BodyLf (Build-ReadmeThemeCatalogBlock -ClassicSlugs $classicSlugs -HolidaySlugs $holidaySlugs)
            & $syncFileContent $readmePath $readmeUpdatedLf
        }
    }

    $colorArchPath = Join-Path (Join-Path $RepoDir 'docs') 'color-architecture.md'
    if ([System.IO.File]::Exists($colorArchPath)) {
        $caLf = [System.IO.File]::ReadAllText($colorArchPath, [System.Text.Encoding]::UTF8).Replace("`r`n", "`n")
        if ($caLf.Contains('<!-- BEGIN GENERATED THEME CATALOG -->')) {
            $caUpdatedLf = ConvertTo-UpdatedBoundedBlock `
                -TextLf $caLf `
                -BeginMarker '<!-- BEGIN GENERATED THEME CATALOG -->' `
                -EndMarker '<!-- END GENERATED THEME CATALOG -->' `
                -BodyLf (Build-ColorArchCatalogBlock -ClassicSlugs $classicSlugs -HolidaySlugs $holidaySlugs)
            & $syncFileContent $colorArchPath $caUpdatedLf
        }
    }

    return $drift
}
