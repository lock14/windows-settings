<#
.SYNOPSIS
    Sums numbers from standard input / pipeline, command-line arguments, or files.
.DESCRIPTION
    Ported from home-settings/bin/sum with full flag parity (-d, -k, -H, -a, -s, -f, -h/--help)
    and exact decimal precision for native PowerShell and CMD pipelines.
#>

$ErrorActionPreference = 'Stop'

$script:UsageText = @"
usage: sum [options] [numbers... | files...]

Sum numbers from command line arguments, standard input, or files.

Options:
  -d <delim>   Field delimiter (default: whitespace, auto-splits commas if -d not set)
  -k <col>     Sum only the specified column number (1-indexed)
  -H           Parse human-readable byte unit suffixes (K/KiB, M/MiB, G/GiB, T/TiB, P/PiB, E/EiB)
  -a           Output average (mean) instead of sum
  -s           Output summary statistics (count, min, max, mean, sum)
  -f <fmt>     Format specifier for output numbers (such as '%.2f', '%d', or '{0:F2}')
  -h, --help   Show this help message
"@

function Test-NumericToken([string]$Token, [bool]$HumanMode) {
    if ($Token -match '^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([eE][+-]?[0-9]+)?$') {
        return $true
    }
    if ($HumanMode -and $Token -match '^[+-]?([0-9]+\.?[0-9]*|\.[0-9]+)([kKmMgGtTpPeE]i?[bB]?)$') {
        return $true
    }
    return $false
}

function ConvertTo-NumericValue([string]$Token, [bool]$HumanMode) {
    if ($HumanMode -and $Token -match '^([+-]?(?:[0-9]+\.?[0-9]*|\.[0-9]+))([kKmMgGtTpPeE])i?[bB]?$') {
        $baseVal = [decimal]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)
        $unit = $Matches[2].ToUpperInvariant()
        $mult = switch ($unit) {
            'K' { [decimal]1024 }
            'M' { [decimal]1048576 }
            'G' { [decimal]1073741824 }
            'T' { [decimal]1099511627776 }
            'P' { [decimal]1125899906842624 }
            'E' { [decimal]1152921504606846976 }
            default { [decimal]1 }
        }
        return ($baseVal * $mult)
    }
    try {
        return [decimal]::Parse($Token, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture)
    } catch {
        return [decimal]([double]::Parse($Token, [System.Globalization.CultureInfo]::InvariantCulture))
    }
}

function Format-SumNumber([decimal]$Val, [string]$Fmt, [bool]$ForceDecimal = $false) {
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Fmt) {
        if ($Fmt -match '^%([0-9]*)(?:\.([0-9]+))?([fFeEgGdDiI])$') {
            $prec = $Matches[2]
            $spec = $Matches[3]
            if ($spec -in @('d', 'i', 'D', 'I')) {
                return ([Math]::Truncate($Val)).ToString('0', $inv)
            }
            if ($spec -in @('f', 'F')) {
                $p = if ($prec -ne '') { [int]$prec } else { 6 }
                return $Val.ToString("F$p", $inv)
            }
            if ($spec -in @('e', 'E')) {
                $p = if ($prec -ne '') { [int]$prec } else { 6 }
                return ([double]$Val).ToString("$spec$p", $inv)
            }
            $p = if ($prec -ne '') { [int]$prec } else { 6 }
            return ([double]$Val).ToString("G$p", $inv)
        }
        if ($Fmt.Contains('{0')) {
            return [string]::Format($inv, $Fmt, $Val)
        }
        return $Val.ToString($Fmt, $inv)
    }
    if ($ForceDecimal -or ($Val % 1 -ne 0)) {
        return $Val.ToString('G29', $inv)
    }
    if ($Val -ge [decimal][long]::MinValue -and $Val -le [decimal][long]::MaxValue) {
        return ([long]$Val).ToString($inv)
    }
    return ([Math]::Truncate($Val)).ToString('0', $inv)
}

$delim = ''
$col = 0
$human = $false
$avg = $false
$stats = $false
$fmt = ''
$endOfOpts = $false
$restArgs = [System.Collections.Generic.List[object]]::new()

