@echo off
:: Ensure UTF-8 code page (65001) for Unicode & Powerline glyph rendering
chcp 65001 >nul

:: =============================================================
:: Windows Command Prompt (cmd.exe) AutoRun Configuration
:: Solarized Dark TrueColor Environment & Doskey Macros
:: =============================================================

:: -------------------------------------------------------------
:: 1. TrueColor & Terminal Environment Variables
:: -------------------------------------------------------------
set "COLORTERM=truecolor"
set "FORCE_HYPERLINK=1"
set "BAT_THEME=Solarized-Dark-TrueColor"
set "BAT_OPTS=--italic-text=always"
if not defined EDITOR set "EDITOR=nvim"
if not defined VISUAL set "VISUAL=%EDITOR%"
if not defined IDE_AI_CLI set "IDE_AI_CLI=agy"
if not defined CC set "CC=gcc"
if not defined CXX set "CXX=g++"
if not defined GOPATH set "GOPATH=%USERPROFILE%\.local\share\go"
if not defined GOCACHE if defined LOCALAPPDATA set "GOCACHE=%LOCALAPPDATA%\go-build"
if not defined ELAN_HOME set "ELAN_HOME=%USERPROFILE%\.local\share\elan"
set "_ZO_ECHO=1"
set "_ZO_RESOLVE_SYMLINKS=1"

:: Calibrated Solarized Dark LS_COLORS (unbolded GNU dircolors across 40 polyglot extensions)
set "LS_COLORS=no=00:fi=00:rs=0:di=34:ow=34;40:ln=36:mh=00:pi=33:so=35:do=35:bd=35:cd=35:or=31:mi=31:su=37;41:sg=30;43:ca=30;41:tw=30;42:st=37;44:ex=32:*.cmd=32:*.exe=32:*.com=32:*.bat=32:*.reg=32:*.app=32:*.bmp=95:*.cgm=95:*.dl=95:*.dvi=95:*.emf=95:*.eps=95:*.gif=95:*.jpeg=95:*.jpg=95:*.JPG=95:*.mng=95:*.pbm=95:*.pcx=95:*.pgm=95:*.png=95:*.ppm=95:*.pps=95:*.ppsx=95:*.ps=95:*.svg=95:*.svgz=95:*.tga=95:*.tif=95:*.tiff=95:*.webp=95:*.xbm=95:*.xcf=95:*.xpm=95:*.xwd=95:*.yuv=95:*.aac=95:*.au=95:*.flac=95:*.mid=95:*.midi=95:*.mka=95:*.mp3=95:*.mpa=95:*.ogg=95:*.ra=95:*.wav=95:*.anx=95:*.asf=95:*.avi=95:*.axv=95:*.flc=95:*.fli=95:*.flv=95:*.gl=95:*.m2v=95:*.m4v=95:*.mkv=95:*.mov=95:*.mp4=95:*.mp4v=95:*.mpeg=95:*.mpg=95:*.nuv=95:*.ogm=95:*.ogv=95:*.ogx=95:*.qt=95:*.rm=95:*.rmvb=95:*.swf=95:*.vob=95:*.webm=95:*.wmv=95:*.7z=91:*.apk=91:*.arj=91:*.bin=91:*.bz=91:*.bz2=91:*.cab=91:*.deb=91:*.dmg=91:*.gem=91:*.gz=91:*.iso=91:*.jar=91:*.msi=91:*.rar=91:*.rpm=91:*.tar=91:*.tbz=91:*.tbz2=91:*.tgz=91:*.tx=91:*.war=91:*.xpi=91:*.xz=91:*.z=91:*.Z=91:*.zip=91:*.zst=91:*.txt=00:*.org=00:*.md=00:*.mkd=00:*.markdown=00:*.doc=00:*.docx=00:*.rtf=00:*.dot=00:*.dotx=00:*.xls=00:*.xlsx=00:*.ppt=00:*.pptx=00:*.pdf=00:*.tex=00:*.epub=00:*.c=00:*.C=00:*.cc=00:*.cpp=00:*.cxx=00:*.h=00:*.hh=00:*.hpp=00:*.hxx=00:*.rs=00:*.go=00:*.py=00:*.java=00:*.kt=00:*.kts=00:*.swift=00:*.js=00:*.ts=00:*.sh=00:*.zsh=00:*.bash=00:*.ps1=00:*.psm1=00:*.psd1=00:*.json=00:*.yaml=00:*.yml=00:*.toml=00:*.xml=00:*.html=00:*.css=00:*.sql=00:*.tf=00:*.properties=00:*.proto=00:*.textproto=00:*.pbtxt=00:*.textpb=00:*.prototxt=00:*.zig=00:*.cs=00:*.scala=00:*.sc=00:*.rb=00:*.graphql=00:*.graphqls=00:*.gql=00:*.bzl=00:*.bazel=00:*.rego=00:*.lua=00:*.mk=00:*.ex=00:*.exs=00:*.hs=00:*.lean=00:*.ml=00:*.mli=00:*.clj=00:*.cljs=00:*.cljc=00:*.edn=00:*.diff=00:*.patch=00:*.gpg=35:*.pgp=35:*.asc=35:*.3des=35:*.aes=35:*.enc=35:*.key=35:*.pem=35:*.crt=35:*.cer=35:*.bak=90:*.BAK=90:*.old=90:*.OLD=90:*.orig=90:*.ORIG=90:*.swp=90:*.swo=90:*~=90:*#=90:*.log=90:"

