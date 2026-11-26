# =============================================================
# Suite 7: Path Hygiene, Byte-Level EOL & Dual-Execution Wrappers
# =============================================================
Write-Host "`n[7/8] Testing Path Invariants, Line Endings & Dual Execution Wrappers..." -ForegroundColor Yellow

$allRepoFiles = @(Get-ChildItem -Path $RootDir -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](\.git|tests[\\/]temp|plugin[\\/]ws-bar[\\/]target)[\\/]' })

# 1. Personal-path scan across ALL tracked/untracked repo files (including AGENTS.md!)
$hardcodedFound = $false
foreach ($f in $allRepoFiles) {
    $content = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match 'C:\\Users\\(?!<)[a-zA-Z0-9_-]+' -or $content -match '/Users/(?!<)[a-zA-Z0-9_-]+' -or $content -match '/home/(?!<)[a-zA-Z0-9_-]+') {
        Add-TestFail "Path invariant check: $($f.FullName)" 'Contains hardcoded personal user path'
        $hardcodedFound = $true
    }
}
if (-not $hardcodedFound) {
    Add-TestPass 'Path invariants valid across all repo files including AGENTS.md (zero hardcoded personal paths)'
}

# 2. Byte-level CRLF / LF line-ending discipline
$crlfExts = @('.ps1', '.psm1', '.psd1', '.cmd', '.bat', '.doskey')
$lfExts   = @('.md', '.json', '.kdl', '.yml', '.yaml', '.toml', '.lock', '.rs', '.lua', '.scm', '.theme', '.tmTheme', '.sublime-syntax', '.gitconfig', '.conf', '.txt')
$eolViolation = $false
foreach ($f in $allRepoFiles) {
    $rawBytes = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($rawBytes.Length -eq 0) { continue }
    $rawStr = [System.Text.Encoding]::UTF8.GetString($rawBytes)
    if ($crlfExts -contains $f.Extension) {
        if (($rawStr -replace "`r`n", '').Contains("`n")) {
            Add-TestFail "Line-ending check (expected CRLF): $($f.FullName)" 'Contains bare LF line endings'
            $eolViolation = $true
        }
    } elseif ($lfExts -contains $f.Extension -or $f.Name -eq 'LICENSE') {
        if ($rawStr.Contains("`r`n")) {
            Add-TestFail "Line-ending check (expected LF): $($f.FullName)" 'Contains CRLF line endings'
            $eolViolation = $true
        }
    }
}
if (-not $eolViolation) {
    Add-TestPass 'Line-ending invariants valid across all repo files (CRLF scripts/batch, LF configs/docs/Rust/Lua)'
}

# 3. Module startup hygiene & pure bin/ boundary
$psm1Raw = Get-Content -LiteralPath (Join-Path $RootDir 'module\WindowsSettings.psm1') -Raw
if ($psm1Raw -notmatch 'Get-ChildItem[^\r\n]*-Recurse') {
    Add-TestPass 'Module startup hygiene valid: zero recursive disk traversals in WindowsSettings.psm1'
} else {
    Add-TestFail 'Module startup hygiene' 'WindowsSettings.psm1 must not use Get-ChildItem -Recurse'
}

$binDir = Join-Path $RootDir 'bin'
$binPs1Files = @(Get-ChildItem -LiteralPath $binDir -Filter '*.ps1' -File)
$binSubDirs = @(Get-ChildItem -LiteralPath $binDir -Directory)
if ($binPs1Files.Count -eq 7 -and $binSubDirs.Count -eq 0) {
    Add-TestPass 'bin/ contains strictly the 7 dual-execution utilities with zero library subdirectories'
} else {
    Add-TestFail 'bin/ boundary check' "Expected 7 .ps1 files and 0 subdirs in bin/, found $($binPs1Files.Count) .ps1 and $($binSubDirs.Count) subdirs"
}

$missingCmd = @($binPs1Files | Where-Object { -not (Test-Path -LiteralPath (Join-Path $binDir ([System.IO.Path]::GetFileNameWithoutExtension($_.Name) + '.cmd'))) })
if ($missingCmd.Count -eq 0) {
    Add-TestPass 'All 7 utilities in bin/ ship matching .cmd batch wrappers'
} else {
    Add-TestFail 'Dual-execution wrappers' "Missing .cmd for: $(($missingCmd | ForEach-Object { $_.Name }) -join ', ')"
}

$badUsebackq = @($allRepoFiles | Where-Object { $_.Extension -in @('.cmd', '.bat') } | Where-Object {
    $rawBatch = Get-Content -LiteralPath $_.FullName -Raw -ErrorAction SilentlyContinue
    $rawBatch -match '(?im)for\s+/f\s+"[^"]*usebackq[^"]*"\s+%%?[A-Za-z]\s+in\s*\(\s*`"[^"]'
})
if ($badUsebackq.Count -eq 0) {
    Add-TestPass 'Batch wrappers avoid unguarded leading quotes inside for /f usebackq subshells'
} else {
    Add-TestFail 'Batch for /f quoting check' "Unguarded leading quote in usebackq: $(($badUsebackq | ForEach-Object { $_.FullName }) -join ', ')"
}

# 4. Execute .cmd batch wrappers
$cmdSumOut = (& cmd.exe /c "`"$(Join-Path $binDir 'sum.cmd')`" 10 20 30" | Out-String).Trim()
$cmdPipeOut = (& cmd.exe /c "echo 25 | `"$(Join-Path $binDir 'sum.cmd')`"" | Out-String).Trim()
$cmdPassOut = (& cmd.exe /c "`"$(Join-Path $binDir 'gen-passwd.cmd')`" -Length 12 -NoSymbols" | Out-String).Trim()
$cmdRepeatOut = (& cmd.exe /c "`"$(Join-Path $binDir 'repeat-until-success.cmd')`" `"Write-Output cmd_repeat_ok`" -MaxAttempts 1") | Out-String
$cmdThemeOut = @(& cmd.exe /c "`"$(Join-Path $binDir 'theme.cmd')`" --list --plain")
$cmdIdeOut = (& cmd.exe /c "`"$(Join-Path $binDir 'ide.cmd')`" --dry-run") | Out-String
& cmd.exe /c "`"$(Join-Path $binDir 'update-system.cmd')`" --dry-run" | Out-Null
$updCmdExit = $LASTEXITCODE

if ($cmdSumOut -eq '60' -and $cmdPipeOut -eq '25' -and $cmdPassOut.Length -eq 12 -and
    $cmdRepeatOut -match 'cmd_repeat_ok' -and $cmdThemeOut.Count -ge 22 -and
    $cmdIdeOut -match 'IDE Session' -and $updCmdExit -eq 0) {
    Add-TestPass 'All .cmd batch wrappers execute cleanly (sum, gen-passwd, repeat-until-success, 22-theme, ide, update-system)'
} else {
    Add-TestFail '.cmd wrapper execution' "sum=$cmdSumOut/$cmdPipeOut, pass=$($cmdPassOut.Length), themes=$($cmdThemeOut.Count), updExit=$updCmdExit"
}