:ParseLoop for ($i = 0; $i -lt $args.Count; $i++) {
    $rawObj = $args[$i]
    if ($rawObj -isnot [string]) {
        $restArgs.Add($rawObj)
        continue ParseLoop
    }
    $arg = [string]$rawObj
    if (-not $endOfOpts -and $arg -eq '--') {
        $endOfOpts = $true
        continue ParseLoop
    }
    if (-not $endOfOpts -and $arg.StartsWith('-') -and $arg.Length -gt 1 -and $arg -notmatch '^-[0-9.]') {
        if ($arg -cmatch '^(-h|--help|-\?)$') {
            Write-Output $script:UsageText
            exit 0
        }
        if ($arg -cmatch '^-d$') {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Invalid option: -d requires an argument')
                exit 1
            }
            $delim = [string]$args[++$i]
            continue ParseLoop
        }
        if ($arg -cmatch '^-k$') {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Invalid option: -k requires an argument')
                exit 1
            }
            $colStr = [string]$args[++$i]
            $parsedCol = 0
            if ($colStr -notmatch '^[0-9]+$' -or -not [int]::TryParse($colStr, [ref]$parsedCol) -or $parsedCol -le 0) {
                [Console]::Error.WriteLine('Error: column (-k) must be a positive integer')
                exit 1
            }
            $col = $parsedCol
            continue ParseLoop
        }
        if ($arg -cmatch '^-f$') {
            if ($i + 1 -ge $args.Count) {
                [Console]::Error.WriteLine('Invalid option: -f requires an argument')
                exit 1
            }
            $fmt = [string]$args[++$i]
            continue ParseLoop
        }
        if ($arg.StartsWith('--')) {
            [Console]::Error.WriteLine("Invalid option: $arg")
            exit 1
        }
        # Support combined short flags such as -Hs or -Ha
        $flags = $arg.Substring(1)
        for ($cIdx = 0; $cIdx -lt $flags.Length; $cIdx++) {
            $ch = [string]$flags[$cIdx]
            switch -CaseSensitive ($ch) {
                'H' { $human = $true }
                'a' { $avg = $true }
                's' { $stats = $true }
                't' { }
                'h' {
                    Write-Output $script:UsageText
                    exit 0
                }
                'd' {
                    $rem = $flags.Substring($cIdx + 1)
                    if ($rem) {
                        $delim = $rem
                    } elseif ($i + 1 -lt $args.Count) {
                        $delim = [string]$args[++$i]
                    } else {
                        [Console]::Error.WriteLine('Invalid option: -d requires an argument')
                        exit 1
                    }
                    $cIdx = $flags.Length
                }
                'k' {
                    $rem = $flags.Substring($cIdx + 1)
                    $colStr = if ($rem) { $rem } elseif ($i + 1 -lt $args.Count) { [string]$args[++$i] } else { '' }
                    $parsedCol = 0
                    if ($colStr -notmatch '^[0-9]+$' -or -not [int]::TryParse($colStr, [ref]$parsedCol) -or $parsedCol -le 0) {
                        [Console]::Error.WriteLine('Error: column (-k) must be a positive integer')
                        exit 1
                    }
                    $col = $parsedCol
                    $cIdx = $flags.Length
                }
                'f' {
                    $rem = $flags.Substring($cIdx + 1)
                    if ($rem) {
                        $fmt = $rem
                    } elseif ($i + 1 -lt $args.Count) {
                        $fmt = [string]$args[++$i]
                    } else {
                        [Console]::Error.WriteLine('Invalid option: -f requires an argument')
                        exit 1
                    }
                    $cIdx = $flags.Length
                }
                default {
                    [Console]::Error.WriteLine("Invalid option: -$ch")
                    exit 1
                }
            }
        }
        continue ParseLoop
    }
    $restArgs.Add($rawObj)
}

$script:SumTotal = [decimal]0
$script:ItemCount = 0
$script:MinVal = [decimal]0
$script:MaxVal = [decimal]0
$script:HasFloat = $false

function Add-CandidateToken([string]$RawToken) {
    $tok = $RawToken.Trim()
    if (-not $tok) { return }
    if (Test-NumericToken -Token $tok -HumanMode $human) {
        if ($tok.Contains('.') -and -not ($human -and $tok -match '[a-zA-Z]$')) {
            $script:HasFloat = $true
        }
        $val = ConvertTo-NumericValue -Token $tok -HumanMode $human
        $script:SumTotal += $val
        $script:ItemCount++
        if ($script:ItemCount -eq 1 -or $val -lt $script:MinVal) { $script:MinVal = $val }
        if ($script:ItemCount -eq 1 -or $val -gt $script:MaxVal) { $script:MaxVal = $val }
    }
}

function Read-SumLine([string]$Line) {
    if ($null -eq $Line) { return }
    $fields = if ($delim -ne '') {
        $Line -split [regex]::Escape($delim)
    } else {
        ($Line.Trim() -split '\s+') | Where-Object { $_ -ne '' }
    }
    if ($col -gt 0) {
        if ($col -le $fields.Count) {
            Add-CandidateToken $fields[$col - 1]
        }
        return
    }
    foreach ($f in $fields) {
        if ($delim -eq '' -and $f.Contains(',')) {
            foreach ($part in ($f -split ',')) {
                Add-CandidateToken $part
            }
        } else {
            Add-CandidateToken $f
        }
    }
}

