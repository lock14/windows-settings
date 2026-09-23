@echo off
:: =============================================================
:: Windows Command Prompt (cmd.exe) AutoRun Configuration
:: Solarized Dark TrueColor Environment & Doskey Macros
:: =============================================================

:: -------------------------------------------------------------
:: 1. TrueColor & Terminal Environment Variables
:: -------------------------------------------------------------
set "COLORTERM=truecolor"
set "BAT_THEME=Solarized-Dark-TrueColor"
set "BAT_OPTS=--italic-text=always"
if not defined CC set "CC=gcc"
if not defined CXX set "CXX=g++"

:: Calibrated Solarized Dark LS_COLORS (unbolded GNU dircolors)
set "LS_COLORS=no=00:fi=00:rs=0:di=34:ow=34;40:ln=36:mh=00:pi=33:so=35:do=35:bd=35:cd=35:or=31:mi=31:su=37;41:sg=30;43:ca=30;41:tw=30;42:st=37;44:ex=32:*.cmd=32:*.exe=32:*.com=32:*.bat=32:*.reg=32:*.app=32:*.bmp=95:*.cgm=95:*.dl=95:*.dvi=95:*.emf=95:*.eps=95:*.gif=95:*.jpeg=95:*.jpg=95:*.JPG=95:*.mng=95:*.pbm=95:*.pcx=95:*.pgm=95:*.png=95:*.ppm=95:*.pps=95:*.ppsx=95:*.ps=95:*.svg=95:*.svgz=95:*.tga=95:*.tif=95:*.tiff=95:*.webp=95:*.xbm=95:*.xcf=95:*.xpm=95:*.xwd=95:*.yuv=95:*.aac=95:*.au=95:*.flac=95:*.mid=95:*.midi=95:*.mka=95:*.mp3=95:*.mpa=95:*.ogg=95:*.ra=95:*.wav=95:*.anx=95:*.asf=95:*.avi=95:*.axv=95:*.flc=95:*.fli=95:*.flv=95:*.gl=95:*.m2v=95:*.m4v=95:*.mkv=95:*.mov=95:*.mp4=95:*.mp4v=95:*.mpeg=95:*.mpg=95:*.nuv=95:*.ogm=95:*.ogv=95:*.ogx=95:*.qt=95:*.rm=95:*.rmvb=95:*.swf=95:*.vob=95:*.webm=95:*.wmv=95:*.7z=91:*.apk=91:*.arj=91:*.bin=91:*.bz=91:*.bz2=91:*.cab=91:*.deb=91:*.dmg=91:*.gem=91:*.gz=91:*.iso=91:*.jar=91:*.msi=91:*.rar=91:*.rpm=91:*.tar=91:*.tbz=91:*.tbz2=91:*.tgz=91:*.tx=91:*.war=91:*.xpi=91:*.xz=91:*.z=91:*.Z=91:*.zip=91:*.zst=91:*.txt=00:*.org=00:*.md=00:*.mkd=00:*.markdown=00:*.doc=00:*.docx=00:*.rtf=00:*.dot=00:*.dotx=00:*.xls=00:*.xlsx=00:*.ppt=00:*.pptx=00:*.pdf=00:*.tex=00:*.epub=00:*.c=00:*.C=00:*.cc=00:*.cpp=00:*.cxx=00:*.h=00:*.hh=00:*.hpp=00:*.hxx=00:*.rs=00:*.go=00:*.py=00:*.java=00:*.js=00:*.ts=00:*.sh=00:*.zsh=00:*.bash=00:*.json=00:*.yaml=00:*.yml=00:*.toml=00:*.xml=00:*.html=00:*.css=00:*.sql=00:*.tf=00:*.gpg=35:*.pgp=35:*.asc=35:*.3des=35:*.aes=35:*.enc=35:*.key=35:*.pem=35:*.crt=35:*.cer=35:*.bak=90:*.BAK=90:*.old=90:*.OLD=90:*.orig=90:*.ORIG=90:*.swp=90:*.swo=90:*~=90:*#=90:*.log=90:"

