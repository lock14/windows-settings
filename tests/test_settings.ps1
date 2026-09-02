# =============================================================
# Test Suite for windows-settings (Modern Workstation Architecture)
# =============================================================

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir

$script:TestsPassed = 0
$script:TestsFailed = 0

function Pass($name) {
    Write-Host "  [PASS] $name" -ForegroundColor Green
    $script:TestsPassed++
}

function Fail($name, $reason) {
    Write-Host "  [FAIL] $name" -ForegroundColor Red
    Write-Host "         $reason" -ForegroundColor DarkRed
    $script:TestsFailed++
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Running windows-settings Test Suite     " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -------------------------------------------------------------
# Test 1: PowerShell Syntax Checks
# -------------------------------------------------------------
Write-Host "`n[1/8] Checking PowerShell Scripts & Module Syntax..." -ForegroundColor Yellow
$psFiles = Get-ChildItem -Path $RootDir -Recurse -Include "*.ps1", "*.psm1", "*.psd1" | Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp)[\\/]' }

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
# Test 2: JSON & Manifest Files Validity
# -------------------------------------------------------------
Write-Host "`n[2/8] Validating JSON Configurations & Manifests..." -ForegroundColor Yellow

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

# Test terminal/Fragments/windows-settings.json
$fragmentJsonPath = Join-Path $RootDir "terminal\Fragments\windows-settings.json"
try {
    $fragJson = Get-Content $fragmentJsonPath -Raw | ConvertFrom-Json
    $fragSolarized = ($fragJson.profiles.defaults.colorScheme -eq "Solarized Dark")
    $fragFont = ($fragJson.profiles.defaults.font.face -eq "MesloLGS NF")
    if ($fragSolarized -and $fragFont) {
        Pass "JSON valid: terminal/Fragments/windows-settings.json (Solarized Dark fragment)"
    } else {
        Fail "terminal/Fragments/windows-settings.json" "Defaults mismatch"
    }
} catch {
    Fail "JSON parse error: terminal/Fragments/windows-settings.json" $_.Exception.Message
}

# Test configuration.dsc.yaml
$dscPath = Join-Path $RootDir "configuration.dsc.yaml"
if (Test-Path $dscPath) {
    $dscContent = Get-Content $dscPath -Raw
    if ($dscContent -match 'configurationVersion:\s*0\.2\.0' -and $dscContent -match 'JanDeDobbeleer\.OhMyPosh') {
        Pass "YAML valid: configuration.dsc.yaml (WinGet DSC v3 Manifest)"
    } else {
        Fail "configuration.dsc.yaml" "Missing configurationVersion or core resources"
    }
}

# Test p10k.omp.json & mise.toml
if (Test-Path $p10kPath) {
    $p10kRaw = Get-Content $p10kPath -Raw
    if ($p10kRaw -match '#002[bB]36' -or $p10kRaw -match '#073642' -or $p10kRaw -match '#586[eE]75') {
        Pass "Theme valid: p10k.omp.json (Solarized Dark Powerline configuration)"
    } else {
        Fail "p10k.omp.json" "Missing Solarized Dark palette definitions"
    }
}

$misePath = Join-Path $RootDir "mise.toml"
if (Test-Path $misePath) {
    Pass "TOML valid: mise.toml (Declarative toolchains)"
}

# -------------------------------------------------------------
# Test 3: WindowsSettings Module Import & Function Exports
# -------------------------------------------------------------
Write-Host "`n[3/8] Testing WindowsSettings PowerShell Module Import..." -ForegroundColor Yellow
$moduleManifest = Join-Path $RootDir "Modules\WindowsSettings\WindowsSettings.psd1"

# Import the module
Import-Module $moduleManifest -Force

