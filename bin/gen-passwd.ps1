<#
.SYNOPSIS
    Generates a cryptographically secure random password without modulo bias.
.DESCRIPTION
    Ported from home-settings/bin/gen-passwd with exact flag and composability parity,
    rejection sampling via RandomNumberGenerator.GetInt32, and PowerShell parameter support.
#>

$ErrorActionPreference = 'Stop'

$script:UsageText = @"
usage: gen-passwd [-s] [-n] [-u] [-l] [-NoSymbols] [-NoNumbers] [length]

Generate a cryptographically secure random password (default length: 16).

Options:
  -s, -Symbols     Include special symbols (^*@#&%`$!-) in custom subset
  -n, -Numbers     Include digits (0-9) in custom subset
  -u, -Upper       Include uppercase letters (A-Z) in custom subset
  -l, -Lower       Include lowercase letters (a-z) in custom subset
  -NoSymbols       Exclude symbols from default full character set
  -NoNumbers       Exclude digits from default full character set
  -h, --help       Show this help message
"@

$length = 16
$hasLength = $false
$useSymbols = $false
$useNumbers = $false
$useUpper = $false
$useLower = $false
$noSymbols = $false
$noNumbers = $false
$endOfOpts = $false

:ParseLoop for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    if (-not $endOfOpts -and $arg -eq '--') {
        $endOfOpts = $true
        continue ParseLoop
    }
    if (-not $endOfOpts -and $arg.StartsWith('-') -and $arg.Length -gt 1) {
        switch -Regex ($arg) {
            '^(-h|--help|-Help|-\?)$' {
                Write-Output $script:UsageText
                exit 0
            }
            '^(-Length|--length)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine('gen-passwd: -Length requires a positive integer')
                    exit 1
                }
                $arg = [string]$args[++$i]
                break
            }
            '^(-s|-Symbols|-SymbolsOnly|-IncludeSymbols|--symbols)$' {
                $useSymbols = $true
                continue ParseLoop
            }
            '^(-n|-Numbers|-NumbersOnly|-IncludeNumbers|--numbers)$' {
                $useNumbers = $true
                continue ParseLoop
            }
            '^(-u|-Upper|-UpperOnly|--upper)$' {
                $useUpper = $true
                continue ParseLoop
            }
            '^(-l|-Lower|-LowerOnly|--lower)$' {
                $useLower = $true
                continue ParseLoop
            }
            '^(-NoSymbols|--no-symbols)$' {
                $noSymbols = $true
                continue ParseLoop
            }
            '^(-NoNumbers|--no-numbers)$' {
                $noNumbers = $true
                continue ParseLoop
            }
            '^-[snulh]+$' {
                foreach ($ch in $arg.Substring(1).ToCharArray()) {
                    switch ([string]$ch) {
                        's' { $useSymbols = $true }
                        'n' { $useNumbers = $true }
                        'u' { $useUpper = $true }
                        'l' { $useLower = $true }
                        'h' {
                            Write-Output $script:UsageText
                            exit 0
                        }
                    }
                }
                continue ParseLoop
            }
            default {
                [Console]::Error.WriteLine("gen-passwd: unknown option '$arg'")
                exit 1
            }
        }
    }

    $parsedLen = 0
    if ($hasLength -or $arg -notmatch '^[0-9]+$' -or -not [int]::TryParse($arg, [ref]$parsedLen) -or $parsedLen -lt 1 -or $parsedLen -gt 4096) {
        [Console]::Error.WriteLine("gen-passwd: invalid password length '$arg' (expected integer 1..4096)")
        exit 1
    }
    $length = $parsedLen
    $hasLength = $true
}

$upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$lowerChars = 'abcdefghijklmnopqrstuvwxyz'
$numberChars = '0123456789'
$symbolChars = '^*@#&%$!-'

$charSet = ''
if ($useUpper -or $useLower -or $useNumbers -or $useSymbols) {
    if ($useUpper) { $charSet += $upperChars }
    if ($useLower) { $charSet += $lowerChars }
    if ($useNumbers) { $charSet += $numberChars }
    if ($useSymbols) { $charSet += $symbolChars }
} else {
    $charSet = $upperChars + $lowerChars
    if (-not $noNumbers) { $charSet += $numberChars }
    if (-not $noSymbols) { $charSet += $symbolChars }
}

if (-not $charSet) {
    [Console]::Error.WriteLine('gen-passwd: character set is empty')
    exit 1
}

$chars = [char[]]::new($length)
for ($idx = 0; $idx -lt $length; $idx++) {
    $randIdx = [System.Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $charSet.Length)
    $chars[$idx] = $charSet[$randIdx]
}

Write-Output (-join $chars)
