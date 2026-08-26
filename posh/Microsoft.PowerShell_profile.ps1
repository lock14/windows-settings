# =============================================================
# PowerShell Profile - windows-settings
# =============================================================

# 1. Oh My Posh Theme Initialization
$themePath = "$HOME\.poshthemes\p10k_single_line.omp.json"
if (Test-Path $themePath) {
    oh-my-posh init pwsh --config $themePath | Invoke-Expression
} elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh | Invoke-Expression
}

# -------------------------------------------------------------
# 2. PSReadLine & Predictive Auto-Suggestions (Solarized Dark)
# -------------------------------------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    try {
        # Inline predictive history (Fish / Zsh-autosuggestions style)
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue

        # Styled in Solarized Dark muted tone (base01)
        Set-PSReadLineOption -Colors @{
            InlinePrediction = '#586E75'
        } -ErrorAction SilentlyContinue

        # Tab menu completion
        Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction SilentlyContinue
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction SilentlyContinue

        # Interactive FZF History Search (Ctrl+R)
        Set-PSReadLineKeyHandler -Chord 'Ctrl+r' -ScriptBlock {
            if (Get-Command fzf -ErrorAction SilentlyContinue) {
                $historyFile = (Get-PSReadLineOption).HistorySavePath
                if (Test-Path $historyFile) {
                    $selected = Get-Content $historyFile -Encoding UTF8 |
                                Select-Object -Unique |
                                fzf --tac --no-sort --reverse --prompt="History > "
                    if ($selected) {
                        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
                        [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selected)
                    }
                }
            } else {
                [Microsoft.PowerShell.PSConsoleReadLine]::ReverseSearchHistory()
            }
        } -ErrorAction SilentlyContinue
    } catch {
        $null = $_
    }
}

# -------------------------------------------------------------
# 3. Developer Tool Aliases (Go, Terraform, YAML, Search)
# -------------------------------------------------------------
# Go
function go_testall  { go test ./... @args }
function go_buildall { go build ./... @args }
function go_lint {
    $cacheDir = if ($env:XDG_CACHE_HOME) { "$env:XDG_CACHE_HOME" } else { "$HOME\.cache" }
    if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null }
    $cfg = Join-Path $cacheDir "golangci.yml"
    if (-not (Test-Path $cfg)) {
        Invoke-WebRequest -Uri "https://raw.githubusercontent.com/abcxyz/pkg/main/.golangci.yml" -OutFile $cfg -UseBasicParsing
    }
    golangci-lint run -c $cfg @args
}

# Terraform & YAML
Set-Alias -Name tf -Value terraform -ErrorAction SilentlyContinue
function yaml_lint { yamllint -c "$HOME\.yamllint.yml" @args }

# Directory Visual Search Helper (fd + tree or recursive search)
function fs {
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        if (Get-Command tree -ErrorAction SilentlyContinue) {
            fd --no-ignore-vcs @args | tree --fromfile
        } else {
            fd --no-ignore-vcs @args
        }
    } else {
        Get-ChildItem -Recurse @args | Select-Object FullName
    }
}

# -------------------------------------------------------------
# 4. Git Shortcuts (Oh My Zsh Git plugin & custom shortcuts)
# -------------------------------------------------------------
# Oh My Zsh Git Plugin Aliases
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

# Custom Git Shortcuts
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

function fix-abcxyz-branch-name {
    $user = if ($env:USER) { $env:USER } else { $env:USERNAME }
    $branch = (git rev-parse --abbrev-ref HEAD 2>$null)
    if ($branch) {
        git branch -m "$user/$($branch.Trim())"
    }
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