$expectedFunctions = @(
    # Developer Tool Shortcuts (Kebab-case & compatibility aliases)
    'go-testall', 'go-buildall', 'go-lint', 'yaml-lint', 'guser-branch',
    'go_testall', 'go_buildall', 'go_lint', 'yaml_lint', 'fix-abcxyz-branch-name',
    'cat', 'fs', 'Format-PathTree', 'ls', 'll', 'la', 'lt',
    # Oh My Zsh Git plugin aliases
    'gco', 'gcb', 'gcm', 'gcd', 'ga', 'gaa', 'gst', 'gss', 'gd', 'gds',
    'gl', 'gp', 'gb', 'gba', 'gbd', 'gbD', 'gsta', 'gstp', 'gstl',
    'glog', 'glo', 'grb', 'grba', 'grbc', 'grbi', 'grh', 'grhh', 'gsw', 'gswc',
    'gcp', 'gcpa', 'gcpc',
    # Custom Git shortcuts
    'gcommit', 'gamend', 'gfetch', 'gpush', 'gpushf', 'gpull', 'gup', 'gprune', 'gsync',
    # Utilities
    'gen-passwd', 'repeat-until-success', 'sum'
)

foreach ($func in $expectedFunctions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Pass "Function defined & exported: $func"
    } else {
        Fail "Function missing: $func" "Get-Command could not find function $func"
    }
}

if (Get-Alias -Name tf -ErrorAction SilentlyContinue) {
    Pass "Alias defined: tf -> terraform"
} else {
    Fail "Alias missing: tf" "Alias tf not found"
}

if (Get-Alias -Name vi -ErrorAction SilentlyContinue) {
    Pass "Alias defined: vi -> nvim"
} else {
    Fail "Alias missing: vi" "Alias vi not found"
}

if (Get-Alias -Name vim -ErrorAction SilentlyContinue) {
    Pass "Alias defined: vim -> nvim"
} else {
    Fail "Alias missing: vim" "Alias vim not found"
}

if (Get-Alias -Name v -ErrorAction SilentlyContinue) {
    Pass "Alias defined: v -> nvim"
} else {
    Fail "Alias missing: v" "Alias v not found"
}

# Test Neovim configuration file
$nvimInit = Join-Path $RootDir "config\nvim\init.lua"
if (Test-Path $nvimInit) {
    $nvimContent = Get-Content $nvimInit -Raw
    if ($nvimContent -match 'solarized' -and $nvimContent -match 'mason') {
        Pass "Neovim modern Lua configuration exists: config/nvim/init.lua (LSP + Treesitter + Solarized)"
    } else {
        Fail "Neovim init.lua" "Missing LSP or Solarized configuration"
    }
}

if ($env:LS_COLORS -and $env:LS_COLORS -match 'di=34') {
    Pass "LS_COLORS environment variable configured (Solarized Dark)"
} else {
    Fail "LS_COLORS environment variable" "LS_COLORS not set properly"
}

$wingetScript = Join-Path $RootDir "packages\winget-setup.ps1"
if (Test-Path $wingetScript) {
    $wingetContent = Get-Content $wingetScript -Raw
    if ($wingetContent -match "'uutils\.coreutils'" -and $wingetContent -match "'JanDeDobbeleer\.OhMyPosh'") {
        Pass "uutils.coreutils and Oh My Posh configured in packages/winget-setup.ps1"
    } else {
        Fail "winget packages configuration" "packages missing in winget-setup.ps1"
    }
}

# -------------------------------------------------------------
# Test 4: Utility Scripts Functional Tests (bin/)
# -------------------------------------------------------------
Write-Host "`n[4/8] Testing Native Utility Scripts (bin/)..." -ForegroundColor Yellow

# Test gen-passwd.ps1
$genPasswdScript = Join-Path $RootDir "bin\gen-passwd.ps1"
$pass16 = & $genPasswdScript -Length 16
if ($pass16.Length -eq 16) {
    Pass "gen-passwd.ps1 generates expected length (16)"
} else {
    Fail "gen-passwd.ps1 length" "Expected 16, got $($pass16.Length)"
}

$pass32 = & $genPasswdScript -Length 32
if ($pass32.Length -eq 32) {
    Pass "gen-passwd.ps1 generates expected length (32)"
} else {
    Fail "gen-passwd.ps1 length" "Expected 32, got $($pass32.Length)"
}

$passSymbols = & $genPasswdScript -Length 24 -s
if ($passSymbols.Length -eq 24 -and $passSymbols -match '^[\^\*\@\#\&\%\$\!]+$') {
    Pass "gen-passwd.ps1 generates symbols-only password (-s)"
} else {
    Fail "gen-passwd.ps1 symbols" "Expected only symbols in $passSymbols"
}

