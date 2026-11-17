@echo off
setlocal

if /i "%~1"=="--agy-hook" if not "%~2"=="" if "%~3"=="" goto :agy_hook
if /i "%~1"=="--quit" if "%~2"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_safe
if /i "%~1"=="-q" if "%~2"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_safe
if /i "%~1"=="--quit" if /i "%~2"=="--force" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="--quit" if /i "%~2"=="-f" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="--force" if /i "%~2"=="--quit" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="-f" if /i "%~2"=="--quit" if "%~3"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="--kill" if "%~2"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="-k" if "%~2"=="" if defined ZELLIJ_SESSION_NAME goto :fast_quit_force
if /i "%~1"=="--run-btop" goto :run_btop
if /i "%~1"=="--run-keys" goto :run_keys
if /i "%~1"=="--run-sessions" goto :run_sessions
if /i "%~1"=="--toggle-monitor" if "%~2"=="" if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" if defined ZELLIJ goto :toggle_monitor
if /i "%~1"=="--toggle-keys" if "%~2"=="" if defined ZELLIJ goto :toggle_keys
if /i "%~1"=="--toggle-sessions" if "%~2"=="" if defined ZELLIJ goto :toggle_sessions
if /i "%~1"=="--monitor" if "%~2"=="" if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" if not "%IDE_MONITOR_ONCE%"=="1" goto :direct_monitor
goto :run_pwsh

:agy_hook
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if /i "%~2"=="SessionStart" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-idle.bin"
    set "MAPPED_STATE=idle"
    set "JSON_REPLY={}"
    goto :agy_hook_emit
)
if /i "%~2"=="PreInvocation" (
    set "OSC_FILE=%STATE_DIR%\osc-agy-working.bin"
    set "MAPPED_STATE=running"
    set "JSON_REPLY={}"
    goto :agy_hook_emit
)
if /i "%~2"=="Stop" goto :agy_hook_stop
goto :run_pwsh

:agy_hook_stop
if not exist "%STATE_DIR%\osc-agy-done.bin" call :exec_pwsh --write-keys-cache >nul 2>nul <nul
if not exist "%STATE_DIR%\osc-agy-done.bin" goto :run_pwsh
setlocal enabledelayedexpansion
set "HOOK_IN="
set /p HOOK_IN=
set "OSC_NAME=osc-agy-done.bin"
set "MAPPED_STATE=done"
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
    call :exec_pwsh --agy-hook Stop <nul
    exit /b !ERRORLEVEL!
)
for %%A in ("!OSC_NAME!") do for %%B in ("!MAPPED_STATE!") do (
    endlocal
    set "OSC_FILE=%STATE_DIR%\%%~A"
    set "MAPPED_STATE=%%~B"
)
set "JSON_REPLY={"decision":"allow"}"

:agy_hook_emit
if not exist "%OSC_FILE%" call :exec_pwsh --write-keys-cache >nul 2>nul <nul
if not exist "%OSC_FILE%" goto :run_pwsh
if not "%WS_AGY_HOOK_NO_TTY%"=="1" type "%OSC_FILE%" >CONOUT$ 2>nul
set "HOOK_SESS=%ZELLIJ_SESSION_NAME%"
if not defined HOOK_SESS set "HOOK_SESS=%IDE_SESSION%"
if defined HOOK_SESS (
    if exist "%STATE_DIR%\%HOOK_SESS%.json" >"%STATE_DIR%\%HOOK_SESS%.state" echo %MAPPED_STATE%
)
echo %JSON_REPLY%
exit /b 0

:direct_monitor
call :find_btop
if not defined BTOP_EXE goto :run_pwsh
pushd "%BTOP_DIR%"
"%BTOP_EXE%"
set "RC=%ERRORLEVEL%"
popd
exit /b %RC%

:run_btop
call :find_btop
if not defined BTOP_EXE goto :run_pwsh_monitor
call :init_modal_paths "monitor"
pushd "%BTOP_DIR%"
9>"%MODAL_LOCK_FILE%" "%BTOP_EXE%"
popd
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_pwsh_monitor
call :init_modal_paths "monitor"
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
call :exec_pwsh --monitor
exit /b %ERRORLEVEL%

:run_keys
call :init_modal_paths "keys"
if not exist "%KEYS_CACHE%" call :exec_pwsh --write-keys-cache >nul 2>nul
if not exist "%KEYS_CACHE%" goto :run_pwsh_keys
9>"%MODAL_LOCK_FILE%" (
    type "%KEYS_CACHE%"
    pause >nul
)
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:run_pwsh_keys
call :init_modal_paths "keys"
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
call :exec_pwsh --keys
exit /b %ERRORLEVEL%