:: 24-bit TrueColor Solarized Dark EZA_COLORS & EXA_COLORS
set "EZA_COLORS=di=38;2;38;139;210:ex=38;2;133;153;0:fi=38;2;131;148;150:pi=38;2;181;137;0:so=38;2;211;54;130:bd=38;2;211;54;130:cd=38;2;211;54;130:ln=38;2;42;161;152:or=38;2;220;50;47:xx=38;2;88;110;117:da=38;2;131;148;150:hd=4;38;2;147;161;161:lp=38;2;131;148;150:cc=38;2;203;75;22:bO=38;2;220;50;47:in=38;2;88;110;117:bl=38;2;88;110;117:oc=38;2;131;148;150:ur=38;2;131;148;150:uw=38;2;131;148;150:ux=38;2;131;148;150:ue=38;2;131;148;150:gr=38;2;131;148;150:gw=38;2;131;148;150:gx=38;2;131;148;150:tr=38;2;131;148;150:tw=38;2;131;148;150:tx=38;2;131;148;150:su=38;2;131;148;150:sf=38;2;131;148;150:xa=38;2;131;148;150:sn=38;2;131;148;150:nb=38;2;88;110;117:nk=38;2;131;148;150:nm=38;2;181;137;0:ng=38;2;203;75;22:nt=38;2;220;50;47:sb=38;2;131;148;150:ub=38;2;88;110;117:uk=38;2;131;148;150:um=38;2;181;137;0:ug=38;2;203;75;22:ut=38;2;220;50;47:df=38;2;131;148;150:ds=38;2;131;148;150:uu=38;2;131;148;150:uR=38;2;220;50;47:un=38;2;131;148;150:gu=38;2;131;148;150:gR=38;2;220;50;47:gn=38;2;131;148;150:lc=38;2;131;148;150:lm=38;2;181;137;0:ga=38;2;133;153;0:gm=38;2;181;137;0:gd=38;2;220;50;47:gv=38;2;131;148;150:gt=38;2;131;148;150:gi=38;2;88;110;117:gc=38;2;220;50;47:Gm=38;2;133;153;0:Go=38;2;38;139;210:Gc=38;2;133;153;0:Gd=38;2;181;137;0:sp=38;2;203;75;22:mp=38;2;38;139;210:im=38;2;108;113;196:vi=38;2;108;113;196:mu=38;2;108;113;196:lo=38;2;108;113;196:cr=38;2;211;54;130:do=38;2;131;148;150:co=38;2;203;75;22:tm=38;2;88;110;117:cm=38;2;88;110;117:bu=38;2;133;153;0:sc=38;2;131;148;150:Sn=38;2;88;110;117:Su=38;2;131;148;150:Sr=38;2;131;148;150:St=38;2;131;148;150:Sl=38;2;131;148;150:ff=38;2;131;148;150"
set "EXA_COLORS=%EZA_COLORS%"

:: -------------------------------------------------------------
:: 2. Toolchain PATH Initializations
:: -------------------------------------------------------------
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links" (
    echo "%PATH%" | find /i "%LOCALAPPDATA%\Microsoft\WinGet\Links" >nul || set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Links;%PATH%"
)
for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\BrechtSanders.WinLibs*") do (
    if exist "%%D\mingw64\bin" (
        echo "%PATH%" | find /i "%%D\mingw64\bin" >nul || set "PATH=%%D\mingw64\bin;%PATH%"
    )
)
if exist "%USERPROFILE%\go\bin" (
    echo "%PATH%" | find /i "%USERPROFILE%\go\bin" >nul || set "PATH=%PATH%;%USERPROFILE%\go\bin"
)
if exist "%USERPROFILE%\.cargo\bin" (
    echo "%PATH%" | find /i "%USERPROFILE%\.cargo\bin" >nul || set "PATH=%PATH%;%USERPROFILE%\.cargo\bin"
)
if exist "%LOCALAPPDATA%\mise\shims" (
    echo "%PATH%" | find /i "%LOCALAPPDATA%\mise\shims" >nul || set "PATH=%LOCALAPPDATA%\mise\shims;%PATH%"
)

