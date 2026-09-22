# =============================================================
# Git Shortcuts (Oh My Zsh Git plugin & custom workflow helpers)
# =============================================================

# Un-alias default PowerShell redirects that conflict with Git plugin
$gitConflictAliases = @('gcm', 'gl', 'gp')
foreach ($a in $gitConflictAliases) {
    if (Test-Path "Alias:$a") {
        Remove-Item "Alias:$a" -Force -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------
# Internal Git Helpers
# -------------------------------------------------------------
function Get-GitCurrentBranch {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $branch) {
        Write-Error "Error: not in a git repository"
        return $null
    }
    return $branch.Trim()
}

function Resolve-GitPrimaryBranch {
    git show-ref --verify --quiet refs/heads/main
    if ($LASTEXITCODE -eq 0) { return 'main' }

    git show-ref --verify --quiet refs/heads/master
    if ($LASTEXITCODE -eq 0) { return 'master' }

    Write-Error "Error: neither 'main' nor 'master' branch found locally."
    return $null
}

# -------------------------------------------------------------
# Standard Git Plugin Aliases & Functions
# -------------------------------------------------------------
function gco  { git checkout @args }
function gcb  { git checkout -b @args }
function gcm {
    $currentBranch = Get-GitCurrentBranch
    if (-not $currentBranch) { return }

    $targetBranch = Resolve-GitPrimaryBranch
    if ($targetBranch) {
        git checkout $targetBranch @args
    }
}
function gcd  { git checkout develop @args }
function ga   { git add @args }
function gaa  { git add --all @args }
function gst  { git status @args }
function gss  { git status -s @args }
function gd   { git diff @args }
function gds  { git diff --staged @args }
function gl   { git pull @args }
function gp   { git push @args }
function gb   { git branch @args }
function gba  { git branch -a @args }
function gbd  { git branch -d @args }
function gbD  { git branch -D @args }
function gsta { git stash push @args }
function gstp { git stash pop @args }
function gstl { git stash list @args }
function glog { git log --oneline --decorate --graph @args }
function glo  { git log --oneline --decorate @args }
function grb  { git rebase @args }
function grba { git rebase --abort @args }
function grbc { git rebase --continue @args }
function grbi { git rebase -i @args }
function grh  { git reset @args }
function grhh { git reset --hard @args }
function gsw  { git switch @args }
function gswc { git switch -c @args }
function gcp  { git cherry-pick @args }
function gcpa { git cherry-pick --abort @args }
function gcpc { git cherry-pick --continue @args }

# -------------------------------------------------------------
# Repository Custom Workflow Helpers
# -------------------------------------------------------------
function gcommit { git add -A && git commit @args }
function gamend  { git add -A && git commit --amend --no-edit @args }
function gfetch  { git fetch @args }
function gpush   { git push origin HEAD @args }
function gpushf  {
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch -and $branch.Trim() -ne 'HEAD') {
        git push --force-with-lease -u origin "$($branch.Trim())" @args
    } else {
        git push --force-with-lease origin HEAD @args
    }
}
function gpull   { git pull --rebase origin HEAD @args }
function gup     { git fetch && git pull --rebase origin HEAD @args }

function gprune {
    $currentBranch = Get-GitCurrentBranch
    if (-not $currentBranch) { return }

    $targetBranch = Resolve-GitPrimaryBranch
    if (-not $targetBranch) { return }

    git checkout $targetBranch
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Error: failed to checkout $targetBranch"
        return
    }

    $branches = git branch --format="%(refname:short)" | Where-Object { $_ -and $_ -notmatch '^(main|master)$' }
    if ($branches) {
        $branches | ForEach-Object { git branch -D $_ }
    }
}

function guser-branch {
    $user = if ($env:USER) { $env:USER } else { $env:USERNAME }
    $branch = Get-GitCurrentBranch
    if (-not $branch) { return }

    if ($branch -ne 'HEAD') {
        $cleanBranch = $branch -replace "^($([regex]::Escape($user))/)+", ""
        git branch -m "$user/$cleanBranch"
    }
}

function fix-abcxyz-branch-name {
    guser-branch
}

function gsync {
    $currentBranch = Get-GitCurrentBranch
    if (-not $currentBranch) { return }

    $targetBranch = Resolve-GitPrimaryBranch
    if (-not $targetBranch) { return }

    if ($currentBranch -eq $targetBranch) {
        git pull --rebase origin $targetBranch
    } else {
        git checkout $targetBranch && git pull --rebase origin $targetBranch && git checkout $currentBranch && git rebase $targetBranch
    }
}