:: 24-bit TrueColor Solarized Dark EZA_COLORS, FZF_DEFAULT_OPTS & JQ_COLORS
set "EZA_COLORS=di=38;2;38;139;210:ex=38;2;133;153;0:fi=38;2;131;148;150:pi=38;2;181;137;0:so=38;2;211;54;130:bd=38;2;211;54;130:cd=38;2;211;54;130:ln=38;2;42;161;152:or=38;2;220;50;47:xx=38;2;88;110;117:da=38;2;131;148;150:hd=4;38;2;147;161;161:lp=38;2;131;148;150:cc=38;2;203;75;22:bO=38;2;220;50;47:in=38;2;88;110;117:bl=38;2;88;110;117:oc=38;2;131;148;150:ur=38;2;131;148;150:uw=38;2;131;148;150:ux=38;2;131;148;150:ue=38;2;131;148;150:gr=38;2;131;148;150:gw=38;2;131;148;150:gx=38;2;131;148;150:tr=38;2;131;148;150:tw=38;2;131;148;150:tx=38;2;131;148;150:su=38;2;131;148;150:sf=38;2;131;148;150:xa=38;2;131;148;150:sn=38;2;131;148;150:nb=38;2;88;110;117:nk=38;2;131;148;150:nm=38;2;181;137;0:ng=38;2;203;75;22:nt=38;2;220;50;47:sb=38;2;131;148;150:ub=38;2;88;110;117:uk=38;2;131;148;150:um=38;2;181;137;0:ug=38;2;203;75;22:ut=38;2;220;50;47:df=38;2;131;148;150:ds=38;2;131;148;150:uu=38;2;131;148;150:uR=38;2;220;50;47:un=38;2;131;148;150:gu=38;2;131;148;150:gR=38;2;220;50;47:gn=38;2;131;148;150:lc=38;2;131;148;150:lm=38;2;181;137;0:ga=38;2;133;153;0:gm=38;2;181;137;0:gd=38;2;220;50;47:gv=38;2;131;148;150:gt=38;2;131;148;150:gi=38;2;88;110;117:gc=38;2;220;50;47:Gm=38;2;133;153;0:Go=38;2;38;139;210:Gc=38;2;133;153;0:Gd=38;2;181;137;0:sp=38;2;203;75;22:mp=38;2;38;139;210:im=38;2;108;113;196:vi=38;2;108;113;196:mu=38;2;108;113;196:lo=38;2;108;113;196:cr=38;2;211;54;130:do=38;2;131;148;150:co=38;2;203;75;22:tm=38;2;88;110;117:cm=38;2;88;110;117:bu=38;2;133;153;0:sc=38;2;131;148;150:Sn=38;2;88;110;117:Su=38;2;131;148;150:Sr=38;2;131;148;150:St=38;2;131;148;150:Sl=38;2;131;148;150:ff=38;2;131;148;150"
set "EXA_COLORS=%EZA_COLORS%"
set "FZF_DEFAULT_OPTS=--color=bg+:#073642,bg:#002B36,spinner:#859900,hl:#586E75 --color=fg:#839496,header:#586E75,info:#B58900,pointer:#859900 --color=marker:#859900,fg+:#93A1A1,prompt:#B58900,hl+:#268BD2 --color=border:#586E75,separator:#586E75,label:#586E75,gutter:#002B36 --layout=reverse --border=rounded --info=inline"
set "_ZO_FZF_OPTS=%FZF_DEFAULT_OPTS% --height=50% --preview=""eza -la --icons=auto --color=always --group-directories-first {2..} 2>nul || ls -la {2..}"" --preview-window=right:50%:wrap"
set "JQ_COLORS=38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;211;54;130:38;2;42;161;152:38;2;131;148;150:38;2;131;148;150:38;2;133;153;0"