function Test-NumericArgumentString([string]$ArgStr) {
    if (-not $ArgStr) { return $false }
    if (Test-NumericToken -Token $ArgStr.Trim() -HumanMode $human) { return $true }
    if ($delim -eq '') {
        $norm = ($ArgStr.Replace(',', ' ').Trim() -split '\s+') | Where-Object { $_ -ne '' }
        if ($norm.Count -eq 0) { return $false }
        foreach ($t in $norm) {
            if (-not (Test-NumericToken -Token $t -HumanMode $human)) { return $false }
        }
        return $true
    }
    if (-not (Test-Path -LiteralPath $ArgStr)) {
        $parts = $ArgStr -split [regex]::Escape($delim)
        if ($parts.Count -lt 2) { return $false }
        if ($col -gt 0) {
            return ($col -le $parts.Count -and (Test-NumericToken -Token $parts[$col - 1].Trim() -HumanMode $human))
        }
        foreach ($p in $parts) {
            if (-not (Test-NumericToken -Token $p.Trim() -HumanMode $human)) { return $false }
        }
        return $true
    }
    return $false
}

if ($restArgs.Count -gt 0) {
    $pipeLoaded = $false
    $pipeItems = @()
    foreach ($item in $restArgs) {
        if ($item -is [System.Collections.IEnumerable] -and $item -isnot [string]) {
            foreach ($sub in $item) {
                if ($null -ne $sub) {
                    foreach ($ln in ("$sub" -split "`r?`n")) { Read-SumLine $ln }
                }
            }
            continue
        }
        $argStr = "$item"
        if ($argStr -eq '-') {
            if (-not $pipeLoaded) {
                $pipeItems = @($input)
                $pipeLoaded = $true
            }
            if ($pipeItems.Count -gt 0) {
                foreach ($pi in $pipeItems) {
                    if ($null -ne $pi) {
                        foreach ($ln in ("$pi" -split "`r?`n")) { Read-SumLine $ln }
                    }
                }
            } elseif ([Console]::IsInputRedirected) {
                while ($null -ne ($ln = [Console]::In.ReadLine())) { Read-SumLine $ln }
            }
            continue
        }
        if (Test-NumericArgumentString $argStr) {
            foreach ($ln in ($argStr -split "`r?`n")) { Read-SumLine $ln }
            continue
        }
        if (Test-Path -LiteralPath $argStr -PathType Container) {
            [Console]::Error.WriteLine("Error: ${argStr}: Is a directory")
            exit 1
        }
        if (-not (Test-Path -LiteralPath $argStr -PathType Leaf)) {
            [Console]::Error.WriteLine("Error: ${argStr}: No such file or directory")
            exit 1
        }
        foreach ($ln in [System.IO.File]::ReadLines((Resolve-Path -LiteralPath $argStr).ProviderPath)) {
            Read-SumLine $ln
        }
    }
} else {
    $pipeItems = @($input)
    if ($pipeItems.Count -gt 0) {
        foreach ($pi in $pipeItems) {
            if ($pi -is [System.Collections.IEnumerable] -and $pi -isnot [string]) {
                foreach ($sub in $pi) {
                    if ($null -ne $sub) {
                        foreach ($ln in ("$sub" -split "`r?`n")) { Read-SumLine $ln }
                    }
                }
            } elseif ($null -ne $pi) {
                foreach ($ln in ("$pi" -split "`r?`n")) { Read-SumLine $ln }
            }
        }
    } elseif ([Console]::IsInputRedirected) {
        while ($null -ne ($ln = [Console]::In.ReadLine())) {
            Read-SumLine $ln
        }
    }
}

$mean = if ($script:ItemCount -gt 0) { $script:SumTotal / $script:ItemCount } else { [decimal]0 }

if ($stats) {
    Write-Output "count: $($script:ItemCount)"
    Write-Output "min: $(Format-SumNumber -Val $script:MinVal -Fmt $fmt)"
    Write-Output "max: $(Format-SumNumber -Val $script:MaxVal -Fmt $fmt)"
    Write-Output "mean: $(Format-SumNumber -Val $mean -Fmt $fmt)"
    Write-Output "sum: $(Format-SumNumber -Val $script:SumTotal -Fmt $fmt -ForceDecimal $script:HasFloat)"
    exit 0
}

if ($avg) {
    if ($fmt) {
        Write-Output (Format-SumNumber -Val $mean -Fmt $fmt)
    } elseif ($mean % 1 -ne 0) {
        Write-Output $mean
    } else {
        Write-Output ([long]$mean)
    }
    exit 0
}

if ($fmt) {
    Write-Output (Format-SumNumber -Val $script:SumTotal -Fmt $fmt)
} elseif ($script:HasFloat -or ($script:SumTotal % 1 -ne 0)) {
    Write-Output $script:SumTotal
} elseif ($script:SumTotal -ge [decimal][long]::MinValue -and $script:SumTotal -le [decimal][long]::MaxValue) {
    Write-Output ([long]$script:SumTotal)
} else {
    Write-Output ([Math]::Truncate($script:SumTotal))
}