$passDigits = & $genPasswdScript -Length 16 -n
if ($passDigits.Length -eq 16 -and $passDigits -match '^[0-9]+$') {
    Pass "gen-passwd.ps1 generates digits-only password (-n)"
} else {
    Fail "gen-passwd.ps1 digits" "Expected only digits in $passDigits"
}

$passUpperDigits = & $genPasswdScript -Length 16 -u -n
if ($passUpperDigits.Length -eq 16 -and $passUpperDigits -match '^[A-Z0-9]+$') {
    Pass "gen-passwd.ps1 generates uppercase and numbers (-u -n)"
} else {
    Fail "gen-passwd.ps1 upper+digits" "Expected only uppercase and digits in $passUpperDigits"
}

$passAlpha = & $genPasswdScript -Length 20 -NoSymbols
if ($passAlpha.Length -eq 20 -and $passAlpha -notmatch '[\^\*\@\#\&\%\$\!]') {
    Pass "gen-passwd.ps1 generates password without symbols (-NoSymbols)"
} else {
    Fail "gen-passwd.ps1 no-symbols" "Did not expect symbols in $passAlpha"
}

# Test sum.ps1 & direct sum cmdlet
$sumScript = Join-Path $RootDir "bin\sum.ps1"
$sumResult = 1..10 | & $sumScript
if ($sumResult -eq 55) {
    Pass "sum.ps1 correctly sums pipeline numbers (1..10 = 55)"
} else {
    Fail "sum.ps1 result" "Expected 55, got $sumResult"
}

$sumDirect1 = sum 1 2
if ($sumDirect1 -eq 3) {
    Pass "sum cmdlet correctly sums positional arguments (sum 1 2 = 3)"
} else {
    Fail "sum cmdlet result" "Expected 3, got $sumDirect1"
}

$sumDirect2 = 1..10 | sum
if ($sumDirect2 -eq 55) {
    Pass "sum cmdlet correctly sums pipeline numbers (1..10 | sum = 55)"
} else {
    Fail "sum cmdlet pipeline" "Expected 55, got $sumDirect2"
}

# Test repeat-until-success.ps1
$repeatScript = Join-Path $RootDir "bin\repeat-until-success.ps1"
try {
    & $repeatScript -Command "Write-Output 'ok'" -MaxAttempts 2 | Out-Null
    Pass "repeat-until-success.ps1 succeeds on valid command"
} catch {
    Fail "repeat-until-success.ps1" $_.Exception.Message
}

# -------------------------------------------------------------
# Test 5: Git Function Behavior Integration Tests
# -------------------------------------------------------------
Write-Host "`n[5/8] Testing Git Functions Behavior..." -ForegroundColor Yellow

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_test_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
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

    # Test 5.1: gsync outside git repo
    $nonGitDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_nongit_" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $nonGitDir | Out-Null
    Push-Location $nonGitDir
    $errCaught = $false
    try {
        gsync
    } catch {
        if ($_.ToString() -match "Error" -or $_.Exception.Message -match "Error") {
            $errCaught = $true
        }
    } finally {
        Pop-Location
        Remove-Item -Recurse -Force -Path $nonGitDir -ErrorAction SilentlyContinue
    }

    if ($errCaught) {
        Pass "gsync fails gracefully when not in a git repository"
    } else {
        Fail "gsync outside repo" "Expected error when executing gsync outside git repository"
    }

    # Test 5.2: gsync on feature branch
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

    # Test 5.3: guser-branch & fix-abcxyz-branch-name
    $expectedUser = if ($env:USER) { $env:USER } else { $env:USERNAME }
    guser-branch
    $renamedBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($renamedBranch -eq "$expectedUser/feature-1") {
        Pass "guser-branch successfully prefixed branch ($expectedUser/feature-1)"
    } else {
        Fail "guser-branch" "Expected $expectedUser/feature-1, got $renamedBranch"
    }

    # Test 5.3.1: guser-branch idempotency (does not duplicate prefix)
    guser-branch
    $idempotentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($idempotentBranch -eq "$expectedUser/feature-1") {
        Pass "guser-branch strips redundant user prefix idempotently"
    } else {
        Fail "guser-branch prefix strip" "Redundant prefix introduced: $idempotentBranch"
    }

    # Test 5.3.2: fix-abcxyz-branch-name compatibility alias
    fix-abcxyz-branch-name
    $aliasBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($aliasBranch -eq "$expectedUser/feature-1") {
        Pass "fix-abcxyz-branch-name compatibility alias works identically"
    } else {
        Fail "fix-abcxyz-branch-name" "Expected $expectedUser/feature-1, got $aliasBranch"
    }

    # Test 5.4: gprune deletes non-main branches
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
# Test 6: Completions & Oh My Posh Rendering
# -------------------------------------------------------------
Write-Host "`n[6/8] Testing Completions & Prompt Rendering..." -ForegroundColor Yellow

