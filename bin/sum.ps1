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
    $total = [decimal]0
    $hasInputObject = $false
    $hasFloat = $false
}

process {
    if ($null -ne $InputObject) {
        $hasInputObject = $true
        foreach ($item in $InputObject) {
            if ($null -ne $item) {
                # Handle multiline string blocks
                $lines = "$item" -split "`r?`n"
                foreach ($line in $lines) {
                    $str = $line.Trim()
                    if ($str -match '^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$') {
                        if ($str.Contains('.')) { $hasFloat = $true }
                        $val = [decimal]$str
                        $total += $val
                    }
                }
            }
        }
    }
}

end {
    # If InputObject was not provided through pipeline/arguments and standard input is redirected (e.g. via cmd.exe pipe)
    if (-not $hasInputObject -and [Console]::IsInputRedirected) {
        while ($null -ne ($line = [Console]::In.ReadLine())) {
            $str = $line.Trim()
            if ($str -match '^[-+]?[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$') {
                if ($str.Contains('.')) { $hasFloat = $true }
                $val = [decimal]$str
                $total += $val
            }
        }
    }

    # If the number is a whole integer, output as integer
    if ($hasFloat -or ($total % 1 -ne 0)) {
        $total
    } else {
        [long]$total
    }
}

