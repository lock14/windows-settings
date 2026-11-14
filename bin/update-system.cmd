@echo off
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-system.ps1" %*