:run_sessions
call :init_modal_paths "sessions"
set "IDE_SESSIONS_MODAL=1"
9>"%MODAL_LOCK_FILE%" call :exec_pwsh --sessions
del /f /q "%MODAL_LOCK_FILE%" "%MODAL_PANE_FILE%" >nul 2>nul
exit /b 0

:toggle_monitor
call :find_btop
if not defined BTOP_EXE goto :run_pwsh
call :toggle_modal "monitor" "System Monitor" "5" "5" "90" "90" "--run-btop" "%BTOP_DIR%"
if errorlevel 1 goto :run_pwsh
exit /b 0

:toggle_keys
call :init_modal_paths "keys"
if not exist "%KEYS_CACHE%" call :exec_pwsh --write-keys-cache >nul 2>nul
call :toggle_modal "keys" "Keybindings" "6" "10" "88" "80" "--run-keys" ""
if errorlevel 1 goto :run_pwsh
exit /b 0

:toggle_sessions
call :toggle_modal "sessions" "IDE Fleet Switcher" "5" "8" "90" "84" "--run-sessions" ""
if errorlevel 1 goto :run_pwsh
exit /b 0

:toggle_modal
call :find_zellij
if not defined ZELLIJ_EXE exit /b 1
call :init_modal_paths "%~1"
if not exist "%MODAL_PANE_FILE%" goto :open_modal
set "ACTIVE_PANE="
set /p ACTIVE_PANE=<"%MODAL_PANE_FILE%"
del /f /q "%MODAL_LOCK_FILE%" >nul 2>nul
if not exist "%MODAL_LOCK_FILE%" (
    del /f /q "%MODAL_PANE_FILE%" >nul 2>nul
    goto :open_modal
)
if defined ACTIVE_PANE "%ZELLIJ_EXE%" action close-pane --pane-id %ACTIVE_PANE% >nul 2>nul
del /f /q "%MODAL_PANE_FILE%" "%MODAL_LOCK_FILE%" >nul 2>nul
exit /b 0

:open_modal
if not "%~8"=="" (
    "%ZELLIJ_EXE%" action new-pane --floating --close-on-exit -x %~3%% -y %~4%% --width %~5%% --height %~6%% --name "%~2" --cwd "%~8" -- cmd.exe /d /c "%~f0" %~7 >"%MODAL_PANE_FILE%" 2>nul
) else (
    "%ZELLIJ_EXE%" action new-pane --floating --close-on-exit -x %~3%% -y %~4%% --width %~5%% --height %~6%% --name "%~2" -- cmd.exe /d /c "%~f0" %~7 >"%MODAL_PANE_FILE%" 2>nul
)
exit /b 0

:fast_quit_safe
call :find_zellij
if not defined ZELLIJ_EXE goto :run_pwsh
call :find_nvim
set "SESS=%ZELLIJ_SESSION_NAME%"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>nul
set "PIPE=\\.\pipe\nvim-ide-%SESS%"
if not defined NVIM_EXE goto :fast_quit_cleanup
set "MOD_FILE=%STATE_DIR%\%SESS%.quit-check"
del /f /q "%MOD_FILE%" >nul 2>nul
"%NVIM_EXE%" --headless --server "%PIPE%" --remote-expr "luaeval('_G.try_ide_quit and _G.try_ide_quit(false) or (_G.count_ide_modified_buffers and _G.count_ide_modified_buffers() or 0)')" >"%MOD_FILE%" 2>nul
set "MOD_OUT="
if exist "%MOD_FILE%" set /p MOD_OUT=<"%MOD_FILE%"
del /f /q "%MOD_FILE%" >nul 2>nul
if not defined MOD_OUT goto :fast_quit_cleanup
if "%MOD_OUT%"=="0" goto :fast_quit_cleanup
set "ED_PANE="
if exist "%STATE_DIR%\%SESS%.pane-editor" set /p ED_PANE=<"%STATE_DIR%\%SESS%.pane-editor"
if defined ED_PANE "%ZELLIJ_EXE%" action focus-pane-id %ED_PANE% >nul 2>nul
exit /b 1

