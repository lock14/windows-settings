# =============================================================
# PowerShell Profile - windows-settings
# =============================================================

# 1. Oh My Posh Theme Initialization (High-speed cached load)
$themePath = "$HOME\.poshthemes\p10k_single_line.omp.json"
$ompCacheDir = "$HOME\.cache\powershell"
$ompInit = "$ompCacheDir\omp_init.ps1"

if (Test-Path $themePath) {
    if (-not (Test-Path $ompInit) -or ((Get-Item $themePath).LastWriteTime -gt (Get-Item $ompInit).LastWriteTime)) {
        if (-not (Test-Path $ompCacheDir)) {
            New-Item -ItemType Directory -Force -Path $ompCacheDir | Out-Null
        }
        oh-my-posh init pwsh --config $themePath --print | Out-File -FilePath $ompInit -Encoding utf8 -Force
    }
    if (Test-Path $ompInit) {
        . $ompInit
    }
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

        # Full Solarized Dark syntax highlighting
        Set-PSReadLineOption -Colors @{
            Command          = '#859900'  # Solarized Green
            Parameter        = '#2AA198'  # Solarized Cyan (clear contrast for -Flags)
            Operator         = '#839496'  # Solarized Base0
            Variable         = '#B58900'  # Solarized Yellow
            String           = '#2AA198'  # Solarized Cyan
            Number           = '#D33682'  # Solarized Magenta
            Type             = '#B58900'  # Solarized Yellow
            Comment          = '#586E75'  # Solarized Base01
            Keyword          = '#859900'  # Solarized Green
            InlinePrediction = '#586E75'  # Solarized Base01 muted prediction
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

# Terraform & YAML & Editors
Set-Alias -Name tf -Value terraform -ErrorAction SilentlyContinue
Set-Alias -Name vi -Value vim -ErrorAction SilentlyContinue
function yaml_lint { yamllint -c "$HOME\.yamllint.yml" @args }

# Directory Listing (Ubuntu style)
function ll {
    if (Get-Command 'C:\Program Files\coreutils\cmd\ls.cmd' -ErrorAction SilentlyContinue) {
        & 'C:\Program Files\coreutils\cmd\ls.cmd' --color=auto -alFh @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -alFh @args
    } else {
        Get-ChildItem -Force @args
    }
}

function la {
    if (Get-Command 'C:\Program Files\coreutils\cmd\ls.cmd' -ErrorAction SilentlyContinue) {
        & 'C:\Program Files\coreutils\cmd\ls.cmd' --color=auto -AFhl @args
    } elseif (Get-Command ls.exe -ErrorAction SilentlyContinue) {
        & ls.exe --color=auto -AFhl @args
    } else {
        Get-ChildItem -Force @args
    }
}

# Visual Tree Path Formatter (Native PowerShell replacement for Linux `tree --fromfile`)
function Format-PathTree {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true)]
        [string[]]$Paths
    )

    begin {
        $allPaths = [System.Collections.Generic.List[string]]::new()
    }
    process {
        if ($null -ne $Paths) {
            foreach ($p in $Paths) {
                if ($p) { $allPaths.Add($p.Trim()) }
            }
        }
    }
    end {
        if ($allPaths.Count -eq 0) { return }

        $root = [ordered]@{}
        foreach ($rawPath in $allPaths) {
            $parts = $rawPath -split '[\\/]' | Where-Object { $_ -ne '' }
            $current = $root
            foreach ($part in $parts) {
                if (-not $current.Contains($part)) {
                    $current[$part] = [ordered]@{}
                }
                $current = $current[$part]
            }
        }

        function Render-TreeNode($node, $prefix) {
            $keys = [string[]]$node.Keys
            for ($i = 0; $i -lt $keys.Count; $i++) {
                $key = $keys[$i]
                $isLast = ($i -eq $keys.Count - 1)
                $connector = if ($isLast) { [char]0x2514 + [char]0x2500 + [char]0x2500 + ' ' } else { [char]0x251C + [char]0x2500 + [char]0x2500 + ' ' }
                $childPrefix = if ($isLast) { '    ' } else { [char]0x2502 + '   ' }

                $isDir = ($node[$key].Keys.Count -gt 0)
                $color = if ($isDir) {
                    'Blue'
                } elseif ($key -match '\.(go|py|rs|c|cpp|h|java|md|txt|json|yml|yaml|toml|xml)$') {
                    'Green'
                } elseif ($key -match '\.(exe|cmd|bat|ps1|sh)$') {
                    'Red'
                } elseif ($key -match '\.(zip|tar|gz|7z|rar|iso|png|jpg|svg|mp4)$') {
                    'Yellow'
                } else {
                    'White'
                }

                Write-Host -NoNewline "$prefix$connector" -ForegroundColor Gray
                Write-Host "$key" -ForegroundColor $color

                if ($isDir) {
                    Render-TreeNode $node[$key] "$prefix$childPrefix"
                }
            }
        }

        Write-Host '.' -ForegroundColor Cyan
        Render-TreeNode $root ''
    }
}

