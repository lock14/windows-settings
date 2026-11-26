# =============================================================
# setup/lib/Log.ps1 - Structured Setup Logging Helpers
# =============================================================

function Write-SetupBanner {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [switch]$DryRun
    )
    Write-Host '=====================================================' -ForegroundColor Cyan
    Write-Host ("{0}" -f $Title.PadLeft([Math]::Min(53, [int]((53 + $Title.Length) / 2))).PadRight(53)) -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host '               [DRY RUN PREVIEW MODE]                ' -ForegroundColor Magenta
    }
    Write-Host '=====================================================' -ForegroundColor Cyan
}

function Write-SetupFooter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SuccessMessage,
        [Parameter(Mandatory = $true)]
        [string]$DryRunMessage,
        [switch]$DryRun
    )
    Write-Host "`n=====================================================" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host (" {0}" -f $DryRunMessage) -ForegroundColor Magenta
    } else {
        Write-Host (" {0}" -f $SuccessMessage) -ForegroundColor Green
    }
    Write-Host '=====================================================' -ForegroundColor Cyan
}

function Write-SetupStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host "`n[$Stage] $Message" -ForegroundColor Yellow
}

function Write-SetupSkip {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Stage,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host "`n[$Stage] $Message" -ForegroundColor DarkCyan
}

function Write-SetupStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-SetupSuccess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host "==> $Message" -ForegroundColor Green
}

function Write-SetupDryRun {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host "  [DryRun] $Message" -ForegroundColor DarkCyan
}

function Write-SetupWarn {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Warning $Message
}
