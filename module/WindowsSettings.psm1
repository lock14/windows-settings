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

# Go binary directory (GOBIN or GOPATH/bin) (zero process spawn)
$goBin = if ($env:GOBIN) { $env:GOBIN } elseif ($env:GOPATH) { "$env:GOPATH\bin" } else { "$HOME\go\bin" }
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

# Solarized Dark LS_COLORS (Calibrated unbolded GNU dircolors)
$env:LS_COLORS = 'no=00:fi=00:rs=0:di=34:ow=34;40:ln=36:mh=00:pi=33:so=35:do=35:bd=35:cd=35:or=31:mi=31:su=37;41:sg=30;43:ca=30;41:tw=30;42:st=37;44:ex=32:*.cmd=32:*.exe=32:*.com=32:*.bat=32:*.reg=32:*.app=32:*.bmp=95:*.cgm=95:*.dl=95:*.dvi=95:*.emf=95:*.eps=95:*.gif=95:*.jpeg=95:*.jpg=95:*.JPG=95:*.mng=95:*.pbm=95:*.pcx=95:*.pgm=95:*.png=95:*.ppm=95:*.pps=95:*.ppsx=95:*.ps=95:*.svg=95:*.svgz=95:*.tga=95:*.tif=95:*.tiff=95:*.webp=95:*.xbm=95:*.xcf=95:*.xpm=95:*.xwd=95:*.yuv=95:*.aac=95:*.au=95:*.flac=95:*.mid=95:*.midi=95:*.mka=95:*.mp3=95:*.mpa=95:*.ogg=95:*.ra=95:*.wav=95:*.anx=95:*.asf=95:*.avi=95:*.axv=95:*.flc=95:*.fli=95:*.flv=95:*.gl=95:*.m2v=95:*.m4v=95:*.mkv=95:*.mov=95:*.mp4=95:*.mp4v=95:*.mpeg=95:*.mpg=95:*.nuv=95:*.ogm=95:*.ogv=95:*.ogx=95:*.qt=95:*.rm=95:*.rmvb=95:*.swf=95:*.vob=95:*.webm=95:*.wmv=95:*.7z=91:*.apk=91:*.arj=91:*.bin=91:*.bz=91:*.bz2=91:*.cab=91:*.deb=91:*.dmg=91:*.gem=91:*.gz=91:*.iso=91:*.jar=91:*.msi=91:*.rar=91:*.rpm=91:*.tar=91:*.tbz=91:*.tbz2=91:*.tgz=91:*.tx=91:*.war=91:*.xpi=91:*.xz=91:*.z=91:*.Z=91:*.zip=91:*.zst=91:*.txt=00:*.org=00:*.md=00:*.mkd=00:*.markdown=00:*.doc=00:*.docx=00:*.rtf=00:*.dot=00:*.dotx=00:*.xls=00:*.xlsx=00:*.ppt=00:*.pptx=00:*.pdf=00:*.tex=00:*.epub=00:*.c=00:*.C=00:*.cc=00:*.cpp=00:*.cxx=00:*.h=00:*.hh=00:*.hpp=00:*.hxx=00:*.rs=00:*.go=00:*.py=00:*.java=00:*.js=00:*.ts=00:*.sh=00:*.zsh=00:*.bash=00:*.json=00:*.yaml=00:*.yml=00:*.toml=00:*.xml=00:*.html=00:*.css=00:*.sql=00:*.tf=00:*.gpg=35:*.pgp=35:*.asc=35:*.3des=35:*.aes=35:*.enc=35:*.key=35:*.pem=35:*.crt=35:*.cer=35:*.bak=90:*.BAK=90:*.old=90:*.OLD=90:*.orig=90:*.ORIG=90:*.swp=90:*.swo=90:*~=90:*#=90:*.log=90:'

