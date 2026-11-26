@echo off
setlocal

REM Fast paths (<10ms, zero pwsh spawn)
if /i "%~1"=="state" if not "%~2"=="" if "%~3"=="" goto :fast_state
if /i "%~1"=="_internal" if /i "%~2"=="agy-hook" if not "%~3"=="" if "%~4"=="" goto :agy_hook
if /i "%~1"=="_internal" if /i "%~2"=="toggle-modal" if not "%~3"=="" if "%~4"=="" if defined ZELLIJ if not "%WS_IDE_TOGGLE_FROM_BATCH%"=="1" goto :toggle_modal_dispatch
if /i "%~1"=="_internal" if /i "%~2"=="run-modal" if not "%~3"=="" goto :run_modal_dispatch
if /i "%~1"=="quit" if "%~2"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_safe
if /i "%~1"=="quit" if /i "%~2"=="--force" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="quit" if /i "%~2"=="-f" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="monitor" if "%~2"=="" if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" if not "%IDE_MONITOR_ONCE%"=="1" goto :direct_monitor
goto :run_pwsh

:fast_state
if /i "%~2"=="-h" goto :run_pwsh
if /i "%~2"=="--help" goto :run_pwsh
if /i "%~2"=="-?" goto :run_pwsh
if defined WS_AGENT_STATE_STDIN goto :run_pwsh
if /i "%~2"=="idle" (
    set "STATE_OSC=osc-agy-idle.bin"
    set "MAPPED_STATE=idle"
    goto :fast_state_emit
)
if /i "%~2"=="running" (
    set "STATE_OSC=osc-agy-working.bin"
    set "MAPPED_STATE=running"
    goto :fast_state_emit
)
if /i "%~2"=="done" goto :fast_state_done
goto :run_pwsh

:fast_state_done
if not defined ZELLIJ_SESSION_NAME if not defined IDE_SESSION exit /b 0
timeout /t 0 >nul 2>nul
if errorlevel 1 (
    setlocal enabledelayedexpansion
    set "DONE_IN="
    set /p DONE_IN=
    if defined DONE_IN (
        set "WS_AGENT_STATE_STDIN=!DONE_IN!"
        call :exec_pwsh state done <nul
        exit /b !ERRORLEVEL!
    )
    endlocal
)
set "STATE_OSC=osc-agy-done.bin"
set "MAPPED_STATE=done"
goto :fast_state_emit

:fast_state_emit
if not defined ZELLIJ_SESSION_NAME if not defined IDE_SESSION exit /b 0
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
set "OSC_FILE=%STATE_DIR%\%STATE_OSC%"
if not exist "%OSC_FILE%" call :exec_pwsh _internal write-keys-cache >nul 2>nul <nul
if not exist "%OSC_FILE%" goto :run_pwsh
if not "%WS_AGY_HOOK_NO_TTY%"=="1" type "%OSC_FILE%" >\\.\CONOUT$ 2>nul
set "TARGET_SESS=%ZELLIJ_SESSION_NAME%"
if not defined TARGET_SESS set "TARGET_SESS=%IDE_SESSION%"
if defined TARGET_SESS (
    if exist "%STATE_DIR%\%TARGET_SESS%.json" >"%STATE_DIR%\%TARGET_SESS%.state" echo(%MAPPED_STATE%
)
exit /b 0

:agy_hook
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if /i "%~3"=="SessionStart" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-idle.bin"
    set "MAPPED_STATE=idle"
    set "JSON_REPLY={}"
    goto :agy_hook_emit
)
if /i "%~3"=="PreInvocation" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-working.bin"
    set "MAPPED_STATE=running"
    set "JSON_REPLY={}"
    goto :agy_hook_emit
)
if /i "%~3"=="PostToolUse" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-working.bin"
    set "MAPPED_STATE=running"
    set "JSON_REPLY={}"
    goto :agy_hook_emit
)
if /i "%~3"=="PreToolUse" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-approval.bin"
    set "MAPPED_STATE=approval"
    set "JSON_REPLY={"decision":"allow"}"
    goto :agy_hook_emit
)
if /i "%~3"=="Stop" goto :agy_hook_stop
goto :run_pwsh