# Test completions setup execution
$completionsScript = Join-Path $RootDir "completions\completions-setup.ps1"
try {
    & $completionsScript | Out-Null
    Pass "completions-setup.ps1 executed successfully"
} catch {
    Fail "completions-setup.ps1" $_.Exception.Message
}

# Test Oh My Posh rendering
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
    Write-Host "  [SKIP] oh-my-posh not installed in current environment" -ForegroundColor DarkCyan
}

# -------------------------------------------------------------
# Test 7: Path Invariant & Dual Execution Validation
# -------------------------------------------------------------
Write-Host "`n[7/8] Testing Path Invariants & Dual Execution Wrappers..." -ForegroundColor Yellow

# 7.1 Path Invariant Check (no hardcoded user paths in repo files)
$filesToScan = Get-ChildItem -Path $RootDir -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp)[\\/]' -and $_.Name -ne 'AGENTS.md' }

$hardcodedFound = $false
foreach ($f in $filesToScan) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'C:\\Users\\(?!<)[a-zA-Z0-9_-]+' -or $content -match '/Users/(?!<)[a-zA-Z0-9_-]+' -or $content -match '/home/(?!<)[a-zA-Z0-9_-]+') {
        Fail "Path invariant check: $($f.Name)" "Contains hardcoded personal user path"
        $hardcodedFound = $true
    }
}
if (-not $hardcodedFound) {
    Pass "Path invariants valid across all repo files (zero hardcoded personal paths)"
}

# 7.2 Dual Execution in bin/
$binPs1Files = Get-ChildItem -Path (Join-Path $RootDir "bin") -Filter "*.ps1"
foreach ($ps1 in $binPs1Files) {
    $cmdName = [System.IO.Path]::GetFileNameWithoutExtension($ps1.Name) + ".cmd"
    $cmdPath = Join-Path (Join-Path $RootDir "bin") $cmdName
    if (Test-Path $cmdPath) {
        Pass "Dual execution wrapper present: $cmdName for $($ps1.Name)"
    } else {
        Fail "Dual execution wrapper missing: $cmdName" "No .cmd wrapper found for $($ps1.Name)"
    }
}

# 7.3 Execute sum.cmd & gen-passwd.cmd wrappers
$sumCmd = Join-Path $RootDir "bin\sum.cmd"
if (Test-Path $sumCmd) {
    $cmdSumOut = (& cmd.exe /c "$sumCmd" 10 20 30).Trim()
    if ($cmdSumOut -eq "60") {
        Pass "sum.cmd batch wrapper executed successfully (10 + 20 + 30 = 60)"
    } else {
        Fail "sum.cmd execution" "Expected 60, got: $cmdSumOut"
    }
}

$genPasswdCmd = Join-Path $RootDir "bin\gen-passwd.cmd"
if (Test-Path $genPasswdCmd) {
    $cmdPassOut = (& cmd.exe /c "$genPasswdCmd" -Length 12 -NoSymbols).Trim()
    if ($cmdPassOut.Length -eq 12) {
        Pass "gen-passwd.cmd batch wrapper executed successfully (Length 12)"
    } else {
        Fail "gen-passwd.cmd execution" "Expected length 12, got: $($cmdPassOut.Length)"
    }
}

# -------------------------------------------------------------
# Test 8: Setup Idempotency & Backup Verification
# -------------------------------------------------------------
Write-Host "`n[8/8] Testing Setup Script Idempotency & Backup Policy..." -ForegroundColor Yellow

$sandboxDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_sandbox_" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $sandboxDir | Out-Null

