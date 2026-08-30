# =============================================================
# Native Workstation Utilities & Modern Stream Tools
# =============================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRootDir = Split-Path -Parent (Split-Path -Parent $scriptDir)
$binDir = Join-Path $repoRootDir "bin"

# Cryptographically Secure Password Generator
function gen-passwd {
    [CmdletBinding()]
    param(
        [int]$Length = 20,
        [switch]$IncludeSymbols
    )
    if (Test-Path "$binDir\gen-passwd.ps1") {
        & "$binDir\gen-passwd.ps1" @PSBoundParameters
    } else {
        $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        if ($IncludeSymbols) { $chars += "!@#$%^&*()-_=+[]{}<>~" }
        $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
        $bytes = [byte[]]::new($Length)
        $rng.GetBytes($bytes)
        $result = [char[]]::new($Length)
        for ($i = 0; $i -lt $Length; $i++) {
            $result[$i] = $chars[$bytes[$i] % $chars.Length]
        }
        -join $result
    }
}

# Repeat Command Until Success (Exit Code 0)
function repeat-until-success {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Command,
        [int]$Interval = 2,
        [int]$MaxAttempts = 0
    )
    if (Test-Path "$binDir\repeat-until-success.ps1") {
        & "$binDir\repeat-until-success.ps1" @PSBoundParameters
    } else {
        $attempt = 1
        while ($true) {
            Write-Host "Attempt #$attempt..." -ForegroundColor Cyan
            try {
                Invoke-Expression $Command
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "Command succeeded on attempt #$attempt!" -ForegroundColor Green
                    return
                }
            } catch {
                Write-Warning "Execution failed: $_"
            }
            if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
                Write-Error "Failed after $MaxAttempts attempts."
                return
            }
            Start-Sleep -Seconds $Interval
            $attempt++
        }
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
        if (Test-Path "$binDir\sum.ps1") {
            & "$binDir\sum.ps1" @items
        } else {
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
}
