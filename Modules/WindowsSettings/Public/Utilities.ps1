# =============================================================
# Native Workstation Utilities & Modern Stream Tools
# =============================================================

# Cryptographically Secure Password Generator
function gen-passwd {
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

    if ($Upper -or $Lower -or $Numbers -or $Symbols) {
        if ($Upper) { $charSet += $upperChars }
        if ($Lower) { $charSet += $lowerChars }
        if ($Numbers) { $charSet += $numberChars }
        if ($Symbols) { $charSet += $symbolChars }
    } else {
        $charSet = $upperChars + $lowerChars
        if (-not $NoNumbers) { $charSet += $numberChars }
        if (-not $NoSymbols) { $charSet += $symbolChars }
    }

    $bytes = [byte[]]::new($Length)
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($bytes)

    $chars = [char[]]::new($Length)
    for ($i = 0; $i -lt $Length; $i++) {
        $chars[$i] = $charSet[$bytes[$i] % $charSet.Length]
    }

    -join $chars
}

# Repeat Command Until Success (Exit Code 0)
function repeat-until-success {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,

        [Alias('Interval', 'IntervalSeconds')]
        [Parameter(Position = 1)]
        [double]$Interval = 2.0,

        [Parameter(Position = 2)]
        [int]$MaxAttempts = 0
    )

    $attempt = 1
    while ($true) {
        Write-Host "[Attempt $attempt] Executing: $Command" -ForegroundColor Cyan
        $succeeded = $false
        try {
            $sb = [scriptblock]::Create($Command)
            & $sb
            if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                $succeeded = $true
            }
        } catch {
            Write-Warning "Attempt $attempt failed with exception: $_"
        }

        if ($succeeded) {
            Write-Host "[Success] Command succeeded on attempt $attempt" -ForegroundColor Green
            return
        }

        if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
            throw "Failed after $MaxAttempts attempts."
        }

        $attempt++
        Start-Sleep -Seconds $Interval
    }
}

# Numeric Pipeline Accumulator (1..10 | sum = 55)
function sum {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true, Position = 0)]
        [object[]]$InputObject
    )
    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $InputObject) {
            foreach ($i in $InputObject) {
                $items.Add($i)
            }
        }
    }
    end {
        $total = [decimal]0
        $hasFloat = $false
        foreach ($item in $items) {
            if ($null -ne $item) {
                $str = $item.ToString().Trim()
                if ($str -match '^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$') {
                    if ($str -contains '.') { $hasFloat = $true }
                    $val = [decimal]$str
                    $total += $val
                }
            }
        }
        if ($hasFloat -or ($total % 1 -ne 0)) {
            $total
        } else {
            [long]$total
        }
    }
}