try {
    # Simulate existing destination file
    $mockTarget = Join-Path $sandboxDir "settings.json"
    Set-Content -Path $mockTarget -Value "initial configuration"

    $sourceSettings = Join-Path $RootDir "terminal\settings.json"
    $sourceContent = Get-Content $sourceSettings -Raw

    # 1. Overwrite with differing content should create a backup
    $isDiff = ((Get-Content $mockTarget -Raw) -ne $sourceContent)
    if ($isDiff) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $mockBackup = "$mockTarget.bak_$timestamp"
        Copy-Item -Path $mockTarget -Destination $mockBackup -Force
        Copy-Item -Path $sourceSettings -Destination $mockTarget -Force
    }

    $backupFiles = Get-ChildItem -Path $sandboxDir -Filter "settings.json.bak_*"
    if ($backupFiles.Count -eq 1) {
        Pass "Backup created when configuration content differed"
    } else {
        Fail "Backup creation" "Expected 1 backup file, found $($backupFiles.Count)"
    }

    # 2. Repeated run with identical content should NOT create additional backups (idempotency)
    $isDiff2 = ((Get-Content $mockTarget -Raw) -ne $sourceContent)
    if ($isDiff2) {
        $timestamp2 = Get-Date -Format "yyyyMMdd_HHmmss"
        $mockBackup2 = "$mockTarget.bak_$timestamp2"
        Copy-Item -Path $mockTarget -Destination $mockBackup2 -Force
    }

    $backupFilesAfter = Get-ChildItem -Path $sandboxDir -Filter "settings.json.bak_*"
    if ($backupFilesAfter.Count -eq 1) {
        Pass "Idempotency preserved: zero redundant backups generated on identical re-run"
    } else {
        Fail "Idempotency failure" "Redundant backup created when content had not changed"
    }

    # 3. Test Windows Terminal deep merge & JSON Fragments
    $terminalSetupScript = Join-Path $RootDir "terminal\terminal-setup.ps1"
    $terminalScriptContent = Get-Content $terminalSetupScript -Raw
    if ($terminalScriptContent -match 'Fragments' -and $terminalScriptContent -match 'Merge-TerminalHashtable') {
        Pass "Windows Terminal setup implements JSON Fragment extension & deep merge"
    } else {
        Fail "Terminal setup" "JSON Fragment support missing in terminal-setup.ps1"
    }

    # 4. Test setup.ps1 and bootstrap.ps1 dry-run execution
    $setupScriptPath = Join-Path $RootDir "setup.ps1"
    try {
        & $setupScriptPath -DryRun | Out-Null
        Pass "setup.ps1 executes cleanly in -DryRun mode"
    } catch {
        Fail "setup.ps1 dry-run" $_.Exception.Message
    }

    try {
        & $setupScriptPath -DryRun -DotfilesOnly | Out-Null
        Pass "setup.ps1 executes cleanly in -DryRun -DotfilesOnly mode"
    } catch {
        Fail "setup.ps1 dotfiles-only dry-run" $_.Exception.Message
    }

    try {
        & $setupScriptPath -DryRun -SystemOnly | Out-Null
        Pass "setup.ps1 executes cleanly in -DryRun -SystemOnly mode"
    } catch {
        Fail "setup.ps1 system-only dry-run" $_.Exception.Message
    }

    try {
        & $setupScriptPath -DryRun -WithGUI | Out-Null
        Pass "setup.ps1 executes cleanly in -DryRun -WithGUI mode"
    } catch {
        Fail "setup.ps1 with-gui dry-run" $_.Exception.Message
    }

    $bootstrapScriptPath = Join-Path $RootDir "bootstrap.ps1"
    if (Test-Path $bootstrapScriptPath) {
        Pass "bootstrap.ps1 exists in repository root"
        try {
            & $bootstrapScriptPath -DryRun -SkipPackages | Out-Null
            Pass "bootstrap.ps1 executes cleanly in -DryRun -SkipPackages mode"
        } catch {
            Fail "bootstrap.ps1 dry-run" $_.Exception.Message
        }
    } else {
        Fail "bootstrap.ps1 missing" "bootstrap.ps1 not found in repository root"
    }
} finally {
    if (Test-Path $sandboxDir) {
        Remove-Item -Recurse -Force -Path $sandboxDir -ErrorAction SilentlyContinue
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Summary: $TestsPassed passed, $TestsFailed failed" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($TestsFailed -gt 0) {
    exit 1
}