# Solarized Dark EZA_COLORS & EXA_COLORS (24-bit TrueColor Ethan Schoonover specification)
$env:EZA_COLORS = 'di=38;2;38;139;210:ex=38;2;133;153;0:fi=38;2;131;148;150:pi=38;2;181;137;0:so=38;2;211;54;130:bd=38;2;211;54;130:cd=38;2;211;54;130:ln=38;2;42;161;152:or=38;2;220;50;47:xx=38;2;88;110;117:da=38;2;131;148;150:hd=4;38;2;147;161;161:lp=38;2;131;148;150:cc=38;2;203;75;22:bO=38;2;220;50;47:in=38;2;88;110;117:bl=38;2;88;110;117:oc=38;2;131;148;150:ur=38;2;131;148;150:uw=38;2;131;148;150:ux=38;2;131;148;150:ue=38;2;131;148;150:gr=38;2;131;148;150:gw=38;2;131;148;150:gx=38;2;131;148;150:tr=38;2;131;148;150:tw=38;2;131;148;150:tx=38;2;131;148;150:su=38;2;131;148;150:sf=38;2;131;148;150:xa=38;2;131;148;150:sn=38;2;131;148;150:nb=38;2;88;110;117:nk=38;2;131;148;150:nm=38;2;181;137;0:ng=38;2;203;75;22:nt=38;2;220;50;47:sb=38;2;131;148;150:ub=38;2;88;110;117:uk=38;2;131;148;150:um=38;2;181;137;0:ug=38;2;203;75;22:ut=38;2;220;50;47:df=38;2;131;148;150:ds=38;2;131;148;150:uu=38;2;131;148;150:uR=38;2;220;50;47:un=38;2;131;148;150:gu=38;2;131;148;150:gR=38;2;220;50;47:gn=38;2;131;148;150:lc=38;2;131;148;150:lm=38;2;181;137;0:ga=38;2;133;153;0:gm=38;2;181;137;0:gd=38;2;220;50;47:gv=38;2;131;148;150:gt=38;2;131;148;150:gi=38;2;88;110;117:gc=38;2;220;50;47:Gm=38;2;133;153;0:Go=38;2;38;139;210:Gc=38;2;133;153;0:Gd=38;2;181;137;0:sp=38;2;203;75;22:mp=38;2;38;139;210:im=38;2;108;113;196:vi=38;2;108;113;196:mu=38;2;108;113;196:lo=38;2;108;113;196:cr=38;2;211;54;130:do=38;2;131;148;150:co=38;2;203;75;22:tm=38;2;88;110;117:cm=38;2;88;110;117:bu=38;2;133;153;0:sc=38;2;131;148;150:Sn=38;2;88;110;117:Su=38;2;131;148;150:Sr=38;2;131;148;150:St=38;2;131;148;150:Sl=38;2;131;148;150:ff=38;2;131;148;150'
$env:EXA_COLORS = $env:EZA_COLORS

# Solarized Dark BAT_THEME & BAT_OPTS for bat / cat
$env:BAT_THEME = 'Solarized-Dark-TrueColor'
$env:BAT_OPTS = '--italic-text=always'

# Enable 24-bit TrueColor across modern CLI tools (bat, delta, eza, etc.)
$env:COLORTERM = 'truecolor'

# FZF Solarized Dark theme & ripgrep / fd integration
$env:FZF_DEFAULT_OPTS = '--color=bg+:#073642,bg:#002B36,spinner:#859900,hl:#586E75 --color=fg:#839496,header:#586E75,info:#B58900,pointer:#859900 --color=marker:#859900,fg+:#93A1A1,prompt:#B58900,hl+:#268BD2 --layout=reverse --border=rounded --info=inline'
if (Get-Command rg -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'rg --files --hidden --glob !.git'
    $env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
} elseif (Get-Command fd -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_COMMAND = 'fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
    $env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
}

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
    Set-PSReadLineOption -Colors @{
        Default                 = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - standard arguments/paths/text)
        Command                 = "`e[38;2;133;153;0m"    # Solarized Green (#859900)
        Parameter               = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained options/parameters)
        Operator                = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained operators/pipes)
        Variable                = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496 - restrained variables)
        String                  = "`e[38;2;42;161;152m"   # Solarized Cyan (#2AA198)
        Number                  = "`e[38;2;211;54;130m"   # Solarized Magenta (#D33682)
        Type                    = "`e[38;2;133;153;0m"    # Solarized Green (#859900 - primitive types & core built-ins)
        Comment                 = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
        Keyword                 = "`e[38;2;181;137;0m"    # Solarized Yellow (#B58900 - uncontested control flow & jumps)
        Member                  = "`e[38;2;131;148;150m"  # Solarized Base0 (#839496)
        Emphasis                = "`e[38;2;38;139;210m"   # Solarized Blue (#268BD2)
        Error                   = "`e[38;2;220;50;47m"    # Solarized Red (#DC322F)
        Selection               = "`e[48;2;7;54;66m"      # Solarized Base02 (#073642 bg)
        InlinePrediction        = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75 muted prediction)
        ListPrediction          = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
        ListPredictionSelected  = "`e[48;2;7;54;66m"      # Solarized Base02 (#073642 bg)
        ListPredictionTooltip   = "`e[38;2;88;110;117m"   # Solarized Base01 (#586E75)
    } -ErrorAction SilentlyContinue

    # Predictive suggestions require interactive virtual terminal processing
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction Stop
    } catch {
        $null = $_
    }

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