:fast_quit_force
call :find_zellij
if not defined ZELLIJ_EXE goto :run_pwsh
call :find_nvim
set "SESS=%ZELLIJ_SESSION_NAME%"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if defined NVIM_EXE "%NVIM_EXE%" --headless --server "\\.\pipe\nvim-ide-%SESS%" --remote-expr "luaeval('_G.try_ide_quit and _G.try_ide_quit(true) or 0')" >nul 2>nul

:fast_quit_cleanup
del /f /q "%STATE_DIR%\%SESS%.json" "%STATE_DIR%\%SESS%.state" "%STATE_DIR%\%SESS%.send.txt" "%STATE_DIR%\%SESS%.quit-check" "%STATE_DIR%\%SESS%.ai-active" "%STATE_DIR%\%SESS%.ai-shell" "%STATE_DIR%\%SESS%.pane-ai" "%STATE_DIR%\%SESS%.pane-editor" "%STATE_DIR%\%SESS%.pane-term" "%STATE_DIR%\launch-%SESS%-*.ps1" "%STATE_DIR%\monitor-%SESS%.*" "%STATE_DIR%\keys-%SESS%.*" "%STATE_DIR%\sessions-%SESS%.*" "%STATE_DIR%\modal-*-%SESS%.json" >nul 2>nul
"%ZELLIJ_EXE%" delete-session --force "%SESS%" >nul 2>nul
exit /b 0

:init_modal_paths
set "SESS=%ZELLIJ_SESSION_NAME%"
if not defined SESS set "SESS=default"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>nul
set "MODAL_PANE_FILE=%STATE_DIR%\%~1-%SESS%.pane"
set "MODAL_LOCK_FILE=%STATE_DIR%\%~1-%SESS%.lock"
set "KEYS_CACHE=%STATE_DIR%\keys-cheatsheet.ans"
exit /b 0

:find_btop
set "BTOP_EXE="
set "BTOP_DIR="
if defined LOCALAPPDATA (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\aristocratos.btop4win*") do (
        if exist "%%~fD\btop4win\btop4win.exe" (
            set "BTOP_EXE=%%~fD\btop4win\btop4win.exe"
            set "BTOP_DIR=%%~fD\btop4win"
            exit /b 0
        )
    )
)
if exist "%ProgramFiles%\btop4win\btop4win.exe" (
    set "BTOP_EXE=%ProgramFiles%\btop4win\btop4win.exe"
    set "BTOP_DIR=%ProgramFiles%\btop4win"
)
exit /b 0

:find_zellij
set "ZELLIJ_EXE="
if defined LOCALAPPDATA (
    for /d %%D in ("%LOCALAPPDATA%\mise\installs\zellij\*") do (
        if exist "%%~fD\zellij.exe" set "ZELLIJ_EXE=%%~fD\zellij.exe"
    )
)
if defined ZELLIJ_EXE exit /b 0
if defined LOCALAPPDATA (
    for /d %%D in ("%LOCALAPPDATA%\Microsoft\WinGet\Packages\Zellij.Zellij*") do (
        if exist "%%~fD\zellij.exe" set "ZELLIJ_EXE=%%~fD\zellij.exe"
    )
)
if defined ZELLIJ_EXE exit /b 0
set "ZELLIJ_EXE=zellij.exe"
exit /b 0

:find_nvim
set "NVIM_EXE="
if defined LOCALAPPDATA (
    for /d %%D in ("%LOCALAPPDATA%\mise\installs\neovim\*") do (
        if exist "%%~fD\bin\nvim.exe" set "NVIM_EXE=%%~fD\bin\nvim.exe"
        if exist "%%~fD\nvim-win64\bin\nvim.exe" set "NVIM_EXE=%%~fD\nvim-win64\bin\nvim.exe"
    )
)
if defined NVIM_EXE exit /b 0
if exist "%ProgramFiles%\Neovim\bin\nvim.exe" (
    set "NVIM_EXE=%ProgramFiles%\Neovim\bin\nvim.exe"
    exit /b 0
)
where nvim.exe >nul 2>nul
if %ERRORLEVEL% EQU 0 set "NVIM_EXE=nvim.exe"
exit /b 0

:run_pwsh
call :exec_pwsh %*
exit /b %ERRORLEVEL%

:exec_pwsh
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
    "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0ide.ps1" %*
    exit /b %ERRORLEVEL%
)
where pwsh >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0ide.ps1" %*
    exit /b %ERRORLEVEL%
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ide.ps1" %*
exit /b %ERRORLEVEL%
