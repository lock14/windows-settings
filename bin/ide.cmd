@echo off
setlocal

if /i "%~1"=="--run-btop" goto :run_btop
if /i "%~1"=="--run-keys" goto :run_keys
if /i "%~1"=="--toggle-monitor" if "%~2"=="" if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" if defined ZELLIJ goto :toggle_monitor
if /i "%~1"=="--toggle-keys" if "%~2"=="" if defined ZELLIJ goto :toggle_keys
if /i "%~1"=="--monitor" if "%~2"=="" if not "%IDE_FORCE_BUILTIN_MONITOR%"=="1" if not "%IDE_MONITOR_ONCE%"=="1" goto :direct_monitor
goto :run_pwsh

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
call :init_state
pushd "%BTOP_DIR%"
9>"%LOCK_FILE%" "%BTOP_EXE%"
popd
del /f /q "%LOCK_FILE%" "%PANE_FILE%" >nul 2>nul
exit /b 0

:run_pwsh_monitor
call :init_state
del /f /q "%LOCK_FILE%" "%PANE_FILE%" >nul 2>nul
call :exec_pwsh --monitor
exit /b %ERRORLEVEL%

:run_keys
call :init_keys_state
if not exist "%KEYS_CACHE%" call :exec_pwsh --write-keys-cache >nul 2>nul
if not exist "%KEYS_CACHE%" goto :run_pwsh_keys
9>"%KEYS_LOCK_FILE%" (
    type "%KEYS_CACHE%"
    pause >nul
)
del /f /q "%KEYS_LOCK_FILE%" "%KEYS_PANE_FILE%" >nul 2>nul
exit /b 0

:run_pwsh_keys
call :init_keys_state
del /f /q "%KEYS_LOCK_FILE%" "%KEYS_PANE_FILE%" >nul 2>nul
call :exec_pwsh --keys
exit /b %ERRORLEVEL%

:toggle_monitor
call :find_btop
if not defined BTOP_EXE goto :run_pwsh
call :find_zellij
if not defined ZELLIJ_EXE goto :run_pwsh
call :init_state

if not exist "%PANE_FILE%" goto :open_monitor
set "MON_PANE="
set /p MON_PANE=<"%PANE_FILE%"
del /f /q "%LOCK_FILE%" >nul 2>nul
if not exist "%LOCK_FILE%" goto :stale_monitor
if defined MON_PANE "%ZELLIJ_EXE%" action close-pane --pane-id %MON_PANE% >nul 2>nul
del /f /q "%PANE_FILE%" "%LOCK_FILE%" >nul 2>nul
exit /b 0

:stale_monitor
del /f /q "%PANE_FILE%" >nul 2>nul

:open_monitor
"%ZELLIJ_EXE%" action new-pane --floating --close-on-exit -x 5%% -y 5%% --width 90%% --height 90%% --name "System Monitor" --cwd "%BTOP_DIR%" -- cmd.exe /d /c "%~f0" --run-btop >"%PANE_FILE%" 2>nul
exit /b 0

:toggle_keys
call :find_zellij
if not defined ZELLIJ_EXE goto :run_pwsh
call :init_keys_state
if not exist "%KEYS_CACHE%" call :exec_pwsh --write-keys-cache >nul 2>nul

if not exist "%KEYS_PANE_FILE%" goto :open_keys
set "KEYS_PANE="
set /p KEYS_PANE=<"%KEYS_PANE_FILE%"
del /f /q "%KEYS_LOCK_FILE%" >nul 2>nul
if not exist "%KEYS_LOCK_FILE%" goto :stale_keys
if defined KEYS_PANE "%ZELLIJ_EXE%" action close-pane --pane-id %KEYS_PANE% >nul 2>nul
del /f /q "%KEYS_PANE_FILE%" "%KEYS_LOCK_FILE%" >nul 2>nul
exit /b 0

:stale_keys
del /f /q "%KEYS_PANE_FILE%" >nul 2>nul

:open_keys
"%ZELLIJ_EXE%" action new-pane --floating --close-on-exit -x 6%% -y 10%% --width 88%% --height 80%% --name "Keybindings" -- cmd.exe /d /c "%~f0" --run-keys >"%KEYS_PANE_FILE%" 2>nul
exit /b 0

:init_state
set "SESS=%ZELLIJ_SESSION_NAME%"
if not defined SESS set "SESS=default"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>nul
set "PANE_FILE=%STATE_DIR%\monitor-%SESS%.pane"
set "LOCK_FILE=%STATE_DIR%\monitor-%SESS%.lock"
exit /b 0

:init_keys_state
set "SESS=%ZELLIJ_SESSION_NAME%"
if not defined SESS set "SESS=default"
set "STATE_DIR=%USERPROFILE%\.cache\windows-settings\ide"
if not exist "%STATE_DIR%" mkdir "%STATE_DIR%" >nul 2>nul
set "KEYS_PANE_FILE=%STATE_DIR%\keys-%SESS%.pane"
set "KEYS_LOCK_FILE=%STATE_DIR%\keys-%SESS%.lock"
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
