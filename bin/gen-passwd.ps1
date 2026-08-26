<#
.SYNOPSIS
    Generates a cryptographically secure random password.
.DESCRIPTION
    Ported from home-settings/common-bin/gen-passwd for native PowerShell usage.
.PARAMETER Length
    Length of the generated password (default: 16).
.PARAMETER IncludeSymbols
    Include special symbols in the password (enabled by default).
.PARAMETER IncludeNumbers
    Include numbers in the password (enabled by default).
.PARAMETER UpperOnly
    Use only uppercase letters.
.PARAMETER LowerOnly
    Use only lowercase letters.
.PARAMETER NumbersOnly
    Use only digits (0-9).
.PARAMETER SymbolsOnly
    Use only special symbols.
.PARAMETER NoSymbols
    Exclude symbols from the password character set.
.PARAMETER NoNumbers
    Exclude numbers from the password character set.
.EXAMPLE
    gen-passwd 20
    gen-passwd -Length 24 -IncludeSymbols
    gen-passwd -NoSymbols
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 1024)]
    [int]$Length = 16,

    [Alias('s')]
    [switch]$IncludeSymbols,

    [Alias('n')]
    [switch]$IncludeNumbers,

    [Alias('u')]
    [switch]$UpperOnly,

    [Alias('l')]
    [switch]$LowerOnly,

    [switch]$NumbersOnly,
    [switch]$SymbolsOnly,
    [switch]$NoSymbols,
    [switch]$NoNumbers
)

$upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$lower = 'abcdefghijklmnopqrstuvwxyz'
$numbers = '0123456789'
$symbols = '^*@#&%$!'

$charSet = ''

if ($UpperOnly) {
    $charSet = $upper
} elseif ($LowerOnly) {
    $charSet = $lower
} elseif ($NumbersOnly) {
    $charSet = $numbers
} elseif ($SymbolsOnly) {
    $charSet = $symbols
} else {
    # Default is full set: uppercase + lowercase + numbers + symbols
    $charSet = $upper + $lower
    if ((-not $NoNumbers) -or $IncludeNumbers) {
        $charSet += $numbers
    }
    if ((-not $NoSymbols) -or $IncludeSymbols) {
        $charSet += $symbols
    }
}

$bytes = [byte[]]::new($Length)
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)

$chars = [char[]]::new($Length)
for ($i = 0; $i -lt $Length; $i++) {
    $chars[$i] = $charSet[$bytes[$i] % $charSet.Length]
}

-join $chars
