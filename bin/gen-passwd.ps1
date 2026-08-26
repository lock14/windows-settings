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
.EXAMPLE
    gen-passwd.ps1 20
    gen-passwd.ps1 -Length 24 -IncludeSymbols
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, 1024)]
    [int]$Length = 16,

    [bool]$IncludeSymbols = $true,
    [bool]$IncludeNumbers = $true,
    [switch]$UpperOnly,
    [switch]$LowerOnly
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
} else {
    $charSet = $upper + $lower
}

if ($IncludeNumbers -and -not $UpperOnly -and -not $LowerOnly) {
    $charSet += $numbers
}

if ($IncludeSymbols -and -not $UpperOnly -and -not $LowerOnly) {
    $charSet += $symbols
}

$bytes = [byte[]]::new($Length)
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$rng.GetBytes($bytes)

$chars = [char[]]::new($Length)
for ($i = 0; $i -lt $Length; $i++) {
    $chars[$i] = $charSet[$bytes[$i] % $charSet.Length]
}

-join $chars