:agy_hook_stop
if defined WS_HOOK_STDIN goto :run_pwsh
if not exist "%STATE_DIR%\osc-agy-done.bin" call :exec_pwsh _internal write-keys-cache >nul 2>nul <nul
if not exist "%STATE_DIR%\osc-agy-done.bin" goto :run_pwsh
set "OSC_NAME=osc-agy-done.bin"
set "MAPPED_STATE=done"
timeout /t 0 >nul 2>nul
if errorlevel 1 (
    setlocal enabledelayedexpansion
    set "HOOK_IN="
    set /p HOOK_IN=
    set "NEED_PWSH=0"
    if defined HOOK_IN (
        if not "!HOOK_IN:USER_CANCELED=!"=="!HOOK_IN!" (
            set "OSC_NAME=osc-agy-clear.bin"
            set "MAPPED_STATE=idle"
        ) else (
            if /i not "!HOOK_IN:error=!"=="!HOOK_IN!" set "NEED_PWSH=1"
            if /i not "!HOOK_IN:fail=!"=="!HOOK_IN!" set "NEED_PWSH=1"
            if /i not "!HOOK_IN:abort=!"=="!HOOK_IN!" set "NEED_PWSH=1"
        )
    )
    if "!NEED_PWSH!"=="1" (
        set "WS_HOOK_STDIN=!HOOK_IN!"
        call :exec_pwsh _internal agy-hook Stop <nul
        exit /b !ERRORLEVEL!
    )
    for %%A in ("!OSC_NAME!") do for %%B in ("!MAPPED_STATE!") do (
        endlocal
        set "OSC_NAME=%%~A"
        set "MAPPED_STATE=%%~B"
    )
)
set "OSC_FILE=%STATE_DIR%\%OSC_NAME%"
set "JSON_REPLY={"decision":"allow"}"

