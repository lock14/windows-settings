# =============================================================
# Suite 5: Git Workflow Behavior & Branch Safety Guards
# =============================================================
Write-Host "`n[5/8] Testing Git Functions & Safety Guards..." -ForegroundColor Yellow

$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_test_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null

try {
    $remoteDir = Join-Path $tempDir 'remote.git'
    $localDir = Join-Path $tempDir 'local'

    git init --bare -b main $remoteDir 2>$null | Out-Null
    git clone $remoteDir $localDir 2>$null | Out-Null
    Push-Location $localDir

    git config user.email 'test@example.com'
    git config user.name 'Test User'
    git config commit.gpgsign false

    Set-Content -Path 'file.txt' -Value 'initial content'
    git add file.txt
    git commit -m 'initial commit' 2>$null | Out-Null
    git push origin main 2>$null | Out-Null

    foreach ($fnName in @('gsync', 'gprune', 'gpurge', 'gcm', 'guser-branch')) {
        $nonGitDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ws_nongit_${fnName}_" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $nonGitDir | Out-Null
        Push-Location $nonGitDir
        $caught = $false
        try {
            if ($fnName -eq 'gpurge') {
                gpurge -Force
            } else {
                & (Get-Command $fnName -CommandType Function)
            }
        } catch {
            if ($_.ToString() -match 'Error' -or $_.Exception.Message -match 'Error') {
                $caught = $true
            }
        } finally {
            Pop-Location
            Remove-Item -Recurse -Force -Path $nonGitDir -ErrorAction SilentlyContinue
        }
        if ($caught) {
            Add-TestPass "$fnName fails gracefully when not in a git repository"
        } else {
            Add-TestFail "$fnName outside repo" 'Expected error outside git repository'
        }
    }

    $mainRenameBlocked = $false
    try {
        guser-branch
    } catch {
        if ($_.ToString() -match 'refusing to rename protected primary branch') {
            $mainRenameBlocked = $true
        }
    }
    if ($mainRenameBlocked -and (git rev-parse --abbrev-ref HEAD).Trim() -eq 'main') {
        Add-TestPass "guser-branch refuses to rename protected primary branch 'main'"
    } else {
        Add-TestFail 'guser-branch main guard' 'Expected refusal on main branch'
    }

    git checkout -b feature-1 2>$null | Out-Null
    Add-Content -Path 'file.txt' -Value "`nfeature work"
    git commit -am 'feature update' 2>$null | Out-Null

    gsync 2>$null | Out-Null
    if ((git rev-parse --abbrev-ref HEAD).Trim() -eq 'feature-1') {
        Add-TestPass 'gsync preserves current branch on clean feature branch'
    } else {
        Add-TestFail 'gsync branch preservation' 'Expected feature-1'
    }

    Add-Content -Path 'file.txt' -Value "`ndirty tracked edit"
    $dirtySyncBlocked = $false
    try {
        gsync
    } catch {
        if ($_.ToString() -match 'uncommitted changes') {
            $dirtySyncBlocked = $true
        }
    }
    git checkout -- file.txt 2>$null | Out-Null
    if ($dirtySyncBlocked) {
        Add-TestPass 'gsync refuses to run when tracked working tree has uncommitted changes'
    } else {
        Add-TestFail 'gsync dirty guard' 'Expected error on dirty working tree'
    }

    $expectedUser = if ($env:USER) { $env:USER } else { $env:USERNAME }
    guser-branch
    guser-branch
    fix-abcxyz-branch-name
    $idempotentBranch = (git rev-parse --abbrev-ref HEAD).Trim()
    if ($idempotentBranch -eq "$expectedUser/feature-1") {
        Add-TestPass "guser-branch & fix-abcxyz-branch-name prefix idempotently ($idempotentBranch)"
    } else {
        Add-TestFail 'guser-branch prefixing' "Expected $expectedUser/feature-1, got $idempotentBranch"
    }

    git checkout main 2>$null | Out-Null
    git branch merged-branch 2>$null | Out-Null
    gprune 2>$null | Out-Null
    git show-ref --verify --quiet refs/heads/merged-branch
    $mergedGone = ($LASTEXITCODE -ne 0)
    git show-ref --verify --quiet "refs/heads/$expectedUser/feature-1"
    $unmergedKept = ($LASTEXITCODE -eq 0)
    if ($mergedGone -and $unmergedKept) {
        Add-TestPass 'gprune safely deletes merged branches while preserving unmerged branches'
    } else {
        Add-TestFail 'gprune safety' "mergedGone=$mergedGone, unmergedKept=$unmergedKept"
    }

    gpurge -Force 2>$null | Out-Null
    git show-ref --verify --quiet "refs/heads/$expectedUser/feature-1"
    if ($LASTEXITCODE -ne 0) {
        Add-TestPass 'gpurge -Force deletes unmerged non-primary branches when explicitly confirmed'
    } else {
        Add-TestFail 'gpurge -Force' 'Expected unmerged branch to be purged'
    }

    git checkout -b gcm-test-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    $mainOk = ((git rev-parse --abbrev-ref HEAD).Trim() -eq 'main')
    git branch -m main master 2>$null | Out-Null
    git checkout -b gcm-test-master-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    $masterOk = ((git rev-parse --abbrev-ref HEAD).Trim() -eq 'master')
    git branch -m master trunk 2>$null | Out-Null
    git checkout -b gcm-test-trunk-feature 2>$null | Out-Null
    & (Get-Command gcm -CommandType Function) 2>$null | Out-Null
    $trunkOk = ((git rev-parse --abbrev-ref HEAD).Trim() -eq 'trunk')
    if ($mainOk -and $masterOk -and $trunkOk) {
        Add-TestPass 'gcm primary branch resolution falls back cleanly across main -> master -> trunk'
    } else {
        Add-TestFail 'gcm resolution' "main=$mainOk, master=$masterOk, trunk=$trunkOk"
    }

    Pop-Location
} finally {
    Set-Location $RootDir
    if (Test-Path -LiteralPath $tempDir) {
        Remove-Item -Recurse -Force -LiteralPath $tempDir -ErrorAction SilentlyContinue
    }
}
