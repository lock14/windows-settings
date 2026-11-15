# =============================================================
# WindowsSettings - Modern Developer Workstation PowerShell Module
# High-Performance Shell Loader (<10ms warm startup)
# =============================================================
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Oh My Posh prompt hook wraps global:prompt')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalFunctions', '', Justification = 'Oh My Posh prompt hook wraps global:prompt')]
param()

# -------------------------------------------------------------
# 1. High-Speed PATH & Environment Initialization
# -------------------------------------------------------------
if ($env:ProgramFiles) {
    $gitMingwBin = Join-Path $env:ProgramFiles 'Git\mingw64\bin'
    $gitCmdBin = Join-Path $env:ProgramFiles 'Git\cmd'
    if ([System.IO.File]::Exists((Join-Path $gitMingwBin 'git.exe')) -and -not $env:Path.Contains($gitMingwBin, [System.StringComparison]::OrdinalIgnoreCase)) {
        $idxGitCmd = $env:Path.IndexOf($gitCmdBin, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idxGitCmd -ge 0) {
            $env:Path = $env:Path.Substring(0, $idxGitCmd) + "$gitMingwBin;" + $env:Path.Substring($idxGitCmd)
        }
    }
}

if ($env:LOCALAPPDATA) {
    $wingetLinksDir = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
    if ([System.IO.Directory]::Exists($wingetLinksDir) -and -not $env:Path.Contains($wingetLinksDir, [System.StringComparison]::OrdinalIgnoreCase)) {
        $env:Path = "$wingetLinksDir;$env:Path"
    }
}

