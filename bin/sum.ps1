<#
.SYNOPSIS
    Sums numbers from standard input / pipeline or arguments.
.DESCRIPTION
    Ported from home-settings/common-bin/sum for native PowerShell usage.
.EXAMPLE
    sum.ps1 1 2 3
    1..10 | sum.ps1
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true, Position = 0)]
    [object[]]$InputObject
)

begin {
    [double]$total = 0.0
}

process {
    if ($null -ne $InputObject) {
        foreach ($item in $InputObject) {
            if ($null -ne $item) {
                # Handle multiline string blocks
                $lines = "$item" -split "`r?`n"
                foreach ($line in $lines) {
                    $trimmed = $line.Trim()
                    if ($trimmed -match '^-?\d+(\.\d+)?$') {
                        $total += [double]$trimmed
                    }
                }
            }
        }
    }
}

end {
    # If the number is a whole integer, output as integer
    if ($total -eq [math]::Floor($total)) {
        [long]$total
    } else {
        $total
    }
}
