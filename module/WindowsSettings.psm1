# =============================================================
# WindowsSettings - Modern Developer Workstation PowerShell Module
# High-Performance Shell Loader (<100ms startup)
# =============================================================

# -------------------------------------------------------------
# 1. High-Speed PATH & Environment Initialization
# -------------------------------------------------------------
$wingetLinksDir = "$env:LOCALAPPDATA\Microsoft\WinGet\Links"
if ($env:Path -notlike "*$wingetLinksDir*") {
    $env:Path = "$wingetLinksDir;$env:Path"
}

# Go GOPATH binary directory (zero process spawn)
$goBin = if ($env:GOPATH) { "$env:GOPATH\bin" } else { "$HOME\go\bin" }
if ($env:Path -notlike "*$goBin*") {
    $env:Path = "$env:Path;$goBin"
}

# Cargo binary directory
$cargoBin = "$HOME\.cargo\bin"
if ((Test-Path $cargoBin) -and ($env:Path -notlike "*$cargoBin*")) {
    $env:Path = "$env:Path;$cargoBin"
}

# Mise shims binary directory
$miseShims = "$env:LOCALAPPDATA\mise\shims"
$miseFallback = "$HOME\.local\share\mise\shims"
if ((Test-Path $miseShims) -and ($env:Path -notlike "*$miseShims*")) {
    $env:Path = "$miseShims;$env:Path"
} elseif ((Test-Path $miseFallback) -and ($env:Path -notlike "*$miseFallback*")) {
    $env:Path = "$miseFallback;$env:Path"
}

# Solarized Dark LS_COLORS
$env:LS_COLORS = 'no=00:fi=00:di=34:ow=34;40:ln=35:pi=30;44:so=35;44:do=35;44:bd=33;44:cd=37;44:or=05;37;41:mi=05;37;41:ex=01;31:*.cmd=01;31:*.exe=01;31:*.com=01;31:*.bat=01;31:*.reg=01;31:*.app=01;31:*.txt=32:*.org=32:*.md=32:*.mkd=32:*.h=32:*.c=32:*.C=32:*.cc=32:*.cpp=32:*.cxx=32:*.objc=32:*.sh=32:*.csh=32:*.zsh=32:*.el=32:*.vim=32:*.java=32:*.pl=32:*.pm=32:*.py=32:*.rb=32:*.hs=32:*.php=32:*.htm=32:*.html=32:*.shtml=32:*.xml=32:*.rdf=32:*.css=32:*.js=32:*.man=32:*.0=32:*.1=32:*.2=32:*.3=32:*.4=32:*.5=32:*.6=32:*.7=32:*.8=32:*.9=32:*.l=32:*.n=32:*.p=32:*.pod=32:*.tex=32:*.bmp=33:*.cgm=33:*.dl=33:*.dvi=33:*.emf=33:*.eps=33:*.gif=33:*.jpeg=33:*.jpg=33:*.JPG=33:*.mng=33:*.pbm=33:*.pcx=33:*.pdf=33:*.pgm=33:*.png=33:*.ppm=33:*.pps=33:*.ppsx=33:*.ps=33:*.svg=33:*.svgz=33:*.tga=33:*.tif=33:*.tiff=33:*.xbm=33:*.xcf=33:*.xpm=33:*.xwd=33:*.xwd=33:*.yuv=33:*.aac=33:*.au=33:*.flac=33:*.mid=33:*.midi=33:*.mka=33:*.mp3=33:*.mpa=33:*.mpeg=33:*.mpg=33:*.ogg=33:*.ra=33:*.wav=33:*.anx=33:*.asf=33:*.avi=33:*.axv=33:*.flc=33:*.fli=33:*.flv=33:*.gl=33:*.m2v=33:*.m4v=33:*.mkv=33:*.mov=33:*.mp4=33:*.mp4v=33:*.mpeg=33:*.mpg=33:*.nuv=33:*.ogm=33:*.ogv=33:*.ogx=33:*.qt=33:*.rm=33:*.rmvb=33:*.swf=33:*.vob=33:*.wmv=33:*.doc=31:*.docx=31:*.rtf=31:*.dot=31:*.dotx=31:*.xls=31:*.xlsx=31:*.ppt=31:*.pptx=31:*.fla=31:*.psd=31:*.7z=1;35:*.apk=1;35:*.arj=1;35:*.bin=1;35:*.bz=1;35:*.bz2=1;35:*.cab=1;35:*.deb=1;35:*.dmg=1;35:*.gem=1;35:*.gz=1;35:*.iso=1;35:*.jar=1;35:*.msi=1;35:*.rar=1;35:*.rpm=1;35:*.tar=1;35:*.tbz=1;35:*.tbz2=1;35:*.tgz=1;35:*.tx=1;35:*.war=1;35:*.xpi=1;35:*.xz=1;35:*.z=1;35:*.Z=1;35:*.zip=1;35:*.log=01;32:*~=01;32:*#=01;32:*.bak=01;33:*.BAK=01;33:*.old=01;33:*.OLD=01;33:*.org_archive=01;33:*.off=01;33:*.OFF=01;33:*.dist=01;33:*.DIST=01;33:*.orig=01;33:*.ORIG=01;33:*.swp=01;33:*.swo=01;33:*,v=01;33:*.gpg=34:*.gpg=34:*.pgp=34:*.asc=34:*.3des=34:*.aes=34:*.enc=34:'

