@echo off
where pwsh >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0theme.ps1" %*
) else (
    powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0theme.ps1" %*
)
set "_WS_THEME_RC=%ERRORLEVEL%"
if %_WS_THEME_RC% equ 0 (
    if /i not "%~1"=="-l" if /i not "%~1"=="--list" if /i not "%~1"=="-c" if /i not "%~1"=="--current" if /i not "%~1"=="-p" if /i not "%~1"=="--preview" if /i not "%~1"=="--env" if /i not "%~1"=="--path" if /i not "%~1"=="--create" if /i not "%~1"=="--sync-assets" if /i not "%~1"=="--check-assets" if /i not "%~1"=="-n" if /i not "%~1"=="--dry-run" if /i not "%~1"=="-DryRun" if /i not "%~1"=="-h" if /i not "%~1"=="--help" if /i not "%~1"=="--plain" (
        if exist "%LOCALAPPDATA%\cmd\theme_env.cmd" call "%LOCALAPPDATA%\cmd\theme_env.cmd"
    )
)
set "_WS_THEME_RC=" & exit /b %_WS_THEME_RC%
