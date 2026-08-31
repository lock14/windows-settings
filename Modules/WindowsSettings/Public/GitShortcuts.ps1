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

function gco  { git checkout @args }
function gcb  { git checkout -b @args }
function gcm  {
    git show-ref --verify --quiet refs/heads/main
    if ($LASTEXITCODE -eq 0) { git checkout main @args } else { git checkout master @args }
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

# Repository Custom Workflow Helpers
function gcommit { git add -A; git commit @args }
function gamend  { git add -A; git commit --amend --no-edit @args }
function gfetch  { git fetch @args }
function gpush   { git push origin HEAD @args }
function gpushf  { git push --force-with-lease origin HEAD @args }
function gpull   { git pull --rebase origin HEAD @args }
function gup     { git fetch; git pull --rebase origin HEAD @args }

function gprune {
    $branches = git branch --format="%(refname:short)" | Where-Object { $_ -and $_ -notmatch '^(main|master)$' }
    if ($branches) {
        $branches | ForEach-Object { git branch -D $_ }
    }
}

function guser-branch {
    $user = if ($env:USER) { $env:USER } else { $env:USERNAME }
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch) {
        $cleanBranch = $branch.Trim() -replace "^($([regex]::Escape($user))/)+", ""
        git branch -m "$user/$cleanBranch"
    }
}

function fix-abcxyz-branch-name {
    guser-branch
}

function gsync {
    $currentBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $currentBranch) {
        Write-Error "Error: not in a git repository"
        return
    }
    $currentBranch = $currentBranch.Trim()

    git show-ref --verify --quiet refs/heads/main
    $hasMain = ($LASTEXITCODE -eq 0)

    git show-ref --verify --quiet refs/heads/master
    $hasMaster = ($LASTEXITCODE -eq 0)

    $targetBranch = if ($hasMain) {
        "main"
    } elseif ($hasMaster) {
        "master"
    } else {
        Write-Error "Error: neither 'main' nor 'master' branch found locally."
        return
    }

    git checkout $targetBranch && git pull --rebase origin $targetBranch && git checkout $currentBranch && git rebase $targetBranch
}