:: -------------------------------------------------------------
:: 3. Directory Navigation & Modern Listing Macros (doskey)
:: -------------------------------------------------------------
doskey ls=ls --color=auto $*
doskey ll=ls --color=auto -alF $*
doskey la=ls --color=auto -A $*
doskey l=ls --color=auto -CF $*

doskey e=eza --icons=auto --group-directories-first $*
doskey el=eza -la --icons=auto --git --header --group --time-style=long-iso $*
doskey elm=eza -la --icons=auto --git --header --group --time-style=long-iso --sort=modified $*
doskey et=eza --tree --level=2 --icons=auto $*
doskey lt=eza --tree --level=2 --icons=auto $*
doskey elt=eza -la --tree --level=2 --icons=auto --git --group --time-style=long-iso $*
doskey elx=eza -la --icons=auto --git --header --group --time-style=long-iso -H -i -S --extended $*

doskey cat=bat --theme="Solarized-Dark-TrueColor" $*

:: -------------------------------------------------------------
:: 4. Git Workflow Macros (doskey)
:: -------------------------------------------------------------
doskey gco=git checkout $*
doskey gcb=git checkout -b $*
doskey gcd=git checkout develop $*
doskey ga=git add $*
doskey gaa=git add --all $*
doskey gst=git status $*
doskey gss=git status -s $*
doskey gd=git diff $*
doskey gds=git diff --staged $*
doskey gl=git pull $*
doskey gp=git push $*
doskey gb=git branch $*
doskey gba=git branch -a $*
doskey gbd=git branch -d $*
doskey gbD=git branch -D $*
doskey gsta=git stash push $*
doskey gstp=git stash pop $*
doskey gstl=git stash list $*
doskey glog=git log --oneline --decorate --graph $*
doskey glo=git log --oneline --decorate $*
doskey grb=git rebase $*
doskey grba=git rebase --abort $*
doskey grbc=git rebase --continue $*
doskey grbi=git rebase -i $*
doskey grh=git reset $*
doskey grhh=git reset --hard $*
doskey gsw=git switch $*
doskey gswc=git switch -c $*
doskey gcp=git cherry-pick $*
doskey gcpa=git cherry-pick --abort $*
doskey gcpc=git cherry-pick --continue $*
doskey gcommit=git add -A $t git commit $*
doskey gamend=git add -A $t git commit --amend --no-edit $*
doskey gfetch=git fetch $*
doskey gpush=git push origin HEAD $*
doskey gpull=git pull --rebase origin HEAD $*
doskey gup=git fetch $t git pull --rebase origin HEAD $*

:: -------------------------------------------------------------
:: 5. Developer Shortcuts & Editor Macros (doskey)
:: -------------------------------------------------------------
doskey vi=nvim $*
doskey vim=nvim $*
doskey v=nvim $*
doskey tf=terraform $*

doskey go-testall=go test ./... $*
doskey go-buildall=go build ./... $*
doskey go-lint=golangci-lint run $*
doskey yaml-lint=yamllint $*

doskey go_testall=go test ./... $*
doskey go_buildall=go build ./... $*
doskey go_lint=golangci-lint run $*
doskey yaml_lint=yamllint $*

doskey clear=cls

:: -------------------------------------------------------------
:: 6. Solarized Dark TrueColor Prompt
:: -------------------------------------------------------------
:: Cyan ($E[38;2;42;161;152m) working path + Green ($E[38;2;133;153;0m) chevron + reset ($E[0m)
prompt $E[38;2;42;161;152m$P $E[38;2;133;153;0m$G$E[0m$S
