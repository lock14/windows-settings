<#
.SYNOPSIS
    Validate Markdown typography, AGENTS.md budget, cross-file links, CLI flag sync,
    mise.toml toolchain sync, keybinding dual representation, and mono-tui overrides.
#>
[CmdletBinding()]
param(
    [string]$RootDir = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

$ErrorActionPreference = 'Stop'

$docPersonalPathRegex = '(?i)(/home/(?!<)[a-z0-9_-]+|/Users/(?!<)[a-z0-9_-]+|C:\\Users\\(?!<)[a-z0-9_-]+)'
$decorativeEmojiRegex = '([\uD83C-\uDBFF][\uDC00-\uDFFF]|[\u26A1\u2705\u2728\u274C]|:(?:white_check_mark|x):)'
$italicAsideRegex = '(?i)(\*|_)\((?:note|tip|alternatively)\b'
$boldTableCellRegex = '^\|\s*\*\*[^*]+\*\*\s*\|'
$htmlCommentRegex = '<!--.*?-->'
$asciiArrowRegex = '(<->|->|<-|=>|\\rightarrow|\\leftrightarrow|\\gg|[\u2190-\u21FF\u226B])'
$proseSlashRegex = '(?<![/\w.-])([A-Za-z]{2,}/[A-Za-z]{2,})(?![/\w.-])'
$allowedSlashTerms = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($t in @('i/o', 'ci/cd', 'tcp/ip', 'ssl/tls', 'n/a')) { [void]$allowedSlashTerms.Add($t) }
$proseAmpRegex = '\s&\s'
$prosePlusRegex = '\s\+\s'
$latinAbbrevRegex = '(?<![A-Za-z0-9_])(?:(?i:e\.g\.|i\.e\.|etc\.|vs\.)|vs)(?![A-Za-z0-9_])'
$headingLineRegex = '^(#{1,6})\s+(.+)$'
$accidentalUnderscoreRegex = '\b[A-Za-z0-9]+_[^_\n`]*[\s,;:/][^_\n`]*_[A-Za-z0-9]+\b'
$italicWrappedRegex = '(?<![*_\\])(\*|_)(\s*`[^`]+`\s*|\s*\[[^\]]+\]\([^)]+\)\s*)\1(?![*_])'
$linkItalicRegex = '\[\s*(\*|_)[^\]*_]+\1\s*\]\([^)]+\)'

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

function Get-MarkdownHeadingSlugSet {
    param([string]$Text)
    $slugs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $slugCounts = @{}
    $inFence = $false
    foreach ($rawLine in ($Text -split "`n")) {
        $trimmed = $rawLine.Trim()
        if ($trimmed.StartsWith('```')) {
            $inFence = -not $inFence
            continue
        }
        if ($inFence) { continue }
        if ($trimmed.StartsWith('#')) {
            $title = $trimmed.TrimStart('#').Trim()
            if ($title -ne '') {
                $baseSlug = Get-GitHubHeadingSlug -Heading $title
                if ($baseSlug -ne '') {
                    $cnt = if ($slugCounts.ContainsKey($baseSlug)) { $slugCounts[$baseSlug] } else { 0 }
                    $slugCounts[$baseSlug] = $cnt + 1
                    $slug = if ($cnt -eq 0) { $baseSlug } else { "$baseSlug-$cnt" }
                    [void]$slugs.Add($slug)
                }
            }
        }
    }
    return $slugs
}

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
        if ($run -eq $TickCount) { return $i }
        $i += $run
    }
    return -1
}

function Get-LineWithoutInlineCode {
    param([string]$Line)
    $sb = [System.Text.StringBuilder]::new($Line.Length)
    $unmatched = $false
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
            $unmatched = $true
            [void]$sb.Append($Line.Substring($i, $tickCount))
            $i += $tickCount
            continue
        }
        [void]$sb.Append($Line[$i])
        $i++
    }
    return [pscustomobject]@{ Cleaned = $sb.ToString(); Unmatched = $unmatched }
}

