<#
.SYNOPSIS
    Retries a command until it succeeds (exit code 0).
.DESCRIPTION
    Ported from home-settings/common-bin/repeat-until-success for native PowerShell usage.
.PARAMETER Command
    The command line string or ScriptBlock to execute.
.PARAMETER IntervalSeconds
    Interval to wait between attempts (default: 2).
.PARAMETER MaxAttempts
    Maximum number of attempts before giving up (0 = infinite).
.EXAMPLE
    repeat-until-success.ps1 -Command "curl -f https://example.com" -IntervalSeconds 5
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,

    [Parameter(Position = 1)]
    [double]$IntervalSeconds = 2.0,

    [Parameter(Position = 2)]
    [int]$MaxAttempts = 0
)

$attempt = 1

while ($true) {
    Write-Host "[Attempt $attempt] Executing: $Command" -ForegroundColor Cyan
    try {
        & pwsh -NoProfile -Command $Command
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[Success] Command succeeded on attempt $attempt" -ForegroundColor Green
            exit 0
        }
    } catch {
        Write-Warning "Attempt $attempt failed with exception: $_"
    }

    if ($MaxAttempts -gt 0 -and $attempt -ge $MaxAttempts) {
        Write-Error "Failed after $MaxAttempts attempts."
        exit 1
    }

    $attempt++
    Start-Sleep -Seconds $IntervalSeconds
}
