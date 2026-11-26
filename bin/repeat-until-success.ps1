<#
.SYNOPSIS
    Retries a command until it succeeds (exit code 0).
.DESCRIPTION
    Ported from home-settings/bin/repeat-until-success with full flag parity
    (-n <max>, -s/-d <delay>, -t <timeout>, --, -h/--help) and PowerShell backward compatibility
    (-Command, -IntervalSeconds, -MaxAttempts).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Resetting LASTEXITCODE before command invocation')]
param()

$ErrorActionPreference = 'Stop'

$script:UsageText = @"
usage: repeat-until-success [options] [--] <command> [args...]

Retry a command until it exits with status 0.

Options:
  -n, -MaxAttempts <int>         Maximum attempts before failing (0 = infinite, default: 0)
  -s, -d, -IntervalSeconds <sec> Delay in seconds between attempts (default: 2)
  -t <sec>                       Per-attempt timeout in seconds (0 = none, default: 0)
  -Command <str>                 PowerShell command string to execute
  -h, --help                     Show this help message
"@

$maxAttempts = 0
$delaySec = 2.0
$timeoutSec = 0.0
$explicitCommand = $null
$cmdTokens = [System.Collections.Generic.List[string]]::new()
$endOfOpts = $false
$inv = [System.Globalization.CultureInfo]::InvariantCulture

:ParseLoop for ($i = 0; $i -lt $args.Count; $i++) {
    $arg = [string]$args[$i]
    if (-not $endOfOpts -and $arg -eq '--') {
        $endOfOpts = $true
        continue ParseLoop
    }
    if (-not $endOfOpts -and $cmdTokens.Count -eq 0 -and $null -eq $explicitCommand -and $arg.StartsWith('-') -and $arg.Length -gt 1) {
        switch -Regex ($arg) {
            '^(-h|--help|-Help|-\?)$' {
                Write-Output $script:UsageText
                exit 0
            }
            '^(-n|--max-attempts|-MaxAttempts)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires an integer argument")
                    exit 1
                }
                $valStr = [string]$args[++$i]
                $parsedN = 0
                if (-not [int]::TryParse($valStr, [ref]$parsedN) -or $parsedN -lt 0) {
                    [Console]::Error.WriteLine("repeat-until-success: invalid max attempts '$valStr'")
                    exit 1
                }
                $maxAttempts = $parsedN
                continue ParseLoop
            }
            '^(-s|-d|--delay|--sleep|-Interval|-IntervalSeconds)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires a numeric delay in seconds")
                    exit 1
                }
                $valStr = [string]$args[++$i]
                $parsedD = 0.0
                if (-not [double]::TryParse($valStr, [System.Globalization.NumberStyles]::Float, $inv, [ref]$parsedD) -or $parsedD -lt 0) {
                    [Console]::Error.WriteLine("repeat-until-success: invalid delay '$valStr'")
                    exit 1
                }
                $delaySec = $parsedD
                continue ParseLoop
            }
            '^(-t|--timeout|-TimeoutSeconds)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires a numeric timeout in seconds")
                    exit 1
                }
                $valStr = [string]$args[++$i]
                $parsedT = 0.0
                if (-not [double]::TryParse($valStr, [System.Globalization.NumberStyles]::Float, $inv, [ref]$parsedT) -or $parsedT -lt 0) {
                    [Console]::Error.WriteLine("repeat-until-success: invalid timeout '$valStr'")
                    exit 1
                }
                $timeoutSec = $parsedT
                continue ParseLoop
            }
            '^(-Command|--command)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires a command string")
                    exit 1
                }
                $explicitCommand = [string]$args[++$i]
                continue ParseLoop
            }
            default {
                [Console]::Error.WriteLine("repeat-until-success: unknown option '$arg'")
                exit 1
            }
        }
    }
    if (-not $endOfOpts -and $arg -match '^(-MaxAttempts|-Interval|-IntervalSeconds|-TimeoutSeconds)$') {
        switch -Regex ($arg) {
            '^-MaxAttempts$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires an integer argument")
                    exit 1
                }
                $maxAttempts = [int]::Parse([string]$args[++$i], $inv)
                continue ParseLoop
            }
            '^(-Interval|-IntervalSeconds)$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires a numeric delay in seconds")
                    exit 1
                }
                $delaySec = [double]::Parse([string]$args[++$i], $inv)
                continue ParseLoop
            }
            '^-TimeoutSeconds$' {
                if ($i + 1 -ge $args.Count) {
                    [Console]::Error.WriteLine("repeat-until-success: $arg requires a numeric timeout in seconds")
                    exit 1
                }
                $timeoutSec = [double]::Parse([string]$args[++$i], $inv)
                continue ParseLoop
            }
        }
    }
    $cmdTokens.Add($arg)
}