:: -------------------------------------------------------------
:: 2. Toolchain PATH Initializations (Zero-Process Substring Checks)
:: -------------------------------------------------------------
call :ws_insert_git_mingw
call :ws_prepend_path "%LOCALAPPDATA%\Microsoft\WinGet\Links"
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do (
    call :ws_prepend_path "%%~fD\mingw64\bin"
)
call :ws_append_path "%GOPATH%\bin"
call :ws_append_path "%USERPROFILE%\.local\share\go\bin"
call :ws_append_path "%USERPROFILE%\go\bin"
call :ws_append_path "%ELAN_HOME%\bin"
call :ws_append_path "%USERPROFILE%\.local\share\elan\bin"
call :ws_append_path "%USERPROFILE%\.elan\bin"
call :ws_append_path "%USERPROFILE%\.cargo\bin"
call :ws_prepend_path "%LOCALAPPDATA%\mise\shims"
if exist "%LOCALAPPDATA%\cmd\mise_paths.cmd" call "%LOCALAPPDATA%\cmd\mise_paths.cmd"

:: -------------------------------------------------------------
:: 3. Doskey Alias Suite (Single-Process Macrofile Load)
:: -------------------------------------------------------------
:: Clear any legacy `cat` macro so coreutils `cat` runs raw (`b` invokes `bat`)
doskey cat=
if exist "%~dp0macros.doskey" doskey /macrofile="%~dp0macros.doskey"

:: -------------------------------------------------------------
:: 4. Solarized Dark TrueColor Powerline Shelf Prompt & Theme Hook
:: -------------------------------------------------------------
:: Authentic Base02 dark teal shelf (#073642) matching Oh My Posh:
:: Base0 Windows icon () + Base01 divider () + Solarized Blue path ( $P) + Base02 wedge cap ()
prompt $E[48;2;7;54;66m$E[38;2;131;148;150m  $E[38;2;88;110;117m$E[38;2;38;139;210m  $P $E[0m$E[38;2;7;54;66m$E[0m$S

if exist "%LOCALAPPDATA%\cmd\theme_env.cmd" call "%LOCALAPPDATA%\cmd\theme_env.cmd"
if exist "%USERPROFILE%\.config\windows-settings\cmd.d" (
    for %%F in ("%USERPROFILE%\.config\windows-settings\cmd.d\*.cmd") do call "%%F"
)
goto :eof

:ws_has_path
setlocal EnableDelayedExpansion
set "_P=;!PATH!;"
set "_T=!_P:*;%~1;=FOUND!"
if "!_T:~0,5!"=="FOUND" (endlocal & exit /b 0)
endlocal & exit /b 1

:ws_insert_git_mingw
if not exist "%ProgramFiles%\Git\mingw64\bin\git.exe" exit /b 0
call :ws_has_path "%ProgramFiles%\Git\mingw64\bin"
if errorlevel 1 call set "PATH=%%PATH:%ProgramFiles%\Git\cmd;=%ProgramFiles%\Git\mingw64\bin;%ProgramFiles%\Git\cmd;%%"
exit /b 0

:ws_prepend_path
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
call :ws_has_path "%~1"
if errorlevel 1 set "PATH=%~1;%PATH%"
exit /b 0

:ws_append_path
if "%~1"=="" exit /b 0
if not exist "%~1" exit /b 0
call :ws_has_path "%~1"
if errorlevel 1 set "PATH=%PATH%;%~1"
exit /b 0