# Solarized Dark EZA_COLORS & EXA_COLORS (Fixes dark tree lines & punctuation for eza)
$env:EZA_COLORS = 'xx=38;5;10:da=38;5;10:sn=38;5;14:sb=38;5;12:hd=38;5;14;4:lp=38;5;14:ga=38;5;10:gm=38;5;11:gd=38;5;9:gv=38;5;10'
$env:EXA_COLORS = $env:EZA_COLORS

# Solarized Dark BAT_THEME for bat / cat
$env:BAT_THEME = 'Solarized-Dark-TrueColor'

# Enable 24-bit TrueColor across modern CLI tools (bat, delta, eza, etc.)
$env:COLORTERM = 'truecolor'

# -------------------------------------------------------------
# 2. Un-Alias Conflicting Legacy Cmdlets
# -------------------------------------------------------------
$unalias = @('cat', 'sort', 'tee', 'diff', 'echo', 'sleep', 'ls', 'gcm', 'gl', 'gp')
foreach ($a in $unalias) {
    if (Test-Path "Alias:$a") {
        Remove-Item -Path "Alias:$a" -Force -ErrorAction SilentlyContinue
    }
}

# -------------------------------------------------------------
# 3. Prompt Engine (Oh My Posh Compiled Disk Cache)
# -------------------------------------------------------------
$ompCacheDir = "$HOME\.cache\powershell"
$ompInit = "$ompCacheDir\omp_init.ps1"
$themePath = "$HOME\.poshthemes\p10k_single_line.omp.json"

if ((Test-Path $ompInit) -and (Get-Item $ompInit).Length -gt 0) {
    . $ompInit
} elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    if (Test-Path $themePath) {
        if (-not (Test-Path $ompCacheDir)) {
            New-Item -ItemType Directory -Force -Path $ompCacheDir | Out-Null
        }
        oh-my-posh init pwsh --config $themePath --print | Out-File -FilePath $ompInit -Encoding utf8 -Force
        if ((Test-Path $ompInit) -and (Get-Item $ompInit).Length -gt 0) {
            . $ompInit
        }
    } else {
        oh-my-posh init pwsh | Invoke-Expression
    }
}

# -------------------------------------------------------------
# 4. PSReadLine & Predictive IntelliSense (Solarized Dark)
# -------------------------------------------------------------
try {
    Import-Module PSReadLine -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction SilentlyContinue
    Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
    Set-PSReadLineOption -Colors @{
        Default                 = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - standard arguments/paths/text)
        Command                 = "`e[38;2;133;153;0m"    # Solarized Green (#859900)
        Parameter               = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained options/parameters)
        Operator                = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained operators/pipes)
        Variable                = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained variables)
        String                  = "`e[38;2;42;161;152m"   # Solarized Cyan (#2AA198)
        Number                  = "`e[38;2;211;54;130m"   # Solarized Magenta (#D33682)
        Type                    = "`e[38;2;181;137;0m"    # Solarized Yellow (#B58900)
        Comment                 = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
        Keyword                 = "`e[38;2;133;153;0m"    # Solarized Green (#859900)
        Member                  = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496)
        Emphasis                = "`e[38;2;38;139;210m"   # Solarized Blue (#268BD2)
        Error                   = "`e[38;2;220;50;47m"    # Solarized Red (#DC322F)
        Selection               = "`e[48;2;7;54;66m"      # Solarized Base02 (#073642 bg)
        InlinePrediction        = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75 muted prediction)
        ListPrediction          = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
        ListPredictionSelected  = "`e[48;2;7;54;66m"      # Solarized Base02 (#073642 bg)
        ListPredictionTooltip   = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
    } -ErrorAction SilentlyContinue
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

# -------------------------------------------------------------
# 5. Static Inlined Public Functions & Completers (Zero Disk Scan)
# -------------------------------------------------------------
. "$PSScriptRoot\Git.ps1"
. "$PSScriptRoot\Developer.ps1"
. "$PSScriptRoot\Navigation.ps1"
. "$PSScriptRoot\Utilities.ps1"
. "$PSScriptRoot\Completions.ps1"