:agy_hook_emit
if not exist "%OSC_FILE%" call :exec_pwsh _internal write-keys-cache >nul 2>nul <nul
if not exist "%OSC_FILE%" goto :run_pwsh
if not "%WS_AGY_HOOK_NO_TTY%"=="1" type "%OSC_FILE%" >\\.\CONOUT$ 2>nul
set "HOOK_SESS=%ZELLIJ_SESSION_NAME%"
if not defined HOOK_SESS set "HOOK_SESS=%IDE_SESSION%"
if defined HOOK_SESS (
    if exist "%STATE_DIR%\%HOOK_SESS%.json" >"%STATE_DIR%\%HOOK_SESS%.state" echo(%MAPPED_STATE%
)
echo(%JSON_REPLY%
exit /b 0

:direct_monitor
call :find_btop
if not defined BTOP_EXE goto :run_pwsh
pushd "%BTOP_DIR%"
"%BTOP_EXE%"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

:toggle_modal_dispatch
if /i "%~3"=="monitor" (
    if "%IDE_FORCE_BUILTIN_MONITOR%"=="1" goto :toggle_modal_fallback
    call :find_btop
    if defined BTOP_EXE (
        call :toggle_modal "monitor" "System Monitor" "5" "5" "90" "90" "monitor" "%BTOP_DIR%"
    ) else (
        call :toggle_modal "monitor" "System Monitor" "5" "5" "90" "90" "monitor" ""
    )
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
if /i "%~3"=="keys" (
    call :init_modal_paths "keys"
    if not exist "%KEYS_CACHE%" call :exec_pwsh _internal write-keys-cache >nul 2>nul <nul
    call :toggle_modal "keys" "Keybindings" "5" "6" "90" "88" "keys" ""
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
if /i "%~3"=="sessions" (
    call :toggle_modal "sessions" "IDE Fleet Switcher" "5" "8" "90" "84" "sessions" ""
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
if /i "%~3"=="new" (
    call :toggle_modal "new" "New Workspace" "15" "20" "70" "48" "new" ""
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
if /i "%~3"=="dir" (
    call :toggle_modal "dir" "Open Directory" "6" "8" "88" "84" "dir" ""
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
if /i "%~3"=="agent" (
    call :toggle_modal "agent" "AI Agent" "22" "24" "56" "40" "agent" ""
    if errorlevel 1 goto :toggle_modal_fallback
    exit /b 0
)
goto :toggle_modal_fallback

:toggle_modal_fallback
if "%WS_IDE_TOGGLE_FROM_PWSH%"=="1" exit /b 1
set "WS_IDE_TOGGLE_FROM_BATCH=1"
goto :run_pwsh

:run_modal_dispatch
if /i "%~3"=="monitor" goto :run_modal_monitor
if /i "%~3"=="keys" goto :run_modal_keys
if /i "%~3"=="sessions" goto :run_modal_sessions
if /i "%~3"=="new" goto :run_modal_new
if /i "%~3"=="dir" goto :run_modal_dir
if /i "%~3"=="agent" goto :run_modal_agent
goto :run_pwsh

:run_modal_monitor
call :init_modal_paths "monitor"
if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" call :find_btop
if defined BTOP_EXE (
    pushd "%BTOP_DIR%"
    9>"%MODAL_LOCK_FILE%" "%BTOP_EXE%"
    popd
) else (
    set "IDE_MODAL_SIZED=1"
    9>"%MODAL_LOCK_FILE%" call :exec_pwsh monitor
)
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_modal_keys
call :init_modal_paths "keys"
set "IDE_MODAL_SIZED=1"
set "USE_STATIC_KEYS=0"
if /i not "%IDE_KEYS_STYLE%"=="compact" (
    call :detect_term_dims
    if defined TERM_COLS if defined TERM_ROWS (
        if %TERM_COLS% GEQ 104 if %TERM_ROWS% GEQ 30 set "USE_STATIC_KEYS=1"
    )
)
if /i "%IDE_KEYS_STYLE%"=="spacious" set "USE_STATIC_KEYS=1"
if /i "%IDE_KEYS_STYLE%"=="wide" set "USE_STATIC_KEYS=1"
if "%USE_STATIC_KEYS%"=="1" (
    if not exist "%KEYS_CACHE%" call :exec_pwsh _internal write-keys-cache >nul 2>nul <nul
    if exist "%KEYS_CACHE%" (
        9>"%MODAL_LOCK_FILE%" (
            type "%KEYS_CACHE%"
            pause >nul
        )
        del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
        exit /b 0
    )
)
9>"%MODAL_LOCK_FILE%" call :exec_pwsh keys
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_modal_sessions
call :init_modal_paths "sessions"
set "IDE_MODAL_SIZED=1"
set "IDE_SESSIONS_MODAL=1"
9>"%MODAL_LOCK_FILE%" call :exec_pwsh switch
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_modal_new
call :init_modal_paths "new"
set "IDE_MODAL_SIZED=1"
9>"%MODAL_LOCK_FILE%" call :exec_pwsh new
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_modal_dir
call :init_modal_paths "dir"
set "IDE_MODAL_SIZED=1"
9>"%MODAL_LOCK_FILE%" call :exec_pwsh dir
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_modal_agent
call :init_modal_paths "agent"
set "IDE_MODAL_SIZED=1"
9>"%MODAL_LOCK_FILE%" call :exec_pwsh agent
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:fast_quit_safe
set "SESS=%ZELLIJ_SESSION_NAME: =-%"
set "SESS=%SESS:.=-%"
set "SESS=%SESS::=-%"
if exist "\\.\pipe\nvim-ide-%SESS%" goto :run_pwsh
goto :fast_quit_exec

:fast_quit_force
set "SESS=%ZELLIJ_SESSION_NAME: =-%"
set "SESS=%SESS:.=-%"
set "SESS=%SESS::=-%"

:fast_quit_exec
call :find_zellij
if not defined ZELLIJ_EXE goto :run_pwsh
"%ZELLIJ_EXE%" delete-session --force "%SESS%" >nul 2>nul
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
del /f /q "%STATE_DIR%\%SESS%.*" "%STATE_DIR%\launch-%SESS%-*.ps1" "%STATE_DIR%\monitor-%SESS%.*" "%STATE_DIR%\keys-%SESS%.*" "%STATE_DIR%\sessions-%SESS%.*" "%STATE_DIR%\new-%SESS%.*" "%STATE_DIR%\dir-%SESS%.*" "%STATE_DIR%\agent-%SESS%.*" "%STATE_DIR%\modal-*-%SESS%.json" >nul 2>nul
echo Closed IDE session '%SESS%'.
exit /b 0

:toggle_modal
call :find_zellij
if not defined ZELLIJ_EXE exit /b 1
call :init_modal_paths "%~1"

REM Exclusive file lock test: if run-modal currently holds MODAL_LOCK_FILE open,
REM redirecting fd 9 fails immediately in <1ms without spawning tasklist/CIM/pwsh.
(9>"%MODAL_LOCK_FILE%" rem.) 2>nul || (
    set "ACTIVE_PANE="
    if exist "%MODAL_PANE_FILE%" set /p ACTIVE_PANE=<"%MODAL_PANE_FILE%"
    if defined ACTIVE_PANE (
        "%ZELLIJ_EXE%" action close-pane --pane-id %ACTIVE_PANE% >nul 2>nul
        exit /b 0
    )
    exit /b 1
)

set "IDE_ORIGIN_SESSION=%SESS%"
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
set "MODAL_OUT_TMP=%STATE_DIR%\modal-out-%~1-%SESS%-%RANDOM%.tmp"
if "%~8"=="" (
    "%ZELLIJ_EXE%" run --floating --pinned true --close-on-exit -x "%~3%%" -y "%~4%%" --width "%~5%%" --height "%~6%%" --name "%~2" -- cmd.exe /d /c "%~f0" _internal run-modal %~7 >"%MODAL_OUT_TMP%" 2>nul
) else (
    "%ZELLIJ_EXE%" run --floating --pinned true --close-on-exit -x "%~3%%" -y "%~4%%" --width "%~5%%" --height "%~6%%" --cwd "%~8" --name "%~2" -- cmd.exe /d /c "%~f0" _internal run-modal %~7 >"%MODAL_OUT_TMP%" 2>nul
)
set "NEW_PANE="
if exist "%MODAL_OUT_TMP%" (
    set /p NEW_PANE=<"%MODAL_OUT_TMP%"
    del /f /q "%MODAL_OUT_TMP%" >nul 2>nul
)
if not defined NEW_PANE exit /b 1
>"%MODAL_PANE_FILE%" echo(%NEW_PANE%
exit /b 0

:init_modal_paths
set "SESS=%ZELLIJ_SESSION_NAME%"
if not defined SESS set "SESS=%IDE_SESSION%"
if not defined SESS set "SESS=default"
set "SESS=%SESS: =-%"
set "SESS=%SESS:.=-%"
set "SESS=%SESS::=-%"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>nul
set "MODAL_PANE_FILE=%STATE_DIR%\%~1-%SESS%.pane"
set "MODAL_LOCK_FILE=%STATE_DIR%\%~1-%SESS%.lock"
set "KEYS_CACHE=%STATE_DIR%\keys-cheatsheet.ans"
exit /b 0

:detect_term_dims
set "TERM_COLS=%COLUMNS%"
set "TERM_ROWS=%LINES%"
if defined TERM_COLS if defined TERM_ROWS exit /b 0
set "M_IDX=0"
setlocal enabledelayedexpansion
for /f "tokens=2 delims=:" %%V in ('mode con 2^>nul') do (
    set "VAL=%%V"
    set "VAL=!VAL: =!"
    if not "!VAL!"=="" (
        set /a "CHECK_NUM=!VAL!+0" 2>nul
        if "!VAL!"=="!CHECK_NUM!" if !CHECK_NUM! GTR 0 (
            set /a M_IDX+=1
            if !M_IDX!==1 set "FOUND_ROWS=!CHECK_NUM!"
            if !M_IDX!==2 set "FOUND_COLS=!CHECK_NUM!"
        )
    )
)
for %%R in ("!FOUND_ROWS!") do for %%C in ("!FOUND_COLS!") do (
    endlocal
    if not defined TERM_ROWS set "TERM_ROWS=%%~R"
    if not defined TERM_COLS set "TERM_COLS=%%~C"
)
exit /b 0

:find_zellij
set "ZELLIJ_EXE="
for %%Z in (zellij.exe) do set "ZELLIJ_EXE=%%~$PATH:Z"
if defined ZELLIJ_EXE (
    echo "%ZELLIJ_EXE%" | findstr /i "\\mise\\shims\\" >nul
    if not errorlevel 1 set "ZELLIJ_EXE="
)
if not defined ZELLIJ_EXE if exist "%LOCALAPPDATA%\mise\installs\zellij" (
    for /f "delims=" %%F in ('dir /b /s /o-n "%LOCALAPPDATA%\mise\installs\zellij\zellij.exe" 2^>nul') do (
        set "ZELLIJ_EXE=%%F"
        goto :found_zellij
    )
)
if not defined ZELLIJ_EXE (
    for %%Z in (zellij.exe) do set "ZELLIJ_EXE=%%~$PATH:Z"
)
:found_zellij
exit /b 0

:find_btop
set "BTOP_EXE="
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages" (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\aristocratos.btop4win*") do (
        if exist "%%~fD\btop4win\btop4win.exe" set "BTOP_EXE=%%~fD\btop4win\btop4win.exe"
        if not defined BTOP_EXE if exist "%%~fD\btop4win.exe" set "BTOP_EXE=%%~fD\btop4win.exe"
    )
)
if not defined BTOP_EXE (
    for %%P in (btop4win.exe btop.exe) do (
        if not defined BTOP_EXE if not "%%~$PATH:P"=="" set "BTOP_EXE=%%~$PATH:P"
    )
)
if not defined BTOP_EXE if exist "%USERPROFILE%\scoop\apps\btop\current\btop.exe" set "BTOP_EXE=%USERPROFILE%\scoop\apps\btop\current\btop.exe"
if not defined BTOP_EXE if exist "%ProgramFiles%\btop4win\btop4win.exe" set "BTOP_EXE=%ProgramFiles%\btop4win\btop4win.exe"
if defined BTOP_EXE (
    for %%I in ("%BTOP_EXE%") do set "BTOP_DIR=%%~dpI"
)
exit /b 0

:exec_pwsh
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0ide.ps1" %*
    exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ide.ps1" %*
exit /b %ERRORLEVEL%

:run_pwsh
call :exec_pwsh %*
exit /b %ERRORLEVEL%