if ($null -eq $explicitCommand -and $cmdTokens.Count -eq 0) {
    [Console]::Error.WriteLine('repeat-until-success: missing command to execute')
    [Console]::Error.WriteLine($script:UsageText)
    exit 1
}

$displayCmd = if ($null -ne $explicitCommand) { $explicitCommand } else { $cmdTokens -join ' ' }
$attempt = 1
$lastRc = 1

while ($true) {
    Write-Host "[Attempt $attempt] Executing: $displayCmd" -ForegroundColor Cyan
    $succeeded = $false
    $lastRc = 1
    try {
        if ($timeoutSec -gt 0) {
            $psi = [System.Diagnostics.ProcessStartInfo]::new()
            $pwshExe = (Get-Process -Id $PID).MainModule.FileName
            $psi.FileName = $pwshExe
            $psi.ArgumentList.Add('-NoLogo')
            $psi.ArgumentList.Add('-NoProfile')
            if ($null -ne $explicitCommand) {
                $psi.ArgumentList.Add('-Command')
                $psi.ArgumentList.Add($explicitCommand)
            } elseif ($cmdTokens.Count -eq 1) {
                $psi.ArgumentList.Add('-Command')
                $psi.ArgumentList.Add($cmdTokens[0])
            } else {
                $psi.ArgumentList.Add('-Command')
                $quoted = $cmdTokens | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }
                $psi.ArgumentList.Add("& $($quoted -join ' ')")
            }
            $psi.UseShellExecute = $false
            $proc = [System.Diagnostics.Process]::Start($psi)
            $ms = [int][Math]::Max(1, [Math]::Round($timeoutSec * 1000))
            if ($proc.WaitForExit($ms)) {
                $lastRc = $proc.ExitCode
                if ($lastRc -eq 0) { $succeeded = $true }
            } else {
                try { $proc.Kill($true) } catch { Write-Verbose 'Timed-out child process terminated' }
                $lastRc = 124
                Write-Warning "Attempt $attempt timed out after ${timeoutSec}s"
            }
        } elseif ($null -ne $explicitCommand -or $cmdTokens.Count -eq 1) {
            $scriptStr = if ($null -ne $explicitCommand) { $explicitCommand } else { $cmdTokens[0] }
            $global:LASTEXITCODE = 0
            $sb = [scriptblock]::Create($scriptStr)
            & $sb
            if ($? -and ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)) {
                $succeeded = $true
                $lastRc = 0
            } else {
                $lastRc = if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
            }
        } else {
            $exe = $cmdTokens[0]
            [string[]]$exeArgs = @(if ($cmdTokens.Count -gt 1) { $cmdTokens[1..($cmdTokens.Count - 1)] })
            $global:LASTEXITCODE = 0
            & $exe @exeArgs
            if ($? -and ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE)) {
                $succeeded = $true
                $lastRc = 0
            } else {
                $lastRc = if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { $LASTEXITCODE } else { 1 }
            }
        }
    } catch {
        Write-Warning "Attempt $attempt failed with exception: $_"
        $lastRc = 1
    }

    if ($succeeded) {
        Write-Host "[Success] Command succeeded on attempt $attempt" -ForegroundColor Green
        exit 0
    }

    if ($maxAttempts -gt 0 -and $attempt -ge $maxAttempts) {
        [Console]::Error.WriteLine("repeat-until-success: failed after $maxAttempts attempts (exit code $lastRc)")
        exit $lastRc
    }

    $attempt++
    if ($delaySec -gt 0) {
        Start-Sleep -Milliseconds ([int][Math]::Round($delaySec * 1000))
    }
}
