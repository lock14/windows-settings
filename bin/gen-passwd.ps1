<#
.SYNOPSIS
    Generates a cryptographically secure random password.
.DESCRIPTION
    Ported from home-settings/common-bin/gen-passwd for native PowerShell usage.
.PARAMETER Length
    Length of the generated password (default: 16).
.PARAMETER IncludeSymbols
    Include special symbols in the password character set.
.PARAMETER IncludeNumbers
    Include numbers in the password character set.
.PARAMETER UpperOnly
    Use only uppercase letters.
.PARAMETER LowerOnly
    Use only lowercase letters.
.PARAMETER NoSymbols
    Exclude symbols from the default character set.
.PARAMETER NoNumbers
    Exclude numbers from the default character set.
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

    [Alias('s', 'Symbols')]
    [switch]$IncludeSymbols,

    [Alias('n', 'Numbers')]
    [switch]$IncludeNumbers,

    [Alias('u')]
    [switch]$UpperOnly,

    [Alias('l')]
    [switch]$LowerOnly,

    [switch]$NoSymbols,
    [switch]$NoNumbers
)

$upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$lower = 'abcdefghijklmnopqrstuvwxyz'
$numbers = '0123456789'
$symbols = '^*@#&%$!'

$charSet = ''

if ($UpperOnly) {
    $charSet += $upper
}
if ($LowerOnly) {
    $charSet += $lower
}
if ($IncludeNumbers) {
    $charSet += $numbers
}
if ($IncludeSymbols) {
    $charSet += $symbols
}

# Default character set when no specific subset is selected
if ($charSet -eq '') {
    $charSet = $upper + $lower
    if (-not $NoNumbers) { $charSet += $numbers }
    if (-not $NoSymbols) { $charSet += $symbols }
}

$bytes = [byte[]]::new($Length)
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)

$chars = [char[]]::new($Length)
for ($i = 0; $i -lt $Length; $i++) {
    $chars[$i] = $charSet[$bytes[$i] % $charSet.Length]
}

-join $chars
