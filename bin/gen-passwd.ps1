<#
.SYNOPSIS
    Generates a cryptographically secure random password.
.DESCRIPTION
    Ported from home-settings/common-bin/gen-passwd with exact flag and composability parity.
.PARAMETER Length
    Length of the generated password (default: 16).
.PARAMETER Symbols
    Include special symbols in custom subset, or select symbols only (-s).
.PARAMETER Numbers
    Include numbers in custom subset, or select numbers only (-n).
.PARAMETER Upper
    Include uppercase letters in custom subset, or select uppercase only (-u).
.PARAMETER Lower
    Include lowercase letters in custom subset, or select lowercase only (-l).
.PARAMETER NoSymbols
    Exclude symbols from default character set.
.PARAMETER NoNumbers
    Exclude numbers from default character set.
.EXAMPLE
    gen-passwd 20
    gen-passwd -n 16
    gen-passwd -u -n 16
    gen-passwd -u -l -n 16
    gen-passwd -NoSymbols 24
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 1024)]
    [int]$Length = 16,

    [Alias('s', 'SymbolsOnly', 'IncludeSymbols')]
    [switch]$Symbols,

    [Alias('n', 'NumbersOnly', 'IncludeNumbers')]
    [switch]$Numbers,

    [Alias('u', 'UpperOnly')]
    [switch]$Upper,

    [Alias('l', 'LowerOnly')]
    [switch]$Lower,

    [switch]$NoSymbols,
    [switch]$NoNumbers
)

$upperChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$lowerChars = 'abcdefghijklmnopqrstuvwxyz'
$numberChars = '0123456789'
$symbolChars = '^*@#&%$!'

$charSet = ''

# If any specific subset flag was provided, compose only the selected sets (exact home-settings parity)
if ($Upper -or $Lower -or $Numbers -or $Symbols) {
    if ($Upper) {
        $charSet += $upperChars
    }
    if ($Lower) {
        $charSet += $lowerChars
    }
    if ($Numbers) {
        $charSet += $numberChars
    }
    if ($Symbols) {
        $charSet += $symbolChars
    }
} else {
    # Default is full set: uppercase + lowercase + numbers + symbols
    $charSet = $upperChars + $lowerChars
    if (-not $NoNumbers) {
        $charSet += $numberChars
    }
    if (-not $NoSymbols) {
        $charSet += $symbolChars
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