# Directory Visual Search Helper (fd piped to Format-PathTree visual hierarchy)
function fs {
    if (Get-Command fd -ErrorAction SilentlyContinue) {
        fd --no-ignore-vcs @args | Format-PathTree
    } else {
        Get-ChildItem -Recurse @args | Select-Object -ExpandProperty FullName | Format-PathTree
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

# -------------------------------------------------------------
# 5. Native CLI Utilities (gen-passwd, repeat-until-success, sum)
# -------------------------------------------------------------
$wsBinDir = if ($PSScriptRoot) { Join-Path (Split-Path -Parent $PSScriptRoot) "bin" } else { "C:\Users\brian\windows-settings\bin" }
if (-not (Test-Path $wsBinDir)) {
    $wsBinDir = "$HOME\windows-settings\bin"
}

if (Test-Path $wsBinDir) {
    if ($env:Path -notlike "*$wsBinDir*") {
        $env:Path = "$env:Path;$wsBinDir"
    }

    function global:gen-passwd {
        & "$wsBinDir\gen-passwd.ps1" @args
    }

    function global:repeat-until-success {
        & "$wsBinDir\repeat-until-success.ps1" @args
    }

    function global:sum {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline = $true, ValueFromRemainingArguments = $true, Position = 0)]
            [object[]]$InputObject
        )
        begin {
            $items = [System.Collections.Generic.List[object]]::new()
        }
        process {
            if ($null -ne $InputObject) {
                foreach ($i in $InputObject) {
                    $items.Add($i)
                }
            }
        }
        end {
            & "$wsBinDir\sum.ps1" @items
        }
    }
}

# -------------------------------------------------------------
# 6. Solarized Dark LS_COLORS (matching home-settings)
# -------------------------------------------------------------
$env:LS_COLORS = 'no=00:fi=00:di=34:ow=34;40:ln=35:pi=30;44:so=35;44:do=35;44:bd=33;44:cd=37;44:or=05;37;41:mi=05;37;41:ex=01;31:*.cmd=01;31:*.exe=01;31:*.com=01;31:*.bat=01;31:*.reg=01;31:*.app=01;31:*.txt=32:*.org=32:*.md=32:*.mkd=32:*.h=32:*.c=32:*.C=32:*.cc=32:*.cpp=32:*.cxx=32:*.objc=32:*.sh=32:*.csh=32:*.zsh=32:*.el=32:*.vim=32:*.java=32:*.pl=32:*.pm=32:*.py=32:*.rb=32:*.hs=32:*.php=32:*.htm=32:*.html=32:*.shtml=32:*.xml=32:*.rdf=32:*.css=32:*.js=32:*.man=32:*.0=32:*.1=32:*.2=32:*.3=32:*.4=32:*.5=32:*.6=32:*.7=32:*.8=32:*.9=32:*.l=32:*.n=32:*.p=32:*.pod=32:*.tex=32:*.bmp=33:*.cgm=33:*.dl=33:*.dvi=33:*.emf=33:*.eps=33:*.gif=33:*.jpeg=33:*.jpg=33:*.JPG=33:*.mng=33:*.pbm=33:*.pcx=33:*.pdf=33:*.pgm=33:*.png=33:*.ppm=33:*.pps=33:*.ppsx=33:*.ps=33:*.svg=33:*.svgz=33:*.tga=33:*.tif=33:*.tiff=33:*.xbm=33:*.xcf=33:*.xpm=33:*.xwd=33:*.xwd=33:*.yuv=33:*.aac=33:*.au=33:*.flac=33:*.mid=33:*.midi=33:*.mka=33:*.mp3=33:*.mpa=33:*.mpeg=33:*.mpg=33:*.ogg=33:*.ra=33:*.wav=33:*.anx=33:*.asf=33:*.avi=33:*.axv=33:*.flc=33:*.fli=33:*.flv=33:*.gl=33:*.m2v=33:*.m4v=33:*.mkv=33:*.mov=33:*.mp4=33:*.mp4v=33:*.mpeg=33:*.mpg=33:*.nuv=33:*.ogm=33:*.ogv=33:*.ogx=33:*.qt=33:*.rm=33:*.rmvb=33:*.swf=33:*.vob=33:*.wmv=33:*.doc=31:*.docx=31:*.rtf=31:*.dot=31:*.dotx=31:*.xls=31:*.xlsx=31:*.ppt=31:*.pptx=31:*.fla=31:*.psd=31:*.7z=1;35:*.apk=1;35:*.arj=1;35:*.bin=1;35:*.bz=1;35:*.bz2=1;35:*.cab=1;35:*.deb=1;35:*.dmg=1;35:*.gem=1;35:*.gz=1;35:*.iso=1;35:*.jar=1;35:*.msi=1;35:*.rar=1;35:*.rpm=1;35:*.tar=1;35:*.tbz=1;35:*.tbz2=1;35:*.tgz=1;35:*.tx=1;35:*.war=1;35:*.xpi=1;35:*.xz=1;35:*.z=1;35:*.Z=1;35:*.zip=1;35:*.log=01;32:*~=01;32:*#=01;32:*.bak=01;33:*.BAK=01;33:*.old=01;33:*.OLD=01;33:*.org_archive=01;33:*.off=01;33:*.OFF=01;33:*.dist=01;33:*.DIST=01;33:*.orig=01;33:*.ORIG=01;33:*.swp=01;33:*.swo=01;33:*,v=01;33:*.gpg=34:*.gpg=34:*.pgp=34:*.asc=34:*.3des=34:*.aes=34:*.enc=34:'
