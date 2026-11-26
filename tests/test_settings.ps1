<#
.SYNOPSIS
    Master automated validation runner for windows-settings.
.DESCRIPTION
    Executes all 8 modular test suites under tests/suites/ (or a filtered subset
    when a suite name such as 'theme', 'ide', 'nvim', 'doclint', or 'setup' is passed).
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Suite 04 explicitly verifies prior global:LASTEXITCODE handling')]
param(
    [Parameter(Position = 0)]
    [string]$Suite = '',

    [Parameter(ValueFromPipeline = $true, DontShow = $true)]
    [object]$InputObject = $null
)

process {
    $null = $InputObject
}

end {
    $ErrorActionPreference = 'Stop'
    $ScriptDir = $PSScriptRoot
    $RootDir = Split-Path -Parent $ScriptDir
    $SuitesDir = Join-Path $ScriptDir 'suites'
    Write-Verbose "Running suites against repository root: $RootDir"

    $script:TestsPassed = 0
    $script:TestsFailed = 0

    function Add-TestPass([string]$Name) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $script:TestsPassed++
    }

    function Add-TestFail([string]$Name, [string]$Reason) {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        Write-Host "         $Reason" -ForegroundColor DarkRed
        $script:TestsFailed++
    }

    $env:WS_TEST_MODE = '1'

    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host 'Running windows-settings Test Suite     ' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan

    $suiteSpecs = @(
        @{ File = '01-Syntax.ps1';              Tags = @('1', 'syntax') },
        @{ File = '02-AssetsAndGovernance.ps1'; Tags = @('2', 'assets', 'doclint', 'docs', 'theme') },
        @{ File = '03-ModuleAndNeovim.ps1';     Tags = @('3', 'module', 'nvim', 'vim', 'env') },
        @{ File = '04-CliThemeAndIde.ps1';      Tags = @('4', 'bin', 'cli', 'theme', 'ide') },
        @{ File = '05-GitGuards.ps1';           Tags = @('5', 'git') },
        @{ File = '06-CompletionsAndPrompt.ps1'; Tags = @('6', 'completions', 'prompt', 'omp') },
        @{ File = '07-HygieneAndWrappers.ps1';  Tags = @('7', 'hygiene', 'wrappers', 'eol') },
        @{ File = '08-SetupAndHooks.ps1';       Tags = @('8', 'setup', 'hooks', 'uninstall') }
    )

    $filter = $Suite.Trim().ToLowerInvariant()
    $matchedAny = $false
    foreach ($spec in $suiteSpecs) {
        if ($filter -and ($spec.Tags -notcontains $filter) -and ($spec.File.ToLowerInvariant() -notlike "*$filter*")) {
            continue
        }
        $matchedAny = $true
        $suitePath = Join-Path $SuitesDir $spec.File
        if (Test-Path -LiteralPath $suitePath -PathType Leaf) {
            . $suitePath
        } else {
            Add-TestFail "Suite missing: $($spec.File)" "File not found at $suitePath"
        }
    }

    if (-not $matchedAny) {
        Write-Error "Unknown test suite filter '$Suite' (expected: syntax, assets, doclint, module, nvim, theme, ide, git, completions, hygiene, or setup)."
        exit 1
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host ("Test Summary: {0} Passed, {1} Failed" -f $script:TestsPassed, $script:TestsFailed) -ForegroundColor $(if ($script:TestsFailed -eq 0) { 'Green' } else { 'Red' })
    Write-Host '========================================' -ForegroundColor Cyan

    if ($script:TestsFailed -gt 0) {
        exit 1
    }
    exit 0
}
