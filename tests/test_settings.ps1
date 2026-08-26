# =============================================================
# Test Suite for windows-settings
# =============================================================

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

$TestsPassed = 0
$TestsFailed = 0

function Pass($name) {
    Write-Host "  [PASS] $name" -ForegroundColor Green
    $global:TestsPassed++
}

function Fail($name, $reason) {
    Write-Host "  [FAIL] $name" -ForegroundColor Red
    Write-Host "         $reason" -ForegroundColor DarkRed
    $global:TestsFailed++
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running windows-settings Test Suite     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -------------------------------------------------------------
# Test 1: PowerShell Syntax Checks
# -------------------------------------------------------------
Write-Host "`n[1/5] Checking PowerShell Scripts Syntax..." -ForegroundColor Yellow
$psFiles = Get-ChildItem -Path $RootDir -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -notmatch '\\(\.git|tests\\temp)\\' }

foreach ($file in $psFiles) {
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -eq 0) {
        Pass "Syntax valid: $($file.Name)"
    } else {
        $msg = ($errors | ForEach-Object { $_.Message }) -join '; '
        Fail "Syntax invalid: $($file.Name)" $msg
    }
}

# -------------------------------------------------------------
# Test 2: JSON Files Validity & Schema Verification
# -------------------------------------------------------------
Write-Host "`n[2/5] Validating JSON Configurations..." -ForegroundColor Yellow

# Test posh/p10k.omp.json
$p10kPath = Join-Path $RootDir "posh\p10k.omp.json"
try {
    $p10kJson = Get-Content $p10kPath -Raw | ConvertFrom-Json
    if ($p10kJson.blocks.Count -gt 0) {
        Pass "JSON valid: posh/p10k.omp.json (blocks: $($p10kJson.blocks.Count))"
    } else {
        Fail "JSON validation: posh/p10k.omp.json" "Missing blocks definition"
    }
} catch {
    Fail "JSON parse error: posh/p10k.omp.json" $_.Exception.Message
}

# Test terminal/settings.json
$terminalJsonPath = Join-Path $RootDir "terminal\settings.json"
try {
    $termJson = Get-Content $terminalJsonPath -Raw | ConvertFrom-Json
    $hasSolarized = ($termJson.profiles.defaults.colorScheme -eq "Solarized Dark")
    $hasFont = ($termJson.profiles.defaults.font.face -eq "MesloLGS NF")
    if ($hasSolarized -and $hasFont) {
        Pass "JSON valid: terminal/settings.json (Solarized Dark + MesloLGS NF)"
    } else {
        Fail "terminal/settings.json validation" "Defaults mismatch (Solarized: $hasSolarized, Font: $hasFont)"
    }
} catch {
    Fail "JSON parse error: terminal/settings.json" $_.Exception.Message
}

# -------------------------------------------------------------
# Test 3: Profile Sourcing & Function Definitions
# -------------------------------------------------------------
Write-Host "`n[3/5] Testing PowerShell Profile & Git Aliases..." -ForegroundColor Yellow
$profileFile = Join-Path $RootDir "posh\Microsoft.PowerShell_profile.ps1"

# Source the profile in current scope
. $profileFile

$expectedFunctions = @(
    # Oh My Zsh Git plugin aliases
    'gco', 'gcb', 'gcm', 'gcd', 'ga', 'gaa', 'gst', 'gss', 'gd', 'gds',
    'gl', 'gp', 'gb', 'gba', 'gbd', 'gbD', 'gsta', 'gstp', 'gstl',
    'glog', 'glo', 'grb', 'grba', 'grbc', 'grbi', 'grh', 'grhh', 'gsw', 'gswc',
    'gcp', 'gcpa', 'gcpc',
    # Custom Git shortcuts
    'gcommit', 'gamend', 'gfetch', 'gpush', 'gpushf', 'gpull', 'gup', 'gprune', 'gsync', 'fix-abcxyz-branch-name'
)

foreach ($func in $expectedFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Pass "Function defined: $func"
    } else {
        Fail "Function missing: $func" "Get-Command could not find function $func"
    }
}

# -------------------------------------------------------------
# Test 4: Git Function Behavior Integration Tests
# -------------------------------------------------------------
Write-Host "`n[4/5] Testing Git Functions Behavior..." -ForegroundColor Yellow

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    # Initialize bare remote repo and clone local repo
    $remoteDir = Join-Path $tempDir "remote.git"
    $localDir = Join-Path $tempDir "local"

    git init --bare -b main $remoteDir 2>$null | Out-Null
    git clone $remoteDir $localDir 2>$null | Out-Null

    Push-Location $localDir

    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false

    # Initial commit on main
    Set-Content -Path "file.txt" -Value "initial content"
    git add file.txt
    git commit -m "initial commit" 2>$null | Out-Null
    git push origin main 2>$null | Out-Null

    # Test 4.1: gsync outside git repo
    Pop-Location
    Push-Location $tempDir
    $outErr = ""
    try {
        gsync 2>&1 | Out-String | ForEach-Object { $outErr = $_ }
    } catch {
        $outErr = $_.Exception.Message
    }
    if ($outErr -match "Error") {
        Pass "gsync fails gracefully when not in a git repository"
    } else {
        Fail "gsync outside repo" "Expected error, got: $outErr"
    }

    # Test 4.2: gsync on feature branch
    Push-Location $localDir
    git checkout -b feature-1 2>$null | Out-Null
    Add-Content -Path "file.txt" -Value "`nfeature work"
    git commit -am "feature update" 2>$null | Out-Null

    gsync 2>$null | Out-Null
    $currentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($currentBranch -eq "feature-1") {
        Pass "gsync preserves current branch on feature branch"
    } else {
        Fail "gsync branch preservation" "Expected feature-1, got $currentBranch"
    }

    # Test 4.3: fix-abcxyz-branch-name
    $expectedUser = if ($env:USER) { $env:USER } else { $env:USERNAME }
    fix-abcxyz-branch-name
    $renamedBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($renamedBranch -eq "$expectedUser/feature-1") {
        Pass "fix-abcxyz-branch-name successfully renamed branch"
    } else {
        Fail "fix-abcxyz-branch-name" "Expected $expectedUser/feature-1, got $renamedBranch"
    }

    # Test 4.4: gprune deletes non-main branches
    git checkout main 2>$null | Out-Null
    git branch branch-to-delete 2>$null | Out-Null
    gprune 2>$null | Out-Null
    git show-ref --verify --quiet refs/heads/branch-to-delete
    if ($LASTEXITCODE -ne 0) {
        Pass "gprune successfully pruned non-main branch"
    } else {
        Fail "gprune" "Branch 'branch-to-delete' was not pruned"
    }

    Pop-Location
} finally {
    Set-Location $RootDir
    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------
# Test 5: Oh My Posh Rendering Check (if installed)
# -------------------------------------------------------------
Write-Host "`n[5/5] Testing Oh My Posh Rendering..." -ForegroundColor Yellow
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    try {
        $renderOutput = oh-my-posh print primary --config $p10kPath
        if ($renderOutput) {
            Pass "Oh My Posh theme renders cleanly"
        } else {
            Fail "Oh My Posh rendering" "Render output was empty"
        }
    } catch {
        Fail "Oh My Posh rendering error" $_.Exception.Message
    }
} else {
    Write-Host "  [SKIP] oh-my-posh not installed in current environment" -ForegroundColor DarkGray
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary: $TestsPassed passed, $TestsFailed failed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($TestsFailed -gt 0) {
    exit 1
}