function Find-StackedFormatting {
    param([string]$Line)
    if ($Line -match $italicWrappedRegex) { return $Matches[0] }
    if ($Line -match $linkItalicRegex) { return $Matches[0] }
    for ($i = 0; $i -lt $Line.Length; ) {
        if ($Line[$i] -eq '`') {
            $tickCount = 0
            while (($i + $tickCount) -lt $Line.Length -and $Line[$i + $tickCount] -eq '`') { $tickCount++ }
            $closeRel = Find-ClosingBacktickRun -Text $Line.Substring($i + $tickCount) -TickCount $tickCount
            if ($closeRel -ge 0) { $i += $tickCount + $closeRel + $tickCount; continue }
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

function Get-MarkdownLinkTargetList {
    param([string]$Line)
    $cleaned = (Get-LineWithoutInlineCode -Line $Line).Cleaned
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

$errors = [System.Collections.Generic.List[string]]::new()

# 1. Check AGENTS.md < 24 KB budget & single AGENTS.md invariant
$agentsPath = Join-Path $RootDir 'AGENTS.md'
if (Test-Path -LiteralPath $agentsPath) {
    $agentsLen = (Get-Item -LiteralPath $agentsPath).Length
    if ($agentsLen -ge 24576) {
        $errors.Add("AGENTS.md: size $agentsLen bytes exceeds 24 KB (24576-byte) context budget")
    }
} else {
    $errors.Add('AGENTS.md: missing root AGENTS.md')
}
if (Test-Path -LiteralPath (Join-Path $RootDir 'CLAUDE.md')) {
    $errors.Add('CLAUDE.md: forbidden duplicate agent file')
}
if (Test-Path -LiteralPath (Join-Path (Join-Path $RootDir '.agents') 'AGENTS.md')) {
    $errors.Add('.agents/AGENTS.md: forbidden duplicate agent file')
}

$docFiles = [System.Collections.Generic.List[string]]::new()
foreach ($rel in @(
    'README.md',
    'CONTRIBUTING.md',
    'AGENTS.md',
    'SECURITY.md',
    'llms.txt',
    '.github\PULL_REQUEST_TEMPLATE.md',
    '.agents\rules\monospace-tui.md',
    '.agents\skills\mono-tui-design\SKILL.md',
    '.agents\skills\mono-tui-audit\SKILL.md'
)) {
    $docFiles.Add($rel)
}
$docsDir = Join-Path $RootDir 'docs'
if (Test-Path -LiteralPath $docsDir) {
    foreach ($f in (Get-ChildItem -LiteralPath $docsDir -Filter '*.md' -Recurse -File | Sort-Object FullName)) {
        $rel = $f.FullName.Substring($RootDir.Length).TrimStart('\', '/')
        if (-not $docFiles.Contains($rel)) { $docFiles.Add($rel) }
    }
}

$yamlFiles = @(
    '.github\ISSUE_TEMPLATE\bug_report.yml',
    '.github\ISSUE_TEMPLATE\feature_request.yml',
    '.github\ISSUE_TEMPLATE\config.yml',
    '.github\dependabot.yml',
    '.github\workflows\ci.yml',
    '.github\workflows\security.yml'
)

foreach ($relYaml in $yamlFiles) {
    $fullYaml = Join-Path $RootDir $relYaml
    if (-not (Test-Path -LiteralPath $fullYaml)) { continue }
    $yamlText = [System.IO.File]::ReadAllText($fullYaml)
    if ($yamlText -match $docPersonalPathRegex) {
        $errors.Add("${relYaml}: personal path '$($Matches[0])'")
    }
    if ($yamlText -match $decorativeEmojiRegex) {
        $errors.Add("${relYaml}: decorative emoji or shortcode '$($Matches[0])'")
    }
}

$headingSlugCache = @{}
$loadedDocs = @{}

foreach ($relDoc in $docFiles) {
    $fullDoc = Join-Path $RootDir $relDoc
    if (-not (Test-Path -LiteralPath $fullDoc)) { continue }
    $normRel = $relDoc.Replace('\', '/')
    $strictDoc = ($normRel -in @('README.md', 'CONTRIBUTING.md', 'AGENTS.md')) -or $normRel.StartsWith('docs/') -or $normRel.StartsWith('.agents/')
    $isAgentDoc = $normRel.StartsWith('.agents/')

    $text = [System.IO.File]::ReadAllText($fullDoc)
    $loadedDocs[$normRel] = $text

    if ($text -match $docPersonalPathRegex) {
        $errors.Add("${normRel}: personal path '$($Matches[0])'")
    }
    if ($text -match $decorativeEmojiRegex) {
        $errors.Add("${normRel}: decorative emoji or shortcode '$($Matches[0])'")
    }

    $lines = $text -split "`n"
    $inFrontmatter = $false
    $inFence = $false
    $fenceLang = ''
    $fenceStart = 0
    $fenceBuf = [System.Text.StringBuilder]::new()
    $headingSlugs = Get-MarkdownHeadingSlugSet -Text $text
    $headingSlugCache[[System.IO.Path]::GetFullPath($fullDoc)] = $headingSlugs
    $pendingHeading = $null

    for ($idx = 0; $idx -lt $lines.Count; $idx++) {
        $lineNum = $idx + 1
        $line = $lines[$idx].TrimEnd("`r")
        $trimmed = $line.Trim()

        if ($isAgentDoc -and $idx -eq 0 -and $trimmed -eq '---') {
            $inFrontmatter = $true
            continue
        }
        if ($inFrontmatter) {
            if ($trimmed -eq '---') { $inFrontmatter = $false }
            continue
        }
        if ($trimmed.StartsWith('```')) {
            if (-not $inFence) {
                $inFence = $true
                $fenceLang = $trimmed.Substring(3).Trim().ToLowerInvariant()
                $fenceStart = $lineNum
                [void]$fenceBuf.Clear()
                $pendingHeading = $null
                if (-not $fenceLang -and $strictDoc) {
                    $errors.Add("${normRel}:${lineNum}: untagged opening code fence")
                }
            } else {
                if ($fenceLang -eq 'json' -and $strictDoc) {
                    try {
                        $null = $fenceBuf.ToString() | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        $errors.Add("${normRel}:${fenceStart}: invalid JSON code block")
                    }
                }
                $inFence = $false
                $fenceLang = ''
            }
            continue
        }
        if ($inFence) {
            [void]$fenceBuf.AppendLine($line)
            if ($normRel -eq 'README.md' -and ($line.Contains([char]0x251C) -or $line.Contains([char]0x2514)) -and $line.Contains('# ')) {
                $treeComment = ($line -split '# ', 2)[1]
                if ($treeComment.Contains(' + ') -or $treeComment.Contains('(+ ')) {
                    $errors.Add("${normRel}:${lineNum}: directory tree comment contains '+' connector")
                }
                if ($treeComment.Contains(' & ')) {
                    $errors.Add("${normRel}:${lineNum}: directory tree comment contains '&' connector")
                }
            }
            continue
        }

        if ($strictDoc -and $line -match $headingLineRegex) {
            $hashes = $Matches[1]
            if ($idx -gt 0 -and $lines[$idx - 1].Trim() -ne '') {
                $errors.Add("${normRel}:${lineNum}: heading '$trimmed' missing preceding blank line")
            }
            if (($idx + 1) -lt $lines.Count -and $lines[$idx + 1].Trim() -ne '') {
                $errors.Add("${normRel}:${lineNum}: heading '$trimmed' missing following blank line")
            }
            if ($null -ne $pendingHeading -and $pendingHeading.Hashes.Length -in @(2, 3)) {
                $errors.Add("${normRel}:$($pendingHeading.Line): heading '$($pendingHeading.Text)' immediately followed by '$trimmed' without introductory prose")
            }
            $pendingHeading = @{ Line = $lineNum; Hashes = $hashes; Text = $trimmed }
        } elseif ($trimmed -ne '' -and $trimmed -notmatch "^$htmlCommentRegex$") {
            $pendingHeading = $null
        }

        if ($trimmed -eq '---') {
            $errors.Add("${normRel}:${lineNum}: horizontal rule divider '---'")
        }
        if ($strictDoc -and $trimmed -match $boldTableCellRegex) {
            $errors.Add("${normRel}:${lineNum}: bolded first-column table cell '$($Matches[0].Trim())'")
        }

        $stacked = Find-StackedFormatting -Line $line
        if ($stacked -ne '') {
            $errors.Add("${normRel}:${lineNum}: stacked formatting '$stacked'")
        }

        $codeCheck = Get-LineWithoutInlineCode -Line $line
        if ($codeCheck.Unmatched) {
            $errors.Add("${normRel}:${lineNum}: unmatched inline backtick")
        }

        $cleanedLine = [regex]::Replace($codeCheck.Cleaned, $htmlCommentRegex, '')
        $origBody = $trimmed.TrimStart('*', '-').Trim()
        $isVerbatimOrig = $isAgentDoc -and ($origBody.StartsWith('**Original**: ') -or $origBody.StartsWith('**Original:** '))

        if (-not $isVerbatimOrig -and $cleanedLine -match $italicAsideRegex) {
            $errors.Add("${normRel}:${lineNum}: italic parenthetical aside '$($Matches[0])'")
        }
        if (-not $isVerbatimOrig -and $cleanedLine -match $asciiArrowRegex) {
            $errors.Add("${normRel}:${lineNum}: prose arrow '$($Matches[0])'")
        }

        if ($strictDoc -and -not $isVerbatimOrig) {
            $proseLine = [regex]::Replace([regex]::Replace($cleanedLine, '\]\((?:\\.|[^)])*\)', ']()'), 'https?://\S+', '')
            if ($proseLine -match $accidentalUnderscoreRegex) {
                $errors.Add("${normRel}:${lineNum}: unbackticked underscore span '$($Matches[0])'")
            }
            foreach ($sm in [regex]::Matches($proseLine, $proseSlashRegex)) {
                $tok = $sm.Groups[1].Value
                if (-not $allowedSlashTerms.Contains($tok)) {
                    $errors.Add("${normRel}:${lineNum}: prose slash '$tok'")
                }
            }
            if ($proseLine -match $proseAmpRegex) {
                $errors.Add("${normRel}:${lineNum}: prose ampersand ' & '")
            }
            if ($proseLine -match $prosePlusRegex) {
                $errors.Add("${normRel}:${lineNum}: prose plus connector ' + '")
            }
            if ($proseLine -match $latinAbbrevRegex) {
                $errors.Add("${normRel}:${lineNum}: forbidden Latin abbreviation '$($Matches[0])'")
            }
        }
    }

    if ($strictDoc) {
        $inFrontmatter = $false
        $inFence = $false
        $docDir = Split-Path -Parent $fullDoc
        for ($idx = 0; $idx -lt $lines.Count; $idx++) {
            $lineNum = $idx + 1
            $line = $lines[$idx].TrimEnd("`r")
            $trimmed = $line.Trim()
            if ($isAgentDoc -and $idx -eq 0 -and $trimmed -eq '---') { $inFrontmatter = $true; continue }
            if ($inFrontmatter) { if ($trimmed -eq '---') { $inFrontmatter = $false }; continue }
            if ($trimmed.StartsWith('```')) { $inFence = -not $inFence; continue }
            if ($inFence) { continue }

            foreach ($target in (Get-MarkdownLinkTargetList -Line $line)) {
                if ($target.StartsWith('#')) {
                    $slug = $target.Substring(1)
                    if (-not $headingSlugs.Contains($slug)) {
                        $errors.Add("${normRel}:${lineNum}: broken anchor link '$target'")
                    }
                    continue
                }
                if ($target.StartsWith('http://') -or $target.StartsWith('https://') -or $target.StartsWith('mailto:')) {
                    continue
                }
                $relTarget = $target
                $frag = ''
                $hashIdx = $target.IndexOf('#')
                if ($hashIdx -ge 0) {
                    $relTarget = $target.Substring(0, $hashIdx)
                    $frag = $target.Substring($hashIdx + 1)
                }
                if ($relTarget -eq '') { continue }
                $targetPath = [System.IO.Path]::GetFullPath((Join-Path $docDir ($relTarget.Replace('/', '\'))))
                if (-not (Test-Path -LiteralPath $targetPath)) {
                    $errors.Add("${normRel}:${lineNum}: broken relative file link '$target'")
                    continue
                }
                if ($frag -ne '' -and $targetPath.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase)) {
                    if (-not $headingSlugCache.ContainsKey($targetPath)) {
                        $headingSlugCache[$targetPath] = Get-MarkdownHeadingSlugSet -Text ([System.IO.File]::ReadAllText($targetPath))
                    }
                    if (-not $headingSlugCache[$targetPath].Contains($frag)) {
                        $errors.Add("${normRel}:${lineNum}: broken cross-file anchor link '$target'")
                    }
                }
            }
        }
    }
}

# 2. Code-to-README synchronization checks
$readmeText = $loadedDocs['README.md']
if ($readmeText) {
    # 2a. mise.toml [tools] vs README.md Developer toolchains table
    $misePath = Join-Path $RootDir 'mise.toml'
    if (Test-Path -LiteralPath $misePath) {
        $inTools = $false
        foreach ($mLine in ([System.IO.File]::ReadAllLines($misePath))) {
            $s = $mLine.Trim()
            if ($s.StartsWith('[')) {
                $inTools = ($s -eq '[tools]')
                continue
            }
            if ($inTools -and $s.Contains('=') -and -not $s.StartsWith('#')) {
                $toolKey = ($s -split '=', 2)[0].Trim().Trim('"').Trim("'")
                if (-not $readmeText.Contains("| ``$toolKey`` |")) {
                    $errors.Add("README.md: missing mise.toml tool '$toolKey' in Developer toolchains table")
                }
            }
        }
    }

    # 2b. setup.ps1 consolidated options vs README.md
    foreach ($setupOpt in @('-User', '-SystemOnly', '-UseDSC', '-Uninstall', '-Gui', '-Theme', '-Skip', '-DryRun', '-Help')) {
        if ($readmeText -notmatch [regex]::Escape($setupOpt)) {
            $errors.Add("README.md: missing setup.ps1 option '$setupOpt'")
        }
    }

    # 2c. ide 16 subcommands vs README.md Standalone utilities table
    $standaloneSec = if ($readmeText.Contains('## Standalone utilities')) { ($readmeText -split '## Standalone utilities', 2)[1] } else { $readmeText }
    $ideRowMatch = [regex]::Match($standaloneSec, '(?m)^\|\s*`ide`\s*\|.*$')
    $ideRow = if ($ideRowMatch.Success) { $ideRowMatch.Value } else { '' }
    foreach ($subcmd in @('list', 'switch', 'new', 'dir', 'agent', 'next', 'cd', 'refresh', 'quit', 'open', 'send', 'state', 'ack', 'pr', 'keys', 'monitor')) {
        if ($ideRow -notmatch "\b$([regex]::Escape($subcmd))\b") {
            $errors.Add("README.md: ide subcommand '$subcmd' missing from Standalone utilities table")
        }
    }

    # 2d. theme & update-system key options vs README.md Standalone utilities table
    $themeRowMatch = [regex]::Match($standaloneSec, '(?m)^\|\s*`theme`\s*\|.*$')
    $themeRow = if ($themeRowMatch.Success) { $themeRowMatch.Value } else { '' }
    foreach ($tFlag in @('--list', '--plain', '--current', '--set', '--holiday', '--preview', '--create', '--sync-assets', '--check-assets', '--dry-run')) {
        if ($themeRow -notmatch [regex]::Escape($tFlag)) {
            $errors.Add("README.md: theme option '$tFlag' missing from Standalone utilities table")
        }
    }
    $updRowMatch = [regex]::Match($standaloneSec, '(?m)^\|\s*`update-system`\s*\|.*$')
    $updRow = if ($updRowMatch.Success) { $updRowMatch.Value } else { '' }
    foreach ($uFlag in @('--all', '--system-only', '--skip', '--interactive', '--dry-run')) {
        if ($updRow -notmatch [regex]::Escape($uFlag)) {
            $errors.Add("README.md: update-system option '$uFlag' missing from Standalone utilities table")
        }
    }

    # 2e. Keybindings dual representation (both prose and reference table)
    $readmeTableLines = (($readmeText -split "`n") | Where-Object { $_.Trim().StartsWith('|') }) -join "`n"
    $readmeProseLines = (($readmeText -split "`n") | Where-Object { -not $_.Trim().StartsWith('|') }) -join "`n"
    $requiredDualKeys = @(
        'Space w', 'Space h', 'Space e', 'Space E', 'Space m',
        'Space ff', 'Space fg', 'Space fb', 'Space gs',
        'Space rn', 'Space ca', 'Space d',
        'Space a', 'Space A', 'Space il', 'Space if', 'Space ia', 'Space id',
        'Space t', 'Space s', 'Space n', 'Space o', 'Space q', 'Space ?', 'Space cd',
        'Space jo', 'Space jv', 'Space jc', 'Space jm',
        'gd', 'gr', 'K', 'gx', 'Home', 'H', 'L',
        'Alt+h/j/k/l', 'Alt+Shift+H/J/K/L', 'Alt+a', 'Alt+e', 'Alt+t',
        'Alt+n', 'Alt+o', 'Alt+u', 'Alt+Shift+A', 'Alt+Shift+E', 'Alt+Shift+T',
        'Alt+Shift+S', 'Alt+z', 'Alt+m', 'Alt+q', 'Alt+?', 'F1', 'F5',
        'Ctrl+b r', 'Ctrl+b d', 'Ctrl+b v', 'Ctrl+b s', 'Ctrl+b S'
    )
    foreach ($key in $requiredDualKeys) {
        if (-not $readmeProseLines.Contains($key)) {
            $errors.Add("README.md: keybinding '$key' missing from conceptual prose")
        }
        if (-not $readmeTableLines.Contains($key)) {
            $errors.Add("README.md: keybinding '$key' missing from reference table")
        }
    }
}

# 3. Verify .agents/rules/monospace-tui.md [OVERRIDE] / [WAIVE] verbatim Original quotes
$tuiRulePath = Join-Path $RootDir '.agents\rules\monospace-tui.md'
if (Test-Path -LiteralPath $tuiRulePath) {
    $refDir = Join-Path $RootDir '.agents\skills\mono-tui-design\references'
    $refParts = [System.Collections.Generic.List[string]]::new()
    foreach ($refName in @('standard.md', 'rendering.md', 'patterns.md')) {
        $rp = Join-Path $refDir $refName
        if (-not (Test-Path -LiteralPath $rp)) {
            $errors.Add(".agents/rules/monospace-tui.md: missing required reference file '$refName'")
        } else {
            $refParts.Add([System.IO.File]::ReadAllText($rp))
        }
    }
    $refCorpus = $refParts -join "`n"
    $ovrLines = [System.IO.File]::ReadAllText($tuiRulePath) -split "`n"
    $curH = ''
    $curHLine = 0
    $curHasOrig = $false
    $ovrCount = 0

    for ($idx = 0; $idx -lt $ovrLines.Count; $idx++) {
        $lineNo = $idx + 1
        $otrim = $ovrLines[$idx].Trim()
        if ($otrim.StartsWith('### ')) {
            if (($curH.StartsWith('[OVERRIDE]') -or $curH.StartsWith('[WAIVE]')) -and -not $curHasOrig) {
                $errors.Add(".agents/rules/monospace-tui.md:${curHLine} ($curH): missing **Original**: quote")
            }
            $curH = $otrim.Substring(4).Trim()
            $curHLine = $lineNo
            $curHasOrig = $false
            if ($curH.StartsWith('[OVERRIDE]') -or $curH.StartsWith('[WAIVE]')) { $ovrCount++ }
            continue
        }
        if ($otrim.StartsWith('## ')) {
            if (($curH.StartsWith('[OVERRIDE]') -or $curH.StartsWith('[WAIVE]')) -and -not $curHasOrig) {
                $errors.Add(".agents/rules/monospace-tui.md:${curHLine} ($curH): missing **Original**: quote")
            }
            $curH = ''
            $curHLine = 0
            $curHasOrig = $false
            continue
        }
        $bbody = $otrim.TrimStart('*', '-').Trim()
        $quoted = $null
        if ($bbody.StartsWith('**Original**: ')) {
            $quoted = $bbody.Substring('**Original**: '.Length).Trim()
        } elseif ($bbody.StartsWith('**Original:** ')) {
            $quoted = $bbody.Substring('**Original:** '.Length).Trim()
        }
        if ($null -ne $quoted) {
            $curHasOrig = $true
            if ($quoted -eq '') {
                $errors.Add(".agents/rules/monospace-tui.md:${lineNo} ($curH): empty Original field")
            } elseif ($refCorpus -ne '' -and -not $refCorpus.Contains($quoted)) {
                $errors.Add(".agents/rules/monospace-tui.md:${lineNo} ($curH): Original text not found verbatim in mono-tui references: $quoted")
            }
        }
    }
    if (($curH.StartsWith('[OVERRIDE]') -or $curH.StartsWith('[WAIVE]')) -and -not $curHasOrig) {
        $errors.Add(".agents/rules/monospace-tui.md:${curHLine} ($curH): missing **Original**: quote")
    }
    if ($ovrCount -eq 0) {
        $errors.Add('.agents/rules/monospace-tui.md: expected at least one ### [OVERRIDE] or ### [WAIVE] heading')
    }
}

if ($errors.Count -gt 0) {
    foreach ($e in $errors) {
        [Console]::Error.WriteLine($e)
    }
    exit 1
}
exit 0