$localUserBin = Join-Path $HOME '.local\bin'
if ([System.IO.Directory]::Exists($localUserBin) -and -not $env:Path.Contains($localUserBin, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$localUserBin;$env:Path"
}

$repoBinCandidate = Join-Path (Split-Path -Parent $PSScriptRoot) 'bin'
if ([System.IO.Directory]::Exists($repoBinCandidate) -and -not $env:Path.Contains($repoBinCandidate, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$repoBinCandidate;$env:Path"
}

# Go binary directories (GOBIN, GOPATH/bin, ~/.local/share/go/bin, ~/go/bin)
$goBinPrimary = if ($env:GOBIN) { $env:GOBIN } elseif ($env:GOPATH) { Join-Path $env:GOPATH 'bin' } else { Join-Path $HOME 'go\bin' }
if (-not $env:Path.Contains($goBinPrimary, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$env:Path;$goBinPrimary"
}
$goXdgBin = Join-Path $HOME '.local\share\go\bin'
if ([System.IO.Directory]::Exists($goXdgBin) -and -not $env:Path.Contains($goXdgBin, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$env:Path;$goXdgBin"
}

# Cargo & Elan (Lean 4) binary directories
foreach ($toolBin in @(
    (Join-Path $HOME '.cargo\bin'),
    (Join-Path $HOME '.local\share\elan\bin'),
    (Join-Path $HOME '.elan\bin')
)) {
    if ([System.IO.Directory]::Exists($toolBin) -and -not $env:Path.Contains($toolBin, [System.StringComparison]::OrdinalIgnoreCase)) {
        $env:Path = "$env:Path;$toolBin"
    }
}

# Mise shims fallback + pre-compiled direct Mise binary paths (ahead of shims to bypass ~180ms shim tax)
$psCacheDir = Join-Path $HOME '.cache\powershell'
$miseShims = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'mise\shims' } else { '' }
$miseFallback = Join-Path $HOME '.local\share\mise\shims'
if ($miseShims -and [System.IO.Directory]::Exists($miseShims) -and -not $env:Path.Contains($miseShims, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$miseShims;$env:Path"
} elseif ([System.IO.Directory]::Exists($miseFallback) -and -not $env:Path.Contains($miseFallback, [System.StringComparison]::OrdinalIgnoreCase)) {
    $env:Path = "$miseFallback;$env:Path"
}

$misePathsCache = Join-Path $psCacheDir 'mise_paths.ps1'
if ([System.IO.File]::Exists($misePathsCache)) {
    . $misePathsCache
}
if ($env:LOCALAPPDATA -and $env:WS_DISABLE_ASYNC_MISE_CACHE -ne '1') {
    $miseInstallsRoot = Join-Path $env:LOCALAPPDATA 'mise\installs'
    if ([System.IO.Directory]::Exists($miseInstallsRoot)) {
        $needMiseRefresh = -not [System.IO.File]::Exists($misePathsCache)
        if (-not $needMiseRefresh) {
            $instTicks = [System.IO.Directory]::GetLastWriteTimeUtc($miseInstallsRoot).Ticks
            $cacheTicks = [System.IO.File]::GetLastWriteTimeUtc($misePathsCache).Ticks
            if ($instTicks -gt $cacheTicks) { $needMiseRefresh = $true }
        }
        $miseLockFile = Join-Path $psCacheDir 'mise_paths.lock'
        if ($needMiseRefresh -and [System.IO.File]::Exists($miseLockFile)) {
            $lockAge = ([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($miseLockFile)).TotalSeconds
            if ($lockAge -lt 60) { $needMiseRefresh = $false }
        }
        if ($needMiseRefresh) {
            try {
                if (-not [System.IO.Directory]::Exists($psCacheDir)) {
                    [System.IO.Directory]::CreateDirectory($psCacheDir) | Out-Null
                }
                [System.IO.File]::WriteAllText($miseLockFile, '')
                $pwshExeMise = (Get-Process -Id $PID).Path
                if ($pwshExeMise) {
                    $cmdCacheTarget = Join-Path (Join-Path $env:LOCALAPPDATA 'cmd') 'mise_paths.cmd'
                    $bgMiseScript = @'
param([string]$PsCache, [string]$CmdCache, [string]$LockFile)
try {
    $rawPaths = @(mise bin-paths 2>$null)
    $cleanDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($rp in $rawPaths) {
        if (-not $rp -or -not "$rp".Trim()) { continue }
        $norm = "$rp".Trim().Replace('/', '\').TrimEnd('\')
        if ([System.IO.Directory]::Exists($norm) -and -not $cleanDirs.Contains($norm)) {
            $cleanDirs.Add($norm)
        }
    }
    if ($cleanDirs.Count -gt 0) {
        $marker = $cleanDirs[0]
        $joined = ($cleanDirs -join ';')
        $escMarker = $marker.Replace("'", "''")
        $escJoined = $joined.Replace("'", "''")
        $psLines = @(
            "`$script:_wsMiseMarker = '$escMarker'",
            "`$script:_wsMisePathBlock = '$escJoined'",
            'if ([System.IO.Directory]::Exists($script:_wsMiseMarker) -and -not $env:Path.Contains($script:_wsMiseMarker, [System.StringComparison]::OrdinalIgnoreCase)) {',
            '    $env:Path = "$script:_wsMisePathBlock;$env:Path"',
            '}'
        )
        [System.IO.File]::WriteAllText($PsCache, ($psLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
        $cmdDir = Split-Path -Parent $CmdCache
        if (-not [System.IO.Directory]::Exists($cmdDir)) { [System.IO.Directory]::CreateDirectory($cmdDir) | Out-Null }
        $cmdLines = @(
            "@if not exist `"$marker`" exit /b 0",
            "@call :ws_mise_has `"$marker`"",
            "@if errorlevel 1 set `"PATH=$joined;%PATH%`"",
            '@exit /b 0',
            ':ws_mise_has',
            '@setlocal EnableDelayedExpansion',
            '@set "_P=;!PATH!;"',
            '@set "_T=!_P:*;%~1;=FOUND!"',
            '@if "!_T:~0,5!"=="FOUND" (endlocal & exit /b 0)',
            '@endlocal & exit /b 1'
        )
        [System.IO.File]::WriteAllText($CmdCache, ($cmdLines -join "`r`n") + "`r`n", [System.Text.UTF8Encoding]::new($false))
    }
} finally {
    Remove-Item -LiteralPath $LockFile -Force -ErrorAction SilentlyContinue
}
'@
                    $psiM = [System.Diagnostics.ProcessStartInfo]::new()
                    $psiM.FileName = $pwshExeMise
                    $psiM.ArgumentList.Add('-NoLogo')
                    $psiM.ArgumentList.Add('-NoProfile')
                    $psiM.ArgumentList.Add('-NonInteractive')
                    $psiM.ArgumentList.Add('-Command')
                    $psiM.ArgumentList.Add("& { $bgMiseScript } -PsCache '$($misePathsCache.Replace("'", "''"))' -CmdCache '$($cmdCacheTarget.Replace("'", "''"))' -LockFile '$($miseLockFile.Replace("'", "''"))'")
                    $psiM.CreateNoWindow = $true
                    $psiM.UseShellExecute = $false
                    [void][System.Diagnostics.Process]::Start($psiM)
                }
            } catch {
                $null = $_
            }
        }
    }
}

$script:_wsPathDirs = $env:Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
function Test-WsExeOnPath([string]$ExeName) {
    foreach ($dir in $script:_wsPathDirs) {
        try {
            if ([System.IO.File]::Exists((Join-Path $dir $ExeName))) {
                return $true
            }
        } catch {
            $null = $_
        }
    }
    return $false
}

# Solarized Dark LS_COLORS (Calibrated 40-language unbolded GNU dircolors baseline)
$env:LS_COLORS = 'no=00:fi=00:rs=0:di=34:ow=34;40:ln=36:mh=00:pi=33:so=35:do=35:bd=35:cd=35:or=31:mi=31:su=37;41:sg=30;43:ca=30;41:tw=30;42:st=37;44:ex=32:*.cmd=32:*.exe=32:*.com=32:*.bat=32:*.reg=32:*.app=32:*.bmp=95:*.cgm=95:*.dl=95:*.dvi=95:*.emf=95:*.eps=95:*.gif=95:*.jpeg=95:*.jpg=95:*.JPG=95:*.mng=95:*.pbm=95:*.pcx=95:*.pgm=95:*.png=95:*.ppm=95:*.pps=95:*.ppsx=95:*.ps=95:*.svg=95:*.svgz=95:*.tga=95:*.tif=95:*.tiff=95:*.webp=95:*.xbm=95:*.xcf=95:*.xpm=95:*.xwd=95:*.yuv=95:*.aac=95:*.au=95:*.flac=95:*.mid=95:*.midi=95:*.mka=95:*.mp3=95:*.mpa=95:*.ogg=95:*.ra=95:*.wav=95:*.anx=95:*.asf=95:*.avi=95:*.axv=95:*.flc=95:*.fli=95:*.flv=95:*.gl=95:*.m2v=95:*.m4v=95:*.mkv=95:*.mov=95:*.mp4=95:*.mp4v=95:*.mpeg=95:*.mpg=95:*.nuv=95:*.ogm=95:*.ogv=95:*.ogx=95:*.qt=95:*.rm=95:*.rmvb=95:*.swf=95:*.vob=95:*.webm=95:*.wmv=95:*.7z=91:*.apk=91:*.arj=91:*.bin=91:*.bz=91:*.bz2=91:*.cab=91:*.deb=91:*.dmg=91:*.gem=91:*.gz=91:*.iso=91:*.jar=91:*.msi=91:*.rar=91:*.rpm=91:*.tar=91:*.tbz=91:*.tbz2=91:*.tgz=91:*.tx=91:*.war=91:*.xpi=91:*.xz=91:*.z=91:*.Z=91:*.zip=91:*.zst=91:*.txt=00:*.org=00:*.md=00:*.mkd=00:*.markdown=00:*.rst=00:*.adoc=00:*.doc=00:*.docx=00:*.rtf=00:*.dot=00:*.dotx=00:*.xls=00:*.xlsx=00:*.ppt=00:*.pptx=00:*.pdf=00:*.tex=00:*.epub=00:*.csv=00:*.tsv=00:*.c=00:*.C=00:*.cc=00:*.cpp=00:*.cxx=00:*.h=00:*.hh=00:*.hpp=00:*.hxx=00:*.rs=00:*.go=00:*.py=00:*.java=00:*.kt=00:*.kts=00:*.scala=00:*.swift=00:*.cs=00:*.zig=00:*.lua=00:*.rb=00:*.php=00:*.pl=00:*.pm=00:*.r=00:*.R=00:*.dart=00:*.ex=00:*.exs=00:*.erl=00:*.hrl=00:*.hs=00:*.ml=00:*.mli=00:*.lean=00:*.js=00:*.jsx=00:*.mjs=00:*.cjs=00:*.ts=00:*.tsx=00:*.sh=00:*.zsh=00:*.bash=00:*.fish=00:*.ps1=00:*.psm1=00:*.psd1=00:*.vim=00:*.json=00:*.jsonc=00:*.json5=00:*.yaml=00:*.yml=00:*.toml=00:*.ini=00:*.cfg=00:*.conf=00:*.properties=00:*.env=00:*.xml=00:*.html=00:*.htm=00:*.css=00:*.scss=00:*.less=00:*.sql=00:*.graphql=00:*.gql=00:*.proto=00:*.tf=00:*.tfvars=00:*.hcl=00:*.nix=00:*.cmake=00:*.mk=00:*.dockerfile=00:*.patch=00:*.diff=00:*.gpg=35:*.pgp=35:*.asc=35:*.3des=35:*.aes=35:*.enc=35:*.key=35:*.pem=35:*.crt=35:*.cer=35:*.p12=35:*.pfx=35:*.pub=35:*.bak=90:*.BAK=90:*.old=90:*.OLD=90:*.orig=90:*.ORIG=90:*.swp=90:*.swo=90:*~=90:*#=90:*.log=90:'

# Solarized Dark EZA_COLORS & EXA_COLORS (24-bit TrueColor Ethan Schoonover specification)
$env:EZA_COLORS = 'di=38;2;38;139;210:ex=38;2;133;153;0:fi=38;2;131;148;150:pi=38;2;181;137;0:so=38;2;211;54;130:bd=38;2;211;54;130:cd=38;2;211;54;130:ln=38;2;42;161;152:or=38;2;220;50;47:xx=38;2;88;110;117:da=38;2;131;148;150:hd=4;38;2;147;161;161:lp=38;2;131;148;150:cc=38;2;203;75;22:bO=38;2;220;50;47:in=38;2;88;110;117:bl=38;2;88;110;117:oc=38;2;131;148;150:ur=38;2;131;148;150:uw=38;2;131;148;150:ux=38;2;131;148;150:ue=38;2;131;148;150:gr=38;2;131;148;150:gw=38;2;131;148;150:gx=38;2;131;148;150:tr=38;2;131;148;150:tw=38;2;131;148;150:tx=38;2;131;148;150:su=38;2;131;148;150:sf=38;2;131;148;150:xa=38;2;131;148;150:sn=38;2;131;148;150:nb=38;2;88;110;117:nk=38;2;131;148;150:nm=38;2;181;137;0:ng=38;2;203;75;22:nt=38;2;220;50;47:sb=38;2;131;148;150:ub=38;2;88;110;117:uk=38;2;131;148;150:um=38;2;181;137;0:ug=38;2;203;75;22:ut=38;2;220;50;47:df=38;2;131;148;150:ds=38;2;131;148;150:uu=38;2;131;148;150:uR=38;2;220;50;47:un=38;2;131;148;150:gu=38;2;131;148;150:gR=38;2;220;50;47:gn=38;2;131;148;150:lc=38;2;131;148;150:lm=38;2;181;137;0:ga=38;2;133;153;0:gm=38;2;181;137;0:gd=38;2;220;50;47:gv=38;2;131;148;150:gt=38;2;131;148;150:gi=38;2;88;110;117:gc=38;2;220;50;47:Gm=38;2;133;153;0:Go=38;2;38;139;210:Gc=38;2;133;153;0:Gd=38;2;181;137;0:sp=38;2;203;75;22:mp=38;2;38;139;210:im=38;2;108;113;196:vi=38;2;108;113;196:mu=38;2;108;113;196:lo=38;2;108;113;196:cr=38;2;211;54;130:do=38;2;131;148;150:co=38;2;203;75;22:tm=38;2;88;110;117:cm=38;2;88;110;117:bu=38;2;133;153;0:sc=38;2;131;148;150:Sn=38;2;88;110;117:Su=38;2;131;148;150:Sr=38;2;131;148;150:St=38;2;131;148;150:Sl=38;2;131;148;150:ff=38;2;131;148;150'
$env:EXA_COLORS = $env:EZA_COLORS

# JQ_COLORS matching Universal Semantic Color Contract (null/bool/num Magenta, str Cyan, keys Green)
$env:JQ_COLORS = '0;35:0;35:0;35:0;39:0;36:0;39:0;39:0;32'

# BAT, TrueColor, OSC 8 Hyperlinks, Editor, IDE & Zoxide defaults
$env:BAT_THEME = 'Solarized-Dark-TrueColor'
$env:BAT_OPTS = '--italic-text=always'
$env:COLORTERM = 'truecolor'
$env:FORCE_HYPERLINK = '1'
if (-not $env:EDITOR) { $env:EDITOR = 'nvim' }
if (-not $env:VISUAL) { $env:VISUAL = 'nvim' }
if (-not $env:IDE_AI_CLI) { $env:IDE_AI_CLI = 'agy' }
$env:_ZO_ECHO = '1'
$env:_ZO_RESOLVE_SYMLINKS = '1'
$env:LESS = '-R -F -X'
$env:GROFF_NO_SGR = '1'

# Default C/C++ compilers for Tree-sitter and native toolchains
if (-not $env:CC) { $env:CC = 'gcc' }
if (-not $env:CXX) { $env:CXX = 'g++' }

# FZF Solarized Dark baseline & ripgrep / fd integration
$env:FZF_DEFAULT_OPTS = '--color=bg+:#073642,bg:#002B36,spinner:#859900,hl:#586E75 --color=fg:#839496,header:#586E75,info:#B58900,pointer:#859900 --color=marker:#859900,fg+:#93A1A1,prompt:#B58900,hl+:#268BD2 --layout=reverse --border=rounded --info=inline'
$env:_ZO_FZF_OPTS = $env:FZF_DEFAULT_OPTS

if (-not $env:FZF_DEFAULT_COMMAND) {
    if (Test-WsExeOnPath 'rg.exe') {
        $env:FZF_DEFAULT_COMMAND = 'rg --files --hidden --glob !.git'
        $env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
    } elseif (Test-WsExeOnPath 'fd.exe') {
        $env:FZF_DEFAULT_COMMAND = 'fd --type f --strip-cwd-prefix --hidden --follow --exclude .git'
        $env:FZF_CTRL_T_COMMAND = $env:FZF_DEFAULT_COMMAND
    }
}

# Pre-compiled active color theme overrides (<1ms disk cache load)
$themeEnvCache = Join-Path $psCacheDir 'theme_env.ps1'
$wsConfigDir = Join-Path $HOME '.config\windows-settings'
$themeSlugFile = Join-Path $wsConfigDir 'theme'
$script:LoadedThemeMtimeTicks = 0L

if ([System.IO.File]::Exists($themeEnvCache)) {
    . $themeEnvCache
    if ([System.IO.File]::Exists($themeSlugFile)) {
        $script:LoadedThemeMtimeTicks = [System.IO.File]::GetLastWriteTimeUtc($themeSlugFile).Ticks
    }
}

# Local machine untracked environment drop-in hooks (~/.config/windows-settings/env.d/*.ps1)
$localEnvDropIn = Join-Path $wsConfigDir 'env.d'
if ([System.IO.Directory]::Exists($localEnvDropIn)) {
    foreach ($dropFile in [System.IO.Directory]::GetFiles($localEnvDropIn, '*.ps1')) {
        . $dropFile
    }
}

# -------------------------------------------------------------
# Internal Helper: Fast User Binary Script Resolution
# -------------------------------------------------------------
function Resolve-WsBinScript([string]$ScriptName) {
    $repoCand = Join-Path (Split-Path -Parent $PSScriptRoot) "bin\$ScriptName.ps1"
    if ([System.IO.File]::Exists($repoCand)) { return $repoCand }
    $extCmd = Get-Command "$ScriptName.ps1" -CommandType ExternalScript -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($extCmd) { return $extCmd.Source }
    $homeRepoCand = Join-Path $HOME "windows-settings\bin\$ScriptName.ps1"
    if ([System.IO.File]::Exists($homeRepoCand)) { return $homeRepoCand }
    return ''
}

function Sync-PSReadLineThemePalette {
    if ($null -eq (Get-Module -Name 'PSReadLine')) { return }
    $cBase0   = if ($env:_HS_ESC_BASE0)   { $env:_HS_ESC_BASE0 }   else { "`e[38;2;131;148;150m" }
    $cBase01  = if ($env:_HS_ESC_BASE01)  { $env:_HS_ESC_BASE01 }  else { "`e[38;2;88;110;117m" }
    $cBase02B = if ($env:_HS_ESC_BG_BASE02) { $env:_HS_ESC_BG_BASE02 } else { "`e[48;2;7;54;66m" }
    $cGreen   = if ($env:_HS_ESC_GREEN)   { $env:_HS_ESC_GREEN }   else { "`e[38;2;133;153;0m" }
    $cYellow  = if ($env:_HS_ESC_YELLOW)  { $env:_HS_ESC_YELLOW }  else { "`e[38;2;181;137;0m" }
    $cCyan    = if ($env:_HS_ESC_CYAN)    { $env:_HS_ESC_CYAN }    else { "`e[38;2;42;161;152m" }
    $cMagenta = if ($env:_HS_ESC_MAGENTA) { $env:_HS_ESC_MAGENTA } else { "`e[38;2;211;54;130m" }
    $cBlue    = if ($env:_HS_ESC_BLUE)    { $env:_HS_ESC_BLUE }    else { "`e[38;2;38;139;210m" }
    $cRed     = if ($env:_HS_ESC_RED)     { $env:_HS_ESC_RED }     else { "`e[38;2;220;50;47m" }

    Set-PSReadLineOption -Colors @{
        Default                 = $cBase0
        Command                 = $cGreen
        Parameter               = $cBase0
        Operator                = $cBase0
        Variable                = $cBase0
        String                  = $cCyan
        Number                  = $cMagenta
        Type                    = $cGreen
        Comment                 = $cBase01
        Keyword                 = $cYellow
        Member                  = $cBase0
        Emphasis                = $cBlue
        Error                   = $cRed
        Selection               = $cBase02B
        InlinePrediction        = $cBase01
        ListPrediction          = $cBase01
        ListPredictionSelected  = $cBase02B
        ListPredictionTooltip   = $cBase01
    } -ErrorAction SilentlyContinue
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
# 3. Prompt Engine (Oh My Posh Compiled Cache + Async PR Badge)
# -------------------------------------------------------------
$ompInit = Join-Path $psCacheDir 'omp_init.ps1'
$themePath = Join-Path $HOME '.poshthemes\p10k_single_line.omp.json'
$script:LoadedOmpMtimeTicks = 0L
$script:OmpCacheDirs = $null

function Sync-OhMyPoshPromptCache {
    $oldSessionId = $env:POSH_SESSION_ID
    if ($oldSessionId) {
        if ($null -eq $script:OmpCacheDirs) {
            $dirs = [System.Collections.Generic.List[string]]::new()
            if ($env:LOCALAPPDATA) {
                $d1 = Join-Path $env:LOCALAPPDATA 'oh-my-posh'
                if ([System.IO.Directory]::Exists($d1)) { $dirs.Add($d1) }
                $pkgRoot = Join-Path $env:LOCALAPPDATA 'Packages'
                if ([System.IO.Directory]::Exists($pkgRoot)) {
                    foreach ($pkgDir in [System.IO.Directory]::GetDirectories($pkgRoot, 'ohmyposh.cli_*')) {
                        $d2 = Join-Path $pkgDir 'LocalCache\Local\oh-my-posh'
                        if ([System.IO.Directory]::Exists($d2)) { $dirs.Add($d2) }
                    }
                }
            }
            $d3 = Join-Path $HOME '.cache\oh-my-posh'
            if ([System.IO.Directory]::Exists($d3)) { $dirs.Add($d3) }
            $script:OmpCacheDirs = $dirs.ToArray()
        }
        foreach ($cDir in $script:OmpCacheDirs) {
            $staleCache = Join-Path $cDir "pwsh.$oldSessionId.omp.cache"
            if ([System.IO.File]::Exists($staleCache)) {
                try { [System.IO.File]::Delete($staleCache) } catch { $null = $_ }
            }
        }
    }

    if ([System.IO.File]::Exists($themePath)) {
        $env:POSH_CONFIG = $themePath
    }
    $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()

    $streamState = Get-Variable -Name _ompStreamingState -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($null -ne $streamState) {
        try {
            if ($null -ne $streamState.StdIn) {
                try {
                    $streamState.StdIn.WriteLine('{"command":"quit"}')
                    $streamState.StdIn.Write([char]0)
                    $streamState.StdIn.Flush()
                    $streamState.StdIn.Close()
                } catch { $null = $_ }
            }
            if ($null -ne $streamState.ServeProcess -and -not $streamState.ServeProcess.HasExited) {
                try { $streamState.ServeProcess.Kill() } catch { $null = $_ }
            }
            $streamState.ServeProcess = $null
            $streamState.StdIn = $null
            $streamState.FailureCount = 0
            $streamState.CycleStarted = $false
            $streamState.Prompt = ''
            $streamState.Transient = ''
            $streamState.Dirty = $false
            $streamState.State = 'NEW'
        } catch {
            $null = $_
        }
    }
}

if ([System.IO.File]::Exists($themePath)) {
    $env:POSH_CONFIG = $themePath
    $script:LoadedOmpMtimeTicks = [System.IO.File]::GetLastWriteTimeUtc($themePath).Ticks
}
if (-not $env:POSH_SESSION_ID) {
    $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
}

function Initialize-WsOhMyPosh {
    $global:_wsOmpInitialized = $true
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) {
        $env:POSH_DISABLE_STREAMING = '1'
    }
    if ($null -eq (Get-Module -Name 'oh-my-posh-core')) {
        function global:prompt {
            "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
        }
        if ([System.IO.File]::Exists($ompInit) -and ([System.IO.FileInfo]::new($ompInit)).Length -gt 0) {
            . $ompInit
        } elseif (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
            if ([System.IO.File]::Exists($themePath)) {
                if (-not [System.IO.Directory]::Exists($psCacheDir)) {
                    New-Item -ItemType Directory -Force -Path $psCacheDir | Out-Null
                }
                oh-my-posh init pwsh --config $themePath --print | Out-File -FilePath $ompInit -Encoding utf8 -Force
                if ([System.IO.File]::Exists($ompInit) -and ([System.IO.FileInfo]::new($ompInit)).Length -gt 0) {
                    . $ompInit
                }
            } else {
                oh-my-posh init pwsh | Invoke-Expression
            }
        }
        if ([System.IO.File]::Exists($themePath)) {
            $env:POSH_CONFIG = $themePath
            $script:LoadedOmpMtimeTicks = [System.IO.File]::GetLastWriteTimeUtc($themePath).Ticks
        }
        $env:POSH_SESSION_ID = [guid]::NewGuid().ToString()
    }

    $ompPromptCmd = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
    if ($ompPromptCmd -and $ompPromptCmd.ScriptBlock.ToString() -notmatch 'Sync-PromptDynamicState') {
        $global:_wsOriginalOmpPrompt = $ompPromptCmd.ScriptBlock
    }
    function global:prompt {
        if (-not $global:_wsOmpInitialized) {
            $null = Initialize-WsOhMyPosh
        }
        if (-not $script:_wsPSReadLineConfigured) {
            $null = Initialize-WsPSReadLine
        }
        $null = Sync-PromptDynamicState
        if ($global:_wsOriginalOmpPrompt) {
            & $global:_wsOriginalOmpPrompt
        } else {
            "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
        }
    }
}

function Find-GitHeadFast([string]$StartDir) {
    $cur = $StartDir
    while ($cur) {
        $dotGit = Join-Path $cur '.git'
        if ([System.IO.Directory]::Exists($dotGit)) {
            $headFile = Join-Path $dotGit 'HEAD'
            if ([System.IO.File]::Exists($headFile)) {
                return @{ Root = $cur; HeadFile = $headFile }
            }
            return $null
        }
        if ([System.IO.File]::Exists($dotGit)) {
            try {
                $firstLine = [System.IO.File]::ReadAllText($dotGit).Trim()
                if ($firstLine -match '^gitdir:\s*(.+)$') {
                    $gitDir = $Matches[1].Trim()
                    if (-not [System.IO.Path]::IsPathRooted($gitDir)) {
                        $gitDir = [System.IO.Path]::GetFullPath((Join-Path $cur $gitDir))
                    }
                    $headFile = Join-Path $gitDir 'HEAD'
                    if ([System.IO.File]::Exists($headFile)) {
                        return @{ Root = $cur; HeadFile = $headFile }
                    }
                }
            } catch {
                return $null
            }
            return $null
        }
        $parent = [System.IO.Path]::GetDirectoryName($cur)
        if (-not $parent -or $parent -eq $cur) { break }
        $cur = $parent
    }
    return $null
}

function Sync-PromptDynamicState {
    # 1. Cross-pane theme & Oh My Posh config synchronization (<0.05ms stat check)
    $themeChanged = $false
    if ([System.IO.File]::Exists($themeSlugFile)) {
        $ticks = [System.IO.File]::GetLastWriteTimeUtc($themeSlugFile).Ticks
        if ($ticks -ne $script:LoadedThemeMtimeTicks) {
            $script:LoadedThemeMtimeTicks = $ticks
            $themeChanged = $true
        }
    }
    if ([System.IO.File]::Exists($themePath)) {
        $ompTicks = [System.IO.File]::GetLastWriteTimeUtc($themePath).Ticks
        if ($ompTicks -ne $script:LoadedOmpMtimeTicks) {
            $script:LoadedOmpMtimeTicks = $ompTicks
            $themeChanged = $true
        }
    }
    if ($themeChanged) {
        if ([System.IO.File]::Exists($themeEnvCache)) {
            . $themeEnvCache
            Sync-PSReadLineThemePalette
        }
        Sync-OhMyPoshPromptCache
    }

    # 2. Zero-latency cached Git Pull Request OSC 8 prompt badge
    $env:_WS_GIT_PR_LABEL = ''
    $env:_WS_GIT_PR_URL = ''
    try {
        $cwd = (Get-Location).ProviderPath
        $gitInfo = Find-GitHeadFast $cwd
        if (-not $gitInfo) { return }
        $headRaw = [System.IO.File]::ReadAllText($gitInfo.HeadFile).Trim()
        if ($headRaw -notmatch '^ref:\s*refs/heads/(.+)$') { return }
        $branch = $Matches[1].Trim()
        if ($branch -in @('main', 'master', 'trunk')) { return }

        $prCacheDir = Join-Path $HOME '.cache\git-pr-prompt'
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("$($gitInfo.Root)|$branch")
        $hashBytes = [System.Security.Cryptography.SHA256]::HashData($bytes)
        $key = [System.BitConverter]::ToString($hashBytes, 0, 8).Replace('-', '').ToLowerInvariant()
        $stateFile = Join-Path $prCacheDir "$key.state"
        $lockFile = Join-Path $prCacheDir "$key.lock"

        $needsRefresh = $true
        if ([System.IO.File]::Exists($stateFile)) {
            $lines = [System.IO.File]::ReadAllLines($stateFile)
            if ($lines.Count -ge 2 -and $lines[0] -and $lines[1]) {
                $env:_WS_GIT_PR_LABEL = $lines[0].Trim()
                $env:_WS_GIT_PR_URL = $lines[1].Trim()
            }
            $ageSec = ([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($stateFile)).TotalSeconds
            if ($ageSec -lt 60) { $needsRefresh = $false }
        }
        if ($needsRefresh -and [System.IO.File]::Exists($lockFile)) {
            $lockAge = ([DateTime]::UtcNow - [System.IO.File]::GetLastWriteTimeUtc($lockFile)).TotalSeconds
            if ($lockAge -lt 60) { $needsRefresh = $false }
        }

        if ($needsRefresh -and $env:WS_DISABLE_ASYNC_PR -ne '1') {
            if (-not [System.IO.Directory]::Exists($prCacheDir)) {
                [System.IO.Directory]::CreateDirectory($prCacheDir) | Out-Null
            }
            [System.IO.File]::WriteAllText($lockFile, '')
            $pwshExe = (Get-Process -Id $PID).Path
            if ($pwshExe) {
                $bgScript = @"
Set-Location -LiteralPath '$($gitInfo.Root.Replace("'", "''"))'
`$label = ''
`$url = ''
if (Get-Command gh -ErrorAction SilentlyContinue) {
    `$json = gh pr view --json number,url,state 2>`$null
    if (`$LASTEXITCODE -eq 0 -and `$json) {
        `$obj = `$json | ConvertFrom-Json
        if (`$obj.number -and `$obj.url -and `$obj.state -eq 'OPEN') {
            `$label = "@`$(`$obj.number)"
            `$url = [string]`$obj.url
        }
    }
}
[System.IO.File]::WriteAllText('$($stateFile.Replace("'", "''"))', "`$label``n`$url``n")
Remove-Item -LiteralPath '$($lockFile.Replace("'", "''"))' -Force -ErrorAction SilentlyContinue
"@
                $psi = [System.Diagnostics.ProcessStartInfo]::new()
                $psi.FileName = $pwshExe
                $psi.ArgumentList.Add('-NoLogo')
                $psi.ArgumentList.Add('-NoProfile')
                $psi.ArgumentList.Add('-NonInteractive')
                $psi.ArgumentList.Add('-Command')
                $psi.ArgumentList.Add($bgScript)
                $psi.CreateNoWindow = $true
                $psi.UseShellExecute = $false
                [void][System.Diagnostics.Process]::Start($psi)
            }
        }
    } catch {
        $null = $_
    }
}

$existingPromptCmd = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
if ($existingPromptCmd -and ($null -ne (Get-Module -Name 'oh-my-posh-core')) -and $existingPromptCmd.ScriptBlock.ToString() -notmatch 'Sync-PromptDynamicState') {
    $global:_wsOriginalOmpPrompt = $existingPromptCmd.ScriptBlock
    $global:_wsOmpInitialized = $true
} elseif ($null -eq (Get-Module -Name 'oh-my-posh-core')) {
    $global:_wsOmpInitialized = $false
}
# -------------------------------------------------------------
# 4. PSReadLine & Predictive IntelliSense (Solarized Dark / Active Theme)
# -------------------------------------------------------------
$script:_wsPSReadLineConfigured = $false
function Initialize-WsPSReadLine {
    if ($script:_wsPSReadLineConfigured) { return }
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected) { return }
    $script:_wsPSReadLineConfigured = $true
    try {
        if ($null -eq (Get-Module -Name 'PSReadLine')) {
            Import-Module PSReadLine -ErrorAction SilentlyContinue
        }
        Sync-PSReadLineThemePalette

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
}

if ($null -ne (Get-Module -Name 'PSReadLine')) {
    Initialize-WsPSReadLine
}

function global:prompt {
    if (-not $global:_wsOmpInitialized) {
        $null = Initialize-WsOhMyPosh
    }
    if (-not $script:_wsPSReadLineConfigured) {
        $null = Initialize-WsPSReadLine
    }
    $null = Sync-PromptDynamicState
    if ($global:_wsOriginalOmpPrompt) {
        & $global:_wsOriginalOmpPrompt
    } else {
        "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) "
    }
}

# -------------------------------------------------------------
# 5. Static Inlined Public Functions & Completers (Zero Disk Scan)
# -------------------------------------------------------------
. "$PSScriptRoot\Git.ps1"
. "$PSScriptRoot\Developer.ps1"
. "$PSScriptRoot\Navigation.ps1"
. "$PSScriptRoot\Utilities.ps1"
. "$PSScriptRoot\Completions.ps1"

# Local machine untracked aliases & functions drop-in hooks (~/.config/windows-settings/{aliases,functions}.d/*.ps1)
foreach ($subDrop in @('aliases.d', 'functions.d')) {
    $dropDir = Join-Path $wsConfigDir $subDrop
    if ([System.IO.Directory]::Exists($dropDir)) {
        foreach ($dropScript in [System.IO.Directory]::GetFiles($dropDir, '*.ps1')) {
            . $dropScript
        }
    }
}
